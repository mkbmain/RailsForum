# Email Verification Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Require users to confirm their email address before they can create posts or replies.

**Architecture:** A new `EmailVerification` model (mirroring `PasswordReset`) holds a `has_secure_token` token and `last_sent_at` for cooldown. `UsersController#create` sends the email; OmniAuth signups auto-verify. A `VerifiedEmail` concern guards `PostsController` and `RepliesController` `create` actions. A resend endpoint handles re-delivery.

**Tech Stack:** Rails 8.1, PostgreSQL, `has_secure_token`, `UserMailer` (Resend), Minitest.

---

## File Map

| Action | Path |
|--------|------|
| Create | `db/migrate/20260329000001_add_email_verified_at_to_users.rb` |
| Create | `db/migrate/20260329000002_create_email_verifications.rb` |
| Create | `app/models/email_verification.rb` |
| Modify | `app/models/user.rb` |
| Modify | `app/mailers/user_mailer.rb` |
| Create | `app/views/user_mailer/verify_email.html.erb` |
| Create | `app/controllers/email_verifications_controller.rb` |
| Create | `app/controllers/concerns/verified_email.rb` |
| Modify | `app/controllers/posts_controller.rb` |
| Modify | `app/controllers/replies_controller.rb` |
| Modify | `app/controllers/users_controller.rb` |
| Modify | `app/controllers/omniauth_callbacks_controller.rb` |
| Modify | `app/views/layouts/application.html.erb` |
| Create | `app/views/email_verifications/resend.html.erb` |
| Modify | `config/routes.rb` |
| Create | `test/models/email_verification_test.rb` |
| Create | `test/controllers/email_verifications_controller_test.rb` |

---

## Task 1: Migrations

**Files:**
- Create: `db/migrate/20260329000001_add_email_verified_at_to_users.rb`
- Create: `db/migrate/20260329000002_create_email_verifications.rb`

- [ ] **Step 1: Write the migration for `email_verified_at` on users**

```ruby
# db/migrate/20260329000001_add_email_verified_at_to_users.rb
class AddEmailVerifiedAtToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :email_verified_at, :datetime
  end
end
```

- [ ] **Step 2: Write the migration for `email_verifications` table**

```ruby
# db/migrate/20260329000002_create_email_verifications.rb
class CreateEmailVerifications < ActiveRecord::Migration[8.1]
  def change
    create_table :email_verifications do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }, index: { unique: true }
      t.string     :token, null: false
      t.datetime   :created_at, null: false
      t.datetime   :last_sent_at
    end

    add_index :email_verifications, :token, unique: true
  end
end
```

- [ ] **Step 3: Run migrations**

```bash
bin/rails db:migrate
```

Expected: both migrations run with no errors, `db/structure.sql` updated.

- [ ] **Step 4: Commit**

```bash
git add db/migrate/20260329000001_add_email_verified_at_to_users.rb \
        db/migrate/20260329000002_create_email_verifications.rb \
        db/structure.sql
git commit -m "feat: add email_verified_at to users and create email_verifications table"
```

---

## Task 2: EmailVerification model

**Files:**
- Create: `app/models/email_verification.rb`
- Create: `test/models/email_verification_test.rb`

- [ ] **Step 1: Write failing tests**

```ruby
# test/models/email_verification_test.rb
require "test_helper"

class EmailVerificationTest < ActiveSupport::TestCase
  setup do
    Provider.find_or_create_by!(id: Provider::INTERNAL, name: "internal")
    @user = User.create!(
      email: "ev@example.com", name: "EV User",
      password: "password123", password_confirmation: "password123",
      provider_id: Provider::INTERNAL
    )
  end

  # expired?
  test "expired? returns false when 23 hours old" do
    ev = travel_to(23.hours.ago) { @user.create_email_verification!(last_sent_at: Time.current) }
    assert_not ev.expired?
  end

  test "expired? returns true when 25 hours old" do
    ev = travel_to(25.hours.ago) { @user.create_email_verification!(last_sent_at: Time.current) }
    assert ev.expired?
  end

  # on_cooldown?
  test "on_cooldown? returns false when last_sent_at is nil" do
    ev = @user.create_email_verification!(last_sent_at: nil)
    assert_not ev.on_cooldown?
  end

  test "on_cooldown? returns true when last_sent_at is 2 minutes ago" do
    ev = @user.create_email_verification!(last_sent_at: 2.minutes.ago)
    assert ev.on_cooldown?
  end

  test "on_cooldown? returns false when last_sent_at is 4 minutes ago" do
    ev = @user.create_email_verification!(last_sent_at: 4.minutes.ago)
    assert_not ev.on_cooldown?
  end
end
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
bin/rails test test/models/email_verification_test.rb
```

