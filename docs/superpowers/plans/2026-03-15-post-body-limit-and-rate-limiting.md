# Post Body Limit & Progressive Rate Limiting Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enforce a 1000-character limit on post and reply bodies, and prevent spam by rate-limiting users to a dynamic number of posts+replies per 15-minute window that scales with account age.

**Architecture:** Two independent features: (1) DB-level CHECK constraints + model validations for body length; (2) a `PostRateLimiter` service object that computes a dynamic limit from account age and is called as a `before_action` in both `PostsController` and `RepliesController`.

**Tech Stack:** Rails 8.1, PostgreSQL, Minitest, ActiveSupport `travel_to` for time-based tests.

---

## File Map

| File | Action | Responsibility |
|------|--------|----------------|
| `db/migrate/<ts1>_add_body_length_constraint_to_posts.rb` | Create | CHECK constraint on `posts.body` |
| `db/migrate/<ts2>_add_body_length_constraint_to_replies.rb` | Create | CHECK constraint on `replies.body` |
| `test/models/post_test.rb` | Create | Body length boundary tests (TDD — written before validation) |
| `test/models/reply_test.rb` | Create | Body length boundary tests (TDD — written before validation) |
| `app/models/post.rb` | Modify | Add `length: { maximum: 1000 }` to body validation |
| `app/models/reply.rb` | Modify | Add `length: { maximum: 1000 }` to body validation |
| `app/services/post_rate_limiter.rb` | Create | Dynamic rate limit logic, public interface: `allowed?`, `limit`, `remaining` |
| `app/controllers/posts_controller.rb` | Modify | Add `check_rate_limit` before_action on `:create` |
| `app/controllers/replies_controller.rb` | Modify | Add `check_rate_limit` before_action on `:create` |
| `test/services/post_rate_limiter_test.rb` | Create | Unit tests for limit formula and allowed?/remaining logic |

Note: This project uses `db/structure.sql` (not `db/schema.rb`) as the canonical schema file. Always include it in migration commits.

---

## Chunk 1: Body Length Constraints

### Task 1: Add CHECK constraint migration for posts.body

**Files:**
- Create: `db/migrate/<timestamp>_add_body_length_constraint_to_posts.rb`

- [ ] **Step 1: Pre-migration data check**

Before generating the migration, verify no existing post bodies exceed 1000 chars:

```bash
rails db -p <<'SQL'
SELECT COUNT(*) FROM posts WHERE char_length(body) > 1000;
SQL
```

Expected: `0`. If non-zero, truncate those rows before continuing.

- [ ] **Step 2: Generate and write the migration**

```bash
rails generate migration AddBodyLengthConstraintToPosts
```

Edit the generated file in `db/migrate/` — the class version `[8.0]` is correct for this Rails 8.x app:

```ruby
class AddBodyLengthConstraintToPosts < ActiveRecord::Migration[8.0]
  def change
    add_check_constraint :posts, "char_length(body) <= 1000", name: "posts_body_max_length"
  end
end
```

- [ ] **Step 3: Run the migration**

```bash
rails db:migrate
```

Expected output: `== AddBodyLengthConstraintToPosts: migrated`

- [ ] **Step 4: Verify constraint exists in the DB**

```bash
rails db -p <<'SQL'
SELECT conname, pg_get_constraintdef(oid)
FROM pg_constraint
WHERE conname = 'posts_body_max_length';
SQL
```

Expected: one row showing `CHECK ((char_length(body) <= 1000))`.

---

### Task 2: Add CHECK constraint migration for replies.body

**Files:**
- Create: `db/migrate/<timestamp>_add_body_length_constraint_to_replies.rb`

- [ ] **Step 1: Pre-migration data check**

```bash
rails db -p <<'SQL'
SELECT COUNT(*) FROM replies WHERE char_length(body) > 1000;
SQL
```

Expected: `0`.

- [ ] **Step 2: Generate and write the migration**

