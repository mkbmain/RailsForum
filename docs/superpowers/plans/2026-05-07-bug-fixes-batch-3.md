# Bug Fixes Batch 3 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix 6 bugs: user bio length limit, mention notifications firing inside code blocks, NotificationService partial-failure state, reply soft-delete inconsistency, expired token accumulation, and missing per-user 2FA throttle.

**Architecture:** Each fix is independent — model validation + migration, service logic, controller behaviour, a new background job, and a new throttle service. All follow existing patterns in the codebase (bcrypt auth, Solid Queue recurring tasks, Rails.cache throttling).

**Tech Stack:** Rails 8.1, PostgreSQL, Minitest, Solid Queue (recurring jobs), Rails.cache

---

## File Map

| File | Action | Purpose |
|------|--------|---------|
| `app/models/user.rb` | Modify | Add bio length validation |
| `db/migrate/TIMESTAMP_add_bio_length_constraint_to_users.rb` | Create | DB CHECK constraint for bio |
| `test/models/user_test.rb` | Modify | Bio length test |
| `app/services/notification_service.rb` | Modify | Strip code blocks before mention scan; wrap in transaction |
| `test/services/notification_service_test.rb` | Modify | Mention-in-code-block test; transaction rollback test |
| `app/controllers/replies_controller.rb` | Modify | User destroy → soft-delete |
| `test/controllers/replies_controller_test.rb` | Modify | Update delete test; add soft-delete assertion |
| `app/jobs/clean_expired_tokens_job.rb` | Create | Delete expired PasswordReset + EmailVerification rows |
| `test/jobs/clean_expired_tokens_job_test.rb` | Create | Cleans expired, keeps unexpired |
| `config/recurring.yml` | Modify | Schedule cleanup job hourly |
| `app/services/two_factor_throttle.rb` | Create | Per-user 2FA attempt throttle |
| `config/initializers/two_factor_throttle.rb` | Create | Configurable defaults (5 attempts, 15 min) |
| `test/services/two_factor_throttle_test.rb` | Create | Throttle behaviour + config |
| `app/controllers/two_factors_controller.rb` | Modify | Add TwoFactorThrottle to confirm_verify |
| `test/controllers/two_factor_controller_test.rb` | Modify | Add user-throttle test |

---

## Task 1: User bio length limit (Fix #9)

**Files:**
- Modify: `app/models/user.rb`
- Create: `db/migrate/TIMESTAMP_add_bio_length_constraint_to_users.rb`
- Modify: `test/models/user_test.rb`

- [ ] **Step 1: Write the failing model test**

Add to `test/models/user_test.rb` (after existing tests):

```ruby
test "bio longer than 500 characters is invalid" do
  user = User.new(email: "bio@example.com", name: "Bio User",
                  password: "pass123", password_confirmation: "pass123",
                  provider_id: 3, bio: "x" * 501)
  assert_not user.valid?
  assert_includes user.errors[:bio], "is too long (maximum is 500 characters)"
end

test "bio of exactly 500 characters is valid" do
  user = User.new(email: "bio2@example.com", name: "Bio User2",
                  password: "pass123", password_confirmation: "pass123",
                  provider_id: 3, bio: "x" * 500)
  assert user.valid?
end

test "blank bio is valid" do
  user = User.new(email: "bio3@example.com", name: "Bio User3",
                  password: "pass123", password_confirmation: "pass123",
                  provider_id: 3, bio: "")
  assert user.valid?
end
```

- [ ] **Step 2: Run test to confirm failure**

```bash
bin/rails test test/models/user_test.rb -n "/bio/"
```

Expected: FAIL — "bio longer than 500 characters is invalid" fails because no validation exists.

- [ ] **Step 3: Add validation to User model**

In `app/models/user.rb`, add after the `avatar_url` validation (line ~28):

```ruby
validates :bio, length: { maximum: 500 }, allow_blank: true
```

- [ ] **Step 4: Run test to confirm pass**

```bash
bin/rails test test/models/user_test.rb -n "/bio/"
```

Expected: 3 tests, 0 failures.

- [ ] **Step 5: Generate and write migration**

```bash
bin/rails generate migration AddBioLengthConstraintToUsers
```

