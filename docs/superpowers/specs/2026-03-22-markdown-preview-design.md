# Markdown Preview in Compose Forms

## Goal

Add a Write/Preview tab toggle to every compose textarea so users can see rendered markdown before posting.

## Scope

Affects all four compose surfaces:
- `posts/new` — new post body
- `posts/edit` — edit post body
- `posts/show` — inline reply form
- `replies/edit` — edit reply body

No server changes. No new routes, controller actions, or DB columns.

## Approach

Client-side rendering via `marked` (pinned via importmap). A Stimulus controller (`markdown-preview`) manages the tab toggle and renders markdown into a preview `<div>` when the user clicks "Preview".

`marked` is chosen over a server round-trip to avoid load on the server. Rendering differences from Redcarpet are negligible for the markdown subset used (bold, italic, code, fenced blocks, autolinks, strikethrough).

## UI Behaviour

Each body field gets:

1. **Tab bar** above the textarea with two tabs: "Write" and "Preview"
2. **Write tab (default):** shows the textarea, hides the preview div
3. **Preview tab:** hides the textarea, shows a `<div>` with the rendered HTML
4. The existing `<p class="text-xs ...">Markdown supported...</p>` hint moves below the tab bar and remains visible in both modes

The preview `<div>` matches the textarea's height (`rows` attribute) so the form doesn't jump.

When the textarea is empty and the user clicks Preview, show a placeholder: `<p class="text-gray-400 italic">Nothing to preview.</p>`

## Stimulus Controller

**Target:** `app/javascript/controllers/markdown_preview_controller.js`

**Identifier:** `markdown-preview`

**Targets:**
- `textarea` — the body textarea
- `preview` — the div that receives rendered HTML
- `writeTab` — the "Write" tab button
- `previewTab` — the "Preview" tab button

**Actions:**
- `showWrite()` — activates Write tab: shows textarea, hides preview, updates tab active styles
- `showPreview()` — activates Preview tab: renders markdown via `marked`, shows preview div, hides textarea

**Active tab style:** active tab has `font-medium text-blue-600 border-b-2 border-blue-600`; inactive has `text-gray-500 hover:text-gray-700`

## importmap

Pin `marked` from jsDelivr:

```ruby
pin "marked", to: "https://cdn.jsdelivr.net/npm/marked/marked.min.js"
```

## Files Changed

| File | Change |
|------|--------|
| `config/importmap.rb` | Pin `marked` |
| `app/javascript/controllers/markdown_preview_controller.js` | New Stimulus controller |
| `app/views/posts/new.html.erb` | Add controller data attrs to body field |
| `app/views/posts/edit.html.erb` | Add controller data attrs to body field |
| `app/views/posts/show.html.erb` | Add controller data attrs to inline reply form |
| `app/views/replies/edit.html.erb` | Add controller data attrs to body field |

## Testing

No automated tests — this is purely client-side Stimulus behaviour with no server-side changes. Verify manually after implementation by:
1. Opening a compose form
2. Typing markdown in the textarea
3. Clicking Preview — confirming rendered output appears
4. Clicking Write — confirming textarea returns with content intact
5. Submitting — confirming actual post/reply renders identically

## Out of Scope

- Live preview (updating as you type)
- Syncing scroll position between editor and preview
- Toolbar (bold/italic buttons)
- Server-side preview endpoint
