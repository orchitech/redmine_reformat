task :convert_textile_to_markdown => :environment do
  convert = {
    Comment =>  [:comments],
    WikiContent => [:text],
    Issue =>  [:description],
    Message => [:content],
    News => [:description],
    Document => [:description],
    Project => [:description],
    Journal => [:notes],
  }

  count = 0
  convert.each do |the_class, attributes|
    print the_class.name
    the_class.find_each do |model|
      attributes.each do |attribute|

        textile = model[attribute]
        if textile != nil
          begin
            markdown = convert_textile_to_markdown(textile)
            model.update_column(attribute, markdown)
          rescue => err
            puts "Failed to convert #{model.id}: #{err}"
          end
        end
      end
      count += 1
      print '.'
    end
    puts
  end
  puts "Done converting #{count} models"
end

def convert_textile_to_markdown(textile)
  require 'tempfile'

  # Redmine support @ inside inline code marked with @ (such as "@git@github.com@"), but not pandoc.
  # So we inject a placeholder that will be replaced later on with a real backtick.
  tag_code = 'pandoc-unescaped-single-backtick'
  textile.gsub!(/@([\S]+@[\S]+)@/, tag_code + '\\1' + tag_code)

  # Drop table colspan/rowspan notation ("|\2." or "|/2.") because pandoc does not support it
  # See https://github.com/jgm/pandoc/issues/22
  textile.gsub!(/\|[\/\\]\d\. /, '| ')

  # Drop table alignement notation ("|>." or "|<." or "|=.") because pandoc does not support it
  # See https://github.com/jgm/pandoc/issues/22
  textile.gsub!(/\|[<>=]\. /, '| ')

  # Move the class from <code> to <pre> so pandoc can generate a code block with correct language
  textile.gsub!(/(<pre)(><code)( class="[^"]*")(>)/, '\\1\\3\\2\\4')

  # Inject a class in all <pre> that do not have a blank line before them
  # This is to force pandoc to use fenced code block (```) otherwise it would
  # use indented code block and would very likely need to insert an empty HTML
  # comment "<!-- -->" (see http://pandoc.org/README.html#ending-a-list)
  # which are unfortunately not supported by Redmine (see http://www.redmine.org/issues/20497)
  tag_fenced_code_block = 'force-pandoc-to-ouput-fenced-code-block'
  textile.gsub!(/([^\n]<pre)(>)/, "\\1 class=\"#{tag_fenced_code_block}\"\\2")

  # Force <pre> to have a blank line before them
  # Without this fix, a list of items containing <pre> would not be interpreted as a list at all.
  textile.gsub!(/([^\n])(<pre)/, "\\1\n\n\\2")

  # Some malformed textile content make pandoc run extremely slow,
  # so we convert it to proper textile before hitting pandoc
  # see https://github.com/jgm/pandoc/issues/3020
  textile.gsub!(/-          # (\d+)/, "* \\1")

  src = Tempfile.new('src')
  src.write(textile)
  src.close
  dst = Tempfile.new('dst')
  dst.close

  command = [
    'pandoc',
    '--wrap=preserve',
    '-f',
    'textile',
    '-t',
    'markdown_github',
    src.path,
    '-o',
    dst.path,
  ]
  exec_with_timeout(command.join(" "), 30)

  dst.open
  markdown = dst.read

  # Remove the \ pandoc puts before * and > at begining of lines
  markdown.gsub!(/^((\\[*>])+)/) { $1.gsub("\\", "") }

  # Add a blank line before lists
  markdown.gsub!(/^([^*].*)\n\*/, "\\1\n\n*")

  # Remove the injected tag
  markdown.gsub!(' ' + tag_fenced_code_block, '')

  # Replace placeholder with real backtick
  markdown.gsub!(tag_code, '`')

  # Un-escape Redmine link syntax to wiki pages
  markdown.gsub!('\[\[', '[[')
  markdown.gsub!('\]\]', ']]')

  # Un-escape Redmine quotation mark "> " that pandoc is not aware of
  markdown.gsub!(/(^|\n)&gt; /, "\n> ")

  return markdown
end

def exec_with_timeout(cmd, timeout)
  require 'timeout'
  
  begin
    # stdout, stderr pipes
    rout, wout = IO.pipe
    rerr, werr = IO.pipe
    stdout, stderr = nil

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
  stdout
 end