Open the generated file and replace its content with:

```ruby
class AddBioLengthConstraintToUsers < ActiveRecord::Migration[8.1]
  def up
    add_check_constraint :users, "char_length(bio) <= 500", name: "users_bio_max_length"
  end

  def down
    remove_check_constraint :users, name: "users_bio_max_length"
  end
end
```

- [ ] **Step 6: Run migration**

```bash
bin/rails db:migrate
```

Expected: migration runs cleanly.

- [ ] **Step 7: Run full model tests to check no regressions**

```bash
bin/rails test test/models/user_test.rb
```

Expected: all pass.

- [ ] **Step 8: Commit**

```bash
git add app/models/user.rb db/migrate/*add_bio_length* db/structure.sql test/models/user_test.rb
git commit -m "fix: add 500 character limit to user bio"
```

---

## Task 2: Mention regex skips code blocks (Fix #4)

**Files:**
- Modify: `app/services/notification_service.rb`
- Modify: `test/services/notification_service_test.rb`

- [ ] **Step 1: Write failing test**

In `test/services/notification_service_test.rb`, add after the existing mention tests:

```ruby
test "does not notify user mentioned inside a fenced code block" do
  mentioned = User.create!(email: "codementor@example.com", name: "codementor",
                           password: "pass123", password_confirmation: "pass123", provider_id: 3)
  reply_with_code = Reply.create!(
    post: @post, user: @replier,
    body: "here is an example:\n```\n@codementor does this\n```\nnot a real mention"
  )
  assert_no_difference "Notification.where(event_type: :mention).count" do
    NotificationService.reply_created(reply_with_code, current_user: @replier)
  end
end

test "does not notify user mentioned inside an inline code span" do
  mentioned = User.create!(email: "inlinementor@example.com", name: "inlinementor",
                           password: "pass123", password_confirmation: "pass123", provider_id: 3)
  reply_with_inline = Reply.create!(
    post: @post, user: @replier,
    body: "run `@inlinementor` in your shell"
  )
  assert_no_difference "Notification.where(event_type: :mention).count" do
    NotificationService.reply_created(reply_with_inline, current_user: @replier)
  end
end

test "still notifies user mentioned outside code blocks" do
  mentioned = User.create!(email: "realmentor@example.com", name: "realmentor",
                           password: "pass123", password_confirmation: "pass123", provider_id: 3)
  reply_mixed = Reply.create!(
    post: @post, user: @replier,
    body: "hey @realmentor, see this:\n```\n@other_person\n```"
  )
  assert_difference "Notification.where(event_type: :mention).count", 1 do
    NotificationService.reply_created(reply_mixed, current_user: @replier)
  end
  n = Notification.find_by(user: mentioned, event_type: :mention)
  assert_not_nil n
end
```

- [ ] **Step 2: Run tests to confirm failure**

```bash
bin/rails test test/services/notification_service_test.rb -n "/code block|code span|outside code/"
```

Expected: first two fail (mention fires inside code), third passes.

- [ ] **Step 3: Update NotificationService to strip code before scanning**

In `app/services/notification_service.rb`, find the mention section (around line 50):

```ruby
    # 3. mention — parse @username patterns
    reply.body.scan(/@(\w+)/i).flatten.uniq.each do |username|
```

Replace it with:

```ruby
    # 3. mention — parse @username patterns (skip code blocks and inline code)
    body_without_code = reply.body
      .gsub(/```.*?```/m, "")
      .gsub(/`[^`]*`/, "")
    body_without_code.scan(/@(\w+)/i).flatten.uniq.each do |username|
```

- [ ] **Step 4: Run tests to confirm pass**

```bash
bin/rails test test/services/notification_service_test.rb -n "/code block|code span|outside code/"
```

Expected: 3 pass.

- [ ] **Step 5: Run full notification service tests**

```bash
bin/rails test test/services/notification_service_test.rb
```

Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add app/services/notification_service.rb test/services/notification_service_test.rb
git commit -m "fix: skip @mentions inside code blocks and inline code spans"
```

---

## Task 3: NotificationService transaction (Fix #7)

**Files:**
- Modify: `app/services/notification_service.rb`
- Modify: `test/services/notification_service_test.rb`

