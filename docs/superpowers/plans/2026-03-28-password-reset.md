# Password Reset Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement a time-limited password reset flow for internal (email/password) accounts, delivered via Resend in production and letter_opener in development.

**Architecture:** A `password_resets` table stores one token per user with EXPIRY / REUSE_THRESHOLD / RESEND_COOLDOWN lifecycle helpers on the model. A `PasswordResetsController` handles four actions (new/create/edit/update). A new `UserMailer#password_reset` queues the reset link via solid_queue. OAuth users are excluded at every entry point.

**Tech Stack:** Rails 8.1, PostgreSQL, ActionMailer, `resend` gem (production delivery), `letter_opener` gem (development preview), solid_queue (background delivery), `has_secure_token` (24-char base58 token).

---

## File Map

| Action | Path |
|--------|------|
| Modify | `Gemfile` |
| Create | `config/initializers/resend.rb` |
| Modify | `config/environments/production.rb` |
| Modify | `config/environments/development.rb` |
| Modify | `app/mailers/application_mailer.rb` |
| Create | `db/migrate/TIMESTAMP_create_password_resets.rb` |
| Auto-update | `db/structure.sql` |
| Create | `app/models/password_reset.rb` |
| Modify | `app/models/user.rb` |
| Create | `test/models/password_reset_test.rb` |
| Create | `app/mailers/user_mailer.rb` |
| Create | `app/views/user_mailer/password_reset.html.erb` |
| Create | `app/views/user_mailer/password_reset.text.erb` |
| Create | `test/mailers/user_mailer_test.rb` |
| Modify | `config/routes.rb` |
| Create | `app/controllers/password_resets_controller.rb` |
| Create | `app/views/password_resets/new.html.erb` |
| Create | `app/views/password_resets/edit.html.erb` |
| Create | `test/controllers/password_resets_controller_test.rb` |
| Modify | `app/views/sessions/new.html.erb` |

---

### Task 1: Gems and Mailer Infrastructure

Add `resend` (production delivery) and `letter_opener` (development preview) gems, configure delivery methods in each environment, and update the ApplicationMailer sender address.

**Files:**
- Modify: `Gemfile`
- Create: `config/initializers/resend.rb`
- Modify: `config/environments/production.rb`
- Modify: `config/environments/development.rb`
- Modify: `app/mailers/application_mailer.rb`

- [ ] **Step 1: Add gems to Gemfile**

In `Gemfile`, add after the `gem "bcrypt"` line:

```ruby
gem "resend"
```

In the existing `group :development do` block, add:

```ruby
gem "letter_opener"
```

- [ ] **Step 2: Run bundle install**

```bash
bundle install
```

Expected: `Gemfile.lock` updated, no errors.

- [ ] **Step 3: Create the Resend initializer**

Create `config/initializers/resend.rb`:

```ruby
Resend.api_key = Rails.application.credentials.dig(:resend, :api_key).to_s
```

- [ ] **Step 4: Add credentials placeholder**

Run `bin/rails credentials:edit --environment production` (for production credentials) or just `bin/rails credentials:edit` (for the shared credential file, which the initializer reads in all environments) and add:

```yaml
resend:
  api_key: ""
```

Save and close. The API key is left blank until a Resend account is configured for production.

- [ ] **Step 5: Set production delivery method**

In `config/environments/production.rb`, add this line directly after the existing `config.action_mailer.default_url_options` line:

```ruby
config.action_mailer.delivery_method = :resend
```

Leave `default_url_options = { host: "example.com" }` as-is — the deployer updates the host value when the real domain is known.

- [ ] **Step 6: Set development delivery method**

In `config/environments/development.rb`, add this line directly after the existing `config.action_mailer.default_url_options` line:

```ruby
config.action_mailer.delivery_method = :letter_opener
```

- [ ] **Step 7: Update ApplicationMailer default sender**

In `app/mailers/application_mailer.rb`, replace `"from@example.com"`:

```ruby
class ApplicationMailer < ActionMailer::Base
  default from: "Forum <noreply@example.com>"
  layout "mailer"
end
```

The deployer replaces `noreply@example.com` with a verified Resend sender address before going live.

