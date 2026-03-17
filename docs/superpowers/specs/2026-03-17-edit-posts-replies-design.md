# Edit Posts & Replies — Design Spec

**Date:** 2026-03-17

## Overview

Allow authenticated users to edit their own posts and replies within a configurable time window. Display a "last edited at" timestamp on posts/replies that have been modified. Sorting and ordering logic is unchanged — edits do not affect post ranking.

---

## Database & Models

### Migrations

Two new migrations, one for `posts` and one for `replies`:

1. Add `last_edited_at` as a nullable datetime column
2. Backfill existing rows: `UPDATE posts SET last_edited_at = created_at` (same for replies)
3. Add NOT NULL constraint

### Models

Both `Post` and `Reply` get:

- A `before_create` callback: `self.last_edited_at = created_at || Time.current`
- A helper method:

```ruby
def edited?
  last_edited_at != created_at
end
```

### Configuration

`config/initializers/forum_settings.rb`:

```ruby
EDIT_WINDOW_SECONDS = ENV.fetch("EDIT_WINDOW_SECONDS", 3600).to_i
```

Change the edit window by setting the `EDIT_WINDOW_SECONDS` environment variable and restarting the server.

---

## Controllers & Authorization

### Routes

Replies resource gains `edit` and `update` actions (posts already has them via full `resources`):

```ruby
resources :posts do
  resources :replies, only: [:create, :destroy, :edit, :update]
end
```

### PostsController

New actions: `edit`, `update`

New `before_action` guards (on `edit` and `update`):
- `require_login` — existing, extended to cover edit/update
- `check_ownership` — `@post.user == current_user`, redirects with alert if not
- `check_edit_window` — `Time.current - @post.created_at <= EDIT_WINDOW_SECONDS`, redirects with alert if expired

On successful `update`:
- Set `last_edited_at = Time.current`
- Save and redirect to post show page
- `last_replied_at` is **never** touched by edits — sort order unaffected

### RepliesController

New actions: `edit`, `update`

Same guards as PostsController (`require_login`, `check_ownership`, `check_edit_window`) applied to `edit` and `update`.

On successful `update`:
- Set `last_edited_at = Time.current`
- Redirect to parent post show page

---

## Views

### New Files

- `app/views/posts/edit.html.erb` — mirrors "New Post" style; fields: title, category dropdown, body; submit: "Update Post"
- `app/views/replies/edit.html.erb` — body textarea only; submit: "Update Reply"; back link to post

### Edit Link (posts/show.html.erb)

Shown next to the post/reply timestamp. Conditionally rendered when:
- `current_user == resource.user`
- `Time.current - resource.created_at <= EDIT_WINDOW_SECONDS`

### "Last Edited" Display (posts/show.html.erb)

Shown below post body and each reply body when `resource.edited?`:

```
last edited at 17 Mar 2026 14:32
```

### No Changes

- `posts/index.html.erb` — post cards do not show edit controls or edited timestamps

---

## What Does NOT Change

- Post ordering (`COALESCE(last_replied_at, created_at) DESC`) — unaffected by edits
- `last_replied_at` on posts — only updated by reply create/destroy, not edits
- Rate limiting and ban checks — only apply to create actions
- Pagination and category filtering — unchanged
