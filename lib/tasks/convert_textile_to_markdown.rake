task convert_textile_to_markdown: :environment do
  TextileToMarkdown::ConvertRedmine.call
end