- [ ] **Step 8: Run the existing test suite**

```bash
bin/rails test
```

Expected: All existing tests pass. Nothing should be broken by these config changes.

- [ ] **Step 9: Commit**

```bash
git add Gemfile Gemfile.lock config/initializers/resend.rb config/environments/production.rb config/environments/development.rb app/mailers/application_mailer.rb
git commit -m "feat: add resend + letter_opener gems, configure mailer delivery"
```

---

### Task 2: Migration — Create `password_resets` Table

**Files:**
- Create: `db/migrate/TIMESTAMP_create_password_resets.rb`
- Auto-update: `db/structure.sql`

- [ ] **Step 1: Generate the migration file**

```bash
bin/rails generate migration CreatePasswordResets
```

Expected: Creates `db/migrate/TIMESTAMP_create_password_resets.rb`.

- [ ] **Step 2: Fill in the migration body**

Open the generated file and replace its contents with:

```ruby
class CreatePasswordResets < ActiveRecord::Migration[8.1]
  def change
    create_table :password_resets do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }, index: { unique: true }
      t.string :token, null: false
      t.datetime :created_at, null: false
      t.datetime :last_sent_at
    end

    add_index :password_resets, :token, unique: true
  end
end
```

Note: No `t.timestamps` — only `created_at` is defined. `updated_at` is intentionally absent (only `last_sent_at` mutates after creation). Rails auto-populates `created_at` on create when the column exists by that name.

- [ ] **Step 3: Run the migration**

```bash
bin/rails db:migrate
```

Expected: Migration succeeds. `db/structure.sql` is regenerated with the new table.

- [ ] **Step 4: Verify structure.sql**

Check that `db/structure.sql` now contains the `password_resets` table with columns `user_id`, `token`, `created_at`, `last_sent_at`, and unique indexes on both `user_id` and `token`.

- [ ] **Step 5: Commit**

```bash
git add db/migrate/ db/structure.sql
git commit -m "feat: create password_resets table"
```

---

### Task 3: PasswordReset Model + User Association

**Files:**
- Create: `app/models/password_reset.rb`
- Modify: `app/models/user.rb`
- Create: `test/models/password_reset_test.rb`

- [ ] **Step 1: Write the failing model tests**

Create `test/models/password_reset_test.rb`:

```ruby
require "test_helper"

class PasswordResetTest < ActiveSupport::TestCase
  setup do
    Provider.find_or_create_by!(id: Provider::INTERNAL, name: "internal")
    @user = User.create!(
      email: "pr@example.com", name: "PR User",
      password: "password123", password_confirmation: "password123",
      provider_id: Provider::INTERNAL
    )
  end

  # expired?
  test "expired? returns false when 59 minutes old" do
    reset = travel_to(59.minutes.ago) { @user.create_password_reset!(last_sent_at: Time.current) }
    assert_not reset.expired?
  end

  test "expired? returns true when 61 minutes old" do
    reset = travel_to(61.minutes.ago) { @user.create_password_reset!(last_sent_at: Time.current) }
    assert reset.expired?
  end

  # reusable?
  test "reusable? returns true when 39 minutes old" do
    reset = travel_to(39.minutes.ago) { @user.create_password_reset!(last_sent_at: Time.current) }
    assert reset.reusable?
  end

  test "reusable? returns true at exact 40-minute boundary" do
    # Capture `now` then travel_to exactly 40 min before it; assert at exactly `now`.
    # Without freezing the assertion moment, sub-second drift between the travel_to
    # block and the assert call makes `created_at` land just before `40.minutes.ago`,
    # flipping the `>=` boundary to false.
    now = Time.current
    reset = travel_to(now - 40.minutes) { @user.create_password_reset!(last_sent_at: Time.current) }
    travel_to(now) do
      assert reset.reusable?
    end
  end

  test "reusable? returns false when 41 minutes old" do
    reset = travel_to(41.minutes.ago) { @user.create_password_reset!(last_sent_at: Time.current) }
    assert_not reset.reusable?
  end

  # on_cooldown?
  test "on_cooldown? returns false when last_sent_at is nil" do
    reset = @user.create_password_reset!(last_sent_at: nil)
    assert_not reset.on_cooldown?
  end

  test "on_cooldown? returns true when last_sent_at is 2 minutes ago" do
    reset = @user.create_password_reset!(last_sent_at: 2.minutes.ago)
    assert reset.on_cooldown?
  end

  test "on_cooldown? returns false when last_sent_at is 4 minutes ago" do
    reset = @user.create_password_reset!(last_sent_at: 4.minutes.ago)
    assert_not reset.on_cooldown?
  end
end
```

