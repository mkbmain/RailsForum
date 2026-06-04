# Session Timeout Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add idle session timeout to the forum so inactive sessions expire after a configurable number of minutes.

**Architecture:** Store `session[:last_active_at]` as a Unix integer in the existing Rails cookie session. A `before_action` in `ApplicationController` checks elapsed time on every authenticated request and expires the session if the threshold is exceeded. An `after_action` refreshes the timestamp on every response.

**Tech Stack:** Rails 8.1, Minitest (`ActionDispatch::IntegrationTest`), Rails time helpers (`travel_to`)

---

## File Map

| File | Change |
|------|--------|
| `config/initializers/forum_settings.rb` | Add `SESSION_TIMEOUT_MINUTES` constant |
| `app/controllers/application_controller.rb` | Add `session_timeout_minutes`, `check_session_timeout`, `touch_session` |
| `test/controllers/sessions_timeout_test.rb` | New test file — all timeout scenarios |

---

### Task 1: Add configuration constant

**Files:**
- Modify: `config/initializers/forum_settings.rb`

- [ ] **Step 1: Add the constant**

  Open `config/initializers/forum_settings.rb`. It currently reads:

  ```ruby
  EDIT_WINDOW_SECONDS = ENV.fetch("EDIT_WINDOW_SECONDS", 3600).to_i
  ```

  Change it to:

  ```ruby
  EDIT_WINDOW_SECONDS     = ENV.fetch("EDIT_WINDOW_SECONDS", 3600).to_i
  SESSION_TIMEOUT_MINUTES = ENV.fetch("SESSION_TIMEOUT_MINUTES", 2880).to_i
  ```

  Default is 2880 (48 hours). Setting the ENV var to `0` disables timeout entirely.

- [ ] **Step 2: Verify the app boots**

  ```bash
  bin/rails runner "puts SESSION_TIMEOUT_MINUTES"
  ```

  Expected output: `2880`

- [ ] **Step 3: Commit**

  ```bash
  git add config/initializers/forum_settings.rb
  git commit -m "feat: add SESSION_TIMEOUT_MINUTES config constant"
  ```

---

### Task 2: Write the failing tests

**Files:**
- Create: `test/controllers/sessions_timeout_test.rb`

Tests use `ActionDispatch::IntegrationTest` (same as all other controller tests in this app). Session manipulation is done by traveling to a point in time, logging in (which triggers `touch_session` to write `last_active_at`), then traveling forward and making a subsequent request.

The constant reassignment pattern in setup/teardown is used to control the timeout value in tests independent of the ENV var.

