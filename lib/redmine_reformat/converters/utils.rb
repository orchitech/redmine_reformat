# frozen_string_literal: true

module RedmineReformat
  module Converters
    module Utils
      class << self

        ENTITY_NAME_REFS = {
          '[' => ['lbrack', 'lsqb'],
          ']' => ['rbrack', 'rsqb'],
          ':' => ['colon'],
        }
        @@markup_char_res = Hash.new {|h, k| h[k] = {}}

        def markup_char_re(c, formatting)
          cache = @@markup_char_res[formatting]
          return cache[c] if cache.key? c
          entnames = ENTITY_NAME_REFS[c]
          raise ArgumentError.new("Markup char '#{c}' not supported") unless entnames
          alts = []
          alts << Regexp.escape(c)
          alts << Regexp.escape("\\#{c}") if markdown_ish(formatting)
          alts << entnames.map {|ent| Regexp.escape("&#{ent};")}
          alts << "&\\#0*#{char2dec(c)};"
          alts << "&\\#x0*#{char2hex(c)};"
          cache[c] = Regexp.new(alts.join('|'), Regexp::IGNORECASE)
        end

        def markdown_ish(formatting)
          formatting && formatting =~ /markdown|common.*mark|gfm/
        end

        def char2hex(c)
          sprintf('%X', c.codepoints[0])
        end

        def char2dec(c)
          c.codepoints[0]
        end

        # convert to int or string based on value
        def to_i_or_s(v)
          return nil if v.nil?
          return v if v.is_a? Integer
          str = v.to_s
          return str unless str =~ /^\d+$/
          str.to_i
        end
      end
    end
  end
end
