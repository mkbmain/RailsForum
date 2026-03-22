# @Mention Autocomplete — Design Spec

**Date:** 2026-03-22
**Status:** Approved

## Problem

Users must know the exact username to @mention someone. An autocomplete dropdown while typing `@` would reduce friction and errors.

## Scope

- Trigger: reply body textarea only (not post body)
- Candidate pool: participants in the current thread (post author + all repliers), deduplicated
- Max results shown: 6
- Filtering: case-insensitive prefix/substring match as user types after `@`

## Approach

Stimulus controller with inline data. Thread participants are embedded as a JSON array in a `data-` attribute on the textarea wrapper at render time. No API calls required — the list is small and stable within a single page load.

## Data Flow

`PostsController#show` collects participants:

```ruby
@mention_users = ([@post.user] + @post.replies.includes(:user).map(&:user)).uniq
```

The reply form passes the names as a Stimulus values attribute:

```erb
data: {
  controller: "mention-autocomplete",
  mention_autocomplete_users_value: @mention_users.map(&:name).to_json
}
```

The textarea gets the target attribute:

```erb
data: { mention_autocomplete_target: "textarea" }
```

## Controller Behavior (`mention-autocomplete`)

**Trigger detection** — on every `input` event, scan backward from the cursor position for a pattern matching `@\w*` with no whitespace between `@` and cursor. Extract the partial name fragment.

**Filtering** — case-insensitive match (name includes fragment) against the embedded users list. Take up to 6 results.

**Dropdown display** — a `<ul>` absolutely positioned below the textarea, appended to the controller element. Tailwind-styled with dark mode variants. Each `<li>` shows the user's name.

**Navigation:**
- `↑` / `↓` — move highlight
- `Enter` or `Tab` — select highlighted item
- `Escape` — dismiss without selecting
- `click` — select item
- `blur` (with ~150ms delay to allow click) — dismiss

**Completion** — replace the `@fragment` in the textarea value with `@FullName` followed by a space. Move cursor to after the inserted text. Hide dropdown.

**Dismissal** — hide if no `@` trigger found at cursor, on Escape, or on blur.

## Files Changed

| File | Change |
|------|--------|
| `app/javascript/controllers/mention_autocomplete_controller.js` | New — Stimulus controller |
| `app/javascript/controllers/index.js` | Register new controller |
| `app/views/posts/show.html.erb` | Add `data-controller`, `data-mention-autocomplete-users-value`, and textarea target to reply form |
| `app/controllers/posts_controller.rb` | Add `@mention_users` in `show` action |

No new routes, models, or migrations.

## Testing

- Unit: `mention_autocomplete_controller` behavior (trigger detection, filtering, completion)
- Controller: `posts_controller_test` — `@mention_users` assigned correctly in `show`
- Integration: reply form renders `data-mention-autocomplete-users-value` with correct JSON
