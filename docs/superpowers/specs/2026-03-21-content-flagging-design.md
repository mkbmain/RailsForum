# Content Reporting / Flagging — Design Spec

**Date:** 2026-03-21
**Status:** Approved

## Overview

Users can flag posts or replies for moderator review by choosing a reason from a fixed list. Moderators (admins and sub-admins) review pending flags in a dedicated admin queue and dismiss them once reviewed. Flag dismissal links to the existing content-removal and ban tools rather than duplicating them.

---

## Data Model

### `content_types` lookup table

Mirrors the `categories` / `providers` pattern — `smallint` id, no timestamps.

| column | type | notes |
|--------|------|-------|
| `id` | smallint PK | 1 = Post, 2 = Reply |
| `name` | varchar(50) | |

Seeded at migration time (not via `seeds.rb`).

### `flags` table

| column | type | notes |
|--------|------|-------|
| `id` | int PK | |
| `user_id` | bigint FK → users | who flagged |
| `content_type_id` | smallint FK → content_types | 1 = Post, 2 = Reply |
| `flaggable_id` | bigint | id of the flagged Post or Reply |
| `reason` | smallint | enum: 0=spam, 1=harassment, 2=misinformation, 3=other |
| `resolved_at` | timestamp | null = pending; set on dismiss |
| `resolved_by_id` | bigint FK → users | null until dismissed |
| `created_at` / `updated_at` | timestamps | |

### Indexes

- Unique `(user_id, content_type_id, flaggable_id)` — one flag per user per content item
- `(content_type_id, flaggable_id)` — count flags on a piece of content
- Partial `(created_at) WHERE resolved_at IS NULL` — pending queue scan

---

## Models

### `ContentType`

```ruby
class ContentType < ApplicationRecord
  CONTENT_POST  = 1
  CONTENT_REPLY = 2
  self.table_name = "content_types"
end
```

### `Flag`

```ruby
class Flag < ApplicationRecord
  belongs_to :user
  belongs_to :content_type
  belongs_to :resolved_by, class_name: "User", optional: true

  enum :reason, { spam: 0, harassment: 1, misinformation: 2, other: 3 }

  scope :pending,  -> { where(resolved_at: nil) }
  scope :resolved, -> { where.not(resolved_at: nil) }

  validates :flaggable_id, presence: true
  validates :user_id, uniqueness: { scope: [:content_type_id, :flaggable_id],
                                    message: "has already flagged this content" }

  def flaggable
    case content_type_id
    when ContentType::CONTENT_POST  then Post.find_by(id: flaggable_id)
    when ContentType::CONTENT_REPLY then Reply.find_by(id: flaggable_id)
    end
  end
end
```

### `Post` and `Reply`

Each gains a manual `has_many :flags` scoped by `content_type_id` (not Rails polymorphic, since `flaggable_type` is a smallint FK):

```ruby
# Post
has_many :flags, -> { where(content_type_id: ContentType::CONTENT_POST) },
         foreign_key: :flaggable_id, dependent: :destroy

# Reply
has_many :flags, -> { where(content_type_id: ContentType::CONTENT_REPLY) },
         foreign_key: :flaggable_id, dependent: :destroy
```

---

## Routes

```ruby
resources :posts do
  resources :flags, only: [:create]           # POST /posts/:post_id/flags
  resources :replies, only: [...] do
    resources :flags, only: [:create]         # POST /posts/:post_id/replies/:reply_id/flags
  end
end

namespace :admin do
  resources :flags, only: [:index] do
    member { patch :dismiss }                 # PATCH /admin/flags/:id/dismiss
  end
end
```

---

## Controllers

### `FlagsController`

- `create` — requires login. Determines `content_type_id` from params (post-level vs reply-level route). Builds and saves a `Flag`. On duplicate, redirects back with an alert "You've already flagged this content." On success, redirects back with notice "Content reported."
- No `destroy` action — users cannot un-flag.

### `Admin::FlagsController < Admin::BaseController`

- `index` — pending queue (`Flag.pending.includes(:user, :content_type).order(created_at: :asc)`), paginated (20 per page, limit+1 trick). Eager-loads flaggable via `ActiveRecord::Associations::Preloader` per type (same pattern as `NotificationsController`).
- `dismiss` — finds flag, sets `resolved_at: Time.current` and `resolved_by: current_user`, redirects back to queue with notice.

Both roles (`admin?` and `sub_admin?`) have access via the inherited `require_moderator` before-action.

---

## User-Facing UI

### Flag button (post show page + reply partial)

- Shown to logged-in users who have not yet flagged that item. Hidden from logged-out users.
- A `<details>`/`<summary>` dropdown containing 4 reason radio buttons (Spam, Harassment, Misinformation, Other) and a Submit button.
- If the user has already flagged: button replaced with a disabled "Flagged ✓" indicator.
- Uses a standard Rails `form_with` POST — no Turbo streams needed.

---

## Admin UI

### `/admin/flags` queue

- Table of pending flags: content type badge (Post/Reply), truncated content snippet, reporter name, reason, time ago, link to content, Dismiss button.
- "Pending Reports" count shown on the admin dashboard alongside existing stats, with a link to `/admin/flags`.
- Empty state: "No pending reports."
- Pagination: standard limit+1 next/prev links.

---

## Testing

### `test/models/flag_test.rb`
- Uniqueness: second flag from same user on same content is invalid
- Enum values for all 4 reasons
- `flaggable` resolves to correct `Post` or `Reply`
- `pending` / `resolved` scopes

### `test/controllers/flags_controller_test.rb`
- Create succeeds for logged-in user
- Duplicate flag returns redirect with alert
- Logged-out user is redirected to login
- Flagging own content is permitted

### `test/controllers/admin/flags_controller_test.rb`
- Queue visible to admin and sub_admin
- Queue hidden from regular users (redirected)
- Dismiss sets `resolved_at` and `resolved_by_id`
- Dismiss by non-moderator is rejected

### Fixtures
- `content_types.yml` — rows for Post (1) and Reply (2)
- `flags.yml` — pending and resolved examples covering both content types and all reasons