`travel_to(N.ago) { ... }` freezes `Time.current` inside the block, so the record's `created_at` is set to that moment. After the block returns, `Time.current` is back to now — the correct baseline for `expired?`/`reusable?` checks.

- [ ] **Step 2: Run tests to verify they fail**

```bash
bin/rails test test/models/password_reset_test.rb
```

Expected: All 8 tests fail with `NameError: uninitialized constant PasswordReset`.

- [ ] **Step 3: Create the PasswordReset model**

Create `app/models/password_reset.rb`:

```ruby
class PasswordReset < ApplicationRecord
  belongs_to :user
  has_secure_token :token

  EXPIRY          = 1.hour
  REUSE_THRESHOLD = 20.minutes
  RESEND_COOLDOWN = 3.minutes

  def expired?
    created_at < EXPIRY.ago
  end

  def reusable?
    created_at >= (EXPIRY - REUSE_THRESHOLD).ago
  end

  def on_cooldown?
    last_sent_at && last_sent_at >= RESEND_COOLDOWN.ago
  end
end
```

- [ ] **Step 4: Add the association to User**

In `app/models/user.rb`, add inside the class body near the other `has_many` lines:

```ruby
has_one :password_reset, dependent: :destroy
```

- [ ] **Step 5: Run the model tests**

```bash
bin/rails test test/models/password_reset_test.rb
```

Expected: All 8 tests pass.

- [ ] **Step 6: Run the full test suite**

```bash
bin/rails test
```

Expected: All tests pass. No regressions.

- [ ] **Step 7: Commit**

```bash
git add app/models/password_reset.rb app/models/user.rb test/models/password_reset_test.rb
git commit -m "feat: add PasswordReset model with token lifecycle helpers"
```

---

### Task 4: UserMailer — Password Reset Email

**Files:**
- Create: `app/mailers/user_mailer.rb`
- Create: `app/views/user_mailer/password_reset.html.erb`
- Create: `app/views/user_mailer/password_reset.text.erb`
- Create: `test/mailers/user_mailer_test.rb`

- [ ] **Step 1: Write the failing mailer test**

Create `test/mailers/user_mailer_test.rb`:

```ruby
require "test_helper"

class UserMailerTest < ActionMailer::TestCase
  setup do
    Provider.find_or_create_by!(id: Provider::INTERNAL, name: "internal")
    @user = User.create!(
      email: "mailer@example.com", name: "Mailer User",
      password: "password123", password_confirmation: "password123",
      provider_id: Provider::INTERNAL
    )
    @reset = @user.create_password_reset!(last_sent_at: Time.current)
  end

  test "password_reset sends to correct recipient with correct subject" do
    email = UserMailer.password_reset(@reset)
    assert_emails 1 do
      email.deliver_now
    end
    assert_equal [ "mailer@example.com" ], email.to
    assert_equal "Reset your Forum password", email.subject
  end

  test "password_reset email body contains the reset URL with correct token" do
    email = UserMailer.password_reset(@reset)
    expected_url = edit_password_reset_url(@reset.token)
    assert_match expected_url, email.html_part.body.to_s
    assert_match expected_url, email.text_part.body.to_s
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
bin/rails test test/mailers/user_mailer_test.rb
```

Expected: Both tests fail with `NameError: uninitialized constant UserMailer`.

- [ ] **Step 3: Create the UserMailer**

Create `app/mailers/user_mailer.rb`:

```ruby
class UserMailer < ApplicationMailer
  def password_reset(reset)
    @reset = reset
    @user = reset.user
    mail to: @user.email, subject: "Reset your Forum password"
  end
end
```

