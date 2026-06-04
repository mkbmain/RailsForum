# Bug Fixes Batch 2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix four confirmed bugs: stale notification badge count, missing delete confirm dialog, silent Turbo frame session timeout, and missing brute force protection on login.

**Architecture:** Each fix is independent and minimal — no new abstractions except `LoginThrottle` (a service matching the existing `PostRateLimiter` pattern). The brute force fix uses `Rails.cache` (backed by solid_cache, already in the stack) to track failed attempts per IP.

**Tech Stack:** Rails 8.1, Minitest, Turbo/Hotwire, solid_cache, Tailwind CSS

---

## File Map

| File | Change |
|---|---|
| `app/controllers/notifications_controller.rb` | Move orphan filter here; compute `@unread_count` from filtered set |
| `app/views/notifications/index.html.erb` | Remove inline orphan filter (moved to controller); use `@unread_count` from controller |
| `app/views/replies/_reply.html.erb` | Add `data: { confirm: }` to user's Delete button |
| `app/controllers/application_controller.rb` | Fix Turbo frame session timeout to redirect the full page |
| `app/services/login_throttle.rb` | **NEW** — rate-limit login attempts per IP using Rails.cache |
| `app/controllers/sessions_controller.rb` | Integrate `LoginThrottle` into `#create` |
| `test/controllers/notifications_controller_test.rb` | Add test: orphaned notification is excluded from count |
| `test/controllers/sessions_controller_test.rb` | Add tests: throttle blocks after 5 failures, clears on success |
| `test/services/login_throttle_test.rb` | **NEW** — unit tests for `LoginThrottle` |

---

## Task 1: Fix stale unread notification count

The view currently computes `visible_notifications = @notifications.reject { |n| n.target_post.nil? }` inline, but `@unread_count` (used for "Mark all read" visibility) comes from a separate DB query that doesn't apply this filter. Move the orphan filter to the controller and recompute `@unread_count` from the filtered set so the badge and button stay consistent with what's actually shown.

**Files:**
- Modify: `app/controllers/notifications_controller.rb`
- Modify: `app/views/notifications/index.html.erb`
- Modify: `test/controllers/notifications_controller_test.rb`

- [ ] **Step 1: Write the failing test**

Add to `test/controllers/notifications_controller_test.rb`:

```ruby
test "GET /notifications excludes orphaned notifications from display and unread count" do
  # Create a second reply and a notification pointing at it
  orphan_reply = Reply.create!(post: @post, user: @actor, body: "orphan reply")
  Notification.create!(user: @user, actor: @actor, notifiable: orphan_reply,
                        event_type: :reply_to_post)
  # Raw-delete the reply (bypasses callbacks so the notification becomes orphaned)
  Reply.where(id: orphan_reply.id).delete_all

  # @user now has 2 DB notifications: @notif (valid) and orphan_notif (notifiable missing)
  post login_path, params: { email: "nuser@example.com", password: "pass123" }
  get notifications_path
  assert_response :success

  # Only the non-orphaned notification should be in @notifications
  assert_equal 1, assigns(:notifications).size
  # Unread count must match the visible set, not the raw DB count
  assert_equal 1, assigns(:unread_count)
end
```

`assigns` is available via the `rails-controller-testing` gem (already in the test group of the Gemfile).

- [ ] **Step 2: Run test to confirm it fails (or is incomplete)**

```bash
bin/rails test test/controllers/notifications_controller_test.rb
```

- [ ] **Step 3: Update the controller**

Replace `notifications_controller.rb` with:

