# frozen_string_literal: true

# Contains portions of Redmine and Redcloth3 code

require 'open3'
require 'tempfile'
require 'timeout'
require 'securerandom'
require 'htmlentities'
require 'textile_to_markdown/markdown-table-formatter/table-formatter'

module TextileToMarkdown
  class ConvertString
    # receives textile, returns markdown
    def self.call(textile, reference = nil)
      new(textile, reference).call
    end

    def initialize(textile, reference = nil)
      @textile = textile.dup
      @reference = reference
      @fragments = {}
      @placeholders = []
    end

    def call
      return String.new if @textile.empty?
      pre_process_textile @textile

      command = [
        'pandoc',
        '--wrap=preserve',
        '-f',
        'textile-smart',
        '-t',
        'gfm'
      ]

      output = exec_with_timeout(command.join(' '), stdin: @textile)
      post_process_markdown output
    end

    private

    TAG_AT = 'pandocIprotectedIatIsign'
    TAG_HASH = 'pandocIprotectedIhashIsign'
    TAG_EXCLAMATION = 'pandocIprotectedIexclamationImark'
    TAG_FENCED_CODE_BLOCK = 'forceIpandocItoIouputIfencedIcodeIblock'

    TAG_NOTHING = 'pandocInothingIwillIbeIhere'
    TAG_WORD_SEP = '.pandocIwordIseparatorIdoubleIsided.'
    TAG_WORD_SEP_LEFT = '.pandocIwordIseparatorIleft'
    TAG_WORD_SEP_RIGHT = 'pandocIwordIseparatorIright.'
    TAG_TO_EMPTY_RE = [
      TAG_NOTHING, TAG_WORD_SEP, TAG_WORD_SEP_LEFT, TAG_WORD_SEP_RIGHT
    ].map {|ph| Regexp::quote ph}.join('|')

    TAG_DASH_SPACE = 'pandocIprotectedIdashIspace'

    TAG_PH_BEGIN = 'MDCONVERSIONPHxqlrx'
    TAG_PH_END = 'xEND'
    PH_RE = "#{TAG_PH_BEGIN}([0-9]+)#{TAG_PH_END}"
    PH_RE_NOCAP = "#{TAG_PH_BEGIN}[0-9]+#{TAG_PH_END}"

    # not really needed
    def no_textile(text)
      text.gsub!(/(^|\s)==([^=]+.*?)==(\s|$)?/,
                 '\1<notextile>\2</notextile>\3')
      text.gsub!(/^ *==([^=]+.*?)==/m,
                 '\1<notextile>\2</notextile>\3')
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

    def smooth_offtags(text)
      unless @pre_list.empty?
        ## replace <pre> content
        text.gsub!(/<redpre \w+ (\d+)>/) { @pre_list[$1.to_i] }
      end
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
          line
        end
      end
      textile << last_blank_line
    end

    def hard_break(text)
      text.gsub!(/(.)\n(?!\Z| *([#*=]+(\s|$)|[{|]))/, "\\1<br />")
    end
    def revert_hard_break(text)
      text.gsub!(/<br \/>/, "\n")
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
          (#{QTAGS_JOIN}|Bqtag#{PH_RE_NOCAP}Eqtag|)      # oqs
          (#{rcq})              # qtag
          ([[:word:]]|[^\s].*?[^\s])    # content
          (?!\-\-)
          #{rcq}
          (#{QTAGS_JOIN}|Bqtag#{PH_RE_NOCAP}Eqtag|)      # oqa
          (?=[[:punct:]]|<|\s|\)|$)/x
      [rc, newrc, re]
    end

    def inline_textile_span(text)
      QTAGS.each do |qtag_rc, newqtag, qtag_re|
        text.gsub!(qtag_re) do |m|
          sta,oqs,qtag,content,oqa = $~[1..6]
          qtag_ph = make_placeholder(newqtag)
          "#{sta}#{oqs}Bqtag#{qtag_ph}Eqtag#{content}Bqtag#{qtag_ph}Eqtag#{oqa}"
        end
      end
    end

    # Preprocess / protect sequences in offtags and @code@ that are treated differently in interpreted code
    def common_code_pre_process(code)
      # allow for escaping/unescaping these characters in special contexts
      code.gsub!(/[!+_*-]/) do |m|
        "Bword#{make_placeholder(m)}Eword"
      end
    end

    def pre_process_textile(textile)

      clean_white_space textile

      ## Code sections

      # temporarily remove redmine macros (and some other stuff thats better
      # when kept as-is) so they dont get corrupted
      # update: avoided using spaces in the placeholder macro as it can break certain things
      textile.gsub!(/^(!?\{\{(.+?)\}\})/m) do
        all = $1
        if $2 =~ /\A\s*collapse/
          # collapse macro should contain textile, so keep it
          all
        else
          "{{MDCONVERSION#{push_fragment(all)}}}"
        end
      end

      # https://github.com/tckz/redmine-wiki_graphviz_plugin
      textile.gsub!(/^(.*\{\{\s*graphviz_me.*)/m){ "{{MDCONVERSION#{push_fragment($1)}}}" }

      # Do not interfere with protected blocks
      @pre_list = []
      rip_offtags textile, false, false

      # pandoc does not create fenced code blocks when there is leading whitespace
      textile.gsub!(/^[[:blank:]]+(?=<redpre pre\b)/, '')

      # Move the class from <code> to <pre> and remove <code> so pandoc can generate a code block with correct language
      # Allow also for swapping closing offtags, which is tolerated by Redmine
      textile.gsub!(
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
        }xm) do
        md = $~
        codeclose2 = md[:codeclose2]
        codeclose2 = nil if md[:codeopen] and md[:codeclose1].nil?

        offcode1 = md[:offcode1].to_i
        offcode = if md[:offcode2] then md[:offcode2].to_i else offcode1 end

        @pre_list[offcode1] = @pre_list[offcode].sub(/^<(?:code|pre)\b(\s+class="[^"]+")?/) do
          preparam = if $1 then $1 else " class=\"#{TAG_FENCED_CODE_BLOCK}\"" end
          "<pre#{preparam}"
        end
        @pre_list[offcode1] += md[:out] unless md[:out].empty?
        "#{md[:preopen]}</pre>#{codeclose2}#{md[:spacepastpreclose]}"
      end

      escape_html_tags textile
      block_textile_quotes textile

      # make sure that empty lines mean new block
      glue_indented_continuations textile

      # blocks starting with a leading space are either space-indented lists or code blocks
      # pandoc treats them diferrently than Redmine, so remove leading spaces and add <pre> tags for non-lists
      #
      # Update: redmine made its Textile interpreting stricter between 3.4.2 and 3.4.11 and
      # space-indented multi-level lists do not work anymore. This code solves it as a side effect :)
      textile.gsub!(/(\n$\n)^((?: (?!<redpre))+)(.+?)(?=\Z|\n$\n)/m) do
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
        else
          @pre_list << "<pre class=\"#{TAG_FENCED_CODE_BLOCK}\">\n#{code_block}\n"
          "#{prefix}\n<redpre pre #{@pre_list.length - 1}></pre>#{postfix}"
        end
      end

      # Match inline code in RedCloth3 way and address these issues:
      # - Redmine support @ inside inline code marked with @ (such as "@git@github.com@"), but not pandoc.
      # - Redmine's inline code also gets html entities interpreted in Textile, but not in Markdown
      # - some sequences will be pre/postprocessed in normal text - protect them in code
      htmlcoder = HTMLEntities.new
      # replace hard line breaks temporarily to support @multiline code@ matching
      hard_break textile
      textile.gsub!(/(?<!\w)@(?:\|(\w+?)\|)?(.+?)@(?!\w)/) do
        # lang = $1 # lang is ignored even by Redmine
        code = $2

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
      textile.gsub!(/@/, TAG_AT) # all @ that do not demark code
      revert_hard_break textile

      # Preprocess non-interpreted sections for latter postprocessing
      # Placeholders can be protected here
      @pre_list.map! do |code|
        code = code.dup
        common_code_pre_process code
        code
      end

      ## Redmine-interpreted sequences

      # protect wiki links
      # escape following '(', which might be interpreted as MD link
      textile.gsub!(/(!?\[\[[^\]\n\|]+(?:\|[^\]\n\|]+)?\]\])(( *\n? *)\()?/m) do
        wiki_link, parenthesis_after, parenthesis_indent = $1, $2, $3
        if parenthesis_after.nil?
          "{{MDCONVERSION#{push_fragment($&)}}}"
        else
          escaped = "#{wiki_link}#{parenthesis_indent}\\("
          "{{MDCONVERSION#{push_fragment(escaped)}}}"
        end
      end

      # This would be an appropriate place to normalize lists to support Redmine flexible treatment.
      # At this moment:
      # - all list items at the beginning of the line
      # - lists are terminated by a blank line
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
      #
      # redmine also allows mixing # and * in items of mixed lists , which is a common mistake
      # -> let's address this.
      textile.gsub!(/^(([*#])+) /) do |m|
        # last character determines list type
        listprefix = $2 * $1.length
        # make placeholders first to ease offtag character escaping
        "list#{make_placeholder(listprefix)} "
      end

      ## Textile sequences

      # Tables

      # pandoc interprets | as table separator regardles of protecting it by code or notextile tags
      escpipeph = ".Bany#{make_placeholder('&#124;')}Eany."
      textile.gsub!(/^ *\|[^\n]*\| *$/) do |row|
        # pandoc even decodes html entity, making it a cell separator
        row.gsub!(/&#124;|&#[xX]7[cC];/, escpipeph);
        row.gsub!(/(?<stag><redpre (?<htag>#{OFFTAG_TAGS}\b) (?<preid>\d+\b)[^>\n]*>|(?<at>@))(?<content>.*?)(?<etag><\/\k<htag>[^>\n]*>|\k<at>)/) do |offtext|
          stag, content, etag = $~[:stag], $~[:content], $~[:etag]
          at = !!$~[:at]
          have_escape = false
          content.gsub!(/\|/) do
            have_escape = true
            escpipeph
          end

          # protect also ripped offtags
          unless @pre_list.empty?
            offtext.scan(/<redpre \w+ (\d+)>/) do
              @pre_list[$1.to_i].gsub!(/\|/) do
                have_escape = true
                escpipeph
              end
            end
          end
          if have_escape && at
            "<code>#{content}</code>"
          elsif have_escape
            "#{stag}#{content}#{etag}"
          else
            offtext
          end
        end
        row
      end

      # Drop table colspan/rowspan notation ("|\2." or "|/2.") because pandoc does not support it
      # See https://github.com/jgm/pandoc/issues/22
      textile.gsub!(%r{\|[/\\]\d{1,2}\. }, '| ')

      # Drop table alignement notation ("|>." or "|<." or "|=.") because pandoc does not support it
      # See https://github.com/jgm/pandoc/issues/22
      textile.gsub!(/\|[<>=]\. /, '| ')

      # MD requires table header and Textile tables were often with plain cells in bold instead of it
      textile.gsub!(/(?<=\A|\n$\n)^( *\|( *\*[^*|\n]+\* *\| *)+)(?=\Z|\n$\n|\n^ *\|)/m) do
        heading = $1
        heading.gsub!(/\| *\*([^*|\n]+)\*/) do
          header = $1
          "|_. #{header}"
        end
      end

      # Make sure all tables have space in their cells
      textile.gsub!(/^ *\|([^|\n]*\|)+ *$/) do |row|
        row.gsub!(/\|([0-9~:_><=^\\\/]{1,4}\.)?(\s*)(([^|\n])+)/) do
          mod, lspace, content = $1, $2, $3
          lspace = ' ' if lspace.empty?
          content.sub!(/(\S)$/, '\\1 ')
          "|#{mod}#{lspace}#{content}"
        end
        row
      end

      # make placeholderes from real qtags
      hard_break textile
      inline_textile_span textile
      revert_hard_break textile

      # protect qtag characters that pandoc tend to misinterpret
      # (has to be done after unindenting)
      textile.gsub!(/(?<!\|)[*_+-](?!\|)/) do |m|
        out = m
        flavour = case m
          when '+', '-'
            'escatstart'
          when '_'
            'escoutword'
          else
            out = "\\#{m}"
            'any'
          end
       ".B#{flavour}#{make_placeholder(out)}E#{flavour}."
      end

      # parenthesis and curly brackets in qtags get misinterpteted
      textile.gsub!(/(?<=#{TAG_PH_END}Eqtag)[{(]|[})](?=Bqtag#{TAG_PH_BEGIN})/) do |m|
        qtag_ph = ".Bany#{make_placeholder(m)}Eany."
      end

      # restore real qtags for conversion
      textile.gsub!(/Bqtag#{PH_RE}Eqtag/) do
        get_placeholder($1)
      end

      # restore list prefixes
      textile.gsub!(/list#{PH_RE}/) do
        get_placeholder($1)
      end

      # pandoc does not interpret html entities directly following a word, help it
      textile.gsub!(/(?<=[\w\/])(&(?:#(?:[0-9]+|[Xx][0-9A-Fa-f]+)|[A-Za-z0-9]+);)/, "#{TAG_WORD_SEP_RIGHT}\\1");

      # backslash-escaped issue links are ugly and backslash is not necessary
      textile.gsub!(/(?<!&)#(?=\w)|(?<=[^\W&])#/, TAG_HASH)

      # Force <pre> to have a blank line before them in list
      # Without this fix, a list of items containing <pre> would not be interpreted as a list at all.
      textile.gsub!(/^([*#]+ [^\n]*)(<redpre pre)\b/, "\\1\n\\2")

      # Symbols that are interpreted as a regular word
      # Relying on that they are not used in a special context
      textile.gsub!(/\([cC]\)/) do |m|
        "Bword#{make_placeholder(m)}Eword"
      end

      # Prefer inline code using backtics over code html tag (code is already protected as an offtag)
      textile.gsub!(/<redpre code (\d+)>\s*<\/code>/) do |m|
        prei = $1.to_i
        code = @pre_list[prei].sub(/^<code\b([^>]*)>/, '')
        codeparam = $1
        @pre_list[prei] = "<code>#{code}" if codeparam == ' at'

        code.strip!
        code = htmlcoder.decode(code)

        if code.empty? or code.include? escpipeph or (codeparam != ' at' and code.include? "\n")
          # cannot convert to @
          m
        else
          # use placehoder for @
          "#{TAG_WORD_SEP_RIGHT}@#{code.gsub(/@/, TAG_AT)}@#{TAG_WORD_SEP_LEFT}"
        end
      end

      smooth_offtags textile

      textile
    end

    ### Postprocessing

    # eat two NLs before and two NLs or end of file after
    def expand_blockqutes(text)
      qlevel = 0
      skip_empty_line = false
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

    def post_process_markdown(markdown)
      # Reclaim known placeholder sparations
      markdown.gsub!(/\.(?<ph>B(?<flavour>any|escatstart|escoutword)#{PH_RE}E\k<flavour>)(?<mis2>[)])\./) do
        ".#{$~[:ph]}.#{$~[:mis2]}"
      end

      # Remove the \ pandoc puts before * and > at begining of lines
      markdown.gsub!(/^((\\[*>])+)/) { $1.gsub("\\", "") }

      # Remove the injected tag
      markdown.gsub!(' ' + TAG_FENCED_CODE_BLOCK, '')

      # Restore protected sequences that do not differ in code blocks and regular MD
      markdown.gsub!(TAG_AT, '@')
      markdown.gsub!(TAG_HASH, '#')
      markdown.gsub!(TAG_EXCLAMATION, '!')

      markdown.gsub!(/\.Bany#{PH_RE}Eany\./) do
        get_placeholder($1)
      end
      markdown.gsub!(/Bword#{PH_RE}Eword/) do
        get_placeholder($1)
      end
      markdown.gsub!(/(^[[:blank:]]*)?\.Bescatstart#{PH_RE}Eescatstart\./) do
        esc = if $1.nil? then '' else '\\' end
        "#{$1}#{esc}#{get_placeholder($2)}"
      end
      markdown.gsub!(/(?<=\w)\.Bescoutword#{PH_RE}Eescoutword\.(?=\w)/) do
        get_placeholder($1)
      end
      markdown.gsub!(/\.Bescoutword#{PH_RE}Eescoutword\./) do
        "\\#{get_placeholder($1)}"
      end

      # Replace sequence-interpretation placehodler back with nothing
      markdown.gsub!(/#{TAG_TO_EMPTY_RE}/, '')
 
      # Replace <!-- end list --> injected by pandoc because Redmine incorrectly
      # does not supported HTML comments: http://www.redmine.org/issues/20497
      markdown.gsub!(/\n\n<!-- end list -->\n/, "\n\n&#29;\n")

      ## Restore/unescaping sequences that are protected differently in code blocks

      # remove trailing parenthesis which was incorrectly treated as a part of a link
      markdown.gsub!(/(\[[^\]^\n]+\]\([^\s)\n]+)\\\)\)/) do |link|
        "#{$1}))"
      end


      # Unescape URL that could easily get mangled
      markdown.gsub!(%r{(https?://[^\s)]+)}) { |link| link.gsub(/\\([#&])/, "\\1") }

      # Escaped exclamation marks look weird in normal text and the only special meaning in MD
      # should be before '['. And Redmine link cancelation works both with ! and \!
      markdown.gsub!(/\\(!)(?!\[)/, '\\1')

      # Make use of Redmine's underline syntax (span does not work)
      # TODO: allow multiline while protecting code blocks ... but don't have a use case for it now
      markdown.gsub!(/<span class="underline">([^\n]*?)<\/span>/, "_\\1_")

      # Add newlines around indented fenced blocks to fix in-list code blocks
      # And restore protected sequences that are restored differently in code blocks
      markdown.gsub!(/^(?'indent1' *)(?'fence'~~~|```)(?'infostr'[^~`\n]*)\n(?'codeblock'(^(?! *\k'fence')[^\n]*\n)*)^(?'indent2' *)\k'fence' *$\n?/m) do
        indent1, fence, infostr, codeblock, indent2 = $~[:indent1], $~[:fence], $~[:infostr], $~[:codeblock], $~[:indent2]

        ## TODO - adressed by qtag escaping?
        ## codeblock.gsub!(/^#{TAG_DASH_SPACE}/, '- ')
        # make codeblocks easily distinguishable from tables
        codeblock.gsub!(/^/, TAG_NOTHING)

        if indent1.empty?
          res = "#{fence}#{infostr}\n#{codeblock}#{indent2}#{fence}\n"
        else
          res = "\n#{indent1}#{fence}#{infostr}\n#{codeblock}#{indent2}#{fence}\n\n"
        end
      end

      markdown.gsub!(/(^\|[^\n]+\|$\n)+/m) do |table|
        begin
          table = MarkdownTableFormatter.new(table).to_md
        rescue
          # keep it as it is
          STDERR.puts("[WARNING] #{@reference} - reformatting MD table failed")
        end
        table
      end
      markdown.gsub!(/#{TAG_NOTHING}/, '')

      # restore protected sequences that were restored differently in code blocks

      # restore global tags that migh have caused issues if restored earlier
      ## TODO not needed?
      ## markdown.gsub!(/#{TAG_DASH_SPACE}/, '\\- ')

      # restore macro-like protected elements
      markdown.gsub!(/\{\{MDCONVERSION(\w+)\}\}/) { pop_fragment $1 }

      expand_blockqutes markdown

      if markdown =~ /MDCONVERSION|#{TAG_PH_BEGIN}|#{TAG_PH_END}|pandocI|<redpre/
        STDERR.puts("[WARNING] #{@reference} - a placeholder likely leaked to the output MD")
      end

      markdown
    end

    def push_fragment(text)
      SecureRandom.hex.tap do |key|
        @fragments[key] = text
      end
    end

    def pop_fragment(key)
      @fragments.delete key
    end

    def make_placeholder(value)
      key = @placeholders.index(value)
      if key.nil?
        key = @placeholders.length
        @placeholders << value
      end
      "#{TAG_PH_BEGIN}#{key}#{TAG_PH_END}"
    end

    def get_placeholder(key)
      i = key.to_i
      @placeholders[i]
    end

    def exec_with_timeout(cmd, timeout: 10, stdin:)
      pid = nil
      result = nil

      begin
        Timeout.timeout(timeout) do
          Open3.popen2(cmd) do |i, o, t|
            pid = t.pid
            (i << stdin).close
            result = o.read
          end
        end
      rescue Timeout::Error
        Process.kill(-9, pid)
        Process.detach(pid)
        STDERR.puts 'timeout'
      end

      result
    end
  end
end
