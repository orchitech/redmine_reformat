require 'textile_to_markdown/convert_string'
require 'parallel'

module TextileToMarkdown
  class ConvertRedmine

    # Experimental parallel processing - set to a number > 1 to check it out.
    # Please note that transaction won't work when parallel processing is on.
    PARALLEL = 12

    ITEMS_TO_MIGRATE = {
      Comment => :comments,
      Document => :description,
      Issue => :description,
      Journal => :notes,
      Message => :content,
      News => :description,
      Project => :description,
      WikiContent => :text,
    }

    # Planio specific
    if defined?(RedmineCrm)
      ITEMS_TO_MIGRATE[CrmTemplate] = :content
    end

    # column has been renamed some time after 3.4
    if Comment.new.respond_to?(:content)
      ITEMS_TO_MIGRATE[Comment] = :content
    end

    SETTINGS_TO_MIGRATE = %w(
      welcome_text
      emails_footer
      emails_header
    )

    def self.call
      new.call
    end

    def call
      decide_transaction do
        Mailer.with_deliveries(false) do
          migrate_settings
          migrate_objects
          migrate_issue_description_journals
          migrate_wiki_versions
          migrate_custom_values
          Setting.text_formatting = 'markdown'
        end
      end
    end

    private

    def decide_transaction(&block)
      if PARALLEL > 1
        # no transaction
        block.call
      else
        Project.transaction(&block)
      end
    end

    def migrate_settings
      STDERR.puts "Settings"
      SETTINGS_TO_MIGRATE.each do |setting|
        migrate_setting setting
      end
    end

    def migrate_setting(name)
      if textile = Setting.send(name)
        if md = convert(textile, "Setting\##{name}")
          Setting.send "#{name}=", md
        else
          STDERR.puts "failed to convert setting #{name}"
        end
      end
    end

    def migrate_objects
      ITEMS_TO_MIGRATE.each do |clazz, attribute|
        name = clazz.name
        pluck_each clazz, attribute do |id, value|
          if md = convert(value, "#{name}\##{id}.#{attribute}")
            clazz.where(id: id).update_all(attribute => md)
          else
            STDERR.puts "failed to convert #{name}\##{id}"
          end
        end
      end
    end

    def migrate_issue_description_journals
      scope = JournalDetail.joins(:journal).joins('LEFT JOIN issues on issues.id=journals.journalized_id').where(
        property: 'attr', prop_key: 'description', journals: { journalized_type: 'Issue' }
      )
      STDERR.puts "JournalDetails (Issue.description): #{scope.count} records"
      rows = scope.pluck(:id, :value, :old_value, :journal_id, 'issues.id')
      process(rows) do |id, value, old_value, journal_id, issue_id|
        ref = "JournalDetails\##{id}: /issues/#{issue_id}\#change-#{journal_id}"
        if value and md = convert(value, ref)
          value = md
        end
        if old_value and md = convert(old_value, ref)
          old_value = md
        end
        JournalDetail.where(id: id).update_all(
          value: value, old_value: old_value
        )
      end
    end

    def migrate_wiki_versions
      all = WikiContent::Version.count
      STDERR.puts "Wiki versions: converting #{all} historic content revisions"
      finished = 0
      r = WikiContent::Version.includes(:page => { :wiki => :project }).find_each
      process(r) do |version|
        ref = "WikiContent::Version\##{version.id}: "\
          "/projects/#{version.project.identifier}"\
          "/wiki/#{version.page.title}/#{version.version}"
        if textile = version.text
          if md = convert(textile, ref)
            if version.compression == 'gzip'
              md = Zlib::Deflate.deflate(md, Zlib::BEST_COMPRESSION)
            end
            version.update_column :data, md
          else
            STDERR.puts "failed to convert #{ref}"
          end
        end
        finished += 1
        if finished % BATCHSIZE == 0 || finished == all
          STDERR.puts "Wiki versions: finished #{finished} of #{all}"
        end
      end
    end

    # convert custom values where applicable
    def migrate_custom_values
      STDERR.puts "Custom values"
      CustomField.all.to_a.select{|cf|cf.text_formatting == 'full'}.each do |cf|
        print "custom field #{cf.name} (#{cf.custom_values.count} values) "
        pluck_each(cf.custom_values, :value) do |id, value|
          if md = convert(value)
            CustomValue.where(id: id).update_all(value: md)
          else
            STDERR.puts "failed to convert custom_value #{custom_value.id}"
          end
        end
      end

      # journal details for formatted custom fields
      IssueCustomField.all.to_a.select{|cf|cf.text_formatting == 'full'}.each do |cf|
        scope = JournalDetail.where(property: 'cf', prop_key: cf.id)
        STDERR.puts "JournalDetails (#{cf.name}): #{scope.count} records"
        scope.pluck(:id, :value, :old_value).each do |id, value, old_value|
          if md = convert(value)
            value = md
          end
          if md = convert(old_value)
            old_value = md
          end
          JournalDetail.where(id: id).update_all(
            value: value, old_value: old_value
          )
        end
      end
    end


    BATCHSIZE = 1000
    def pluck_each(scope, attribute, &block)
      all = scope.count
      scope = scope.where.not(attribute => [nil, ''])
      notnull = scope.count
      STDERR.puts "#{scope.table_name}: converting #{notnull} non-blank #{attribute} occurences of #{all} total"
      scope = scope.reorder(id: :asc).limit(BATCHSIZE)

      rows = scope.pluck(:id, attribute)
      finished = 0
      while rows.any?
        row_count = rows.size
        offset = rows.last[0]

        process(rows) {|r| yield r}
        finished += row_count
        STDERR.puts "#{scope.table_name}: finished #{finished} of #{notnull}"
        raise "test end" if finished > 3000

        break if row_count < BATCHSIZE
        rows = scope.where("id > ?", offset).pluck(:id, attribute)
      end
    end

    def process(rows, &block)
      if PARALLEL > 1
        Parallel.each(rows, in_threads: PARALLEL, &block)
      else
        rows.each &block
      end
    end

    def convert(textile, reference = nil)
      md = textile
      md = ConvertString.(md, reference) if md
      # browsers use \r\n, so restore it to avoid EOL differences
      md = md.gsub(/\r?\n/m, "\r\n") if md
      md
    end
  end
end
