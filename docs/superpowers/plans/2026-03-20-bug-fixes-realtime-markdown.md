# Real-Time Replies and Markdown Support Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add real-time reply broadcasting via Turbo Streams and Markdown rendering in post/reply bodies.

**Architecture:** Extract inline reply markup into a `_reply.html.erb` partial, wire Turbo Stream subscriptions and server-side broadcasts in `RepliesController`, add a `redcarpet`-backed `render_markdown` helper with double-layer sanitization, and update body output locations plus compose forms.

**Tech Stack:** Rails 8.1, Turbo Streams (solid_cable in production / test adapter in tests), Redcarpet gem, ActionCable::TestHelper for broadcast assertions.

---

> **Status note:** Both bugs from the spec (orphaned notifications, posts index probe pattern) are **already implemented**. This plan covers only the two remaining features.

---

## File Map

**Created:**
- `app/views/replies/_reply.html.erb` — reply card partial (extracted from `posts/show.html.erb`)
- `app/views/replies/_count.html.erb` — reply count Turbo Frame partial (used in show + broadcasts)
- `test/helpers/application_helper_test.rb` — unit tests for `render_markdown`

**Modified:**
- `app/views/posts/show.html.erb` — add `turbo_stream_from`, wrap count in Turbo Frame, use partials
- `app/controllers/replies_controller.rb` — add broadcasts on create/update/destroy
- `test/controllers/replies_controller_test.rb` — add `include ActionCable::TestHelper` + broadcast assertions
- `Gemfile` — add `redcarpet`
- `app/helpers/application_helper.rb` — add `render_markdown`
- `app/views/posts/show.html.erb` — use `render_markdown` for post and reply bodies
- `app/views/posts/new.html.erb` — markdown hint below body textarea
- `app/views/posts/edit.html.erb` — markdown hint below body textarea
- `app/views/replies/edit.html.erb` — markdown hint below body textarea

---

## Task 1: Extract `_reply.html.erb` Partial

**Files:**
- Create: `app/views/replies/_reply.html.erb`
- Modify: `app/views/posts/show.html.erb:59-108`

The inline reply loop in `posts/show.html.erb` becomes a partial. The partial receives `reply` (from collection) and `post` (as explicit local — needed for path helpers like `post_reply_path`). Auth helpers (`logged_in?`, `current_user`, `can_moderate?`) remain available as view helpers.

- [ ] **Step 1: Verify existing tests pass before touching anything**

```bash
bin/rails test test/controllers/posts_controller_test.rb
```
Expected: all green. These tests (`div#reply-#{reply.id}`, `.last-edited-at`, edit link visibility) will serve as the regression suite for this refactor.

- [ ] **Step 2: Create `app/views/replies/_reply.html.erb`**

Extract exactly the inner div from `posts/show.html.erb` lines 60–108 (the `<div class="bg-gray-50 ...">` block). Change every `@post` reference to the `post` local variable. Change `edit_post_reply_path(@post, reply)` and `post_reply_path(@post, reply)` to use `post`.

```erb
<%# app/views/replies/_reply.html.erb %>
<div class="bg-gray-50 border border-gray-200 rounded-lg p-4 mb-3" id="reply-<%= reply.id %>">
  <div class="flex items-center gap-2 mb-2">
    <% if reply.user.avatar_url.present? %>
      <%= image_tag reply.user.avatar_url, class: "w-6 h-6 rounded-full", alt: "" %>
    <% else %>
      <span class="w-6 h-6 rounded-full bg-teal-100 text-teal-700 font-semibold flex items-center justify-center text-xs">
        <%= (reply.user.name.presence || "?").first.upcase %>
      </span>
    <% end %>
    <span class="text-sm font-medium text-gray-700"><%= reply.user.name %></span>
    <span class="text-xs text-gray-400"><%= time_ago_in_words(reply.created_at) %> ago</span>
    <% if logged_in? && current_user == reply.user && Time.current - reply.created_at <= EDIT_WINDOW_SECONDS %>
      <%= link_to "Edit", edit_post_reply_path(post, reply), class: "text-xs text-blue-500 hover:underline ml-auto" %>
    <% end %>
  </div>
  <% if reply.removed? %>
    <p class="text-gray-400 italic">[removed by moderator]</p>
    <% if logged_in? && current_user.moderator? %>
      <p class="text-xs text-gray-400 mt-1">
        Removed by <%= reply.removed_by.name %> on <%= reply.removed_at.strftime("%B %-d, %Y") %>
      </p>
    <% end %>
  <% else %>
    <p class="text-gray-800 whitespace-pre-wrap"><%= reply.body %></p>
    <% if reply.edited? %>
      <p class="text-xs text-gray-400 mt-1 last-edited-at">last edited at <%= reply.last_edited_at.strftime("%-d %b %Y %H:%M") %></p>
    <% end %>
    <%= turbo_frame_tag reactions_frame_id(reply) do %>
      <%= render "reactions/reactions", reactionable: reply %>
    <% end %>
  <% end %>
  <div class="flex items-center justify-between mt-2">
    <span></span>
    <div class="flex gap-3">
      <% if logged_in? && reply.user == current_user && !reply.removed? %>
        <%= button_to "Delete", post_reply_path(post, reply), method: :delete,
              class: "text-xs text-gray-400 hover:text-red-500 bg-transparent border-0 p-0 cursor-pointer" %>
      <% end %>
      <% if logged_in? && can_moderate?(reply.user) && !reply.removed? %>
        <%= button_to "Remove", post_reply_path(post, reply), method: :delete,
              class: "text-xs text-red-600 hover:underline bg-transparent border-0 p-0 cursor-pointer",
              data: { confirm: "Remove this reply?" } %>
        <%= link_to "Ban User", new_user_ban_path(user_id: reply.user_id),
              class: "text-xs text-orange-600 hover:underline" %>
      <% end %>
    </div>
  </div>
</div>
```

