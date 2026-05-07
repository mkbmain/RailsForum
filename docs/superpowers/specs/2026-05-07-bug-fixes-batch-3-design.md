# Bug Fixes Batch 3

**Date:** 2026-05-07

Fixes for 6 bugs identified in a codebase audit (fix #10 was already implemented).

---

## Fix #1 — Token cleanup job

**Problem:** `PasswordReset` and `EmailVerification` records accumulate indefinitely; expired tokens are never removed.

**Solution:** New `CleanExpiredTokensJob < ApplicationJob` with `queue_as :background`. On each run:
- Destroys `PasswordReset` records where `created_at < PasswordReset::EXPIRY.ago` (1 hour)
- Destroys `EmailVerification` records where `created_at < EmailVerification::EXPIRY.ago` (24 hours)

Registered in `config/recurring.yml` under both `production:` and `development:` as `schedule: every hour at minute 30`.

**Files changed:**
- `app/jobs/clean_expired_tokens_job.rb` — new job
- `config/recurring.yml` — add recurring entry

---

## Fix #2 — 2FA throttle (configurable)

**Problem:** TOTP verification in `TwoFactorsController#confirm_verify` uses `LoginThrottle` (IP-keyed, 5 attempts / 10 min), but this doesn't protect against a targeted attack on a specific account's backup codes from multiple IPs.

**Solution:** New `TwoFactorThrottle` class, keyed on user ID from `session[:awaiting_2fa]`. Defaults:
- `MAX_ATTEMPTS = 5` (configurable via `Rails.application.config.x.two_factor_max_attempts`)
- `LOCKOUT_MINUTES = 15` (configurable via `Rails.application.config.x.two_factor_lockout_minutes`)

`confirm_verify` checks both `LoginThrottle` (IP) and `TwoFactorThrottle` (user). On success, clears both. On failure, increments both.

Defaults set in `config/initializers/two_factor_throttle.rb`.

**Files changed:**
- `app/services/two_factor_throttle.rb` — new service
- `config/initializers/two_factor_throttle.rb` — configurable defaults
- `app/controllers/two_factors_controller.rb` — use `TwoFactorThrottle` alongside existing `LoginThrottle`

---

## Fix #4 — Mention regex skips code blocks

**Problem:** `NotificationService` scans `reply.body` with `/@(\w+)/i`, which fires on `@username` patterns inside fenced code blocks (` ```...``` `) and inline code (`` `...` ``), creating spurious mention notifications.

**Solution:** Strip code spans from the body before scanning. In `NotificationService.reply_created`, replace the scan line with:

```ruby
body_without_code = reply.body
  .gsub(/```.*?```/m, "")
  .gsub(/`[^`]*`/, "")
body_without_code.scan(/@(\w+)/i).flatten.uniq.each do |username|
```

No new dependencies. Does not mutate stored content.

**Files changed:**
- `app/services/notification_service.rb`

---

## Fix #5 — Reply soft-delete for users

**Problem:** Users can hard-delete their own replies (`@reply.destroy`), but moderators soft-delete via `removed_at`. This inconsistency means moderation history is lost when a user self-deletes before a mod acts.

**Solution:** The `replies` table already has `removed_at` and `removed_by` columns. Change the user self-delete path in `RepliesController#destroy` to soft-delete:

```ruby
@reply.update!(removed_at: Time.current, removed_by: current_user)
```

Use existing `broadcast_reply_soft_deleted` instead of `broadcast_reply_hard_deleted`. No `NotificationService.content_removed` call — self-removal does not trigger a moderation notification.

The `after_destroy :recalculate_post_last_replied_at` callback stays for cascade deletes (e.g. user account hard-deletion).

**Files changed:**
- `app/controllers/replies_controller.rb`

---

## Fix #7 — NotificationService transaction

**Problem:** `NotificationService.reply_created` calls `Notification.create!` multiple times with no transaction wrapper. A failure midway through (e.g. DB error, validation) leaves some notifications created and others not.

**Solution:** Wrap the entire `reply_created` body in `ActiveRecord::Base.transaction { ... }`. Any `create!` failure rolls back all prior creates in that call.

**Files changed:**
- `app/services/notification_service.rb`

---

## Fix #9 — User bio length limit

**Problem:** `User#bio` has no length validation or DB constraint, allowing arbitrarily large values.

**Solution:**
- Model validation: `validates :bio, length: { maximum: 500 }, allow_blank: true`
- Migration adds a PostgreSQL CHECK constraint: `CHECK (char_length(bio) <= 500)`

**Files changed:**
- `app/models/user.rb`
- New migration: `db/migrate/TIMESTAMP_add_bio_length_constraint_to_users.rb`

---

## Fix #10 — Notification index (already present)

The DB already has `index_notifications_on_user_id_unread`, a partial index on `(user_id) WHERE read_at IS NULL`. The `notifications.unread.count` query is already covered. No action needed.

---

## Testing

Each fix gets focused test coverage:

| Fix | Test location | What to test |
|-----|--------------|--------------|
| #1 | `test/jobs/clean_expired_tokens_job_test.rb` | Cleans expired, keeps unexpired |
| #2 | `test/services/two_factor_throttle_test.rb` | Throttles after N attempts, clears on success, respects config |
| #2 | `test/controllers/two_factors_controller_test.rb` | confirm_verify uses both throttles |
| #4 | `test/services/notification_service_test.rb` | No mention notification for `@user` inside code blocks |
| #5 | `test/controllers/replies_controller_test.rb` | User destroy soft-deletes; reply visible as removed, not gone |
| #7 | `test/services/notification_service_test.rb` | Transaction rollback on create! failure |
| #9 | `test/models/user_test.rb` | Bio over 500 chars fails validation |
