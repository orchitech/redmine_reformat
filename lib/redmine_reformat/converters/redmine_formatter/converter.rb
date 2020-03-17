# frozen_string_literal: true

module RedmineReformat::Converters::RedmineFormatter
  class Converter
    def initialize(opts = {})
      @opts = {}
      # macros = keep | encode
      @opts[:macros] = (opts[:macros] || 'keep').to_sym
    end

    # returns HTML obtained from internal Redmine's formatter
    def convert(text, ctx = nil)
      reference = ctx && ctx.ref
      begin
        helper = ReformatApplicationHelper.instance
        # no need to be be thread-safe
        helper.send("reformat_opts=", @opts)
        output = helper.textilizable(text, {:only_path => true, :headings => false})
        helper.send("reformat_opts=", nil)
        output
      rescue Exception => e
        STDERR.puts "failed textilizable() '#{reference}' due to #{e.message} - #{e.class}"
        STDERR.puts "Text was:"
        STDERR.puts text
        raise
      end
    end
  end
end
