# frozen_string_literal: true

require 'commonmarker'
require_relative 'editor'

module RedmineReformat::Converters::MarkdownToCommonmark
  class Converter
    def initialize(opts = {})
      @replaces = {
        hard_wrap: opts.fetch(:hard_wrap, true),
        underline: opts.fetch(:underline, true),
      }
      @superscript = opts.fetch(:superscript, true)
    end

    def convert(text, ctx = nil)
      text = text.dup
      macros = extract_macros(text)
      text = outplace_superscript(text) if @superscript
      text = replace(text, @replaces) if @replaces.values.any?
      restore_macros(text, macros)
      text
    end

    private
    CMARK_PARSE_OPTS = [:STRIKETHROUGH_DOUBLE_TILDE, :FOOTNOTES]
    # SOURCEPOS actually affects also parsing
    CMARK_RENDER_OPTS = [:SOURCEPOS]
    CMARK_EXTS = [:table, :strikethrough, :autolink]

    def document(text)
      text = text.encode('UTF-8')
      opts = CommonMarker::Config.process_options(CMARK_PARSE_OPTS, :parse)
      opts |= CommonMarker::Config.process_options(CMARK_RENDER_OPTS, :render)
      CommonMarker::Node.parse_document(text, text.bytesize, opts, CMARK_EXTS)
    end

    # Nonstructural replaces not affecting the document structure
    # Recognized opts: :hard_wrap and :underline
    def replace(text, opts)
      e = Editor.new(text)
      macrotext = false
      document(text).walk do |node|
        if opts[:hard_wrap] && node.type == :softbreak
          pos = node.previous && node.previous.sourcepos
          lineno = pos && pos[:end_line]
          lineno && lineno > 0 and e.line(lineno) do |line, range|
            line.match(/(?<macro>#{MACRO_SUB_RE})?(?<nl>[\r\n]*)$/) do |m|
              if macrotext && e.line?(lineno + 1) && /^}}/ =~ e.line(lineno + 1)
                macrotext = false
              elsif m['macro']
                macrotext = true if m['macro'].include?('macrotext')
              else
                e.insert(m.begin('nl'), '  ', range)
              end
            end
          end
        end
        if opts[:underline] && node.type == :emph
          e.source(node.sourcepos) do |source, range|
            source.match(/\A(_).*(_)\z/m) do |m|
              e.replace(m.begin(1)...m.end(1), '<ins>', range)
              e.replace(m.begin(2)...m.end(2), '</ins>', range)
            end
          end
        end
      end
      e.apply
    end

    SUPERSCRIPT_RE = /
        \^
        (?:
          ([^\s(]\S*)          # plain content
        |
          \((.*?)(?:\)|\\(.?)) # parenthesized content, esctrailer
        )
      /xm

    def outplace_superscript(text)
      e = Editor.new(text)
      protect_until_idx = 0
      document(text).walk do |node|
        if node.type == :text
          pos = content_sourcepos(e, node.parent)
          next unless pos
          parentctx = e.source_range(pos)
          e.source(node.sourcepos) do |textsrc, textctx|
            textsrc.scan(/(?<!\\)(?:\\\\)*(\^)/m) do
              m = Regexp.last_match
              sup_evalctx = (textctx.min + m.begin(1))..parentctx.max
              next if sup_evalctx.min < protect_until_idx
              text[sup_evalctx].match(SUPERSCRIPT_RE) do |bm|
                protect_until_idx = sup_evalctx.min + bm.end(0)
                body = bm[1] || bm[2]
                trailer = superscript_esc_trailer(bm[3])
                suprng = bm.begin(0)...bm.end(0)
                newbody, restart = superscript_process_body(body)
                replacement = "<sup>#{newbody}#{trailer}</sup>"
                e.replace(suprng, replacement, sup_evalctx)
                return outplace_superscript(e.apply) if restart
              end
            end
          end
        end
      end
      e.apply
    end

    # Process eventual nested superscripts and ensure non-delimiting delimiter chars are
    # escaped to prevent them to bind to the subsequent text.
    # Returns processed superscript body and a flag indicating whether the subsequent
    # text might have changed interpretation.
    def superscript_process_body(text)
      # nested superscripts are rare, save CPU...
      text = outplace_superscript(text) if text.include? '^'
      # escape delimiter characters in text nodes, as they are bound to this superscript
      e = Editor.new(text)
      document(text).walk do |node|
        if node.type == :text
          e.source(node.sourcepos) do |textsrc, textctx|
            textsrc.scan(/(?<!\\)(?:\\\\)*([*~`]|(?<!\w)_|_(?!\w))/m) do
              m = Regexp.last_match
              e.insert(m.begin(1), '\\', textctx)
            end
          end
        end
      end
      [e.apply, e.editcount.positive?]
    end

    # ^`(sup\x` renders as `<sup>sup\</sup>`, the x is always dropped.
    # weird, but we should not drop any user content
    def superscript_esc_trailer(x)
      return '' unless x
      case x
      when '', '\\', /\s/
        '\\\\'
      else
        "\\\\<!-- #{x} -->"
      end
    end

    # Create sourcepos from combination of the first and last child elements
    # Note that code nodes actually reports their content position
    def content_sourcepos(e, node)
      edges = [node.first_child, node.last_child]
      return nil unless edges.all?
      poses = edges.map { |node| node.sourcepos }
      return nil unless poses.all?
      pos = {
        start_line: poses[0][:start_line],
        start_column: poses[0][:start_column],
        end_line: poses[1][:end_line],
        end_column: poses[1][:end_column],
      }
      # code node sourcepos excludes the backticks -> extend to inner elimiter first
      if edges[0].type == :code && pos[:start_column] > 1
        pos[:start_column] -= 1
      end
      # end column can even be legally zero
      if edges[1].type == :code && pos[:end_column] >= 0
        pos[:end_column] += 1
      end
      return nil unless pos.values.all? { |p| p && p > 0 }

      # extend code node sourcepos to outer delimiter
      if edges[0].type == :code
        delimpos = node.sourcepos.dup
        delimpos[:end_line] = pos[:start_line]
        delimpos[:end_column] = pos[:start_column]
        e.source(delimpos) do |delims|
          delims.match(/`+\s*$/) do |m|
            pos[:start_column] -= m[0].length - 1
          end
        end
      end
      if edges[1].type == :code
        delimpos = node.sourcepos.dup
        delimpos[:start_line] = pos[:end_line]
        delimpos[:start_column] = pos[:end_column]
        e.source(delimpos) do |delims|
          delims.match(/^\s*`+/) do |m|
            pos[:end_column] += m[0].length - 1
          end
        end
      end
      pos
    end

    # adapted from Redmine ApplicacationHelper
    MACROS_RE = /(
      (!)?                        # escaping
      (
      \{\{                        # opening tag
      ([\w]+)                     # macro name
      (\(([^\n\r]*?)\))?          # optional arguments
      ([\n\r].*?[\n\r])?          # optional block of text
      \}\}                        # closing tag
      )
     )/mx

    MACRO_SUB_RE = /(
        \{\{
        macro(?:text)?\((\d+)\)
        \}\}
        )/x

    def extract_macros(text)
      macros = {}
      text.gsub!(MACROS_RE) do
        all, esc, orig_macro, macro, args, text = $1, $2, $4, $4.downcase, $5, $7
        index = macros.size
        # macros with interpreted text
        if text && ['collapse'].include?(macro)
          macros[index] = "#{esc}{{#{orig_macro}#{args}"
          "{{macrotext(#{index})}}#{text}}}"
        else
          macros[index] = all
          "{{macro(#{index})}}"
        end
      end
      macros
    end

    def restore_macros(text, macros)
      text.gsub!(MACRO_SUB_RE) do
        all, index = $1, $2.to_i
        orig = macros.delete(index)
        if orig then orig else all end
      end
    end
  end
end
