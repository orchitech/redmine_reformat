# frozen_string_literal: true

# Contains portions of Redmine and Redcloth3 code

require 'set'
require 'open3'
require 'tempfile'
require 'timeout'
require 'securerandom'
require 'htmlentities'
require 'textile_to_markdown/redmine_reformat'
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
    include TextileToMarkdown::RedmineReformat

    TAG_AT = 'pandocIprotectedIatIsign' #TBD remove
    TAG_HASH = 'pandocIprotectedIhashIsign'
    TAG_FENCED_CODE_BLOCK = 'pandocIforceItoIouputIfencedIcodeIblock' #TBD remove
    TAG_BREAK_NOTEXTILE_2EQS = 'pandocIbreakInotextileI2eqs'

    TAG_NOTHING = 'pandocInothingIwillIbeIhere'
    TAG_WORD_SEP = '.pandocIwordIseparatorIdoubleIsided.'
    TAG_WORD_SEP_LEFT = '.pandocIwordIseparatorIleft'
    TAG_WORD_SEP_RIGHT = 'pandocIwordIseparatorIright.'
    TAG_TO_EMPTY_RE = [
      TAG_NOTHING, TAG_WORD_SEP, TAG_WORD_SEP_LEFT, TAG_WORD_SEP_RIGHT
    ].map {|ph| Regexp::quote ph}.join('|')

    TAG_PH_BEGIN = 'MDCONVERSIONPHxqlrx'
    TAG_PH_END = 'xEND'
    PH_RE = "#{TAG_PH_BEGIN}([0-9]+)#{TAG_PH_END}"
    PH_RE_NOCAP = "#{TAG_PH_BEGIN}[0-9]+#{TAG_PH_END}"

    # Preprocess / protect sequences in offtags and @code@ that are treated differently in interpreted code
    def common_code_pre_process(code)
      # allow for escaping/unescaping these characters in special contexts
      code.gsub!(/[!+_*{}\[\]-]/) do |m|
        "Bcodeword#{make_placeholder(m)}Ecodeword"
      end
    end



    def pre_process_textile(textile)

      clean_white_space textile
      initialize_reformatter textile
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
      rip_offtags textile, false, false
      unindent_pre_offtag textile

      # Move the class from <code> to <pre> and remove <code>, so pandoc can generate a code block with correct language
      merge_pre_code_offtags textile

      no_textile textile
      escape_html_tags textile
      block_textile_quotes textile

      # strip surrounding whitespace, which is allowed by Redmine, but would break further processing
      # temprarily placeholderize at the same time to avoid confusion with 'free qtags'
      normalize_hr_to_phs textile

      # make sure that empty lines mean new block
      glue_indented_continuations textile

      # extrect indented code and unindent lists
      process_indented_blocks textile

      # replace hard line breaks temporarily to support @multiline code@ and avoid "multi line":links
      hard_break textile
      inline_textile_link textile # avoid misinterpeation of invalid link-like sequences
      inline_textile_code textile # offtagize inline code
      revert_hard_break textile

      # Preprocess non-interpreted sections for latter postprocessing
      # Placeholders can be protected here
      @pre_list.map! do |code|
        code = code.dup
        common_code_pre_process code
        code
      end

      ## Redmine-interpreted sequences
      protect_wiki_links textile
      normalize_lists_to_phs textile

      ## Textile sequences
      # Tables
      protect_pipes_in_tables textile
      drop_unsupported_table_features textile
      guess_table_headers textile
      pad_table_cells textile

      # make placeholderes from real qtags
      hard_break textile
      inline_textile_span_to_phs textile
      revert_hard_break textile

      # protect qtag characters that pandoc tend to misinterpret
      # (has to be done after unindenting)
      protect_autolinks textile

      protect_qtag_surroundings textile
      restore_real_qtags textile

      ## restore constructs that use qtag characters
      restore_textile_lists textile
      restore_textile_hrs textile

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
      htmlcoder = HTMLEntities.new
      textile.gsub!(/<redpre code (\d+)>\s*<\/code>/) do |m|
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
          "#{TAG_WORD_SEP_RIGHT}@#{code.gsub(/@/, TAG_AT)}@#{TAG_WORD_SEP_LEFT}"
        end
      end

      # prevent sequences of = to be interpreted as <notextile>, see #no_textile
      textile.gsub!(/={2,}/) do |m|
        m.gsub('=', "=#{TAG_BREAK_NOTEXTILE_2EQS}")
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
    def post_process_markdown(markdown)
      markdown.gsub!(TAG_LINE_BREAK_IN_QTAG, "  \n")
      markdown.gsub!(/^([[:blank:]]*)=#{TAG_BREAK_NOTEXTILE_2EQS}/, '\\1\\=')
      markdown.gsub!("=#{TAG_BREAK_NOTEXTILE_2EQS}", '=')
      # Reclaim known placeholder sparations
      markdown.gsub!(/\.(?<ph>B(?<flavour>any|escatstart|escoutword)#{PH_RE}E\k<flavour>)(?<mis2>[)])\./) do
        ".#{$~[:ph]}.#{$~[:mis2]}"
      end

      ## TODO: probably undesired
      ### Remove the \ pandoc puts before > at begining of lines
      ### markdown.gsub!(/^((\\[>])+)/) { $1.gsub("\\", "") }

      # Remove the injected tag
      markdown.gsub!(' ' + TAG_FENCED_CODE_BLOCK, '')

      ############ default restores go here
      # Restore protected sequences that do not differ in code blocks and regular MD
      markdown.gsub!(TAG_AT, '@')
      markdown.gsub!(TAG_HASH, '#')

      markdown.gsub!(/\.Bany#{PH_RE}Eany\./) do
        get_placeholder($1)
      end
      markdown.gsub!(/Bword#{PH_RE}Eword/) do
        get_placeholder($1)
      end

      markdown.gsub!(QTAG_CHAR_RESTORE_RE) do
        pre = $~[:pre]
        post = $~[:post]
        atstart = $~[:atstart]
        inword = $~[:word1] && $~[:word2]
        ph = $~[:ph]
        replaced = @ph.restore(ph) do |qtag|
          esc = case qtag
          when '+', '-'
            '\\' if atstart
          when '_'
            '\\' unless inword
          else
            '\\'
          end
          "#{esc}#{qtag}"
        end
        "#{pre}#{replaced}#{post}"
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

      # Escaped exclamation marks look weird in normal text and the only special meaning in MD
      # should be before '['. And Redmine link cancelation works both with ! and \!
      markdown.gsub!(/\\(!)(?!\[)/, '\\1')

      # Remove MD line break after collapse macro
      markdown.gsub!(/(\{\{collapse\([^\n]*)[ ]{2}$/, '\\1')

      # Replace code placeholders *after* the playing with the text
      markdown.gsub!(/Bcodeword#{PH_RE}Ecodeword/) do
        get_placeholder($1)
      end

      # Make use of Redmine's underline syntax (span does not work)
      # TODO: allow multiline while protecting code blocks ... but don't have a use case for it now
      markdown.gsub!(/<span class="underline">(.*?)<\/span>/m, "_\\1_")

      # Add newlines around indented fenced blocks to fix in-list code blocks
      # And restore protected sequences that are restored differently in code blocks
      markdown.gsub!(/^(?'indent1' *)(?'fence'~~~|```)(?'infostr'[^~`\n]*)\n(?'codeblock'(^(?! *\k'fence')[^\n]*\n)*)^(?'indent2' *)\k'fence' *$\n?/m) do
        indent1, fence, infostr, codeblock, indent2 = $~[:indent1], $~[:fence], $~[:infostr], $~[:codeblock], $~[:indent2]

        # make codeblocks easily distinguishable from tables
        codeblock.gsub!(/^/, TAG_NOTHING)

        if indent1.empty?
          res = "#{fence}#{infostr}\n#{codeblock}#{indent2}#{fence}\n"
        else
          res = "\n#{indent1}#{fence}#{infostr}\n#{codeblock}#{indent2}#{fence}\n\n"
        end
      end

      # restore protected sequences that were restored differently in code blocks

      # restore global tags that migh have caused issues if restored earlier

      # restore macro-like protected elements
      # links
      markdown.gsub!(/\{\{MDCONVERSION(\w+)\}\}/) { pop_fragment $1 }
      # and the eventual placeholders in them
      markdown.gsub!(TAG_AT, '@')

      # table reformatting depends on final character count in table cells
      markdown.gsub!(/(^\|[^\n]+\|$\n)+/m) do |table|
        begin
          table = MarkdownTableFormatter.new(table).to_md
        rescue
          # keep it as it is
          STDERR.puts("[WARNING] #{@reference} - reformatting MD table failed")
        end
        table
      end

      # unmark code blocks
      markdown.gsub!(/#{TAG_NOTHING}/, '')

      # restore placeholders preserving text length
      markdown.gsub!(Placeholders::UNICODE_1CHAR_PRIV_NOBREAKERS_RE) {|ph| @ph.restore(ph, :after_table_reformat)}
      markdown.gsub!(/#{@ph.match_context_match(TABLE_PIPE_MATCH_CONTEXT, nil)}/) do
        @ph.restore($1, TABLE_PIPE_MATCH_CONTEXT)
      end
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
