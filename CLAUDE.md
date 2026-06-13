# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
# Run full test suite
bin/rails test

# Run a single test file
bin/rails test test/models/user_test.rb

# Run a single test by line number
bin/rails test test/models/user_test.rb:42

# Lint (Rails Omakase style)
./bin/rubocop

# Security audits
./bin/brakeman
./bin/bundler-audit

# Full CI pipeline (lint + security + tests + seed check)
./bin/ci

# Start dev server (Rails + Tailwind watch)
./bin/dev
```

## Architecture

Rails 8.1 forum app using PostgreSQL, Hotwire (Turbo + Stimulus), Tailwind CSS via importmap (no npm).

**DB schema:** Uses `db/structure.sql` (not `schema.rb`) — PostgreSQL CHECK constraints enforce 1000-char body limits on posts and replies. Migrations must be run before seeds.

**Tests:** Minitest with fixtures, parallel workers. No system tests in CI (Capybara/Selenium available but disabled in `./bin/ci`). Set `DB_PASSWORD=postgres` when running tests.

### Models

- `User` — authenticates via email/password (bcrypt) or OAuth (Google/Microsoft via OmniAuth). `User.from_omniauth` finds/creates from OAuth callback. `has_secure_password` with validations disabled manually. `totp_secret` encrypted at rest via Active Record Encryption.
- `Post` — belongs to `User` and `Category`. Tracks `last_replied_at` (updated by reply create/destroy callbacks). Soft-deleted via `removed_at`/`removed_by`.
- `Reply` — belongs to `Post` and `User`. Also soft-deletable.
- `Notification` — polymorphic `notifiable` (Post or Reply). Four `event_type` enum values: `reply_to_post`, `reply_in_thread`, `mention`, `moderation`. Cached unread count per user (2 min TTL).
- `Reaction` — polymorphic `reactionable` (Post or Reply). One per user per content item.
- `Flag` — polymorphic via `flaggable_id` + `content_type_id` FK (not Rails string polymorphism). Uses `ContentType` lookup table for stable numeric FKs.
- `UserBan` — active ban when `ban_until >= Time.current`. `BanChecker` service checks status.
- `Role` / `UserRole` — roles stored in a join table (not an enum column), supporting multiple roles per user. Constants: `Role::CREATOR`, `Role::ADMIN`, `Role::SUB_ADMIN`. The first registered user is auto-assigned creator via `after_create :assign_creator_role`.
- `EmailVerification`, `PasswordReset`, `BackupCode` — one-time token records for their respective flows.
- `Category`, `BanReason`, `Provider`, `ContentType` — lookup/seed tables. `Provider::INTERNAL` identifies email/password users.

### Services (`app/services/`)

- `NotificationService` — all notification fan-out on reply create. Handles reply_to_post, reply_in_thread (24h dedup window per thread to prevent inbox flood), and `@mention` parsing (skips code blocks). Uses `insert_all` for bulk inserts.
- `PostRateLimiter` — dynamic rate limit: 5–15 posts+replies per 15 min, scaling with account age. One place for the algorithm.
- `BanChecker` — thin wrapper to check active ban status, shared between posts and replies.
- `LoginThrottle` / `TwoFactorThrottle` — throttle login and 2FA attempts by IP/user.

### Controller concerns (`app/controllers/concerns/`)

- `Bannable` — **prepended** (not included) on `PostsController`/`RepliesController` so the `before_action` runs before controller callbacks. Redirects banned users.
- `RateLimitable` — **prepended** on same controllers; invokes `PostRateLimiter`.
- `Moderatable` — **included** in `ApplicationController`. Provides `require_moderator`, `require_admin`, and `can_moderate?(user)` (prevents moderating admins or peers of equal rank).
- `VerifiedEmail` — ensures email is verified before certain actions.

### Admin namespace (`app/controllers/admin/`)

All controllers inherit from `Admin::BaseController` which enforces admin access. Routes are at `/admin/`. Covers dashboard stats, user management (promote/demote), category management (with ordering), and flag queue.

### Jobs & Mailers

- `NotificationJob` — async broadcast of Turbo Stream notification updates after reply creation.
- `CleanExpiredTokensJob` — purges stale password reset and email verification tokens.
- `UserMailer` — handles password reset, email verification, and notification emails.

### Frontend (`app/javascript/controllers/`)

Stimulus controllers:
- `dark_mode_controller.js` — toggles `dark` class on `<html>`, persisted in `localStorage`. Applied in `<head>` before render to prevent flash.
- `mention_autocomplete_controller.js` — live `@username` autocomplete in reply boxes.
- `markdown_preview_controller.js` — live Markdown preview for compose forms.

### Key patterns

- **Soft deletion:** Posts and replies are never hard-deleted by moderators. `removed_at` + `removed_by` are set; content is hidden but the record persists for audit trail and potential restore.
- **Session timeout:** Enforced in `ApplicationController` (not rack). `last_active_at` written to session each request; expired sessions are cleared with a user-facing redirect. Turbo/JSON requests get `401` instead.
- **Dark mode:** `darkMode: 'class'` strategy in Tailwind config. State in `localStorage`, not OS preference.
- **Roles as table:** Extensible without migrations; supports multiple roles per user. Use `user.moderator?` (sub_admin or admin), `user.admin?`, `user.creator?`.
- **Notification dedup:** `reply_in_thread` events have a 24h per-thread window — checked via a query before bulk-inserting.

### Key environment variables

| Variable | Description |
|---|---|
| `DB_PASSWORD` | PostgreSQL password (`postgres` in local dev/test) |
| `EDIT_WINDOW_SECONDS` | How long users can edit posts/replies (default: 3600) |
| `SESSION_TIMEOUT_MINUTES` | Idle timeout (default: 2880 = 48h; 0 = disabled) |
| `GOOGLE_CLIENT_ID/SECRET` | OAuth — leave blank to hide Google login button |
| `MICROSOFT_CLIENT_ID/SECRET` | OAuth — leave blank to hide Microsoft login button |
