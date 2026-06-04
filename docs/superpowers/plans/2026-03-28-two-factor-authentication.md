# Two-Factor Authentication (TOTP) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Allow users to protect their account with a TOTP authenticator app (Google Authenticator, Authy, etc.), with backup codes for account recovery.

**Architecture:** `totp_secret` is stored as an encrypted column on `users`. A `BackupCode` model holds bcrypt-hashed single-use codes. `SessionsController#create` redirects to `TwoFactorController#verify` before completing login when `totp_secret` is present. The login throttle (keyed by IP) covers both the password step and the TOTP step. `ApplicationController` session-timeout logic is extended to handle the intermediate `session[:awaiting_2fa]` state.

**Tech Stack:** Rails 8.1, `rotp` gem (TOTP), `rqrcode` gem (QR codes), Rails Active Record Encryption (`encrypts`), bcrypt (backup codes), `LoginThrottle` service, Minitest.

**Prerequisite:** The email verification plan (`2026-03-28-email-verification.md`) must be merged first — this plan assumes `email_verified_at` exists on users.

---

## File Map

| Action | Path |
|--------|------|
| Modify | `Gemfile` |
| Create | `db/migrate/20260330000001_add_totp_secret_to_users.rb` |
| Create | `db/migrate/20260330000002_create_backup_codes.rb` |
| Create | `app/models/backup_code.rb` |
| Modify | `app/models/user.rb` |
| Create | `app/controllers/two_factor_controller.rb` |
| Modify | `app/controllers/sessions_controller.rb` |
| Modify | `app/controllers/application_controller.rb` |
| Modify | `config/routes.rb` |
| Create | `app/views/two_factor/setup.html.erb` |
| Create | `app/views/two_factor/verify.html.erb` |
| Create | `app/views/two_factor/backup_codes.html.erb` |
| Modify | `app/views/users/edit.html.erb` |
| Create | `test/models/backup_code_test.rb` |
| Create | `test/controllers/two_factor_controller_test.rb` |
| Modify | `test/controllers/sessions_controller_test.rb` |

---

## Task 1: Add gems

**Files:**
- Modify: `Gemfile`

- [ ] **Step 1: Add rotp and rqrcode to Gemfile**

In `Gemfile`, after the `gem "bcrypt"` line, add:

```ruby
gem "rotp"
gem "rqrcode"
```

- [ ] **Step 2: Install**

```bash
bundle install
```

Expected: both gems install successfully.

- [ ] **Step 3: Commit**

```bash
git add Gemfile Gemfile.lock
git commit -m "feat: add rotp and rqrcode gems for TOTP 2FA"
```

---

## Task 2: Migrations

**Files:**
- Create: `db/migrate/20260330000001_add_totp_secret_to_users.rb`
- Create: `db/migrate/20260330000002_create_backup_codes.rb`

- [ ] **Step 1: Write migration for `totp_secret` on users**

```ruby
# db/migrate/20260330000001_add_totp_secret_to_users.rb
class AddTotpSecretToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :totp_secret, :string
  end
end
```

- [ ] **Step 2: Write migration for `backup_codes` table**

```ruby
# db/migrate/20260330000002_create_backup_codes.rb
class CreateBackupCodes < ActiveRecord::Migration[8.1]
  def change
    create_table :backup_codes do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.string     :digest, null: false
      t.datetime   :used_at
      t.datetime   :created_at, null: false
    end

    add_index :backup_codes, [ :user_id, :digest ], unique: true
  end
end
```

- [ ] **Step 3: Run migrations**

```bash
bin/rails db:migrate
```

Expected: both migrations apply, `db/structure.sql` updated.

- [ ] **Step 4: Commit**

```bash
git add db/migrate/20260330000001_add_totp_secret_to_users.rb \
        db/migrate/20260330000002_create_backup_codes.rb \
        db/structure.sql
git commit -m "feat: add totp_secret to users and create backup_codes table"
```

---

## Task 3: BackupCode model and User associations

**Files:**
- Create: `app/models/backup_code.rb`
- Modify: `app/models/user.rb`
- Create: `test/models/backup_code_test.rb`

