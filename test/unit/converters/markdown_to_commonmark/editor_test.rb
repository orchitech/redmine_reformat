require_relative '../../../test_helper'
require 'redmine_reformat/converters/markdown_to_commonmark/editor'

class RedmineReformat::Converters::MarkdownToCommonmark::EditorTest < ActiveSupport::TestCase

  Editor = RedmineReformat::Converters::MarkdownToCommonmark::Editor

  test "should convert byte positions to char positions" do
    inputs = ["a", "ä", "aa", "aä"]
    # make sure the right data is tested
    lengths = [1, 1, 2, 2]
    bytesizes = [1, 2, 2, 3]
    assert_equal lengths, inputs.map { |c| c.length }
    assert_equal bytesizes, inputs.map { |c| c.bytesize }
    inputs.each_with_index do |input, index|
      e = Editor.new(input)
      e.document.walk do |n|
        # make sure commonmarker behavior has not changed
        cmark_start = [:start_line, :start_column].map { |k| n.sourcepos[k] }
        cmark_end = [:end_line, :end_column].map { |k| n.sourcepos[k] }
        assert_equal [1, 1], cmark_start
        assert_equal [1, bytesizes[index]], cmark_end

        # make sure we have dealt with it right
        spos = e.sourcepos(n)
        assert_equal [1, 1], spos.startpos
        assert_equal [1, lengths[index]], spos.endpos
      end
    end
  end

  test "should deal with cmark-gfm broken reporting of code sourcepos" do
    # implemented, but rather decided to use patched commonmarker first
    # https://github.com/commonmark/cmark/pull/298https://github.com/commonmark/cmark/pull/298
  end

  test "should deal with cmark-gfm broken reporting of underline sourcepos" do
    cases = [
      # input, broken endpos, fixed endpos
      ["~~foo~~", [1, 7], [1, 7]],
      ["~~foo\n~~", [1, 2], [2, 2]],
      ["~~foo\nbar baz~~", [1, 9], [2, 9]],
      ["~~f#{'o'*3000}o\nbar~~", [1, 5], [2, 5]],
      ["~~foo\nb#{'a'*3000}r~~", [1, 3004], [2, 3004]],
    ]
    cases.each do |input, broken_endpos, fixed_endpos|
      e = Editor.new(input)
      e.document.walk do |n|
        next unless n.type == :strikethrough
        # make sure commonmarker behavior has not changed
        cmark_start = [:start_line, :start_column].map { |k| n.sourcepos[k] }
        cmark_end = [:end_line, :end_column].map { |k| n.sourcepos[k] }
        assert_equal [1, 1], cmark_start
        assert_equal broken_endpos, cmark_end

        # make sure we have dealt with it right
        spos = e.sourcepos(n)
        assert_equal [1, 1], spos.startpos
        assert_equal fixed_endpos, spos.endpos
      end
    end
  end
end
