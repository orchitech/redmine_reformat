module RedmineReformat
  module Converters
    class ConverterChain
      attr_accessor :force_crlf
      attr_accessor :match_trailing_nl

      def initialize(defs)
        normdefs = Array(defs)
        normdefs = [defs] if normdefs.any? && !defs.first.is_a?(Array)
        @converters = normdefs.collect do |d|
          self.class.create_converter(*d)
        end
        @force_crlf = true
        @match_trailing_nl = true
      end

      def convert(text, ctx = nil)
        converted = text
        @converters.each do |c|
          converted = c.convert(converted, ctx) if converted
        end
        converted = convert_to_crlf(converted) if converted && @force_crlf
        converted = restore_trailing_nl(text, converted) if converted && @match_trailing_nl
        converted
      end

      private
      def convert_to_crlf(text)
        text.gsub(/\r?\n/, "\r\n")
      end

      def restore_trailing_nl(original, converted)
        otrail, ctrail = [original, converted].collect do |text|
          trail = text.match(/(\r?\n)*$/)[0]
          nls = trail.count("\n")
          [trail, nls]
        end
        return converted if otrail[1] == ctrail[1]
        cstripped = converted.sub(/(\r?\n)+$/, '')
        trail = if @force_crlf then "\r\n" * otrail[1] else otrail[0] end
        "#{cstripped}#{trail}"
      end

      def self.create_converter(name, *args)
        className = "RedmineReformat::Converters::#{name}::Converter"
        klass = className.constantize
        klass.new(*args)
      end
    end
  end
end