- [ ] **Step 4: Create the HTML email template**

Create `app/views/user_mailer/password_reset.html.erb`:

```erb
<p>Hi <%= @user.name %>,</p>

<p>Someone requested a password reset for your Forum account. Click the link below to set a new password:</p>

<p><%= link_to "Reset my password", edit_password_reset_url(@reset.token) %></p>

<p>This link expires in 1 hour.</p>

<p>If you didn't request this, you can safely ignore this email — your password won't change.</p>
```

- [ ] **Step 5: Create the plain text email template**

Create `app/views/user_mailer/password_reset.text.erb`:

```erb
Hi <%= @user.name %>,

Someone requested a password reset for your Forum account.

Reset your password: <%= edit_password_reset_url(@reset.token) %>

This link expires in 1 hour.

If you didn't request this, you can safely ignore this email — your password won't change.
```

- [ ] **Step 6: Run the mailer tests**

```bash
bin/rails test test/mailers/user_mailer_test.rb
```

Expected: Both tests pass.

- [ ] **Step 7: Run the full test suite**

```bash
bin/rails test
```

Expected: All tests pass.

- [ ] **Step 8: Commit**

```bash
git add app/mailers/user_mailer.rb app/views/user_mailer/ test/mailers/user_mailer_test.rb
git commit -m "feat: add UserMailer password_reset email"
```

---

### Task 5: Routes and Controller Skeleton

**Files:**
- Modify: `config/routes.rb`
- Create: `app/controllers/password_resets_controller.rb`

- [ ] **Step 1: Add the resource route**

In `config/routes.rb`, add after the `post "/signup"` line in the `# Auth` block:

```ruby
resources :password_resets, only: [ :new, :create, :edit, :update ], param: :token
```

- [ ] **Step 2: Create the controller skeleton**

Create `app/controllers/password_resets_controller.rb`:

```ruby
class PasswordResetsController < ApplicationController
  def new
  end

  def create
  end

  def edit
  end

  def update
  end
end
```

- [ ] **Step 3: Verify routes**

```bash
bin/rails routes | grep password_reset
```

Expected output includes:

```
new_password_reset  GET    /password_resets/new             password_resets#new
    password_resets  POST   /password_resets                 password_resets#create
edit_password_reset  GET    /password_resets/:token/edit     password_resets#edit
     password_reset  PATCH  /password_resets/:token          password_resets#update
```

- [ ] **Step 4: Commit**

```bash
git add config/routes.rb app/controllers/password_resets_controller.rb
git commit -m "feat: add password_resets routes and controller skeleton"
```

---

### Task 6: new + create Actions, new View, and Integration Tests

**Files:**
- Modify: `app/controllers/password_resets_controller.rb`
- Create: `app/views/password_resets/new.html.erb`
- Create: `test/controllers/password_resets_controller_test.rb`

- [ ] **Step 1: Write the complete integration test file**

Create `test/controllers/password_resets_controller_test.rb`:

```ruby
require "test_helper"

class PasswordResetsControllerTest < ActionDispatch::IntegrationTest
  # Rails 7.1+ includes ActionMailer::TestHelper in ActiveSupport::TestCase, so
  # assert_emails is available here. Include it explicitly for clarity and safety.
  include ActionMailer::TestHelper

  setup do
    ActionMailer::Base.deliveries.clear
    Provider.find_or_create_by!(id: Provider::INTERNAL, name: "internal")
    Provider.find_or_create_by!(id: Provider::GOOGLE,   name: "google")
    @user = User.create!(
      email: "reset@example.com", name: "Reset User",
      password: "password123", password_confirmation: "password123",
      provider_id: Provider::INTERNAL
    )
    @oauth_user = User.create!(
      email: "oauth@example.com", name: "OAuth User",
      provider_id: Provider::GOOGLE, uid: "oauth-uid-123"
    )
  end

  teardown do
    Rails.cache.clear
  end

  # ─── new ────────────────────────────────────────────────────────────────────
  test "GET /password_resets/new renders the email form" do
    get new_password_reset_path
    assert_response :success
    assert_select "form"
  end

  # ─── create: no information leak ────────────────────────────────────────────
  test "POST /password_resets with unknown email redirects with generic flash" do
    assert_emails 0 do
      post password_resets_path, params: { email: "nobody@example.com" }
    end
    assert_redirected_to login_path
    assert flash[:notice].present?
  end

  test "POST /password_resets with OAuth user email redirects with generic flash, no row created" do
    assert_emails 0 do
      post password_resets_path, params: { email: @oauth_user.email }
    end
    assert_redirected_to login_path
    assert_nil @oauth_user.reload.password_reset
  end

  # ─── create: first valid request ────────────────────────────────────────────
  test "POST /password_resets creates reset row with last_sent_at set and enqueues email" do
    assert_emails 1 do
      post password_resets_path, params: { email: @user.email }
    end
    assert_redirected_to login_path
    @user.reload
    assert_not_nil @user.password_reset
    assert_not_nil @user.password_reset.last_sent_at
  end

  # ─── create: cooldown on brand-new token ────────────────────────────────────
  test "second POST within 3-minute cooldown suppresses email" do
    assert_emails 1 do
      post password_resets_path, params: { email: @user.email }
    end
    assert_emails 0 do
      post password_resets_path, params: { email: @user.email }
    end
    assert_redirected_to login_path
  end

  # ─── create: resend when reusable and outside cooldown ──────────────────────
  test "POST when token is reusable and outside cooldown updates last_sent_at and resends" do
    original_reset = travel_to(10.minutes.ago) { @user.create_password_reset!(last_sent_at: Time.current) }
    original_reset.update_column(:last_sent_at, 5.minutes.ago)
    original_token = original_reset.token

    assert_emails 1 do
      post password_resets_path, params: { email: @user.email }
    end

    @user.password_reset.reload
    assert_equal original_token, @user.password_reset.token
    assert @user.password_reset.last_sent_at >= 1.minute.ago
  end

  # ─── create: token in 41–59 min zone (not reusable, not expired) ────────────
  test "POST when token is 45 minutes old destroys old row and creates new token" do
    old_reset = travel_to(45.minutes.ago) { @user.create_password_reset!(last_sent_at: Time.current) }
    old_token = old_reset.token

    assert_emails 1 do
      post password_resets_path, params: { email: @user.email }
    end

    @user.reload
    assert_not_nil @user.password_reset
    assert_not_equal old_token, @user.password_reset.token
  end

  # ─── create: expired token ──────────────────────────────────────────────────
  test "POST when token is expired destroys old row and creates new token" do
    old_reset = travel_to(2.hours.ago) { @user.create_password_reset!(last_sent_at: Time.current) }
    old_token = old_reset.token

    assert_emails 1 do
      post password_resets_path, params: { email: @user.email }
    end

    @user.reload
    assert_not_nil @user.password_reset
    assert_not_equal old_token, @user.password_reset.token
  end

  # ─── edit ───────────────────────────────────────────────────────────────────
  test "GET /password_resets/:token/edit with unknown token redirects with alert" do
    get edit_password_reset_path("nonexistent-token")
    assert_redirected_to new_password_reset_path
    assert flash[:alert].present?
  end

  test "GET /password_resets/:token/edit with expired token redirects with alert" do
    reset = travel_to(2.hours.ago) { @user.create_password_reset!(last_sent_at: Time.current) }
    get edit_password_reset_path(reset.token)
    assert_redirected_to new_password_reset_path
    assert flash[:alert].present?
  end

  test "GET /password_resets/:token/edit with valid token renders the form" do
    reset = @user.create_password_reset!(last_sent_at: Time.current)
    get edit_password_reset_path(reset.token)
    assert_response :success
    assert_select "form"
  end

  test "GET /password_resets/:token/edit with OAuth user token redirects to login" do
    # Defensive guard: crafted URL for a token belonging to an OAuth user
    # should redirect rather than render the form.
    # In normal flow create never issues a token for OAuth users; this guards
    # against crafted URLs or future code changes.
    reset = PasswordReset.create!(user: @oauth_user, last_sent_at: Time.current)
    get edit_password_reset_path(reset.token)
    assert_redirected_to login_path
    assert flash[:alert].present?
  end

  test "PATCH /password_resets/:token with OAuth user token redirects to login" do
    reset = PasswordReset.create!(user: @oauth_user, last_sent_at: Time.current)
    patch password_reset_path(reset.token),
          params: { user: { password: "newpass123", password_confirmation: "newpass123" } }
    assert_redirected_to login_path
    assert flash[:alert].present?
  end

  # ─── update ─────────────────────────────────────────────────────────────────
  test "PATCH with expired token redirects" do
    reset = travel_to(2.hours.ago) { @user.create_password_reset!(last_sent_at: Time.current) }
    patch password_reset_path(reset.token),
          params: { user: { password: "newpass123", password_confirmation: "newpass123" } }
    assert_redirected_to new_password_reset_path
  end

  test "PATCH happy path updates password, destroys reset row, and logs user in" do
    reset = @user.create_password_reset!(last_sent_at: Time.current)
    patch password_reset_path(reset.token),
          params: { user: { password: "newpass123", password_confirmation: "newpass123" } }
    assert_redirected_to root_path
    assert flash[:notice].present?
    assert_equal @user.id, session[:user_id]
    assert_nil PasswordReset.find_by(id: reset.id)
    assert @user.reload.authenticate("newpass123")
  end

  test "PATCH with mismatched passwords re-renders edit with 422" do
    reset = @user.create_password_reset!(last_sent_at: Time.current)
    patch password_reset_path(reset.token),
          params: { user: { password: "newpass123", password_confirmation: "wrongpass" } }
    assert_response :unprocessable_entity
    assert_not_nil PasswordReset.find_by(id: reset.id)
  end

  test "PATCH with blank password re-renders edit with 422" do
    reset = @user.create_password_reset!(last_sent_at: Time.current)
    patch password_reset_path(reset.token),
          params: { user: { password: "", password_confirmation: "" } }
    assert_response :unprocessable_entity
  end

  test "PATCH with password shorter than 6 characters re-renders with 422" do
    reset = @user.create_password_reset!(last_sent_at: Time.current)
    patch password_reset_path(reset.token),
          params: { user: { password: "abc", password_confirmation: "abc" } }
    assert_response :unprocessable_entity
  end

  test "PATCH with blank confirmation and present password re-renders with 422" do
    reset = @user.create_password_reset!(last_sent_at: Time.current)
    patch password_reset_path(reset.token),
          params: { user: { password: "newpass123", password_confirmation: "" } }
    assert_response :unprocessable_entity
  end
end
```

