module ApplicationHelper
  MARKDOWN_ALLOWED_TAGS = %w[p strong em del code pre ul ol li blockquote a br h1 h2 h3].freeze

  def google_oauth_configured?
    ENV["GOOGLE_CLIENT_ID"].present? && ENV["GOOGLE_CLIENT_SECRET"].present?
  end

  def microsoft_oauth_configured?
    ENV["MICROSOFT_CLIENT_ID"].present? && ENV["MICROSOFT_CLIENT_SECRET"].present?
  end

  def render_markdown(text)
    renderer = Redcarpet::Render::HTML.new(no_html: true)
    parser   = Redcarpet::Markdown.new(
      renderer,
      autolink:           true,
      fenced_code_blocks: true,
      strikethrough:      true,
      no_intra_emphasis:  true
    )
    sanitize(
      parser.render(text.to_s),
      tags: MARKDOWN_ALLOWED_TAGS,
      protocols: { "a" => { "href" => [ "http", "https", "mailto", :relative ] } }
    )
  end

  def plain_text_excerpt(text, length: 160)
    html  = render_markdown(text.to_s)
    plain = CGI.unescapeHTML(ActionView::Base.full_sanitizer.sanitize(html).squish)
    truncate(plain, length: length, omission: "…")
  end
end