```bash
rails generate migration AddBodyLengthConstraintToReplies
```

Edit the generated file:

```ruby
class AddBodyLengthConstraintToReplies < ActiveRecord::Migration[8.0]
  def change
    add_check_constraint :replies, "char_length(body) <= 1000", name: "replies_body_max_length"
  end
end
```

- [ ] **Step 3: Run the migration**

```bash
rails db:migrate
```

Expected: `== AddBodyLengthConstraintToReplies: migrated`

- [ ] **Step 4: Verify constraint exists in the DB**

```bash
rails db -p <<'SQL'
SELECT conname, pg_get_constraintdef(oid)
FROM pg_constraint
WHERE conname = 'replies_body_max_length';
SQL
```

Expected: one row showing `CHECK ((char_length(body) <= 1000))`.

---

### Task 3: TDD model validations for body length

**Files:**
- Create: `test/models/post_test.rb`
- Create: `test/models/reply_test.rb`
- Modify: `app/models/post.rb`
- Modify: `app/models/reply.rb`

- [ ] **Step 1: Write failing Post model tests**

Create `test/models/post_test.rb`:

```ruby
require "test_helper"

class PostTest < ActiveSupport::TestCase
  setup do
    Provider.find_or_create_by!(id: 3, name: "internal")
    @user = User.create!(email: "pt@example.com", name: "Post Tester",
                         password: "pass123", password_confirmation: "pass123",
                         provider_id: 3)
  end

  test "body at exactly 1000 characters is valid" do
    post = Post.new(user: @user, title: "Title", body: "a" * 1000)
    assert post.valid?, "Expected valid but got: #{post.errors.full_messages}"
  end

  test "body at 1001 characters is invalid" do
    post = Post.new(user: @user, title: "Title", body: "a" * 1001)
    assert_not post.valid?
    assert_includes post.errors[:body], "is too long (maximum is 1000 characters)"
  end

  test "body at 1 character is valid" do
    post = Post.new(user: @user, title: "Title", body: "a")
    assert post.valid?, "Expected valid but got: #{post.errors.full_messages}"
  end
end
```

- [ ] **Step 2: Write failing Reply model tests**

Create `test/models/reply_test.rb`:

```ruby
require "test_helper"

class ReplyTest < ActiveSupport::TestCase
  setup do
    Provider.find_or_create_by!(id: 3, name: "internal")
    @user = User.create!(email: "rt@example.com", name: "Reply Tester",
                         password: "pass123", password_confirmation: "pass123",
                         provider_id: 3)
    @post = Post.create!(user: @user, title: "A Post", body: "Post body")
  end

  test "body at exactly 1000 characters is valid" do
    reply = Reply.new(post: @post, user: @user, body: "a" * 1000)
    assert reply.valid?, "Expected valid but got: #{reply.errors.full_messages}"
  end

  test "body at 1001 characters is invalid" do
    reply = Reply.new(post: @post, user: @user, body: "a" * 1001)
    assert_not reply.valid?
    assert_includes reply.errors[:body], "is too long (maximum is 1000 characters)"
  end

  test "body at 1 character is valid" do
    reply = Reply.new(post: @post, user: @user, body: "a")
    assert reply.valid?, "Expected valid but got: #{reply.errors.full_messages}"
  end
end
```

- [ ] **Step 3: Run tests — confirm they fail**

```bash
rails test test/models/post_test.rb test/models/reply_test.rb
```

Expected: the 1001-char tests pass (no validation yet rejects them — `.valid?` returns `true`), meaning the 1001-char assertions `assert_not post.valid?` will FAIL. Confirms we are in red before adding the validation.

- [ ] **Step 4: Add length validation to Post**

In `app/models/post.rb`, change:

```ruby
validates :body, presence: true
```

to:

```ruby
validates :body, presence: true, length: { maximum: 1000 }
```

