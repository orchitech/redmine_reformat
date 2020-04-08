require 'ostruct'
require_relative '../../../test_helper'
require 'redmine_reformat/converters/markdown_to_commonmark/converter'

class RedmineReformat::Converters::MarkdownToCommonmark::ConverterTest < ActiveSupport::TestCase

  def setup
    @converter = RedmineReformat::Converters::MarkdownToCommonmark::Converter.new
    @ctx = OpenStruct.new(ref: self.class.name, to_formatting: 'common_mark')
  end

  test "should convert soft breaks to hard breaks" do
    # and should preserve line ends too
    text = "foo\r\nbar  \nbaz\n\nfoo"
    expected = "foo  \r\nbar  \nbaz\n\nfoo"
    assert_equal expected, @converter.convert(text, @ctx)
  end

  test "should convert unerscore underlines" do
    text = "foo_bar_ _foo_ *_foo bar_* _*foo*_\n\n___\n"
    expected = "foo_bar_ <ins>foo</ins> *<ins>foo bar</ins>* <ins>*foo*</ins>\n\n___\n"
    assert_equal expected, @converter.convert(text, @ctx)
  end

  test "should convert superscript carets" do
    text = "foo^bar foo^bar^baz foo^(*bar*) foo^(no\\ baz"
    expected = "foo<sup>bar</sup> foo<sup>bar<sup>baz</sup></sup> foo<sup>*bar*</sup> foo<sup>no\\\\</sup>baz"
    assert_equal expected, @converter.convert(text, @ctx)
  end

  test "should terminate superscript by left-bound inlines" do
    text = "*foo^(bar*.baz)* *foo^bar*.baz"
    expected = "*foo^(bar*.baz)* *foo<sup>bar</sup>*.baz"
    assert_equal expected, @converter.convert(text, @ctx)
  end

  test "should escape delimiter chars to prevent their binding to subsequent text" do
    text = "foo^(*bar) baz*"
    expected = "foo<sup>\\*bar</sup> baz*"
    assert_equal expected, @converter.convert(text, @ctx)
  end

  test "should mimick weird Redcarpet superscript backslash behavior" do
    # users are not very disciplined at using backticks
    text = "your password: foo^(bar\\x"
    # it should still be possible to guess it at least
    expected = "your password: foo<sup>bar\\\\<!-- x --></sup>"
    assert_equal expected, @converter.convert(text, @ctx)
  end

  test "should respect code" do
    text = "_baz `_foo_ foo^bar foo\nbar` zab_"
    expected = "<ins>baz `_foo_ foo^bar foo\nbar` zab</ins>"
    assert_equal expected, @converter.convert(text, @ctx)
  end

  test "should respect code block" do
    text = "_foo_\n\n```\n_foo_ foo^bar foo\nbar\n```\nfoo^bar"
    expected = "<ins>foo</ins>\n\n```\n_foo_ foo^bar foo\nbar\n```\nfoo<sup>bar</sup>"
    assert_equal expected, @converter.convert(text, @ctx)
  end

  test "should respect macro" do
    text = "{{hello_world(_foo_ foo^bar)}}"
    assert_equal text, @converter.convert(text, @ctx)
    text = "{{hello_world(_foo_ foo^bar)\n_foo_ foo^bar\n}}"
    assert_equal text, @converter.convert(text, @ctx)
  end

  test "should convert text in collapse macro but protect its delimiting newlines" do
    text = "{{collapse(_foo_ foo^bar)\n_foo_\nfoo^bar\n}}\n}}\nfoo"
    expected = "{{collapse(_foo_ foo^bar)\n<ins>foo</ins>  \nfoo<sup>bar</sup>\n}}  \n}}  \nfoo"
    assert_equal expected, @converter.convert(text, @ctx)
  end
end
