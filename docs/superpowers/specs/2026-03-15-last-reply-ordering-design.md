# Spec: Last Reply Date Display & Ordering

**Date:** 2026-03-15
**Status:** Approved

## Problem

The post index page currently shows each post's creation date in the top-right timestamp and orders posts by `posts.created_at DESC`. Users want to see when the last reply was made and have posts sorted by most recent activity (last reply, falling back to post creation when no replies exist).

## Goals

1. Display the last reply date (falling back to post creation date) on each post card in the index view.
2. Order the paginated post list by last activity date (last reply date, or post creation date if no replies).

## Non-Goals

- Changing the post show page.
- Real-time updates.
- Separate "last reply" vs "created" label distinction (keep display simple).

## Design

### Database

Add a nullable, indexed `last_replied_at datetime` column to the `posts` table.

```
add_column :posts, :last_replied_at, :datetime
add_index  :posts, :last_replied_at
```

Existing rows will have `NULL` for this column; the fallback to `created_at` is handled at the application layer.

### Model: `Reply`

Two `after_*` callbacks keep `last_replied_at` in sync:

- **`after_create`**: Sets `post.update_column(:last_replied_at, created_at)`.
- **`after_destroy`**: Recalculates via `post.replies.maximum(:created_at)` and writes the result (which is `nil` if no replies remain) back with `update_column`.

Using `update_column` bypasses validations and callbacks on `Post`, keeping the update lightweight.

### Model: `Post`

A `last_activity_at` helper method centralises the fallback logic:

```ruby
def last_activity_at
  last_replied_at || created_at
end
```

All consumers (view, ordering) use this method — no `nil` handling is scattered elsewhere.

### Controller: `posts#index`

Replace:
```ruby
Post.includes(...).order(created_at: :desc)
```

With:
```ruby
Post.includes(...).order(Arel.sql("COALESCE(last_replied_at, created_at) DESC"))
```

This correctly handles the `NULL` fallback at the SQL level and ensures consistent ordering with the display value.

### View: `posts/index.html.erb`

Replace the timestamp in the top-right of each post card:

```erb
<%# Before %>
<span class="text-xs text-stone-400"><%= time_ago_in_words(post.created_at) %> ago</span>

<%# After %>
<span class="text-xs text-stone-400"><%= time_ago_in_words(post.last_activity_at) %> ago</span>
```

No label change — "X ago" remains the format. The value now reflects last reply activity.

## Data Flow

```
Reply created/destroyed
  → Reply#after_create / after_destroy callback
    → post.update_column(:last_replied_at, ...)
      → Post#last_activity_at returns last_replied_at || created_at
        → View displays time_ago_in_words(post.last_activity_at)
        → Controller orders by COALESCE(last_replied_at, created_at) DESC
```

## Files Changed

| File | Change |
|------|--------|
| `db/migrate/TIMESTAMP_add_last_replied_at_to_posts.rb` | New migration |
| `app/models/reply.rb` | Add `after_create` / `after_destroy` callbacks |
| `app/models/post.rb` | Add `last_activity_at` helper |
| `app/controllers/posts_controller.rb` | Update ordering SQL |
| `app/views/posts/index.html.erb` | Update timestamp display |

## Testing

- `Post#last_activity_at` returns `created_at` when no replies exist.
- `Post#last_activity_at` returns the latest reply's `created_at` when replies exist.
- Creating a reply updates `post.last_replied_at`.
- Destroying the last reply sets `post.last_replied_at` to `nil`.
- Destroying a non-last reply sets `post.last_replied_at` to the next-most-recent reply's date.
- Posts are ordered by last activity (most recent reply or post) on the index page.
