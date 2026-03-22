# Soft-Delete Restore Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Allow moderators to restore removed posts and replies via a "Restore" button on the post show page.

**Architecture:** Add `member { patch :restore }` routes for posts and replies, implement `restore` actions in both controllers (clearing `removed_at`/`removed_by`), and add a Restore button in the `[removed by moderator]` sections of the post show view and reply partial. Reply restore also broadcasts a Turbo Stream replace + count update.

**Tech Stack:** Rails 8.1, Turbo Streams, ActionCable::TestHelper (for broadcast assertions), Minitest.

---

## File Map

**Modified:**
- `config/routes.rb` — add `member { patch :restore }` to posts and replies
- `app/controllers/posts_controller.rb` — add `restore` action + update three before_action `only:` lists
- `app/controllers/replies_controller.rb` — add `restore` action + `broadcast_reply_restored` helper + new `require_moderator` before_action
- `app/views/posts/show.html.erb` — add Restore button in `@post.removed?` block
- `app/views/replies/_reply.html.erb` — add Restore button in `reply.removed?` block
- `test/controllers/posts_controller_test.rb` — add restore tests
- `test/controllers/replies_controller_test.rb` — add restore tests

---

## Task 1: Add Routes

**Files:**
- Modify: `config/routes.rb`

- [ ] **Step 1: Add `member { patch :restore }` to posts and replies**

In `config/routes.rb`, replace:

```ruby
  resources :posts do
    resources :flags,     only: [ :create ]
    resources :reactions, only: [ :create, :destroy ]
    resources :replies,   only: [ :create, :destroy, :edit, :update ] do
```

With:

```ruby
  resources :posts do
    member { patch :restore }
    resources :flags,     only: [ :create ]
    resources :reactions, only: [ :create, :destroy ]
    resources :replies,   only: [ :create, :destroy, :edit, :update ] do
      member { patch :restore }
```

- [ ] **Step 2: Verify routes exist**

```bash
bin/rails routes | grep restore
```

Expected output includes:
```
restore_post        PATCH  /posts/:id/restore(.:format)
restore_post_reply  PATCH  /posts/:post_id/replies/:id/restore(.:format)
```

- [ ] **Step 3: Commit**

```bash
git add config/routes.rb
git commit -m "feat: add restore member routes for posts and replies"
```

---

## Task 2: PostsController#restore

**Files:**
- Modify: `app/controllers/posts_controller.rb`
- Modify: `test/controllers/posts_controller_test.rb`

- [ ] **Step 1: Write failing tests**

Add these tests at the end of `test/controllers/posts_controller_test.rb` (before the final `end`):

```ruby
  # ---- Restore ----

  test "PATCH restore as moderator clears removed_at and removed_by" do
    @post.update!(removed_at: Time.current, removed_by: @sub_admin)
    post login_path, params: { email: "sub@example.com", password: "pass123" }
    patch restore_post_path(@post)
    @post.reload
    assert_nil @post.removed_at
    assert_nil @post.removed_by
    assert_redirected_to post_path(@post)
    assert_equal "Post restored.", flash[:notice]
  end

  test "PATCH restore as non-moderator is rejected" do
    @post.update!(removed_at: Time.current, removed_by: @sub_admin)
    post login_path, params: { email: "u@example.com", password: "pass123" }
    patch restore_post_path(@post)
    @post.reload
    assert_not_nil @post.removed_at
    assert_redirected_to root_path
  end

  test "PATCH restore requires login" do
    @post.update!(removed_at: Time.current, removed_by: @sub_admin)
    patch restore_post_path(@post)
    @post.reload
    assert_not_nil @post.removed_at
    assert_redirected_to login_path
  end
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
bin/rails test test/controllers/posts_controller_test.rb -n "/restore/"
```

Expected: 3 failures / errors (route exists but action undefined).

- [ ] **Step 3: Update before_actions in PostsController**

In `app/controllers/posts_controller.rb`, update the three before_action lines at the top:

