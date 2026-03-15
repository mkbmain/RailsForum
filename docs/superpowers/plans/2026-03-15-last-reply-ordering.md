# Last Reply Date Display & Ordering Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show the last reply date on post cards and order posts by last activity (last reply, falling back to post creation date).

**Architecture:** Add a `last_replied_at` column to `posts`, maintained by `after_create`/`after_destroy` callbacks on `Reply`. A `Post#last_activity_at` helper centralises the `nil` fallback. The controller orders with `COALESCE(last_replied_at, created_at) DESC` and the view reads `post.last_activity_at`.

**Tech Stack:** Rails 8, SQLite, Minitest

---

## Chunk 1: Migration, model changes, and tests

### Task 1: Add `last_replied_at` migration

**Files:**
- Create: `db/migrate/20260315200000_add_last_replied_at_to_posts.rb`

- [ ] **Step 1: Write the migration**

```ruby
class AddLastRepliedAtToPosts < ActiveRecord::Migration[8.0]
  def change
    add_column :posts, :last_replied_at, :datetime
  end
end
```

- [ ] **Step 2: Run the migration**

```bash
bin/rails db:migrate
```

Expected: `== 20260315200000 AddLastRepliedAtToPosts: migrating ==` … `migrated`

- [ ] **Step 3: Commit**

```bash
git add db/migrate/20260315200000_add_last_replied_at_to_posts.rb
git commit -m "feat: add last_replied_at column to posts"
```

---

### Task 2: Add `last_activity_at` to `Post`

**Files:**
- Modify: `app/models/post.rb`
- Test: `test/models/post_test.rb`

- [ ] **Step 1: Write the failing tests**

Add to `test/models/post_test.rb` (inside the class, after existing tests):

```ruby
test "last_activity_at returns created_at when no replies" do
  post = Post.create!(user: @user, title: "No replies", body: "body")
  assert_equal post.created_at, post.last_activity_at
end

test "last_activity_at returns last_replied_at when set" do
  post = Post.create!(user: @user, title: "Has replies", body: "body")
  time = 1.hour.from_now
  post.update_column(:last_replied_at, time)
  assert_equal time.to_i, post.reload.last_activity_at.to_i
end
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
bin/rails test test/models/post_test.rb
```

Expected: 2 failures — `NoMethodError: undefined method 'last_activity_at'`

- [ ] **Step 3: Add `last_activity_at` to `Post`**

In `app/models/post.rb`, add after the `has_many :replies` line:

```ruby
def last_activity_at
  last_replied_at || created_at
end
```

- [ ] **Step 4: Run tests to confirm they pass**

```bash
bin/rails test test/models/post_test.rb
```

Expected: 5 tests, 0 failures

- [ ] **Step 5: Commit**

```bash
git add app/models/post.rb test/models/post_test.rb
git commit -m "feat: add Post#last_activity_at helper"
```

---

### Task 3: Add Reply callbacks to maintain `last_replied_at`

**Files:**
- Modify: `app/models/reply.rb`
- Test: `test/models/reply_test.rb`

- [ ] **Step 1: Write the failing tests**

Add to `test/models/reply_test.rb` (inside the class, after existing tests):

```ruby
test "creating a reply sets post last_replied_at" do
  reply = Reply.create!(post: @post, user: @user, body: "first reply")
  assert_in_delta reply.created_at.to_i, @post.reload.last_replied_at.to_i, 1
end

test "destroying the only reply sets post last_replied_at to nil" do
  reply = Reply.create!(post: @post, user: @user, body: "only reply")
  reply.destroy
  assert_nil @post.reload.last_replied_at
end

test "destroying a non-last reply keeps last_replied_at as the remaining latest" do
  older = Reply.create!(post: @post, user: @user, body: "older", created_at: 2.hours.ago)
  newer = Reply.create!(post: @post, user: @user, body: "newer", created_at: 1.hour.ago)
  older.destroy
  assert_in_delta newer.created_at.to_i, @post.reload.last_replied_at.to_i, 1
end
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
bin/rails test test/models/reply_test.rb
```

Expected: 3 failures — `last_replied_at` not updated

- [ ] **Step 3: Add callbacks to `Reply`**

Replace the contents of `app/models/reply.rb` with:

```ruby
class Reply < ApplicationRecord
  belongs_to :post
  belongs_to :user

  validates :body, presence: true, length: { maximum: 1000 }

  after_create  :update_post_last_replied_at
  after_destroy :recalculate_post_last_replied_at

  private

  def update_post_last_replied_at
    post.update_column(:last_replied_at, created_at)
  end

  def recalculate_post_last_replied_at
    post.update_column(:last_replied_at, post.replies.maximum(:created_at))
  end
end
```