- [ ] **Step 1: Write failing tests**

```ruby
# test/models/backup_code_test.rb
require "test_helper"

class BackupCodeTest < ActiveSupport::TestCase
  setup do
    Provider.find_or_create_by!(id: Provider::INTERNAL, name: "internal")
    @user = User.create!(
      email: "bc@example.com", name: "BC User",
      password: "password123", password_confirmation: "password123",
      provider_id: Provider::INTERNAL,
      email_verified_at: Time.current
    )
  end

  test "generate_for creates 8 backup codes for the user" do
    plaintext = BackupCode.generate_for(@user)
    assert_equal 8, plaintext.length
    assert_equal 8, @user.backup_codes.count
  end

  test "generate_for returns plaintext codes that are not stored in plaintext" do
    plaintext = BackupCode.generate_for(@user)
    digests = @user.backup_codes.pluck(:digest)
    plaintext.each do |code|
      assert_none digests, code
    end
  end

  test "consume_for returns true and marks code used when a valid code is submitted" do
    plaintext = BackupCode.generate_for(@user)
    assert BackupCode.consume_for(@user, plaintext.first)
    used = @user.backup_codes.find { |bc| BCrypt::Password.new(bc.digest) == plaintext.first }
    assert_not_nil used&.used_at
  end

  test "consume_for returns false for an invalid code" do
    BackupCode.generate_for(@user)
    assert_not BackupCode.consume_for(@user, "invalid-code-000")
  end

  test "consume_for returns false when code has already been used" do
    plaintext = BackupCode.generate_for(@user)
    BackupCode.consume_for(@user, plaintext.first)
    assert_not BackupCode.consume_for(@user, plaintext.first)
  end

  test "unused scope excludes used codes" do
    BackupCode.generate_for(@user)
    code = @user.backup_codes.first
    code.update!(used_at: Time.current)
    assert_equal 7, @user.backup_codes.unused.count
  end
end
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
bin/rails test test/models/backup_code_test.rb
```

Expected: `BackupCode` constant undefined.

- [ ] **Step 3: Write the BackupCode model**

```ruby
# app/models/backup_code.rb
class BackupCode < ApplicationRecord
  belongs_to :user

  scope :unused, -> { where(used_at: nil) }

  def self.generate_for(user)
    plaintext_codes = Array.new(8) { SecureRandom.alphanumeric(10) }
    plaintext_codes.each do |code|
      user.backup_codes.create!(digest: BCrypt::Password.create(code))
    end
    plaintext_codes
  end

  def self.consume_for(user, submitted_code)
    user.backup_codes.unused.find_each do |backup_code|
      next unless BCrypt::Password.new(backup_code.digest) == submitted_code

      BackupCode.transaction do
        locked = BackupCode.lock.find(backup_code.id)
        return false if locked.used_at.present?

        locked.update!(used_at: Time.current)
      end
      return true
    end
    false
  end
end
```

- [ ] **Step 4: Add associations and helpers to User**

In `app/models/user.rb`, add after `has_one :email_verification, dependent: :destroy`:

```ruby
has_many :backup_codes, dependent: :destroy
encrypts :totp_secret
```

Add this instance method in the public section (after the existing `mention_handle` method):

```ruby
def totp_enabled?
  totp_secret.present?
end
```

- [ ] **Step 5: Run tests to confirm they pass**

```bash
bin/rails test test/models/backup_code_test.rb
```

Expected: 6 tests, 0 failures.

- [ ] **Step 6: Run full suite**

```bash
bin/rails test
```

Expected: 0 failures.

- [ ] **Step 7: Commit**

```bash
git add app/models/backup_code.rb app/models/user.rb \
        test/models/backup_code_test.rb
git commit -m "feat: add BackupCode model and User#totp_enabled? with encrypted totp_secret"
```

---

## Task 4: TwoFactorController setup flow (enrollment)

**Files:**
- Create: `app/controllers/two_factor_controller.rb`
- Create: `app/views/two_factor/setup.html.erb`
- Create: `app/views/two_factor/backup_codes.html.erb`
- Modify: `config/routes.rb`
- Create: `test/controllers/two_factor_controller_test.rb`