```ruby
class NotificationsController < ApplicationController
  before_action :require_login

  def index
    all_notifications = current_user.notifications
                                    .includes(:actor, :notifiable)
                                    .order(created_at: :desc)
                                    .limit(30)

    reply_notifiables = all_notifications.map(&:notifiable).grep(Reply)
    ActiveRecord::Associations::Preloader.new(records: reply_notifiables, associations: :post).call if reply_notifiables.any?

    @notifications = all_notifications.reject { |n| n.target_post.nil? }
    @unread_count  = @notifications.count(&:unread?)
  end

  def read
    notification = current_user.notifications.find_by(id: params[:id])
    notification&.mark_as_read!
    redirect_to notifications_path
  end

  def read_all
    current_user.notifications.unread.update_all(read_at: Time.current)
    redirect_to notifications_path
  end
end
```

Key changes:
- Orphan filter moves from view to controller
- `@unread_count` is now computed from the filtered in-memory set (no extra DB query)

- [ ] **Step 4: Update the view**

In `app/views/notifications/index.html.erb`, remove the inline orphan filter. The `@notifications` variable is already filtered.

Replace:
```erb
<% visible_notifications = @notifications.reject { |n| n.target_post.nil? } %>
<% if visible_notifications.empty? %>
```
and all occurrences of `visible_notifications` with `@notifications`:

```erb
<% if @notifications.empty? %>
  <div class="bg-white dark:bg-stone-800 border border-stone-200 dark:border-stone-700 rounded-xl p-8 text-center">
    <p class="text-stone-400 dark:text-stone-500 text-sm">No notifications yet.</p>
  </div>
<% else %>
  <div class="space-y-2">
    <% @notifications.each do |n| %>
```

- [ ] **Step 5: Run the full test suite**

```bash
bin/rails test test/controllers/notifications_controller_test.rb test/models/notification_test.rb
```

Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add app/controllers/notifications_controller.rb app/views/notifications/index.html.erb test/controllers/notifications_controller_test.rb
git commit -m "fix: compute notification unread count from visible set, not raw DB count"
```

---

## Task 2: Add confirm dialog to user's Delete reply button

The "Remove" button (moderator soft-delete) already has `data: { confirm: "Remove this reply?" }`. The "Delete" button (user hard-delete) does not, making one-click permanent deletion too easy.

**Files:**
- Modify: `app/views/replies/_reply.html.erb`
- Modify: `test/controllers/replies_controller_test.rb` (verify test coverage exists — no new test needed for a view attribute)

- [ ] **Step 1: Check existing test coverage for reply destroy**

```bash
bin/rails test test/controllers/replies_controller_test.rb
```

Confirm there's a test for user deleting their own reply.

- [ ] **Step 2: Add the confirm attribute**

In `app/views/replies/_reply.html.erb`, find the Delete button (line ~39):

```erb
<%= button_to "Delete", post_reply_path(post, reply), method: :delete,
      class: "text-xs text-gray-400 dark:text-stone-500 hover:text-red-500 bg-transparent border-0 p-0 cursor-pointer" %>
```

Add `data: { confirm: "Delete this reply? This cannot be undone." }`:

```erb
<%= button_to "Delete", post_reply_path(post, reply), method: :delete,
      class: "text-xs text-gray-400 dark:text-stone-500 hover:text-red-500 bg-transparent border-0 p-0 cursor-pointer",
      data: { confirm: "Delete this reply? This cannot be undone." } %>
```

- [ ] **Step 3: Run tests**

```bash
bin/rails test
```

Expected: all pass (this is a view-only change; existing controller tests should still pass).

- [ ] **Step 4: Commit**

```bash
git add app/views/replies/_reply.html.erb
git commit -m "fix: add confirm dialog to reply delete button"
```

---

## Task 3: Fix session timeout in Turbo frame context

Currently `check_session_timeout` returns `head :unauthorized` for Turbo frame requests. The frame silently fails with no user-visible feedback. Fix: set the `Turbo-Frame: _top` response header before redirecting so Turbo loads the redirect at the top-level frame (full page navigation to login).

Turbo Stream requests (non-frame AJAX) will keep returning 401 — those are background requests where a full-page redirect is not appropriate.

**Files:**
- Modify: `app/controllers/application_controller.rb`
- Modify: `test/controllers/sessions_timeout_test.rb` — update the existing Turbo frame test and add the header assertion

- [ ] **Step 1: Locate the existing Turbo frame timeout test**

Open `test/controllers/sessions_timeout_test.rb`. Find the test on line 47:

```ruby
test "expired session returns 401 for Turbo Frame requests" do
```

This test currently asserts `assert_response :unauthorized`. After the fix it must assert a redirect with the `Turbo-Frame: _top` header instead.

- [ ] **Step 2: Update the existing test**

Replace that test with:

```ruby
test "expired session redirects full page for Turbo Frame requests" do
  travel_to 2.minutes.ago do
    login_user
  end

  get root_path, headers: { "Turbo-Frame" => "main" }
  assert_redirected_to login_path
  assert_equal "_top", response.headers["Turbo-Frame"]
  assert_nil session[:user_id]
