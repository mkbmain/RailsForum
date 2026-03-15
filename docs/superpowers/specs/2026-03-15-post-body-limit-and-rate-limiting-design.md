# Design: Post Body Length Limit & Progressive Rate Limiting

**Date:** 2026-03-15
**Status:** Draft

## Overview

Two features to protect the forum from spam and bot abuse:

1. Enforce a 1000-character limit on post and reply body content at both the database and model layer.
2. Implement a dynamic rate limiter that restricts the number of posts + replies a user can create in a 15-minute window, scaling up based on account age to reward trusted long-term users.

---

## Feature 1: Body Length Limit (Posts and Replies)

Both `posts.body` and `replies.body` are currently unlimited `text` columns. Both will be capped at 1000 characters.

### Approach: DB-level CHECK constraints

Rather than changing the column type (which would require a full table rewrite and `ACCESS EXCLUSIVE` lock on PostgreSQL), length enforcement is added as a `CHECK` constraint on each table. PostgreSQL's own documentation recommends `text` with a `CHECK` constraint over `varchar(n)` — there is no performance difference and the constraint can be added without rewriting the table.

In the `CHECK` constraint, `char_length(body)` counts Unicode code points (characters), which is consistent with Rails' `length` validator that also counts characters by default. The result is functionally equivalent to `nvarchar(1000)` in SQL Server: fully Unicode, 1000-character maximum.

`add_check_constraint` is reversible by default in Rails 6.1+ — no explicit `down` method is needed.

**Migration for posts:**
```ruby
add_check_constraint :posts, "char_length(body) <= 1000", name: "posts_body_max_length"
```

**Migration for replies:**
```ruby
add_check_constraint :replies, "char_length(body) <= 1000", name: "replies_body_max_length"
```

> **Pre-migration data check:** Before running these migrations, verify no existing rows exceed 1000 characters:
> ```sql
> SELECT COUNT(*) FROM posts WHERE char_length(body) > 1000;
> SELECT COUNT(*) FROM replies WHERE char_length(body) > 1000;
> ```
> If any rows are found, truncate or handle them before migrating.

### Model Validations

**Post:**
```ruby
validates :body, presence: true, length: { maximum: 1000 }
```

**Reply:**
```ruby
validates :body, presence: true, length: { maximum: 1000 }
```

The model validation provides a user-friendly error message before the record reaches the database. The DB constraint is a hard safety net. The `posts.title` DB constraint alignment is intentionally out of scope for this feature.

---

## Feature 2: Progressive Rate Limiting

### Goal

Prevent bots and new accounts from spamming. Allow trusted long-term users progressively higher limits. The rate limit window is 15 minutes and counts **posts and replies combined**.

The rate limiter uses live DB queries (two `COUNT` queries per create action). This is simple, accurate, and provides a true sliding window. `solid_cache` was considered but skipped in favour of simplicity — the DB queries are cheap for a forum workload. Under high concurrency two simultaneous requests from the same user could both pass `allowed?` and overshoot the limit by 1; this is an accepted known trade-off at current scale (see Out of Scope).

### Dynamic Limit Formula

Account age is calculated from `user.created_at`.

- `age_in_days = ((Time.current - user.created_at) / 1.day).floor`
- `months_since_creation = (age_in_days / 30).floor`

The limit is determined by:

```ruby
weeks  = [(age_in_days / 7).floor, 4].min          # +1 per completed week, max +4
months = [([months_since_creation - 1, 0].max), 6].min  # +1 per completed month after month 1, max +6
limit  = [5 + weeks + months, 15].min
```

This produces the following table (age_in_days ranges are inclusive):

| age_in_days | weeks bonus | months bonus | limit |
|-------------|-------------|--------------|-------|
| 0–6         | 0           | 0            | 5     |
| 7–13        | 1           | 0            | 6     |
| 14–20       | 2           | 0            | 7     |
| 21–27       | 3           | 0            | 8     |
| 28–59       | 4           | 0            | 9     |
| 60–89       | 4           | 1            | 10    |
| 90–119      | 4           | 2            | 11    |
| 120–149     | 4           | 3            | 12    |
| 150–179     | 4           | 4            | 13    |
| 180–209     | 4           | 5            | 14    |
| 210+        | 4           | 6            | 15    |