- [ ] **Step 1: Write failing test**

Add to `test/services/notification_service_test.rb`:

```ruby
test "rolls back all notifications when any creation fails" do
  # Override Notification.create! to succeed on call 1, raise on call 2
  original_create = Notification.method(:create!)
  call_count = 0

  Notification.define_singleton_method(:create!) do |*args, **kwargs|
    call_count += 1
    raise ActiveRecord::RecordInvalid.new(Notification.new) if call_count == 2
    original_create.call(*args, **kwargs)
  end

  assert_raises(ActiveRecord::RecordInvalid) do
    NotificationService.reply_created(@reply, current_user: @replier)
  end

  assert_equal 0, Notification.count, "transaction must roll back all notifications"
ensure
  Notification.define_singleton_method(:create!, original_create)
end
```

- [ ] **Step 2: Run test to confirm failure**

```bash
bin/rails test test/services/notification_service_test.rb -n "/rolls back/"
```

Expected: FAIL — 1 notification remains after the exception (no transaction yet).

- [ ] **Step 3: Wrap reply_created in a transaction**

In `app/services/notification_service.rb`, wrap the body of `reply_created` in a transaction. The full updated method:

```ruby
def self.reply_created(reply, current_user:)
  actor             = current_user
  post              = reply.post
  already_notified  = Set.new

  ActiveRecord::Base.transaction do
    # 1. reply_to_post — notify post owner
    if post.user != actor
      Notification.create!(
        user:       post.user,
        actor:      actor,
        notifiable: reply,
        event_type: :reply_to_post
      )
      already_notified.add(post.user.id)
    end

    # 2. reply_in_thread — notify prior participants (deduplicated per 24h)
    reply_ids_in_post = post.replies.pluck(:id)
    recent_thread_notified_ids = Notification
      .where(notifiable_type: "Reply", notifiable_id: reply_ids_in_post, event_type: :reply_in_thread)
      .where("created_at > ?", 24.hours.ago)
      .pluck(:user_id)

    excluded_ids = [ actor.id ] + already_notified.to_a + recent_thread_notified_ids

    participant_ids = post.replies
                         .where.not(id: reply.id)
                         .where.not(user_id: excluded_ids)
                         .distinct
                         .pluck(:user_id)

    participant_ids.each do |uid|
      Notification.create!(
        user_id:          uid,
        actor_id:         actor.id,
        notifiable_type:  "Reply",
        notifiable_id:    reply.id,
        event_type:       :reply_in_thread
      )
      already_notified.add(uid)
    end

    # 3. mention — parse @username patterns (skip code blocks and inline code)
    body_without_code = reply.body
      .gsub(/```.*?```/m, "")
      .gsub(/`[^`]*`/, "")
    body_without_code.scan(/@(\w+)/i).flatten.uniq.each do |username|
      mentioned = User.find_by_mention_handle(username)
      next unless mentioned
      next if mentioned == actor
      next if already_notified.include?(mentioned.id)

      Notification.create!(
        user:       mentioned,
        actor:      actor,
        notifiable: reply,
        event_type: :mention
      )
      already_notified.add(mentioned.id)
    end
  end
end
```

- [ ] **Step 4: Run test to confirm pass**

```bash
bin/rails test test/services/notification_service_test.rb -n "/rolls back/"
```

Expected: PASS.

- [ ] **Step 5: Run full notification service tests**

```bash
bin/rails test test/services/notification_service_test.rb
```

Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add app/services/notification_service.rb test/services/notification_service_test.rb
git commit -m "fix: wrap NotificationService.reply_created in a transaction"
```

---

## Task 4: Reply soft-delete for users (Fix #5)

**Files:**
- Modify: `app/controllers/replies_controller.rb`
- Modify: `test/controllers/replies_controller_test.rb`

- [ ] **Step 1: Update the existing delete test and add soft-delete assertion**

In `test/controllers/replies_controller_test.rb`, find the test:

```ruby
test "DELETE /posts/:post_id/replies/:id succeeds when owner" do
  post login_path, params: { email: "u@example.com", password: "pass123" }
  reply = Reply.create!(post: @post, user: @user, body: "My reply")
  assert_difference "Reply.count", -1 do
    delete post_reply_path(@post, reply)
  end
  assert_redirected_to post_path(@post)
end
```