end
```

- [ ] **Step 3: Run the timeout tests to confirm the updated test now fails**

```bash
bin/rails test test/controllers/sessions_timeout_test.rb
```

Expected: the updated Turbo frame test fails (still returns 401); all other timeout tests still pass.

- [ ] **Step 4: Update `check_session_timeout` in `application_controller.rb`**

Replace the entire `check_session_timeout` method:

```ruby
def check_session_timeout
  return if session_timeout_minutes == 0

  unless session[:last_active_at]
    session[:last_active_at] = Time.current.to_i
    return
  end

  if Time.current.to_i - session[:last_active_at] > session_timeout_minutes * 60
    @current_user = nil
    reset_session

    if request.format.turbo_stream? || request.format.json?
      head :unauthorized
    else
      response.set_header("Turbo-Frame", "_top") if turbo_frame_request?
      redirect_to login_path, alert: "Your session has expired. Please log in again."
    end
  end
end
```

Changes from the original:
- Turbo frame requests now get a redirect (not 401) with `Turbo-Frame: _top` so Turbo navigates the full page
- Turbo Stream and JSON requests still return 401 (appropriate for background/AJAX requests)

- [ ] **Step 5: Run the timeout tests**

```bash
bin/rails test test/controllers/sessions_timeout_test.rb
```

Expected: all tests pass, including the updated Turbo frame test.

- [ ] **Step 6: Run full suite**

```bash
bin/rails test
```

Expected: all pass.

- [ ] **Step 7: Commit**

```bash
git add app/controllers/application_controller.rb test/controllers/sessions_timeout_test.rb
git commit -m "fix: redirect full page on session timeout in Turbo frame context"
```

---

## Task 4: Add login brute force protection

No protection exists against password guessing. Add a `LoginThrottle` service (matching the `PostRateLimiter` pattern) that uses `Rails.cache` (solid_cache) to track failed attempts per IP. After 5 failures in 10 minutes, block further attempts with a clear error message.

**Files:**
- Create: `app/services/login_throttle.rb`
- Modify: `app/controllers/sessions_controller.rb`
- Create: `test/services/login_throttle_test.rb`
- Modify: `test/controllers/sessions_controller_test.rb`

- [ ] **Step 1: Write unit tests for `LoginThrottle`**

Create `test/services/login_throttle_test.rb`:

```ruby
require "test_helper"

class LoginThrottleTest < ActiveSupport::TestCase
  setup do
    Rails.cache.clear
    @throttle = LoginThrottle.new("1.2.3.4")
  end

  teardown do
    Rails.cache.clear
  end

  test "not throttled with zero failures" do
    assert_not @throttle.throttled?
  end

  test "not throttled below the limit" do
    (LoginThrottle::MAX_ATTEMPTS - 1).times { @throttle.record_failure! }
    assert_not @throttle.throttled?
  end

  test "throttled at the limit" do
    LoginThrottle::MAX_ATTEMPTS.times { @throttle.record_failure! }
    assert @throttle.throttled?
  end

  test "clear! resets the counter" do
    LoginThrottle::MAX_ATTEMPTS.times { @throttle.record_failure! }
    assert @throttle.throttled?
    @throttle.clear!
    assert_not @throttle.throttled?
  end

  test "separate IPs are tracked independently" do
    other = LoginThrottle.new("9.9.9.9")
    LoginThrottle::MAX_ATTEMPTS.times { @throttle.record_failure! }
    assert @throttle.throttled?
    assert_not other.throttled?
  end
