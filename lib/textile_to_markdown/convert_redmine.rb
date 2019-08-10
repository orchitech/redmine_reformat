require 'textile_to_markdown/convert_string'

module TextileToMarkdown
  class ConvertRedmine

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
      Project.transaction do
        Mailer.with_deliveries(false) do
          migrate_settings
          migrate_objects
          migrate_wiki_versions
          migrate_custom_values
          Setting.text_formatting = 'markdown'
        end
      end
    end

    private

    def migrate_settings
      puts "Settings"
      SETTINGS_TO_MIGRATE.each do |setting|
        migrate_setting setting
      end
    end

    def migrate_setting(name)
      if textile = Setting.send(name)
        if md = convert(textile)
          Setting.send "#{name}=", md
        else
          puts "failed to convert setting #{name}"
        end
      end
    end

    def migrate_objects
      ITEMS_TO_MIGRATE.each do |clazz, attribute|
        name = clazz.name
        pluck_each clazz, attribute do |id, value|
          if md = convert(value)
            clazz.where(id: id).update_all(attribute => md)
          else
            puts "failed to convert #{name} #{object.id}"
          end
        end
      end
    end

    def migrate_wiki_versions
      puts "Wiki versions: #{WikiContent::Version.count}"
      WikiContent::Version.find_each do |version|
        if textile = version.text
          if md = convert(textile)
            if version.compression == 'gzip'
              md = Zlib::Deflate.deflate(md, Zlib::BEST_COMPRESSION)
            end
            version.update_column :data, md
          else
            puts "failed to convert wiki version #{version.id}"
          end
        end
      end
    end

    # convert custom values where applicable
    def migrate_custom_values
      puts "Custom values"
      CustomField.all.to_a.select{|cf|cf.text_formatting == 'full'}.each do |cf|
        print "custom field #{cf.name} (#{cf.custom_values.count} values) "
        pluck_each(cf.custom_values, :value) do |id, value|
          if md = convert(value)
            CustomValue.where(id: id).update_all(value: md)
          else
            puts "failed to convert custom_value #{custom_value.id}"
          end
        end
      end

      # journal details for formatted custom fields
      IssueCustomField.all.to_a.select{|cf|cf.text_formatting == 'full'}.each do |cf|
        scope = JournalDetail.where(property: 'cf', prop_key: cf.id)
        puts "JournalDetails (#{cf.name}): #{scope.count} records"
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
      puts "#{scope.table_name}: converting #{notnull} non-blank #{attribute} occurences of #{all} total"
      scope = scope.reorder(id: :asc).limit(BATCHSIZE)

      rows = scope.pluck(:id, attribute)
      finished = 0
      while rows.any?
        row_count = rows.size
        offset = rows.last[0]

        rows.each{|r| yield r}
        finished += row_count

        break if row_count < BATCHSIZE
        puts "#{scope.table_name}: finished #{finished} of #{notnull}"
        rows = scope.where("id > ?", offset).pluck(:id, attribute)
      end
    end


    def convert(textile)
      ConvertString.(textile) if textile
    end
  end
end
