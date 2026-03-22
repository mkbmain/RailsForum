# @Mention Autocomplete — Design Spec

**Date:** 2026-03-22
**Status:** Approved

## Problem

Users must know the exact username to @mention someone. An autocomplete dropdown while typing `@` would reduce friction and errors.

## Scope

- Trigger: reply body textarea only (not post body)
- Candidate pool: participants in the current thread (post author + all visible repliers, across all pages), deduplicated. The current logged-in user is included only if they have already replied; they are not added automatically.
- Max results shown: 6
- Filtering: case-insensitive substring match as user types after `@`

## Multi-Word Names

User names may contain spaces (e.g. "Jane Doe"). The existing `NotificationService` resolves mentions via `/@(\w+)/i`, which only matches word characters — spaces break the match. To keep names resolvable, spaces are replaced with underscores when building the mention token. A user named "Jane Doe" is mentioned as `@Jane_Doe`.

**Disambiguation:** If two users share the same name, the first match found by the case-insensitive lookup wins — the same ambiguity that already exists in `NotificationService`. This is a known limitation; no uniqueness constraint is added.

**Underscore collision:** A user whose name contains a literal underscore (e.g. "Jane_Doe") would collide with a user named "Jane Doe". To prevent this, `User` silently replaces underscores with spaces on every save path via a `before_validation` callback:

```ruby
before_validation :sanitize_name
private
def sanitize_name
  self.name = name.gsub('_', ' ') if name.present?
end
```

No format validation is added — the sanitizer is sufficient and a validation would be dead code on all normal save paths. Existing users with underscores in their names will have them silently converted to spaces on their next save.

## Approach

Stimulus controller with inline data. Thread participants are embedded as a JSON array in a `data-` attribute on the textarea wrapper at render time. No API calls required.

**Known limitation:** The page uses `turbo_stream_from @post, :replies`, so new replies stream in after load. If someone joins the thread while you are composing, they will not appear in the autocomplete until the next page load. Accepted trade-off.

## Data Flow

`PostsController#show` collects all visible participants. The `else` branch is required — without it `@mention_users` is `nil` and the view raises `NoMethodError` on `.map` in any guest context:

```ruby
if logged_in?
  participant_ids = (@post.replies.visible.distinct.pluck(:user_id) + [@post.user_id]).uniq
  @mention_users = User.where(id: participant_ids)
else
  @mention_users = []
end
```

Uses `.visible` to exclude removed replies, consistent with the rest of the `show` action.

The reply form is already wrapped in `<% if logged_in? %>` (line 99 of `show.html.erb`), so `@mention_users` will always be set when the data attribute is rendered.

**JSON shape** — each entry includes both token and display name:

```ruby
@mention_users.map { |u| { token: u.name.gsub(' ', '_'), display: u.name } }.to_json
# => [{"token":"Jane_Doe","display":"Jane Doe"}, ...]
```

The existing `<div data-controller="markdown-preview">` at line 108 of `show.html.erb` gains the second controller and the users value:

```erb
data: {
  controller: "markdown-preview mention-autocomplete",
  mention_autocomplete_users_value: @mention_users.map { |u| { token: u.name.gsub(' ', '_'), display: u.name } }.to_json
}
```

The textarea carries both controllers' namespaced target attributes — each controller reads only its own:

```erb
data: {
  markdown_preview_target: "textarea",
  mention_autocomplete_target: "textarea"
}
```

## Controller Behavior (`mention-autocomplete`)

**Stimulus values declaration:**

```js
static values = { users: Array }
// Stimulus deserializes data-mention-autocomplete-users-value JSON automatically
// Each element: { token: "Jane_Doe", display: "Jane Doe" }
```

**Trigger detection** — on every `input` event, scan backward from the cursor position for `@\w*` with no whitespace between `@` and cursor. Extract the partial fragment. Since `\w` includes underscores, `@Jane_Do` passes `Jane_Do` to the filter.

**Filtering** — case-insensitive substring match of the fragment against each entry's `token` field. Take up to 6 results.

**Dropdown display** — a `<ul>` appended to `document.body`, positioned with `position: fixed` at the bottom-left corner of the textarea (not the cursor position) using `getBoundingClientRect()`. `position: fixed` avoids scroll-offset calculation and is not clipped by ancestor `overflow` styles. Each `<li>` shows `entry.display` (the human-readable name). `z-index: 9999`. Tailwind-styled with dark mode variants. No viewport-edge repositioning is performed — if the dropdown extends below the visible area the user can scroll to see it. This is an accepted simplification.

**Navigation:**
- `↑` / `↓` — move highlight
- `Enter` — select highlighted item; `preventDefault()` called to prevent newline insertion. If no item is highlighted, `Enter` is not intercepted (normal behavior).
- `Tab` — if an item is highlighted, select it and call `preventDefault()` to prevent focus change. If no item is highlighted, do not intercept — allow default Tab behavior (dropdown dismissed by the subsequent blur event).
- `Escape` — dismiss without selecting
- `click` — select item
- `blur` (with ~150ms delay to allow click to register) — dismiss. Covers the Preview-tab case: clicking "Preview" causes the textarea to lose focus, dismissing the dropdown before the tab hides it.

**Completion** — replace the `@fragment` in the textarea value with `@token` followed by a space. Move cursor to after the inserted text. Hide dropdown.

**Dismissal** — hide if no `@` trigger found at cursor, on Escape, or on blur.

**Cleanup** — the dropdown `<ul>` is removed in `disconnect()` to avoid leaking DOM nodes on Turbo navigation.

## NotificationService Change

`notification_service.rb` line 50:

```ruby
mentioned = User.find_by("LOWER(name) = LOWER(?)", username.gsub('_', ' '))
```

Single-word names are unaffected. The underscore validation ensures no collision with literal-underscore names.

## Files Changed

| File | Change |
|------|--------|
| `app/javascript/controllers/mention_autocomplete_controller.js` | New — Stimulus controller (auto-discovered via `eagerLoadControllersFrom`) |
| `app/views/posts/show.html.erb` | Extend `<div data-controller="markdown-preview">` (line 108) with second controller, users value, and textarea target |
| `app/controllers/posts_controller.rb` | Add `@mention_users` in `show` action (logged-in only, else `[]`) |
| `app/models/user.rb` | Add `before_validation :sanitize_name` (replaces underscores with spaces in name) |
| `app/services/notification_service.rb` | Add `.gsub('_', ' ')` when resolving mention usernames |

No new routes or migrations. `index.js` requires no change.

## Testing

- **Model:** `user_test` — name with underscore is invalid; name without underscore is valid
- **Model:** `user_test` — `from_omniauth` with a name containing underscores saves with underscores replaced by spaces
- **Controller:** `posts_controller_test` — `@mention_users` includes post author and all visible repliers, deduplicated; removed repliers are excluded; is `[]` for logged-out requests
- **Integration:** reply form renders `data-mention-autocomplete-users-value` with correct `{token, display}` JSON
- **Service:** `notification_service_test` — a reply body containing `@Jane_Doe` triggers a mention notification for the user named "Jane Doe"
- **Service:** `notification_service_test` — single-word names continue to resolve correctly (no regression)
