# frozen_string_literal: true

module RedmineReformat::Converters::Log
  class Converter
    def initialize(opts = {})
      @text_re = Regexp.new(opts[:text_re] || '\\A')
      @reference_re = Regexp.new(opts[:reference_re] || '')
      @print = (opts[:print] || 'none').to_sym
    end

    def convert(text, ctx = nil)
      reference = ctx && ctx.ref || ''
      if reference =~ @reference_re && text =~ @text_re
        ptext = nil
        case @print
        when :first
          ptext = text[@text_re]
        when :all
          ptext = text.scan(@text_re).join("\n")
        end
        STDOUT.puts "[#{reference}] Log#{': ' if ptext}#{ptext}"
      end
      text
    end
  end
end
