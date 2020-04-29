# frozen_string_literal: true

module RedmineReformat::Converters::RedmineFormatter
  class Converter
    include RedmineReformat::Helpers

    def initialize(opts = {})
      @opts = {}
      # macros = keep | encode
      @opts[:macros] = (opts[:macros] || 'keep').to_sym
    end

    # returns HTML obtained from internal Redmine's formatter
    def convert(text, ctx = nil)
      reference = ctx && ctx.ref
      begin
        with_application_helper(@opts, ctx) do |helper|
          textilizable_opts = {
            only_path: true,
            headings: false,
            project: ctx.project,
          }
          helper.textilizable(text, textilizable_opts)
        end
      rescue Exception => e
        STDERR.puts "failed textilizable() '#{reference}' due to #{e.message} - #{e.class}"
        STDERR.puts "Text was:"
        STDERR.puts text
        raise
      end
    end
  end
end
