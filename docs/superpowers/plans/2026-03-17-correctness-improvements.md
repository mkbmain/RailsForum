# Correctness Improvements Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix four targeted correctness bugs across Notification model, notifications view, search pagination, and ReactionsController.

**Architecture:** Pure bug-fix pass — add two scopes and two methods to `Notification`, update three call sites in `NotificationsController`, fix one view line, load `@take + 1` in search, and scope `set_post` through `Post.visible` in `ReactionsController`. No migrations, no new files.

**Tech Stack:** Rails 8.1, Minitest, PostgreSQL

---

### Task 1: Notification model — `unread`/`read` scopes and `mark_as_read!`

**Files:**
- Modify: `app/models/notification.rb`
- Test: `test/models/notification_test.rb`

- [ ] **Step 1: Write failing tests**

Add to `test/models/notification_test.rb` inside the existing `NotificationTest` class, after the last test:

```ruby
test "unread scope returns only notifications with nil read_at" do
  unread = Notification.create!(user: @user, actor: @actor, notifiable: @reply, event_type: :reply_to_post)
  read   = Notification.create!(user: @user, actor: @actor, notifiable: @reply, event_type: :mention,
                                  read_at: Time.current)
  assert_includes Notification.unread, unread
  assert_not_includes Notification.unread, read
end

test "read scope returns only notifications with read_at set" do
  unread = Notification.create!(user: @user, actor: @actor, notifiable: @reply, event_type: :reply_to_post)
  read   = Notification.create!(user: @user, actor: @actor, notifiable: @reply, event_type: :mention,
                                  read_at: Time.current)
  assert_includes Notification.read, read
  assert_not_includes Notification.read, unread
end

test "mark_as_read! sets read_at" do
  n = Notification.create!(user: @user, actor: @actor, notifiable: @reply, event_type: :reply_to_post)
  assert_nil n.read_at
  n.mark_as_read!
  assert_not_nil n.reload.read_at
end

test "mark_as_read! is idempotent — does not update read_at if already read" do
  n = Notification.create!(user: @user, actor: @actor, notifiable: @reply, event_type: :reply_to_post)
  n.mark_as_read!
  original_read_at = n.reload.read_at
  n.mark_as_read!
  assert_equal original_read_at, n.reload.read_at
end
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
bin/rails test test/models/notification_test.rb
```

Expected: 4 failures/errors — `unread`, `read`, `mark_as_read!` methods not defined.

- [ ] **Step 3: Add scopes and method to Notification model**

In `app/models/notification.rb`, add after the `enum` line:

```ruby
scope :unread, -> { where(read_at: nil) }
scope :read,   -> { where.not(read_at: nil) }

def mark_as_read!
  update!(read_at: Time.current) unless read?
end
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
bin/rails test test/models/notification_test.rb
```

Expected: all green.

- [ ] **Step 5: Update the three call sites in NotificationsController**

In `app/controllers/notifications_controller.rb`:

- Line 9: change `current_user.notifications.where(read_at: nil).count` → `current_user.notifications.unread.count`
- Line 14: change `notification&.update(read_at: Time.current)` → `notification&.mark_as_read!`
- Line 19: change `current_user.notifications.where(read_at: nil).update_all(...)` → `current_user.notifications.unread.update_all(read_at: Time.current)`

- [ ] **Step 6: Run controller tests to confirm nothing broke**

```bash
bin/rails test test/controllers/notifications_controller_test.rb
```

Expected: all green.

- [ ] **Step 7: Commit**

```bash
git add app/models/notification.rb app/controllers/notifications_controller.rb test/models/notification_test.rb
git commit -m "feat: add unread/read scopes and mark_as_read! to Notification; update controller call sites"
```

---

### Task 2: Notification `target_post` helper + view fix

**Files:**
- Modify: `app/models/notification.rb`
- Modify: `app/views/notifications/index.html.erb`
- Test: `test/models/notification_test.rb`

- [ ] **Step 1: Write failing tests**

Add to `test/models/notification_test.rb`:

```ruby
test "target_post returns the post when notifiable is a Post" do
  post_notif = Notification.create!(user: @user, actor: @actor, notifiable: @post, event_type: :moderation)
  assert_equal @post, post_notif.target_post
end

test "target_post returns parent post when notifiable is a Reply" do
  reply_notif = Notification.create!(user: @user, actor: @actor, notifiable: @reply, event_type: :reply_to_post)
  assert_equal @post, reply_notif.target_post
end
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
bin/rails test test/models/notification_test.rb
```

Expected: 2 failures — `target_post` not defined.

- [ ] **Step 3: Add `target_post` to Notification model**

In `app/models/notification.rb`, add after `mark_as_read!`:

