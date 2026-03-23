# Bug & Security Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix 9 confirmed bugs and security issues across auth, data integrity, XSS, mention parsing, pagination, and query performance.

**Architecture:** Each fix is isolated to its own commit. Auth fixes land first (1a–1d) because later tests rely on correct redirect behavior. Data and security fixes follow (2a–2b). Logic and perf fixes last (3a–3c). Run `bin/rails test` and `bin/rubocop` after every task.

**Tech Stack:** Rails 8.1, PostgreSQL, Minitest (ActionDispatch::IntegrationTest for controllers, ActiveSupport::TestCase for services/models), Redcarpet, Hotwire/Stimulus.

**Spec:** `docs/superpowers/specs/2026-03-23-bug-and-security-fixes-design.md`

---

## File Map

| File | Tasks |
|------|-------|
| `app/controllers/posts_controller.rb` | 1a, 1b, 3c |
| `app/controllers/replies_controller.rb` | 1a, 1b, 1c |
| `app/controllers/concerns/moderatable.rb` | 1d |
| `app/models/user.rb` | 2a, 3a |
| `db/migrate/YYYYMMDDHHMMSS_fix_email_index_case_sensitivity.rb` | 2a (new) |
| `app/helpers/application_helper.rb` | 2b |
| `app/services/notification_service.rb` | 3a |
| `app/views/posts/show.html.erb` | 3a |
| `app/controllers/admin/users_controller.rb` | 3b |
| `app/views/admin/users/show.html.erb` | 3b |
| `app/views/posts/index.html.erb` | 3c |
| `test/controllers/posts_controller_test.rb` | 1a, 1b |
| `test/controllers/replies_controller_test.rb` | 1a, 1b, 1c |
| `test/controllers/moderatable_test.rb` | 1d |
| `test/models/user_test.rb` | 2a, 3a |
| `test/helpers/application_helper_test.rb` | 2b |
| `test/services/notification_service_test.rb` | 3a |
| `test/controllers/admin/users_controller_test.rb` | 3b |

---

## Task 1a: Fix missing `return` in before-action guards

`check_ownership` and `check_edit_window` in both controllers call `redirect_to` without returning. In Rails, `redirect_to` sets the response but execution continues — the action body still runs. Use `return redirect_to(...)` to halt immediately.

**Files:**
- Modify: `app/controllers/posts_controller.rb:107-117`
- Modify: `app/controllers/replies_controller.rb:76-86`
- Modify: `test/controllers/posts_controller_test.rb`
- Modify: `test/controllers/replies_controller_test.rb`

- [ ] **Step 1: Write failing tests**

Add to `test/controllers/posts_controller_test.rb` (inside the class, after existing tests):

```ruby
test "PATCH /posts/:id by non-owner redirects and does not update" do
  other = User.create!(email: "other@example.com", name: "Other",
                       password: "pass123", password_confirmation: "pass123", provider_id: 3)
  post login_path, params: { email: "other@example.com", password: "pass123" }
  original_title = @post.title
  patch post_path(@post), params: { post: { title: "Hijacked" } }
  assert_redirected_to post_path(@post)
  assert_equal original_title, @post.reload.title
end

test "PATCH /posts/:id outside edit window redirects and does not update" do
  post login_path, params: { email: "u@example.com", password: "pass123" }
  travel_to(PostsController::EDIT_WINDOW_SECONDS.seconds.from_now + 1.second) do
    patch post_path(@post), params: { post: { title: "Late edit" } }
    assert_redirected_to post_path(@post)
    assert_equal "Hello World", @post.reload.title
  end
end
```

Add to `test/controllers/replies_controller_test.rb`:

```ruby
test "PATCH /posts/:post_id/replies/:id by non-owner redirects and does not update" do
  reply = Reply.create!(post: @post, user: @user, body: "Original body")
  other = User.create!(email: "other@example.com", name: "Other",
                       password: "pass123", password_confirmation: "pass123", provider_id: 3)
  post login_path, params: { email: "other@example.com", password: "pass123" }
  patch post_reply_path(@post, reply), params: { reply: { body: "Hijacked" } }
  assert_redirected_to post_path(@post)
  assert_equal "Original body", reply.reload.body
end

test "PATCH /posts/:post_id/replies/:id outside edit window redirects and does not update" do
  reply = Reply.create!(post: @post, user: @user, body: "Original body")
  post login_path, params: { email: "u@example.com", password: "pass123" }
  travel_to(RepliesController::EDIT_WINDOW_SECONDS.seconds.from_now + 1.second) do
    patch post_reply_path(@post, reply), params: { reply: { body: "Late edit" } }
    assert_redirected_to post_path(@post)
    assert_equal "Original body", reply.reload.body
  end
end
```

