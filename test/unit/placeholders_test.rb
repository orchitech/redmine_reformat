require_relative '../test_helper'
require 'redmine_reformat/converters/placeholders'

class PlaceholdersTest < ActiveSupport::TestCase
  test "match_context_match should match the longest occurence" do
    text = '- --'.dup
    ph = RedmineReformat::Converters::Placeholders.new(text)
    ph.prepare_text text
    # TODO
  end
end