Replace it with:

```ruby
test "DELETE /posts/:post_id/replies/:id soft-deletes when owner" do
  post login_path, params: { email: "u@example.com", password: "pass123" }
  reply = Reply.create!(post: @post, user: @user, body: "My reply")
  assert_no_difference "Reply.count" do
    delete post_reply_path(@post, reply)
  end
  assert_redirected_to post_path(@post)
  reply.reload
  assert reply.removed?, "reply should be soft-deleted"
  assert_equal @user, reply.removed_by, "removed_by should be the owner"
end
```

- [ ] **Step 2: Run test to confirm failure**

```bash
bin/rails test test/controllers/replies_controller_test.rb -n "/soft-deletes when owner/"
```

Expected: FAIL — Reply.count decreases by 1 (hard delete still active).

- [ ] **Step 3: Update the destroy action in RepliesController**

In `app/controllers/replies_controller.rb`, find the `destroy` action and replace the `elsif @reply.user == current_user` branch:

Old code (lines 63–66):
```ruby
    elsif @reply.user == current_user
      @reply.destroy
      @post.update_column(:last_replied_at, @post.replies.visible.maximum(:created_at))
      broadcast_reply_hard_deleted
```

New code:
```ruby
    elsif @reply.user == current_user
      @reply.update!(removed_at: Time.current, removed_by: current_user)
      @post.update_column(:last_replied_at, @post.replies.visible.maximum(:created_at))
      broadcast_reply_soft_deleted
```

- [ ] **Step 4: Run test to confirm pass**

```bash
bin/rails test test/controllers/replies_controller_test.rb -n "/soft-deletes when owner/"
```

Expected: PASS.

- [ ] **Step 5: Run full replies controller tests**

```bash
bin/rails test test/controllers/replies_controller_test.rb
```

Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add app/controllers/replies_controller.rb test/controllers/replies_controller_test.rb
git commit -m "fix: soft-delete replies when user self-deletes instead of hard-delete"
```

---

## Task 5: Token cleanup job (Fix #1)

**Files:**
- Create: `app/jobs/clean_expired_tokens_job.rb`
- Create: `test/jobs/clean_expired_tokens_job_test.rb`
- Modify: `config/recurring.yml`

- [ ] **Step 1: Create the test file**

Create `test/jobs/clean_expired_tokens_job_test.rb`:

```ruby
require "test_helper"

class CleanExpiredTokensJobTest < ActiveSupport::TestCase
  setup do
    Provider.find_or_create_by!(id: 3, name: "internal")
    @user = User.create!(email: "token@example.com", name: "Token User",
                         password: "pass123", password_confirmation: "pass123",
                         provider_id: 3)
  end

  test "deletes expired password resets" do
    pr = PasswordReset.create!(user: @user)
    pr.update_columns(created_at: (PasswordReset::EXPIRY + 1.minute).ago)

    assert_difference "PasswordReset.count", -1 do
      CleanExpiredTokensJob.perform_now
    end
  end

  test "keeps unexpired password resets" do
    PasswordReset.create!(user: @user)

    assert_no_difference "PasswordReset.count" do
      CleanExpiredTokensJob.perform_now
    end
  end

  test "deletes expired email verifications" do
    ev = EmailVerification.create!(user: @user)
    ev.update_columns(created_at: (EmailVerification::EXPIRY + 1.minute).ago)

    assert_difference "EmailVerification.count", -1 do
      CleanExpiredTokensJob.perform_now
    end
  end

  test "keeps unexpired email verifications" do
    EmailVerification.create!(user: @user)

    assert_no_difference "EmailVerification.count" do
      CleanExpiredTokensJob.perform_now
    end
  end

  test "deletes both in one run" do
    pr = PasswordReset.create!(user: @user)
    pr.update_columns(created_at: (PasswordReset::EXPIRY + 1.minute).ago)

    user2 = User.create!(email: "token2@example.com", name: "Token User2",
                         password: "pass123", password_confirmation: "pass123",
                         provider_id: 3)
    ev = EmailVerification.create!(user: user2)
    ev.update_columns(created_at: (EmailVerification::EXPIRY + 1.minute).ago)

    assert_difference "PasswordReset.count", -1 do
      assert_difference "EmailVerification.count", -1 do
        CleanExpiredTokensJob.perform_now
      end
    end
  end
