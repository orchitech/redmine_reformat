# frozen_string_literal: true

module RedmineReformat
  module Converters
    class SourcePos
      include Enumerable

      protected
      attr_reader :boundaries

      public
      def initialize(startpos = nil, endpos = nil)
        @boundaries = [[nil, nil], [nil, nil]]
        self.startpos = startpos
        self.endpos = endpos
      end

      def initialize_copy(orig)
        super
        initialize(*orig.boundaries)
      end

      def [](key)
        @boundaries[key]
      end

      def each(&block)
        @boundaries.each do |charpos|
          yield charpos
        end
      end

      def startpos
        @boundaries[0]
      end

      def startpos=(charpos)
        @boundaries[0] = charpos && charpos[0..1] || [nil, nil]
      end

      def endpos
        @boundaries[1]
      end

      def endpos=(charpos)
        @boundaries[1] = charpos && charpos[0..1] || [nil, nil]
      end

      def start_line
        @boundaries[0][0]
      end

      def start_line=(line)
        @boundaries[0][0] = line
      end

      def start_column
        @boundaries[0][1]
      end

      def start_column=(column)
        @boundaries[0][1] = column
      end

      def end_line
        @boundaries[1][0]
      end

      def end_line=(line)
        @boundaries[1][0] = line
      end

      def end_column
        @boundaries[1][1]
      end

      def end_column=(column)
        @boundaries[1][1] = column
      end

      def ==(o)
        o.class == self.class && o.boundaries == self.boundaries
      end

      def eql?(o)
        o == self
      end

      def hash
        self.boundaries.hash
      end

      def to_s
        @boundaries.to_s
      end

      def inspect
        "#{self.class.name}#{@boundaries.inspect}"
      end
    end
  end
end