```ruby
  before_action :require_login,    only: [ :new, :create, :destroy, :edit, :update, :restore ]
  before_action :require_moderator, only: [ :destroy, :restore ]
  before_action :set_post,          only: [ :edit, :update, :restore ]
```

- [ ] **Step 4: Add the restore action**

Add after the `destroy` action (before the `private` line):

```ruby
  def restore
    @post.update!(removed_at: nil, removed_by: nil)
    redirect_to @post, notice: "Post restored."
  end
```

- [ ] **Step 5: Run restore tests — expect green**

```bash
bin/rails test test/controllers/posts_controller_test.rb -n "/restore/"
```

Expected: 3 tests, 0 failures.

- [ ] **Step 6: Run full posts controller tests to check for regressions**

```bash
bin/rails test test/controllers/posts_controller_test.rb
```

Expected: all green.

- [ ] **Step 7: Commit**

```bash
git add app/controllers/posts_controller.rb test/controllers/posts_controller_test.rb
git commit -m "feat: add restore action to PostsController"
```

---

## Task 3: RepliesController#restore

**Files:**
- Modify: `app/controllers/replies_controller.rb`
- Modify: `test/controllers/replies_controller_test.rb`

- [ ] **Step 1: Write failing tests**

Add these tests at the end of `test/controllers/replies_controller_test.rb` (before the final `end`):

```ruby
  # ---- Restore ----

  test "PATCH restore as moderator clears removed_at and removed_by" do
    reply = Reply.create!(post: @post, user: @user, body: "a reply")
    reply.update!(removed_at: Time.current, removed_by: @sub_admin)
    @post.update_column(:last_replied_at, nil)
    post login_path, params: { email: "sub@example.com", password: "pass123" }
    patch restore_post_reply_path(@post, reply)
    reply.reload
    assert_nil reply.removed_at
    assert_nil reply.removed_by
    assert_redirected_to post_path(@post)
    assert_equal "Reply restored.", flash[:notice]
  end

  test "PATCH restore recalculates post last_replied_at" do
    reply = Reply.create!(post: @post, user: @user, body: "a reply")
    reply.update!(removed_at: Time.current, removed_by: @sub_admin)
    @post.update_column(:last_replied_at, nil)
    post login_path, params: { email: "sub@example.com", password: "pass123" }
    patch restore_post_reply_path(@post, reply)
    @post.reload
    assert_not_nil @post.last_replied_at
  end

  test "PATCH restore broadcasts replace + count to replies stream" do
    reply = Reply.create!(post: @post, user: @user, body: "a reply")
    reply.update!(removed_at: Time.current, removed_by: @sub_admin)
    post login_path, params: { email: "sub@example.com", password: "pass123" }
    assert_broadcasts(Turbo::StreamsChannel.broadcasting_for([ @post, :replies ]), 2) do
      patch restore_post_reply_path(@post, reply)
    end
  end

  test "PATCH restore as non-moderator is rejected" do
    reply = Reply.create!(post: @post, user: @user, body: "a reply")
    reply.update!(removed_at: Time.current, removed_by: @sub_admin)
    post login_path, params: { email: "u@example.com", password: "pass123" }
    patch restore_post_reply_path(@post, reply)
    reply.reload
    assert_not_nil reply.removed_at
    assert_redirected_to root_path
  end
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
bin/rails test test/controllers/replies_controller_test.rb -n "/restore/"
```

Expected: 4 failures / errors.

- [ ] **Step 3: Add before_actions and restore action to RepliesController**

In `app/controllers/replies_controller.rb`:

1. Add a new before_action line after the existing `set_reply` before_action:

```ruby
  before_action :set_reply,          only: [ :edit, :update, :restore ]
  before_action :require_moderator,  only: [ :restore ]
```

2. Add the `restore` action after the `destroy` action:

```ruby
  def restore
    @reply.update!(removed_at: nil, removed_by: nil)
    @post.update_column(:last_replied_at, @post.replies.visible.maximum(:created_at))
    broadcast_reply_restored
    redirect_to @post, notice: "Reply restored."
  end
```

