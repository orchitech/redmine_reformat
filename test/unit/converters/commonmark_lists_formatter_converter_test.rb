require_relative '../../test_helper'

class RedmineReformat::Converters::CommonmarkListFormatterConverterTest < ActiveSupport::TestCase
  Converter = RedmineReformat::Converters::CommonmarkListFormatter::Converter
  Context = RedmineReformat::Context

  def setup
    Setting.text_formatting = 'common_mark'
    @ctx = Context.new(ref: @NAME, project_id: 1)
  end

  test "should minimize indenting from pandoc output" do
    converter = Converter.new
    text = <<-TEXT.strip_heredoc
    # OL in OL
    1.  numberedList
        1.  indented

    # UL in UL
      - bulletlist
          - indented
      - bullet 2
    TEXT
    expected = <<-EXPECTED.strip_heredoc
    # OL in OL
    1. numberedList
       1. indented

    # UL in UL
    * bulletlist
      * indented
    * bullet 2
    EXPECTED
    assert_equal expected, converter.convert(text, @ctx)
  end

  test "should deal with inequally indented and deeply nested lists" do
    converter = Converter.new
    text = <<-TEXT.strip_heredoc
    # UL
      -   foo
       - bar
           - baz
        x
                - qux
                 - not an item
                - item
    # OL / UL
     -  foo
        1.  bar
        99.  baz
                - qux1
        100.  baz
               - qux2
    TEXT
    expected = <<-EXPECTED.strip_heredoc
    # UL
    * foo
    * bar
      * baz
        x
        * qux
            - not an item
        * item
    # OL / UL
    * foo
      1. bar
      99. baz
          * qux1
      100. baz
           * qux2
    EXPECTED
    assert_equal expected, converter.convert(text, @ctx)
  end

  test "should deal with lists inside blockquote" do
    converter = Converter.new
    text = <<-TEXT.strip_heredoc
    >   - foo
    >     bar
    >   - baz
    TEXT
    expected = <<-EXPECTED.strip_heredoc
    > * foo
    >   bar
    > * baz
    EXPECTED
    assert_equal expected, converter.convert(text, @ctx)
  end

  test "should survive pure sublist despite not supported" do
    converter = Converter.new
    text = <<-TEXT.strip_heredoc
    Choose:
      - /
      - -
      - .
    TEXT
    expected = <<-EXPECTED.strip_heredoc
    Choose:
    * /
    * -
    * .
    EXPECTED
    assert_equal expected, converter.convert(text, @ctx)
  end
end