end
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
bin/rails test test/services/login_throttle_test.rb
```

Expected: FAIL — `LoginThrottle` does not exist yet.

- [ ] **Step 3: Create `LoginThrottle`**

Create `app/services/login_throttle.rb`:

```ruby
class LoginThrottle
  MAX_ATTEMPTS = 5
  WINDOW       = 10.minutes

  def initialize(ip)
    @key = "login_attempts:#{ip}"
  end

  def throttled?
    attempts >= MAX_ATTEMPTS
  end

  def record_failure!
    count = attempts + 1
    Rails.cache.write(@key, count, expires_in: WINDOW)
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

- [ ] **Step 4: Run service tests**

```bash
bin/rails test test/services/login_throttle_test.rb
```

Expected: all 5 tests pass.

- [ ] **Step 5: Write controller integration tests for throttling**

Add to `test/controllers/sessions_controller_test.rb`:

```ruby
test "POST /login is blocked after too many failed attempts" do
  LoginThrottle::MAX_ATTEMPTS.times do
    post login_path, params: { email: "user@example.com", password: "wrong" }
  end
  post login_path, params: { email: "user@example.com", password: "wrong" }
  assert_response :too_many_requests
  assert_select "form"  # login form still shown
end

test "POST /login throttle clears on successful login" do
  (LoginThrottle::MAX_ATTEMPTS - 1).times do
    post login_path, params: { email: "user@example.com", password: "wrong" }
  end
  post login_path, params: { email: "user@example.com", password: "password123" }
  assert_redirected_to root_path

  # After successful login, a wrong attempt should NOT be immediately blocked
  delete logout_path
  post login_path, params: { email: "user@example.com", password: "wrong" }
  assert_response :unprocessable_entity  # not :too_many_requests
end
```

Also add a `teardown` block to `sessions_controller_test.rb` so cache state doesn't bleed between tests:

```ruby
teardown do
  Rails.cache.clear
end
```

- [ ] **Step 6: Run controller tests to confirm they fail**

```bash
bin/rails test test/controllers/sessions_controller_test.rb
```

Expected: the two new tests fail (no throttle in controller yet).

- [ ] **Step 7: Integrate `LoginThrottle` into `SessionsController#create`**

Replace `sessions_controller.rb#create`:

```ruby
def create
  throttle = LoginThrottle.new(request.remote_ip)

  if throttle.throttled?
    flash.now[:alert] = "Too many failed login attempts. Please wait before trying again."
    render :new, status: :too_many_requests
    return
  end

  user = User.find_by(email: params[:email].to_s.downcase)
  if user&.authenticate(params[:password])
    throttle.clear!
    reset_session
    session[:user_id] = user.id
    redirect_to root_path, notice: "Welcome back, #{user.name}!"
  else
    throttle.record_failure!
    flash.now[:alert] = "Invalid email or password."
    render :new, status: :unprocessable_entity
  end
end
```

- [ ] **Step 8: Run all login-related tests**

```bash
bin/rails test test/services/login_throttle_test.rb test/controllers/sessions_controller_test.rb
```

Expected: all pass.

- [ ] **Step 9: Run full suite**

```bash
bin/rails test
```

Expected: all pass.

- [ ] **Step 10: Commit**

```bash
git add app/services/login_throttle.rb app/controllers/sessions_controller.rb \
        test/services/login_throttle_test.rb test/controllers/sessions_controller_test.rb
git commit -m "feat: add login brute force protection via LoginThrottle (5 attempts / 10 min)"
```