- [ ] **Step 2: Run tests to see them fail**

```bash
bin/rails test test/controllers/password_resets_controller_test.rb
```

Expected: Multiple failures — the empty stub actions cause missing template errors and incorrect redirects.

- [ ] **Step 3: Implement the new action and create new.html.erb**

`new` needs no logic — it just renders. Create the view first.

Create `app/views/password_resets/new.html.erb`:

```erb
<div class="max-w-md mx-auto mt-12 p-6 bg-white dark:bg-stone-800 dark:border dark:border-stone-700 rounded-lg shadow">
  <h1 class="text-2xl font-bold mb-2 dark:text-stone-100">Forgot your password?</h1>
  <p class="text-sm text-gray-600 dark:text-stone-400 mb-6">Enter your email and we'll send you a reset link.</p>

  <%= form_with url: password_resets_path, class: "space-y-4" do |f| %>
    <div>
      <%= f.label :email, class: "block text-sm font-medium text-gray-700 dark:text-stone-300" %>
      <%= f.email_field :email, class: "mt-1 block w-full border border-gray-300 dark:border-stone-600 rounded-md px-3 py-2 focus:outline-none focus:ring-2 focus:ring-blue-500 dark:focus:ring-blue-400 bg-white dark:bg-stone-700 text-stone-900 dark:text-stone-100", required: true %>
    </div>
    <%= f.submit "Send reset link", class: "w-full bg-blue-600 text-white py-2 px-4 rounded-md hover:bg-blue-700 font-medium" %>
  <% end %>

  <p class="mt-4 text-center text-sm text-gray-600 dark:text-stone-400">
    <%= link_to "Back to login", login_path, class: "text-blue-600 hover:underline" %>
  </p>
</div>
```

