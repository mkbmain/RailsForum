# Email Verification + Two-Factor Authentication Design

**Date:** 2026-03-28
**Status:** Approved

## Overview

Two phased security improvements:

1. **Phase 1 — Email Verification:** Require users to confirm their email address before posting or replying.
2. **Phase 2 — Two-Factor Authentication (TOTP):** Allow users to protect their account with a TOTP authenticator app.

Both features build on existing infrastructure (`UserMailer`, `PasswordReset` token pattern, `LoginThrottle`).

---

## Phase 1: Email Verification

### Data Model

- Add `email_verified_at:datetime` to the `users` table (nullable; null = unverified).
- Add an `EmailVerification` model with `token:string` (via `has_secure_token :token`), `user_id:integer`, and `last_sent_at:datetime`. Expiry is checked via `created_at`-based logic (same as `PasswordReset#expired?`: `created_at < EXPIRY.ago`), not a separate `expires_at` column.

### Signup Flow

- On `UsersController#create`, after saving the user, send a `UserMailer#verify_email` email containing the token link.
- OAuth signups (`OmniauthCallbacksController`) auto-set `email_verified_at = Time.current` — the provider has already verified the address.

### Verification Endpoint

- `GET /email_verifications/:token` — looks up the `EmailVerification` record by token, checks expiry, marks `user.email_verified_at = Time.current`, destroys the token record, redirects to root with a success flash.
- Already-verified users hitting the endpoint get a benign "already verified" redirect.
- Tokens expire after 24 hours (constant on the model, same as `PasswordReset::EXPIRY`).

### Enforcement

- A `VerifiedEmail` concern (module using `extend ActiveSupport::Concern`) is included in `PostsController` and `RepliesController`, consistent with the existing `Bannable` and `RateLimitable` include pattern. It adds a `require_verified_email` before_action on `create` actions only (not `update` — a user who was verified at account creation and later their `email_verified_at` is cleared is an out-of-scope edge case given email change is not yet supported).
- A dismissible banner in the application layout nudges unverified users to check their email. Hidden once verified.

### Resend

- `POST /email_verifications/resend` — rate-limited using `EmailVerification#on_cooldown?` (checks `last_sent_at`, consistent with `PasswordReset#on_cooldown?`). Destroys any existing token and creates a fresh one.

### Routes

```ruby
resources :email_verifications, only: [:show], param: :token do
  collection { post :resend }
end
```

### Edge Cases

- **Email change:** `UsersController#update` does not currently permit `:email`. Clearing `email_verified_at` on email change is out of scope and will be addressed when email-change functionality is added.
- Already-verified users hitting the verification endpoint get a benign redirect with no error.

---

## Phase 2: Two-Factor Authentication (TOTP)

### Dependencies

- `rotp` gem — TOTP generation and verification.
- `rqrcode` gem — QR code rendering for authenticator app enrollment.

### Data Model

- Add `totp_secret:string` to `users` table, stored as an Active Record encrypted attribute (`encrypts :totp_secret`).
- Add a `BackupCode` model with `user_id:integer`, `digest:string`, `used_at:datetime`. Backup codes are stored as bcrypt digests. Add a unique index on `(user_id, digest)` to enforce single-use at the DB level.

### Enrollment Flow

1. User visits the "Two-factor authentication" section of their edit page.
2. Clicking "Enable 2FA" calls `GET /two_factor/setup` — generates a TOTP secret, stores it in the session (not yet persisted), renders a QR code and the plain-text secret for manual entry.
3. User scans the QR code in their authenticator app, then submits the current 6-digit code via `POST /two_factor/setup`.
4. On success: secret is saved to `users.totp_secret`, 8 backup codes are generated, stored as bcrypt digests in `backup_codes`, and shown to the user **once** in plaintext with a prompt to save them.
5. On failure: error message, user must try again (same secret kept in session).

### Login Flow