- [ ] **Step 5: Add length validation to Reply**

In `app/models/reply.rb`, change:

```ruby
validates :body, presence: true
```

to:

```ruby
validates :body, presence: true, length: { maximum: 1000 }
```

- [ ] **Step 6: Run model tests — all should pass**

```bash
rails test test/models/post_test.rb test/models/reply_test.rb
```

Expected: 6 tests, 0 failures.

- [ ] **Step 7: Verify over-limit bodies are rejected at the controller level**

Add these tests to `test/controllers/posts_controller_test.rb` (inside the class, before the closing `end`):

```ruby
  test "POST /posts with body over 1000 chars is rejected" do
    post login_path, params: { email: "u@example.com", password: "pass123" }
    assert_no_difference "Post.count" do
      post posts_path, params: { post: { title: "Long post", body: "a" * 1001 } }
    end
    assert_response :unprocessable_entity
  end
```

Add to `test/controllers/replies_controller_test.rb`:

```ruby
  test "POST /posts/:post_id/replies with body over 1000 chars is rejected" do
    post login_path, params: { email: "u@example.com", password: "pass123" }
    assert_no_difference "Reply.count" do
      post post_replies_path(@post), params: { reply: { body: "a" * 1001 } }
    end
    assert_response :unprocessable_entity
  end
```

- [ ] **Step 8: Run all controller tests**

```bash
rails test test/controllers/posts_controller_test.rb test/controllers/replies_controller_test.rb
```

Expected: all tests pass.

- [ ] **Step 9: Commit**

```bash
git add db/migrate/ db/structure.sql app/models/post.rb app/models/reply.rb \
        test/models/post_test.rb test/models/reply_test.rb \
        test/controllers/posts_controller_test.rb test/controllers/replies_controller_test.rb
git commit -m "feat: enforce 1000-char limit on post and reply bodies via CHECK constraint and validation"
```

---

## Chunk 2: Progressive Rate Limiting

### Task 4: Implement PostRateLimiter service (TDD)

**Files:**
- Create: `app/services/post_rate_limiter.rb`
- Create: `test/services/post_rate_limiter_test.rb`

#### Step 1 — Write the failing tests

- [ ] **Create the test directory and file**

```bash
mkdir -p test/services
```

Create `test/services/post_rate_limiter_test.rb`:

