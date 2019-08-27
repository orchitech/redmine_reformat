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
        # TODO: HTML entities should be also considered if we are really paranoid
        @occupied_char_placeholders = Set.new(text.scan(UNICODE_1CHAR_PRIV_NOBREAKERS_RE).collect {|c| c.ord})
        @char_ph_unused = UNICODE_1CHAR_PRIV_START.ord
        @char_phs = []
        @ph_chars = []
        @ph_usage = []
        @match_context_phs = Hash.new {|h,k| h[k]=[]}
      end

      def prepare_text(text)
        text.gsub!(/[«»]/) do |m|
          ph_for(m, :both, :init)
        end
      end

      def finalize_text(text)
        text.scan(/[«»]/) do |m|
          warn("a string breaker '#{m}' likely leaked to the output MD")
        end
        text.gsub!(UNICODE_1CHAR_PRIV_BREAKERS_RE) {|ph| restore(ph, :init)}
        text.scan(UNICODE_1CHAR_PRIV_NOBREAKERS_RE) do |m|
          if !@occupied_char_placeholders.include? m
            warn("a placeholder ord(#{m.ord}) likely leaked to the output MD")
          end
        end
        @ph_usage.each_with_index do |val, i|
          warn "placeholder '#{@ph_chars[i]}' usage is #{val} at the end" unless val.zero?
        end
        rand_re = @@match_context_randoms.each_value.map{|r| Regexp::quote(r)}.join('|')
        warn "a placeholder match context likely leaked to the output MD" if text.match? rand_re
        warn "a pandoc tag likely leaked to the output MD" if text.match? /pandocI/
        warn "an offtag tag likely leaked to the output MD" if text.match? /<redpre/
      end

      # match_context: nil, :inherit or string
      def ph_for(char, breaker, context = nil, match_context = nil)
        char = if context then "«#{context}»#{char}" else char.to_s end
        i = @ph_chars.index(char)
        if i.nil?
          i = @ph_chars.length
          @char_ph_unused += 1 while @occupied_char_placeholders.include? @char_ph_unused
          raise 'Run out of 1-char placeholders' if @char_ph_unused > UNICODE_1CHAR_PRIV_END.ord
          @ph_chars << char
          @char_phs << @char_ph_unused
          @ph_usage << 0
          @char_ph_unused += 1
        end
        @ph_usage[i] += 1
        phstr = with_breakers(@char_phs[i].chr(Encoding::UTF_8), breaker)
        match_context = context if match_context == :inherit
        return phstr unless match_context
        add_match_context(phstr, match_context)
      end

      def ph_for_each(str, breaker, context = nil, match_context = nil)
        chars = if str.nil? || str.empty? then [''] else str.to_s.each_char end
        phstr = chars.map{|c| ph_for(c, :none, context)}.join
        phstr = with_breakers(phstr, breaker)
        match_context = context if match_context == :inherit
        return phstr unless match_context
        add_match_context(phstr, match_context)
      end

      def add_match_context(str, contextstr)
        @match_context_phs[contextstr] << str
        contextstr.sub(/<random>/){@@match_context_randoms[contextstr]}.sub(/<ph>/, str)
      end

      def match_context_match(contextstr, capture = nil)
        phs = @match_context_phs[contextstr]
        max = phs.length
        phmatch = if phs.empty?
          max = 1
          '[^\s\S]' # avoid matching anything
        else
          phs.uniq.map{|s| Regexp::quote(s)}.join('|')
        end
        self.class.build_match_context_match(contextstr, phmatch, 1, max, capture)
      end

      # less accurate match not relying on matched data
      def self.match_context_static_match(contextstr, min = 1, max = 1, capture = nil)
        build_match_context_match(contextstr, UNICODE_1CHAR_PRIV_OPTBREAKS_MATCH, min, max, capture)
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

      def self.to_capturestr(capture)
        case
        when Symbol === capture
          "?<#{capture}>"
        when capture
          ''
        else
          '?:'
        end
      end

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

      def self.build_match_context_match(contextstr, phmatch, min, max, capture)
        m = contextstr.gsub(/(.*?)(<random>|<ph>|\Z)/) {"#{Regexp::quote($1)}#{$2}"}
        m.gsub!(/<random>/){@@match_context_randoms[contextstr]}
        m.gsub!(/<ph>/, "(#{to_capturestr(capture)}(?:#{phmatch}){#{min},#{max}})")
        m
      end

      def restore1(ph, context = nil, &block)
        i = @char_phs.index(ph.ord)
        return ph if i.nil?
        res = @ph_chars[i].sub(/^«([^»]*)»/) do
          return ph if context.nil? || context.to_s != $1
          ''
        end
        @ph_usage[i] -= 1
        warn "Placeholder '#{@ph_chars[i]}' restored more times than added" if @ph_usage[i] < 0
        yield res
      end

      def warn(msg)
        STDERR.puts("[WARNING] #{@reference} - #{msg}")
      end
    end
  end
end
