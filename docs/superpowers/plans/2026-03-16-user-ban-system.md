# User Ban System Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prevent banned users from creating posts or replies, with a full audit trail of bans stored in dedicated tables.

**Architecture:** Two new tables (`ban_reasons`, `user_bans`) with corresponding models. A `BanChecker` service (mirrors `PostRateLimiter`) queries active bans. A `Bannable` concern (mirrors `RateLimitable`) wires the check into both controllers via `before_action`.

**Tech Stack:** Rails 8.1, PostgreSQL, Rails Minitest

---

## Chunk 1: Database, Models & Seeds

### Task 1: Migrations

**Files:**
- Create: `db/migrate/20260316134715_create_ban_reasons.rb`
- Create: `db/migrate/20260316134716_create_user_bans.rb`

- [ ] **Step 1: Write the ban_reasons migration**

```ruby
# db/migrate/20260316134715_create_ban_reasons.rb
class CreateBanReasons < ActiveRecord::Migration[8.1]
  def change
    create_table :ban_reasons do |t|
      t.string :name, null: false
      t.timestamps
    end
    add_index :ban_reasons, :name, unique: true
  end
end
```

- [ ] **Step 2: Write the user_bans migration**

```ruby
# db/migrate/20260316134716_create_user_bans.rb
class CreateUserBans < ActiveRecord::Migration[8.1]
  def change
    create_table :user_bans do |t|
      t.references :user,       null: false, foreign_key: true
      t.references :ban_reason, null: false, foreign_key: true
      t.datetime :banned_from,  null: false, default: -> { "now()" }
      t.datetime :banned_until, null: false
      t.timestamps
    end
    add_index :user_bans, [:user_id, :banned_until]
  end
end
```

- [ ] **Step 3: Run the migrations**

```bash
bin/rails db:migrate
```

Expected: two new tables appear, `schema.rb` updated.

- [ ] **Step 4: Commit**

```bash
git add db/migrate/20260316134715_create_ban_reasons.rb \
        db/migrate/20260316134716_create_user_bans.rb \
        db/schema.rb
git commit -m "feat: add ban_reasons and user_bans migrations"
```

---

### Task 2: BanReason model

**Files:**
- Create: `app/models/ban_reason.rb`
- Create: `test/models/ban_reason_test.rb`

- [ ] **Step 1: Write the failing tests**

```ruby
# test/models/ban_reason_test.rb
require "test_helper"

class BanReasonTest < ActiveSupport::TestCase
  test "valid with a name" do
    assert BanReason.new(name: "Spam").valid?
  end

  test "invalid without a name" do
    assert_not BanReason.new(name: nil).valid?
  end

  test "invalid with a duplicate name" do
    BanReason.create!(name: "Spam")
    assert_not BanReason.new(name: "Spam").valid?
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
bin/rails test test/models/ban_reason_test.rb
```

