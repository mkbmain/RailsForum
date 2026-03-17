# Correctness Improvements Design
**Date:** 2026-03-17
**Scope:** Bug fixes + light refactor across Notification model, notifications view, search pagination, and reactions controller

---

## Overview

Four targeted correctness fixes with small model helpers where they prevent recurrence. No migrations, no new controllers, no performance work. Scale is not a concern (single user).

---

## Section 1 — Notification Model

**Problem:** No convenience API; raw `where(read_at: nil)` is duplicated across the controller and will be duplicated again anywhere that needs unread counts. The `read` action in the controller calls `update` directly rather than through a meaningful method.

**Fix:** Add two scopes and one instance method to `app/models/notification.rb`:

```ruby
scope :unread, -> { where(read_at: nil) }
scope :read,   -> { where.not(read_at: nil) }

def mark_as_read!
  update!(read_at: Time.current) unless read?
end
```

- `unread` / `read` replace all raw `where(read_at: nil)` calls going forward
- `mark_as_read!` is idempotent — safe to call even if already read, no unnecessary write

The existing controller already has two raw `where(read_at: nil)` calls (lines 9 and 19 of `notifications_controller.rb`) and uses `update` directly in the `read` action. These are updated as part of this section to use the new scopes and method — otherwise the problem of duplicated raw queries is not actually resolved, just given a parallel API.

**Controller changes:**
- `@unread_count` line: `current_user.notifications.unread.count`
- `read_all` action: `current_user.notifications.unread.update_all(read_at: Time.current)`
- `read` action: `notification&.mark_as_read!`

---

## Section 2 — Notification `target_post` Helper + View Fix

**Problem:** The notifications index view contains inline `is_a?` logic to resolve the link target:

```erb
<% post_link = n.notifiable.is_a?(Post) ? post_path(n.notifiable) : post_path(n.notifiable.post) %>
```

This is fragile — it leaks knowledge of the notifiable inconsistency (some notifications store a `Reply`, others store a `Post`) into the view. If a third notifiable type is added, every view that does this check breaks.

**Fix:** Add a `target_post` method to `Notification`:

```ruby
def target_post
  case notifiable
  when Post  then notifiable
  when Reply then notifiable.post
  else raise "Unknown notifiable type for target_post: #{notifiable.class}"
  end
end
```

The `else` raises a descriptive error rather than returning `nil`. Passing `nil` to `post_path` would raise an opaque `ActionController::UrlGenerationError`; a descriptive raise makes the failure obvious at the point of introduction of a new notifiable type.

Update the view to use it:

```erb
<% post_link = post_path(n.target_post) %>
```

This centralises the polymorphic resolution in the model where it belongs. The view becomes declarative.

**Note on eager loading:** The existing `includes(:actor, :notifiable)` does not preload `notifiable.post` for Reply notifiables. This is a known N+1 but deferred — not a correctness bug at current scale. `target_post` does not make this worse.

---

## Section 3 — Search Pagination Probe

**Problem:** The search controller loads exactly `@take` records and the view detects a next page with:

```erb
<% if @posts.size >= @take %>
```

When the last page has exactly `@take` results, this condition is true and "Next →" is shown, leading the user to an empty page.

**Fix:** Load `@take + 1` records in the controller:

```ruby
@posts = posts.limit(@take + 1).offset((@page - 1) * @take)
```

In the view, detect next page with:

```erb
<% if @posts.size > @take %>
```

And only render `@posts.first(@take)` items. The extra record is never displayed — it is only used as a probe.

The `@total` count is unaffected (it runs before the limit).

---

## Section 4 — ReactionsController Visibility Guard

**Problem:** `set_post` uses `Post.find(params[:post_id])`, which finds any post regardless of visibility. A user can add or remove reactions on a soft-deleted or hidden post.

**Fix:** Change `set_post` to scope through `Post.visible`:

```ruby
def set_post
  @post = Post.visible.find(params[:post_id])
end
```

Rails raises `ActiveRecord::RecordNotFound` (→ 404) if the post is hidden or deleted. No other changes needed — the rest of the controller is unaffected.

---

## Out of Scope

- NotificationsController deep refactor (deferred — the three targeted call-site updates in Section 1 are included; broader restructuring of the controller is deferred)
- Eager load fix for `notifiable.post` (deferred — performance, not correctness)
- Full-text search upgrade (deferred — performance)
- User profile activity pagination efficiency (deferred — performance)
- Bulk notification inserts / background jobs (deferred — performance)

---

## Testing

Each fix has a clear test surface:

| Fix | Test |
|-----|------|
| `unread` scope | `Notification` model test: unread returns only unread records |
| `read` scope | `Notification` model test: read returns only read records |
| `mark_as_read!` | Model test: idempotent, sets `read_at`, no-ops if already read |
| `target_post` | Model test: returns post for Post notifiable, parent post for Reply notifiable |
| Search pagination | Controller test: exactly `@take` DB results → no "Next", only `@take` items rendered; `@take + 1` DB results → "Next" shown, only `@take` items rendered (probe record suppressed) |
| Reactions visibility | Controller test: reaction on hidden post returns 404 |