- [ ] **Step 3: Replace the inline loop in `app/views/posts/show.html.erb`**

Replace lines 59–108 (the `<% @replies.first(@take).each do |reply| %>` block) with:

```erb
    <div id="replies-list-<%= @post.id %>">
      <%= render partial: "replies/reply", collection: @replies.first(@take), as: :reply, locals: { post: @post } %>
    </div>
```

- [ ] **Step 4: Run the existing tests to confirm refactor is clean**

```bash
bin/rails test test/controllers/posts_controller_test.rb
```
Expected: all green. If any test fails, the partial diverged from the original markup — diff carefully and fix.

- [ ] **Step 5: Commit**

```bash
git add app/views/replies/_reply.html.erb app/views/posts/show.html.erb
git commit -m "refactor: extract reply card into replies/_reply partial"
```

---

## Task 2: Wire Turbo Stream Subscription and Reply Count Frame

**Files:**
- Create: `app/views/replies/_count.html.erb`
- Modify: `app/views/posts/show.html.erb`

Add the `turbo_stream_from` subscription tag and wrap the reply count heading in a Turbo Frame so broadcasts can update it independently.

- [ ] **Step 1: Create `app/views/replies/_count.html.erb`**

```erb
<%# app/views/replies/_count.html.erb %>
<%= turbo_frame_tag "replies_count_#{post.id}" do %>
  <h2 class="text-xl font-semibold mb-4">Replies (<%= count %>)</h2>
<% end %>
```

- [ ] **Step 2: Update `app/views/posts/show.html.erb`**

At the very top of the replies section (just before the h2 on line 55), add the subscription tag:

```erb
  <div class="mt-8">
    <%= turbo_stream_from @post, :replies %>
    <%= render partial: "replies/count", locals: { post: @post, count: @reply_count } %>
```

This replaces the existing `<div class="mt-8">` and the `<h2>` on lines 54–57.

- [ ] **Step 3: Run existing tests to confirm nothing broken**

```bash
bin/rails test test/controllers/posts_controller_test.rb
```
Expected: all green. The `Replies (N)` heading is now inside a turbo-frame but the text is unchanged.

- [ ] **Step 4: Commit**

```bash
git add app/views/replies/_count.html.erb app/views/posts/show.html.erb
git commit -m "feat: add Turbo Stream subscription and reply count frame to posts#show"
```

---

## Task 3: Add Broadcasts to RepliesController

**Files:**
- Modify: `app/controllers/replies_controller.rb`

Add server-side broadcasts on every mutating success path. Broadcasts go before the redirect. Use four private helpers to keep action bodies clean.

- [ ] **Step 1: Add broadcast helpers and calls to `app/controllers/replies_controller.rb`**

In `create`, after `NotificationService.reply_created(...)`, add `broadcast_reply_created`:

```ruby
  def create
    @post = Post.find(params[:post_id])
    @reply = @post.replies.build(reply_params.merge(user: current_user))
    if @reply.save
      NotificationService.reply_created(@reply, current_user: current_user)
      broadcast_reply_created
      redirect_to @post, notice: "Reply posted!"
    else
      ...
    end
  end
```

