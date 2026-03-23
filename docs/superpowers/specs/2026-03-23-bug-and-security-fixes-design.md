# Bug & Security Fixes — Design Spec

**Date:** 2026-03-23
**Scope:** All confirmed bugs and security issues identified in the March 2026 codebase audit.
**Approach:** Single branch, tasks ordered by risk (security/auth first, then correctness, then performance). One PR.

---

## Overview

Nine issues are addressed across four themes:

| # | Theme | Issue | Type |
|---|-------|-------|------|
| 1a | Auth | Missing `return` in `check_ownership` and `check_edit_window` | Bug |
| 1b | Auth | Owners can edit their own soft-deleted content | Bug |
| 1c | Auth | Replies on a removed post editable via direct URL | Security |
| 1d | Auth | Admins can moderate other admins' content | Security |
| 2a | Data | Case-sensitive email unique index vs. model validation | Bug |
| 2b | Security | Markdown XSS via `javascript:` URIs in links | Security |
| 3a | Logic | Mention parsing broken for names with non-word characters | Bug |
| 3b | Logic | Admin activity tab pagination conflates three collections | Bug |
| 3c | Perf | N+1 reply count query on posts index | Bug |

---

## Section 1 — Auth & Authorization

### 1a — Missing `return` after `redirect_to` in before-action guards

**Problem:** `check_ownership` and `check_edit_window` in both `PostsController` and `RepliesController` call `redirect_to` without a subsequent `return`. In Rails, `redirect_to` sets the response but does not halt execution — the rest of the before-action method continues, and the action itself still runs after all before-actions complete. This causes a double-render error or, worse, allows the unauthorized action to execute despite the redirect being queued. The fix is to exit the method immediately after redirecting.

**Affected methods (4 total):**
- `app/controllers/posts_controller.rb` — `check_ownership` (line 107) and `check_edit_window` (line 113)
- `app/controllers/replies_controller.rb` — `check_ownership` (line 76) and `check_edit_window` (line 82)

**Fix:** Use `return redirect_to(...)` in all four methods — this is unambiguous and the preferred Rails idiom. Example:

```ruby
# Before
def check_ownership
  unless @post.user == current_user
    redirect_to @post, alert: "Not authorized to edit this post."
  end
end

# After
def check_ownership
  unless @post.user == current_user
    return redirect_to(@post, alert: "Not authorized to edit this post.")
  end
end
```

Apply the same pattern to `check_edit_window` in both controllers. Note: `redirect_to(...) and return` is functionally equivalent but relies on Ruby operator precedence; `return redirect_to(...)` is clearer and preferred.

**Test:** Verify that a request from a non-owner is redirected and the update action body does not execute (assert no DB writes). Verify the same for an expired edit window.

---

### 1b — Owners cannot edit soft-deleted content

**Problem:** `check_ownership` only verifies that `current_user` owns the resource. It does not check `removed?`. A post or reply soft-deleted by a moderator can still be updated by its owner via `PATCH /posts/:id` or `PATCH /posts/:id/replies/:id`.

**Fix:** In `check_ownership` for both controllers, add an early guard before the ownership check:

```ruby
# posts_controller.rb
def check_ownership
  if @post.removed?
    return redirect_to(@post, alert: "This content has been removed and can no longer be edited.")
  end
  unless @post.user == current_user
    return redirect_to(@post, alert: "Not authorized to edit this post.")
  end
end
```

Apply the equivalent guard in `replies_controller.rb` using `@reply.removed?`. Note that in the replies controller, `check_ownership` guards the reply object (`@reply.removed?`) while the separate `check_post_not_removed` (fix 1c) guards the parent post (`@post.removed?`). These are complementary — both are necessary and guard different conditions.

**Files:**
- `app/controllers/posts_controller.rb` — `check_ownership`
- `app/controllers/replies_controller.rb` — `check_ownership`

**Test:** Add tests for `edit` and `update` on a removed post/reply owned by the current user. Assert redirect with alert and no DB write.

---

### 1c — Replies on a removed post are not editable via direct URL

**Problem:** `RepliesController` loads `@post` via `set_post` but never checks if the post is removed before allowing reply edits. A user who knows the URL (`/posts/:id/replies/:reply_id/edit`) can edit their reply on a removed post.