- [ ] **Step 1: Add routes**

In `config/routes.rb`, after the `resources :password_resets` line, add:

```ruby
resource :two_factor, only: [:destroy] do
  get  :setup,        action: :setup
  post :setup,        action: :confirm_setup
  get  :verify
  post :verify,       action: :confirm_verify
  post :backup_codes, action: :regenerate_backup_codes
end
```

This provides helpers: `setup_two_factor_path`, `confirm_setup_two_factor_path` (via `post :setup`), `verify_two_factor_path`, `confirm_verify_two_factor_path` (via `post :verify`), `backup_codes_two_factor_path`, `two_factor_path` (for DELETE).

- [ ] **Step 2: Write failing setup tests**

```ruby
# test/controllers/two_factor_controller_test.rb
require "test_helper"

class TwoFactorControllerTest < ActionDispatch::IntegrationTest
  setup do
    Provider.find_or_create_by!(id: Provider::INTERNAL, name: "internal")
    @user = User.create!(
      email: "2fa@example.com", name: "2FA User",
      password: "password123", password_confirmation: "password123",
      provider_id: Provider::INTERNAL,
      email_verified_at: Time.current
    )
    # Log in
    post login_path, params: { email: @user.email, password: "password123" }
  end

  teardown { Rails.cache.clear }

  # ─── setup ──────────────────────────────────────────────────────────────────

  test "GET /two_factor/setup renders QR code page" do
    get setup_two_factor_path
    assert_response :success
    assert_select "form"
  end

  test "POST /two_factor/setup with invalid code re-renders setup with error" do
    get setup_two_factor_path  # seeds session[:pending_totp_secret]
    post setup_two_factor_path, params: { code: "000000" }
    assert_response :unprocessable_entity
  end

  test "POST /two_factor/setup with valid code saves totp_secret and renders backup codes" do
    get setup_two_factor_path
    secret = session[:pending_totp_secret]
    totp = ROTP::TOTP.new(secret)
    valid_code = totp.now

    post setup_two_factor_path, params: { code: valid_code }

    assert_response :success
    assert_template :backup_codes
    @user.reload
    assert @user.totp_enabled?
    assert_equal 8, @user.backup_codes.count
    assert_nil session[:pending_totp_secret]
  end

  test "GET /two_factor/setup requires login" do
    delete logout_path
    get setup_two_factor_path
    assert_redirected_to login_path
  end
end
```

- [ ] **Step 3: Run tests to confirm they fail**

```bash
bin/rails test test/controllers/two_factor_controller_test.rb \
  -n "/setup/"
```

Expected: routing error or uninitialized constant.

- [ ] **Step 4: Write the controller (setup actions only for now)**

```ruby
# app/controllers/two_factor_controller.rb
class TwoFactorController < ApplicationController
  before_action :require_login, except: [:verify, :confirm_verify]

  def setup
    @secret = session[:pending_totp_secret] ||= ROTP::Base32.random
    @qr_svg = build_qr_svg(@secret)
  end

  def confirm_setup
    secret = session[:pending_totp_secret]
    redirect_to setup_two_factor_path and return unless secret

    totp = ROTP::TOTP.new(secret)
    if totp.verify(params[:code].to_s.strip, drift_behind: 30, drift_ahead: 30)
      current_user.update!(totp_secret: secret)
      session.delete(:pending_totp_secret)
      @backup_codes = BackupCode.generate_for(current_user)
      render :backup_codes
    else
      @secret = secret
      @qr_svg = build_qr_svg(@secret)
      flash.now[:alert] = "Invalid code. Please try again."
      render :setup, status: :unprocessable_entity
    end
  end

  def verify
    redirect_to root_path and return unless session[:awaiting_2fa]
  end

  def confirm_verify
    redirect_to root_path and return unless session[:awaiting_2fa]

    throttle = LoginThrottle.new(request.remote_ip)
    if throttle.throttled?
      flash.now[:alert] = "Too many failed attempts. Please wait before trying again."
      render :verify, status: :too_many_requests
      return
    end

    user = User.find_by(id: session[:awaiting_2fa])
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
      throttle.clear!
      reset_session
      session[:user_id] = user.id
      redirect_to root_path, notice: "Welcome back, #{user.name}!"
    else
      throttle.record_failure!
      flash.now[:alert] = "Invalid code."
      render :verify, status: :unprocessable_entity
    end
  end

  def destroy
    unless current_user.authenticate(params[:current_password].to_s)
      redirect_to edit_user_path(current_user), alert: "Incorrect password."
      return
    end

    current_user.update!(totp_secret: nil)
    current_user.backup_codes.destroy_all
    redirect_to edit_user_path(current_user), notice: "Two-factor authentication disabled."
  end

  def regenerate_backup_codes
    unless current_user.authenticate(params[:current_password].to_s)
      redirect_to edit_user_path(current_user), alert: "Incorrect password."
      return
    end

    current_user.backup_codes.destroy_all
    @backup_codes = BackupCode.generate_for(current_user)
    render :backup_codes
  end

  private

  def build_qr_svg(secret)
    totp = ROTP::TOTP.new(secret, issuer: "Forum")
    uri  = totp.provisioning_uri(current_user.email)
    RQRCode::QRCode.new(uri).as_svg(module_size: 4)
  end
end
```

