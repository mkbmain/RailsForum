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

**Core models:**
- `User` — authenticates via email/password (bcrypt) or OAuth (Google/Microsoft via OmniAuth). `User.from_omniauth` finds/creates from OAuth callback.
- `Post` — belongs to `User` and `Category`. Tracks `last_replied_at` (updated by reply create/destroy callbacks).
- `Reply` — belongs to `Post` and `User`.
- `UserBan` — active ban when `ban_until >= Time.current`. `BanChecker` service checks status.
- `Category`, `BanReason`, `Provider` — lookup/enum tables.

**Controller concerns:**
- `Bannable` — prepend on `PostsController`/`RepliesController`; redirects banned users before create.
- `RateLimitable` — prepend on same controllers; uses `PostRateLimiter` service (dynamic limit: 5–15 posts per 15 min based on account age).

**DB schema:** Uses `db/structure.sql` (not `schema.rb`) — PostgreSQL CHECK constraints enforce 1000-char body limits on posts and replies.

**Tests:** Minitest with fixtures, parallel workers. No system tests in CI (Capybara/Selenium available but disabled in `./bin/ci`).