```ruby
require "test_helper"

class PostRateLimiterTest < ActiveSupport::TestCase
  setup do
    Provider.find_or_create_by!(id: 3, name: "internal")
    @user = User.create!(
      email: "limiter@example.com",
      name: "Rate Tester",
      password: "pass123",
      password_confirmation: "pass123",
      provider_id: 3
    )
  end

  # ---- limit formula: week boundaries ----

  test "day 0 limit is 5" do
    assert_equal 5, limiter_at_age(0).limit
  end

  test "day 6 limit is still 5" do
    assert_equal 5, limiter_at_age(6).limit
  end

  test "day 7 limit is 6" do
    assert_equal 6, limiter_at_age(7).limit
  end

  test "day 13 limit is 6" do
    assert_equal 6, limiter_at_age(13).limit
  end

  test "day 14 limit is 7" do
    assert_equal 7, limiter_at_age(14).limit
  end

  test "day 20 limit is 7" do
    assert_equal 7, limiter_at_age(20).limit
  end

  test "day 21 limit is 8" do
    assert_equal 8, limiter_at_age(21).limit
  end

  test "day 27 limit is 8" do
    assert_equal 8, limiter_at_age(27).limit
  end

  test "day 28 limit is 9" do
    assert_equal 9, limiter_at_age(28).limit
  end

  # ---- limit formula: month boundaries ----

  test "day 59 limit is 9" do
    assert_equal 9, limiter_at_age(59).limit
  end

  test "day 60 limit is 10" do
    assert_equal 10, limiter_at_age(60).limit
  end

  test "day 89 limit is 10" do
    assert_equal 10, limiter_at_age(89).limit
  end

  test "day 90 limit is 11" do
    assert_equal 11, limiter_at_age(90).limit
  end

  test "day 119 limit is 11" do
    assert_equal 11, limiter_at_age(119).limit
  end

  test "day 120 limit is 12" do
    assert_equal 12, limiter_at_age(120).limit
  end

  test "day 149 limit is 12" do
    assert_equal 12, limiter_at_age(149).limit
  end

  test "day 150 limit is 13" do
    assert_equal 13, limiter_at_age(150).limit
  end

  test "day 179 limit is 13" do
    assert_equal 13, limiter_at_age(179).limit
  end

  test "day 180 limit is 14" do
    assert_equal 14, limiter_at_age(180).limit
  end

  test "day 209 limit is 14" do
    assert_equal 14, limiter_at_age(209).limit
  end

  test "day 210 limit is 15" do
    assert_equal 15, limiter_at_age(210).limit
  end

  test "day 999 limit is capped at 15" do
    assert_equal 15, limiter_at_age(999).limit
  end

  # ---- allowed? and remaining ----

  test "allowed? is true when no activity" do
    assert limiter_now.allowed?
  end

  test "allowed? is true when activity is below limit" do
    create_posts(4)
    assert limiter_now.allowed?   # new user limit=5, activity=4
  end

  test "allowed? is false when activity equals limit" do
    create_posts(5)
    assert_not limiter_now.allowed?   # new user limit=5, activity=5
  end

  test "allowed? is false when activity exceeds limit" do
    create_posts(6)
    assert_not limiter_now.allowed?
  end

  test "remaining returns correct count below limit" do
    create_posts(3)
    assert_equal 2, limiter_now.remaining   # 5 - 3 = 2
  end

  test "remaining returns 0 when at limit" do
    create_posts(5)
    assert_equal 0, limiter_now.remaining
  end

  test "remaining returns 0 and does not go negative when over limit" do
    create_posts(7)
    assert_equal 0, limiter_now.remaining
  end

  test "activity outside the 15-minute window does not count" do
    travel_to 20.minutes.ago do
      Post.create!(user: @user, title: "Old post", body: "Old body")
    end
    assert_equal 5, limiter_now.remaining   # still full budget
  end

  test "replies count toward the same budget as posts" do
    create_posts(3)
    a_post = Post.create!(user: @user, title: "A post", body: "A body")
    Reply.create!(post: a_post, user: @user, body: "My reply")
    assert_equal 1, limiter_now.remaining   # 5 - 4 = 1
  end

  private

  def limiter_at_age(days)
    @user.update_column(:created_at, days.days.ago)
    PostRateLimiter.new(@user)
  end

  def limiter_now
    PostRateLimiter.new(@user)
  end

  def create_posts(count)
    count.times do |i|
      Post.create!(user: @user, title: "Post #{i}", body: "Body #{i}")
    end
  end
end
```

- [ ] **Step 2: Run the tests — confirm they all fail with "uninitialized constant PostRateLimiter"**

```bash
rails test test/services/post_rate_limiter_test.rb
```

Expected: all tests fail with `NameError: uninitialized constant PostRateLimiter`.

#### Step 3 — Implement the service

- [ ] **Create `app/services/post_rate_limiter.rb`**

```ruby
class PostRateLimiter
  WINDOW     = 15.minutes
  BASE_LIMIT = 5
  MAX_LIMIT  = 15

  def initialize(user)
    @user = user
  end

  def allowed?
    activity < limit
  end

  def limit
    age_in_days = ((Time.current - @user.created_at) / 1.day).floor
    weeks       = [(age_in_days / 7).floor, 4].min
    months      = [[((age_in_days / 30).floor) - 1, 0].max, 6].min
    [BASE_LIMIT + weeks + months, MAX_LIMIT].min
  end

  def remaining
    [limit - activity, 0].max
  end

  private

  def activity
    @activity ||= begin
      posts_count   = @user.posts.where(created_at: WINDOW.ago..).count
      replies_count = @user.replies.where(created_at: WINDOW.ago..).count
      posts_count + replies_count
    end
  end
end
```