- [ ] **Step 5: Create setup view**

```erb
<%# app/views/two_factor/setup.html.erb %>
<div class="max-w-md mx-auto mt-8 px-4 pb-12">
  <div class="bg-white dark:bg-stone-800 border border-stone-200 dark:border-stone-700 rounded-xl p-6">
    <h1 class="text-xl font-bold mb-2 dark:text-stone-100">Enable two-factor authentication</h1>
    <p class="text-sm text-stone-600 dark:text-stone-400 mb-6">
      Scan the QR code with your authenticator app (Google Authenticator, Authy, etc.),
      then enter the 6-digit code to confirm.
    </p>

    <div class="flex justify-center mb-4">
      <%= raw @qr_svg %>
    </div>

    <p class="text-xs text-center text-stone-500 dark:text-stone-400 mb-6 break-all">
      Can't scan? Enter this key manually: <strong><%= @secret %></strong>
    </p>

    <%= form_with url: setup_two_factor_path, method: :post, class: "space-y-4" do |f| %>
      <div>
        <%= f.label :code, "6-digit code", class: "block text-sm font-medium text-stone-700 dark:text-stone-300 mb-1" %>
        <%= f.text_field :code, autocomplete: "one-time-code", inputmode: "numeric",
              maxlength: 6, placeholder: "000000",
              class: "w-full border border-stone-300 dark:border-stone-600 rounded-md px-3 py-2 focus:outline-none focus:ring-2 focus:ring-teal-500 bg-white dark:bg-stone-700 text-stone-900 dark:text-stone-100 tracking-widest text-center text-lg" %>
      </div>
      <%= f.submit "Enable 2FA",
            class: "w-full bg-teal-700 text-white py-2 px-4 rounded-md hover:bg-teal-600 font-semibold" %>
    <% end %>
  </div>
</div>
```

- [ ] **Step 6: Create backup codes view**

```erb
<%# app/views/two_factor/backup_codes.html.erb %>
<div class="max-w-md mx-auto mt-8 px-4 pb-12">
  <div class="bg-white dark:bg-stone-800 border border-stone-200 dark:border-stone-700 rounded-xl p-6">
    <h1 class="text-xl font-bold mb-2 dark:text-stone-100">Save your backup codes</h1>
    <p class="text-sm text-stone-600 dark:text-stone-400 mb-4">
      These codes can be used to access your account if you lose your authenticator.
      <strong>Save them somewhere safe — they won't be shown again.</strong>
    </p>

    <div class="bg-stone-100 dark:bg-stone-900 rounded-lg p-4 font-mono text-sm grid grid-cols-2 gap-2 mb-6">
      <% @backup_codes.each do |code| %>
        <span class="text-center tracking-wider dark:text-stone-200"><%= code %></span>
      <% end %>
    </div>

    <%= link_to "Done — go to my profile", edit_user_path(current_user),
          class: "block text-center bg-teal-700 text-white py-2 px-4 rounded-md hover:bg-teal-600 font-semibold" %>
  </div>
</div>
```