The `new` stub in the controller needs no changes — it renders `new.html.erb` by convention.

- [ ] **Step 4: Implement the create action**

In `app/controllers/password_resets_controller.rb`, replace the `create` stub:

```ruby
def create
  email = params[:email].to_s.downcase.strip
  user = User.find_by(email: email)

  if user&.internal?
    reset = user.password_reset

    if reset&.reusable?
      unless reset.on_cooldown?
        reset.update!(last_sent_at: Time.current)
        UserMailer.password_reset(reset).deliver_later
      end
    else
      reset&.destroy
      reset = user.create_password_reset!(last_sent_at: Time.current)
      UserMailer.password_reset(reset).deliver_later
    end
  end

  redirect_to login_path, notice: "If that email is registered, you'll receive a reset link shortly."
end
```

Logic: find user by email → skip silently if not found or OAuth → reuse/resend or destroy-and-recreate based on token age → always redirect with the same generic flash.

- [ ] **Step 5: Run the new + create tests**

```bash
bin/rails test test/controllers/password_resets_controller_test.rb -n "/new|create/"
```

Expected: All new and create tests pass. Edit/update tests still fail — that's expected.

- [ ] **Step 6: Commit new + create**

```bash
git add app/controllers/password_resets_controller.rb app/views/password_resets/new.html.erb test/controllers/password_resets_controller_test.rb
git commit -m "feat: add PasswordResetsController new/create with token lifecycle"
```

---

### Task 7: edit + update Actions and edit View

**Files:**
- Modify: `app/controllers/password_resets_controller.rb`
- Create: `app/views/password_resets/edit.html.erb`

- [ ] **Step 1: Implement the edit action**

In `app/controllers/password_resets_controller.rb`, replace the `edit` stub:

```ruby
def edit
  @reset = PasswordReset.find_by(token: params[:token])

  if @reset.nil? || @reset.expired?
    redirect_to new_password_reset_path,
                alert: "That reset link is invalid or has expired. Please request a new one."
    return
  end

  unless @reset.user.internal?
    redirect_to login_path,
                alert: "Your account uses a social provider to sign in. Please reset your password there."
    return
  end
end
```

- [ ] **Step 2: Create the edit view**

Create `app/views/password_resets/edit.html.erb`:

```erb
<div class="max-w-md mx-auto mt-12 p-6 bg-white dark:bg-stone-800 dark:border dark:border-stone-700 rounded-lg shadow">
  <h1 class="text-2xl font-bold mb-6 dark:text-stone-100">Choose a new password</h1>

  <% if @error %>
    <p class="mb-4 text-sm text-red-600 dark:text-red-400"><%= @error %></p>
  <% end %>

  <% if @reset.user.errors.any? %>
    <div class="mb-4">
      <% @reset.user.errors.full_messages.each do |msg| %>
        <p class="text-sm text-red-600 dark:text-red-400"><%= msg %></p>
      <% end %>
    </div>
  <% end %>

  <%= form_with url: password_reset_path(@reset.token), method: :patch, class: "space-y-4" do |f| %>
    <div>
      <%= f.label :password, "New password", class: "block text-sm font-medium text-gray-700 dark:text-stone-300" %>
      <p class="text-xs text-gray-500 dark:text-stone-400 mt-1 mb-1">Minimum 6 characters</p>
      <%= f.password_field :password, name: "user[password]",
            class: "mt-1 block w-full border border-gray-300 dark:border-stone-600 rounded-md px-3 py-2 focus:outline-none focus:ring-2 focus:ring-blue-500 dark:focus:ring-blue-400 bg-white dark:bg-stone-700 text-stone-900 dark:text-stone-100",
            required: true, minlength: 6 %>
    </div>
    <div>
      <%= f.label :password_confirmation, "Confirm new password", class: "block text-sm font-medium text-gray-700 dark:text-stone-300" %>
      <%= f.password_field :password_confirmation, name: "user[password_confirmation]",
            class: "mt-1 block w-full border border-gray-300 dark:border-stone-600 rounded-md px-3 py-2 focus:outline-none focus:ring-2 focus:ring-blue-500 dark:focus:ring-blue-400 bg-white dark:bg-stone-700 text-stone-900 dark:text-stone-100",
            required: true %>
    </div>
    <%= f.submit "Update password", class: "w-full bg-blue-600 text-white py-2 px-4 rounded-md hover:bg-blue-700 font-medium" %>
  <% end %>
</div>
```