- [ ] **Step 2: Run tests to confirm they fail (or pass trivially — check for double-render warnings)**

```bash
bin/rails test test/controllers/posts_controller_test.rb test/controllers/replies_controller_test.rb 2>&1 | grep -E "FAIL|ERROR|pass"
```

- [ ] **Step 3: Fix `posts_controller.rb` — add `return` to both guards**

In `app/controllers/posts_controller.rb`, change `check_ownership` (line 107) and `check_edit_window` (line 113):

```ruby
def check_ownership
  unless @post.user == current_user
    return redirect_to(@post, alert: "Not authorized to edit this post.")
  end
end

def check_edit_window
  if Time.current - @post.created_at > EDIT_WINDOW_SECONDS
    return redirect_to(@post, alert: "This post can no longer be edited (edit window has expired).")
  end
end
```

- [ ] **Step 4: Fix `replies_controller.rb` — add `return` to both guards**

In `app/controllers/replies_controller.rb`, change `check_ownership` (line 76) and `check_edit_window` (line 82):

```ruby
def check_ownership
  unless @reply.user == current_user
    return redirect_to(@post, alert: "Not authorized to edit this reply.")
  end
end

def check_edit_window
  if Time.current - @reply.created_at > EDIT_WINDOW_SECONDS
    return redirect_to(@post, alert: "This reply can no longer be edited (edit window has expired).")
  end
end
```

- [ ] **Step 5: Run tests**

```bash
bin/rails test test/controllers/posts_controller_test.rb test/controllers/replies_controller_test.rb
```

Expected: all pass, no double-render warnings.

- [ ] **Step 6: Lint**

```bash
bin/rubocop app/controllers/posts_controller.rb app/controllers/replies_controller.rb
```

- [ ] **Step 7: Commit**

```bash
git add app/controllers/posts_controller.rb app/controllers/replies_controller.rb \
        test/controllers/posts_controller_test.rb test/controllers/replies_controller_test.rb
git commit -m "fix: return after redirect_to in check_ownership and check_edit_window"
```

---

## Task 1b: Block owners from editing soft-deleted content

Moderators soft-delete content by setting `removed_at`. Owners can still `PATCH` their own removed posts/replies because `check_ownership` only checks ownership, not removal status.

**Files:**
- Modify: `app/controllers/posts_controller.rb:107-111`
- Modify: `app/controllers/replies_controller.rb:76-80`
- Modify: `test/controllers/posts_controller_test.rb`
- Modify: `test/controllers/replies_controller_test.rb`

- [ ] **Step 1: Write failing tests**

Add to `test/controllers/posts_controller_test.rb`:

```ruby
test "GET /posts/:id/edit for removed post owned by user redirects" do
  @post.update_columns(removed_at: Time.current, removed_by_id: @admin.id)
  post login_path, params: { email: "u@example.com", password: "pass123" }
  get edit_post_path(@post)
  assert_redirected_to post_path(@post)
  assert_equal "This content has been removed and can no longer be edited.", flash[:alert]
end

test "PATCH /posts/:id for removed post owned by user does not update" do
  @post.update_columns(removed_at: Time.current, removed_by_id: @admin.id)
  post login_path, params: { email: "u@example.com", password: "pass123" }
  patch post_path(@post), params: { post: { title: "Restore attempt" } }
  assert_redirected_to post_path(@post)
  assert_equal "Hello World", @post.reload.title
end
```

Add to `test/controllers/replies_controller_test.rb`:

```ruby
test "GET /posts/:post_id/replies/:id/edit for removed reply owned by user redirects" do
  reply = Reply.create!(post: @post, user: @user, body: "My reply")
  reply.update_columns(removed_at: Time.current, removed_by_id: @admin.id)
  post login_path, params: { email: "u@example.com", password: "pass123" }
  get edit_post_reply_path(@post, reply)
  assert_redirected_to post_path(@post)
  assert_equal "This content has been removed and can no longer be edited.", flash[:alert]
end

test "PATCH /posts/:post_id/replies/:id for removed reply owned by user does not update" do
  reply = Reply.create!(post: @post, user: @user, body: "My reply")
  reply.update_columns(removed_at: Time.current, removed_by_id: @admin.id)
  post login_path, params: { email: "u@example.com", password: "pass123" }
  patch post_reply_path(@post, reply), params: { reply: { body: "Changed" } }
  assert_redirected_to post_path(@post)
  assert_equal "My reply", reply.reload.body
end
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
bin/rails test test/controllers/posts_controller_test.rb test/controllers/replies_controller_test.rb 2>&1 | grep -E "FAIL|ERROR"
```