In `update`, after the successful update, add `broadcast_reply_updated`:

```ruby
  def update
    if @reply.update(reply_params.merge(last_edited_at: Time.current))
      broadcast_reply_updated
      redirect_to @post, notice: "Reply updated!"
    else
      ...
    end
  end
```

In `destroy`, add broadcasts on both success branches (before each redirect):

```ruby
  def destroy
    @post  = Post.find(params[:post_id])
    @reply = @post.replies.find(params[:id])

    if current_user.moderator? && can_moderate?(@reply.user)
      @reply.update!(removed_at: Time.current, removed_by: current_user)
      @post.update_column(:last_replied_at, @post.replies.visible.maximum(:created_at))
      NotificationService.content_removed(@reply, removed_by: current_user)
      broadcast_reply_soft_deleted
      redirect_to @post, notice: "Reply removed."
    elsif @reply.user == current_user
      @reply.destroy
      broadcast_reply_hard_deleted
      redirect_to @post, notice: "Reply deleted."
    else
      redirect_to @post, alert: "Not authorized.", status: :see_other
    end
  end
```

Add private broadcast helpers at the bottom of the `private` section:

```ruby
    def broadcast_reply_created
      Turbo::StreamsChannel.broadcast_append_to(
        [ @post, :replies ],
        target: "replies-list-#{@post.id}",
        partial: "replies/reply",
        locals: { reply: @reply, post: @post }
      )
      broadcast_reply_count
    end

    def broadcast_reply_updated
      Turbo::StreamsChannel.broadcast_replace_to(
        [ @post, :replies ],
        target: "reply-#{@reply.id}",
        partial: "replies/reply",
        locals: { reply: @reply, post: @post }
      )
    end

    def broadcast_reply_soft_deleted
      Turbo::StreamsChannel.broadcast_replace_to(
        [ @post, :replies ],
        target: "reply-#{@reply.id}",
        partial: "replies/reply",
        locals: { reply: @reply, post: @post }
      )
      broadcast_reply_count
    end

    def broadcast_reply_hard_deleted
      Turbo::StreamsChannel.broadcast_remove_to(
        [ @post, :replies ],
        target: "reply-#{@reply.id}"
      )
      broadcast_reply_count
    end

    def broadcast_reply_count
      Turbo::StreamsChannel.broadcast_replace_to(
        [ @post, :replies ],
        target: "replies_count_#{@post.id}",
        partial: "replies/count",
        locals: { post: @post, count: @post.replies.visible.count }
      )
    end
```

- [ ] **Step 2: Run existing controller tests to confirm no regressions**

```bash
bin/rails test test/controllers/replies_controller_test.rb
```
Expected: all green. Broadcasts fire alongside the redirect; existing redirect/flash assertions are unaffected.

- [ ] **Step 3: Commit**

```bash
git add app/controllers/replies_controller.rb
git commit -m "feat: broadcast reply create/update/destroy via Turbo Streams"
```

---

## Task 4: Broadcast Tests

**Files:**
- Modify: `test/controllers/replies_controller_test.rb`

Use `ActionCable::TestHelper` to assert the correct number of broadcasts fires on each mutating action.

- [ ] **Step 1: Add `include ActionCable::TestHelper` to the test class**

Add the include on the line after `class RepliesControllerTest < ActionDispatch::IntegrationTest`:

```ruby
class RepliesControllerTest < ActionDispatch::IntegrationTest
  include ActionCable::TestHelper
```

- [ ] **Step 2: Write the failing broadcast tests**

Add these four tests at the end of `test/controllers/replies_controller_test.rb` (before the final `end`):

```ruby
  # ---- Turbo Stream broadcasts ----

  test "POST create broadcasts append + count to replies stream" do
    post login_path, params: { email: "u@example.com", password: "pass123" }
    assert_broadcasts(Turbo::StreamsChannel.broadcasting_for([ @post, :replies ]), 2) do
      post post_replies_path(@post), params: { reply: { body: "live reply" } }
    end
  end

  test "PATCH update broadcasts replace to replies stream" do
    post login_path, params: { email: "u@example.com", password: "pass123" }
    reply = Reply.create!(post: @post, user: @user, body: "original")
    assert_broadcasts(Turbo::StreamsChannel.broadcasting_for([ @post, :replies ]), 1) do
      patch post_reply_path(@post, reply), params: { reply: { body: "updated" } }
    end
  end

  test "DELETE (owner hard-delete) broadcasts remove + count to replies stream" do
    post login_path, params: { email: "u@example.com", password: "pass123" }
    reply = Reply.create!(post: @post, user: @user, body: "my reply")
    assert_broadcasts(Turbo::StreamsChannel.broadcasting_for([ @post, :replies ]), 2) do
      delete post_reply_path(@post, reply)
    end
  end

  test "DELETE (moderator soft-delete) broadcasts replace + count to replies stream" do
    post login_path, params: { email: "sub@example.com", password: "pass123" }
    reply = Reply.create!(post: @post, user: @user, body: "reply to moderate")
    assert_broadcasts(Turbo::StreamsChannel.broadcasting_for([ @post, :replies ]), 2) do
      delete post_reply_path(@post, reply)
    end
  end
```

