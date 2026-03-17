# Design: Search, User Profiles, Notifications, Post Reactions

**Date:** 2026-03-17
**Status:** Approved

---

## Overview

Add four features to the Rails 8.1 forum app: full-text post search, editable user profiles, in-app notifications, and emoji post reactions. All features use existing Hotwire/Turbo infrastructure. Reactions and the notification badge use Turbo Frames/Drive for a responsive feel without real-time WebSocket complexity.

---

## Data Model

### `users.bio`
Add a nullable `text` column `bio` to the existing `users` table.

### `reactions`
| Column | Type | Notes |
|--------|------|-------|
| `id` | bigint PK | |
| `user_id` | bigint FK → users | reactor |
| `post_id` | bigint FK → posts | |
| `emoji` | varchar(10) | constrained to allowed set in app layer |
| `created_at` | timestamp | |
| `updated_at` | timestamp | required — Rails sets this on `update!` |

**Unique index on `(user_id, post_id)`** — one reaction per user per post. User picks which emoji; changing it updates the existing row; removing it deletes it.

**Upsert logic:** use `Reaction.upsert({ user_id:, post_id:, emoji: }, unique_by: [:user_id, :post_id])` — a single `INSERT ... ON CONFLICT DO UPDATE` statement that is safe under concurrent requests. Do not use `find_or_initialize_by` + `update!`, which is two queries and subject to a race condition under concurrent requests.

### `notifications`
| Column | Type | Notes |
|--------|------|-------|
| `id` | bigint PK | |
| `user_id` | bigint FK → users | recipient |
| `actor_id` | bigint FK → users | who triggered the event |
| `notifiable_type` | varchar | polymorphic — `"Post"` or `"Reply"` |
| `notifiable_id` | bigint | polymorphic ID |
| `event_type` | smallint | enum (see below) |
| `read_at` | timestamp, nullable | null = unread |
| `created_at` | timestamp | |
| `updated_at` | timestamp | |

**Partial index on `(user_id) WHERE read_at IS NULL`** — efficient unread count queries; small because only unread rows are indexed.

**Index on `(user_id, notifiable_id, notifiable_type, event_type, created_at)`** — supports the 24-hour deduplication query for `reply_in_thread` notifications.

**`event_type` enum:**
- `0` — `reply_to_post` — someone replied to a post you own
- `1` — `reply_in_thread` — someone replied in a thread you've participated in
- `2` — `mention` — someone @mentioned you
- `3` — `moderation` — a moderator removed your post or reply

---

## Routes

The existing `resources :users, only: []` block (used for bans nesting) is merged into a single declaration:

```ruby
# Search
get "/search", to: "search#index"

# Users — merge existing bans nesting with new profile actions
resources :users, only: [:show, :edit, :update] do
  resources :bans, only: [:new, :create]
end

# Notifications
resources :notifications, only: [:index] do
  collection { patch :read_all }
  member     { patch :read }
end
# Note: member :read generates /notifications/:id/read
# Path helper: read_notification_path(@notification)

# Posts — merge replies and new reactions nesting
resources :posts do
  resources :reactions, only: [:create, :destroy]
  resources :replies,   only: [:create, :destroy, :edit, :update]
end
```

---

## Controllers

### `SearchController#index`
- Accepts `q` (query string), `category` (optional filter), `page`, `take`
- Scoped to `Post.visible` — removed posts never appear in results
- Query: `Post.visible.where("title ILIKE :q OR body ILIKE :q", q: "%#{params[:q]}%")`
- The named bind parameter handles SQL injection safety. User-supplied `%` or `_` within the query string are treated as ILIKE pattern wildcards — accepted behaviour, no escaping applied.
- Paginates with the same `limit`/`offset` pattern as `PostsController#index`
- Renders results in the same post-card style as the index feed

### `UsersController` — new actions
- **`show`** — public profile: avatar/initials, name, bio, join date, post/reply counts, recent activity feed (posts + replies, chronological descending, paginated 20 per page)
- **`edit`** / **`update`** — own profile only, enforced by `before_action :require_owner`
- Editable fields: `name`, `bio`
- Password change: rendered and processed only for `user.internal?` (i.e. `Provider::INTERNAL`). OAuth users never see this section.

**Password change update logic:**
- All params are submitted under the `user` key. Permitted via `params.require(:user).permit(:name, :bio, :current_password, :password, :password_confirmation)`
- `current_password` is not an Active Record attribute — read it via `user_params[:current_password]` separately from the attributes passed to `update`
- If `user_params[:password].present?`:
  - Call `@user.authenticate(user_params[:current_password])` — if false, add error `"Current password is incorrect"` to `@user` and re-render edit with status 422
  - If authentication passes, update with `name`, `bio`, `password`, `password_confirmation`
- If `password` is blank, update only `name` and `bio`
- Avatar stays read-only

### `NotificationsController`
- **`index`** — paginated list of `current_user`'s notifications, newest first. Read/unread state shown visually; marking happens via explicit actions only.
- **`read`** (`PATCH /notifications/:id/read`) — sets `read_at = Time.current` on a single notification scoped to `current_user`
- **`read_all`** (`PATCH /notifications/read_all`) — sets `read_at = Time.current` on all unread notifications for `current_user`

All actions require login.

