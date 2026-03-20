# Design Spec: Bug Fixes, Real-Time Replies, and Markdown Support

**Date:** 2026-03-20
**Status:** Approved

---

## Overview

This spec covers two correctness bugs and two UX features, sequenced bugs-first so the real-time and markdown work lands on a stable base.

1. Bug: Orphaned notifications crash when a reply is hard-deleted
2. Bug: Posts index shows a false "Older →" link on exact-count pages
3. Feature: Real-time reply updates via Turbo Streams
4. Feature: Markdown rendering in post and reply bodies

---

## Bug 1: Orphaned Notifications Crash on Reply Hard-Delete

### Problem

`Reply` has no `has_many :notifications, as: :notifiable, dependent: :destroy`. When a user hard-deletes their own reply (`RepliesController#destroy`), notification records with `notifiable_type: "Reply", notifiable_id: <id>` remain in the database.

When those notifications are later rendered in `NotificationsController#index`, `Notification#target_post` calls `notifiable.post`. Because the reply record is gone, `belongs_to :notifiable` returns `nil`, and `.post` raises `NoMethodError`, crashing the notifications page for the affected user.

### Fix

**`app/models/reply.rb`**
- Add `has_many :notifications, as: :notifiable, dependent: :destroy`
- This cascades deletion of notification records when a reply is destroyed

**`app/models/notification.rb`**
- Add a nil guard in `target_post`: if `notifiable` is nil, return `nil` rather than raising
- In the notifications view, skip rendering notifications where `target_post` returns nil

### Tests

- `test/models/reply_test.rb`: destroy a reply that has associated notifications; assert those notifications are deleted
- `test/models/notification_test.rb`: call `target_post` on a notification whose `notifiable` is nil (simulate orphan); assert it returns nil instead of raising

---

## Bug 2: False "Older →" Link on Exact-Count Posts Page

### Problem

`PostsController#index` loads exactly `@take` records with `posts.limit(take)`. The view checks `@posts.size >= @take` to decide whether to show the "Older →" pagination link. When the last page contains exactly `@take` posts, this condition is true and the Next link appears — clicking it yields an empty page.

The probe pattern (load `take + 1`, render `take`, show Next only if `size > take`) was already applied to reply pagination in `PostsController#show` but was missed in `#index`.

### Fix

**`app/controllers/posts_controller.rb`**
- Change `posts.limit(take)` to `posts.limit(take + 1)`

**`app/views/posts/index.html.erb`**
- Change `@posts.size >= @take` to `@posts.size > @take`
- Wrap the posts loop body in `@posts.first(@take).each` to render only `take` records

### Tests

- `test/controllers/posts_controller_test.rb`:
  - Create exactly `take` posts; assert no "Older →" link in response
  - Create `take + 1` posts; assert "Older →" link is present

---

## Feature: Real-Time Reply Updates (Turbo Streams)

### Overview

When any user creates, edits, or destroys a reply on a post, all other browsers viewing that post see the change without a page refresh. Solid Cable is already configured; no new infrastructure is required.

### Subscription

In `app/views/posts/show.html.erb`, add `<%= turbo_stream_from @post, :replies %>` near the top of the replies section. This subscribes the browser to a named ActionCable stream for that post's replies.

Wrap the reply count display in a Turbo Frame with a stable DOM id (e.g. `replies_count_<post_id>`) so it can be replaced independently.

### Broadcasting

In `RepliesController`, after each mutating action, broadcast to the post's reply stream:

- **`create`**: `broadcast_append_to` with the new reply partial appended to the replies list; `broadcast_replace_to` targeting the reply count frame
- **`update`**: `broadcast_replace_to` targeting the updated reply's DOM element with the refreshed reply partial
- **`destroy` (hard delete by owner)**: `broadcast_remove_to` targeting the reply's DOM element; also update reply count
- **`destroy` (soft remove by moderator)**: `broadcast_replace_to` with the reply card in its "[removed by moderator]" state; also update reply count

All broadcasts use the same reply partial already used for initial render — no new templates needed.

### No JavaScript Required

Turbo Streams handles all DOM mutations server-side. No Stimulus changes are needed.

### Tests

Use `assert_broadcasts`/`assert_broadcast_on` in controller tests to verify that the correct stream and Turbo Stream action are enqueued after each mutating action. Existing action tests continue to pass unchanged.

---

## Feature: Markdown Support

### Gem

Add `redcarpet` to the Gemfile. Configure with:
- `no_html: true` on the renderer — strips any raw HTML from user input before output
- Extensions: `:autolink`, `:fenced_code_blocks`, `:strikethrough`, `:no_intra_emphasis`

### Helper

Add `render_markdown(text)` to `app/helpers/application_helper.rb`:

1. Parse `text` through Redcarpet with the above renderer and extensions
2. Pass output through Rails `sanitize` with an explicit allowlist of safe tags: `p`, `strong`, `em`, `code`, `pre`, `ul`, `ol`, `li`, `blockquote`, `a`, `br`, `h1`, `h2`, `h3`
3. Return the result marked `html_safe`

No raw user HTML ever reaches the browser — `no_html: true` strips it at parse time and `sanitize` provides a second layer.

### Views

- `app/views/posts/show.html.erb`: replace `<%= post.body %>` with `<%= render_markdown(post.body) %>`
- `app/views/replies/_reply.html.erb` (or equivalent partial): replace `<%= reply.body %>` with `<%= render_markdown(reply.body) %>`
- `app/views/posts/index.html.erb`: the body preview already uses `truncate(strip_tags(post.body), length: 200)` — keep as-is; `strip_tags` handles markdown syntax gracefully

### Compose Form

Add a single line of hint text below the body textarea in both `posts/_form.html.erb` and the reply form:

> Markdown supported — `**bold**`, `_italic_`, `` `code` ``, fenced code blocks

No live preview. Can be added later if requested.

### Tests

Unit tests in `test/helpers/application_helper_test.rb`:
- Bold, italic, inline code render correctly
- Fenced code block renders as `<pre><code>`
- Autolinks produce `<a>` tags
- Raw `<script>` tags are stripped from output
- Raw `<img>` tags are stripped from output

---

## Sequencing

1. **Bug 1** — orphaned notifications (model + test, no view changes)
2. **Bug 2** — probe pattern for posts index (controller + view + test)
3. **Real-time replies** — Turbo Streams wiring (controller + view + test)
4. **Markdown** — gem + helper + views + test

Each step is independently shippable and testable.
