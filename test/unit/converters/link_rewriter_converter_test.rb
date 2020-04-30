require_relative '../../test_helper'

class RedmineReformat::Converters::LinkRewriterConverterTest < ActiveSupport::TestCase
  fixtures :projects, :wikis, :wiki_pages
  Converter = RedmineReformat::Converters::LinkRewriter::Converter
  Context = RedmineReformat::Context

  def setup
    Setting.text_formatting = 'markdown'
    @wiki_link_rewrites = {
      'ecookbook' => {page_prefix: 'NewBook'},
    }
    @ctx = Context.new(ref: @NAME, project_id: 1)
  end

  test "should process real wiki links" do
    converter = Converter.new(@wiki_link_rewrites)
    text = "hello #1 [[Page_with_an_inline_image]] [[Foo]] `[[Page_with_an_inline_image]]`"
    expected = "hello #1 [[NewBookPage_with_an_inline_image]] [[Foo]] `[[Page_with_an_inline_image]]`"
    assert_equal expected, converter.convert(text, @ctx)
  end

  test "should execute collapse macro" do
    converter = Converter.new(@wiki_link_rewrites)
    text = "[[Page_with_an_inline_image]] {{collapse\n[[Page_with_an_inline_image]]\n}}\n"
    expected = "[[NewBookPage_with_an_inline_image]] {{collapse\n[[NewBookPage_with_an_inline_image]]\n}}\n"
    assert_equal expected, converter.convert(text, @ctx)
  end

  test "should respect linked project" do
    converter = Converter.new(@wiki_link_rewrites)
    @ctx.project_id = nil
    text = "[[ecookbook:Page_with_an_inline_image]] [[Page_with_an_inline_image]]"
    expected = "[[ecookbook:NewBookPage_with_an_inline_image]] [[Page_with_an_inline_image]]"
    assert_equal expected, converter.convert(text, @ctx)
  end

  test "should detect escaped wiki links" do
    converter = Converter.new(@wiki_link_rewrites)
    text = "\\[\\[Page_with_an_inline_image\\]\\]"
    expected = "\\[\\[NewBookPage_with_an_inline_image\\]\\]"
    assert_equal expected, converter.convert(text, @ctx)
  end

  test "should remove linked project" do
    @wiki_link_rewrites['ecookbook'][:project] = nil
    converter = Converter.new(@wiki_link_rewrites)
    text = "[[ecookbook:Page_with_an_inline_image]] [[Page_with_an_inline_image]]"
    expected = "[[NewBookPage_with_an_inline_image]] [[NewBookPage_with_an_inline_image]]"
    assert_equal expected, converter.convert(text, @ctx)
  end

  test "should change linked project" do
    @wiki_link_rewrites['ecookbook'][:project] = 'book'
    converter = Converter.new(@wiki_link_rewrites)
    text = "[[ecookbook:Page_with_an_inline_image#foo]] [[Page_with_an_inline_image]]"
    expected = "[[book:NewBookPage_with_an_inline_image#foo]] [[book:NewBookPage_with_an_inline_image]]"
    assert_equal expected, converter.convert(text, @ctx)
  end

  test "should change linked project without adding page prefix" do
    @wiki_link_rewrites = {
      'ecookbook' => {project: 'book'}
    }
    converter = Converter.new(@wiki_link_rewrites)
    text = "[[ecookbook:Page_with_an_inline_image]] [[Page_with_an_inline_image]] [[ecookbook:Foo]]"
    expected = "[[book:Page_with_an_inline_image]] [[book:Page_with_an_inline_image]] [[ecookbook:Foo]]"
    assert_equal expected, converter.convert(text, @ctx)
  end

  test "should accept project_id instead identifier" do
    @wiki_link_rewrites = {
      1 => {project: 'book'}
    }
    converter = Converter.new(@wiki_link_rewrites)
    text = "[[ecookbook:Page_with_an_inline_image]] [[Page_with_an_inline_image]] [[ecookbook:Foo]]"
    expected = "[[book:Page_with_an_inline_image]] [[book:Page_with_an_inline_image]] [[ecookbook:Foo]]"
    assert_equal expected, converter.convert(text, @ctx)
  end

  test "should use explicit wiki start page when project prefix is removed" do
    @wiki_link_rewrites = {
      'ecookbook' => {project: nil}
    }
    converter = Converter.new(@wiki_link_rewrites)
    text = "[[ecookbook:]]"
    expected = "[[CookBook documentation]]"
    assert_equal expected, converter.convert(text, @ctx)
  end

  test "should use explicit wiki start page when its name is changed" do
    converter = Converter.new(@wiki_link_rewrites)
    text = "[[ecookbook:]]"
    expected = "[[ecookbook:NewBookCookBook documentation]]"
    assert_equal expected, converter.convert(text, @ctx)
  end
end