- [ ] **Step 3: Update `check_ownership` in `posts_controller.rb`**

```ruby
def check_ownership
  if @post.removed?
    return redirect_to(@post, alert: "This content has been removed and can no longer be edited.")
  end
  unless @post.user == current_user
    return redirect_to(@post, alert: "Not authorized to edit this post.")
  end
end
```

- [ ] **Step 4: Update `check_ownership` in `replies_controller.rb`**

```ruby
def check_ownership
  if @reply.removed?
    return redirect_to(@post, alert: "This content has been removed and can no longer be edited.")
  end
  unless @reply.user == current_user
    return redirect_to(@post, alert: "Not authorized to edit this reply.")
  end
end
```

- [ ] **Step 5: Run tests**

```bash
bin/rails test test/controllers/posts_controller_test.rb test/controllers/replies_controller_test.rb
```

Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add app/controllers/posts_controller.rb app/controllers/replies_controller.rb \
        test/controllers/posts_controller_test.rb test/controllers/replies_controller_test.rb
git commit -m "fix: block owners from editing soft-deleted posts and replies"
```

---

## Task 1c: Block reply edits when parent post is removed

Even after 1b, a user can edit their reply on a removed post (the reply itself isn't removed — the post is). `RepliesController` loads `@post` via `set_reply` but never checks `@post.removed?`.

**Files:**
- Modify: `app/controllers/replies_controller.rb`
- Modify: `test/controllers/replies_controller_test.rb`

- [ ] **Step 1: Write failing test**

Add to `test/controllers/replies_controller_test.rb`:

```ruby
test "GET /posts/:post_id/replies/:id/edit redirects when parent post is removed" do
  reply = Reply.create!(post: @post, user: @user, body: "My reply")
  @post.update_columns(removed_at: Time.current, removed_by_id: @admin.id)
  post login_path, params: { email: "u@example.com", password: "pass123" }
  get edit_post_reply_path(@post, reply)
  assert_redirected_to posts_path
  assert_equal "This post is no longer available.", flash[:alert]
end

test "PATCH /posts/:post_id/replies/:id does not update when parent post is removed" do
  reply = Reply.create!(post: @post, user: @user, body: "Original")
  @post.update_columns(removed_at: Time.current, removed_by_id: @admin.id)
  post login_path, params: { email: "u@example.com", password: "pass123" }
  patch post_reply_path(@post, reply), params: { reply: { body: "Changed" } }
  assert_redirected_to posts_path
  assert_equal "Original", reply.reload.body
end
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
bin/rails test test/controllers/replies_controller_test.rb 2>&1 | grep -E "FAIL|ERROR"
```

- [ ] **Step 3: Add `check_post_not_removed` to `replies_controller.rb`**

Add the before-action declaration **after** `before_action :set_reply` (line 8), and add the private method. The declaration order matters — `@post` is set by `set_reply`, so this must come after:

```ruby
# In the before_action block, after line 8:
before_action :check_post_not_removed, only: [ :edit, :update ]

# In the private section:
def check_post_not_removed
  return redirect_to(posts_path, alert: "This post is no longer available.") if @post.removed?
end
```

- [ ] **Step 4: Run tests**

```bash
bin/rails test test/controllers/replies_controller_test.rb
```

Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add app/controllers/replies_controller.rb test/controllers/replies_controller_test.rb
git commit -m "fix: block reply edits when parent post has been removed"
```

---

## Task 1d: Block admin-on-admin moderation

`can_moderate?(target_user)` in `Moderatable` concern returns `true` for any admin unconditionally, before the `!target_user.admin?` guard on line 18. A one-line fix closes this.

**Files:**
- Modify: `app/controllers/concerns/moderatable.rb:14-19`
- Modify: `test/controllers/moderatable_test.rb`

- [ ] **Step 1: Write failing test**

The existing `moderatable_test.rb` tests role predicates. Add integration tests that verify the HTTP behavior. Add to `test/controllers/moderatable_test.rb`:

