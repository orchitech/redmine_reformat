module RedmineReformat
  module Converters
    class ConfiguredConverter

      def initialize(cfg)
        @project_ids = if cfg[:projects]
          Array(cfg[:projects]).collect do |p|
            find_project_id(p)
          end
        end
        @items = Array(cfg[:items]) if cfg[:items]
        @from_formatting = Array(cfg[:from_formatting]) if cfg[:from_formatting]
        @to_formatting = Array(cfg[:to_formatting]) if cfg[:to_formatting]
        @converter_chain = ConverterChain.new(cfg[:converters], cfg) if cfg[:converters]
      end

      def matches?(ctx)
        if @project_ids
          return false unless @project_ids.include?(ctx.project_id)
        end
        if @items
          return false unless @items.include?(ctx.item)
        end
        if @from_formatting
          return false unless @from_formatting.include?(ctx.from_formatting)
        end
        if @to_formatting
          return false unless @to_formatting.include?(ctx.to_formatting)
        end
        true
      end

      def converting?
        !!@converter_chain
      end

      def convert(text, ctx)
        return nil unless converting?
        @converter_chain.convert(text, ctx)
      end

      private
      def find_project_id(project)
        p = Project.find(project)
        raise "Project '#{project}' not found" if p.nil?
        p.id
      end
    end
  end
end
