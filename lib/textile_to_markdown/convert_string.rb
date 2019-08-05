# frozen_string_literal: true

require 'open3'
require 'tempfile'
require 'timeout'
require 'securerandom'

module TextileToMarkdown
  class ConvertString

    # receives textile, returns markdown
    def self.call(textile)
      new(textile).call
    end

    def initialize(textile)
      @textile = textile.dup
      @fragments = {}
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

      output = exec_with_timeout(command.join(" "), stdin: @textile)
      return post_process_markdown output
    end


    private

    TAG_AT = 'pandoc-protected-at-sign'
    TAG_HASH = 'pandoc-protected-hash-sign'
    TAG_FENCED_CODE_BLOCK = 'force-pandoc-to-ouput-fenced-code-block'
    TAG_NOTHING = 'pandoc-nothing-will-be-here'
    TAG_DASH_SPACE = 'pandoc-protected-dash-space'

    def pre_process_textile(textile)

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

      # fix line endings
      textile.gsub!(/\r\n?/, "\n")

      # https://github.com/tckz/redmine-wiki_graphviz_plugin
      textile.gsub!(/^(.*\{\{\s*graphviz_me.*)/m){ "{{MDCONVERSION#{push_fragment($1)}}}" }

      # underscores within words get escaped, which causes issues in link detection
      textile.gsub!(/(?<=\w)(_+)(?=\w)/){ "{{MDCONVERSION#{push_fragment($1)}}}" }

      # more subsequent underscores get misinterpreted, prevent that
      textile.gsub!(/(_{2,})/){ "{{MDCONVERSION#{push_fragment($1)}}}" }

      # _(...)_, *(...)* etc. get misinterpreted, prevent that
      textile.gsub!(/(?<!\w)(?'tag'[_+*~-])(?'content'\([^\n]+?\))\k'tag'(?!\w)/){ "#{$~[:tag]}#{TAG_NOTHING}#{$~[:content]}#{TAG_NOTHING}#{$~[:tag]}" }

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

      # Redmine support @ inside inline code marked with @ (such as "@git@github.com@"), but not pandoc.
      # Match inline code in RedCloth3 way and protect enclosed @ signs
      textile.gsub!(/(?<!\w)@(?:\|(\w+?)\|)?(.+?)@(?!\w)/) do
        # lang = $1 # lang is ignored even by Redmine
        "@#{$2.gsub(/@/, TAG_AT)}@"
      end

      # Backslash-escaped issue links are ugly and backslash is not necessary
      textile.gsub!(/#(?=\w)/, TAG_HASH)

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
          if line =~ /^[*#]+ /
            block_start = block_end =''
          end
          line
        end.join("\n")
        "#{prefix}#{block_start}\n#{code_block}#{block_end}#{postfix}"
      end

      # Redmine allows mixing # and * in mixed lists, but not pandoc
      textile.gsub!(/^ *[*#]([*#])+ /) do |m|
        m.gsub(/[*#]/, $1)
      end

      # Move the class from <code> to <pre> and remove <code> so pandoc can generate a code block with correct language
      textile.gsub!(/(<pre\b)\s*(>)\s*<code\b(\s+class="[^"]*")?[^>]*>([\s\S]*?)<\/code>\s*(<\/pre>)/, '\\1\\3\\2\\4\\5')

      # Remove the <code> directly inside <pre>, because pandoc would incorrectly preserve it
      textile.gsub!(/(<pre[^>]*>)<code>/, '\\1')
      textile.gsub!(/<\/code>(<\/pre>)/, '\\1')

      # Inject a class in all <pre> that do not have a blank line before them
      # This is to force pandoc to use fenced code block (```) otherwise it would
      # use indented code block and would very likely need to insert an empty HTML
      # comment "<!-- -->" (see http://pandoc.org/README.html#ending-a-list)
      # which are unfortunately not supported by Redmine (see http://www.redmine.org/issues/20497)
      textile.gsub!(/([^\n\r]\s*<pre\b)\s*(>)/, "\\1 class=\"#{TAG_FENCED_CODE_BLOCK}\"\\2")

      # Force <pre> to have a blank line before them
      # Without this fix, a list of items containing <pre> would not be interpreted as a list at all.
      textile.gsub!(/([^\n][[:blank:]]*)(<pre\b)/, "\\1\n\\2")

      # Drop table colspan/rowspan notation ("|\2." or "|/2.") because pandoc does not support it
      # See https://github.com/jgm/pandoc/issues/22
      textile.gsub!(/\|[\/\\]\d\. /, '| ')

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

      if false
        # update: the following was not obseved with recent pandoc and dashes are not lists in Textile

        # Some malformed textile content make pandoc run extremely slow,
        # so we convert it to proper textile before hitting pandoc
        # see https://github.com/jgm/pandoc/issues/3020
        textile.gsub!(/-          # (\d+)/, "* \\1")

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
      #textile.gsub!(/^ *([^#].*?)\n(#+ )/m, "\\1\n\n\\2")
      #textile.gsub!(/^ *([^*].*?)\n(\*+ )/m, "\\1\n\n\\2")
      return textile
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

      # Replace sequence-interpretation placehodler back with nothing
      markdown.gsub!(TAG_NOTHING, '')

      # Un-escape Redmine quotation mark "> " that pandoc is not aware of
      markdown.gsub!(/(^|\n)&gt; /, "\n> ")

      # Remove <!-- end list --> injected by pandoc because Redmine incorrectly
      # does not supported HTML comments: http://www.redmine.org/issues/20497
      markdown.gsub!(/\n\n<!-- end list -->\n/, "\n")


      # Unescape URL that could easily get mangled
      markdown.gsub!(/(https?:\/\/\S+)/) { |link| link.gsub(/\\([_#&])/, "\\1") }

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

      # Restore protected sequences that are restored differently in code blocks
      markdown.gsub!(/^#{TAG_DASH_SPACE}/, '\\- ')

      # restore macros and other protected elements
      markdown.gsub!(/\{\{MDCONVERSION(\w+)\}\}/){ pop_fragment $1 }

      return markdown
    end

    def push_fragment(text)
      SecureRandom.hex.tap do |key|
        @fragments[key] = text
      end
    end

    def pop_fragment(key)
      @fragments.delete key
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

      return result
    end

  end
end
