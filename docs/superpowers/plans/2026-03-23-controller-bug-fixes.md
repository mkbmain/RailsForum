# Controller Bug Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix three controller correctness bugs — stale `last_replied_at` on owner hard-delete, empty `edit` action in `RepliesController`, and missing `return` in `PostsController#check_ownership`.

**Architecture:** All three fixes are surgical one-liners or near-one-liners in two controller files. No new files or abstractions needed. Each fix is independently testable and committed separately.

**Tech Stack:** Rails 8.1, Minitest integration tests (`ActionDispatch::IntegrationTest`), PostgreSQL.

---

## File Map

| File | Role |
|------|------|
| `app/controllers/replies_controller.rb` | Bug 1 (hard-delete path) and Bug 2 (edit action) |
| `app/controllers/posts_controller.rb` | Bug 3 (check_ownership) |
| `test/controllers/replies_controller_test.rb` | Tests for bugs 1 & 2 |
| `test/controllers/posts_controller_test.rb` | Test for bug 3 |

---

### Task 1: Fix last_replied_at not updated on owner hard-delete

**Problem:** When the reply owner deletes their own reply (hard-delete path, line 61–64 of `replies_controller.rb`), `@post.last_replied_at` is never updated. The moderator soft-delete path (line 55–60) and the restore path (line 44–49) both call `@post.update_column(:last_replied_at, @post.replies.visible.maximum(:created_at))`. The owner hard-delete path is missing this call.

**Files:**
- Modify: `app/controllers/replies_controller.rb:61-64`
- Modify: `test/controllers/replies_controller_test.rb`

- [ ] **Step 1: Write the failing test**

Add this test to `test/controllers/replies_controller_test.rb`, inside the `# ---- moderation: reply removal ----` section (after line 210):

```ruby
test "DELETE owner hard-delete recalculates post last_replied_at" do
  reply = Reply.create!(post: @post, user: @user, body: "Only reply")
  @post.update_column(:last_replied_at, 1.hour.ago)
  post login_path, params: { email: "u@example.com", password: "pass123" }
  delete post_reply_path(@post, reply)
  assert_nil @post.reload.last_replied_at
end
```

> **Why nil?** After deleting the only visible reply, `@post.replies.visible.maximum(:created_at)` returns `nil`. The test verifies the timestamp is recalculated (not left stale at `1.hour.ago`).

- [ ] **Step 2: Run the test to verify it fails**

```bash
bin/rails test test/controllers/replies_controller_test.rb -n "test_DELETE_owner_hard-delete_recalculates_post_last_replied_at"
```

Expected: FAIL — `last_replied_at` remains `1.hour.ago` instead of becoming `nil`.

- [ ] **Step 3: Apply the fix**

In `app/controllers/replies_controller.rb`, find the hard-delete branch (around line 61):

```ruby
# BEFORE
elsif @reply.user == current_user
  @reply.destroy
  broadcast_reply_hard_deleted
  redirect_to @post, notice: "Reply deleted."
```

Change to:

```ruby
# AFTER
elsif @reply.user == current_user
  @reply.destroy
  @post.update_column(:last_replied_at, @post.replies.visible.maximum(:created_at))
  broadcast_reply_hard_deleted
  redirect_to @post, notice: "Reply deleted."
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
bin/rails test test/controllers/replies_controller_test.rb -n "test_DELETE_owner_hard-delete_recalculates_post_last_replied_at"
```

Expected: PASS.

- [ ] **Step 5: Run the full replies controller test suite to catch regressions**

```bash
bin/rails test test/controllers/replies_controller_test.rb
```

Expected: all green.

- [ ] **Step 6: Commit**

```bash
git add app/controllers/replies_controller.rb test/controllers/replies_controller_test.rb
git commit -m "fix: recalculate last_replied_at on owner hard-delete of reply"
```

---

### Task 2: Explicitly set @post in RepliesController#edit

**Problem:** `def edit` has an empty body. `@post` is set as a side-effect of the `set_reply` before-action (which sets `@post = Post.find(params[:post_id])` and `@reply = @post.replies.find(params[:id])`). The view (`app/views/replies/edit.html.erb`) uses `@post` for the form URL (`form_with model: [@post, @reply]`) and the Cancel link (`link_to "Cancel", @post`). If `set_reply` is ever refactored to not assign `@post`, the view silently breaks with a nil-routing error. Add a test documenting the Cancel-link requirement, then make the assignment explicit.

**Files:**
- Modify: `app/controllers/replies_controller.rb:32-33`
- Modify: `test/controllers/replies_controller_test.rb`

- [ ] **Step 1: Write the test**

Add to the `# ---- edit / update ----` section of `test/controllers/replies_controller_test.rb` (after the existing edit tests):

```ruby
test "GET /posts/:post_id/replies/:id/edit cancel link points to parent post" do
  post login_path, params: { email: "u@example.com", password: "pass123" }
  reply = Reply.create!(post: @post, user: @user, body: "My reply")
  get edit_post_reply_path(@post, reply)
  assert_response :success
  assert_select "a[href=?]", post_path(@post), text: /cancel/i
end
```

- [ ] **Step 2: Run the test to confirm it currently passes**

```bash
bin/rails test test/controllers/replies_controller_test.rb -n "test_GET_/posts/:post_id/replies/:id/edit_cancel_link_points_to_parent_post"
```

