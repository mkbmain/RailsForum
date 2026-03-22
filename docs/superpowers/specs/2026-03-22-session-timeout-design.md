# Session Timeout Design

**Date:** 2026-03-22
**Status:** Approved

## Problem

Users stay logged in forever unless they explicitly log out. There is no session expiration configured.

## Goal

Implement an idle session timeout: if a logged-in user makes no request for `session_timeout_minutes` minutes, their session is expired on the next request.

## Requirements

- Idle timeout — resets on every request, not a fixed absolute TTL
- Configurable via `SESSION_TIMEOUT_MINUTES` ENV var (in minutes), defaulting to `2880` (48 hours)
- Setting `SESSION_TIMEOUT_MINUTES=0` disables timeout entirely (also skips writing `last_active_at`)
- On expiry for HTML requests: clear session, redirect to login with flash alert message
- On expiry for Turbo Frame / Turbo Stream / JSON requests: clear session, return 401
- Applies to both password and OAuth logins

## Approach

Store `session[:last_active_at]` as a Unix integer in the existing Rails cookie session. No database changes required.

## Configuration

`config/initializers/forum_settings.rb` (existing file — add alongside `EDIT_WINDOW_SECONDS`):

```ruby
EDIT_WINDOW_SECONDS     = ENV.fetch("EDIT_WINDOW_SECONDS", 3600).to_i
SESSION_TIMEOUT_MINUTES = ENV.fetch("SESSION_TIMEOUT_MINUTES", 2880).to_i
```

## Implementation

### `ApplicationController`

Three additions:

**Private method `session_timeout_minutes`:**
- Returns `SESSION_TIMEOUT_MINUTES`
- Extracted so the value can be overridden in tests without constant reassignment

**`before_action :check_session_timeout`** (runs only when `logged_in?`):
- Skip entirely if `session_timeout_minutes == 0`
- If `session[:last_active_at]` is absent: write `session[:last_active_at] = Time.current.to_i` and return — avoids expiring all existing sessions on first deploy
- If `session[:last_active_at]` is present and `Time.current.to_i - session[:last_active_at] > session_timeout_minutes * 60` (strictly greater than):
  - Set `@current_user = nil` to invalidate the memoized value
  - Call `reset_session` (clears `session[:user_id]`; the cleared session cookie is written to the response automatically by Rails)
  - After both steps, `logged_in?` re-evaluates `current_user` which returns `nil` — `touch_session` will be skipped
  - Detect non-HTML: `turbo_frame_request? || request.format.turbo_stream? || request.format.json?`
    - Non-HTML: `return head :unauthorized` (explicit return required to halt)
    - HTML: `redirect_to login_path, alert: "Your session has expired. Please log in again."` then `return` (explicit return required to halt)

**`after_action :touch_session`** (runs only when `session[:user_id].present?` and `session_timeout_minutes > 0`):
- Guard uses `session[:user_id].present?` (not `logged_in?`) to avoid an extra DB query in the after_action phase
- Sets `session[:last_active_at] = Time.current.to_i`
- After an expiry, `reset_session` clears `session[:user_id]`, so this guard is false and the method is skipped

### Login

No changes needed. `touch_session` fires as an `after_action` on the login response, setting `last_active_at` automatically.

### Deploy Transition

Users with no `last_active_at` in their session (logged in before this feature ships) are treated as active and will not be immediately expired. Their `last_active_at` will be written on their next request.

## Testing

File: `test/controllers/sessions_timeout_test.rb`

All tests inherit from `ActionDispatch::IntegrationTest` (consistent with the rest of the app).

Time simulation uses `travel_to` from Rails' time helpers.

For tests requiring a different timeout value than the default, temporarily reassign the constant in `setup`/`teardown`:

```ruby
setup do
  @original_timeout = SESSION_TIMEOUT_MINUTES
  silence_warnings { Object.const_set(:SESSION_TIMEOUT_MINUTES, 1) } # 1 minute
end

teardown do
  silence_warnings { Object.const_set(:SESSION_TIMEOUT_MINUTES, @original_timeout) }
end
```

Flash messages: the app layout renders both `alert` and `notice` flash keys, so `alert:` is correct.

Expiry boundary: expiry occurs when `Time.current.to_i - session[:last_active_at] > session_timeout_minutes * 60` (strictly greater than). A session exactly at the timeout boundary is still considered active.

| Scenario | Setup | Assertion |
|---|---|---|
| Expired session (HTML) | `last_active_at` = `(timeout * 60) + 1` seconds ago via `travel_to` | Redirected to login with alert, session cleared |
| Expired session (Turbo Frame) | Same, plus `Turbo-Frame` request header | 401 response, session cleared |
| Expired session (Turbo Stream) | Same, `Accept: text/vnd.turbo-stream.html` | 401 response |
| At exact boundary | `last_active_at` = exactly `timeout * 60` seconds ago | User still logged in (not expired) |
| Active session | `last_active_at` = 60 seconds ago | User still logged in; `session[:last_active_at]` updated to within 1 second of `Time.current.to_i` |
| Absent `last_active_at` | Logged in, no `last_active_at` in session | User stays logged in, `last_active_at` written |
| Timeout disabled | `SESSION_TIMEOUT_MINUTES` set to 0 | No expiry regardless of `last_active_at` age; `last_active_at` not written |
| Unauthenticated request | No session | No-op (before_action skipped) |

## Files Changed

- `config/initializers/forum_settings.rb` — add `SESSION_TIMEOUT_MINUTES`
- `app/controllers/application_controller.rb` — add `session_timeout_minutes`, `check_session_timeout`, `touch_session`
- `test/controllers/sessions_timeout_test.rb` — new test file