end
```

- [ ] **Step 2: Run tests to confirm failure**

```bash
mkdir -p test/jobs
bin/rails test test/jobs/clean_expired_tokens_job_test.rb
```

Expected: error — `CleanExpiredTokensJob` is uninitialized.

- [ ] **Step 3: Create the job**

Create `app/jobs/clean_expired_tokens_job.rb`:

```ruby
class CleanExpiredTokensJob < ApplicationJob
  queue_as :background

  def perform
    PasswordReset.where("created_at < ?", PasswordReset::EXPIRY.ago).delete_all
    EmailVerification.where("created_at < ?", EmailVerification::EXPIRY.ago).delete_all
  end
end
```

- [ ] **Step 4: Run tests to confirm pass**

```bash
bin/rails test test/jobs/clean_expired_tokens_job_test.rb
```

Expected: 5 tests, 0 failures.

- [ ] **Step 5: Register in recurring.yml**

In `config/recurring.yml`, add the new entry under `production:`:

```yaml
production:
  clear_solid_queue_finished_jobs:
    command: "SolidQueue::Job.clear_finished_in_batches(sleep_between_batches: 0.3)"
    schedule: every hour at minute 12

  clean_expired_tokens:
    class: CleanExpiredTokensJob
    queue: background
    schedule: every hour at minute 30
```

- [ ] **Step 6: Commit**

```bash
git add app/jobs/clean_expired_tokens_job.rb test/jobs/clean_expired_tokens_job_test.rb config/recurring.yml
git commit -m "fix: add job to clean up expired password reset and email verification tokens"
```

---

## Task 6: Configurable per-user 2FA throttle (Fix #2)

**Files:**
- Create: `app/services/two_factor_throttle.rb`
- Create: `config/initializers/two_factor_throttle.rb`
- Create: `test/services/two_factor_throttle_test.rb`
- Modify: `app/controllers/two_factors_controller.rb`
- Modify: `test/controllers/two_factor_controller_test.rb`

- [ ] **Step 1: Write the service tests**

Create `test/services/two_factor_throttle_test.rb`:

```ruby
require "test_helper"

class TwoFactorThrottleTest < ActiveSupport::TestCase
  setup do
    Rails.cache.clear
    @throttle = TwoFactorThrottle.new(42)
  end

  teardown do
    Rails.cache.clear
  end

  test "not throttled with zero failures" do
    assert_not @throttle.throttled?
  end

  test "not throttled below the limit" do
    (Rails.application.config.x.two_factor_max_attempts - 1).times { @throttle.record_failure! }
    assert_not @throttle.throttled?
  end

  test "throttled at the limit" do
    Rails.application.config.x.two_factor_max_attempts.times { @throttle.record_failure! }
    assert @throttle.throttled?
  end

  test "clear! resets the counter" do
    Rails.application.config.x.two_factor_max_attempts.times { @throttle.record_failure! }
    @throttle.clear!
    assert_not @throttle.throttled?
  end

  test "separate user IDs are tracked independently" do
    other = TwoFactorThrottle.new(99)
    Rails.application.config.x.two_factor_max_attempts.times { @throttle.record_failure! }
    assert @throttle.throttled?
    assert_not other.throttled?
  end
end
```

- [ ] **Step 2: Run tests to confirm failure**

```bash
bin/rails test test/services/two_factor_throttle_test.rb
```

Expected: error — `TwoFactorThrottle` is uninitialized.

- [ ] **Step 3: Create the initializer with configurable defaults**

Create `config/initializers/two_factor_throttle.rb`:

```ruby
Rails.application.config.x.two_factor_max_attempts    = 5
Rails.application.config.x.two_factor_lockout_minutes = 15
```

- [ ] **Step 4: Create the service**

Create `app/services/two_factor_throttle.rb`:

```ruby
class TwoFactorThrottle
  def initialize(user_id)
    @key     = "2fa_attempts:#{user_id}"
    @max     = Rails.application.config.x.two_factor_max_attempts
    @window  = Rails.application.config.x.two_factor_lockout_minutes.minutes
  end

  def throttled?
    attempts >= @max
  end

  def record_failure!
    written = Rails.cache.write(@key, 1, expires_in: @window, unless_exist: true)
    Rails.cache.increment(@key) unless written
  end

  def clear!
    Rails.cache.delete(@key)
  end

  private

  def attempts
    Rails.cache.read(@key).to_i
  end
