module ApplicationHelper
  MARKDOWN_ALLOWED_TAGS = %w[p strong em del code pre ul ol li blockquote a br h1 h2 h3].freeze

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
end
