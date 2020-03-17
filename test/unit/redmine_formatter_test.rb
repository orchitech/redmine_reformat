require_relative '../test_helper'

class RedmineFormatterTest < ActiveSupport::TestCase
  test "should encode macros" do
    Setting.text_formatting = 'markdown'
    opts = { macros: :encode }
    converter = RedmineReformat::Converters::RedmineFormatter::Converter.new(opts)
    ctx = OpenStruct.new(ref: 'text_with_macro')
    text = "hello {{hello_world}}"
    actual = converter.convert(text, ctx)
    expected = "<p>hello <code>{{</code><code>&quot;hello_world&quot;</code><code>}}</code></p>"
    assert_equal expected, actual.strip
  end
end