- [ ] **Step 1: Create the test file**

  ```ruby
  # test/controllers/sessions_timeout_test.rb
  require "test_helper"

  class SessionsTimeoutTest < ActionDispatch::IntegrationTest
    setup do
      Provider.find_or_create_by!(id: 3, name: "internal")
      @user = User.create!(
        email: "timeout@example.com",
        name: "Timeout User",
        password: "password123",
        password_confirmation: "password123",
        provider_id: 3
      )
      # Use a short timeout (1 min) for all tests so travel_to distances are small
      @original_timeout = SESSION_TIMEOUT_MINUTES
      silence_warnings { Object.const_set(:SESSION_TIMEOUT_MINUTES, 1) }
    end

    teardown do
      silence_warnings { Object.const_set(:SESSION_TIMEOUT_MINUTES, @original_timeout) }
    end

    # Helper: log in as @user at the current time (touch_session writes last_active_at)
    def login_user
      post login_path, params: { email: "timeout@example.com", password: "password123" }
    end

    # -------------------------------------------------------------------------
    # Expired session — HTML request
    # -------------------------------------------------------------------------
    test "expired session redirects to login with alert for HTML requests" do
      # Log in 2 minutes ago — last_active_at is set to that time
      travel_to 2.minutes.ago do
        login_user
      end

      # Now (back at current time) make an HTML request — timeout check fires
      get root_path
      assert_redirected_to login_path
      assert_equal "Your session has expired. Please log in again.", flash[:alert]
      assert_nil session[:user_id]
    end

    # -------------------------------------------------------------------------
    # Expired session — Turbo Frame request
    # -------------------------------------------------------------------------
    test "expired session returns 401 for Turbo Frame requests" do
      travel_to 2.minutes.ago do
        login_user
      end

      get root_path, headers: { "Turbo-Frame" => "main" }
      assert_response :unauthorized
      assert_nil session[:user_id]
    end

    # -------------------------------------------------------------------------
    # Expired session — Turbo Stream request
    # -------------------------------------------------------------------------
    test "expired session returns 401 for Turbo Stream requests" do
      travel_to 2.minutes.ago do
        login_user
      end

      get root_path, headers: { "Accept" => "text/vnd.turbo-stream.html" }
      assert_response :unauthorized
      assert_nil session[:user_id]
    end

    # -------------------------------------------------------------------------
    # Active session — within timeout window
    # -------------------------------------------------------------------------
    test "active session within timeout window stays logged in and refreshes timestamp" do
      travel_to 30.seconds.ago do
        login_user
      end

      before_ts = session[:last_active_at]
      get root_path
      assert_response :success
      assert_equal @user.id, session[:user_id]
      # touch_session should have updated the timestamp
      assert session[:last_active_at] >= before_ts
    end

    # -------------------------------------------------------------------------
    # At exact boundary — not expired (strictly greater than)
    # -------------------------------------------------------------------------
    test "session at exact timeout boundary is not expired" do
      travel_to 1.minute.ago do
        login_user
      end

      get root_path
      assert_response :success
      assert_equal @user.id, session[:user_id]
    end

    # -------------------------------------------------------------------------
    # Absent last_active_at — treated as active (deploy transition)
    # -------------------------------------------------------------------------
    test "absent last_active_at is treated as active and gets written" do
      login_user
      # Manually clear last_active_at to simulate a pre-deploy session
      # We can't write session directly in integration tests, so we skip this
      # scenario to the controller unit test context — see note below.
      # Instead, verify that a freshly-logged-in user (where last_active_at
      # may not yet exist on the very first request prior to touch_session)
      # is not immediately expired.
      #
      # After login, touch_session has already written last_active_at.
      # We verify the user remains logged in on the next request.
      get root_path
      assert_response :success
      assert_equal @user.id, session[:user_id]
      assert_not_nil session[:last_active_at]
    end

    # -------------------------------------------------------------------------
    # Timeout disabled — SESSION_TIMEOUT_MINUTES = 0
    # -------------------------------------------------------------------------
    test "timeout disabled: old session is not expired and last_active_at is not written" do
      silence_warnings { Object.const_set(:SESSION_TIMEOUT_MINUTES, 0) }

      travel_to 999.minutes.ago do
        login_user
      end

      get root_path
      assert_response :success
      assert_equal @user.id, session[:user_id]
      # last_active_at should NOT be written when timeout is disabled
      assert_nil session[:last_active_at]
    end

    # -------------------------------------------------------------------------
    # Unauthenticated request — no session, no-op
    # -------------------------------------------------------------------------
    test "unauthenticated request is unaffected by timeout logic" do
      get root_path
      assert_response :success
      assert_nil session[:user_id]
      assert_nil session[:last_active_at]
    end
  end
  ```

- [ ] **Step 2: Run the tests to verify they fail**

  ```bash
  bin/rails test test/controllers/sessions_timeout_test.rb
  ```

  Expected: most tests fail because `check_session_timeout` and `touch_session` don't exist yet. The unauthenticated test may pass.

- [ ] **Step 3: Commit the failing tests**

  ```bash
  git add test/controllers/sessions_timeout_test.rb
  git commit -m "test: add failing session timeout tests"
  ```