end
```

- [ ] **Step 5: Run service tests to confirm pass**

```bash
bin/rails test test/services/two_factor_throttle_test.rb
```

Expected: 5 tests, 0 failures.

- [ ] **Step 6: Write controller test for user-level throttle**

In `test/controllers/two_factor_controller_test.rb`, find the `teardown` block and add after the existing 2FA verify tests:

```ruby
test "confirm_verify is blocked after too many failures for the same user (user throttle)" do
  secret = ROTP::Base32.random
  @user.update!(totp_secret: secret)
  delete logout_path
  post login_path, params: { email: @user.email, password: "password123" }

  # Exhaust the user-level throttle by recording failures directly
  throttle = TwoFactorThrottle.new(@user.id)
  Rails.application.config.x.two_factor_max_attempts.times { throttle.record_failure! }

  post verify_two_factor_path, params: { code: "000000" }
  assert_response :too_many_requests
end
```

- [ ] **Step 7: Run controller test to confirm failure**

```bash
bin/rails test test/controllers/two_factor_controller_test.rb -n "/user throttle/"
```

Expected: FAIL — 200 or 422, not 429.

- [ ] **Step 8: Update TwoFactorsController#confirm_verify**

In `app/controllers/two_factors_controller.rb`, replace the `confirm_verify` action with:

```ruby
def confirm_verify
  redirect_to root_path and return unless session[:awaiting_2fa]

  user_id       = session[:awaiting_2fa]
  ip_throttle   = LoginThrottle.new(request.remote_ip)
  user_throttle = TwoFactorThrottle.new(user_id)

  if ip_throttle.throttled? || user_throttle.throttled?
    flash.now[:alert] = "Too many failed attempts. Please wait before trying again."
    render :verify, status: :too_many_requests
    return
  end

  user = User.find_by(id: user_id)
  unless user
    reset_session
    redirect_to login_path, alert: "Session expired. Please log in again."
    return
  end

  submitted = params[:code].to_s.strip.gsub(/\s/, "")
  totp = ROTP::TOTP.new(user.totp_secret)
  valid = totp.verify(submitted, drift_behind: 30, drift_ahead: 30) ||
          BackupCode.consume_for(user, submitted)

  if valid
    ip_throttle.clear!
    user_throttle.clear!
    reset_session
    session[:user_id] = user.id
    redirect_to root_path, notice: "Welcome back, #{user.name}!"
  else
    ip_throttle.record_failure!
    user_throttle.record_failure!
    flash.now[:alert] = "Invalid code."
    render :verify, status: :unprocessable_entity
  end
end
```

- [ ] **Step 9: Run controller test to confirm pass**

```bash
bin/rails test test/controllers/two_factor_controller_test.rb -n "/user throttle/"
```

Expected: PASS.

- [ ] **Step 10: Run full 2FA controller tests**

```bash
bin/rails test test/controllers/two_factor_controller_test.rb
```

Expected: all pass.

- [ ] **Step 11: Commit**

```bash
git add app/services/two_factor_throttle.rb config/initializers/two_factor_throttle.rb \
        test/services/two_factor_throttle_test.rb \
        app/controllers/two_factors_controller.rb \
        test/controllers/two_factor_controller_test.rb
git commit -m "fix: add configurable per-user throttle for 2FA verification attempts"
```

---

## Final verification

- [ ] **Run full test suite**

```bash
bin/rails test
```

Expected: all tests pass, 0 failures, 0 errors.

- [ ] **Run linter**

```bash
./bin/rubocop
```

Expected: no offenses (fix any reported before marking complete).

- [ ] **Run security audit**

```bash
./bin/brakeman
```

Expected: no new warnings.
