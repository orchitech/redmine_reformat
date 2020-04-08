# frozen_string_literal: true

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
      reference = ctx && ctx.ref
      text = text.dup
      return text if text.empty?
      macros = extract_macros(text)
      text = outplace_superscript(text) if @superscript
      text = replace(text, @replaces) if @replaces.values.any?
      restore_macros(text, macros)
      text
    end

    private
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
    NL_MACRO_RE = /(?<macro>#{MACRO_SUB_RE})?(?<nl>[\r\n]*)$/
    SUPERSCRIPT_RE = /
        \^
        (?:
          ([^\s(]\S*)          # plain content
        |
          \((.*?)(?:\)|\\(.?)) # parenthesized content, esctrailer
        )
      /xm

    # Nonstructural replaces not affecting the document structure
    # Recognized opts: :hard_wrap and :underline
    def replace(text, opts)
      e = Editor.new(text)
      macrotext = false
      e.document.walk do |node|
        if opts[:hard_wrap] && node.type == :softbreak
          spos = e.sourcepos(node)
          lineno = spos && spos.start_line
          lineno and e.line(lineno, NL_MACRO_RE) do |line, range, m|
            if macrotext && e.line?(lineno + 1) && /^}}/ =~ e.line(lineno + 1)
              macrotext = false
            elsif m['macro']
              macrotext = true if m['macro'].include?('macrotext')
            else
              e.insert(m.begin('nl'), '  ', range)
            end
          end
        end
        if opts[:underline] && node.type == :emph
          e.source(node, /\A([_*]).*(\1)\z/m) do |source, range, m|
            if m[1] == '_'
              e.replace(m.begin(1)...m.end(1), '<ins>', range)
              e.replace(m.begin(2)...m.end(2), '</ins>', range)
            end
          end
        end
      end
      e.apply
    end

    def outplace_superscript(text)
      e = Editor.new(text)
      protect_until_idx = 0
      e.document.walk do |node|
        if node.type == :text
          spos = e.inner_sourcepos(node.parent)
          next unless spos
          parentctx = e.source_range(spos)
          e.source(node) do |textsrc, textctx|
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
      e.document.walk do |node|
        if node.type == :text
          e.source(node) do |textsrc, textctx|
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
