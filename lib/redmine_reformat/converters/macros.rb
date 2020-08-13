# frozen_string_literal: true

module RedmineReformat
  module Converters
    module Macros
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
end