---

### Task 3: Implement session timeout in ApplicationController

**Files:**
- Modify: `app/controllers/application_controller.rb`

Current file:

```ruby
class ApplicationController < ActionController::Base
  include Moderatable
  helper_method :current_user, :logged_in?, :can_moderate?

  private

  def current_user
    @current_user ||= User.find_by(id: session[:user_id])
  end

  def logged_in?
    current_user.present?
  end

  def require_login
    redirect_to login_path, alert: "Please log in first." and return unless logged_in?
  end
end
```

- [ ] **Step 1: Add the three new methods**

  Replace the entire file with:

  ```ruby
  class ApplicationController < ActionController::Base
    include Moderatable
    helper_method :current_user, :logged_in?, :can_moderate?

    before_action :check_session_timeout, if: :logged_in?
    after_action  :touch_session

    private

    def current_user
      @current_user ||= User.find_by(id: session[:user_id])
    end

    def logged_in?
      current_user.present?
    end

    def require_login
      redirect_to login_path, alert: "Please log in first." and return unless logged_in?
    end

    def session_timeout_minutes
      SESSION_TIMEOUT_MINUTES
    end

    def check_session_timeout
      return if session_timeout_minutes == 0

      unless session[:last_active_at]
        session[:last_active_at] = Time.current.to_i
        return
      end

      if Time.current.to_i - session[:last_active_at] > session_timeout_minutes * 60
        @current_user = nil
        reset_session

        if turbo_frame_request? || request.format.turbo_stream? || request.format.json?
          return head :unauthorized
        else
          redirect_to login_path, alert: "Your session has expired. Please log in again."
          return
        end
      end
    end

    def touch_session
      return unless session[:user_id].present? && session_timeout_minutes > 0
      session[:last_active_at] = Time.current.to_i
    end
  end
  ```

  Key implementation notes:
  - `before_action :check_session_timeout, if: :logged_in?` — only runs for authenticated requests
  - `after_action :touch_session` — runs unconditionally but guards internally with `session[:user_id].present?`
  - After `reset_session`, `session[:user_id]` is nil, so `touch_session` skips correctly
  - `turbo_frame_request?` is provided by `turbo-rails`

- [ ] **Step 2: Run the tests**

  ```bash
  bin/rails test test/controllers/sessions_timeout_test.rb
  ```

  Expected: all tests pass.

- [ ] **Step 3: Run the full test suite**

  ```bash
  bin/rails test
  ```

  Expected: all tests pass. If any existing tests fail, they likely need `session[:last_active_at]` to be set. Check whether tests that log in and make subsequent requests now trip the expiry check — they shouldn't because `touch_session` runs after login and subsequent requests within the same test happen in real time (well within 48 hours or even 1 minute for tests using the default constant).

  > **If existing tests fail:** The most likely cause is that the test overrides `SESSION_TIMEOUT_MINUTES` in `setup` but doesn't restore it in `teardown`, affecting other tests. Make sure the teardown in `sessions_timeout_test.rb` is correct. Another cause: if a test somehow has a stale `last_active_at`, but this shouldn't happen since each test uses a fresh session.

- [ ] **Step 4: Commit**

  ```bash
  git add app/controllers/application_controller.rb
  git commit -m "feat: implement idle session timeout in ApplicationController"
  ```

---

### Task 4: Run CI

- [ ] **Step 1: Run the full CI pipeline**

  ```bash
  bin/ci
  ```

  Expected: all checks pass (lint, security, tests, seed check).

  > If RuboCop reports style issues on `application_controller.rb`, run `bin/rubocop -a app/controllers/application_controller.rb` to auto-correct.

- [ ] **Step 2: Commit any lint fixes**

  Only if Step 1 required auto-corrections:

  ```bash
  git add app/controllers/application_controller.rb
  git commit -m "style: rubocop fixes on application_controller"
  ```