Expected: PASS (documents existing behavior; guards against future regressions if `set_reply` changes).

- [ ] **Step 3: Make the assignment explicit in the action**

In `app/controllers/replies_controller.rb`, change:

```ruby
def edit
end
```

To:

```ruby
def edit
  # @post and @reply are assigned by set_reply before_action
end
```

> This is intentionally a comment rather than a duplicate `@post = Post.find(...)` assignment, because `set_reply` is authoritative for the parent-post lookup shared by `edit`, `update`, and `restore`. Adding a redundant find would create a silent disagreement if `set_reply` diverges. The comment makes the implicit dependency visible without creating two sources of truth.

- [ ] **Step 4: Run tests to confirm nothing broke**

```bash
bin/rails test test/controllers/replies_controller_test.rb
```

Expected: all green.

- [ ] **Step 5: Commit**

```bash
git add app/controllers/replies_controller.rb test/controllers/replies_controller_test.rb
git commit -m "test: document that replies#edit relies on set_reply for @post and @reply"
```

---

### Task 3: Add missing return in PostsController#check_ownership

**Problem:** In `app/controllers/posts_controller.rb`, `check_ownership` (around line 112) redirects when the post does not belong to the current user but does not `return`. The `check_edit_window` before-action runs next and may also call `redirect_to`, causing `AbstractController::DoubleRenderError` when a non-owner tries to edit a post whose edit window has also expired.

```ruby
# CURRENT (buggy)
def check_ownership
  if @post.removed?
    return redirect_to(@post, alert: "This content has been removed and can no longer be edited.")
  end
  unless @post.user == current_user
    redirect_to(@post, alert: "Not authorized to edit this post.")  # missing return
  end
end
```

**Files:**
- Modify: `app/controllers/posts_controller.rb:116-118`
- Modify: `test/controllers/posts_controller_test.rb`

- [ ] **Step 1: Write the failing test**

The test needs a second user. Check `test/controllers/posts_controller_test.rb` setup to see if `@other_user` already exists. The setup creates `@user` but not a second user, so create one inline.

Add to `test/controllers/posts_controller_test.rb` in the ownership/edit section:

```ruby
test "GET /posts/:id/edit by non-owner when edit window also expired redirects with not-authorized message" do
  other = User.create!(email: "other@example.com", name: "Other",
                       password: "pass123", password_confirmation: "pass123", provider_id: 3)
  other_post = Post.create!(user: other, title: "Other Post", body: "body")
  other_post.update_column(:created_at, (EDIT_WINDOW_SECONDS + 1).seconds.ago)
  post login_path, params: { email: "u@example.com", password: "pass123" }
  get edit_post_path(other_post)
  assert_redirected_to post_path(other_post)
  assert_match /not authorized/i, flash[:alert]
end

test "PATCH /posts/:id by non-owner when edit window also expired redirects with not-authorized message" do
  other = User.create!(email: "other@example.com", name: "Other",
                       password: "pass123", password_confirmation: "pass123", provider_id: 3)
  other_post = Post.create!(user: other, title: "Other Post", body: "body")
  other_post.update_column(:created_at, (EDIT_WINDOW_SECONDS + 1).seconds.ago)
  post login_path, params: { email: "u@example.com", password: "pass123" }
  patch post_path(other_post), params: { post: { title: "Hacked", body: "hacked" } }
  assert_redirected_to post_path(other_post)
  assert_match /not authorized/i, flash[:alert]
end
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
bin/rails test test/controllers/posts_controller_test.rb -n "test_GET_/posts/:id/edit_by_non-owner_when_edit_window_also_expired_redirects_with_not-authorized_message"
```

Expected: FAIL — either `AbstractController::DoubleRenderError` is raised, or the flash message says "can no longer be edited" instead of "not authorized".

- [ ] **Step 3: Apply the fix**

In `app/controllers/posts_controller.rb`, find `check_ownership` (around line 112):

```ruby
# BEFORE
def check_ownership
  if @post.removed?
    return redirect_to(@post, alert: "This content has been removed and can no longer be edited.")
  end
  unless @post.user == current_user
    redirect_to(@post, alert: "Not authorized to edit this post.")
  end
end
```

Change to:

```ruby
# AFTER
def check_ownership
  if @post.removed?
    return redirect_to(@post, alert: "This content has been removed and can no longer be edited.")
  end
  unless @post.user == current_user
    return redirect_to(@post, alert: "Not authorized to edit this post.")
  end
end
```

- [ ] **Step 4: Run the new tests to verify they pass**

```bash
bin/rails test test/controllers/posts_controller_test.rb -n "test_GET_/posts/:id/edit_by_non-owner_when_edit_window_also_expired_redirects_with_not-authorized_message"
bin/rails test test/controllers/posts_controller_test.rb -n "test_PATCH_/posts/:id_by_non-owner_when_edit_window_also_expired_redirects_with_not-authorized_message"
```

Expected: both PASS.

- [ ] **Step 5: Run the full posts controller test suite to catch regressions**

```bash
bin/rails test test/controllers/posts_controller_test.rb
```

Expected: all green.

- [ ] **Step 6: Run the full test suite**

```bash
bin/rails test
```

Expected: all green.

- [ ] **Step 7: Commit**

```bash
git add app/controllers/posts_controller.rb test/controllers/posts_controller_test.rb
git commit -m "fix: add missing return in PostsController#check_ownership to prevent double-redirect"
```