Note: the weekly bonus reaches its cap at day 28 (4 complete weeks). The monthly bonus first contributes at day 60 (month 2 complete → `months_since_creation - 1 = 1`, limit 10). Days 28–59 hold at 9 because the weeks bonus is capped at 4 and the months bonus evaluates to 0 (`months_since_creation - 1 = 0` is clamped to 0). The `allowed?` boundary is `activity < limit` (strictly less than).

### Service Object: `PostRateLimiter`

File: `app/services/post_rate_limiter.rb`

**Constructor:** `PostRateLimiter.new(user)` — accepts a persisted `User` ActiveRecord instance.

**Public interface:**

| Method        | Returns                                       |
|---------------|-----------------------------------------------|
| `allowed?`    | `true` if under the limit, `false` otherwise  |
| `limit`       | Integer — the user's current dynamic limit    |
| `remaining`   | Integer — how many more they can post (min 0) |

**Activity count query:**
```ruby
posts_count   = user.posts.where(created_at: 15.minutes.ago..).count
replies_count = user.replies.where(created_at: 15.minutes.ago..).count
activity      = posts_count + replies_count
```

### Controller Integration

`check_rate_limit` must be declared **after** `require_login` in the before-action chain so `current_user` is guaranteed non-nil.

**PostsController** (adds `check_rate_limit` alongside existing `require_login`):
```ruby
before_action :require_login,    only: [:new, :create]
before_action :check_rate_limit, only: [:create]

def check_rate_limit
  limiter = PostRateLimiter.new(current_user)
  unless limiter.allowed?
    flash[:alert] = "You're posting too fast. Limit is #{limiter.limit} posts/replies per 15 minutes."
    redirect_to new_post_path
  end
end
```

**RepliesController** (preserves existing bare `require_login`, adds `check_rate_limit`):
```ruby
before_action :require_login                         # existing — protects all actions
before_action :check_rate_limit, only: [:create]     # new

def check_rate_limit
  limiter = PostRateLimiter.new(current_user)
  unless limiter.allowed?
    flash[:alert] = "You're posting too fast. Limit is #{limiter.limit} posts/replies per 15 minutes."
    redirect_to post_path(params[:post_id])          # returns user to the post they were replying to
  end
end
```

---

## Files Changed / Created

| File | Change |
|------|--------|
| `db/migrate/<timestamp>_limit_post_body_to_1000.rb` | Add CHECK constraint on `posts.body` |
| `db/migrate/<timestamp>_limit_reply_body_to_1000.rb` | Add CHECK constraint on `replies.body` |
| `app/models/post.rb` | Add `length: { maximum: 1000 }` to body validation |
| `app/models/reply.rb` | Add `length: { maximum: 1000 }` to body validation |
| `app/services/post_rate_limiter.rb` | New service object |
| `app/controllers/posts_controller.rb` | Add `check_rate_limit` before_action |
| `app/controllers/replies_controller.rb` | Add `check_rate_limit` before_action |
| `test/services/post_rate_limiter_test.rb` | Unit tests (directory `test/services/` must be created) |

### Test Coverage for `PostRateLimiter`

The test file must cover:
- Day 0 → limit is 5
- Boundary days: 6 (limit 5), 7 (limit 6), 13 (limit 6), 14 (limit 7), 20 (limit 7), 21 (limit 8), 27 (limit 8), 28 (limit 9)
- Boundary days: 59 (limit 9), 60 (limit 10), 89 (limit 10), 90 (limit 11), continuing through 210 (limit 15)
- Day 210+ → limit is capped at 15
- `allowed?` returns `true` when activity count is below limit
- `allowed?` returns `false` when activity count equals or exceeds limit
- `remaining` returns 0 when over limit (does not go negative)

---

## Out of Scope

- Rate limiting does not apply to edits, only creates.
- No admin override or bypass — a future iteration could add a `trusted` flag to users.
- No UI indicator showing users how many posts they have remaining in the window.
- Concurrent request race condition: two simultaneous create requests from the same user can both pass `allowed?` and overshoot the limit by 1. Acceptable at current scale; a future fix would use a DB-level counter or distributed lock.
- `posts.title` DB constraint alignment is not included in this feature.
