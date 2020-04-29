$: << File.join(File.dirname(__FILE__), 'lib')

require 'getoptlong'
require 'redmine_reformat/converters/textile_to_markdown/converter'

Dir.chdir(File.join(File.dirname(__FILE__), 'test', 'fixtures', 'textile_to_markdown'))

def temp_file(name, content)
    file = Tempfile.new(name)
    file.write(content)
    file.close
    file.path
end

test_pattern = '*'
show_diff = true
overwrite = false
opts = GetoptLong.new(
  [ '--stdout', '-c', GetoptLong::NO_ARGUMENT ],
  [ '--write-md', '-w', GetoptLong::NO_ARGUMENT ]
)
opts.each do |opt|
  case opt
  when '--stdout'
    show_diff = false
    overwrite = false
  when '--write-md'
    show_diff = false
    overwrite = true
  end
end

test_pattern = ARGV[0] unless ARGV.length.zero?

failed = 0
succeeded = 0
converter = RedmineReformat::Converters::TextileToMarkdown::Converter.new
Dir.glob("#{test_pattern}.textile").each do |textile|
  md = textile.sub(/(\.textile)?$/, '.md')
  md = '/dev/null' unless overwrite or File.exists?(md)
  name = textile.sub(/\.textile$/, '')
  ctx = RedmineReformat::Context.new(ref: name, to_formatting: 'markdown')

  input = File.read(textile)
  actual = converter.convert(input, ctx)

  if show_diff
    expected = File.read(md)
    if actual != expected
      a = temp_file(name, actual)

      STDERR.puts "#{name}: TEST FAILED!"
      STDERR.flush
      puts `colordiff -u #{md} #{a}`
      STDOUT.flush
      failed += 1
    else
      STDERR.puts "#{name}: TEST SUCCESS!"
      STDERR.flush
      succeeded += 1
    end
  else
    out = if overwrite then File.open(md, 'w') else $stdout.dup end
    out.write(actual)
    out.close
  end
end

exit unless show_diff

if failed.zero?
  STDERR.puts "All #{succeeded} tests succeeded."
else
  STDERR.puts "#{failed} of #{succeeded + failed} tests failed."
  exit 1
end
