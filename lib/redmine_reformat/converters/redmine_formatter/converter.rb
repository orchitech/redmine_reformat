# frozen_string_literal: true

module RedmineReformat::Converters::RedmineFormatter
  class Converter
    # returns HTML obtained from internal Redmine's formatter
    def convert(text, reference = nil)
      begin
        helper = ReformatApplicationHelper.instance
        helper.textilizable(text, {:only_path => true, :headings => false})
      rescue Exception => e
        STDERR.puts "failed textilizable() '#{reference}' due to #{e.message} - #{e.class}"
        STDERR.puts "Text was:"
        STDERR.puts text
        raise
      end
    end
  end
end
