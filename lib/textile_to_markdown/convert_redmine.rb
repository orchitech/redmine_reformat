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
      fail "db is already set to markdown" if Setting.text_formatting == 'markdown'

      Project.transaction do
        migrate_settings
        migrate_objects
        migrate_wiki_versions
        migrate_custom_values
        Setting.text_formatting = 'markdown'
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
        scope = clazz.where.not(attribute => nil)
        puts "#{name} (#{clazz.count} records, #{scope.count} with #{attribute} set})"
        scope.find_each do |object|
          if textile = object.send(attribute)
            if md = convert(textile)
              object.update_column attribute, md
            else
              puts "failed to convert #{name} #{object.id}"
            end
          end
        end
      end
    end

    def migrate_wiki_versions
      puts "Wiki versions"
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
        cf.custom_values.where.not(value: nil).find_each do |custom_value|
          if textile = custom_value.value
            if md = convert(textile)
              custom_value.update_column :value, md
            else
              puts "failed to convert custom_value #{custom_value.id}"
            end
          end
        end
      end

      # journal details for formatted custom fields
      IssueCustomField.all.to_a.select{|cf|cf.text_formatting == 'full'}.each do |cf|
        JournalDetail.where(property: 'cf', prop_key: cf.id).find_each do |detail|
          if md = convert(detail.value)
            detail.update_column :value, md
          end
          if md = convert(detail.old_value)
            detail.update_column :old_value, md
          end
        end
      end
    end


    def convert(textile)
      ConvertString.(textile) if textile
    end
  end
end