- [ ] **Step 3: Run the new tests to verify they fail before broadcasts are wired**

```bash
bin/rails test test/controllers/replies_controller_test.rb -n "/broadcast/"
```
Expected: 4 failures with "0 broadcasts, expected 2" (or similar) — confirms the tests are real. (Broadcasts were actually added in Task 3 already, so if running sequentially these will pass. If writing tests before wiring, you'd see failures here.)

- [ ] **Step 4: Run the full replies controller test suite**

```bash
bin/rails test test/controllers/replies_controller_test.rb
```
Expected: all green.

- [ ] **Step 5: Commit**

```bash
git add test/controllers/replies_controller_test.rb
git commit -m "test: assert Turbo Stream broadcasts on reply create/update/destroy"
```

---

## Task 5: Add `redcarpet` Gem

**Files:**
- Modify: `Gemfile`

- [ ] **Step 1: Add `redcarpet` to `Gemfile`**

Add after the `bcrypt` line:

```ruby
gem "redcarpet"
```

- [ ] **Step 2: Install the gem**

```bash
bundle install
```
Expected: `Bundle complete!` with redcarpet listed in the install output.

- [ ] **Step 3: Verify the gem loads**

```bash
bin/rails runner "require 'redcarpet'; puts Redcarpet::VERSION"
```
Expected: prints a version string like `3.6.0`.

- [ ] **Step 4: Commit**

```bash
git add Gemfile Gemfile.lock
git commit -m "gem: add redcarpet for Markdown rendering"
```

---

## Task 6: `render_markdown` Helper and Unit Tests

**Files:**
- Modify: `app/helpers/application_helper.rb`
- Create: `test/helpers/application_helper_test.rb`

Write the tests first, then implement the helper.

- [ ] **Step 1: Write failing tests in `test/helpers/application_helper_test.rb`**

```ruby
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
    assert_not_includes output, "alert(1)"
  end

  test "raw img tags are stripped from output" do
    output = render_markdown("<img src='x' onerror='alert(1)'>")
    assert_not_includes output, "<img"
  end

  test "strip_tags on markdown body preserves syntax characters as literal text" do
    # Confirms the index preview (which uses strip_tags) does not mangle markdown syntax
    result = strip_tags("**bold**")
    assert_equal "**bold**", result
  end
end
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
bin/rails test test/helpers/application_helper_test.rb
```
Expected: failures — `render_markdown` is undefined.

- [ ] **Step 3: Implement `render_markdown` in `app/helpers/application_helper.rb`**

```ruby
module ApplicationHelper
  MARKDOWN_RENDERER = Redcarpet::Render::HTML.new(no_html: true)
  MARKDOWN_PARSER   = Redcarpet::Markdown.new(
    MARKDOWN_RENDERER,
    autolink:           true,
    fenced_code_blocks: true,
    strikethrough:      true,
    no_intra_emphasis:  true
  )
  MARKDOWN_ALLOWED_TAGS = %w[p strong em code pre ul ol li blockquote a br h1 h2 h3].freeze

  def render_markdown(text)
    html = MARKDOWN_PARSER.render(text.to_s)
    sanitize(html, tags: MARKDOWN_ALLOWED_TAGS).html_safe
  end
end
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
bin/rails test test/helpers/application_helper_test.rb
```
Expected: 8 tests, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add app/helpers/application_helper.rb test/helpers/application_helper_test.rb
git commit -m "feat: add render_markdown helper with redcarpet + sanitize"
```

---

## Task 7: Apply `render_markdown` to Post and Reply Body Views

**Files:**
- Modify: `app/views/posts/show.html.erb:44`
- Modify: `app/views/replies/_reply.html.erb:21`

Replace plain `<%= body %>` output with `<%= render_markdown(body) %>` in the non-removed branches. The `whitespace-pre-wrap` class is no longer needed once Markdown generates its own block elements — remove it from both body paragraphs.

- [ ] **Step 1: Update post body in `app/views/posts/show.html.erb`**

Replace:
```erb
      <div class="mt-4 text-gray-800 whitespace-pre-wrap"><%= @post.body %></div>
```
With:
```erb
      <div class="mt-4 text-gray-800 prose prose-sm max-w-none"><%= render_markdown(@post.body) %></div>
```

(The `prose` classes are optional Tailwind Typography helpers — if the project does not include `@tailwindcss/typography`, just use `text-gray-800` without `prose`.)

Actually: keep it simple, no typography plugin dependency. Replace with:
```erb
      <div class="mt-4 text-gray-800"><%= render_markdown(@post.body) %></div>
```

- [ ] **Step 2: Update reply body in `app/views/replies/_reply.html.erb`**

Replace:
```erb
    <p class="text-gray-800 whitespace-pre-wrap"><%= reply.body %></p>
```
With:
```erb
    <div class="text-gray-800"><%= render_markdown(reply.body) %></div>
```

- [ ] **Step 3: Run the full test suite**

```bash
bin/rails test test/controllers/posts_controller_test.rb test/controllers/replies_controller_test.rb
```
Expected: all green. The body content tests match on substrings; Markdown wraps text in `<p>` tags which is fine for the existing assertions.

- [ ] **Step 4: Commit**

```bash
git add app/views/posts/show.html.erb app/views/replies/_reply.html.erb
git commit -m "feat: render post and reply bodies as Markdown"
```

---

## Task 8: Add Markdown Hint to Compose Forms

**Files:**
- Modify: `app/views/posts/new.html.erb`
- Modify: `app/views/posts/edit.html.erb`
- Modify: `app/views/posts/show.html.erb` (inline reply form)
- Modify: `app/views/replies/edit.html.erb`

Add a single line of hint text below the body textarea in each of the four compose forms.

- [ ] **Step 1: Add hint to `app/views/posts/new.html.erb`**

After the `<%= f.text_area :body ... %>` line, add:
```erb
      <p class="text-xs text-gray-400 mt-1">Markdown supported — <strong>**bold**</strong>, <em>_italic_</em>, <code>`code`</code>, fenced code blocks</p>
```

- [ ] **Step 2: Add hint to `app/views/posts/edit.html.erb`**

Same hint after the body textarea:
```erb
      <p class="text-xs text-gray-400 mt-1">Markdown supported — <strong>**bold**</strong>, <em>_italic_</em>, <code>`code`</code>, fenced code blocks</p>
```

- [ ] **Step 3: Add hint to the inline reply form in `app/views/posts/show.html.erb`**

After `<%= f.text_area :body, rows: 4 ... %>`, add:
```erb
          <p class="text-xs text-gray-400">Markdown supported — <strong>**bold**</strong>, <em>_italic_</em>, <code>`code`</code>, fenced code blocks</p>
```

- [ ] **Step 4: Add hint to `app/views/replies/edit.html.erb`**

After `<%= f.text_area :body, rows: 6 ... %>`, add:
```erb
      <p class="text-xs text-gray-400 mt-1">Markdown supported — <strong>**bold**</strong>, <em>_italic_</em>, <code>`code`</code>, fenced code blocks</p>
```

- [ ] **Step 5: Run the full CI pipeline**

```bash
bin/ci
```
Expected: lint, security, and all tests pass.

- [ ] **Step 6: Commit**

```bash
git add app/views/posts/new.html.erb app/views/posts/edit.html.erb \
        app/views/posts/show.html.erb app/views/replies/edit.html.erb
git commit -m "feat: add Markdown hint text to all compose forms"
```

---

## Summary

| Task | Files | Tests |
|---|---|---|
| 1. Extract reply partial | `_reply.html.erb`, `show.html.erb` | Existing tests serve as regression |
| 2. Turbo Stream subscription + count frame | `_count.html.erb`, `show.html.erb` | Existing tests |
| 3. Broadcasts in RepliesController | `replies_controller.rb` | Added in Task 4 |
| 4. Broadcast assertions | `replies_controller_test.rb` | 4 new broadcast tests |
| 5. Add redcarpet gem | `Gemfile` | Verified with `rails runner` |
| 6. render_markdown helper | `application_helper.rb`, `application_helper_test.rb` | 8 new unit tests |
| 7. Apply render_markdown to views | `show.html.erb`, `_reply.html.erb` | Existing tests |
| 8. Markdown hints | 4 form views | Full CI |
