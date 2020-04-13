require_relative '../../test_helper'
require 'redmine_reformat/converters/gfm_editor'

class RedmineReformat::Converters::MarkdownToCommonmark::EditorTest < ActiveSupport::TestCase

  GfmEditor = RedmineReformat::Converters::GfmEditor

  test "should convert byte positions to char positions" do
    inputs = ["a", "ä", "aa", "aä"]
    # make sure the right data is tested
    lengths = [1, 1, 2, 2]
    bytesizes = [1, 2, 2, 3]
    assert_equal lengths, inputs.map { |c| c.length }
    assert_equal bytesizes, inputs.map { |c| c.bytesize }
    inputs.each_with_index do |input, index|
      e = GfmEditor.new(input)
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

  test "should extend code sourcepos to include delimiters" do
    assert_sourcepos [
      ["`foo`", [1, 1], [1, 5]],
      [" `foo\nbar`", [1, 2], [2, 4]],
      [" `foo\n b`", [1, 2], [2, 3]],
      ["`` `foo` ``", [1, 1], [1, 11]],
    ], :code
  end

  test "should use cmark-gfm patch for newline sourcepos and interpret it consistently" do
    assert_sourcepos [
      ["foo\nbar", [1, 4], [1, 4]],
      ["foo\r\nbar", [1, 4], [1, 5]],
      ["* foo\r\nbar", [1, 6], [1, 7]],
    ], :softbreak
  end

  test "should use cmark-gfm fix for strikethrough sourcepos" do
    assert_sourcepos [
      ["~~foo~~", [1, 1], [1, 7]],
      ["~~foo\n~~", [1, 1], [2, 2]],
      ["~~foo\nbar baz~~", [1, 1], [2, 9]],
      ["~~f#{'o'*3000}o\nbar~~", [1, 1], [2, 5]],
      ["~~foo\nb#{'a'*3000}r~~", [1, 1], [2, 3004]],
    ], :strikethrough
  end

  private
  def assert_sourcepos(cases, nodetype)
    cases.each do |input, expected_startpos, expected_endpos|
      e = GfmEditor.new(input)
      e.document.walk do |node|
        next unless node.type == nodetype
        spos = e.sourcepos(node)
        msg = "of #{nodetype} did not match for '#{input}'"
        assert_equal expected_startpos, spos.startpos, "startpos #{msg}"
        assert_equal expected_endpos, spos.endpos, "endpos #{msg}"
      end
    end
  end
end
