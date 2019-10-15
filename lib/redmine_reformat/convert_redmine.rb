require 'textile_to_markdown/convert_string'
require 'ostruct'
require 'action_view'

require 'textile_to_markdown/application_helper_patch'
require 'net/http/persistent'

module RedmineReformat

  class Spec
    def initialize(clazz, cols, subset = nil, args = {})
      @clazz = clazz
      @cols = Array(cols)
      @item = "#{clazz.name}#{'[' + subset + ']' if subset}"
      @joins = args[:joins]
      @where = Array(args[:where])
      @project_id_col = args[:project_id] || 'NULL'
      @ctxcols = Array(args[:ctxcols])
      @mkurl = args[:mkurl] || ->(ctx) { nil }
    end

    BATCHSIZE = 100
    def pluck_each(exn, &block)
      scope = @clazz
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
          ctx = OpenStruct.new({
            clazz: @clazz,
            item: @item,
            id: id,
            project_id: project_id,
            vals: ctxvals,
            ref: "#{@item}\##{id}"
          })
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

    #include ActionView::Helpers::SanitizeHelper
    include ERB::Util
    include ActionView::Helpers::TextHelper
    include ActionView::Helpers::SanitizeHelper
    include ActionView::Helpers::UrlHelper
    include Rails.application.routes.url_helpers
    include ApplicationHelper

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
      @dryrun = false
      #ActiveRecord::Base.logger = Logger.new(STDOUT)

      Project.transaction do
        Mailer.with_deliveries(false) do
          @exn.start
          @original_text_formatting = Setting.text_formatting
          migrate_settings if @exn.master?
          migrate_objects
          migrate_wiki_versions
          migrate_custom_values
          unless @exn.finish(true)
            raise ActiveRecord::Rollback
          end
          @exn.tx_wait
        end
      end
      @exn.tx_done
      exit 0
      @http = Net::HTTP::Persistent.new name: 'redmine_reformat'
      @http.retry_change_requests = true
      User.current = nil
      unless ApplicationHelper.included_modules.include? TextileToMarkdown::ApplicationHelperPatch
        ApplicationHelper.send(:include, TextileToMarkdown::ApplicationHelperPatch)
      end
      #puts Setting.text_formatting
      #uts textilizable("\n\nh1. Hey\n\n{{toc}}\n\n!myimg.png! #7194\n")
      #puts textilizable("\n\n[[orchitech:WikiLink]] #7194\n", {:only_path => true})
      #exit 0
      decide_transaction do
        Mailer.with_deliveries(false) do
          @original_text_formatting = Setting.text_formatting
          migrate_settings
          migrate_objects
          migrate_wiki_versions
          migrate_custom_values
          Setting.text_formatting = 'markdown' unless @dryrun
        end
      end
      @http.shutdown
    end

    private
    def migrate_settings
      STDERR.puts "Settings"
      SETTINGS_TO_MIGRATE.each do |setting|
        migrate_setting setting
      end
    end

    def migrate_setting(name)
      ctx = {:item => 'Settings', :ref => "Setting\##{name}"}
      if textile = Setting.send(name)
        if md = convert(textile, ctx)
          Setting.send "#{name}=", md unless @dryrun
        else
          STDERR.puts "failed to convert setting #{name}"
        end
      end
    end

    def migrate_objects
      ITEMS_TO_MIGRATE.each do |spec|
        migrate_spec spec
      end
    end

    def migrate_wiki_versions
      item = 'wiki_version'
      ctx = {:item => item}

      scope = @exn.scope(item, WikiContent::Version)
      tot = @exn.total(item)
      mytot = @exn.mytotal(item)

      STDERR.puts "Wiki versions: converting #{mytot}/#{tot} historic content revisions"

      finished = 0
      scope.includes(:page => { :wiki => :project }).find_each do |version|
        ctx[:ref] = "WikiContent::Version\##{version.id}: "\
          "/projects/#{version.project.identifier}"\
          "/wiki/#{version.page.title}/#{version.version}"
        ctx[:project_id] = version.project.id
        if textile = version.text
          if md = convert(textile, ctx)
            if version.compression == 'gzip'
              md = Zlib::Deflate.deflate(md, Zlib::BEST_COMPRESSION)
            end
            version.update_column :data, md unless @dryrun
          else
            STDERR.puts "failed to convert #{ref}"
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
      CustomField.all.to_a.select{|cf|cf.text_formatting == 'full'}.each do |cf|
        spec = Spec.new(CustomValue, :value, cf.name, {where: [custom_field_id: cf.id]})
        migrate_spec spec
      end 

      # journal details for formatted custom fields
      IssueCustomField.all.to_a.select{|cf|cf.text_formatting == 'full'}.each do |cf|
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
        updates = vals.map do |col, value|
          converted = convert(value, ctx) if value
          if value and not converted
            STDERR.puts "failed to convert #{ctx.ref}"
            next
          end
          [col, converted]
        end.compact
        unless @dryrun or updates.empty?
          ctx.clazz.where(id: ctx.id).update_all(Hash[updates]) unless @dryrun
        end
      end
    end

    JWM_ITEMS = [
      'Issue',
      'Journal',
      'JournalDetail_Issues_description',
    ]
    JWM_PROJECT_IDS = [
    ]
    def convert(text, ctx)
      return text + 'END'
      if @original_text_formatting == 'textile'
        if JWM_ITEMS.include?(ctx[:item]) && JWM_PROJECT_IDS.include?(ctx[:project_id])
          md = convertJwmToHtmlToMd(text, ctx[:ref])
        else
          md = convertTextileToMd(text, ctx[:ref])
        end
      else
        md = convertMdToHtmlAndBack(text, ctx[:ref])
      end
      # browsers use \r\n, so restore it to avoid EOL differences
      md.gsub(/\r?\n/m, "\r\n") if md
    end

    def convertTextileToMd(textile, reference)
      ConvertString.(textile, reference)
    end

    TURNDOWN_URI = URI('http://localhost:4000')
    JWM_TO_HTML_URI = URI('http://192.168.1.191:4001')
    def convertMdToHtmlAndBack(text, reference)
      md = html = nil
      begin
        html = textilizable(text, {:only_path => true, :headings => false})
        # return unescapeHtml(data)
        # .replace(/\$(.)/g, '$1')
        # .replace(/<legend>.+<\/legend>/g, '')
        # .replace(/<a name=.+?><\/a>/g, '')
        # .replace(/<a href="#(?!note-\d+).+?>.+<\/a>/g, '');
        md = convertUsingWebService(TURNDOWN_URI, html)
        return md
      rescue Exception => e
        STDERR.puts "failed textilizable() + turndown for ref '#{reference}' due to #{e.message} - #{e.class}"
        STDERR.puts "Text was:"
        STDERR.puts text
        STDERR.puts "Intermediate HTML was:"
        STDERR.puts html
        raise
      end
    end

    def convertJwmToHtmlToMd(text, reference)
      md = html = nil
      begin
        html = convertUsingWebService(JWM_TO_HTML_URI, text)
        #STDERR.puts "JWM done in #{Time.now - start}"
        #start = Time.now
        md = convertUsingWebService(TURNDOWN_URI, html)
        #STDERR.puts "Turndown done in #{Time.now - start}"
        return md
      rescue Exception => e
        STDERR.puts "failed JWM2HTML + turndown for ref '#{reference}' due to #{e.message} - #{e.class}"
        STDERR.puts "Text was:"
        STDERR.puts text
        STDERR.puts "Intermediate HTML was:"
        STDERR.puts html
        raise
      end
    end

    def convertUsingWebService(uri, input)
      req = Net::HTTP::Post.new(uri)
      req['Content-Type'] = 'text/html; charset=UTF-8'
      req.body = input
      res = @http.request uri, req
      unless res.code == '200'
        raise "Turnddown API request failed. [code=#{res.code}, msg=#{res.msg}]"
      end
      return res.body
    end
  end
end