- [ ] **Step 4: Run the tests — all should pass**

```bash
rails test test/services/post_rate_limiter_test.rb
```

Expected: all tests pass with 0 failures.

- [ ] **Step 5: Commit**

```bash
git add app/services/post_rate_limiter.rb test/services/post_rate_limiter_test.rb
git commit -m "feat: add PostRateLimiter service with progressive account-age-based limits"
```

---

### Task 5: Integrate rate limiter into PostsController

**Files:**
- Modify: `app/controllers/posts_controller.rb`
- Modify: `test/controllers/posts_controller_test.rb`

- [ ] **Step 1: Write the failing controller tests**

Add to the end of the test class in `test/controllers/posts_controller_test.rb` (before the closing `end`):

```ruby
  # ---- rate limiting ----

  test "POST /posts is blocked when user hits rate limit" do
    post login_path, params: { email: "u@example.com", password: "pass123" }
    5.times { |i| Post.create!(user: @user, title: "Spam #{i}", body: "body") }

    assert_no_difference "Post.count" do
      post posts_path, params: { post: { title: "Spam 6", body: "blocked" } }
    end
    assert_redirected_to new_post_path
    assert_match /posting too fast/, flash[:alert]
  end

  test "POST /posts flash includes the user limit" do
    post login_path, params: { email: "u@example.com", password: "pass123" }
    5.times { |i| Post.create!(user: @user, title: "Spam #{i}", body: "body") }
    post posts_path, params: { post: { title: "X", body: "Y" } }
    assert_match /5/, flash[:alert]
  end

  test "POST /posts is allowed when under rate limit" do
    post login_path, params: { email: "u@example.com", password: "pass123" }
    4.times { |i| Post.create!(user: @user, title: "Spam #{i}", body: "body") }
    assert_difference "Post.count", 1 do
      post posts_path, params: { post: { title: "5th Post", body: "allowed" } }
    end
  end
```

- [ ] **Step 2: Run the new tests — confirm they fail**

```bash
rails test test/controllers/posts_controller_test.rb -n "/rate limit/"
```

Expected: 3 failures (rate limit not enforced yet).

- [ ] **Step 3: Update PostsController**

Replace the full content of `app/controllers/posts_controller.rb`:

```ruby
class PostsController < ApplicationController
  before_action :require_login, only: [:new, :create]
  before_action :check_rate_limit, only: [:create]

  def index
    @categories = Category.all.order(:name)
    posts = Post.includes(:user, :category, :replies).order(created_at: :desc)

    category_id = params[:category].to_i
    posts = posts.where(category_id: category_id) if category_id > 0

    take = (params[:take] || 10).to_i.clamp(1, 100)
    page = [(params[:page] || 1).to_i, 1].max

    @posts = posts.limit(take).offset((page - 1) * take)
    @take  = take
    @page  = page
  end

  def show
    @post  = Post.includes(:category, replies: :user).find(params[:id])
    @reply = Reply.new
  end

  def new
    @post       = Post.new
    @categories = Category.all.order(:name)
  end

  def create
    @post = current_user.posts.build(post_params)
    if @post.save
      redirect_to @post, notice: "Post created!"
    else
      @categories = Category.all.order(:name)
      render :new, status: :unprocessable_entity
    end
  end

  private

  def post_params
    params.require(:post).permit(:title, :body, :category_id)
  end

  def check_rate_limit
    limiter = PostRateLimiter.new(current_user)
    unless limiter.allowed?
      flash[:alert] = "You're posting too fast. Limit is #{limiter.limit} posts/replies per 15 minutes."
      redirect_to new_post_path
    end
  end
end
```

