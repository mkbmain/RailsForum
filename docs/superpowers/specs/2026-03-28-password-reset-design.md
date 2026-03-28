# Password Reset Design

**Date:** 2026-03-28
**Status:** Approved

## Overview

Implement a password reset flow for internal (email/password) accounts. Users receive a time-limited reset link via email. Delivery is handled by Resend via ActionMailer. OAuth users (Google/Microsoft) are directed to reset via their provider instead.

---

## Data Model

### New table: `password_resets`

| Column        | Type      | Constraints                                           |
|---------------|-----------|-------------------------------------------------------|
| `id`          | bigint    | PK                                                    |
| `user_id`     | bigint    | FK → users, NOT NULL, on delete cascade, unique index |
| `token`       | string    | NOT NULL, unique index                                |
| `created_at`  | datetime  | NOT NULL                                              |
| `last_sent_at`| datetime  | nullable                                              |

No `updated_at` — only `last_sent_at` is mutated after creation. The unique index on `user_id` enforces one row per user at the DB level, preventing duplicate rows from concurrent requests.

### `users` table

No changes required.

---

## Token Lifecycle

Constants on `PasswordReset`:

```ruby
EXPIRY          = 1.hour
REUSE_THRESHOLD = 20.minutes
RESEND_COOLDOWN = 3.minutes
```

| Helper        | Logic                                                 |
|---------------|-------------------------------------------------------|
| `expired?`    | `created_at < EXPIRY.ago`                             |
| `reusable?`   | `created_at >= (EXPIRY - REUSE_THRESHOLD).ago`        |
| `on_cooldown?`| `last_sent_at && last_sent_at >= RESEND_COOLDOWN.ago` |

Note: `expired?` implies `!reusable?` (any expired token is also not reusable), but `!reusable?` does NOT imply `expired?` — a token aged 41–59 minutes is not reusable but not expired. Step 3 below uses `!reusable?` as the sole branch condition, which correctly covers both the 41–59 min zone and fully expired tokens.

**Worked examples for `reusable?`** (boundary = 40 min = `EXPIRY - REUSE_THRESHOLD`):

| Token age | Remaining | `reusable?` | Action         |
|-----------|-----------|-------------|----------------|
| 35 min    | 25 min    | true        | Resend if not on cooldown |
| 40 min    | 20 min    | true (`>=` is inclusive boundary) | Resend if not on cooldown |
| 41 min    | 19 min    | false       | Destroy, create new |
| 61 min    | expired   | false       | Destroy, create new |

**On a new reset request for a user:**

1. Find the user's `PasswordReset` row (if any) via `user.password_reset`.
2. If row exists **and** `reusable?`:
   - If `on_cooldown?` → do nothing (silently skip email).
   - Otherwise → `reset.update!(last_sent_at: Time.current)`, send email via `UserMailer`.
3. Otherwise (`!reusable?`, which covers both the 41–60 min zone and expired tokens) → `user.password_reset&.destroy`, then `user.create_password_reset!(last_sent_at: Time.current)` and send email.
   - `last_sent_at` is set explicitly at row creation so the 3-minute cooldown applies even to brand-new tokens. A second request within 3 minutes of the first send will be silently suppressed.
4. Always redirect with the same generic flash regardless of outcome — never reveal whether an address is registered.

---

## Routes

```ruby
resources :password_resets, only: [:new, :create, :edit, :update], param: :token
```

Using `param: :token` means Rails generates `/password_resets/:token/edit` and puts the value in `params[:token]`. `has_secure_token` generates a 24-character base58 token — URL-safe, no additional encoding needed.

| Verb  | Path                            | Action   | Purpose                         |
|-------|---------------------------------|----------|---------------------------------|
| GET   | /password_resets/new            | `new`    | Email input form                |
| POST  | /password_resets                | `create` | Trigger token + email           |
| GET   | /password_resets/:token/edit    | `edit`   | New password form               |
| PATCH | /password_resets/:token         | `update` | Apply new password              |

---

## Controller: `PasswordResetsController`

### `new`
Renders the email input form. No auth required.

### `create`
1. Find user by downcased, stripped email param.
2. If user exists and `user.internal?`: run the token lifecycle logic above.
3. Always redirect to `login_path` with generic notice — never branch on user existence.

No additional IP-level rate limiting is specified; the per-user `RESEND_COOLDOWN` is the primary guard. Acknowledged gap — acceptable for a low-traffic internal forum, revisit if public-facing at scale.