**Fix:** Add a `check_post_not_removed` before-action on `edit` and `update` in `RepliesController`. This before-action depends on `@post` being set, so it must be declared **after** `before_action :set_reply` in the file (Rails executes before-actions in declaration order):

```ruby
before_action :set_reply, only: [:edit, :update, :restore]   # already present — shown for ordering context
before_action :check_post_not_removed, only: [:edit, :update] # declare after set_reply

def check_post_not_removed
  return redirect_to(posts_path, alert: "This post is no longer available.") if @post.removed?
end
```

**Files:**
- `app/controllers/replies_controller.rb`

**Test:** Assert that `GET /posts/:removed_post_id/replies/:id/edit` redirects even when the reply is owned by the current user.

---

### 1d — Admins cannot moderate other admins' content

**Problem:** `can_moderate?(target_user)` in `Moderatable` concern takes a `User` object directly (not a resource). The current implementation:

```ruby
def can_moderate?(target_user)
  return false unless current_user&.moderator?
  return false if current_user == target_user
  return true if current_user.admin?           # ← unconditional: any admin passes
  !target_user.sub_admin? && !target_user.admin?
end
```

Line 17 (`return true if current_user.admin?`) short-circuits before the `!target_user.admin?` guard on line 18. Any admin can moderate any other admin.

**Fix:** Add a guard before line 17 to deny moderation when the target is also an admin:

```ruby
def can_moderate?(target_user)
  return false unless current_user&.moderator?
  return false if current_user == target_user
  return false if target_user.admin?           # ← new: admins cannot be moderated
  return true if current_user.admin?
  !target_user.sub_admin? && !target_user.admin?
end
```

**Files:**
- `app/controllers/concerns/moderatable.rb`

**Test:** Assert that an admin cannot remove a post authored by another admin (call `can_moderate?` with an admin `target_user`, expect `false`). Assert that an admin can still moderate a regular user.

---

## Section 2 — Data Integrity & Content Security

### 2a — Case-insensitive email unique index

**Problem:** The btree index `CREATE UNIQUE INDEX index_users_on_email ON public.users USING btree (email)` is case-sensitive. The model validation uses `case_sensitive: false`. This mismatch allows `user@example.com` and `User@example.com` to coexist as separate accounts.

**Additional confirmed gap:** The `User` model has no `before_save` email normalization callback. The uniqueness validation `case_sensitive: false` performs a case-insensitive SQL check at validation time, but the value stored in the DB retains its original casing. This means the index won't enforce uniqueness across cases even after this fix is applied unless normalization is also added.

**Fix:**

1. Add a migration that:
   - Drops `index_users_on_email`
   - Creates `CREATE UNIQUE INDEX index_users_on_lower_email ON users (LOWER(email))`

2. Add a `before_save` normalizer to `User`. Include a nil guard since OAuth providers could theoretically omit an email (the `from_omniauth` path raises `ArgumentError` if email is blank, but the guard is defensive):

```ruby
before_save { self.email = email&.downcase&.strip }
```

**Files:**
- New migration file
- `app/models/user.rb` — add `before_save` normalization
- `db/structure.sql` (auto-updated by migration)

**Test:** Assert that attempting to create a user with an email differing only in case from an existing user raises a uniqueness error. Assert that the stored email is always lowercase.

---

### 2b — Markdown XSS via `javascript:` URIs

**Problem:** The `render_markdown` helper in `application_helper.rb` (line 4) renders Markdown then passes it to `sanitize` with a tag allowlist but no protocol restriction:

```ruby
sanitize(parser.render(text.to_s), tags: MARKDOWN_ALLOWED_TAGS)
```

A Markdown link `[click me](javascript:alert(1))` produces `<a href="javascript:alert(1)">click me</a>`. The `<a>` tag is permitted by `MARKDOWN_ALLOWED_TAGS` but the `href` value is unconstrained.

**Fix:** Add a `protocols:` restriction to the existing `sanitize` call, whitelisting only safe URI schemes for `href`. This uses Rails' built-in sanitizer — no custom scrubber class is needed:

```ruby
sanitize(
  parser.render(text.to_s),
  tags: MARKDOWN_ALLOWED_TAGS,
  protocols: { "a" => { "href" => ["http", "https", "mailto", :relative] } }
)
```

The `:relative` symbol permits relative paths (e.g., `/posts/1`). Any `href` with a scheme not in this list (including `javascript:`, `data:`, `vbscript:`) is stripped by Rails' HTML sanitizer.