- [ ] **Step 4: Run all posts controller tests**

```bash
rails test test/controllers/posts_controller_test.rb
```

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add app/controllers/posts_controller.rb test/controllers/posts_controller_test.rb
git commit -m "feat: enforce rate limit on post creation"
```

---

### Task 6: Integrate rate limiter into RepliesController

**Files:**
- Modify: `app/controllers/replies_controller.rb`
- Modify: `test/controllers/replies_controller_test.rb`

- [ ] **Step 1: Write the failing controller tests**

Add to the end of the test class in `test/controllers/replies_controller_test.rb` (before the closing `end`):

```ruby
  # ---- rate limiting ----

  test "POST /posts/:post_id/replies is blocked when user hits rate limit" do
    post login_path, params: { email: "u@example.com", password: "pass123" }
    5.times { |i| Post.create!(user: @user, title: "Spam #{i}", body: "body") }

    assert_no_difference "Reply.count" do
      post post_replies_path(@post), params: { reply: { body: "blocked reply" } }
    end
    assert_redirected_to post_path(@post)
    assert_match /posting too fast/, flash[:alert]
  end

  test "POST /posts/:post_id/replies rate limit redirects back to the post, not new_post" do
    post login_path, params: { email: "u@example.com", password: "pass123" }
    5.times { |i| Post.create!(user: @user, title: "Spam #{i}", body: "body") }
    post post_replies_path(@post), params: { reply: { body: "blocked" } }
    assert_redirected_to post_path(@post)
  end

  test "DELETE /posts/:post_id/replies/:id is unaffected by rate limit" do
    post login_path, params: { email: "u@example.com", password: "pass123" }
    reply = Reply.create!(post: @post, user: @user, body: "My reply")
    5.times { |i| Post.create!(user: @user, title: "Spam #{i}", body: "body") }
    assert_difference "Reply.count", -1 do
      delete post_reply_path(@post, reply)
    end
    assert_redirected_to post_path(@post)
  end
```

- [ ] **Step 2: Run the new tests — confirm they fail**

```bash
rails test test/controllers/replies_controller_test.rb -n "/rate limit/"
```

Expected: 3 failures.

- [ ] **Step 3: Update RepliesController**

Replace the full content of `app/controllers/replies_controller.rb`:

```ruby
class RepliesController < ApplicationController
  before_action :require_login
  before_action :check_rate_limit, only: [:create]

  def create
    @post = Post.find(params[:post_id])
    @reply = @post.replies.build(reply_params.merge(user: current_user))
    if @reply.save
      redirect_to @post, notice: "Reply posted!"
    else
      @post = Post.includes(replies: :user).find(params[:post_id])
      render "posts/show", status: :unprocessable_entity
    end
  end

  def destroy
    @post = Post.find(params[:post_id])
    @reply = @post.replies.find(params[:id])
    unless @reply.user == current_user
      redirect_to @post, alert: "Not authorized to delete this reply.", status: :see_other
      return
    end
    @reply.destroy
    redirect_to @post, notice: "Reply deleted."
  end

  private

  def reply_params
    params.require(:reply).permit(:body)
  end

  def check_rate_limit
    limiter = PostRateLimiter.new(current_user)
    unless limiter.allowed?
      flash[:alert] = "You're posting too fast. Limit is #{limiter.limit} posts/replies per 15 minutes."
      redirect_to post_path(params[:post_id])
    end
  end
end
```

- [ ] **Step 4: Run all replies controller tests**

```bash
rails test test/controllers/replies_controller_test.rb
```

Expected: all tests pass.

- [ ] **Step 5: Run the full test suite**

```bash
rails test
```

Expected: all tests pass, 0 failures.

- [ ] **Step 6: Commit**

```bash
git add app/controllers/replies_controller.rb test/controllers/replies_controller_test.rb
git commit -m "feat: enforce rate limit on reply creation"
```
