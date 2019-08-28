# Redmine Textile reformatter allowing to be processed to Markdown
# Currently uses pandoc, but it would make more sense to output Markown directly
#
# Written by Martin Cizek, Orchitech Solutions
# Contains portions of Redmine and Redcloth3 code

require 'textile_to_markdown/redmine_reformat/placeholders'
require 'textile_to_markdown/markdown-table-formatter/table-formatter'
require 'htmlentities'

module TextileToMarkdown
  module RedmineReformat

    # treat '==' as <notextile> ?
    CONF_NOTEXTILE_2EQS = false

    # Redcloth3-Redmine constants
    A_HLGN = /(?:(?:<>|<|>|\=|[()]+)+)/
    A_VLGN = /[\-^~]/
    C_CLAS = '(?:\([^")]+\))'
    C_LNGE = '(?:\[[a-z\-_]+\])'
    C_STYL = '(?:\{[^{][^"}]+\})'
    S_CSPN = '(?:\\\\\d+)'
    S_RSPN = '(?:/\d+)'
    A = "(?:#{A_HLGN}?#{A_VLGN}?|#{A_VLGN}?#{A_HLGN}?)"
    S = "(?:#{S_CSPN}?#{S_RSPN}|#{S_RSPN}?#{S_CSPN}?)"
    C = "(?:#{C_CLAS}?#{C_STYL}?#{C_LNGE}?|#{C_STYL}?#{C_LNGE}?#{C_CLAS}?|#{C_LNGE}?#{C_STYL}?#{C_CLAS}?)"
    # PUNCT = Regexp::quote( '!"#$%&\'()*+,-./:;<=>?@[\\]^_`{|}~' )
    PUNCT = Regexp::quote( '!"#$%&\'*+,-./:;=?@\\^_`|~' )
    PUNCT_NOQ = Regexp::quote( '!"#$&\',./:;=?@\\`|' )
    PUNCT_Q = Regexp::quote( '*-_+^~%' )
    HYPERLINK = '(\S+?)([^\w\s/;=\?]*?)(?=\s|<|$)'

    PANDOC_MARKUP_CHARS = Regexp::quote('\\*#_@~-+^|%=[]&')
    PANDOC_STRING_BREAKERS = Regexp::quote(" \t\n\r.,\"'?!;:<>«»„“”‚‘’()[]")
    PANDOC_WORD_BOUNDARIES = PANDOC_MARKUP_CHARS + PANDOC_STRING_BREAKERS

    # Tag constants
    TAG_FENCED_CODE_BLOCK = 'pandocIforceItoIouputIfencedIcodeIblock'
    TAG_LINE_BREAK_IN_QTAG = ' <br class="pandocIprotectIlineIbreakIinIqtag" />'

    # Match contexts
    TEXTILE_LIST_MATCH_CONTEXT = 'list<random><ph>'
    TEXTILE_HR_MATCH_CONTEXT = 'hr<random><ph>'
    TABLE_PIPE_MATCH_CONTEXT = '.tp<ph>' # should match the length of #PIPE_HTMLENT
    REAL_QTAG_RESTORE_MATCH_CONTEXT = 'qtag<random><ph>'
    MACRO_MATCH_CONTEXT = '{{MdConversionMacro<random><ph>}}'
    FENCED_CODE_BLOCK_MATCH_CONTEXT = '{{MdConversionFencedCode<random><ph>}}'
    FOOTNOTE_MATCH_CONTEXT = '<random>fn<ph>follows'

    # Special matches
    PIPE_HTMLENT_MATCH = '&vert;|&#124;|&#[xX]7[cC];'
    PIPE_HTMLENT = '&#124;'

    def initialize_reformatter(text, reference)
      @ph = Placeholders.new(text, reference)
      @ph.prepare_text(text)
      @pre_list = []
      @defined_footnotes = []
      @referenced_footnotes = []
    end

    def finalize_reformatter(text)
      @ph.finalize_text(text)
      @ph = nil
    end

    # Redmine way of normalizing
    def clean_white_space(text)
      # normalize line breaks
      text.gsub!(/\r\n?/, "\n")
      text.gsub!(/\t/, '    ')
      text.gsub!(/^ +$/, '')
      text.gsub!(/\n{3,}/, "\n\n")
      # this is probably counterproductive:
      # text.gsub!(/"$/, '" ')
    end

    # Rip redmine macros, so they don't get corrupted
    def rip_macros textile
      textile.gsub!(/^!?\{\{(.+?)\}\}/m) do |m|
        macro = $1
        if macro =~ /<redpre \w+ \d+>/
          m # avoid cross-matching with offtags
        elsif macro =~ /\A\s*collapse/
          m # collapse macro should contain textile, so keep it
        else
          @ph.ph_for(m, :none, MACRO_MATCH_CONTEXT, :inherit)
        end
      end
      # https://github.com/tckz/redmine-wiki_graphviz_plugin
      textile.gsub!(/^.*\{\{\s*graphviz_me.*/m) do |m|
        smooth_offtags m, true
        @ph.ph_for(m, :none, MACRO_MATCH_CONTEXT, :inherit)
      end
    end

    #
    # Flexible HTML escaping
    #
    def htmlesc(str, mode = :Quotes)
      if str
        str.gsub!('&', '&amp;')
        str.gsub!('"', '&quot;') if mode != :NoQuotes
        str.gsub!("'", '&#039;') if mode == :Quotes
        str.gsub!('<', '&lt;')
        str.gsub!('>', '&gt;')
      end
      str
    end

    OFFTAG_TAGS = 'code|pre|kbd|notextile'
    OFFTAGS = /(#{OFFTAG_TAGS})/.freeze
    OFFTAG_MATCH = %r{(?:(</#{OFFTAGS}\b>)|(<#{OFFTAGS}\b[^>]*>))(.*?)(?=</?#{OFFTAGS}\b\W|\Z)}mi.freeze

    def rip_offtags(text, escape_aftertag = true, escape_line = true)
      if text =~ /<.*>/
        ## strip and encode <pre> content
        codepre = 0
        used_offtags = {}
        text.gsub!(OFFTAG_MATCH) do |line|
          if $3
            first = $3
            offtag = $4
            aftertag = $5
            codepre += 1
            used_offtags[offtag] = true
            if codepre - used_offtags.length > 0
              htmlesc(line, :NoQuotes) if escape_line
              @pre_list[-1] = @pre_list.last + line
              line = ''
            else
              ### htmlesc is disabled between CODE tags which will be parsed with highlighter
              ### Regexp in formatter.rb is : /<code\s+class="(\w+)">\s?(.+)/m
              ### NB: some changes were made not to use $N variables, because we use "match"
              ###   and it breaks following lines
              htmlesc(aftertag, :NoQuotes) if aftertag && escape_aftertag && !first.match(/<code\s+class="(\w+)">/)
              line = "<redpre #{offtag} #{@pre_list.length}>"
              first.match(/<#{OFFTAGS}([^>]*)>/)
              tag = $1
              $2.to_s.match(/(class\=("[^"]+"|'[^']+'))/i)
              tag << " #{$1}" if $1 && tag == 'code'
              @pre_list << "<#{tag}>#{aftertag}"
            end
          elsif $1 && (codepre > 0)
            if codepre - used_offtags.length > 0
              htmlesc(line, :NoQuotes) if escape_line
              @pre_list[-1] = @pre_list.last + line
              line = ''
            end
            codepre -= 1 unless codepre.zero?
            used_offtags = {} if codepre.zero?
          end
          line
        end
      end
      text
    end

    # pandoc does not create fenced code blocks when there is leading whitespace
    def unindent_pre_offtag(text)
      text.gsub!(/^[[:blank:]]+(?=<redpre pre\b)/, '')
    end

    # Merge <pre><code>... to <pre>...
    # Allow also for swapping closing offtags, which is tolerated by Redmine
    def merge_pre_code_offtags(text)
      text.gsub!(
        %r{
          (?<preopen><redpre[ ]pre[ ](?<offcode1>\d+)>\s*)
          (?<codeopen><redpre[ ]code[ ](?<offcode2>\d+)>)?
          (?<out>.*?)
          (?<preclose>
            (?<codeclose1></code[ ]*>)?
            \s*
            </pre[ ]*>
            (?<spacepastpreclose>\s*)
            (?<codeclose2></code[ ]*>)?
            |\Z
          )
        }xm) do |full|
        md = $~
        codeclose2 = md[:codeclose2]
        codeclose2 = nil if md[:codeopen] and md[:codeclose1].nil?

        offcode1 = md[:offcode1].to_i
        # redmine mangles pre block if it contains code, let's be better
        raw_code = @pre_list[offcode1] =~ /^<pre[^>]*>.*[\S]/m

        offcode = if md[:offcode2] and !raw_code then md[:offcode2].to_i else offcode1 end

        @pre_list[offcode1] = @pre_list[offcode].sub(/^<(?:code|pre)\b(\s+class="[^"]+")?/) do
          preparam = if $1 then $1 else " class=\"#{TAG_FENCED_CODE_BLOCK}\"" end
          "<pre#{preparam}"
        end
        # avoid any further work with the merged offtag contents
        @pre_list[md[:offcode2].to_i] = nil if md[:offcode2]
        out = md[:out]
        if raw_code
          pre_content = "#{md[:codeopen]}#{out}#{md[:codeclose1]}".dup
          out = String.new
          smooth_offtags pre_content
          @pre_list[offcode1] += pre_content
        end
        # eat </code> if it is opened and <pre> is closed by EOF
        out.sub!(/<\/code>\s*$/m, '') if md[:codeopen]
        "#{md[:preopen]}#{out}</pre>#{codeclose2}#{md[:spacepastpreclose]}"
      end
    end

    # Preprocess non-interpreted sections for latter postprocessing
    def protect_offtag_contents
      @pre_list.map! do |code|
        code.gsub(/[!+_*{}\[\]-]/) {|m| @ph.ph_for(m, :none, :aftercode)} if code
      end
    end

    def smooth_offtags(text, clean = false)
      unless @pre_list.empty?
        ## replace <pre> content
        text.gsub!(/<redpre \w+ (\d+)>/) do
          i = $1.to_i
          res = @pre_list[i]
          @pre_list[i] = nil if clean
          res
        end
      end
    end

    def no_textile(text)
      return unless CONF_NOTEXTILE_2EQS
      text.gsub!(/(^|\s)==([^=]+.*?)==(\s|$)?/,
                 '\1<notextile>\2</notextile>\3')
      text.gsub!(/^ *==([^=]+.*?)==/m,
                 '\1<notextile>\2</notextile>\3')
    end

    ALLOWED_TAGS = %w[redpre pre code kbd notextile].freeze
    def escape_html_tags(text)
      text.gsub!(%r{<(\/?([!\w]+)[^<>\n]*)(>)?}) do |_m|
        if ALLOWED_TAGS.include?($2) && !$3.nil?
          "<#{$1}#{$3}"
        else
          "&lt;#{$1}#{'>' if $3 =~ /[^[:space:]]/}"
        end
      end
    end

    QUOTES_RE = /(^>+([^\n]*?)(\n|$))+/m.freeze
    QUOTES_CONTENT_RE = /^([> ]+)(.*)$/m.freeze

    def block_textile_quotes(text)
      text.gsub!(QUOTES_RE) do |match|
        lines = match.split(/\n/)
        quotes = String.new
        indent = 0
        lines.each do |line|
          line =~ QUOTES_CONTENT_RE
          bq = $1
          content = $2
          l = bq.count('>')
          if l != indent
            quotes << ("\n\n" + (l > indent ? '<blockquote>' * (l - indent) : '</blockquote>' * (indent - l)) + "\n\n")
            indent = l
          end
          quotes << (content + "\n")
        end
        quotes << ("\n" + '</blockquote>' * indent + "\n\n")
        quotes
      end
    end

    def normalize_hr_to_phs(text)
      text.gsub!(/((?:\n\n|\A\n?))[[:blank:]]*(-{3,})[[:blank:]]*((?:\n\n|\n?\Z))/m) do
        before, hr, after = $~[1..3]
        "#{before}#{@ph.ph_for_each(hr, :none, :qtag, TEXTILE_HR_MATCH_CONTEXT)}#{after}"
      end
    end

    # eat empty lines between indented continuations
    def glue_indented_continuations(textile)
      last_blank_line = ''
      continuation = false
      textile.gsub!(/^(([[:blank:]]*(([*#])+) )|([[:blank:]]))?([^\n]*$)(?:\n|\Z)/) do |line|
        list, leading_space = !$2.nil?, !$5.nil?
        list_prefix, list_type = $3, $4
        rest = $6
        tag_ended = (rest =~ /<\/[^\s>]+>/)
        if list or tag_ended
          continuation = true
          res = "#{last_blank_line}#{line}"
          last_blank_line = ''
          res
        elsif continuation
          if leading_space
            # eat eventual preceding blank line
            last_blank_line = ''
            line
          elsif rest.empty?
            # blank line - waiting for next line
            last_blank_line = "\n"
            ''
          elsif last_blank_line.empty?
            # just continuing
            line
          else
            # blank line was present and we are not indented - finally ending continuation
            continuation = false
            res = "#{last_blank_line}#{line}"
            last_blank_line = ''
            res
          end
        else
          last_blank_line = ''
          # unindent heading (which is allowed by Redmine)
          line.sub(/^[[:blank:]]+(h[1-6]\.[[:blank:]]+\S)/, '\\1')
        end
      end
      textile << last_blank_line
    end

    # blocks starting with a leading space are either space-indented lists or code blocks
    # pandoc treats them diferrently than Redmine, so remove leading spaces and add <pre> tags for non-lists
    #
    # Update: redmine made its Textile interpreting stricter between 3.4.2 and 3.4.11 and
    # space-indented multi-level lists do not work anymore. This code solves it as a side effect :)
    def process_indented_blocks(text)
      text.gsub!(/(\A\n?|\n\n)^((?: (?!<redpre))+)((?:.(?!<redpre))+?)(?=\n?\Z|\n\n)/m) do |block|
        prefix = $1
        strip_spaces = $2.length
        postfix = $4
        list = false
        code_block = $3.split("\n").map do |line|
          line.sub!(/^ {#{strip_spaces}}/, '')
          list = true if line =~ /^[*#]+ /
          line
        end.join("\n")
        if list
          "#{prefix}\n#{code_block}#{postfix}"
        elsif prefix == "\n\n"
          # indented code must not be at the beginning of file
          @pre_list << "<pre class=\"#{TAG_FENCED_CODE_BLOCK}\">\n#{code_block}\n"
          "#{prefix}\n<redpre pre #{@pre_list.length - 1}></pre>#{postfix}"
        else
          block
        end
      end
    end

    HARD_BREAK_RE = /
      (.)  # $pre
      \n
      (?!
          \n
        |
          \Z
        |
          [[:blank:]]*
          (
              (?:[#*=]+|#{Placeholders.match_context_static_match(TEXTILE_LIST_MATCH_CONTEXT, 1, nil)})
              (\s|$)
            |
              [{|]
          )
      )
    /x
    def hard_break(text)
      text.gsub!(HARD_BREAK_RE, '\\1<br />')
    end
    def revert_hard_break(text)
      text.gsub!(/<br \/>/, "\n")
    end

    # This should be what Pandoc matches in the unbracketed version
    PANDOC_LINK_RE = /
      ((?:[\s\[{(]|[#{PUNCT}])?) # $ppre
      "                          # start
      ([^"\n]+?)                 # $ptext
      ":
      (\S+?)                     # $purl
      ([!.,;:]?)                 # $ppost
      (?=<|\s|$)
    /x

    LINK_RE = /
            (
            ([\s\[{(]|[#{PUNCT}])?     # $pre
            "                          # start
            (                          # $fulltext
              (#{C})                     # $atts
              ([^"\n]+?)                 # $text
              \s?
              (?:\(([^)]+?)\)(?="))?     # $title
            )
            ":
            (                          # $url
              (\/|[a-zA-Z]+:\/\/|www\.|mailto:) # $proto
              [[:alnum:]_\/]\S+?
            )
            (\/)?                      # $slash
            ([^[:alnum:]_\=\/;\(\)]*?) # $post
            )
            (?=<|\s|$)
        /x
    def inline_textile_link(text)
      text.gsub!(PANDOC_LINK_RE) do |m|
        ppre, ptext, purl, ppost = $~[1..4]
        # Redmine links are apparently subset of what Pandoc treats as a link
        if !ptext.include?('<br />') && !purl.include?('<br />') && m =~ LINK_RE
          all,pre,fulltext,atts,text,title,url,proto,slash,post = $~[1..10]
          # Idea below : an URL with unbalanced parethesis and
          # ending by ')' is put into external parenthesis
          if ( url[-1]==?) and ((url.count("(") - url.count(")")) < 0 ) )
            url=url[0..-2] # discard closing parenth from url
            post = ")"+post # add closing parenth to post
          end
          # Redmine does not recognize bracketed version while Pandoc does
          pre.sub!(/\[$/, '&#91;') if pre
          url.gsub!(']') {|b| @ph.ph_for(b, :none)}
          "#{pre}[\"#{fulltext}\":#{url}#{slash}]#{post}"
        else
          "#{ppre}&quot;#{ptext}\":#{purl}#{ppost}"
        end
      end
    end

    # Match inline code in RedCloth3 way and address these issues:
    # - Redmine support @ inside inline code marked with @ (such as "@git@github.com@"), but not pandoc.
    # - Redmine's inline code also gets html entities interpreted in Textile, but not in Markdown
    # - some sequences will be pre/postprocessed in normal text - protect them in code
    def inline_textile_code(text)
      htmlcoder = HTMLEntities.new
      text.gsub!(/(?<!\w)@(?:\|(\w+?)\|)?(.+?)@(?!\w)/) do |m|
        # lang = $1 # lang is ignored even by Redmine
        code = $2

        if m =~ /<redpre \w+ \d+>/
          # offtag accidentaly matched - Redmine 3.4.2 fails on this, let's be better
          m
        else
          revert_hard_break code

          # tighten the code span
          lspace = rspace = ''
          code.match(/^\s+/) {|s| lspace = s}
          code.match(/\s+$/) {|s| rspace = s}
          code.strip!

          if code.empty?
            "#{lspace}#{rspace}"
          else
            @pre_list << "<code at>#{code}"
            "#{lspace}<redpre code #{@pre_list.length - 1}></code>#{rspace}"
          end
        end
      end
      # all @ that do not demark code
      text.gsub!(/@/) {|m| @ph.ph_for(m, :none)}
    end

    def protect_wiki_links(text)
      # protect wiki links
      # eat and escape even the following '(', which might be interpreted as a MD link
      text.gsub!(/(!?\[\[[^\]\n\|]+(?:\|[^\]\n\|]+)?\]\])(( *\n? *)\()?/m) do |link|
        wiki_link, parenthesis_after, parenthesis_indent = $1, $2, $3
        if parenthesis_after
          link = "#{wiki_link}#{parenthesis_indent}\\("
        end
        # needs to be restored after table processing because of pipe character
        link.gsub(/[#{PANDOC_WORD_BOUNDARIES}]/) {|m| @ph.ph_for(m, :none, :after_table_reformat)}
      end
    end

    # Normalize lists to support Redmine flexible treatment and fix common users' mistakes eventually.
    # At this moment, it is expected:
    # - common unindenting was done and all list items at the beginning of the line, see #process_indented_blocks
    # - lists are terminated by a blank line, see #glue_indented_continuations
    # Currently, we fix only mixed # and * in items of mixed lists , which is a common mistake.
    # But Redmine's behavior is a bit more complex - which we DO NOT address:
    # Redmine catches the initial list level and unindents it. It also treats invalid nesting of
    # ordered and unordered lists and inherits the oter type of list as sublist in the parent's
    # current level. But in the end, the behavior might be quire weird.
    # E.g.:
    # ```
    # * 1 List item (level 1)
    # # 2 This produces an ordered sublist of 1 (level 2)
    # * 3 And this produces an unordered sublist of 2 (level 3)
    # ```
    # pandoc does not interpret lines 2 and 3 as list items and it's probably OK :)
    def normalize_lists_to_phs(text)
      text.gsub!(/^(([*#])+)(?= )/) do |m|
        # last character determines list type
        listprefix = $2 * $1.length
        # make placeholders first to ease qtag character escaping
        @ph.ph_for_each(listprefix, :none, :qtag, TEXTILE_LIST_MATCH_CONTEXT)
      end
    end

    # pandoc interprets | as table separator regardless of protecting it by code or notextile tags
    def protect_pipes_in_tables(text)
      text.gsub!(/^ *\|[^\n]*\| *$/) do |row|
        # pandoc even decodes html entity, making it a cell separator
        row.gsub!(/#{PIPE_HTMLENT_MATCH}/) {@ph.ph_for(PIPE_HTMLENT, :both, TABLE_PIPE_MATCH_CONTEXT, :inherit)}
        row.gsub!(/(?<stag><redpre (?<htag>#{OFFTAG_TAGS}\b) (?<preid>\d+\b)[^>\n]*>)(?<content>.*?)(?<etag><\/\k<htag>[^>\n]*>)/) do |offtext|
          stag, content, etag = $~[:stag], $~[:content], $~[:etag]
          have_escape = false
          content.gsub!(/\|/) do
            have_escape = true
            @ph.ph_for(PIPE_HTMLENT, :both, TABLE_PIPE_MATCH_CONTEXT, :inherit)
          end

          # protect also ripped offtags
          unless @pre_list.empty?
            offtext.scan(/<redpre \w+ (\d+)>/) do
              @pre_list[$1.to_i].gsub!(/\||#{PIPE_HTMLENT_MATCH}/) do
                have_escape = true
                @ph.ph_for(PIPE_HTMLENT, :both, TABLE_PIPE_MATCH_CONTEXT, :inherit)
              end
            end
          end
          if have_escape
            "#{stag}#{content}#{etag}"
          else
            offtext
          end
        end
        row
      end
    end

    def drop_unsupported_table_features(text)
      text.gsub!(/^ *\|[^\n]*\| *$/) do |row|
        # Drop table colspan/rowspan notation ("|\2." or "|/2.") because pandoc does not support it
        # See https://github.com/jgm/pandoc/issues/22
        row.gsub!(%r{\|[/\\]\d{1,2}\. }, '| ')
        # Drop table alignement notation ("|>." or "|<." or "|=.") because pandoc does not support it
        # See https://github.com/jgm/pandoc/issues/22
        row.gsub!(/\|[<>=]\. /, '| ')
        row
      end
    end

    # MD requires table header and Textile tables were often with plain cells in bold instead of it
    def guess_table_headers(text)
      text.gsub!(/(?<=\A|\n$\n)^( *\|( *\*[^*|\n]+\* *\| *)+)(?=\Z|\n$\n|\n^ *\|)/m) do
        heading = $1
        heading.gsub!(/\| *\*([^*|\n]+)\*/) do
          header = $1
          "|_. #{header}"
        end
      end
    end

    # Make sure all tables have space in their cells
    def pad_table_cells(text)
      text.gsub!(/^ *\|([^|\n]*\|)+ *$/) do |row|
        row.gsub!(/\|([0-9~:_><=^\\\/]{1,4}\.)?(\s*)(([^|\n])+)/) do
          mod, lspace, content = $1, $2, $3
          lspace = ' ' if lspace.empty?
          content.sub!(/(\S)$/, '\\1 ')
          "|#{mod}#{lspace}#{content}"
        end
        row
      end
    end

    BLOCKS_GROUP_RE = /\n{2,}(?! )/m
    PREFIX_BLOCK_RE = /^(([a-z]+)(\d*))(#{A}#{C})\.(?::(\S+))?( )?(.*)$/m
    def process_textile_prefix_blocks(text)
      @defined_footnotes = []
      text.replace(text.split( BLOCKS_GROUP_RE ).collect do |blk|
        blk.strip!
        if blk =~ PREFIX_BLOCK_RE
          tag,tagpre,num,atts,cite,space,content = $~[1..7]
          # pandoc does not require space at least after p.
          next "#{@ph.ph_for(nil, :none)}#{blk}" unless space
          # supported by pandoc, but not Redmine
          next "#{@ph.ph_for(nil, :none)}#{blk}" if ['bc'].include? tagpre
          # drop attributes - probably should be done on more blocks
          next "#{tag}.#{cite}#{space}#{content}" if ['h'].include? tagpre

          next blk unless tagpre == 'fn'
          # deal with footnotes
          newtag = @ph.add_match_context(num, FOOTNOTE_MATCH_CONTEXT)
          @defined_footnotes << num
          blk.replace("#{newtag} #{content}")
        end
        blk
      end.join("\n\n"))
    end

    QTAGS = [
      ['**', '*'],
      ['*'],
      ['??', '_'],
      ['-', nil],
      ['__', '_'],
      ['_', '_'],
      ['%', nil],
      ['+', nil],
      ['^', nil],
      ['~', nil]
    ]
    QTAGS_JOIN = QTAGS.map {|rc, ht| Regexp::quote rc}.join('|')

    QTAGS.collect! do |rc, newrc|
      rcq = Regexp::quote rc
      newrc = rc if newrc.nil?
      re =
          /(^|[>\s\(])          # sta
          (?!\-\-)
          (#{QTAGS_JOIN}|#{Placeholders.match_context_static_match(REAL_QTAG_RESTORE_MATCH_CONTEXT)}|)      # oqs
          (#{rcq})              # qtag
          ([[:word:]]|[^\s].*?[^\s])    # content
          (?!\-\-)
          #{rcq}
          (#{QTAGS_JOIN}|#{Placeholders.match_context_static_match(REAL_QTAG_RESTORE_MATCH_CONTEXT)}|)      # oqa
          (?=[[:punct:]]|<|\s|\)|$)/x
      [rc, newrc, re]
    end

    def inline_textile_span_to_phs(text)
      QTAGS.each do |qtag_rc, newqtag, qtag_re|
        text.gsub!(qtag_re) do |m|
          sta,oqs,qtag,content,oqa = $~[1..6]
          # outplace leading and trailing line breaks, which Redmine supports
          content.sub!(/^((?:<br \/>)+)/) {|brl| oqs << brl; ''}
          content.sub!(/((?:<br \/>)+)$/) {|brr| oqa = "#{brr}#{oqa}"; ''}
          # eat the qtag including contents is nothing left
          next "#{sta}#{oqs}#{oqa}" unless content =~ /\S/

          content.gsub!(/<br \/>/, TAG_LINE_BREAK_IN_QTAG)
          # supress qtag atts where Redmine does not use them
          atts = content.match(/^(#{C})(.+)$/) {$1 unless $1.empty?}
          noatts = @ph.ph_for(nil, :both) unless atts
          qtag_mcph1 = @ph.ph_for("#{newqtag}#{noatts}", :none, :qtag, REAL_QTAG_RESTORE_MATCH_CONTEXT)
          qtag_mcph2 = @ph.ph_for(newqtag, :none, :qtag, REAL_QTAG_RESTORE_MATCH_CONTEXT)
          "#{sta}#{oqs}#{qtag_mcph1}#{content}#{qtag_mcph2}#{oqa}"
        end
      end
    end

    def protect_qtag_chars(text)
      text.gsub!(/(?<!\|)[#{PUNCT_Q}](?!\|)/) do |m|
        @ph.ph_for(m, :both, :qtag)
      end
      text.gsub!(/\?{2,}/) do |qms|
        # insert nil placeholders in between each char
        qms.gsub(/(?<=.)(?!$)/) {@ph.ph_for(nil, :none)}
      end
    end

    # restore real qtags for conversion
    def restore_real_qtags(text)
      text.gsub!(/#{@ph.match_context_match(REAL_QTAG_RESTORE_MATCH_CONTEXT, true)}/) do
        @ph.restore($1, :qtag)
      end
    end

    def textile_footnote_refs(text)
      text.gsub!(/\b\[([0-9]+?)\](\s)?/) do |m|
        num, after = $~[1..2]
        @referenced_footnotes << num
        if @defined_footnotes.include? num
          "#{@ph.ph_for_each('[^', :none)}#{num}#{@ph.ph_for(']', :right)}#{after}"
        else
          m
        end
      end
    end

    def restore_textile_lists(text)
      text.gsub!(/#{@ph.match_context_match(TEXTILE_LIST_MATCH_CONTEXT, true)}/) do
        @ph.restore($1, :qtag)
      end
    end

    def restore_textile_hrs(text)
      text.gsub!(/#{@ph.match_context_match(TEXTILE_HR_MATCH_CONTEXT, true)}/) do
        @ph.restore($1, :qtag)
      end
    end


    AUTO_LINK_RE = %r{
      (                          # leading text
        <\w+[^>]*?>|             # leading HTML tag, or
        [\s\(\[,;]|              # leading punctuation, or
        ^                        # beginning of line
      )
      (
        (?:https?://)|           # protocol spec, or
        (?:s?ftps?://)|
        (?:www\.)                # www.*
      )
      (
        ([^<]\S*?)               # url
        (\/)?                    # slash
      )
      ((?:&gt;)?|[^[:alnum:]_\=\/;\(\)]*?) # post
      (?=<|\s|$)
    }x

    # Protect in-link sequences that causes issues to pandoc
    def protect_autolinks(text)
      htmlcoder = HTMLEntities.new
      text.gsub!(AUTO_LINK_RE) do
        all, leading, proto, url, post = $&, $1, $2, $3, $6
        if leading =~ /<a\s/i || leading =~ /![<>=]?/
          # don't replace URLs that are already linked
          # and URLs prefixed with ! !> !< != (textile images)
          all
        else
          urlesc = url.gsub(/[#&_!\[\]\\~-]/) {|m| @ph.ph_for(m, :none, :aftercode)}
          postesc = post.sub(/>/) {|m| @ph.ph_for(htmlcoder.encode(m), :both)}
          "#{leading}#{proto}#{urlesc}#{postesc}"
        end
      end
    end

    def put_breaks_before_html_entities(text)
      text.gsub!(/(?<=[\w\/])(&(?:#(?:[0-9]+|[Xx][0-9A-Fa-f]+)|[A-Za-z0-9]+);)/) do
        start = $1
        "#{@ph.ph_for(nil, :right)}#{start}"
      end
    end

    def protect_hashes textile
      textile.gsub!(/(?<!&)#(?=\w)|(?<=[^\W&])#/) do |m|
        @ph.ph_for(m, :none)
      end
    end

    def put_blank_line_before_pre_in_list(text)
      text.gsub!(/^([*#]+ [^\n]*)(<redpre pre)\b/, "\\1\n\\2")
    end

    def protect_symbols(text)
      # copyright
      text.gsub!(/(?<=\()[cC](?=\))/) do |m|
        @ph.ph_for(m, :none)
      end
    end

    def prefer_inline_code_over_html(text)
      htmlcoder = HTMLEntities.new
      text.gsub!(/<redpre code (\d+)>\s*<\/code>/) do |m|
        prei = $1.to_i
        code = @pre_list[prei].sub(/^<code\b([^>]*)>/, '')
        codeparam = $1
        @pre_list[prei] = "<code>#{code}" if codeparam == ' at'

        code.strip!
        code = htmlcoder.decode(code)

        escpipem = @ph.match_context_match(TABLE_PIPE_MATCH_CONTEXT)
        if code.empty? or code.match? escpipem or (codeparam != ' at' and code.include? "\n")
          # cannot convert to @
          m
        else
          # use placehoder for @
          code.gsub!(/@/) {|m| @ph.ph_for(m, :none)}
          "#{@ph.ph_for(nil, :right)}@#{code}@#{@ph.ph_for(nil, :left)}"
        end
      end
    end

    def protect_eq_sequences(text)
      text.gsub!(/={2,}/) do |m|
        @ph.ph_for_each(m, :both, :qtag)
      end
    end

    ### Postprocessing

    def expand_blockqutes(text)
      qlevel = 0
      skip_empty_line = false
      # eat two NLs before and two NLs or end of file after
      text.gsub!(%r{^((<blockquote>)|((\n)?</blockquote>))?([^\n]*$\n?)}) do
        tag = $1
        tagstart = $2
        tagend = $3
        nl_before_tagend = $4
        regline = $5
        output = ''
        if tag.nil?
          empty_line = regline == "\n"
          separator = qlevel > 0 && !empty_line  ? ' ' : ''
          if skip_empty_line && empty_line
            # nothing
          else
            output = "#{'>' * qlevel}#{separator}#{regline}"
          end
          skip_empty_line = false
        elsif tagend.nil?
          qlevel += 1
          #  if qlevel == 1
          skip_empty_line = true
        else
          # Apparently not needed - keep the list compact
          # output = "#{'>' * qlevel}\n" if nl_before_tagend and (qlevel > 1)
          qlevel -= 1 unless qlevel.zero?
          skip_empty_line = false
        end
        output
      end
    end

    def restore_protected_line_breaks(text)
      text.gsub!(TAG_LINE_BREAK_IN_QTAG, "  \n")
    end

    def md_remove_auxiliary_code_block_lang(text)
      text.gsub!(' ' + TAG_FENCED_CODE_BLOCK, '')
    end

    def restore_context_free_placeholders(text)
      text.gsub!(/#{Placeholders::UNICODE_1CHAR_PRIV_OPTBREAKS_MATCH}/) do |m|
        @ph.restore(m)
      end
    end

    QTAG_CHAR_RESTORE_RE = /
      (?<pre>
        (?<atstart>^[[:blank:]]*)
        |(?<word1>\w)
        |
      )
      (?<ph>#{Placeholders::UNICODE_1CHAR_PRIV_OPTBREAKS_MATCH})
      (?<post>
        (?<word2>\w)
        |
      )
    /x

    def restore_qtag_chars_to_md(text)
      text.gsub!(QTAG_CHAR_RESTORE_RE) do
        pre = $~[:pre]
        post = $~[:post]
        atstart = $~[:atstart]
        inword = $~[:word1] && $~[:word2]
        ph = $~[:ph]
        replaced = @ph.restore(ph, :qtag) do |qtag|
          esc = case qtag
          when '+', '-', '='
            '\\' if atstart
          when '_'
            '\\' unless inword
          when '%'
            nil
          else
            '\\'
          end
          "#{esc}#{qtag}"
        end
        "#{pre}#{replaced}#{post}"
      end
    end

    def md_footnotes(text)
      text.gsub!(/#{@ph.match_context_match(FOOTNOTE_MATCH_CONTEXT, true)}/) do
        num = $1
        if @referenced_footnotes.include? num
          "[^#{num}]:"
        else
          "\\[#{num}\\]"
        end
      end
    end

    def md_separate_lists_redmine_friendly(text)
      text.gsub!(/\n\n<!-- end list -->\n/, "\n\n&#29;\n")
    end

    def md_polish_before_code_restore(text)
      # Escaped exclamation marks look weird in normal text and the only special meaning in MD
      # should be before '['. And Redmine link cancelation works both with ! and \!
      text.gsub!(/\\(!)(?!\[)/, '\\1')
      # Remove MD line break after collapse macro
      text.gsub!(/(\{\{collapse\([^\n]*)[ ]{2}$/, '\\1')
    end

    def restore_aftercode_placeholders(text)
      text.gsub!(/#{Placeholders::UNICODE_1CHAR_PRIV_OPTBREAKS_MATCH}/) do |m|
        @ph.restore(m, :aftercode)
      end
    end

    def smooth_macros(text)
      text.gsub!(/#{@ph.match_context_match(MACRO_MATCH_CONTEXT, true)}/) do
        @ph.restore($1, MACRO_MATCH_CONTEXT)
      end
    end

    def normalize_and_rip_fenced_code_blocks(text)
      # Add newlines around indented fenced blocks to fix in-list code blocks
      # And restore protected sequences that are restored differently in code blocks
      text.gsub!(/^(?'indent1' *)(?'fence'~~~|```)(?'infostr'[^~`\n]*)\n(?'codeblock'(^(?! *\k'fence')[^\n]*\n)*)^(?'indent2' *)\k'fence' *$\n?/m) do
        indent1, fence, infostr, codeblock, indent2 = $~[:indent1], $~[:fence], $~[:infostr], $~[:codeblock], $~[:indent2]
        # keep codeblocks away of further processing
        codeblock = @ph.ph_for(codeblock, :none, FENCED_CODE_BLOCK_MATCH_CONTEXT, :inherit)
        if indent1.empty?
          "#{fence}#{infostr}\n#{codeblock}#{indent2}#{fence}\n"
        else
          "\n#{indent1}#{fence}#{infostr}\n#{codeblock}#{indent2}#{fence}\n\n"
        end
      end
    end

    def smooth_fenced_code_blocks(text)
      text.gsub!(/#{@ph.match_context_match(FENCED_CODE_BLOCK_MATCH_CONTEXT, true)}/) do
        @ph.restore($1, FENCED_CODE_BLOCK_MATCH_CONTEXT)
      end
    end

    def md_use_redmine_underline(text)
      text.gsub!(/<span class="underline">(.*?)<\/span>/m, "_\\1_")
    end

    def remove_init_breakers(text)
      @ph.remove_breakers text, :init
    end

    def md_reformat_tables(text)
      text.gsub!(/(^\|[^\n]+\|$\n)+/m) do |table|
        begin
          table = MarkdownTableFormatter.new(table).to_md
        rescue
          # keep it as it is
          STDERR.puts("[WARNING] #{@reference} - reformatting MD table failed")
        end
        table
      end
    end

    def restore_after_table_reformat_placeholders(text)
      text.gsub!(Placeholders::UNICODE_1CHAR_PRIV_NOBREAKERS_RE) {|ph| @ph.restore(ph, :after_table_reformat)}
      text.gsub!(/#{@ph.match_context_match(TABLE_PIPE_MATCH_CONTEXT, true)}/) do
        @ph.restore($1, TABLE_PIPE_MATCH_CONTEXT)
      end
    end

  end
end
