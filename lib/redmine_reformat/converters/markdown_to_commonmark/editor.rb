# frozen_string_literal: true

require 'commonmarker'
require_relative 'source_pos'

module RedmineReformat::Converters::MarkdownToCommonmark
  class Editor

    CMARK_PARSE_OPTS = [:STRIKETHROUGH_DOUBLE_TILDE, :FOOTNOTES]
    # SOURCEPOS actually affects also parsing
    CMARK_RENDER_OPTS = [:SOURCEPOS]
    CMARK_EXTS = [:table, :strikethrough, :autolink]

    def initialize(text)
      @text = text.encode('UTF-8')
      parse_lines(@text)
      @ranges = []
      @replacements = {}
      @document = nil
    end

    def document
      @document ||= begin
        opts = CommonMarker::Config.process_options(CMARK_PARSE_OPTS, :parse)
        opts |= CommonMarker::Config.process_options(CMARK_RENDER_OPTS, :render)
        CommonMarker::Node.parse_document(@text, @text.bytesize, opts, CMARK_EXTS)
      end
    end

    def index(lineno, columnno)
      raise IndexError, [lineno, columnno] unless line_column?(lineno, columnno)
      @offsets[lineno] + columnno - 1
    end

    def line?(lineno)
      @lines.key? lineno
    end

    def line_length(lineno)
      raise IndexError, lineno unless line? lineno
      @lines[lineno].length
    end

    def line_column?(lineno, columnno)
      return false unless line?(lineno)
      columnno >=1 && columnno <= @lines[lineno].length
    end

    def source_range(sourcepos)
      r = index(*sourcepos.startpos)..index(*sourcepos.endpos)
      raise IndexError, r if r.size.zero?
      r
    end

    def source(pos, pattern = nil, &block)
      range = case pos
      when Range
        pos
      when SourcePos
        source_range(pos)
      when CommonMarker::Node
        spos = sourcepos(pos)
        spos && source_range(spos)
      else
        raise ArgumentError, pos
      end
      return nil unless range
      range_text = @text[range]
      match = pattern && range_text.match(pattern)
      if pattern && !match
        raise RangeError, "Match #{pattern} failed for '#{range_text}'"
      end
      if block_given?
        yield range_text, range, match
      else
        range_text
      end
    end

    def line_range(lineno)
      raise IndexError, lineno unless line? lineno
      index(lineno, 1)..index(lineno, @lines[lineno].length)
    end

    def line(lineno, sanitycheck = nil, &block)
      source(line_range(lineno), sanitycheck, &block)
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
      @ranges.each do |range|
        out << @text.slice(idx...range.first)
        out << @replacements[range]
        idx = range.last
      end
      out << @text.slice(idx...@text.length)
    end

    def editcount
      @ranges.length
    end

    def sourcepos(node)
      if respond_to? "sourcepos_#{node.type}", true
        return method("sourcepos_#{node.type}").call(node)
      end
      to_sourcepos(node)
    end

    # Create sourcepos from combination of the first and last child elements
    def inner_sourcepos(node)
      edgenodes = [node.first_child, node.last_child]
      return nil unless edgenodes.all?
      sposes = edgenodes.map { |node| sourcepos(node) }
      return nil unless sposes.all?
      SourcePos.new(sposes[0].startpos, sposes[1].endpos)
    end

    private
    def line_columnb?(lineno, bcolumnno)
      return false unless line?(lineno)
      bcolumnno >= 1 && bcolumnno <= @lines[lineno].bytesize
    end

    def edit(name, range, replacement)
      range = range.first...range.last+1 unless range.exclude_end?
      raise "#{name} descending range" if range.last < range.first
      raise "#{name} outside of edited text" if range.first < 0 || range.last > @text.length
      insert_at = @ranges.bsearch_index do |r|
        self.class.rangecmp(r, range) >= 0
      end
      if insert_at
        if self.class.rangecmp(@ranges[insert_at], range) > 0
          @ranges.insert(insert_at, range)
        else
          msg = "#{name} must not overlap with other edits"
          raise RangeError.new(msg)
        end
      else
        @ranges << range
      end
      @replacements[range] = replacement
    end

    # Compares ranges `<=>`-like.
    # The ranges must be end-exclusive (`#exclude_end? == true`)
    def self.rangecmp(range1, range2)
      if range1.size.zero? && range2.size.zero?
        return range1.first <=> range2.first
      end
      return -1 if range1.last <= range2.first
      return 1 if range1.first >= range2.last
      return 0
    end

    def charpos(lineno, bcolumnno, exclude)
      raise IndexError, [lineno, bcolumnno] unless line_columnb?(lineno, bcolumnno)
      [lineno, @lines[lineno].byteslice(0, bcolumnno + exclude).length - exclude]
    end

    def to_sourcepos(node)
      nodepos = node.is_a?(CommonMarker::Node) ? node.sourcepos : node
      return nil unless nodepos
      byteposes = [
        [nodepos[:start_line], nodepos[:start_column]],
        [nodepos[:end_line], nodepos[:end_column]],
      ]
      return nil unless byteposes.flatten.all? { |p| p && p > 0 }
      charposes = byteposes.each.with_index(-1).map do |(lineno, bcolumnno), exclude|
        charpos(lineno, bcolumnno, exclude)
      end
      SourcePos.new(*charposes)
    end

    def sourcepos_code(node)
      nodepos = node.sourcepos.dup
      # code node sourcepos excludes the backticks -> extend to inner delimiter first
      nodepos[:start_column] -= 1
      # end column can even be legally zero
      nodepos[:end_column] += 1
      raise RangeError, nodepos unless nodepos.values.all? { |p| p > 0 }

      # skip eventual space padding and the delimiter
      spos = to_sourcepos(nodepos)
      delimpos1, delimpos2 = spos.dup, spos.dup
      delim1, delim2 = nil, nil

      delimpos1.endpos = delimpos1.startpos
      delimpos1.start_column = 1
      source(delimpos1, /(`+)\s*$/) do |delims, range, m|
        spos.start_column -= m[0].length - 1
        delim1 = m[1]
      end

      # fix end pos, skip eventual space padding and the delimiter
      delimpos2.startpos = delimpos2.endpos
      delimpos2.end_column = line_length(delimpos2.end_line)
      if spos.end_line > spos.start_line
        # leading spaces are not counted at multiline code end line - weird
        start_column = delimpos2.start_column
        delimpos2.start_column = 1
        source(delimpos2, /^\s*/) do |delims, range, m|
          start_column += m[0].length
          spos.end_column += m[0].length
        end
        delimpos2.start_column = start_column
      end
      source(delimpos2, /^\s*(`+)/) do |delims, range, m|
        spos.end_column += m[0].length - 1
        delim2 = m[1]
      end
      # sanity
      raise RangeError, node unless delim1 == delim2
      spos
    end

    def sourcepos_softbreak(node)
      prevnodepos = (prev = node.previous) && prev.sourcepos
      return nil unless prevnodepos && prevnodepos[:end_line] > 0
      lineno = prevnodepos[:end_line]
      linepos = SourcePos.new([lineno, 1], [lineno, line_length(lineno)])
      source(linepos, /(?:\r?\n|\r)$/) do |nl, range, m|
        linepos.start_column = linepos.end_column - m[0].length + 1
      end
      linepos
    end

    # work around sourcepos bug in strikethrough extension
    def sourcepos_strikethrough(node)
      nextnode = node.next
      nextspos = nil
      while nextnode && (nextspos = sourcepos(nextnode)).nil?
        nextnode = nextnode.next
      end
      if nextspos
        termcharpos = nextspos.startpos
      else
        parentspos = sourcepos(node.parent)
        termcharpos = parentspos && parentspos.endpos
      end
      return nil unless termcharpos
      start_bytepos = [node.sourcepos[:start_line], node.sourcepos[:start_column]]
      spos = SourcePos.new(charpos(*start_bytepos, -1), termcharpos)
      source(spos, /\A~~(?:\\.|[^\\])*?(?<!\p{Zs}|[\s\f~])~~/m) do |source, range, m|
        lines = m[0].lines
        if lines.length > 1
          raise RangeError, node unless lines[-1].bytesize == node.sourcepos[:end_column]
          spos.endpos = [spos.start_line + lines.length - 1, lines[-1].length]
        end
      end
      spos
    end

    def parse_lines(text)
      @lines = {}
      @offsets = {}
      offset = 0
      text.each_line.with_index(1) do |line, lineno|
        @lines[lineno] = line
        @offsets[lineno] = offset
        offset += line.length
      end
    end
  end
end
