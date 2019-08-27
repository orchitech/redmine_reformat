require 'securerandom'

module TextileToMarkdown
  module RedmineReformat
    class Placeholders

      UNICODE_1CHAR_PRIV_START = "\uE000"
      UNICODE_1CHAR_PRIV_END = "\uF8FF"
      UNICODE_1CHAR_PRIV_NOBREAKS_MATCH = "[#{UNICODE_1CHAR_PRIV_START}-#{UNICODE_1CHAR_PRIV_END}]"
      UNICODE_1CHAR_PRIV_OPTBREAKS_MATCH = "«?#{UNICODE_1CHAR_PRIV_NOBREAKS_MATCH}»?"
      UNICODE_1CHAR_PRIV_OPTBREAKS_RE = /#{UNICODE_1CHAR_PRIV_OPTBREAKS_MATCH}/
      UNICODE_1CHAR_PRIV_NOBREAKERS_RE = /#{UNICODE_1CHAR_PRIV_NOBREAKS_MATCH}/
      UNICODE_1CHAR_PRIV_LBREAKER_RE = /«#{UNICODE_1CHAR_PRIV_NOBREAKS_MATCH}/
      UNICODE_1CHAR_PRIV_RBREAKER_RE = /#{UNICODE_1CHAR_PRIV_NOBREAKS_MATCH}»/
      UNICODE_1CHAR_PRIV_BREAKERS_RE = /«#{UNICODE_1CHAR_PRIV_NOBREAKS_MATCH}»/

      @@match_context_randoms = Hash.new {|h,k| h[k]=SecureRandom.hex}

      def initialize(text, reference = nil)
        @reference = reference
        # prepare 1-char placeholders from Unicode's Private Use Area
        # this approach might have been utilized more if introduced earlier :)
        # TODO: HTML entities should be also considered if we are really paranoid
        @occupied_char_placeholders = Set.new(text.scan(UNICODE_1CHAR_PRIV_NOBREAKERS_RE).collect {|c| c.ord})
        @char_ph_unused = UNICODE_1CHAR_PRIV_START.ord
        @char_phs = []
        @ph_chars = []
        @match_context_phs = Hash.new {|h,k| h[k]=[]}
      end

      def prepare_text(text)
        text.gsub!(/[«»]/) do |m|
          ph_for(m, :both, :init)
        end
      end

      def finalize_text(text)
        text.scan(/[«»]/, reference = nil) do |m|
          warn("a string breaker '#{m}' likely leaked to the output MD")
        end
        text.gsub!(UNICODE_1CHAR_PRIV_BREAKERS_RE) {|ph| restore(ph, :init)}
        # TODO: check if all placeholder usage counts are zeroed here
        text.scan(UNICODE_1CHAR_PRIV_NOBREAKERS_RE) do |m|
          if !@occupied_char_placeholders.include? m
            warn("a placeholder ord(#{m.ord}) likely leaked to the output MD")
          end
        end
        # TODO: consider checking placeholder set equivality - which can be tricky though
        #       as it can be legally entity-converted or duplicated
      end

      # TODO: parameter for whole/individual(?)
      # match_context: nil, :inherit or string
      def ph_for(char, breaker, context = nil, match_context = nil)
        char = "«#{context}»#{char}" if context
        i = @ph_chars.index(char)
        if i.nil?
          i = @ph_chars.length
          @char_ph_unused += 1 while @occupied_char_placeholders.include? @char_ph_unused
          raise 'Run out of 1-char placeholders' if @char_ph_unused > UNICODE_1CHAR_PRIV_END.ord
          @ph_chars << char
          @char_phs << @char_ph_unused
          @char_ph_unused += 1
        end
        phstr = with_breakers(@char_phs[i].chr(Encoding::UTF_8), breaker)
        match_context = context if match_context == :inherit
        return phstr unless match_context
        add_match_context(phstr, match_context)
      end

      def ph_for_each(str, breaker, context = nil, match_context = nil)
        phstr = str.to_s.each_char.map{|c| ph_for(c, :none, context)}.join
        phstr = with_breakers(phstr, breaker)
        match_context = context if match_context == :inherit
        return phstr unless match_context
        add_match_context(phstr, match_context)
      end

      def add_match_context(str, contextstr)
        @match_context_phs[contextstr] << str
        contextstr.sub(/<random>/){@@match_context_randoms[contextstr]}.sub(/<ph>/, str)
      end

      def match_context_match(contextstr, capture = '?:')
        phmatch = @match_context_phs[contextstr].uniq.map{|s| Regexp::quote(s)}.join('|')
        phmatch = '[^\s\S]' if phmatch.empty? # avoid matching anything
        m = contextstr.gsub(/(.*?)(<random>|<ph>|\Z)/) {"#{Regexp::quote($1)}#{$2}"}
        m.sub(/<random>/){@@match_context_randoms[contextstr]}.sub(/<ph>/, "(#{capture}#{phmatch})")
      end

      # less accurate match not relying on matched data
      def self.match_context_static_match(contextstr, min = 1, max = 1, capture = '?:')
        m = contextstr.gsub(/(.*?)(<random>|<ph>|\Z)/) {"#{Regexp::quote($1)}#{$2}"}
        m.sub(/<random>/){@@match_context_randoms[contextstr]}.sub(/<ph>/,
          "(#{capture}(?:#{UNICODE_1CHAR_PRIV_OPTBREAKS_MATCH}){#{min},#{max}})")
      end

      RESTORE_RE = /
        (.*?)                                       # $pre
        (?:
            (\A)?                                   # $phatstart
            («)?                                    # $lbreaker
            (#{UNICODE_1CHAR_PRIV_NOBREAKS_MATCH})  # $phchar
            (»)?                                    # $rbreaker
            (\Z)?                                   # $phatend
          |
            (?:\Z)
        )
      /x
      def restore(ph, context = nil, &block)
        have_phchar = nil
        ph.gsub(RESTORE_RE) do
          pre, phatstart, lbreaker, phchar, rbreaker, phatend = $~[1..6]
          have_phchar ||= phchar
          warn "invalid placeholder sequence '#{pre}'" unless pre.empty?
          warn "unexpected '«' position in multicharacter ph restore" if lbreaker && !phatstart
          warn "unexpected '»' position in multicharacter ph restore" if rbreaker && !phatend
          warn "restoring ph without ph char in '#{ph}'" unless have_phchar
          restored = if phchar then restore1(phchar, context) do |r|
            lbreaker = rbreaker = nil
            if block_given? then yield r else r end
          end
          end
          "#{pre}#{lbreaker}#{restored}#{rbreaker}"
        end
      end

      private

      def with_breakers(s, breaker)
        case breaker
        when :both
          "«#{s}»"
        when :left
          "«#{s}"
        when :right
          "#{s}»"
        when :none
          s
        else
          raise "Unknown breaker option '#{breaker}'"
        end
      end

      # TODO: Introduce a push/pop mechanism - counting individual placeholder em/displacements.
      # And report warning if the final count is not zero.
      def restore1(ph, context = nil, &block)
        i = @char_phs.index(ph.ord)
        return ph if i.nil?
        res = @ph_chars[i].sub(/^«([^»]*)»/) do
          return ph if context.nil? || context.to_s != $1
          ''
        end
        yield res
      end

      def warn(msg)
        STDERR.puts("[WARNING] #{@reference} - #{msg}")
      end
    end
  end
end