Expected: errors — `EmailVerification` constant undefined or `create_email_verification!` missing.

- [ ] **Step 3: Write the model**

```ruby
# app/models/email_verification.rb
class EmailVerification < ApplicationRecord
  belongs_to :user
  has_secure_token :token

  EXPIRY          = 24.hours
  RESEND_COOLDOWN = 3.minutes

  def expired?
    created_at < EXPIRY.ago
  end

  def on_cooldown?
    last_sent_at && last_sent_at >= RESEND_COOLDOWN.ago
  end
end
```

- [ ] **Step 4: Add association to User**

In `app/models/user.rb`, after `has_one :password_reset, dependent: :destroy`, add:

```ruby
has_one :email_verification, dependent: :destroy
```

- [ ] **Step 5: Run tests to confirm they pass**

```bash
bin/rails test test/models/email_verification_test.rb
```

Expected: 5 tests, 0 failures.

- [ ] **Step 6: Commit**

```bash
git add app/models/email_verification.rb app/models/user.rb \
        test/models/email_verification_test.rb
git commit -m "feat: add EmailVerification model with expired? and on_cooldown?"
```

---

## Task 3: UserMailer verify_email method and view

**Files:**
- Modify: `app/mailers/user_mailer.rb`
- Create: `app/views/user_mailer/verify_email.html.erb`

- [ ] **Step 1: Write failing mailer test**

Add to a new file `test/mailers/user_mailer_verify_email_test.rb`:

```ruby
# test/mailers/user_mailer_verify_email_test.rb
require "test_helper"

class UserMailerVerifyEmailTest < ActionMailer::TestCase
  setup do
    Provider.find_or_create_by!(id: Provider::INTERNAL, name: "internal")
    @user = User.create!(
      email: "verify@example.com", name: "Verify User",
      password: "password123", password_confirmation: "password123",
      provider_id: Provider::INTERNAL
    )
    @ev = @user.create_email_verification!(last_sent_at: Time.current)
  end

  test "verify_email sends to user email with correct subject" do
    mail = UserMailer.verify_email(@ev)
    assert_equal [@user.email], mail.to
    assert_equal "Verify your Forum email address", mail.subject
  end

  test "verify_email body contains token link" do
    mail = UserMailer.verify_email(@ev)
    assert_includes mail.body.encoded, @ev.token
  end
end
```

- [ ] **Step 2: Run test to confirm it fails**

```bash
bin/rails test test/mailers/user_mailer_verify_email_test.rb
```

Expected: `NoMethodError` — `UserMailer.verify_email` undefined.

- [ ] **Step 3: Add mailer method**

In `app/mailers/user_mailer.rb`, add:

```ruby
def verify_email(verification)
  @verification = verification
  @user = verification.user
  mail to: @user.email, subject: "Verify your Forum email address"
end
```

- [ ] **Step 4: Create the email view**

```erb
<%# app/views/user_mailer/verify_email.html.erb %>
<p>Hi <%= @user.name %>,</p>

<p>Thanks for signing up for Forum. Please verify your email address by clicking the link below:</p>

<p><%= link_to "Verify my email address", email_verification_url(@verification.token) %></p>

<p>This link expires in 24 hours.</p>

<p>If you didn't create a Forum account, you can safely ignore this email.</p>
```

- [ ] **Step 5: Run tests to confirm they pass**

```bash
bin/rails test test/mailers/user_mailer_verify_email_test.rb
```

Expected: 2 tests, 0 failures.

- [ ] **Step 6: Commit**

```bash
git add app/mailers/user_mailer.rb app/views/user_mailer/verify_email.html.erb \
        test/mailers/user_mailer_verify_email_test.rb
git commit -m "feat: add UserMailer#verify_email with view"
```

---

## Task 4: EmailVerificationsController, routes, and resend view

**Files:**
- Create: `app/controllers/email_verifications_controller.rb`
- Create: `app/views/email_verifications/resend.html.erb`
- Modify: `config/routes.rb`
- Create: `test/controllers/email_verifications_controller_test.rb`

- [ ] **Step 1: Add routes**

In `config/routes.rb`, after the `resources :password_resets` line, add:

```ruby
resources :email_verifications, only: [:show], param: :token do
  collection { post :resend }
end
```

- [ ] **Step 2: Write failing controller tests**

```ruby
# test/controllers/email_verifications_controller_test.rb
require "test_helper"

class EmailVerificationsControllerTest < ActionDispatch::IntegrationTest
  include ActionMailer::TestHelper

  setup do
    ActionMailer::Base.deliveries.clear
    Provider.find_or_create_by!(id: Provider::INTERNAL, name: "internal")
    @user = User.create!(
      email: "ev@example.com", name: "EV User",
      password: "password123", password_confirmation: "password123",
      provider_id: Provider::INTERNAL
    )
  end

  # ─── show (verify token) ────────────────────────────────────────────────────

  test "GET /email_verifications/:token verifies user and redirects to root" do
    ev = @user.create_email_verification!(last_sent_at: Time.current)
    get email_verification_path(ev.token)
    assert_redirected_to root_path
    assert flash[:notice].present?
    assert_not_nil @user.reload.email_verified_at
    assert_nil EmailVerification.find_by(id: ev.id)
  end

  test "GET /email_verifications/:token with unknown token redirects with alert" do
    get email_verification_path("nonexistent-token")
    assert_redirected_to root_path
    assert flash[:alert].present?
  end

  test "GET /email_verifications/:token with expired token redirects with alert" do
    ev = travel_to(25.hours.ago) { @user.create_email_verification!(last_sent_at: Time.current) }
    get email_verification_path(ev.token)
    assert_redirected_to root_path
    assert flash[:alert].present?
    assert_nil @user.reload.email_verified_at
  end

  test "GET /email_verifications/:token for already-verified user redirects benignly" do
    @user.update_column(:email_verified_at, Time.current)
    ev = @user.create_email_verification!(last_sent_at: Time.current)
    get email_verification_path(ev.token)
    assert_redirected_to root_path
    assert flash[:notice].present?
  end

  # ─── resend ─────────────────────────────────────────────────────────────────

  test "POST /email_verifications/resend when logged in creates token and sends email" do
    post login_path, params: { email: @user.email, password: "password123" }

    assert_emails 1 do
      post resend_email_verifications_path
    end
    assert_redirected_to root_path
    assert flash[:notice].present?
    assert_not_nil @user.reload.email_verification
  end

  test "POST /email_verifications/resend when on cooldown suppresses email" do
    post login_path, params: { email: @user.email, password: "password123" }
    @user.create_email_verification!(last_sent_at: 1.minute.ago)

    assert_emails 0 do
      post resend_email_verifications_path
    end
    assert_redirected_to root_path
  end

  test "POST /email_verifications/resend when not logged in redirects to login" do
    post resend_email_verifications_path
    assert_redirected_to login_path
  end
end
```

- [ ] **Step 3: Run tests to confirm they fail**

```bash
bin/rails test test/controllers/email_verifications_controller_test.rb
```

Expected: routing error or uninitialized constant.

- [ ] **Step 4: Write the controller**

```ruby
# app/controllers/email_verifications_controller.rb
class EmailVerificationsController < ApplicationController
  before_action :require_login, only: [:resend]

  def show
    ev = EmailVerification.find_by(token: params[:token])

    if ev.nil? || ev.expired?
      redirect_to root_path, alert: "That verification link is invalid or has expired."
      return
    end

    ev.user.update_column(:email_verified_at, Time.current)
    ev.destroy
    redirect_to root_path, notice: "Email verified. Thank you!"
  end

  def resend
    return if current_user.email_verified_at.present?

    ev = current_user.email_verification

    if ev&.on_cooldown?
      redirect_to root_path, notice: "Verification email already sent. Please check your inbox."
      return
    end

    ev&.destroy
    ev = current_user.create_email_verification!(last_sent_at: Time.current)
    UserMailer.verify_email(ev).deliver_later
    redirect_to root_path, notice: "Verification email sent. Please check your inbox."
  end
end
```

- [ ] **Step 5: Run tests to confirm they pass**

```bash
bin/rails test test/controllers/email_verifications_controller_test.rb
```

Expected: 7 tests, 0 failures.

- [ ] **Step 6: Create resend page (used by the banner link)**