**Files:**
- `app/helpers/application_helper.rb` — `render_markdown` method

**Test:** Assert that `render_markdown("[evil](javascript:alert(1))")` does not contain `javascript:` in the output. Assert that `render_markdown("[link](https://example.com)")` preserves the href.

---

## Section 3 — Logic Correctness & Performance

### 3a — Mention parsing broken for names with non-word characters

**Corrected diagnosis:** The space-handling in the mention system is actually correct. The autocomplete emits tokens via `u.name.gsub(' ', '_')` (e.g., `"John Doe"` → token `"John_Doe"`, inserted as `@John_Doe`). The regex `/@(\w+)/i` captures `"John_Doe"`, and `NotificationService` looks up the user with:

```ruby
User.find_by("LOWER(name) = LOWER(?)", username.gsub("_", " "))
# → LOWER(name) = LOWER('John Doe') ✓
```

This works correctly for names containing only letters and spaces.

**Actual bug:** Names containing non-word characters — apostrophes (`O'Brien`), hyphens (`Mary-Jane`), or dots (`J.K.`) — break the system. The `gsub(' ', '_')` token for `"O'Brien"` is `"O'Brien"`, and `\w` does not match `'`. The autocomplete inserts `@O'Brien ` but the regex only captures `"O"`, which does not resolve to any user.

**Fix:** Three parts:

1. In `User`, add a `mention_handle` method that strips non-word characters (keeping underscores as space separators) to produce a safe, `\w`-only handle:

```ruby
def mention_handle
  name.gsub(" ", "_").gsub(/[^\w]/, "").downcase
end
# "O'Brien"  → "obrien"
# "Mary-Jane" → "maryjane"
# "John Doe"  → "john_doe"
```

2. Add a class method to `User` that resolves a captured mention token back to a user. Since `sanitize_name` ensures stored names never contain underscores, the lookup strips non-alphanumeric characters from both sides before comparing. Use PostgreSQL's `REGEXP_REPLACE` with POSIX character class syntax (`[^a-z0-9 ]`), **not** `\w` (which is unreliable in PostgreSQL's regex engine):

```ruby
def self.find_by_mention_handle(handle)
  # handle: e.g. "obrien", "john_doe", "maryjane"
  # Convert underscores back to spaces to match stored names like "John Doe"
  normalized = handle.downcase.gsub("_", " ")
  # Strip remaining non-alphanumeric chars to match stored names like "O'Brien" → "o brien"
  find_by(
    "LOWER(REGEXP_REPLACE(name, '[^a-z0-9 ]', '', 'g')) = LOWER(REGEXP_REPLACE(?, '[^a-z0-9 ]', '', 'g'))",
    normalized
  )
end
```

3. In `NotificationService` (line 50), replace the existing lookup with `find_by_mention_handle`:

```ruby
# Before (line 50):
mentioned = User.find_by("LOWER(name) = LOWER(?)", username.gsub("_", " "))

# After:
mentioned = User.find_by_mention_handle(username)
```

4. Update the autocomplete token generation in `posts/show.html.erb` (and any reply form) to use `mention_handle` instead of `name.gsub(' ', '_')`:

```erb
data-mention-autocomplete-users-value="<%= @mention_users.map { |u|
  { token: u.mention_handle, display: u.name }
}.to_json.html_safe %>"
```

**Files:**
- `app/models/user.rb` — add `mention_handle` and `find_by_mention_handle`
- `app/services/notification_service.rb` — replace line 50 as shown above
- `app/views/posts/show.html.erb` — update token generation
- Any reply form view that also renders mention autocomplete data

**Note:** Users whose names consist entirely of non-alphanumeric characters (extreme edge case) may not be mentionable. This is acceptable; a stored handle field would be the robust solution and is out of scope here.

**Test:** Add a test where a user named `"O'Brien"` exists and a reply body contains `@OBrien`. Assert the mention notification is created. Also verify `"John Doe"` is still mentionable as `@John_Doe`.

---

### 3b — Admin activity tab pagination

**Problem:** `Admin::UsersController` activity tab (`when "activity"`, lines 53–68) fetches bans, posts, and replies independently with the same `page` param and sets a single `@has_more` boolean:

```ruby
@has_more = bans_raw.size > TAB_PER_PAGE ||
             posts_raw.size > TAB_PER_PAGE ||
             replies_raw.size > TAB_PER_PAGE
```