3. Add the `broadcast_reply_restored` private helper after `broadcast_reply_soft_deleted`:

```ruby
    def broadcast_reply_restored
      Turbo::StreamsChannel.broadcast_replace_to(
        [ @post, :replies ],
        target: "reply-#{@reply.id}",
        partial: "replies/reply",
        locals: { reply: @reply, post: @post, flagged_reply_ids: Set.new }
      )
      broadcast_reply_count
    end
```

- [ ] **Step 4: Run restore tests — expect green**

```bash
bin/rails test test/controllers/replies_controller_test.rb -n "/restore/"
```

Expected: 4 tests, 0 failures.

- [ ] **Step 5: Run full replies controller tests for regressions**

```bash
bin/rails test test/controllers/replies_controller_test.rb
```

Expected: all green.

- [ ] **Step 6: Commit**

```bash
git add app/controllers/replies_controller.rb test/controllers/replies_controller_test.rb
git commit -m "feat: add restore action to RepliesController with broadcast"
```

---

## Task 4: Add Restore Button to Views

**Files:**
- Modify: `app/views/posts/show.html.erb`
- Modify: `app/views/replies/_reply.html.erb`

- [ ] **Step 1: Add Restore button to `app/views/posts/show.html.erb`**

The current moderator-only block inside `@post.removed?` (lines 60–64) looks like:

```erb
    <% if logged_in? && current_user.moderator? %>
      <p class="text-xs text-gray-400 mt-1">
        Removed by <%= @post.removed_by.name %> on <%= @post.removed_at.strftime("%B %-d, %Y") %>
      </p>
    <% end %>
```

Replace it with:

```erb
    <% if logged_in? && current_user.moderator? %>
      <p class="text-xs text-gray-400 mt-1">
        Removed by <%= @post.removed_by.name %> on <%= @post.removed_at.strftime("%B %-d, %Y") %>
      </p>
      <%= button_to "Restore", restore_post_path(@post), method: :patch,
            class: "text-xs text-green-600 hover:underline bg-transparent border-0 p-0 cursor-pointer mt-1" %>
    <% end %>
```

- [ ] **Step 2: Add Restore button to `app/views/replies/_reply.html.erb`**

The current moderator-only block inside `reply.removed?` (lines 19–23) looks like:

```erb
    <% if logged_in? && current_user.moderator? %>
      <p class="text-xs text-gray-400 mt-1">
        Removed by <%= reply.removed_by.name %> on <%= reply.removed_at.strftime("%B %-d, %Y") %>
      </p>
    <% end %>
```

Replace it with:

```erb
    <% if logged_in? && current_user.moderator? %>
      <p class="text-xs text-gray-400 mt-1">
        Removed by <%= reply.removed_by.name %> on <%= reply.removed_at.strftime("%B %-d, %Y") %>
      </p>
      <%= button_to "Restore", restore_post_reply_path(post, reply), method: :patch,
            class: "text-xs text-green-600 hover:underline bg-transparent border-0 p-0 cursor-pointer mt-1" %>
    <% end %>
```

- [ ] **Step 3: Run full test suite**

```bash
bin/rails test
```

Expected: all green.

- [ ] **Step 4: Run full CI**

```bash
bin/ci
```

Expected: lint, security, and all tests pass.

- [ ] **Step 5: Commit**

```bash
git add app/views/posts/show.html.erb app/views/replies/_reply.html.erb
git commit -m "feat: add Restore button to post and reply removed sections"
```

---

## Summary

| Task | Files | Tests |
|---|---|---|
| 1. Routes | `routes.rb` | Verified via `rails routes` |
| 2. PostsController#restore | `posts_controller.rb`, `posts_controller_test.rb` | 3 new tests |
| 3. RepliesController#restore | `replies_controller.rb`, `replies_controller_test.rb` | 4 new tests |
| 4. Views | `show.html.erb`, `_reply.html.erb` | Full CI |
