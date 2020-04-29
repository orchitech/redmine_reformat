require_relative '../../test_helper'

class  RedmineReformat::Converters::UtilsTest < ActiveSupport::TestCase
  Utils = RedmineReformat::Converters::Utils
  test "markup_char_re should generate bracket matching regexp for markdown" do
    lbrack = Utils.markup_char_re('[', 'markdown')
    testre = /^x#{lbrack}$/
    # tested object is actually in expected here
    assert_match testre, "x["
    refute_match testre, "X["

    assert_match testre, "x\\["
    assert_match testre, "x&#91;"
    assert_match testre, "x&#091;"
    assert_match testre, "x&lbrack;"
    assert_match testre, "x&lsqb;"
    assert_match testre, "x&LBRACK;"
    assert_match testre, "x&#x5B;"
    assert_match testre, "x&#X005B;"
  end

  test "markup_char_re should be usable as a subregexp" do
    lbrack = Utils.markup_char_re('[', 'markdown')
    testre = /^x#{lbrack}{2}y/
    assert_match testre, "x&lbrack;\\[y"
    refute_match testre, "x[y"
  end

  test "should convert numeric ids to ints and identifiers to strings" do
    assert_nil Utils.to_i_or_s(nil)
    assert_equal 42, Utils.to_i_or_s(42)
    assert_equal 42, Utils.to_i_or_s("42")
    assert_equal 42, Utils.to_i_or_s(:"42")
    assert_equal "42x", Utils.to_i_or_s("42x")
    assert_equal "42x", Utils.to_i_or_s(:"42x")
  end
end
