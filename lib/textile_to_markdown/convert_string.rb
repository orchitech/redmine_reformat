# frozen_string_literal: true

require 'tempfile'
require 'timeout'

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

      src = Tempfile.new('src')
      src.binmode
      src.write(@textile)
      src.close
      dst = Tempfile.new('dst')
      dst.close

      command = [
        'pandoc',
        '--wrap=preserve',
        '-f',
        'textile',
        '-t',
        'gfm+smart',
        src.path,
        '-o',
        dst.path,
      ]
      exec_with_timeout(command.join(" "), 30)

      dst.open
      return post_process_markdown dst.read
    end


    private

    TAG_CODE = 'pandoc-unescaped-single-backtick'
    TAG_FENCED_CODE_BLOCK = 'force-pandoc-to-ouput-fenced-code-block'

    def pre_process_textile(textile)

      # temporarily remove redmine macros (and some other stuff thats better
      # when kept as-is) so they dont get corrupted
      textile.gsub!(/^(!?\{\{(.+?)\}\})/m) do
        all = $1
        if $2 =~ /\A\s*collapse/
          # collapse macro should contain textile, so keep it
          all
        else
          "{{MDCONVERSION #{push_fragment(all)}}}"
        end
      end

      # fix line endings
      textile.gsub!(/\r\n?/, "\n")

      # https://github.com/tckz/redmine-wiki_graphviz_plugin
      textile.gsub!(/^(.*\{\{\s*graphviz_me.*)/m){ "{{MDCONVERSION #{push_fragment($1)}}}" }

      # _(.*)_ gets misinterpreted, prevent that
      textile.gsub!(/(_\([^\n]+?\)_)/){ "{{MDCONVERSION #{push_fragment($1)}}}" }

      # Redmine support @ inside inline code marked with @ (such as "@git@github.com@"), but not pandoc.
      # So we inject a placeholder that will be replaced later on with a real backtick.
      textile.gsub!(/@([\S]+@[\S]+)@/, TAG_CODE + '\\1' + TAG_CODE)

      # wrap blocks starting with a leading space in <pre> tags since Redmine's
      # textile treats them as code, however pandoc does not:
      textile.gsub!(/(\A|\n$\n)^( +)(.+?)(\Z|\n$\n)/m) do
        prefix = $1
        strip_spaces = $2.length
        postfix = $4
        code_block = $3.split("\n").map do |line|
          line.sub(/^ {#{strip_spaces}}/, '')
        end.join("\n")
        "#{prefix}\n<pre>\n#{code_block}\n</pre>#{postfix}"
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
      textile.gsub!(/([^\n\r]\s*)(<pre\b)/, "\\1\n\n\\2")

      # Drop table colspan/rowspan notation ("|\2." or "|/2.") because pandoc does not support it
      # See https://github.com/jgm/pandoc/issues/22
      textile.gsub!(/\|[\/\\]\d\. /, '| ')

      # Drop table alignement notation ("|>." or "|<." or "|=.") because pandoc does not support it
      # See https://github.com/jgm/pandoc/issues/22
      textile.gsub!(/\|[<>=]\. /, '| ')

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

      # add new lines before lists
      textile.gsub!(/^ *([^#].*?)\n(#+ )/m, "\\1\n\n\\2")
      textile.gsub!(/^ *([^*].*?)\n(\*+ )/m, "\\1\n\n\\2")


      return textile
    end



    def post_process_markdown(markdown)
      # Remove the \ pandoc puts before * and > at begining of lines
      markdown.gsub!(/^((\\[*>])+)/) { $1.gsub("\\", "") }

      # Add a blank line before lists
      markdown.gsub!(/^([^*].*)\n\*/, "\\1\n\n*")

      # Remove the injected tag
      markdown.gsub!(' ' + TAG_FENCED_CODE_BLOCK, '')

      # Replace placeholder with real backtick
      markdown.gsub!(TAG_CODE, '`')

      # Un-escape Redmine link syntax to wiki pages
      markdown.gsub!('\[\[', '[[')
      markdown.gsub!('\]\]', ']]')

      # Un-escape Redmine quotation mark "> " that pandoc is not aware of
      markdown.gsub!(/(^|\n)&gt; /, "\n> ")

      # Remove <!-- end list --> injected by pandoc because Redmine incorrectly
      # does not supported HTML comments: http://www.redmine.org/issues/20497
      markdown.gsub!(/\n\n<!-- end list -->\n/, "\n")


      # Unescape URL that could easily get mangled
      markdown.gsub!(/(https?:\/\/\S+)/) { |link| link.gsub(/\\([_#])/, "\\1") }

      # restore macros
      markdown.gsub!(/\{\{MDCONVERSION (\w+)\}\}/){ pop_fragment $1 }

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

    def exec_with_timeout(cmd, timeout)
      begin
        # stdout, stderr pipes
        rout, wout = IO.pipe
        rerr, werr = IO.pipe
        stdout = nil
        stderr = nil

        pid = Process.spawn(cmd, pgroup: true, :out => wout, :err => werr)

        Timeout.timeout(timeout) do
          Process.waitpid(pid)

          # close write ends so we can read from them
          wout.close
          werr.close

          stdout = rout.readlines.join
          stderr = rerr.readlines.join
        end

      rescue Timeout::Error
        Process.kill(-9, pid)
        Process.detach(pid)
        raise "timed out"
      ensure
        wout.close unless wout.closed?
        werr.close unless werr.closed?
        # dispose the read ends of the pipes
        rout.close
        rerr.close
      end
      puts stderr if stderr && stderr.length > 0
      stdout
    end
  end
end