Expected: NameError or 3 failures (model doesn't exist yet).

- [ ] **Step 3: Write the model**

```ruby
# app/models/ban_reason.rb
class BanReason < ApplicationRecord
  validates :name, presence: true, uniqueness: true
end
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
bin/rails test test/models/ban_reason_test.rb
```

Expected: 3 tests, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add app/models/ban_reason.rb test/models/ban_reason_test.rb
git commit -m "feat: add BanReason model"
```

---

### Task 3: UserBan model

**Files:**
- Create: `app/models/user_ban.rb`
- Create: `test/models/user_ban_test.rb`

- [ ] **Step 1: Write the failing tests**

```ruby
# test/models/user_ban_test.rb
require "test_helper"

class UserBanTest < ActiveSupport::TestCase
  setup do
    Provider.find_or_create_by!(id: 3, name: "internal")
    @user   = User.create!(email: "banned@example.com", name: "Banned User",
                           password: "pass123", password_confirmation: "pass123", provider_id: 3)
    @reason = BanReason.create!(name: "Spam")
  end

  test "valid with user, reason, and banned_until in the future" do
    ban = UserBan.new(user: @user, ban_reason: @reason, banned_until: 1.day.from_now)
    assert ban.valid?
  end

  test "before_validation sets banned_from to now when blank" do
    ban = UserBan.new(user: @user, ban_reason: @reason, banned_until: 1.day.from_now)
    ban.valid?
    assert_not_nil ban.banned_from
  end

  test "invalid without banned_until" do
    ban = UserBan.new(user: @user, ban_reason: @reason)
    assert_not ban.valid?
    assert_includes ban.errors[:banned_until], "can't be blank"
  end

  test "invalid when banned_until is not after banned_from" do
    ban = UserBan.new(user: @user, ban_reason: @reason,
                      banned_from: Time.current, banned_until: 1.hour.ago)
    assert_not ban.valid?
    assert_includes ban.errors[:banned_until], "must be after banned from"
  end

  test "invalid without a user" do
    ban = UserBan.new(ban_reason: @reason, banned_until: 1.day.from_now)
    assert_not ban.valid?
  end

  test "invalid without a ban_reason" do
    ban = UserBan.new(user: @user, banned_until: 1.day.from_now)
    assert_not ban.valid?
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
bin/rails test test/models/user_ban_test.rb
```

Expected: NameError or failures (model doesn't exist yet).

- [ ] **Step 3: Write the model**

```ruby
# app/models/user_ban.rb
class UserBan < ApplicationRecord
  belongs_to :user
  belongs_to :ban_reason

  before_validation { self.banned_from ||= Time.current }

  validates :banned_from, :banned_until, presence: true
  validate :banned_until_after_banned_from

  private

  def banned_until_after_banned_from
    return unless banned_from.present? && banned_until.present?
    errors.add(:banned_until, "must be after banned from") if banned_until <= banned_from
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
bin/rails test test/models/user_ban_test.rb
```

Expected: 6 tests, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add app/models/user_ban.rb test/models/user_ban_test.rb
git commit -m "feat: add UserBan model"
```

---

### Task 4: Update User model

**Files:**
- Modify: `app/models/user.rb`
- Modify: `test/models/user_test.rb`

- [ ] **Step 1: Write the failing test**

Add to `test/models/user_test.rb`:

```ruby
test "has many user_bans" do
  Provider.find_or_create_by!(id: 3, name: "internal")
  user   = User.create!(email: "u@example.com", name: "U", password: "pass123",
                        password_confirmation: "pass123", provider_id: 3)
  reason = BanReason.create!(name: "Spam")
  ban    = UserBan.create!(user: user, ban_reason: reason, banned_until: 1.day.from_now)
  assert_includes user.user_bans, ban
end
```

- [ ] **Step 2: Run test to verify it fails**

```bash
bin/rails test test/models/user_test.rb
```

Expected: failure — `user_bans` association not defined.

- [ ] **Step 3: Add the association**

In `app/models/user.rb`, add after `has_many :replies, dependent: :destroy`:

```ruby
has_many :user_bans
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
bin/rails test test/models/user_test.rb
```

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add app/models/user.rb test/models/user_test.rb
git commit -m "feat: add has_many :user_bans to User"
```

---

### Task 5: Seeds

**Files:**
- Modify: `db/seeds.rb`

- [ ] **Step 1: Add ban reasons to seeds**

Add to the bottom of `db/seeds.rb`:

```ruby
["Spam", "Harassment", "Against Guidelines"].each do |name|
  BanReason.find_or_create_by!(name: name)
end
puts "Seeded #{BanReason.count} ban reasons"
```

- [ ] **Step 2: Run seeds to verify they work**

```bash
bin/rails db:seed
```

Expected: "Seeded 3 ban reasons" (or more if re-run).

- [ ] **Step 3: Commit**

```bash
git add db/seeds.rb
git commit -m "feat: seed ban_reasons (Spam, Harassment, Against Guidelines)"
```

---

## Chunk 2: Service, Concern & Controller Integration

### Task 6: BanChecker service

**Files:**
- Create: `app/services/ban_checker.rb`
- Create: `test/services/ban_checker_test.rb`

- [ ] **Step 1: Write the failing tests**

```ruby
# test/services/ban_checker_test.rb
require "test_helper"

class BanCheckerTest < ActiveSupport::TestCase
  setup do
    Provider.find_or_create_by!(id: 3, name: "internal")
    @user   = User.create!(email: "bc@example.com", name: "Ban Checker",
                           password: "pass123", password_confirmation: "pass123", provider_id: 3)
    @reason = BanReason.create!(name: "Spam")
  end

  test "banned? is false when user has no bans" do
    assert_not BanChecker.new(@user).banned?
  end

  test "banned? is true when user has an active ban" do
    UserBan.create!(user: @user, ban_reason: @reason, banned_until: 1.day.from_now)
    assert BanChecker.new(@user).banned?
  end

  test "banned? is false when all bans are expired" do
    UserBan.create!(user: @user, ban_reason: @reason, banned_until: 1.second.ago)
    assert_not BanChecker.new(@user).banned?
  end

  test "banned_until returns nil when not banned" do
    assert_nil BanChecker.new(@user).banned_until
  end

  test "banned_until returns the expiry of the active ban" do
    expiry = 3.days.from_now
    UserBan.create!(user: @user, ban_reason: @reason, banned_until: expiry)
    assert_equal expiry.to_i, BanChecker.new(@user).banned_until.to_i
  end

  test "banned_until returns the latest expiry when multiple active bans exist" do
    UserBan.create!(user: @user, ban_reason: @reason, banned_until: 1.day.from_now)
    later = 5.days.from_now
    UserBan.create!(user: @user, ban_reason: @reason, banned_until: later)
    assert_equal later.to_i, BanChecker.new(@user).banned_until.to_i
  end

  test "expired ban does not make user appear banned" do
    travel_to 2.days.ago do
      UserBan.create!(user: @user, ban_reason: @reason, banned_until: 1.day.from_now)
    end
    assert_not BanChecker.new(@user).banned?
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
bin/rails test test/services/ban_checker_test.rb
```

Expected: NameError or failures (service doesn't exist yet).

- [ ] **Step 3: Write the service**

```ruby
# app/services/ban_checker.rb
class BanChecker
  def initialize(user)
    @user = user
  end

  def banned?
    active_ban.present?
  end

  def banned_until
    active_ban&.banned_until
  end

  private

  def active_ban
    @active_ban ||= @user.user_bans
                         .where("banned_until >= ?", Time.current)
                         .order(banned_until: :desc)
                         .first
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
bin/rails test test/services/ban_checker_test.rb
```

Expected: 7 tests, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add app/services/ban_checker.rb test/services/ban_checker_test.rb
git commit -m "feat: add BanChecker service"
```

---

### Task 7: Bannable concern

**Files:**
- Create: `app/controllers/concerns/bannable.rb`

- [ ] **Step 1: Write the concern**

```ruby
# app/controllers/concerns/bannable.rb
module Bannable
  extend ActiveSupport::Concern

  private

  # Depends on require_login having already run (current_user is guaranteed non-nil).
  def check_not_banned
    checker = BanChecker.new(current_user)
    if checker.banned?
      flash[:alert] = "You are banned until #{checker.banned_until.strftime("%B %-d, %Y")}."
      redirect_to ban_redirect_path
    end
  end

  def ban_redirect_path
    root_path
  end
end
```

- [ ] **Step 2: Commit**

```bash
git add app/controllers/concerns/bannable.rb
git commit -m "feat: add Bannable concern"
```

---

### Task 8: Wire Bannable into PostsController

**Files:**
- Modify: `app/controllers/posts_controller.rb`
- Modify: `test/controllers/posts_controller_test.rb`

- [ ] **Step 1: Write the failing tests**

Add to `test/controllers/posts_controller_test.rb`:

```ruby
# ---- ban enforcement ----

test "POST /posts is blocked when user is banned" do
  ban_reason = BanReason.find_or_create_by!(name: "Spam")
  UserBan.create!(user: @user, ban_reason: ban_reason, banned_until: 1.day.from_now)
  post login_path, params: { email: "u@example.com", password: "pass123" }

  assert_no_difference "Post.count" do
    post posts_path, params: { post: { title: "Sneaky", body: "blocked" } }
  end
  assert_redirected_to new_post_path
  assert_match /banned until/, flash[:alert]
end

test "POST /posts ban flash includes the expiry date" do
  ban_reason = BanReason.find_or_create_by!(name: "Spam")
  expiry = 5.days.from_now
  UserBan.create!(user: @user, ban_reason: ban_reason, banned_until: expiry)
  post login_path, params: { email: "u@example.com", password: "pass123" }
  post posts_path, params: { post: { title: "X", body: "Y" } }
  assert_match expiry.strftime("%B %-d, %Y"), flash[:alert]
end

test "POST /posts is allowed when ban is expired" do
  ban_reason = BanReason.find_or_create_by!(name: "Spam")
  UserBan.create!(user: @user, ban_reason: ban_reason, banned_until: 1.second.ago)
  post login_path, params: { email: "u@example.com", password: "pass123" }

  assert_difference "Post.count", 1 do
    post posts_path, params: { post: { title: "Allowed", body: "some content" } }
  end
end

test "GET /posts/new is accessible when user is banned" do
  ban_reason = BanReason.find_or_create_by!(name: "Spam")
  UserBan.create!(user: @user, ban_reason: ban_reason, banned_until: 1.day.from_now)
  post login_path, params: { email: "u@example.com", password: "pass123" }
  get new_post_path
  assert_response :success
end
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
bin/rails test test/controllers/posts_controller_test.rb
```

Expected: 3 new failures — ban check not wired in yet.

- [ ] **Step 3: Wire Bannable into PostsController**

In `app/controllers/posts_controller.rb`, make exactly these two insertions (do NOT remove or replace existing lines):

**Insert** `include Bannable` directly after the existing `include RateLimitable` line:
```ruby
include Bannable   # ADD — insert after existing `include RateLimitable`
```

**Insert** `before_action :check_not_banned, only: [:create]` between the existing `require_login` and `check_rate_limit` lines:
```ruby
before_action :check_not_banned, only: [:create]   # ADD — insert after require_login, before check_rate_limit
```

**Add** to the private section:
```ruby
def ban_redirect_path
  new_post_path
end
```

The top of the controller should look like this after the changes:
```ruby
include RateLimitable
include Bannable                                    # new

before_action :require_login, only: [:new, :create]
before_action :check_not_banned, only: [:create]   # new
before_action :check_rate_limit, only: [:create]
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
bin/rails test test/controllers/posts_controller_test.rb
```

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add app/controllers/posts_controller.rb test/controllers/posts_controller_test.rb
git commit -m "feat: enforce ban check in PostsController"
```

---

### Task 9: Wire Bannable into RepliesController

**Files:**
- Modify: `app/controllers/replies_controller.rb`
- Modify: `test/controllers/replies_controller_test.rb`

- [ ] **Step 1: Write the failing tests**

Add to `test/controllers/replies_controller_test.rb`:

```ruby
# ---- ban enforcement ----

test "POST /posts/:post_id/replies is blocked when user is banned" do
  ban_reason = BanReason.find_or_create_by!(name: "Spam")
  UserBan.create!(user: @user, ban_reason: ban_reason, banned_until: 1.day.from_now)
  post login_path, params: { email: "u@example.com", password: "pass123" }

  assert_no_difference "Reply.count" do
    post post_replies_path(@post), params: { reply: { body: "blocked reply" } }
  end
  assert_redirected_to post_path(@post)
  assert_match /banned until/, flash[:alert]
end

test "POST /posts/:post_id/replies ban redirects back to the post, not root" do
  ban_reason = BanReason.find_or_create_by!(name: "Spam")
  UserBan.create!(user: @user, ban_reason: ban_reason, banned_until: 1.day.from_now)
  post login_path, params: { email: "u@example.com", password: "pass123" }
  post post_replies_path(@post), params: { reply: { body: "blocked" } }
  assert_redirected_to post_path(@post)
end

test "POST /posts/:post_id/replies is allowed when ban is expired" do
  ban_reason = BanReason.find_or_create_by!(name: "Spam")
  UserBan.create!(user: @user, ban_reason: ban_reason, banned_until: 1.second.ago)
  post login_path, params: { email: "u@example.com", password: "pass123" }

  assert_difference "Reply.count", 1 do
    post post_replies_path(@post), params: { reply: { body: "allowed reply" } }
  end
end

test "DELETE /posts/:post_id/replies/:id is unaffected by ban" do
  ban_reason = BanReason.find_or_create_by!(name: "Spam")
  UserBan.create!(user: @user, ban_reason: ban_reason, banned_until: 1.day.from_now)
  post login_path, params: { email: "u@example.com", password: "pass123" }
  reply = Reply.create!(post: @post, user: @user, body: "My reply")

  assert_difference "Reply.count", -1 do
    delete post_reply_path(@post, reply)
  end
  assert_redirected_to post_path(@post)
end
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
bin/rails test test/controllers/replies_controller_test.rb
```

Expected: 4 new failures — ban check not wired in yet.

- [ ] **Step 3: Wire Bannable into RepliesController**

In `app/controllers/replies_controller.rb`, make exactly these two insertions (do NOT remove or replace existing lines):

**Insert** `include Bannable` directly after the existing `include RateLimitable` line:
```ruby
include Bannable   # ADD — insert after existing `include RateLimitable`
```

**Insert** `before_action :check_not_banned, only: [:create]` between the existing `require_login` and `check_rate_limit` lines:
```ruby
before_action :check_not_banned, only: [:create]   # ADD — insert after require_login, before check_rate_limit
```

**Add** to the private section:
```ruby
def ban_redirect_path
  post_path(params[:post_id])
end
```

The top of the controller should look like this after the changes:
```ruby
include RateLimitable
include Bannable                                    # new

before_action :require_login
before_action :check_not_banned, only: [:create]   # new
before_action :check_rate_limit, only: [:create]
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
bin/rails test test/controllers/replies_controller_test.rb
```

Expected: all tests pass.

- [ ] **Step 5: Run the full test suite**

```bash
bin/rails test
```

Expected: all tests pass, 0 failures.

- [ ] **Step 6: Commit**

```bash
git add app/controllers/replies_controller.rb test/controllers/replies_controller_test.rb
git commit -m "feat: enforce ban check in RepliesController"
```
