# Edit Posts & Replies — Design Spec

**Date:** 2026-03-17

## Overview

Allow authenticated users to edit their own posts and replies within a configurable time window (default 1 hour). Display a "last edited at" timestamp on posts/replies that have been modified. Sorting and ordering logic is unchanged — edits do not affect post ranking.

**Edit window reference point:** The window is always measured from `created_at`, not from `last_edited_at`. Editing does not extend the window. `last_edited_at` is used only for display purposes.

---

## Database & Models

### Migrations

Two new migrations, one for `posts` and one for `replies`. Use a DB-level default of `NOW()` so the column is initialized correctly at INSERT time without requiring application-level callbacks:

```ruby
# Step 1: add column with DB default (covers new rows automatically)
add_column :posts, :last_edited_at, :datetime, default: -> { "NOW()" }

# Step 2: backfill existing rows
execute "UPDATE posts SET last_edited_at = created_at"

# Step 3: add NOT NULL constraint
# Using change_column_null is acceptable for this small app (brief table lock)
change_column_null :posts, :last_edited_at, false
```

Same pattern for `replies`. Because `last_edited_at` and `created_at` are both set in the same INSERT statement, they will be exactly equal on new records, making the `edited?` check reliable.

### Models

No `before_create` callback needed — the DB default handles initialization.

Both `Post` and `Reply` get a helper method:

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

Replies resource gains `edit` and `update` (posts already has them via full `resources`):

```ruby
resources :posts do
  resources :replies, only: [:create, :destroy, :edit, :update]
end
```

### PostsController

New actions: `edit`, `update`

**Before action changes:**
- `require_login` — already on `[:new, :create]`; extend to also cover `[:edit, :update]`
- `check_ownership` — new; `@post.user == current_user`, redirects to post with alert if not
- `check_edit_window` — new; `Time.current - @post.created_at <= EDIT_WINDOW_SECONDS`, redirects to post with alert if expired

Both new guards apply to `[:edit, :update]`.

**On successful `update`:**
- Set `last_edited_at = Time.current` before saving
- Redirect to post show page

**On failed `update` (validation error):**
- Re-assign `@categories = Category.all.order(:name)` (required for the category dropdown)
- Render `:edit`, `status: :unprocessable_entity`

`last_replied_at` is **never** touched by edits — sort order unaffected.

### RepliesController

New actions: `edit`, `update`

**Before action changes:**
- `require_login` — already applies to all actions; no change needed
- `check_ownership` — new; applied to `[:edit, :update]`. The existing inline ownership check in `destroy` is left as-is
- `check_edit_window` — new; applied to `[:edit, :update]`

**On successful `update`:**
- Set `last_edited_at = Time.current` before saving
- Redirect to parent post show page

**On failed `update` (validation error):**
- Render `:edit`, `status: :unprocessable_entity`

---

## Views

### New Files

- `app/views/posts/edit.html.erb` — mirrors "New Post" style; fields: title, category dropdown, body; submit: "Update Post"
- `app/views/replies/edit.html.erb` — body textarea only; submit: "Update Reply"; back link to post

### Edit Link (posts/show.html.erb)

Shown inline next to the post/reply timestamp. Conditionally rendered when:
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
- `destroy` ownership check in `RepliesController` — left as existing inline check
