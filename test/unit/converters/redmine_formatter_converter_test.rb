require_relative '../../test_helper'

class RedmineReformat::Converters::RedmineFormatterConverterTest < ActiveSupport::TestCase
  Converter = RedmineReformat::Converters::RedmineFormatter::Converter
  Context = RedmineReformat::Context

  def setup
    Setting.text_formatting = 'markdown'
    @ctx = Context.new(ref: @NAME)
  end

  test "should preserve macros" do
    converter = Converter.new
    text = "hello {{hello_world}}"
    expected = "<p>hello {{hello_world}}</p>"
    assert_equal expected, converter.convert(text, @ctx).strip
  end

  test "should encode macros" do
    converter = Converter.new({macros: :encode})
    text = "hello {{hello_world}}"
    expected = "<p>hello <code>{{</code><code>&quot;hello_world&quot;</code><code>}}</code></p>"
    assert_equal expected, converter.convert(text, @ctx).strip
  end

  test "should preserve macro-like strings within code" do
    converter = Converter.new({macros: :encode})
    text = "`hello {{hello_world}}`"
    expected = "<p><code>hello {{hello_world}}</code></p>"
    assert_equal expected, converter.convert(text, @ctx).strip
  end
end