- [ ] **Step 7: Run setup tests to confirm they pass**

```bash
bin/rails test test/controllers/two_factor_controller_test.rb -n "/setup/"
```

Expected: 4 tests, 0 failures.

- [ ] **Step 8: Commit**

```bash
git add app/controllers/two_factor_controller.rb \
        app/views/two_factor/setup.html.erb \
        app/views/two_factor/backup_codes.html.erb \
        config/routes.rb \
        test/controllers/two_factor_controller_test.rb
git commit -m "feat: add TwoFactorController setup/confirm_setup with QR code and backup codes"
```

---

## Task 5: Login flow — intercept for TOTP, verify action and tests

**Files:**
- Modify: `app/controllers/sessions_controller.rb`
- Create: `app/views/two_factor/verify.html.erb`
- Modify: `test/controllers/two_factor_controller_test.rb` (add verify tests)

- [ ] **Step 1: Write failing verify tests**

Append to `test/controllers/two_factor_controller_test.rb`:

```ruby
# ─── login flow with 2FA ─────────────────────────────────────────────────────

test "login redirects to verify page when user has 2FA enabled" do
  secret = ROTP::Base32.random
  @user.update!(totp_secret: secret)

  delete logout_path
  post login_path, params: { email: @user.email, password: "password123" }

  assert_redirected_to verify_two_factor_path
  assert_nil session[:user_id]
  assert_equal @user.id, session[:awaiting_2fa]
end

test "POST /two_factor/verify with valid TOTP code completes login" do
  secret = ROTP::Base32.random
  @user.update!(totp_secret: secret)
  delete logout_path
  post login_path, params: { email: @user.email, password: "password123" }

  valid_code = ROTP::TOTP.new(secret).now
  post confirm_verify_two_factor_path, params: { code: valid_code }

  assert_redirected_to root_path
  assert_equal @user.id, session[:user_id]
  assert_nil session[:awaiting_2fa]
end

test "POST /two_factor/verify with invalid TOTP code increments throttle and re-renders" do
  secret = ROTP::Base32.random
  @user.update!(totp_secret: secret)
  delete logout_path
  post login_path, params: { email: @user.email, password: "password123" }

  post confirm_verify_two_factor_path, params: { code: "000000" }

  assert_response :unprocessable_entity
  assert_nil session[:user_id]
end

test "POST /two_factor/verify with valid backup code completes login and marks code used" do
  secret = ROTP::Base32.random
  @user.update!(totp_secret: secret)
  delete logout_path
  plaintext = BackupCode.generate_for(@user)
  post login_path, params: { email: @user.email, password: "password123" }

  post confirm_verify_two_factor_path, params: { code: plaintext.first }

  assert_redirected_to root_path
  assert_equal @user.id, session[:user_id]
  used = @user.backup_codes.find { |bc| BCrypt::Password.new(bc.digest) == plaintext.first }
  assert_not_nil used&.used_at
end

test "POST /two_factor/verify with already-used backup code is rejected" do
  secret = ROTP::Base32.random
  @user.update!(totp_secret: secret)
  delete logout_path
  plaintext = BackupCode.generate_for(@user)
  post login_path, params: { email: @user.email, password: "password123" }
  post confirm_verify_two_factor_path, params: { code: plaintext.first }

  # Start a new 2FA challenge
  delete logout_path
  post login_path, params: { email: @user.email, password: "password123" }
  post confirm_verify_two_factor_path, params: { code: plaintext.first }

  assert_response :unprocessable_entity
end

test "POST /two_factor/verify when throttled returns 429" do
  secret = ROTP::Base32.random
  @user.update!(totp_secret: secret)
  delete logout_path
  post login_path, params: { email: @user.email, password: "password123" }

  # Exhaust throttle
  5.times { post confirm_verify_two_factor_path, params: { code: "000000" } }
  post confirm_verify_two_factor_path, params: { code: "000000" }

  assert_response :too_many_requests
end
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
bin/rails test test/controllers/two_factor_controller_test.rb \
  -n "/login redirects|verify/"
```

