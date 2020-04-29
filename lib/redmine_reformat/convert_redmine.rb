# frozen_string_literal: true

module RedmineReformat
  class Spec
    def initialize(klass, cols, subset = nil, args = {})
      @klass = klass
      @cols = Array(cols)
      @item = "#{klass.name}#{'[' + subset + ']' if subset}"
      @joins = args[:joins]
      @where = Array(args[:where])
      @project_id_col = args[:project_id] || 'NULL'
      @ctxcols = Array(args[:ctxcols])
      @mkurl = args[:mkurl] || ->(ctx) { nil }
    end

    BATCHSIZE = 100
    def pluck_each(exn, &block)
      scope = @klass
      id_col = "#{scope.table_name}.id"

      scope = scope.joins(@joins) if @joins
      @where.each{|w| scope = scope.where(w)}

      all = scope.count
      scope = scope.where(@cols.map{|col| "#{col} <> ''"}.join(' OR '))

      scope = exn.scope(@item, scope)
      tot = exn.total(@item)
      mytot = exn.mytotal(@item)
      STDERR.puts "#{@item}: converting #{mytot}/#{tot} non-blank #{@cols} occurences of #{all} total"

      scope = scope.limit(BATCHSIZE)
      pluck_cols = [:id, @project_id_col].concat(@ctxcols).concat(@cols)

      rows = scope.pluck(*pluck_cols)
      while rows.any?
        row_count = rows.size
        offset = rows.last[0]
        rows.each do |r|
          id = r.shift
          project_id = r.shift
          ctxvals = Hash[@ctxcols.zip(r.shift(@ctxcols.length))]
          ctx = Context.new(
            klass: @klass,
            item: @item,
            id: id,
            project_id: project_id,
            vals: ctxvals,
            ref: +"#{@item}\##{id}"
          )
          url = @mkurl.call(ctx)
          ctx.ref << ": #{url}" if url
          vals = Hash[@cols.zip(r)]
          yield ctx, vals
        end

        exn.progress(@item, row_count)
        break if row_count < BATCHSIZE
        rows = scope.where("#{id_col} > ?", offset).pluck(*pluck_cols)
      end
    end
  end

  class ConvertRedmine

    BATCHSIZE = 100 # xxx remove

    COMMENT_CONTENT_COL = if Comment.new.respond_to?(:content) then :content else :comments end

    ITEMS_TO_MIGRATE = [
      Spec.new(Comment, COMMENT_CONTENT_COL),
      Spec.new(Document, :description),
      Spec.new(Issue, :description, nil, {project_id: :project_id, mkurl: ->(ctx) { "/issues/#{ctx.id}" }}),
      Spec.new(JournalDetail, [:value, :old_value], 'Issue.description', {
        joins: [:journal, 'LEFT JOIN issues on issues.id = journals.journalized_id'],
        where: [property: :attr, prop_key: :description, journals: {journalized_type: :Issue}],
        project_id: 'issues.project_id',
        ctxcols: [:journal_id, 'issues.id'],
        mkurl: ->(ctx) { "/issues/#{ctx.vals['issues.id']}\#change-#{ctx.vals[:journal_id]}" }
      }),
      Spec.new(Journal, :notes, nil, {
        joins: "LEFT JOIN issues ON issues.id=journals.journalized_id AND journalized_type = 'Issue'",
        project_id: 'issues.project_id',
        ctxcols: 'issues.id',
        mkurl: ->(ctx) { "/issues/#{ctx.vals['issues.id']}\#change-#{ctx.id}" }
      }),
      Spec.new(Message, :content),
      Spec.new(News, :description),
      Spec.new(Project, :description, nil, {project_id: :id}),
      Spec.new(WikiContent, :text, nil, {
        joins: {page: {wiki: :project}},
        project_id: 'wikis.project_id',
        ctxcols: ['projects.identifier', 'wiki_pages.title'],
        mkurl: ->(ctx) { "/projects/#{ctx.vals['projects.identifier']}/wiki/#{ctx.vals['wiki_pages.title']}" }
      })
    ]

    # Planio specific
    if defined?(RedmineCrm)
      ITEMS_TO_MIGRATE << Spec.new(CrmTemplate, :content)
    end

    SETTINGS_TO_MIGRATE = %w(
      welcome_text
      emails_footer
      emails_header
    )

    def self.call(exn)
      new.call(exn)
    end

    def call(exn)
      @exn = exn
      Project.transaction do
        Mailer.with_deliveries(false) do
          Context.with_cached_projects do
            do_migrate
          end
        end
      end
      @exn.tx_done
    end

    private
    def do_migrate
      @from_formatting = Setting.text_formatting
      @to_formatting = @exn.to_formatting || @from_formatting
      @exn.start
      migrate_settings if @exn.master?
      migrate_objects
      migrate_wiki_versions
      migrate_custom_values
      Setting.text_formatting = @to_formatting if @exn.master? && !@exn.dryrun
      unless @exn.finish(true)
        raise ActiveRecord::Rollback
      end
      @exn.tx_wait
    end

    def migrate_settings
      STDERR.puts "Settings"
      SETTINGS_TO_MIGRATE.each do |setting|
        migrate_setting setting
      end
    end

    def migrate_setting(name)
      ctx = Context.new(
        item: 'Settings',
        from_formatting: @from_formatting,
        to_formatting: @to_formatting,
        ref: "Setting\##{name}"
      )
      if textile = Setting.send(name)
        md = convert(textile, ctx)
        Setting.send "#{name}=", md if !@exn.dryrun && md
      end
    end

    def migrate_objects
      ITEMS_TO_MIGRATE.each do |spec|
        migrate_spec spec
      end
    end

    def migrate_wiki_versions
      item = 'wiki_version'
      ctx = Context.new(
        :item => item,
        :from_formatting => @from_formatting,
        :to_formatting => @to_formatting
      )

      scope = @exn.scope(item, WikiContent::Version)
      tot = @exn.total(item)
      mytot = @exn.mytotal(item)

      STDERR.puts "Wiki versions: converting #{mytot}/#{tot} historic content revisions"

      finished = 0
      scope.includes(:page => { :wiki => :project }).find_each do |version|
        ctx.ref = "WikiContent::Version\##{version.id}: "\
          "/projects/#{version.project.identifier}"\
          "/wiki/#{version.page.title}/#{version.version}"
        ctx.project_id = version.project.id
        if textile = version.text
          if md = convert(textile, ctx)
            if version.compression == 'gzip'
              md = Zlib::Deflate.deflate(md, Zlib::BEST_COMPRESSION)
            end
            version.update_column(:data, md) unless @exn.dryrun
          end
        end
        finished += 1
        if (finished % BATCHSIZE) == 0 || finished == mytot
          inc = (finished % BATCHSIZE) # xxx rewrite
          inc = BATCHSIZE if inc == 0
          @exn.progress(item, inc) # xxx rewrite
        end
      end
    end

    # convert custom values where applicable
    def migrate_custom_values
      # formatted custom fields
      CustomField.all.to_a.select{|cf| cf.text_formatting == 'full'}.each do |cf|
        spec = Spec.new(CustomValue, :value, cf.name, {where: [custom_field_id: cf.id]})
        migrate_spec spec
      end

      # journal details for formatted custom fields
      IssueCustomField.all.to_a.select{|cf| cf.text_formatting == 'full'}.each do |cf|
        spec = Spec.new(JournalDetail, [:value, :old_value], "cf_#{cf.name}", {
          joins: [:journal, 'LEFT JOIN issues on issues.id = journals.journalized_id'],
          where: [property: :cf, prop_key: cf.id, journals: {journalized_type: :Issue}],
          project_id: 'issues.project_id',
          ctxcols: [:journal_id, 'issues.id'],
          mkurl: ->(ctx) { "/issues/#{ctx.vals['issues.id']}\#change-#{ctx.vals[:journal_id]}" }
        });
        migrate_spec spec
      end
    end

    def migrate_spec(spec)
      spec.pluck_each(@exn) do |ctx, vals|
        ctx.from_formatting = @from_formatting
        ctx.to_formatting = @to_formatting
        updates = vals.map do |col, value|
          converted = convert(value, ctx) if value
          next if converted.nil?
          [col, converted]
        end.compact
        if !@exn.dryrun && !updates.empty?
          ctx.klass.where(id: ctx.id).update_all(Hash[updates])
        end
      end
    end

    def convert(text, ctx)
      @exn.converter.convert(text, ctx)
    end
  end
end
