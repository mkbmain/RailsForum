# Content Reporting / Flagging — Design Spec

**Date:** 2026-03-21
**Status:** Approved

## Overview

Users can flag posts or replies for moderator review by choosing a reason from a fixed list. Moderators (admins and sub-admins) review pending flags in a dedicated admin queue and dismiss them once reviewed. Flag dismissal links to the existing content-removal and ban tools rather than duplicating them.

---

## Data Model

### `content_types` lookup table

Mirrors the `categories` / `providers` pattern (smallint id, varchar name, no timestamps — not `ban_reasons`, which has timestamps).

| column | type | notes |
|--------|------|-------|
| `id` | smallint PK | 1 = Post, 2 = Reply |
| `name` | varchar(50) | |

Seeded via `INSERT` in the migration (not `seeds.rb`).

### `flags` table

`id` is `int` (deliberate — not bigint). Use `id: :integer` in the `create_table` call to override Rails' bigint default. All FK columns targeting `users` use `bigint` to match the users PK.

| column | type | notes |
|--------|------|-------|
| `id` | int PK | `id: :integer` in migration |
| `user_id` | bigint FK → users | who flagged |
| `content_type_id` | smallint FK → content_types | 1 = Post, 2 = Reply |
| `flaggable_id` | bigint | id of the flagged Post or Reply |
| `reason` | smallint | enum: 0=spam, 1=harassment, 2=misinformation, 3=other |
| `resolved_at` | timestamp | null = pending; set on dismiss |
| `resolved_by_id` | bigint FK → users | null until dismissed |
| `created_at` / `updated_at` | timestamps | |

### Indexes

- Unique `(user_id, content_type_id, flaggable_id)` — one flag per user per content item, **regardless of reason**. A user cannot flag the same post/reply twice even with a different reason.
- `(content_type_id, flaggable_id)` — count flags on a piece of content
- Partial `(created_at) WHERE resolved_at IS NULL` — pending queue scan

---

## Models

### `ContentType`

Follows the `Provider` pattern (`self.primary_key = :id` required for smallint-keyed tables).

```ruby
class ContentType < ApplicationRecord
  self.primary_key = :id

  CONTENT_POST  = 1
  CONTENT_REPLY = 2
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

  validates :flaggable_id,    presence: true
  validates :content_type_id, presence: true,
                              inclusion: { in: [ContentType::CONTENT_POST, ContentType::CONTENT_REPLY] }
  validates :user_id, uniqueness: { scope: [:content_type_id, :flaggable_id],
                                    message: "has already flagged this content" }

  # Resolves the flagged record. Not an AR association — used directly in views/controllers.
  # Returns nil if the content has been hard-deleted.
  # Returns the record (possibly soft-deleted) if it still exists.
  def flaggable
    case content_type_id
    when ContentType::CONTENT_POST  then Post.find_by(id: flaggable_id)
    when ContentType::CONTENT_REPLY then Reply.find_by(id: flaggable_id)
    end
  end
end
```

### `Post` and `Reply`

Each gains a manual `has_many :flags` scoped by `content_type_id`. `class_name: "Flag"` is explicit for clarity. Used for `dependent: :destroy` only — flag resolution in the admin queue goes through `Flag#flaggable`, not through these associations.

```ruby
# Post
has_many :flags, -> { where(content_type_id: ContentType::CONTENT_POST) },
         class_name: "Flag", foreign_key: :flaggable_id, dependent: :destroy

# Reply
has_many :flags, -> { where(content_type_id: ContentType::CONTENT_REPLY) },
         class_name: "Flag", foreign_key: :flaggable_id, dependent: :destroy
```

---

## Routes

```ruby
resources :posts do
  resources :flags, only: [:create]            # POST /posts/:post_id/flags
  resources :replies, only: [...] do
    resources :flags, only: [:create]          # POST /posts/:post_id/replies/:reply_id/flags
  end
end

namespace :admin do
  resources :flags, only: [:index] do
    member { patch :dismiss }                  # PATCH /admin/flags/:id/dismiss
  end
end
```

Three-level nesting for reply flags is a deliberate match of the existing `ReactionsController` pattern in this codebase.

---

## Controllers

### `FlagsController`

- `create` — requires login. Mirrors the `ReactionsController#set_reactionable` pattern for lookups:
  - If `params[:reply_id]` is present:
    - `content_type_id = ContentType::CONTENT_REPLY`
    - `@post = Post.visible.find(params[:post_id])`
    - `flaggable = @post.replies.visible.find_by(id: params[:reply_id])`
  - Otherwise:
    - `content_type_id = ContentType::CONTENT_POST`
    - `flaggable = Post.visible.find(params[:post_id])`
  - Scoping reply through its parent post prevents cross-post flag requests, consistent with `ReactionsController`.
  - If `flaggable` is nil (soft-deleted or missing), redirect back with alert "Content not found."
  - Builds and saves a `Flag`. On duplicate (uniqueness failure), redirect back with alert "You've already flagged this content."
  - On success: `redirect_back(fallback_location: post_path(params[:post_id]), allow_other_host: false)` with notice "Content reported."