```ruby
test "admin cannot remove a post authored by another admin" do
  admin2 = User.create!(email: "admin2@example.com", name: "Admin Two",
                        password: "pass123", password_confirmation: "pass123",
                        provider_id: 3)
  admin2.roles << Role.find_by!(name: Role::ADMIN)
  target_post = Post.create!(user: admin2, title: "Admin Post", body: "Admin content")

  post login_path, params: { email: "admin@example.com", password: "pass123" }
  delete post_path(target_post)
  # Should be denied — admin cannot moderate another admin's content
  assert_redirected_to post_path(target_post)
  assert_not target_post.reload.removed?, "Post should not have been soft-deleted"
end

test "admin can still remove a post authored by a regular user" do
  regular_post = Post.create!(user: @creator, title: "Regular Post", body: "body")
  post login_path, params: { email: "admin@example.com", password: "pass123" }
  delete post_path(regular_post)
  # Should succeed — admin moderating a non-admin
  assert regular_post.reload.removed?, "Post should be soft-deleted"
end
```

Note: this test inherits the `setup` block from `ModeratableTest` which creates `@creator`, `@sub_admin`, and `@admin`. You also need `login_path` — check that `sessions` routes are available in this test class (they should be, since it's `ActionDispatch::IntegrationTest`).

- [ ] **Step 2: Run tests to confirm they fail**

```bash
bin/rails test test/controllers/moderatable_test.rb 2>&1 | grep -E "FAIL|ERROR"
```

- [ ] **Step 3: Add guard to `can_moderate?` in `moderatable.rb`**

Open `app/controllers/concerns/moderatable.rb`. The current method (lines 14–19):

```ruby
def can_moderate?(target_user)
  return false unless current_user&.moderator?
  return false if current_user == target_user
  return true if current_user.admin?
  !target_user.sub_admin? && !target_user.admin?
end
```

Add one line before `return true if current_user.admin?`:

```ruby
def can_moderate?(target_user)
  return false unless current_user&.moderator?
  return false if current_user == target_user
  return false if target_user.admin?
  return true if current_user.admin?
  !target_user.sub_admin? && !target_user.admin?
end
```

- [ ] **Step 4: Run tests**

```bash
bin/rails test test/controllers/moderatable_test.rb
```

Expected: all pass.

- [ ] **Step 5: Run full suite to check for regressions**

```bash
bin/rails test
```

- [ ] **Step 6: Commit**

```bash
git add app/controllers/concerns/moderatable.rb test/controllers/moderatable_test.rb
git commit -m "fix: prevent admins from moderating other admins' content"
```

---

## Task 2a: Case-insensitive email unique index + normalization

The DB index `index_users_on_email` is a case-sensitive btree, but the model validates `case_sensitive: false`. Two accounts can exist for the same email differing only in case. Also, no `before_save` normalizes email casing, so stored emails can have mixed case.

**Files:**
- Create: `db/migrate/YYYYMMDDHHMMSS_fix_email_index_case_sensitivity.rb`
- Modify: `app/models/user.rb`
- Modify: `test/models/user_test.rb`

- [ ] **Step 1: Write failing test**

Add to `test/models/user_test.rb`:

```ruby
test "email is normalized to lowercase before save" do
  user = User.create!(email: "TEST@EXAMPLE.COM", name: "Tester",
                      password: "pass123", password_confirmation: "pass123",
                      provider_id: Provider.find_or_create_by!(id: 3, name: "internal").id)
  assert_equal "test@example.com", user.reload.email
end

test "email uniqueness is enforced case-insensitively at DB level" do
  provider = Provider.find_or_create_by!(id: 3, name: "internal")
  User.create!(email: "dupe@example.com", name: "First",
               password: "pass123", password_confirmation: "pass123", provider_id: provider.id)
  # Bypass model validations to test the DB index directly.
  # `before_save` normalizes email, so insert raw SQL to simulate a mixed-case duplicate
  # that would slip through without the functional index.
  assert_raises(ActiveRecord::RecordNotUnique) do
    ActiveRecord::Base.connection.execute(
      "INSERT INTO users (email, name, password_digest, provider_id, created_at, updated_at) " \
      "VALUES ('DUPE@EXAMPLE.COM', 'Second', 'x', #{provider.id}, NOW(), NOW())"
    )
  end
end
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
bin/rails test test/models/user_test.rb 2>&1 | grep -E "FAIL|ERROR"
```

- [ ] **Step 3: Generate the migration**

```bash
bin/rails generate migration FixEmailIndexCaseSensitivity
```

Open the generated file in `db/migrate/` and replace the body with:

```ruby
class FixEmailIndexCaseSensitivity < ActiveRecord::Migration[8.1]
  def up
    remove_index :users, :email, name: "index_users_on_email"
    execute "CREATE UNIQUE INDEX index_users_on_lower_email ON users (LOWER(email))"
  end

  def down
    execute "DROP INDEX index_users_on_lower_email"
    add_index :users, :email, unique: true, name: "index_users_on_email"
  end
end
```

- [ ] **Step 4: Run the migration**

```bash
bin/rails db:migrate
```

- [ ] **Step 5: Add `before_save` normalization to `User` model**

In `app/models/user.rb`, add before the validations block (or near the top of the callbacks section):

```ruby
before_save { self.email = email&.downcase&.strip }
```

- [ ] **Step 6: Run tests**

```bash
bin/rails test test/models/user_test.rb
```

Expected: both new tests pass.

- [ ] **Step 7: Commit**

```bash
git add db/migrate/ db/structure.sql app/models/user.rb test/models/user_test.rb
git commit -m "fix: enforce case-insensitive email uniqueness via functional index and before_save normalization"
```

---

## Task 2b: Markdown XSS via `javascript:` URIs

`render_markdown` in `application_helper.rb` sanitizes HTML with a tag allowlist but no `protocols:` restriction. A Markdown link `[x](javascript:alert(1))` produces a live XSS vector.

**Files:**
- Modify: `app/helpers/application_helper.rb`
- Modify: `test/helpers/application_helper_test.rb`

- [ ] **Step 1: Write failing test**

Add to `test/helpers/application_helper_test.rb`:

```ruby
test "javascript: href is stripped from links" do
  output = render_markdown("[evil](javascript:alert(1))")
  assert_not_includes output, "javascript:"
end

test "data: href is stripped from links" do
  output = render_markdown("[evil](data:text/html,<script>alert(1)</script>)")
  assert_not_includes output, "data:"
end

test "https links are preserved" do
  output = render_markdown("[safe](https://example.com)")
  assert_includes output, 'href="https://example.com"'
end

test "relative links are preserved" do
  output = render_markdown("[relative](/posts/1)")
  assert_includes output, 'href="/posts/1"'
end
```

- [ ] **Step 2: Run tests to confirm the XSS tests fail**

```bash
bin/rails test test/helpers/application_helper_test.rb 2>&1 | grep -E "FAIL|ERROR"
```

- [ ] **Step 3: Add `protocols:` restriction to `render_markdown`**

In `app/helpers/application_helper.rb`, find the `sanitize` call in `render_markdown` and add a `protocols:` key:

```ruby
sanitize(
  parser.render(text.to_s),
  tags: MARKDOWN_ALLOWED_TAGS,
  protocols: { "a" => { "href" => [ "http", "https", "mailto", :relative ] } }
)
```

The `:relative` symbol tells Rails' sanitizer to permit relative paths like `/posts/1`. Any scheme not in this list — including `javascript:`, `data:`, `vbscript:` — is stripped from the `href`.

- [ ] **Step 4: Run tests**

```bash
bin/rails test test/helpers/application_helper_test.rb
```

Expected: all pass including existing tests.

- [ ] **Step 5: Commit**

```bash
git add app/helpers/application_helper.rb test/helpers/application_helper_test.rb
git commit -m "fix: strip javascript: and data: URIs from markdown links"
```

---

## Task 3a: Fix mention parsing for names with non-word characters

The mention autocomplete emits tokens like `@John_Doe` (spaces → underscores). The regex `/@(\w+)/` and lookup work correctly for names with letters and spaces. **The bug is names containing non-`\w` characters** (apostrophes, hyphens, dots): `"O'Brien"` emits token `@O'Brien`, the regex captures only `"O"`, and no user is found.

Fix: add `mention_handle` on `User` that strips non-word chars, update the autocomplete token generation to use it, and update `NotificationService` to look up by handle.

**Files:**
- Modify: `app/models/user.rb`
- Modify: `app/services/notification_service.rb:50`
- Modify: `app/views/posts/show.html.erb` (the `data-mention-autocomplete-users-value` attribute)
- Modify: `test/models/user_test.rb`
- Modify: `test/services/notification_service_test.rb`

- [ ] **Step 1: Write failing model tests**

Add to `test/models/user_test.rb`:

```ruby
test "mention_handle converts spaces to underscores and lowercases" do
  user = User.new(name: "John Doe")
  assert_equal "john_doe", user.mention_handle
end

test "mention_handle strips apostrophes" do
  user = User.new(name: "O'Brien")
  assert_equal "obrien", user.mention_handle
end

test "mention_handle strips hyphens" do
  user = User.new(name: "Mary-Jane")
  assert_equal "maryjane", user.mention_handle
end

test "find_by_mention_handle finds user with special-char name" do
  provider = Provider.find_or_create_by!(id: 3, name: "internal")
  user = User.create!(email: "obrien@example.com", name: "O'Brien",
                      password: "pass123", password_confirmation: "pass123",
                      provider_id: provider.id)
  assert_equal user, User.find_by_mention_handle("OBrien")
end

test "find_by_mention_handle still finds user with plain space name" do
  provider = Provider.find_or_create_by!(id: 3, name: "internal")
  user = User.create!(email: "jdoe@example.com", name: "John Doe",
                      password: "pass123", password_confirmation: "pass123",
                      provider_id: provider.id)
  assert_equal user, User.find_by_mention_handle("John_Doe")
end
```

- [ ] **Step 2: Write failing notification service test**

Add to `test/services/notification_service_test.rb`:

```ruby
test "mentions work for users with apostrophes in names" do
  provider = Provider.find_or_create_by!(id: 3, name: "internal")
  obrien = User.create!(email: "obrien@example.com", name: "O'Brien",
                        password: "pass123", password_confirmation: "pass123",
                        provider_id: provider.id)
  mentioning_reply = Reply.create!(post: @post, user: @replier, body: "Hey @OBrien check this out")
  assert_difference "Notification.where(event_type: :mention, user: obrien).count", 1 do
    NotificationService.reply_created(mentioning_reply, current_user: @replier)
  end
end
```

- [ ] **Step 3: Run tests to confirm they fail**

```bash
bin/rails test test/models/user_test.rb test/services/notification_service_test.rb 2>&1 | grep -E "FAIL|ERROR"
```

- [ ] **Step 4: Add `mention_handle` and `find_by_mention_handle` to `User` model**

In `app/models/user.rb`, add two methods in the public section:

```ruby
def mention_handle
  name.gsub(" ", "_").gsub(/[^\w]/, "").downcase
end

def self.find_by_mention_handle(handle)
  # Convert underscores → spaces to match stored name (sanitize_name ensures no underscores in DB)
  # Then strip remaining non-alphanumeric chars to match names like "O'Brien" → "obrien"
  normalized = handle.downcase.gsub("_", " ")
  find_by(
    "LOWER(REGEXP_REPLACE(name, '[^a-z0-9 ]', '', 'g')) = LOWER(REGEXP_REPLACE(?, '[^a-z0-9 ]', '', 'g'))",
    normalized
  )
end
```

Note: uses PostgreSQL `REGEXP_REPLACE` with POSIX character class `[^a-z0-9 ]`. Do not use `\w` in PostgreSQL regex — it is unreliable.

- [ ] **Step 5: Update `NotificationService` (line 50) to use `find_by_mention_handle`**

In `app/services/notification_service.rb`, find line 50:

```ruby
# Before:
mentioned = User.find_by("LOWER(name) = LOWER(?)", username.gsub("_", " "))

# After:
mentioned = User.find_by_mention_handle(username)
```

- [ ] **Step 6: Update autocomplete token generation in `posts/show.html.erb`**

Find the `data-mention-autocomplete-users-value` attribute (line 109). Change:

```erb
<%# Before — generates tokens like "John_Doe" via gsub %>
data-mention-autocomplete-users-value="<%= html_escape(@mention_users.map { |u| { token: u.name.gsub(' ', '_'), display: u.name } }.to_json) %>"

<%# After — uses mention_handle which also strips special chars %>
data-mention-autocomplete-users-value="<%= html_escape(@mention_users.map { |u| { token: u.mention_handle, display: u.name } }.to_json) %>"
```

- [ ] **Step 7: Run tests**

```bash
bin/rails test test/models/user_test.rb test/services/notification_service_test.rb
```

Expected: all pass.

- [ ] **Step 8: Run full suite**

```bash
bin/rails test
```

- [ ] **Step 9: Commit**

```bash
git add app/models/user.rb app/services/notification_service.rb \
        app/views/posts/show.html.erb \
        test/models/user_test.rb test/services/notification_service_test.rb
git commit -m "fix: mention parsing for names with apostrophes, hyphens, and other non-word characters"
```

---

## Task 3b: Fix admin activity tab pagination per content type

The activity tab fetches bans, posts, and replies independently but uses a single `@has_more` (OR across all three) and a shared `page` param. If only bans overflow, the "Next" link appears for all types. Fix: per-type page params and per-type `@has_more` flags. The view's shared pagination block must also be updated.

**Files:**
- Modify: `app/controllers/admin/users_controller.rb:53-68`
- Modify: `app/views/admin/users/show.html.erb:218-234` (shared pagination) + the activity section
- Modify: `test/controllers/admin/users_controller_test.rb`

- [ ] **Step 1: Write failing test**

Add to `test/controllers/admin/users_controller_test.rb`. First check how this test file sets up its admin user; if the pattern differs from other test files, follow the existing pattern in the file. Then add:

```ruby
test "activity tab sets has_more per collection independently" do
  # Create enough bans to overflow (TAB_PER_PAGE = 30), but no removed posts
  admin_user = User.find_by(email: "admin@example.com")  # or however your setup creates one
  acting_admin = # whichever admin can view this page

  (Admin::UsersController::TAB_PER_PAGE + 1).times do |i|
    banned = User.create!(email: "banned#{i}@example.com", name: "Banned #{i}",
                          password: "pass123", password_confirmation: "pass123",
                          provider_id: 3)
    UserBan.create!(user: banned, banned_by: admin_user,
                    banned_until: 1.year.from_now, banned_from: Time.current)
  end

  get admin_user_path(admin_user, tab: "activity")
  assert_response :success
  assert assigns(:bans_has_more), "bans should have more"
  assert_not assigns(:posts_has_more), "posts should not have more (none exist)"
  assert_not assigns(:replies_has_more), "replies should not have more (none exist)"
end
```

Note: look at existing tests in `test/controllers/admin/users_controller_test.rb` to understand the login setup and how the admin user is authenticated.

- [ ] **Step 2: Run test to confirm it fails**

```bash
bin/rails test test/controllers/admin/users_controller_test.rb 2>&1 | grep -E "FAIL|ERROR"
```

- [ ] **Step 3: Update the `when "activity"` branch in `admin/users_controller.rb`**

Replace lines 53–68 with:

```ruby
when "activity"
  bans_page    = [ (params[:bans_page]    || 1).to_i, 1 ].max
  posts_page   = [ (params[:posts_page]   || 1).to_i, 1 ].max
  replies_page = [ (params[:replies_page] || 1).to_i, 1 ].max

  bans_raw    = UserBan.where(banned_by: @user).includes(:user, :ban_reason)
                       .order(banned_from: :desc)
                       .limit(TAB_PER_PAGE + 1).offset((bans_page - 1) * TAB_PER_PAGE).to_a
  posts_raw   = Post.where(removed_by: @user).includes(:user)
                    .order(removed_at: :desc)
                    .limit(TAB_PER_PAGE + 1).offset((posts_page - 1) * TAB_PER_PAGE).to_a
  replies_raw = Reply.where(removed_by: @user).includes(:user, :post)
                     .order(removed_at: :desc)
                     .limit(TAB_PER_PAGE + 1).offset((replies_page - 1) * TAB_PER_PAGE).to_a

  @bans_has_more    = bans_raw.size > TAB_PER_PAGE
  @posts_has_more   = posts_raw.size > TAB_PER_PAGE
  @replies_has_more = replies_raw.size > TAB_PER_PAGE
  @bans_page        = bans_page
  @posts_page       = posts_page
  @replies_page     = replies_page
  @bans_issued      = bans_raw.first(TAB_PER_PAGE)
  @posts_removed    = posts_raw.first(TAB_PER_PAGE)
  @replies_removed  = replies_raw.first(TAB_PER_PAGE)
```

- [ ] **Step 4: Update the view — shared pagination block**

In `app/views/admin/users/show.html.erb`, the shared pagination block (lines 218–234) uses `@has_more` and `@page`. It currently applies to all tabs including `activity`. Exclude `activity` from it since the activity tab now has per-type pagination:

```erb
<%# Change the condition from: %>
<% if %w[posts replies bans activity].include?(@tab) %>

<%# To: %>
<% if %w[posts replies bans].include?(@tab) %>
```

- [ ] **Step 5: Add per-type pagination controls within the activity section**

In `app/views/admin/users/show.html.erb`, find the `<% when "activity" %>` block (around line 163). After each of the three subsections (`@bans_issued`, `@posts_removed`, `@replies_removed`), add a "load more" link. Locate where each sub-list ends in the view and add:

After the bans list:
```erb
<% if @bans_has_more %>
  <%= link_to "More bans →",
        admin_user_path(@user, tab: "activity",
                        bans_page: @bans_page + 1,
                        posts_page: @posts_page,
                        replies_page: @replies_page),
        class: "text-sm text-blue-600 hover:underline" %>
<% end %>
```

After the posts list:
```erb
<% if @posts_has_more %>
  <%= link_to "More removed posts →",
        admin_user_path(@user, tab: "activity",
                        bans_page: @bans_page,
                        posts_page: @posts_page + 1,
                        replies_page: @replies_page),
        class: "text-sm text-blue-600 hover:underline" %>
<% end %>
```

After the replies list:
```erb
<% if @replies_has_more %>
  <%= link_to "More removed replies →",
        admin_user_path(@user, tab: "activity",
                        bans_page: @bans_page,
                        posts_page: @posts_page,
                        replies_page: @replies_page + 1),
        class: "text-sm text-blue-600 hover:underline" %>
<% end %>
```

- [ ] **Step 6: Run tests**

```bash
bin/rails test test/controllers/admin/users_controller_test.rb
```

Expected: all pass.

- [ ] **Step 7: Commit**

```bash
git add app/controllers/admin/users_controller.rb \
        app/views/admin/users/show.html.erb \
        test/controllers/admin/users_controller_test.rb
git commit -m "fix: per-type pagination for admin activity tab"
```

---

## Task 3c: Fix N+1 reply count on posts index

`posts/index.html.erb:72` calls `post.replies.count { |r| !r.removed? }` per post, loading all reply rows into Ruby. Replace with a single grouped SQL query in the controller.

**Files:**
- Modify: `app/controllers/posts_controller.rb:15` (remove `:replies` from includes) and `index` action
- Modify: `app/views/posts/index.html.erb:72`
- Modify: `test/controllers/posts_controller_test.rb`

- [ ] **Step 1: Write a test that verifies correct count with mixed visible/removed replies**

Add to `test/controllers/posts_controller_test.rb`:

```ruby
test "GET /posts shows correct reply count excluding removed replies" do
  Reply.create!(post: @post, user: @user, body: "Visible reply")
  removed_reply = Reply.create!(post: @post, user: @user, body: "Removed reply")
  removed_reply.update_columns(removed_at: Time.current, removed_by_id: @admin.id)

  get posts_path
  assert_response :success
  # @reply_counts should have 1 for this post (not 2)
  assert_equal 1, assigns(:reply_counts)[@post.id]
end
```

- [ ] **Step 2: Run test**

```bash
bin/rails test test/controllers/posts_controller_test.rb 2>&1 | grep -E "FAIL|ERROR|💬"
```

- [ ] **Step 3: Update `PostsController#index`**

In `app/controllers/posts_controller.rb`, update the `index` action:

```ruby
def index
  @categories = Category.all.order(:name)
  # Remove :replies from includes — replaced by a single grouped count query below
  posts = Post.visible.includes(:user, :category).order(Arel.sql("COALESCE(last_replied_at, created_at) DESC"))

  category_id = params[:category].to_i
  posts = posts.where(category_id: category_id) if category_id > 0

  take = (params[:take] || 10).to_i.clamp(1, 100)
  page = [ (params[:page] || 1).to_i, 1 ].max

  @posts = posts.limit(take + 1).offset((page - 1) * take)
  @take  = take
  @page  = page

  # Single query: count visible replies per post
  post_ids = @posts.map(&:id)
  @reply_counts = Reply.where(post_id: post_ids, removed_at: nil)
                       .group(:post_id)
                       .count
end
```

- [ ] **Step 4: Update `posts/index.html.erb` line 72**

Find the line with `post.replies.count { |r| !r.removed? }` and replace:

```erb
<%# Before %>
&#128172; <%= post.replies.count { |r| !r.removed? } %>

<%# After %>
&#128172; <%= @reply_counts[post.id] || 0 %>
```

- [ ] **Step 5: Run tests**

```bash
bin/rails test test/controllers/posts_controller_test.rb
```

Expected: all pass.

- [ ] **Step 6: Run full suite**

```bash
bin/rails test
```

- [ ] **Step 7: Lint**

```bash
bin/rubocop
```

- [ ] **Step 8: Commit**

```bash
git add app/controllers/posts_controller.rb app/views/posts/index.html.erb \
        test/controllers/posts_controller_test.rb
git commit -m "fix: replace N+1 reply count with single grouped SQL query on posts index"
```

---

## Final Verification

- [ ] **Run the full test suite**

```bash
bin/rails test
```

Expected: all pass, no errors.

- [ ] **Run the full CI pipeline**

```bash
bin/ci
```

Expected: lint, security audits, and tests all pass.
