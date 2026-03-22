# Session Timeout Design

**Date:** 2026-03-22
**Status:** Approved

## Problem

Users stay logged in forever unless they explicitly log out. There is no session expiration configured.

## Goal

Implement an idle session timeout: if a logged-in user makes no request for `SESSION_TIMEOUT_MINUTES` minutes, their session is expired on the next request.

## Requirements

- Idle timeout — resets on every request, not a fixed absolute TTL
- Configurable via `SESSION_TIMEOUT_MINUTES` ENV var (in minutes), defaulting to `2880` (48 hours)
- Setting `SESSION_TIMEOUT_MINUTES=0` disables timeout entirely
- On expiry for HTML requests: clear session, redirect to login with flash message
- On expiry for Turbo/JSON requests: clear session, return 401
- Applies to both password and OAuth logins

## Approach

Store `session[:last_active_at]` as a Unix integer in the existing Rails cookie session. No database changes required.

## Configuration

`config/initializers/forum_settings.rb`:

```ruby
SESSION_TIMEOUT_MINUTES = ENV.fetch("SESSION_TIMEOUT_MINUTES", 2880).to_i
```

## Implementation

### `ApplicationController`

Two additions:

**`before_action :check_session_timeout`** (only when `logged_in?`):
- Skip if `SESSION_TIMEOUT_MINUTES == 0`
- If `session[:last_active_at]` is absent or older than `SESSION_TIMEOUT_MINUTES` minutes ago:
  - Call `reset_session`
  - Turbo/JSON (`request.format.json? || request.xhr?`): `head :unauthorized`
  - HTML: `redirect_to login_path, alert: "Your session has expired. Please log in again."`

**`after_action :touch_session`** (only when `logged_in?`):
- Sets `session[:last_active_at] = Time.current.to_i`

### Login

No changes needed. `touch_session` fires as an `after_action` on the login response, setting `last_active_at` automatically.

## Testing

File: `test/controllers/sessions_timeout_test.rb`

| Scenario | Setup | Assertion |
|---|---|---|
| Expired session (HTML) | `last_active_at` = timeout + 1 min ago | Redirected to login, session cleared |
| Expired session (Turbo) | `last_active_at` = timeout + 1 min ago, Turbo headers | 401 response |
| Active session | `last_active_at` = 1 min ago | User still logged in, `last_active_at` updated |
| Timeout disabled | `SESSION_TIMEOUT_MINUTES=0` | No expiry regardless of age |
| Unauthenticated request | No session | No-op (before_action skipped) |

## Files Changed

- `config/initializers/forum_settings.rb` — add `SESSION_TIMEOUT_MINUTES`
- `app/controllers/application_controller.rb` — add `check_session_timeout` and `touch_session`
- `test/controllers/sessions_timeout_test.rb` — new test file
