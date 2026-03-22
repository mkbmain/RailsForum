# Soft-Delete Restore for Moderators

## Goal

Allow moderators to restore removed posts and replies. Currently `removed_at`/`removed_by` can only be set, never cleared — leaving no recovery path even for admins.

## Scope

- Restore action for posts
- Restore action for replies (with Turbo Stream broadcast)
- Visible only to moderators (`can_moderate?` gate, same as removal)
- No new models, migrations, or services

## Routes

Two new member routes:

```ruby
resources :posts do
  member { patch :restore }
  resources :replies, only: [:create, :destroy, :edit, :update] do
    member { patch :restore }
  end
end
```

Member routes are not constrained by `only:`, so `:restore` does not need to appear in the `only:` list. This yields `restore_post_path(@post)` and `restore_post_reply_path(@post, @reply)`.

## Controller Actions

### PostsController#restore

- Add `:restore` to `require_login`'s `only:` list (currently `[:new, :create, :destroy, :edit, :update]`)
- Add `:restore` to `require_moderator`'s `only:` list (currently `[:destroy]`)
- Add `:restore` to `set_post`'s `only:` list (currently `[:edit, :update]`) so `@post` is set
- Clears `removed_at: nil, removed_by: nil` via `update!`
- Redirects to `@post` with `notice: "Post restored."`

### RepliesController#restore

- `require_login` already applies to all actions — no change needed
- Add `before_action :require_moderator, only: [:restore]` (RepliesController has no existing `require_moderator` — this introduces it)
- Add `:restore` to `set_reply`'s `only:` list (currently `[:edit, :update]`) so `@post` and `@reply` are set
- Finds `@post` and `@reply` via the updated `set_reply` before_action
- Clears `removed_at: nil, removed_by: nil` via `update!`
- Recalculates `@post.last_replied_at` via `@post.update_column(:last_replied_at, @post.replies.visible.maximum(:created_at))` — mirrors the soft-delete destroy path
- Calls a new private helper `broadcast_reply_restored` — structurally identical to `broadcast_reply_soft_deleted` (replace partial + count broadcast), since restoring makes the reply visible again
- Broadcasts pass `locals: { reply: @reply, post: @post, flagged_reply_ids: Set.new }` to satisfy the partial's `flagged_reply_ids` local (restored replies are never flagged in the broadcast context)
- Redirects to `@post` with `notice: "Reply restored."`

### broadcast_reply_restored (private helper)

```ruby
def broadcast_reply_restored
  Turbo::StreamsChannel.broadcast_replace_to(
    [ @post, :replies ],
    target: "reply-#{@reply.id}",
    partial: "replies/reply",
    locals: { reply: @reply, post: @post, flagged_reply_ids: Set.new }
  )
  broadcast_reply_count
end
```

Note: the existing `broadcast_reply_soft_deleted` and `broadcast_reply_updated` helpers also omit `flagged_reply_ids` from their locals — this is a pre-existing gap. This spec fixes it only in `broadcast_reply_restored`; fixing the others is out of scope here.

## Views

### posts/show.html.erb

Inside the `@post.removed?` block, the existing moderator-only removal info paragraph gains a "Restore" button below it:

```erb
<% if logged_in? && current_user.moderator? %>
  <p class="text-xs text-gray-400 mt-1">
    Removed by <%= @post.removed_by.name %> on <%= @post.removed_at.strftime("%B %-d, %Y") %>
  </p>
  <%= button_to "Restore", restore_post_path(@post), method: :patch,
        class: "text-xs text-green-600 hover:underline bg-transparent border-0 p-0 cursor-pointer mt-1" %>
<% end %>
```

### replies/_reply.html.erb

Same pattern inside the `reply.removed?` block, below the existing removal info:

```erb
<% if logged_in? && current_user.moderator? %>
  <p class="text-xs text-gray-400 mt-1">
    Removed by <%= reply.removed_by.name %> on <%= reply.removed_at.strftime("%B %-d, %Y") %>
  </p>
  <%= button_to "Restore", restore_post_reply_path(post, reply), method: :patch,
        class: "text-xs text-green-600 hover:underline bg-transparent border-0 p-0 cursor-pointer mt-1" %>
<% end %>
```

## Testing

### posts_controller_test.rb

- Moderator restores a removed post → `removed_at` and `removed_by` are nil, redirects with `"Post restored."`
- Non-moderator (regular user) cannot restore → redirected, not authorized

### replies_controller_test.rb

- Moderator restores a removed reply → `removed_at` and `removed_by` are nil, redirects with `"Reply restored."`
- Moderator restore recalculates `post.last_replied_at`
- Moderator restore broadcasts 2 messages to the replies stream (replace + count)
- Non-moderator cannot restore → redirected

## Out of Scope

- Restore audit log / notification to original author
- Admin panel restore UI
- Fixing `flagged_reply_ids` omission in existing broadcast helpers