```ruby
def target_post
  case notifiable
  when Post  then notifiable
  when Reply then notifiable.post
  else raise "Unknown notifiable type for target_post: #{notifiable.class}"
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
bin/rails test test/models/notification_test.rb
```

Expected: all green.

- [ ] **Step 5: Update the notifications view**

In `app/views/notifications/index.html.erb`, change line 18 from:

```erb
<% post_link = n.notifiable.is_a?(Post) ? post_path(n.notifiable) : post_path(n.notifiable.post) %>
```

to:

```erb
<% post_link = post_path(n.target_post) %>
```

- [ ] **Step 6: Run full notification tests**

```bash
bin/rails test test/models/notification_test.rb test/controllers/notifications_controller_test.rb
```

Expected: all green.

- [ ] **Step 7: Commit**

```bash
git add app/models/notification.rb app/views/notifications/index.html.erb test/models/notification_test.rb
git commit -m "feat: add target_post to Notification and simplify notifications view"
```

---

### Task 3: Search pagination probe

**Files:**
- Modify: `app/controllers/search_controller.rb`
- Modify: `app/views/search/index.html.erb`
- Test: `test/controllers/search_controller_test.rb`

- [ ] **Step 1: Write failing tests**

Add to `test/controllers/search_controller_test.rb`:

```ruby
test "Next link is not shown when exactly @take results exist" do
  # Default take is 10. The setup creates 1 post. Create 9 more to reach exactly 10.
  9.times { |i| Post.create!(user: @user, title: "Rails post #{i}", body: "body") }
  get search_path, params: { q: "Rails", take: 10 }
  assert_response :success
  assert_select "a", text: /Next/, count: 0
end

test "Next link is shown when more than @take results exist" do
  10.times { |i| Post.create!(user: @user, title: "Rails post #{i}", body: "body") }
  get search_path, params: { q: "Rails", take: 10 }
  assert_response :success
  assert_select "a", text: /Next/
end

test "only @take items are rendered even when probe record is loaded" do
  10.times { |i| Post.create!(user: @user, title: "Rails post #{i}", body: "body") }
  get search_path, params: { q: "Rails", take: 10 }
  assert_response :success
  # 10 posts should be rendered, not 11
  assert_select "h2 a", count: 10
end
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
bin/rails test test/controllers/search_controller_test.rb
```

Expected: the "Next link is not shown" test fails (Next link is incorrectly shown when exactly 10 results).

- [ ] **Step 3: Fix the controller — load `@take + 1`**

In `app/controllers/search_controller.rb`, change line 19:

```ruby
@posts = posts.limit(@take + 1).offset((@page - 1) * @take)
```

- [ ] **Step 4: Fix the view — probe detection and rendering**

In `app/views/search/index.html.erb`:

Change line 69:
```erb
<% if @posts.size >= @take %>
```
to:
```erb
<% if @posts.size > @take %>
```

Change line 41 (the `@posts.each` loop):
```erb
<% @posts.each do |post| %>
```
to:
```erb
<% @posts.first(@take).each do |post| %>
```

- [ ] **Step 5: Run tests to verify they pass**

```bash
bin/rails test test/controllers/search_controller_test.rb
```

Expected: all green.

- [ ] **Step 6: Commit**

```bash
git add app/controllers/search_controller.rb app/views/search/index.html.erb test/controllers/search_controller_test.rb
git commit -m "fix: use probe record to prevent false Next link on last search page"
```

---

### Task 4: ReactionsController visibility guard

**Files:**
- Modify: `app/controllers/reactions_controller.rb`
- Test: `test/controllers/reactions_controller_test.rb`

- [ ] **Step 1: Write failing test**

Add to `test/controllers/reactions_controller_test.rb`:

```ruby
test "POST on hidden post returns 404" do
  @post.update_column(:removed_at, Time.current)
  post login_path, params: { email: "u@example.com", password: "pass123" }
  post post_reactions_path(@post), params: { emoji: "👍" }
  assert_response :not_found
end
```

- [ ] **Step 2: Run test to verify it fails**

```bash
bin/rails test test/controllers/reactions_controller_test.rb
```

Expected: the new test fails — currently a hidden post is found and reactions are added rather than returning 404.

- [ ] **Step 3: Scope `set_post` through `Post.visible`**

In `app/controllers/reactions_controller.rb`, change the `set_post` private method:

```ruby
def set_post
  @post = Post.visible.find(params[:post_id])
end
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
bin/rails test test/controllers/reactions_controller_test.rb
```

Expected: all green.

- [ ] **Step 5: Commit**

```bash
git add app/controllers/reactions_controller.rb test/controllers/reactions_controller_test.rb
git commit -m "fix: scope ReactionsController set_post through Post.visible to reject hidden posts"
```

---

### Final: Full CI pass

- [ ] **Run full test suite and linter**

```bash
bin/ci
```

Expected: all tests pass, no rubocop violations, no security warnings.
