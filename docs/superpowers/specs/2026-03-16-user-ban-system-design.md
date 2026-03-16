# User Ban System Design

**Date:** 2026-03-16
**Status:** Approved

## Overview

Add a user ban system that prevents banned users from creating posts or replies until their ban expires. Bans are managed directly in PostgreSQL by the site administrator. A full audit trail of all bans is kept.

---

## Database

### `ban_reasons` table

Lookup table of predefined ban reasons.

| Column | Type | Constraints |
|---|---|---|
| id | integer | PK |
| name | string | not null, unique |
| created_at | datetime | not null |
| updated_at | datetime | not null |

Seeded with: `Spam`, `Harassment`, `Against Guidelines`.

### `user_bans` table

One row per ban issued. Multiple bans per user are allowed, providing a full audit trail.

| Column | Type | Constraints |
|---|---|---|
| id | integer | PK |
| user_id | integer | not null, FK → users |
| ban_reason_id | integer | not null, FK → ban_reasons |
| banned_from | datetime | not null, defaults to now() |
| banned_until | datetime | not null |
| created_at | datetime | not null |
| updated_at | datetime | not null |

Index on `(user_id, banned_until)` for fast active-ban lookups.

A ban is **active** when `banned_until >= Time.current`. Bans are not expected to have future start dates, so `banned_from` is always set to the time the ban is created.

---

## Models

### `BanReason`
- `validates :name, presence: true, uniqueness: true`

### `UserBan`
- `belongs_to :user`
- `belongs_to :ban_reason`
- `validates :banned_from, :banned_until, presence: true`
- Validates `banned_until > banned_from`

### `User`
- Gains `has_many :user_bans`

---

## Service: `BanChecker` (`app/services/ban_checker.rb`)

Mirrors the existing `PostRateLimiter` pattern.

```ruby
class BanChecker
  def initialize(user)
    @user = user
  end

  def banned?
    active_ban.present?
  end

  def banned_until
    active_ban&.banned_until
  end

  private

  def active_ban
    @active_ban ||= @user.user_bans
                         .where("banned_until >= ?", Time.current)
                         .order(banned_until: :desc)
                         .first
  end
end
```

When multiple overlapping bans exist, the one expiring latest is used so the displayed date is always accurate.

---

## Controller Concern: `Bannable` (`app/controllers/concerns/bannable.rb`)

Mirrors the existing `RateLimitable` pattern.

```ruby
module Bannable
  extend ActiveSupport::Concern

  private

  def check_not_banned
    checker = BanChecker.new(current_user)
    if checker.banned?
      flash[:alert] = "You are banned until #{checker.banned_until.strftime("%B %d, %Y")}."
      redirect_to ban_redirect_path
    end
  end

  def ban_redirect_path
    root_path
  end
end
```

### `PostsController`
- `include Bannable`
- `before_action :check_not_banned, only: [:create]`
- Overrides `ban_redirect_path` to return `new_post_path`

### `RepliesController`
- `include Bannable`
- `before_action :check_not_banned, only: [:create]`

---

## Seeds

`db/seeds.rb` gains:

```ruby
["Spam", "Harassment", "Against Guidelines"].each do |name|
  BanReason.find_or_create_by!(name: name)
end
```

Uses `find_or_create_by!` so re-running seeds is idempotent.

---

## What Is Out of Scope

- Admin panel for issuing bans (managed directly in PostgreSQL)
- Banning users from reading content
- Permanent (no-expiry) bans
