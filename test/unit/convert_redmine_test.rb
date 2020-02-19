require_relative '../test_helper'

class ConvertRedmineTest < ActiveSupport::TestCase
  fixtures :projects,
           :users, :email_addresses, :user_preferences,
           :roles, :members, :member_roles,
           :issues, :issue_statuses, :issue_relations,
           :versions,
           :trackers,
           :projects_trackers,
           :issue_categories,
           :enabled_modules,
           :enumerations,
           :attachments,
           :workflows,
           :custom_fields, :custom_values, :custom_fields_projects,
           :custom_fields_trackers,
           :time_entries,
           :journals, :journal_details,
           :queries,
           :repositories, :changesets,
           :wikis, :wiki_pages, :wiki_contents,
           :wiki_content_versions


  test "should convert redmine" do
    @textile = IO.read File.join(File.dirname(__FILE__), "../fixtures/textile_to_markdown/test.textile")
    @md = IO.read(File.join(File.dirname(__FILE__), "../fixtures/textile_to_markdown/test.md")).gsub(/\r?\n/, "\r\n")

    Setting.text_formatting = 'textile'
    Setting.welcome_text = "h1. Welcome\n\nLorem ipsum\n"
    Issue.find(1).update_column :description, @textile
    v = WikiContent::Version.find(1)
    v.update_attributes compression: 'gzip', text: @textile

    invoker = RedmineReformat::Invoker.new(to_formatting: 'markdown')
    invoker.run

    assert_equal "# Welcome\r\n\r\nLorem ipsum\r\n", Setting.welcome_text
    assert_equal @md, Issue.find(1).description
    assert_equal @md, WikiContent::Version.find(1).text

    assert_equal 'markdown', Setting.text_formatting
  end
end
