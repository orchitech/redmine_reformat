$: << File.join(File.dirname(__FILE__), 'lib')

require 'textile_to_markdown/convert_string'

def temp_file(name, content)
    file = Tempfile.new(name)
    file.write(content)
    file.close
    file.path
end

input = File.read('test/fixtures/test.textile')
expected = File.read('test/fixtures/test.md')
actual = TextileToMarkdown::ConvertString.(input)

if actual != expected
  a = temp_file('actual', actual)
  e = temp_file('expected', expected)

  puts `git diff --color #{e} #{a}`
  puts 'TEST FAILED!'
  exit 1
else
  puts 'TEST SUCCESS!'
end