```erb
<%# app/views/email_verifications/resend.html.erb %>
<div class="max-w-md mx-auto mt-12 p-6 bg-white dark:bg-stone-800 dark:border dark:border-stone-700 rounded-lg shadow text-center">
  <h1 class="text-xl font-bold mb-3 dark:text-stone-100">Verify your email</h1>
  <p class="text-sm text-stone-600 dark:text-stone-400 mb-6">
    We sent a verification link to <strong><%= current_user.email %></strong>.
    Click the link in that email to activate posting.
  </p>
  <%= button_to "Resend verification email", resend_email_verifications_path,
        method: :post,
        class: "bg-teal-700 text-white px-5 py-2 rounded-lg hover:bg-teal-600 font-semibold" %>
</div>
```

- [ ] **Step 7: Commit**

```bash
git add app/controllers/email_verifications_controller.rb \
        app/views/email_verifications/resend.html.erb \
        config/routes.rb \
        test/controllers/email_verifications_controller_test.rb
git commit -m "feat: add EmailVerificationsController with verify and resend"
```

---

## Task 5: VerifiedEmail concern + enforce on posts and replies

**Files:**
- Create: `app/controllers/concerns/verified_email.rb`
- Modify: `app/controllers/posts_controller.rb`
- Modify: `app/controllers/replies_controller.rb`
- Modify: `test/controllers/posts_controller_test.rb` (add unverified-user cases)

- [ ] **Step 1: Write failing tests**

Add the following tests to `test/controllers/posts_controller_test.rb`. Find the existing `setup` block and note the fixtures/setup used, then add:

```ruby
test "POST /posts by unverified user redirects with alert" do
  # Create a user without email_verified_at
  unverified = User.create!(
    email: "unverified@example.com", name: "Unverified",
    password: "password123", password_confirmation: "password123",
    provider_id: Provider::INTERNAL
  )
  post login_path, params: { email: unverified.email, password: "password123" }

  category = Category.first || Category.create!(name: "General", position: 1)
  post posts_path, params: { post: { title: "Hello", body: "World", category_id: category.id } }

  assert_redirected_to root_path
  assert flash[:alert].present?
  assert_equal 0, Post.where(user: unverified).count
end

test "POST /posts by verified user creates post" do
  verified = User.create!(
    email: "verified2@example.com", name: "Verified",
    password: "password123", password_confirmation: "password123",
    provider_id: Provider::INTERNAL,
    email_verified_at: Time.current
  )
  post login_path, params: { email: verified.email, password: "password123" }

  category = Category.first || Category.create!(name: "General", position: 1)
  post posts_path, params: { post: { title: "Hello", body: "World", category_id: category.id } }

  assert_response :redirect
  assert_not_equal root_path, response.location
end
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
bin/rails test test/controllers/posts_controller_test.rb -n "/unverified|verified user creates/"
```

Expected: the unverified test passes (no enforcement yet), the verified test may pass — after adding concern the unverified test should redirect.

- [ ] **Step 3: Write the concern**

```ruby
# app/controllers/concerns/verified_email.rb
module VerifiedEmail
  extend ActiveSupport::Concern

  private

  def require_verified_email
    return if current_user.email_verified_at.present?
    flash[:alert] = "Please verify your email address before posting. Check your inbox or resend below."
    redirect_to root_path
  end
end
```

- [ ] **Step 4: Include concern in PostsController**

In `app/controllers/posts_controller.rb`, add after the existing `include` lines:

```ruby
include VerifiedEmail
```

And add to the `before_action` chain:

```ruby
before_action :require_verified_email, only: [:create]
```

The full `before_action` block at the top of the class should now include (add it after `check_not_banned` and `check_rate_limit`, both also only for `:create`):

```ruby
before_action :require_verified_email, only: [:create]
```

- [ ] **Step 5: Include concern in RepliesController**

In `app/controllers/replies_controller.rb`, add after the existing `include` lines:

```ruby
include VerifiedEmail
```

And add:

```ruby
before_action :require_verified_email, only: [:create]
```

- [ ] **Step 6: Run tests to confirm they pass**

```bash
bin/rails test test/controllers/posts_controller_test.rb
```

Expected: all tests pass including the new unverified-user case.

- [ ] **Step 7: Run full suite**

```bash
bin/rails test
```

Expected: 0 failures.

- [ ] **Step 8: Commit**

```bash
git add app/controllers/concerns/verified_email.rb \
        app/controllers/posts_controller.rb \
        app/controllers/replies_controller.rb \
        test/controllers/posts_controller_test.rb
git commit -m "feat: add VerifiedEmail concern, enforce on posts and replies create"
```

---

