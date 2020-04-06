# frozen_string_literal: true

module RedmineReformat
  module Converters
    module MarkdownToCommonmark
      class Editor
        def initialize(text)
          @text = text
          @line_offsets = self.class.line_offsets text
          @positions = []
          @replacements = {}
        end

        def index(lineno, columnno)
          raise IndexError, [lineno, columnno] unless line_column?(lineno, columnno)
          @line_offsets[lineno - 1] + columnno - 1
        end

        def line_length(lineno)
          raise IndexError, lineno unless line?(lineno)
          index1 = @line_offsets[lineno - 1]
          index2 = lineno < @line_offsets.length ? @line_offsets[lineno] : @text.length
          index2 - index1
        end

        def line?(lineno)
          lineno >= 1 && lineno <= @line_offsets.length
        end

        def line_column?(lineno, columnno)
          return false unless line?(lineno)
          columnno >=1 && columnno <= line_length(lineno)
        end

        def start_index(sourcepos)
          index(sourcepos[:start_line], sourcepos[:start_column])
        end

        def end_index(sourcepos)
          index(sourcepos[:end_line], sourcepos[:end_column])
        end

        def source_range(sourcepos)
          r = start_index(sourcepos)..end_index(sourcepos)
          raise IndexError, r if r.size.zero?
          r
        end

        def source(sourcepos, &block)
          range = if sourcepos.is_a? Range then sourcepos else source_range(sourcepos) end
          range_text = @text[range]
          if block_given?
            yield range_text, range
          else
            range_text
          end
        end

        def line_range(lineno)
          index(lineno, 1)..index(lineno, line_length(lineno))
        end

        def line(lineno, &block)
          source(line_range(lineno), &block)
        end

        def replace(range, replacement, ctx = nil)
          name = "Replace (#{range}#{" in #{ctx}" if ctx})"
          range = range..range unless range.instance_of? Range
          raise RangeError.new("#{name} cannot be empty") if range.size.zero?
          range = (range.min + ctx.first)..(range.max + ctx.first) if ctx
          edit(name, range, replacement)
        end

        def insert(index, insertion, ctx = nil)
          name = "Replace (#{index}#{" in #{ctx}" if ctx})"
          index += ctx.first if ctx
          range = index...index
          if @replacements.key? range
            @replacements[range] << insertion
          else
            edit(name, range, insertion)
          end
        end

        def apply
          out = String.new(capacity: @text.bytesize + @text.bytesize << 4 + 16)
          idx = 0
          @positions.each do |range|
            out << @text.slice(idx...range.first)
            out << @replacements[range]
            idx = range.last
          end
          out << @text.slice(idx...@text.length)
        end

        def editcount
          @positions.length
        end

        private
        def edit(name, range, replacement)
          range = range.first...range.last+1 unless range.exclude_end?
          raise "#{name} descending range" if range.last < range.first
          raise "#{name} outside of edited text" if range.first < 0 || range.last > @text.length
          insert_at = @positions.bsearch_index do |pos|
            self.class.poscmp(pos, range) >= 0
          end
          if insert_at
            if self.class.poscmp(@positions[insert_at], range) > 0
              @positions.insert(insert_at, range)
            else
              msg = "#{name} must not overlap with other edits"
              raise RangeError.new(msg)
            end
          else
            @positions << range
          end
          @replacements[range] = replacement
        end

        # Compares positions `<=>`-like.
        # The ranges must be end-exclusive (`#exclude_end? == true`)
        def self.poscmp(range1, range2)
          if range1.size.zero? && range2.size.zero?
            return range1.first <=> range2.first
          end
          return -1 if range1.last <= range2.first
          return 1 if range1.first >= range2.last
          return 0
        end

        def self.line_offsets(text)
          offsets = []
          offset = 0
          text.each_line.with_index do |line, lineidx|
            offsets << offset
            offset += line.length
          end
          offsets
        end
      end
    end
  end
end