The `@error` variable is set by the controller for the blank-confirmation guard. Model validation errors are rendered via `@reset.user.errors`.

- [ ] **Step 3: Implement the update action**

In `app/controllers/password_resets_controller.rb`, replace the `update` stub:

```ruby
def update
  @reset = PasswordReset.find_by(token: params[:token])

  if @reset.nil? || @reset.expired?
    redirect_to new_password_reset_path, alert: "That reset link is invalid or has expired."
    return
  end

  unless @reset.user.internal?
    redirect_to login_path, alert: "Your account uses a social provider. Please reset your password there."
    return
  end

  user = @reset.user
  password = params[:user][:password]
  confirmation = params[:user][:password_confirmation]

  if password.present? && confirmation.blank?
    @error = "Password confirmation can't be blank"
    render :edit, status: :unprocessable_entity
    return
  end

  if user.update(password: password, password_confirmation: confirmation)
    @reset.destroy
    reset_session
    session[:user_id] = user.id
    redirect_to root_path, notice: "Password updated. You're now logged in."
  else
    render :edit, status: :unprocessable_entity
  end
end
```

Key points:
- Blank confirmation with a present password is caught before `user.update` — the `password_matches_confirmation` validator only fires when both are present, so this case would silently save without confirmation otherwise.
- On success: destroy the reset row, call `reset_session` (session fixation protection, matching `SessionsController#create`), then set `session[:user_id]`. The `touch_session` after_action in `ApplicationController` fires automatically because `session[:user_id]` is now set.
- A blank `password` field arrives as `""` (not `nil`), which fails the 6-character minimum validator — no special handling needed.

- [ ] **Step 4: Run the full controller test file**

```bash
bin/rails test test/controllers/password_resets_controller_test.rb
```

Expected: All tests pass.

- [ ] **Step 5: Run the full test suite**

```bash
bin/rails test
```

Expected: All tests pass. No regressions.

- [ ] **Step 6: Commit edit + update**

```bash
git add app/controllers/password_resets_controller.rb app/views/password_resets/edit.html.erb
git commit -m "feat: add PasswordResetsController edit/update, complete password reset flow"
```

---

### Task 8: Forgot Password Link + Full CI

Add the "Forgot password?" link to the login page, then run the full CI pipeline.

**Files:**
- Modify: `app/views/sessions/new.html.erb`

- [ ] **Step 1: Add "Forgot password?" link to the login form**

In `app/views/sessions/new.html.erb`, replace the password field `<div>` block:

```erb
    <div>
      <%= f.label :password, class: "block text-sm font-medium text-gray-700 dark:text-stone-300" %>
      <%= f.password_field :password, class: "mt-1 block w-full border border-gray-300 dark:border-stone-600 rounded-md px-3 py-2 focus:outline-none focus:ring-2 focus:ring-blue-500 dark:focus:ring-blue-400 bg-white dark:bg-stone-700 text-stone-900 dark:text-stone-100", required: true %>
      <div class="text-right mt-1">
        <%= link_to "Forgot password?", new_password_reset_path, class: "text-sm text-blue-600 hover:underline" %>
      </div>
    </div>
```

The link appears right-aligned below the password field. No conditional rendering is needed — OAuth users who click it will see the generic flash on submit, since their email won't match an internal account.

- [ ] **Step 2: Run the full CI pipeline**

```bash
./bin/ci
```

Expected: All linting, security checks, and tests pass.

- [ ] **Step 3: Fix any rubocop offenses**

If rubocop reports style issues, run:

```bash
./bin/rubocop -A
```

Then re-run `./bin/ci` to confirm everything passes.

- [ ] **Step 4: Commit**

```bash
git add app/views/sessions/new.html.erb
git commit -m "feat: add forgot password link to login page"
```
