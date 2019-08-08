# frozen_string_literal: true

# Contains portions of Redmine and Redcloth3 code

require 'open3'
require 'tempfile'
require 'timeout'
require 'securerandom'
require 'htmlentities'

module TextileToMarkdown
  class ConvertString
    # receives textile, returns markdown
    def self.call(textile)
      new(textile).call
    end

    def initialize(textile)
      @textile = textile.dup
      @fragments = {}
      @placeholders = []
    end

    def call
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

    TAG_AT = 'pandoc-protected-at-sign'
    TAG_HASH = 'pandoc-protected-hash-sign'
    TAG_EXCLAMATION = 'pandoc-protected-exclamation-mark'
    TAG_FENCED_CODE_BLOCK = 'force-pandoc-to-ouput-fenced-code-block'
    TAG_NOTHING = 'pandoc-nothing-will-be-here'
    TAG_DASH_SPACE = 'pandoc-protected-dash-space'
    # trailing character has to be a harmless non-word
    TAG_WORD_HTML_ENTITY_SEP = 'pandoc-separate-html-entity.'

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
      text.gsub!(/"$/, '" ')
    end

    QUOTES_RE = /(^>+([^\n]*?)(\n|$))+/m.freeze
    QUOTES_CONTENT_RE = /^([> ]+)(.*)$/m.freeze

    def block_textile_quotes(text)
      text.gsub!(QUOTES_RE) do |match|
        lines = match.split(/\n/)
        quotes = ''.dup
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

    OFFTAGS = /(code|pre|kbd|notextile)/.freeze
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
      # allow for unescaping
      code.gsub!(/!/, TAG_EXCLAMATION)
    end

    def pre_process_textile(textile)
      clean_white_space textile

      # Do not interfere with protected blocks
      @pre_list = []
      rip_offtags textile, false, false
      escape_html_tags textile

      block_textile_quotes textile

      ## Code sections

      # Move the class from <code> to <pre> and remove <code> so pandoc can generate a code block with correct language
      # Allow also for swapping closing offtags, which is tolerated by Redmine
      textile.gsub!(%r{(<redpre pre (\d+)>\s*)<redpre code (\d+)>(\s*)(</code *>\s*</pre *>|</pre *>\s*</code *>)}) do
        pre = $1
        offcode1, offcode2 = $2.to_i, $3.to_i
        space_after = $4

        if @pre_list[offcode2].match(/^<code\b\s+(class="[^"]*")/)
          @pre_list[offcode1] = @pre_list[offcode2].sub(/^<code\b/, '<pre')
        else
          @pre_list[offcode1] = @pre_list[offcode2].sub(/^<code\b/, "<pre class=\"#{TAG_FENCED_CODE_BLOCK}\"")
        end
        "#{pre}#{space_after}</pre>"
      end

      # Preprocess non-interpreted sections for latter postprocessing
      # Placeholders can be protected here
      @pre_list.map! do |code|
        code = code.dup
        common_code_pre_process code

        # Inject a class in all <pre> that do not have a blank line before them
        # This is to force pandoc to use fenced code block (```) otherwise it would
        # use indented code block and would very likely need to insert an empty HTML
        # comment "<!-- -->" (see http://pandoc.org/README.html#ending-a-list)
        # which are unfortunately not supported by Redmine (see http://www.redmine.org/issues/20497)
        code.sub(/^<pre\b(?!\s*class=)/, "<pre class=\"#{TAG_FENCED_CODE_BLOCK}\"")
      end


      # Match inline code in RedCloth3 way and address these issues:
      # - Redmine support @ inside inline code marked with @ (such as "@git@github.com@"), but not pandoc.
      # - Redmine's inline code also gets html entities interpreted in Textile, but not in Markdown
      # - some sequences will be pre/postprocessed in normal text - protect them in code
      htmlcoder = HTMLEntities.new
      textile.gsub!(/(?<!\w)@(?:\|(\w+?)\|)?(.+?)@(?!\w)/) do
        # lang = $1 # lang is ignored even by Redmine
        code = htmlcoder.decode($2)
        # sanitize dangerous resulting characters
        code.gsub!(/[\r\n]/, ' ')

        common_code_pre_process code

        # use placehoder for @
        "@#{code.gsub(/@/, TAG_AT)}@"
      end

      ## Redmine-interpreted sequences

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

      # https://github.com/tckz/redmine-wiki_graphviz_plugin
      textile.gsub!(/^(.*\{\{\s*graphviz_me.*)/m) { "{{MDCONVERSION#{push_fragment($1)}}}" }

      # blocks starting with a leading space are either space-indented lists or code blocks
      # pandoc treats them diferrently than Redmine, so remove leading spaces and add <pre> tags for non-lists:
      textile.gsub!(/(\A|\n$\n)^( +)(.+?)(?=\Z|\n$\n)/m) do
        prefix = $1
        strip_spaces = $2.length
        postfix = $4
        block_start = "\n<pre>"
        block_end = "\n</pre>"
        code_block = $3.split("\n").map do |line|
          line.sub!(/^ {#{strip_spaces}}/, '')
          block_start = block_end = '' if line =~ /^[*#]+ /
          line
        end.join("\n")
        "#{prefix}#{block_start}\n#{code_block}#{block_end}#{postfix}"
      end

      # redmine allows mixing # and * in mixed lists, but not pandoc
      # and replace list prefixes for now, as they collide with other syntax
      textile.gsub!(/^([*#])+ /) do |m|
        listprefix = $1 * $1.length
        "list#{make_placeholder(listprefix)} "
      end

      ## Textile sequences


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
      inline_textile_span textile

      # protect offtag characters that pandoc tend to misinterpret
      # (has to be done after unindenting)
      textile.gsub!(/(?<!\|)[*_+]+(?!\|)/) do |m|
       ".Bany#{make_placeholder(m)}Eany."
      end

      # parenthesis in qtags get misinterpteted
      textile.gsub!(/(?<=#{TAG_PH_END}Eqtag)\(|\)(?=Bqtag#{TAG_PH_BEGIN})/) do |m|
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
      textile.gsub!(/(?<=[\w\/])(&(?:#(?:[0-9]+|[Xx][0-9A-Fa-f]+)|[A-Za-z0-9]+);)/, "#{TAG_WORD_HTML_ENTITY_SEP}\\1");

      # backslash-escaped issue links are ugly and backslash is not necessary
      textile.gsub!(/(?<!&)#(?=\w)|(?<=[^\W&])#/, TAG_HASH)

      # Force <pre> to have a blank line before them in list
      # Without this fix, a list of items containing <pre> would not be interpreted as a list at all.
      textile.gsub!(/^([*#]+ [^\n]*)(<redpre pre)\b/, "\\1\n\\2")

      if false
        # update: the following was not obseved with recent pandoc and dashes are not lists in Textile

        # Some malformed textile content make pandoc run extremely slow,
        # so we convert it to proper textile before hitting pandoc
        # see https://github.com/jgm/pandoc/issues/3020
        textile.gsub!(/-          # (\d+)/, '* \\1')

        # long sequences of lines with leading dashes make pandoc hang, that's why
        # we turn them into proper unordered lists:
        textile.gsub!(/^(\s*)----(\s+[^-])/, "\\1****\\2")
        textile.gsub!(/^(\s*)---(\s+[^-])/, "\\1***\\2")
        textile.gsub!(/^(\s*)--(\s+[^-])/, "\\1**\\2")
        textile.gsub!(/^(\s*)-(\s+[^-])/, "\\1*\\2")
      else
        # but these lines make pandoc add extra paragraphs, prevent it
        textile.gsub!(/^- /, TAG_DASH_SPACE)
      end

      # add new lines before lists - commented out, as this can break subsequent lists and
      # this should not be necessary - would have not worked even with Textile
      # textile.gsub!(/^ *([^#].*?)\n(#+ )/m, "\\1\n\n\\2")
      # textile.gsub!(/^ *([^*].*?)\n(\*+ )/m, "\\1\n\n\\2")

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
      # Remove the \ pandoc puts before * and > at begining of lines
      markdown.gsub!(/^((\\[*>])+)/) { $1.gsub("\\", "") }

      # Add a blank line before lists
      markdown.gsub!(/^([^*].*)\n\*/, "\\1\n\n*")

      # Remove the injected tag
      markdown.gsub!(' ' + TAG_FENCED_CODE_BLOCK, '')

      # Restore protected sequences that do not differ in code blocks and refular MD
      markdown.gsub!(TAG_AT, '@')
      markdown.gsub!(TAG_HASH, '#')
      markdown.gsub!(/\.Bany#{PH_RE}Eany\./) do
        get_placeholder($1)
      end

      # Replace sequence-interpretation placehodler back with nothing
      markdown.gsub!(TAG_NOTHING, '')
      markdown.gsub!(TAG_WORD_HTML_ENTITY_SEP, '')
 
      # Remove <!-- end list --> injected by pandoc because Redmine incorrectly
      # does not supported HTML comments: http://www.redmine.org/issues/20497
      markdown.gsub!(/\n\n<!-- end list -->\n/, "\n")

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

        codeblock.gsub!(/^#{TAG_DASH_SPACE}/, '- ')

        if indent1.empty?
          "#{fence}#{infostr}\n#{codeblock}#{indent2}#{fence}\n"
        else
          "\n#{indent1}#{fence}#{infostr}\n#{codeblock}#{indent2}#{fence}\n\n"
        end
      end

      # restore protected sequences that were restored differently in code blocks
      markdown.gsub!(/#{TAG_EXCLAMATION}/, '!')

      # restore global tags that migh have caused issues if restored earlier
      markdown.gsub!(/#{TAG_DASH_SPACE}/, '\\- ')

      # restore macro-like protected elements
      markdown.gsub!(/\{\{MDCONVERSION(\w+)\}\}/) { pop_fragment $1 }

      expand_blockqutes markdown

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
        puts 'timeout'
      end

      result
    end
  end
end