- [ ] **Step 4: Run tests to confirm they pass**

```bash
bin/rails test test/models/reply_test.rb
```

Expected: 6 tests, 0 failures

- [ ] **Step 5: Commit**

```bash
git add app/models/reply.rb test/models/reply_test.rb
git commit -m "feat: maintain Post#last_replied_at via Reply callbacks"
```

---

## Chunk 2: Controller ordering and view display

### Task 4: Order posts by last activity in controller

**Files:**
- Modify: `app/controllers/posts_controller.rb`
- Test: `test/controllers/posts_controller_test.rb`

- [ ] **Step 1: Write the failing test**

Add to `test/controllers/posts_controller_test.rb` (inside the class, after existing tests):

```ruby
test "GET /posts orders by last activity: post with recent reply appears first" do
  older_post = Post.create!(user: @user, title: "Older Post", body: "body",
                             created_at: 2.hours.ago)
  newer_reply_user = User.create!(email: "nr@example.com", name: "NR",
                                   password: "pass123", password_confirmation: "pass123",
                                   provider_id: 3)
  # Give the setup post (@post, created more recently) no replies.
  # Give older_post a very recent reply so it should sort first.
  Reply.create!(post: older_post, user: newer_reply_user, body: "recent reply")

  get posts_path
  assert_response :success

  titles = css_select(".post-card h2 a").map(&:text).map(&:strip)
  assert_equal "Older Post", titles.first,
    "Post with recent reply should appear first. Got: #{titles.inspect}"
end
```

- [ ] **Step 2: Run test to confirm it fails**

```bash
bin/rails test test/controllers/posts_controller_test.rb -n "test_GET_/posts_orders_by_last_activity:_post_with_recent_reply_appears_first"
```

Expected: FAIL — the older post with a reply does not appear first

- [ ] **Step 3: Update controller ordering**

In `app/controllers/posts_controller.rb`, change line 9 from:

```ruby
posts = Post.includes(:user, :category, :replies).order(created_at: :desc)
```

to:

```ruby
posts = Post.includes(:user, :category, :replies).order(Arel.sql("COALESCE(last_replied_at, created_at) DESC"))
```

- [ ] **Step 4: Run test to confirm it passes**

```bash
bin/rails test test/controllers/posts_controller_test.rb
```

Expected: all tests pass, 0 failures

- [ ] **Step 5: Commit**

```bash
git add app/controllers/posts_controller.rb test/controllers/posts_controller_test.rb
git commit -m "feat: order posts by last activity (last reply or creation date)"
```

---

### Task 5: Update view to display last activity timestamp

**Files:**
- Modify: `app/views/posts/index.html.erb`
- Test: `test/controllers/posts_controller_test.rb`

- [ ] **Step 1: Write the failing test**

Add to `test/controllers/posts_controller_test.rb` (inside the class, after existing tests):

```ruby
test "GET /posts shows last reply time when post has a reply" do
  reply_user = User.create!(email: "rv@example.com", name: "RV",
                             password: "pass123", password_confirmation: "pass123",
                             provider_id: 3)
  # Create reply, then manually set last_replied_at to a known time
  reply = Reply.create!(post: @post, user: reply_user, body: "a reply")
  known_time = 3.hours.ago
  @post.update_column(:last_replied_at, known_time)

  get posts_path
  assert_response :success
  # time_ago_in_words(3.hours.ago) produces "about 3 hours"
  assert_select ".post-card span.text-xs", text: /about 3 hours ago/
end
```

- [ ] **Step 2: Run test to confirm it fails**

```bash
bin/rails test test/controllers/posts_controller_test.rb -n "test_GET_/posts_shows_last_reply_time_when_post_has_a_reply"
```

Expected: FAIL — timestamp still shows `created_at`

- [ ] **Step 3: Update the view**

In `app/views/posts/index.html.erb`, change line 41 from:

```erb
<span class="text-xs text-stone-400"><%= time_ago_in_words(post.created_at) %> ago</span>
```

to:

```erb
<span class="text-xs text-stone-400"><%= time_ago_in_words(post.last_activity_at) %> ago</span>
```

- [ ] **Step 4: Run all tests to confirm everything passes**

```bash
bin/rails test
```

Expected: all tests pass, 0 failures

- [ ] **Step 5: Commit**

```bash
git add app/views/posts/index.html.erb test/controllers/posts_controller_test.rb
git commit -m "feat: show last activity timestamp on post cards"
```