### `edit`
1. Fetch: `@reset = PasswordReset.find_by(token: params[:token])`.
2. If `@reset.nil? || @reset.expired?` → redirect to `new_password_reset_path`, alert: `"That reset link is invalid or has expired. Please request a new one."`.
3. Defensive OAuth guard: if `!@reset.user.internal?` → redirect to `login_path` with alert directing them to their OAuth provider. This path is unreachable in normal flow — `create` never generates a token for OAuth users — but guards against crafted URLs or future code changes.
4. Assign `@reset` and render `edit`.

### `update`
1. Fetch: `@reset = PasswordReset.find_by(token: params[:token])`.
2. If `@reset.nil? || @reset.expired?` → redirect to `new_password_reset_path`, alert: `"That reset link is invalid or has expired."`.
3. Repeat defensive OAuth guard: if `!@reset.user.internal?` → redirect to `login_path`. A raw `PATCH` can bypass the `edit` render entirely.
4. Set `user = @reset.user`.
5. Attempt `user.update(password: params[:user][:password], password_confirmation: params[:user][:password_confirmation])`.
   - **Password validation:** The `User` model uses `has_secure_password validations: false` with a custom length validator: `validates :password, length: { minimum: 6, allow_nil: true }, if: :internal?`. A blank `password` field comes through as `""` (empty string), which has length 0 — the length validator rejects it with "is too short (minimum is 6 characters)". The HTML `required` attribute is defence-in-depth only.
   - **Confirmation validation:** The `password_matches_confirmation` custom validator fires `if: -> { internal? && password.present? && password_confirmation.present? }`. If the user submits a non-blank password but a **blank confirmation**, the mismatch validator does NOT fire — the password would be saved without being confirmed. **Chosen fix: controller-level guard** — before calling `user.update`, check `if params[:user][:password].present? && params[:user][:password_confirmation].blank?` and re-render `edit` with `@error = "Password confirmation can't be blank"` (status 422). Surface this via an instance variable the view renders above the form.
   - The reset form must display the 6-character minimum requirement to the user.
6. On success: `@reset.destroy`, `reset_session` (session fixation protection — consistent with `SessionsController#create`), `session[:user_id] = user.id`, redirect to `root_path`, notice: `"Password updated. You're now logged in."`.
   - `touch_session` (an after_action in `ApplicationController`) sets `session[:last_active_at]` when `session[:user_id].present?`. Since `session[:user_id] = user.id` is set before the action returns, `touch_session` will fire correctly — the implementer does not need to set `last_active_at` manually.
   - `reset_session` wipes any pre-existing session cleanly. `check_session_timeout` (a before_action) only fires `if: :logged_in?`; after `reset_session` the session is blank so it is a no-op on this request.
7. On failure: re-render `edit` with status `422`.

---

## Model: `PasswordReset`

```ruby
class PasswordReset < ApplicationRecord
  belongs_to :user
  has_secure_token :token

  EXPIRY          = 1.hour
  REUSE_THRESHOLD = 20.minutes
  RESEND_COOLDOWN = 3.minutes

  # last_sent_at must be passed explicitly at creation:
  #   user.create_password_reset!(last_sent_at: Time.current)

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

### Association on `User`

```ruby
has_one :password_reset, dependent: :destroy
```

---

## Mailer: `UserMailer`

New action `password_reset(reset)`:
- Recipient: `reset.user.email`
- Subject: `"Reset your Forum password"`
- From: update `ApplicationMailer` default from `"from@example.com"` to a real address, e.g. `"Forum <noreply@yourdomain.com>"`. The implementer must update `app/mailers/application_mailer.rb`.
- Body: `edit_password_reset_url(reset.token)`, note link expires in 1 hour, note that if they didn't request this they can safely ignore it.
- Delivered via `deliver_later` on the `default` queue (solid_queue). Verify no app-wide queue override exists for mailer jobs; if one does, match it.
- If the job fails, solid_queue retries per its default policy. The user sees the generic success flash regardless — acceptable for a reset flow.

Two templates: `user_mailer/password_reset.html.erb` and `user_mailer/password_reset.text.erb`.

---

## Resend Integration

```ruby
# Gemfile
gem "resend"
gem "letter_opener", group: :development