Expected: login still completes without 2FA redirect.

- [ ] **Step 3: Update SessionsController#create to intercept for 2FA**

Replace the entire `create` action in `app/controllers/sessions_controller.rb`:

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
    if user.totp_enabled?
      reset_session
      session[:awaiting_2fa] = user.id
      redirect_to verify_two_factor_path
    else
      throttle.clear!
      reset_session
      session[:user_id] = user.id
      redirect_to root_path, notice: "Welcome back, #{user.name}!"
    end
  else
    throttle.record_failure!
    flash.now[:alert] = "Invalid email or password."
    render :new, status: :unprocessable_entity
  end
end
```

Also update `destroy` to use `reset_session` (clears `awaiting_2fa` on logout):

```ruby
def destroy
  reset_session
  redirect_to root_path, notice: "Logged out."
end
```

- [ ] **Step 4: Create verify view**

```erb
<%# app/views/two_factor/verify.html.erb %>
<div class="max-w-md mx-auto mt-12 p-6 bg-white dark:bg-stone-800 dark:border dark:border-stone-700 rounded-lg shadow">
  <h1 class="text-2xl font-bold mb-2 dark:text-stone-100">Two-factor authentication</h1>
  <p class="text-sm text-stone-600 dark:text-stone-400 mb-6">
    Enter the 6-digit code from your authenticator app, or one of your backup codes.
  </p>

  <%= form_with url: confirm_verify_two_factor_path, method: :post, class: "space-y-4" do |f| %>
    <div>
      <%= f.label :code, "Authentication code", class: "block text-sm font-medium text-stone-700 dark:text-stone-300 mb-1" %>
      <%= f.text_field :code, autocomplete: "one-time-code", inputmode: "numeric",
            autofocus: true, placeholder: "000000",
            class: "w-full border border-stone-300 dark:border-stone-600 rounded-md px-3 py-2 focus:outline-none focus:ring-2 focus:ring-teal-500 bg-white dark:bg-stone-700 text-stone-900 dark:text-stone-100 tracking-widest text-center text-lg" %>
    </div>
    <%= f.submit "Verify",
          class: "w-full bg-teal-700 text-white py-2 px-4 rounded-md hover:bg-teal-600 font-semibold" %>
  <% end %>

  <p class="mt-4 text-center text-sm text-stone-500 dark:text-stone-400">
    <%= link_to "Cancel and return to login", login_path, class: "text-teal-600 hover:underline" %>
  </p>
</div>
```

- [ ] **Step 5: Run verify tests to confirm they pass**

```bash
bin/rails test test/controllers/two_factor_controller_test.rb
```

Expected: all tests pass.

- [ ] **Step 6: Run full suite**

```bash
bin/rails test
```

Expected: 0 failures.

- [ ] **Step 7: Commit**

```bash
git add app/controllers/sessions_controller.rb \
        app/views/two_factor/verify.html.erb \
        test/controllers/two_factor_controller_test.rb
git commit -m "feat: intercept login for TOTP verification, add TwoFactorController verify flow"
```

---

## Task 6: Disable 2FA and regenerate backup codes

Tests for these actions are already in the controller (called via `DELETE /two_factor` and `POST /two_factor/backup_codes`). Add dedicated test cases now.

**Files:**
- Modify: `test/controllers/two_factor_controller_test.rb`

- [ ] **Step 1: Write disable and regenerate tests**

Append to `test/controllers/two_factor_controller_test.rb`:

```ruby
# ─── disable 2FA ────────────────────────────────────────────────────────────

test "DELETE /two_factor with correct password disables 2FA and destroys backup codes" do
  secret = ROTP::Base32.random
  @user.update!(totp_secret: secret)
  BackupCode.generate_for(@user)

  delete two_factor_path, params: { current_password: "password123" }

  assert_redirected_to edit_user_path(@user)
  assert flash[:notice].present?
  @user.reload
  assert_not @user.totp_enabled?
  assert_equal 0, @user.backup_codes.count
end

