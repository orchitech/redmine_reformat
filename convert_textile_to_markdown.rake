require 'textile_to_markdown/convert_string'

task :convert_textile_to_markdown => :environment do
  convert = {
    Comment =>  [:comments],
    WikiContent => [:text],
    Issue =>  [:description],
    Message => [:content],
    News => [:description],
    Document => [:description],
    Project => [:description],
    Journal => [:notes],
  }

  count = 0
  print 'WelcomeText'
  textile = Setting.welcome_text
  if textile != nil
    markdown = TextileToMarkdown::ConvertString.(textile)
    Setting.welcome_text = markdown
  end
  count += 1
  print '.'
  puts

  convert.each do |the_class, attributes|
    print the_class.name
    the_class.find_each do |model|
      attributes.each do |attribute|

        textile = model[attribute]
        if textile != nil
          begin
            markdown = TextileToMarkdown::ConvertString.(textile)
            model.update_column(attribute, markdown)
          rescue => err
            puts "Failed to convert #{model.id}: #{err}"
          end
        end
      end
      count += 1
      print '.'
    end
    puts
  end
  puts "Done converting #{count} models"
end


