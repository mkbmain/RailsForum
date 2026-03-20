require "test_helper"

class ApplicationHelperTest < ActionView::TestCase
  test "bold renders as <strong>" do
    output = render_markdown("**bold**")
    assert_includes output, "<strong>bold</strong>"
  end

  test "italic renders as <em>" do
    output = render_markdown("_italic_")
    assert_includes output, "<em>italic</em>"
  end

  test "inline code renders as <code>" do
    output = render_markdown("`code`")
    assert_includes output, "<code>code</code>"
  end

  test "fenced code block renders as pre > code" do
    output = render_markdown("```\nhello\n```")
    assert_includes output, "<pre>"
    assert_includes output, "<code>"
  end

  test "autolink renders URLs as anchor tags" do
    output = render_markdown("https://example.com")
    assert_includes output, "<a href=\"https://example.com\""
  end

  test "raw script tags are stripped from output" do
    output = render_markdown("<script>alert(1)</script>")
    assert_not_includes output, "<script>"
    assert_not_includes output, "</script>"
  end

  test "raw img tags are stripped from output" do
    output = render_markdown("<img src='x' onerror='alert(1)'>")
    assert_not_includes output, "<img"
  end

  test "strikethrough renders as <del>" do
    output = render_markdown("~~strike~~")
    assert_includes output, "<del>strike</del>"
  end
end