## Task 6: Send verification email on signup; auto-verify OAuth users

**Files:**
- Modify: `app/controllers/users_controller.rb`
- Modify: `app/controllers/omniauth_callbacks_controller.rb`

- [ ] **Step 1: Write failing tests**

Add to `test/controllers/users_controller_test.rb` (create it if it doesn't exist):

```ruby
# test/controllers/users_controller_test.rb
require "test_helper"

class UsersControllerTest < ActionDispatch::IntegrationTest
  include ActionMailer::TestHelper

  setup do
    ActionMailer::Base.deliveries.clear
    Provider.find_or_create_by!(id: Provider::INTERNAL, name: "internal")
    Provider.find_or_create_by!(id: Provider::GOOGLE,   name: "google")
  end

  test "POST /signup sends verification email and leaves email_verified_at nil" do
    assert_emails 1 do
      post signup_path, params: {
        user: {
          email: "newuser@example.com", name: "New User",
          password: "password123", password_confirmation: "password123"
        }
      }
    end
    user = User.find_by!(email: "newuser@example.com")
    assert_nil user.email_verified_at
    assert_not_nil user.email_verification
  end
end
```

- [ ] **Step 2: Run test to confirm it fails**

```bash
bin/rails test test/controllers/users_controller_test.rb
```

Expected: 0 emails sent (assertion failure).

- [ ] **Step 3: Update UsersController#create**

In `app/controllers/users_controller.rb`, update the `create` action's success branch:

```ruby
def create
  @user = User.new(user_params)
  @user.provider_id = Provider::INTERNAL
  if @user.save
    reset_session
    session[:user_id] = @user.id
    ev = @user.create_email_verification!(last_sent_at: Time.current)
    UserMailer.verify_email(ev).deliver_later
    redirect_to root_path, notice: "Welcome, #{@user.name}! Please check your email to verify your address."
  else
    render :new, status: :unprocessable_entity
  end
end
```

- [ ] **Step 4: Update OmniauthCallbacksController to auto-verify**

In `app/controllers/omniauth_callbacks_controller.rb`, update the `handle` action. After `user = User.from_omniauth(auth, provider_id)` succeeds, set `email_verified_at` if not already set:

```ruby
user = User.from_omniauth(auth, provider_id)
user.update_column(:email_verified_at, Time.current) if user.email_verified_at.nil?
reset_session
session[:user_id] = user.id
redirect_to root_path, notice: "Signed in as #{user.name}."
```

- [ ] **Step 5: Run tests to confirm they pass**

```bash
bin/rails test test/controllers/users_controller_test.rb
```

Expected: 1 test, 0 failures.

- [ ] **Step 6: Run full suite**

```bash
bin/rails test
```

Expected: 0 failures.

- [ ] **Step 7: Commit**

```bash
git add app/controllers/users_controller.rb \
        app/controllers/omniauth_callbacks_controller.rb \
        test/controllers/users_controller_test.rb
git commit -m "feat: send verification email on signup, auto-verify OAuth users"
```

---

## Task 7: Unverified user banner in application layout

**Files:**
- Modify: `app/views/layouts/application.html.erb`

- [ ] **Step 1: Add the banner**

In `app/views/layouts/application.html.erb`, after the `</nav>` closing tag and before the existing flash notice/alert blocks, add:

```erb
<% if logged_in? && current_user.email_verified_at.nil? %>
  <div class="max-w-7xl mx-auto px-4 mt-4">
    <div class="bg-yellow-50 dark:bg-yellow-900/20 border border-yellow-200 dark:border-yellow-700 text-yellow-800 dark:text-yellow-300 px-4 py-3 rounded-lg text-sm flex items-center justify-between gap-4">
      <span>Please verify your email address to enable posting.</span>
      <%= button_to "Resend verification email", resend_email_verifications_path,
            method: :post,
            class: "shrink-0 text-yellow-700 dark:text-yellow-300 underline hover:no-underline bg-transparent border-0 p-0 cursor-pointer" %>
    </div>
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
git add app/views/layouts/application.html.erb
git commit -m "feat: show email verification banner for unverified users"
```

---

## Task 8: Final CI check

- [ ] **Step 1: Run full CI pipeline**

```bash
./bin/ci
```

Expected: lint, security, and all tests pass.

- [ ] **Step 2: Commit any rubocop fixes if needed, then tag completion**

```bash
git add -A
git commit -m "fix: rubocop offenses from email verification feature"
```
