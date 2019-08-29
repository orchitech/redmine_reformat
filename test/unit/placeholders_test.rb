require_relative "../test_helper"
require "textile_to_markdown/redmine_reformat/placeholders.rb"

class PlaceholdersTest < ActiveSupport::TestCase
  test "match_context_match should match the longest occurence" do
    text = '- --'.dup
    ph = Placeholders.new(text)
    ph.prepare_text text
    # TODO
  end
end