- No `destroy` action — users cannot un-flag.

### `Admin::FlagsController < Admin::BaseController`

- `index` — loads pending queue with `params[:page]` (integer, min 1) for pagination, 20 per page, limit+1 trick:
  ```ruby
  flags = Flag.pending.includes(:user, :content_type)
                      .order(created_at: :asc)
                      .limit(21).offset((page - 1) * 20)
                      .to_a
  ```
  After the query, avoid N+1 by building a composite-keyed lookup hash for the flaggable records. Because `Flag#flaggable` is a manual method (not an AR association), `ActiveRecord::Associations::Preloader` cannot be used here. Keys are `[content_type_id, flaggable_id]` pairs to avoid collision between a `Post` and a `Reply` that share the same integer id:
  ```ruby
  post_flaggable_ids  = flags.select { |f| f.content_type_id == ContentType::CONTENT_POST }.map(&:flaggable_id)
  reply_flaggable_ids = flags.select { |f| f.content_type_id == ContentType::CONTENT_REPLY }.map(&:flaggable_id)

  @flaggables = {}
  Post.where(id: post_flaggable_ids).each do |r|
    @flaggables[[ContentType::CONTENT_POST, r.id]] = r
  end
  Reply.where(id: reply_flaggable_ids).includes(:post).each do |r|
    @flaggables[[ContentType::CONTENT_REPLY, r.id]] = r
  end
  ```
  Pass `@flaggables` to the view; each row renders `@flaggables[[flag.content_type_id, flag.flaggable_id]]`.
  - The view uses `@flaggables[[flag.content_type_id, flag.flaggable_id]]` for each flag. Three states:
    - `nil` — hard-deleted: show "[content removed]", no link
    - `flaggable.removed?` — soft-deleted: show body with "[removed]" badge, link to post
    - live: show truncated body, link to post (with `#reply-{id}` anchor for replies)
- `dismiss` — uses `Flag.find_by(id: params[:id])` with a nil guard. If not found or already resolved (`resolved_at` present), redirect back with notice "Already resolved." Otherwise sets `resolved_at: Time.current` and `resolved_by: current_user`, redirect to admin flags path with notice "Flag dismissed."

Both roles (`admin?` and `sub_admin?`) have access via the inherited `require_moderator` before-action.

---

## User-Facing UI

### Flag button (post show page + reply partial)

- Shown to logged-in users who have not yet flagged that item. **Not shown on soft-deleted (removed) content** — consistent with the controller rejecting flags on invisible content.
- Hidden from logged-out users.
- A `<details>`/`<summary>` dropdown containing 4 reason radio buttons (Spam, Harassment, Misinformation, Other) and a Submit button.
- If the user has already flagged: button replaced with a disabled "Flagged ✓" indicator.
- Uses a standard Rails `form_with` POST — no Turbo streams needed.

---

## Admin UI

### `/admin/flags` queue

- Table of pending flags: content type badge (Post/Reply), truncated content snippet with removed state handled (see controller section), reporter name, reason, time ago, link to content, Dismiss button.
- The Dismiss button must be a `button_to` (renders as a `<form>` with `method: :patch`) — not a plain link — to include the CSRF token.
- "Pending Reports" count shown on the admin dashboard alongside existing stats, with a link to `/admin/flags`.
- Empty state: "No pending reports."
- Pagination: `params[:page]`-based, standard limit+1 next/prev links.

---

## Testing

### `test/models/flag_test.rb`
- Uniqueness: second flag from same user on same content is invalid (regardless of reason)
- `content_type_id` presence and inclusion validation
- Enum values for all 4 reasons
- `flaggable` resolves to correct `Post` or `Reply`
- `flaggable` returns `nil` when content has been hard-deleted
- `flaggable` returns the soft-deleted record when content has been soft-deleted
- `pending` / `resolved` scopes

### `test/controllers/flags_controller_test.rb`
- Create succeeds for logged-in user on a post
- Create succeeds for logged-in user on a reply
- Reply flag is scoped to its parent post (cross-post attempt returns 404)
- Duplicate flag redirects with alert
- Flagging soft-deleted content redirects with alert "Content not found"
- Logged-out user is redirected to login
- Flagging own content is permitted

### `test/controllers/admin/flags_controller_test.rb`
- Queue visible to admin and sub_admin
- Queue hidden from regular users (redirected)
- Dismiss sets `resolved_at` and `resolved_by_id`
- Dismiss on already-resolved flag redirects with "Already resolved"
- Dismiss on missing flag redirects with "Already resolved"
- Dismiss by non-moderator is rejected

### Fixtures
- `content_types.yml` — rows with explicit `id:` values: Post (1) and Reply (2). Reference from other fixtures by hardcoded integer (e.g. `content_type_id: 1`), matching the `providers` fixture convention.
- `flags.yml` — pending and resolved examples covering both content types and all reasons
