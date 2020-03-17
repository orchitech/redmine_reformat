require 'ostruct'
require_relative '../test_helper'
require 'redmine_reformat/converters/textile_to_markdown/converter'

class TextileToMarkdownConverterTest < ActiveSupport::TestCase

  test "should convert textile to markdown (general test case)" do
    check_conversion "test"
  end

  test "should convert textile to markdown - inline formatting" do
    check_conversion "text_formatting"
  end

  test "should convert textile to markdown - tables" do
    check_conversion "tables"
  end

  test "should convert textile to markdown - lists" do
    check_conversion "lists"
  end

  test "should convert textile to markdown - code blocks" do
    check_conversion "code_blocks"
  end

  test "should convert textile to markdown - macros" do
    check_conversion "macros"
  end

  # https://github.com/tckz/redmine-wiki_graphviz_plugin
  test "should convert textile to markdown - graphviz_me macro" do
    check_conversion "graphviz_me"
  end

  def check_conversion(name)
    source = File.join(File.dirname(__FILE__), "../fixtures/textile_to_markdown/#{name}.textile")
    converter = RedmineReformat::Converters::TextileToMarkdown::Converter.new

    ctx = OpenStruct.new(ref: name, to_formatting: 'markdown')
    actual = converter.convert(IO.read(source), ctx)
    expected = IO.read(source.sub(/textile\z/, 'md'))
    assert_equal expected, actual
  end
end
