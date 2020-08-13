# frozen_string_literal: true

require_relative '../gfm_editor'
require_relative '../macros'

module RedmineReformat::Converters::CommonmarkListFormatter
  class Converter
    GfmEditor = RedmineReformat::Converters::GfmEditor
    SourcePos = RedmineReformat::Converters::SourcePos

    def initialize(opts = {})
      @bullet_list_marker = opts.fetch(:bullet_list_marker, '*')
      @spaces_before = opts.fetch(:spaces_before,  0)
      @spaces_after = opts.fetch(:spaces_after,  0)
      @pad = (opts[:pad] || 'none').to_sym
      @silent = opts.fetch(:silent, false)
    end

    def convert(text, ctx = nil)
      return text if text.empty?
      reference = ctx && ctx.ref
      converted = text.dup
      macros = extract_macros(converted)
      begin
        converted = normalize_lists(converted)
      rescue Exception => e
        unless @silent
          msg = String.new
          msg << "Failed CommonmarkListFormatter '#{reference}' due to #{e.message} - #{e.class}\n"
          msg << "The text was:\n"
          msg << "#{'-' * 80}\n"
          msg << "#{text}\n"
          msg << "#{'-' * 80}\n"
          STDERR.print msg
        end
        raise
      end
      restore_macros(converted, macros)
      converted
    end

    private
    include RedmineReformat::Converters::Macros
    LI_START_PAT = '(?:(?:(?:[0-9]+\.)|[-*+])[ ]*(?= |$))'
    LI_START_RE = /^(([0-9]+\.)|[-*+])[ ]*(?= |$)/
    BQ_PAT = '(?:(?:[ ]{0,3}\>[ ]?)*)'

    def line_start_col(e, lineno)
      e.line(lineno, /\A#{BQ_PAT}/) do |source, range, m|
        return 1 + m[0].length
      end
    end

    def process_node(e, node, indent_diffs, indent)
      nested_indent = indent
      if node.type == :list_item
        pos = e.sourcepos(node)
        # malformed source - rare
        return nil unless pos
        e.source(pos, LI_START_RE) do |source, range, m|
          sp_marker = m[0] # spaced marker
          marker = m[1]
          ordered = !!m[2]
          newmarker = if ordered then m[1] else @bullet_list_marker end
          # extra space around marker
          sp_before = nil
          sp_after = sp_marker.length - marker.length
          newsp_before = @spaces_before
          newsp_after = @spaces_after
          case @pad
          when :left
            newsp_before -= min(newsp_before, newmarker.length - 1)
          when :right
            newsp_after -= min(newsp_after, newmarker.length - 1)
          end
          new_sp_marker = "#{' ' * newsp_before}#{newmarker}#{' ' * newsp_after}"

          pos1 = SourcePos.new(
            [pos.start_line, line_start_col(e, pos.start_line)],
            [pos.start_line, pos.start_column + sp_marker.length - 1]
          )
          # locate space after indent and prepend it to sp_marker
          e.source(pos1, /\A((?:\s*#{LI_START_PAT})+)?\s*#{Regexp::quote(sp_marker)}\z/) do |s1, r1, m1|
            # list with empty first item - not supported
            return nil if m1[1]
          end

          e.source(pos1, /\A[ ]{#{indent}}([ ]*)#{Regexp::quote(sp_marker)}\z/) do |s1, r1, m1|
            sp_before = m[1].length
            sp_marker = "#{m1[1]}#{sp_marker}"
            e.replace(m1.begin(1)...m1.end(0), new_sp_marker, r1)
          end

          nested_indent = indent + sp_marker.length + 1
          indent_diff = new_sp_marker.length - sp_marker.length
          unless indent_diff.zero?
            # note indentation change of wrapped / nested list items
            (pos.start_line + 1).upto(pos.end_line) do |lineno|
              e.line(lineno, /\A#{BQ_PAT}([ ]*)/) do |sn, rn, mn|
                # only shorten indentation if it is at least as expected for proper formatting
                unless indent_diff.negative? && mn[1].length < nested_indent
                  indent_diffs[lineno] ||= 0
                  indent_diffs[lineno] += new_sp_marker.length - sp_marker.length
                end
              end
            end
          end
        end
      end
      return nested_indent
    end

    def walk_lists(e, root, indent_diffs, indent = 0)
      root.each do |node|
        nested_indent = process_node(e, node, indent_diffs, indent)
        walk_lists(e, node, indent_diffs, nested_indent) if nested_indent
      end
    end

    def normalize_lists(text)
      e = GfmEditor.new(text)
      indent_diffs = {}
      walk_lists(e, e.document, indent_diffs)
      e.apply.each_line.with_index(1).map do |line, lineno|
        if indent_diffs.key?(lineno)
          indent_diff = indent_diffs[lineno]
          line.sub(/\A(#{BQ_PAT})([ ]*)(.*)/m) do |m|
            bq, sp, rest = $1, $2, $3
            new_spaces = sp.length + indent_diff
            raise "Unexpected space deletion" if new_spaces.negative?
            "#{bq}#{' ' * new_spaces}#{rest}"
          end
        else
          line
        end
      end.join
    end
  end
end