1. After successful email/password authentication, if `user.totp_secret.present?`, set `session[:awaiting_2fa] = user.id` and redirect to `GET /two_factor/verify` instead of completing login. Do not set `session[:user_id]` yet. **Do not call `LoginThrottle#clear!` at this point** — clearing before 2FA passes would allow an attacker who knows the password to get a fresh 5-attempt window on TOTP repeatedly. `clear!` is deferred to step 5.
2. `TwoFactorController#confirm_verify` checks the throttle first (same `LoginThrottle` keyed by IP) and halts with a `429 Too Many Requests` response if the limit is exceeded, before attempting any TOTP or backup code verification.
3. User submits their 6-digit TOTP code (or a backup code) via `POST /two_factor/verify`.
4. TOTP verification uses a ±1 step drift window (rotp default).
5. **Backup code path:** iterate all unused `BackupCode` records for the user and bcrypt-compare each against the submitted code. On match, consume the code atomically using a pessimistic lock (`BackupCode.lock.find(id)` + update `used_at`) to prevent a race condition where two simultaneous requests pass the bcrypt check before either marks the code used. Timing variation across the set is accepted as a trade-off.
6. On success: call `throttle.clear!` (keyed by IP), clear `session[:awaiting_2fa]`, then set `session[:user_id]` to complete login.
7. On failure: increment `LoginThrottle` counter (keyed by IP, `MAX_ATTEMPTS = 5`, `WINDOW = 10.minutes` — same thresholds as password attempts, intentionally).
8. **OAuth logins bypass 2FA** — the provider is the second factor. `User.from_omniauth` never merges with an existing internal account (matches on `uid` + `provider_id`), so OAuth cannot be used to bypass 2FA on an internal account. This assumption must be revisited if account linking is ever added. Redirecting to `/two_factor/verify` only when `totp_secret` is present does reveal whether a given account has 2FA enabled; this is accepted as a trade-off.
9. `session[:awaiting_2fa]` is cleared by `reset_session` on logout (`SessionsController#destroy` will call `reset_session` instead of `session.delete(:user_id)`).
10. **Session timeout fix:** `ApplicationController#touch_session` only updates `last_active_at` when `session[:user_id]` is present. A user parked at `/two_factor/verify` (with only `session[:awaiting_2fa]`) would never be timed out. Fix: `touch_session` also runs when `session[:awaiting_2fa]` is present. `check_session_timeout` on an `awaiting_2fa`-only session calls `reset_session` and redirects to login (same behavior as a timed-out normal session).

### Disable 2FA

- `DELETE /two_factor` — user must enter their current password to confirm. Clears `totp_secret`, destroys all `BackupCode` records.

### Backup Code Regeneration

- `POST /two_factor/backup_codes` (action: `regenerate_backup_codes`) — requires re-entering current password. Destroys existing backup codes and generates 8 new ones, shown once. Route helper: `two_factor_backup_codes_path`, URL: `/two_factor/backup_codes`.

### Routes

```ruby
resource :two_factor, only: [:destroy] do
  get  :setup,        action: :setup
  post :setup,        action: :confirm_setup
  get  :verify
  post :verify,       action: :confirm_verify
  post :backup_codes, action: :regenerate_backup_codes
end
```

### Security Notes

- TOTP secret encrypted at rest via Rails `encrypts`.
- `session[:awaiting_2fa]` cleared via `reset_session` on logout and on successful verification.
- Backup codes are single-use and hashed with bcrypt; plaintext is never stored. Consumption is atomic via pessimistic lock.
- `LoginThrottle#clear!` called on successful TOTP/backup-code verification.
- Session timeout extended to cover the `awaiting_2fa` state.

---

## Testing

- **Email verification:** unit tests on `EmailVerification` token lifecycle (`expired?`, `on_cooldown?`); controller tests covering unverified-user redirect on `create`, successful verification, expired token, resend cooldown enforcement.
- **2FA enrollment:** controller tests for setup flow (valid TOTP code persists secret + generates backup codes, invalid code re-renders with error).
- **2FA login:** controller tests covering full login with 2FA, wrong code increments throttle, successful verify calls `throttle.clear!`, backup code acceptance, single-use enforcement (second use of same code rejected), OAuth bypass.
- **Disable/regenerate:** controller tests requiring password confirmation, backup code destruction.
- **Session timeout:** unit test confirming `touch_session` runs for `awaiting_2fa` sessions.

---

## Implementation Order

1. **Phase 1:** migration → `EmailVerification` model (`has_secure_token`, `expired?`, `on_cooldown?`) → `UserMailer#verify_email` → `VerifiedEmail` concern (included in `PostsController` + `RepliesController`) → views (banner + resend page)
2. **Phase 2:** add `rotp` + `rqrcode` gems → migrations (`totp_secret` on users, `backup_codes` table) → `TwoFactorController` (setup/confirm_setup/verify/confirm_verify/destroy/regenerate_backup_codes) → update `SessionsController` login flow + `#destroy` → update `touch_session`/`check_session_timeout` for `awaiting_2fa` → views