test "DELETE /two_factor with wrong password redirects with alert and leaves 2FA enabled" do
  secret = ROTP::Base32.random
  @user.update!(totp_secret: secret)

  delete two_factor_path, params: { current_password: "wrongpassword" }

  assert_redirected_to edit_user_path(@user)
  assert flash[:alert].present?
  assert @user.reload.totp_enabled?
end

# ─── regenerate backup codes ─────────────────────────────────────────────────

test "POST /two_factor/backup_codes with correct password replaces backup codes" do
  secret = ROTP::Base32.random
  @user.update!(totp_secret: secret)
  old_codes = BackupCode.generate_for(@user)
  old_digests = @user.backup_codes.pluck(:digest)

  post backup_codes_two_factor_path, params: { current_password: "password123" }

  assert_response :success
  assert_template :backup_codes
  @user.reload
  assert_equal 8, @user.backup_codes.count
  assert_not_equal old_digests.sort, @user.backup_codes.pluck(:digest).sort
end

test "POST /two_factor/backup_codes with wrong password redirects with alert" do
  secret = ROTP::Base32.random
  @user.update!(totp_secret: secret)
  BackupCode.generate_for(@user)

  post backup_codes_two_factor_path, params: { current_password: "wrongpassword" }

  assert_redirected_to edit_user_path(@user)
  assert flash[:alert].present?
end
```

- [ ] **Step 2: Run tests to confirm they pass (controller already written in Task 4)**

```bash
bin/rails test test/controllers/two_factor_controller_test.rb \
  -n "/disable|regenerate/"
```

Expected: 4 tests, 0 failures.

- [ ] **Step 3: Commit**

```bash
git add test/controllers/two_factor_controller_test.rb
git commit -m "test: add disable 2FA and regenerate backup code tests"
```

---

## Task 7: Session timeout for `awaiting_2fa` state

**Files:**
- Modify: `app/controllers/application_controller.rb`

- [ ] **Step 1: Write failing tests**

Add to `test/controllers/sessions_controller_test.rb` (create it if it doesn't exist):

```ruby
# test/controllers/sessions_controller_test.rb
require "test_helper"

class SessionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    Provider.find_or_create_by!(id: Provider::INTERNAL, name: "internal")
    @user = User.create!(
      email: "sess@example.com", name: "Sess User",
      password: "password123", password_confirmation: "password123",
      provider_id: Provider::INTERNAL,
      email_verified_at: Time.current
    )
  end

  teardown { Rails.cache.clear }

  test "awaiting_2fa session is timed out after SESSION_TIMEOUT_MINUTES" do
    skip if SESSION_TIMEOUT_MINUTES == 0

    secret = ROTP::Base32.random
    @user.update!(totp_secret: secret)

    post login_path, params: { email: @user.email, password: "password123" }
    assert_equal @user.id, session[:awaiting_2fa]

    travel (SESSION_TIMEOUT_MINUTES + 1).minutes do
      get verify_two_factor_path
      assert_redirected_to login_path
      assert flash[:alert].present?
      assert_nil session[:awaiting_2fa]
    end
  end

  test "awaiting_2fa session touch_session updates last_active_at" do
    skip if SESSION_TIMEOUT_MINUTES == 0

    secret = ROTP::Base32.random
    @user.update!(totp_secret: secret)

    post login_path, params: { email: @user.email, password: "password123" }
    assert_not_nil session[:last_active_at]
  end
end
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
bin/rails test test/controllers/sessions_controller_test.rb
```

Expected: the timeout test fails — `awaiting_2fa` session is not timed out.

- [ ] **Step 3: Update ApplicationController**

Replace the `check_session_timeout` and `touch_session` methods in `app/controllers/application_controller.rb`:

```ruby
before_action :check_session_timeout, if: -> { logged_in? || session[:awaiting_2fa].present? }
after_action  :touch_session

# ...inside private:

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

def touch_session
  active = session[:user_id].present? || session[:awaiting_2fa].present?
  return unless active && session_timeout_minutes > 0
  session[:last_active_at] = Time.current.to_i