# config/initializers/resend.rb
Resend.api_key = Rails.application.credentials.dig(:resend, :api_key).to_s

# config/environments/production.rb
config.action_mailer.delivery_method = :resend
# UPDATE the existing default_url_options line (don't add a duplicate):
#   config.action_mailer.default_url_options = { host: "YOUR_REAL_DOMAIN" }
# production.rb already has this line set to "example.com" — replace that value.

# config/environments/development.rb
config.action_mailer.delivery_method = :letter_opener
# perform_deliveries defaults to true in Rails — no line needed.
# default_url_options { host: "localhost", port: 3000 } already set.

# config/environments/test.rb — no changes needed
# delivery_method :test already set; default_url_options { host: "example.com" } already set.
# Tests assert email delivery via assert_emails / ActionMailer::Base.deliveries.
```

Credentials file gets a `resend:` section — `api_key` left blank until a Resend account is set up.

---

## Views

| File                                        | Purpose                                              |
|---------------------------------------------|------------------------------------------------------|
| `password_resets/new.html.erb`              | Email input form                                     |
| `password_resets/edit.html.erb`             | Password + confirmation fields, 6-char min noted     |
| `user_mailer/password_reset.html.erb`       | HTML email template                                  |
| `user_mailer/password_reset.text.erb`       | Plain text email fallback                            |

Styling follows existing Tailwind patterns. A "Forgot password?" link is added below the password field in `app/views/sessions/new.html.erb`. No conditional rendering needed — the link is harmless for OAuth users (who will see the generic flash if they try to use it, since their email won't match an internal account that has a token).

**`edit.html.erb` form:** Because the route uses `param: :token`, use an explicit URL:
```erb
<%= form_with url: password_reset_path(@reset.token), method: :patch do |f| %>
```

---

## Security Notes

- Generic flash on `create` — never reveals whether an email is registered.
- Tokens are single-use — destroyed immediately after successful password change.
- Tokens expire after 1 hour; tokens with ≤ 20 min remaining are replaced, not resent.
- `reset_session` called before `session[:user_id]` is set (session fixation protection).
- OAuth users (`!user.internal?`) cannot trigger a reset; defensive guard also in `edit` and `update`.
- `on_cooldown?` prevents email flooding per user (3-minute minimum between sends).
- `last_sent_at` set at row creation so the cooldown applies immediately to new tokens.
- Unique DB index on `user_id` prevents duplicate rows from concurrent requests.
- Blank `password_confirmation` with a present `password` caught by controller-level guard.
- No IP-level rate limit on `POST /password_resets` — acknowledged gap, acceptable for low-traffic use.
- Token lookup uses `find_by(token:)` (direct DB equality), not constant-time comparison. Minor timing oracle risk — acknowledged, acceptable for a low-traffic forum.

---

## Testing

### `PasswordReset` model
- `expired?` returns false when `created_at` is 59 min ago; true when 61 min ago.
- `reusable?` returns true when token is 39 min old; true at exact 40-min boundary (`>=`); false when 41 min old.
- `on_cooldown?` returns false when `last_sent_at` is nil; true when 2 min ago; false when 4 min ago.

### `PasswordResetsController` integration
- Unknown email → same generic flash (no leak).
- OAuth user email → same generic flash (no reset sent, no row created).
- Valid first-time request → `PasswordReset` row created with `last_sent_at` set, email enqueued.
- Second request within 3-min cooldown of a brand-new token → no new email enqueued.
- Second request outside cooldown, token still reusable → `last_sent_at` updated, email resent, token unchanged.
- Request when token is 41–59 min old (not reusable, not expired) → old row destroyed, new token created, email enqueued.
- Request when token is expired → old row destroyed, new token created, email enqueued.
- `edit` with unknown token → redirect with alert.
- `edit` with expired token → redirect with alert.
- `update` with expired token → redirect with alert.
- `update` happy path → password updated, reset row destroyed, user logged in, redirected to root.
- `update` with mismatched passwords → re-renders `edit` with `422`, reset row preserved.
- `update` with blank password → re-renders `edit` with `422`.
- `update` with password shorter than 6 characters → re-renders `edit` with `422`.
- `update` with blank `password_confirmation` (non-blank password) → re-renders `edit` with `422`.

### Mailer
- `password_reset` sends to correct recipient with correct subject.
- Email body contains `edit_password_reset_url` with the correct token.
- Uses `assert_emails 1` in integration tests.
