module RedmineReformat
  module Converters
    class ConfiguredConverters
      def initialize(cfgs)
        @configured_converters = cfgs.collect do |cfg|
          ConfiguredConverter.new(cfg)
        end
      end

      def convert(text, ctx)
        @configured_converters.each do |cc|
          return cc.convert(text, ctx) if cc.matches?(ctx)
        end
        raise "No converter found for #{ctx}"
      end
    end
  end
end