### `ReactionsController`
- **`create`** — validates emoji is in `Reaction::ALLOWED_REACTIONS`, returns 422 if not. Upserts via `Reaction.upsert({ user_id: current_user.id, post_id: @post.id, emoji: params[:emoji] }, unique_by: [:user_id, :post_id])`. Responds with Turbo Stream replacing the reactions Turbo Frame.
- **`destroy`** — finds reaction by `params[:id]`, scoped to `current_user` and `@post` for authorization (`@post.reactions.find_by!(id: params[:id], user_id: current_user.id)`), then destroys it. Returns 404 if not found. Same Turbo Stream response.
- Requires login. Users can only destroy their own reactions.

---

## Notification Logic

### `NotificationService`

A standalone service class. Called from controllers, not model callbacks, to keep models free of cross-cutting concerns and to make tests straightforward.

Designed as a clean boundary — in future, callers can publish to an event bus (e.g. RabbitMQ) instead of calling the service directly, with no other changes required.

**Interface:**
```ruby
NotificationService.reply_created(reply, current_user:)
NotificationService.content_removed(content, removed_by:)
```

**`reply_created(reply, current_user:)` fan-out — executed in this order:**

1. **reply_to_post** — collect: `reply.post.user`, unless they are the actor. Create notification.

2. **reply_in_thread** — collect: all distinct users who have previously replied to `reply.post`, then exclude:
   - the actor
   - users already notified in step 1 (post owner)
   - users already sent a `reply_in_thread` notification for this post within the last 24 hours
   The deduplication query filters on `(user_id, notifiable_id, notifiable_type, event_type, created_at)`.

3. **mention** — scan `reply.body` for `/@(\w+)/i`, look up each match via `User.where("LOWER(name) = LOWER(?)", match)`, then exclude:
   - the actor
   - users already notified in steps 1 or 2

**`content_removed(content, removed_by:)` — moderation:**
- Notify `content.user` with `event_type: :moderation`, `actor: removed_by`
- Guard: skip if `content.user == removed_by` (self-notification)
- If a moderator removes their own content, the guard silently no-ops — this is intentional
- Note: if a moderator is also the content's author, the moderator branch of `RepliesController#destroy` still fires `content_removed`, but the self-notification guard prevents any notification from being created

**Global rule:** never create a notification where `user_id == actor_id`.

### Trigger points
- `RepliesController#create` (after successful save) → `NotificationService.reply_created(@reply, current_user: current_user)`
- `PostsController#destroy` → `NotificationService.content_removed(@post, removed_by: current_user)`
- `RepliesController#destroy` — moderator soft-delete path only → `NotificationService.content_removed(@reply, removed_by: current_user)`. Owner self-delete path does NOT trigger a notification.

---

## UI & Views

### Nav bar
- Search form (text input + submit) visible on all pages
- Bell icon with unread count badge rendered server-side on every page visit via Turbo Drive. No polling or WebSocket needed.

### Search results (`search/index.html.erb`)
- Same post-card style as `posts/index`
- Body excerpt showing matched text (truncated)
- "N results for 'query'" heading
- Category filter and query string carried through pagination links
- Empty state if no results

### User profile (`users/show.html.erb`)
- Header: avatar/initials, name, bio, join date, post count, reply count
- Activity feed: combined list of user's posts and replies, chronological descending, paginated 20 per page
- Each item links to the relevant post

### Edit profile (`users/edit.html.erb`)
- Fields: name, bio (textarea)
- Password section (internal users only, `user.internal?`): current password, new password, confirmation
- Save button

### Notifications (`notifications/index.html.erb`)
- "Mark all read" button (top right, only shown if unread exist)
- List items: actor avatar/initials, description (e.g. "Alice replied to your post"), link to post, time ago
- Unread items: subtle background highlight
- Paginated

### Post reactions (`posts/show.html.erb`)
- Below post body, above replies section
- `<turbo-frame id="post_reactions_<post_id>">` wrapping a row of emoji buttons
- Each button: emoji + count. Highlighted if current user has reacted with it.
- Clicking a highlighted button → DELETE (remove reaction)
- Clicking an unhighlighted button → POST (add/replace reaction via upsert)
- Logged-out users see counts but no interactive buttons

---

## Allowed Emoji Set

Defined as a constant on the `Reaction` model:

```ruby
ALLOWED_REACTIONS = %w[👍 ❤️ 😂 😮].freeze
```

Validated in the `Reaction` model. Controller returns 422 if emoji is not in the set.

---

## Testing

Follow existing Minitest + fixtures pattern.

- **`ReactionTest`** — model validations, unique constraint (one per user per post), allowed emoji validation
- **`NotificationTest`** — model validations, `read?` helper
- **`NotificationServiceTest`** — reply_to_post fan-out, reply_in_thread fan-out + 24hr dedup, no double-notification for post owner who is also a thread participant, mention parsing, self-notification guard, moderation event, moderator-removes-own-content no-op
- **`SearchControllerTest`** — results returned, scoped to visible posts only, category filter, pagination, empty state
- **`UsersControllerTest`** — show (public), edit/update (own only, 401 for others), password change (internal only, wrong current password rejected, OAuth user cannot change password), bio update
- **`NotificationsControllerTest`** — index (auth required), read, read_all, cannot mark others' notifications
- **`ReactionsControllerTest`** — create, destroy (by params[:id] scoped to current_user), upsert (emoji change updates row), auth required, cannot destroy others' reactions, invalid emoji rejected

---

## Out of Scope

- Email notifications (in-app only)
- Reactions on replies (posts only)
- Search within replies
- Real-time WebSocket push for notifications or reactions
- User-configurable notification preferences
- Avatar upload (read-only; sourced from OAuth or rendered as initials)