If only bans overflow, the "load more" link appears even though posts and replies are complete. All three types advance together on the same `page`, meaning paginating to page 2 re-fetches all types regardless of which one has more.

**Fix:** Track `@has_more` per collection with separate instance variables, and accept separate page params per type:

```ruby
when "activity"
  bans_page    = (params[:bans_page]    || 1).to_i
  posts_page   = (params[:posts_page]   || 1).to_i
  replies_page = (params[:replies_page] || 1).to_i

  bans_raw    = UserBan.where(banned_by: @user)...
                       .limit(TAB_PER_PAGE + 1).offset((bans_page - 1) * TAB_PER_PAGE).to_a
  posts_raw   = Post.where(removed_by: @user)...
                    .limit(TAB_PER_PAGE + 1).offset((posts_page - 1) * TAB_PER_PAGE).to_a
  replies_raw = Reply.where(removed_by: @user)...
                     .limit(TAB_PER_PAGE + 1).offset((replies_page - 1) * TAB_PER_PAGE).to_a

  @bans_has_more    = bans_raw.size > TAB_PER_PAGE
  @posts_has_more   = posts_raw.size > TAB_PER_PAGE
  @replies_has_more = replies_raw.size > TAB_PER_PAGE
  @bans_issued      = bans_raw.first(TAB_PER_PAGE)
  @posts_removed    = posts_raw.first(TAB_PER_PAGE)
  @replies_removed  = replies_raw.first(TAB_PER_PAGE)
```

The view renders a per-type "load more" link only when that type's flag is true. **Note:** The activity tab content may be rendered inline in `app/views/admin/users/show.html.erb` or extracted into a partial — verify the actual file location before editing. Update whichever file renders the `@bans_issued`, `@posts_removed`, `@replies_removed` collections.

**Files:**
- `app/controllers/admin/users_controller.rb` — `show` action, `when "activity"` branch
- `app/views/admin/users/show.html.erb` (or activity partial if extracted)

**Test:** Assert that when bans exceed `TAB_PER_PAGE` but posts do not, `@bans_has_more` is true and `@posts_has_more` is false.

---

### 3c — N+1 reply count on posts index

**Problem:** `posts/index.html.erb` calls `post.replies.count { |r| !r.removed? }` per post. Even with `includes(:replies)` in the controller, this loads all reply records for all posts into Ruby memory and filters in application code.

**Fix:** Preload visible reply counts in the controller using a single grouped query:

```ruby
# In PostsController#index, after loading @posts:
post_ids = @posts.map(&:id)
@reply_counts = Reply.where(post_id: post_ids)
                     .where(removed_at: nil)
                     .group(:post_id)
                     .count
# Returns: { post_id => count, ... }
```

In the view, replace the per-post count call:

```erb
<%# Before %>
<%= post.replies.count { |r| !r.removed? } %>

<%# After %>
<%= @reply_counts[post.id] || 0 %>
```

Remove `:replies` from the `includes` in the index query — verified that the index view's only use of replies is this count, so the eager load is now unnecessary. The `Reply` soft-delete column is confirmed as `removed_at` (used by `Reply#removed?`), so `.where(removed_at: nil)` is correct.

**Files:**
- `app/controllers/posts_controller.rb` — `index` action
- `app/views/posts/index.html.erb`

**Test:** Existing index tests should continue to pass. Optionally assert the reply count renders correctly for a post with a mix of visible and removed replies.

---

## Implementation Order

Execute in this order to avoid regressions:

1. **1a** — Fix missing `return` in all four guard methods (prerequisite for correctly testing 1b/1c)
2. **1b** — Block owner edits on removed content
3. **1c** — Block reply edits on removed post
4. **1d** — Block admin-on-admin moderation
5. **2a** — Email index migration + `before_save` normalization
6. **2b** — Markdown XSS `protocols:` restriction
7. **3a** — Mention handle fix
8. **3b** — Admin pagination fix
9. **3c** — N+1 reply count

Run `bin/rails test` and `bin/rubocop` after each fix before moving to the next.

---

## Out of Scope

- Password reset / forgot password flow (missing feature, separate spec)
- Email verification (missing feature, separate spec)
- Avatar upload (missing feature, separate spec)
- UX improvements to rate limit/ban messaging (separate spec)