end
```

Also update the `before_action` at the top of the class — replace:

```ruby
before_action :check_session_timeout, if: :logged_in?
```

with:

```ruby
before_action :check_session_timeout, if: -> { logged_in? || session[:awaiting_2fa].present? }
```

- [ ] **Step 4: Run tests to confirm they pass**

```bash
bin/rails test test/controllers/sessions_controller_test.rb
```

Expected: all tests pass.

- [ ] **Step 5: Run full suite**

```bash
bin/rails test
```

Expected: 0 failures.

- [ ] **Step 6: Commit**

```bash
git add app/controllers/application_controller.rb \
        test/controllers/sessions_controller_test.rb
git commit -m "feat: extend session timeout to cover awaiting_2fa state"
```

---

## Task 8: Edit profile 2FA section

**Files:**
- Modify: `app/views/users/edit.html.erb`

- [ ] **Step 1: Add 2FA section to edit profile view**

In `app/views/users/edit.html.erb`, after the closing `<% end %>` of the `if @profile_user.internal?` password section (before `<%= f.submit`), add a new section outside the form. Place it after the closing `<% end %>` of the form block:

```erb
<%# Two-factor authentication section — only for internal (password-based) accounts %>
<% if @profile_user.internal? %>
  <div class="bg-white dark:bg-stone-800 border border-stone-200 dark:border-stone-700 rounded-xl p-6 mt-6">
    <h2 class="text-lg font-bold mb-1 dark:text-stone-100">Two-factor authentication</h2>

    <% if @profile_user.totp_enabled? %>
      <p class="text-sm text-stone-600 dark:text-stone-400 mb-4">
        2FA is <strong class="text-green-600 dark:text-green-400">enabled</strong> on your account.
      </p>

      <div class="flex flex-col gap-3 sm:flex-row">
        <%= form_with url: backup_codes_two_factor_path, method: :post, class: "flex gap-2 items-end" do |f| %>
          <%= f.password_field :current_password, placeholder: "Current password",
                class: "border border-stone-300 dark:border-stone-600 rounded-md px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-teal-500 bg-white dark:bg-stone-700 text-stone-900 dark:text-stone-100" %>
          <%= f.submit "Regenerate backup codes",
                class: "bg-stone-200 dark:bg-stone-700 text-stone-800 dark:text-stone-200 px-4 py-2 rounded-lg text-sm hover:bg-stone-300 dark:hover:bg-stone-600 font-medium cursor-pointer" %>
        <% end %>

        <%= form_with url: two_factor_path, method: :delete, class: "flex gap-2 items-end" do |f| %>
          <%= f.password_field :current_password, placeholder: "Current password",
                class: "border border-stone-300 dark:border-stone-600 rounded-md px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-teal-500 bg-white dark:bg-stone-700 text-stone-900 dark:text-stone-100" %>
          <%= f.submit "Disable 2FA",
                class: "bg-red-100 dark:bg-red-900/30 text-red-700 dark:text-red-400 px-4 py-2 rounded-lg text-sm hover:bg-red-200 dark:hover:bg-red-900/50 font-medium cursor-pointer",
                data: { turbo_confirm: "Are you sure? This will make your account less secure." } %>
        <% end %>
      </div>
    <% else %>
      <p class="text-sm text-stone-600 dark:text-stone-400 mb-4">
        Add an extra layer of security to your account with a TOTP authenticator app.
      </p>
      <%= link_to "Enable two-factor authentication", setup_two_factor_path,
            class: "inline-block bg-teal-700 text-white px-5 py-2 rounded-lg hover:bg-teal-600 font-semibold text-sm" %>
    <% end %>
  </div>
<% end %>
```

- [ ] **Step 2: Run full test suite**

```bash
bin/rails test
```

Expected: 0 failures.

- [ ] **Step 3: Commit**

```bash
git add app/views/users/edit.html.erb
git commit -m "feat: add 2FA management section to edit profile page"
```

---

## Task 9: Final CI check

- [ ] **Step 1: Run full CI pipeline**

```bash
./bin/ci
```

Expected: lint, security, and all tests pass.

- [ ] **Step 2: Fix any rubocop offenses, commit if needed**

```bash
./bin/rubocop -a
git add -A
git commit -m "fix: rubocop offenses from 2FA feature"
```
