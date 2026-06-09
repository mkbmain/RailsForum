# Bug Fixes Batch 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix 9 confirmed bugs: OmniAuth nil crash, replies to removed posts, reactions N+1, OAuth email overwrite, broadcast missing local, notification anchor, layout DB query in every request, banned users editing replies.

**Architecture:** Each fix is surgical — one file or two at most per issue, no structural changes. Tests use existing Minitest + fixtures/inline-create pattern. All fixes follow the existing before_action / helper_method / service patterns already in the codebase.

**Tech Stack:** Rails 8.1, Minitest, Hotwire/Turbo, PostgreSQL, OmniAuth (Google/Microsoft).

---

## File Map

| File | Change |
|------|--------|
| `app/controllers/omniauth_callbacks_controller.rb` | Guard against nil `auth` |
| `app/controllers/replies_controller.rb` | (a) Guard create against removed post; (b) add ban check to edit/update; (c) pass `flagged_reply_ids` in all broadcasts |
| `app/models/user.rb` | `from_omniauth` — skip email/name overwrite for existing records |
| `app/services/notification_service.rb` | `reply_in_thread` notifiable → Reply not Post; update dedup query |
| `app/controllers/application_controller.rb` | Add memoised `unread_notification_count` helper method |
| `app/views/layouts/application.html.erb` | Replace inline DB query with helper call |
| `app/views/reactions/_reactions.html.erb` | Compute counts/user_reaction in Ruby from loaded association |
| `app/controllers/posts_controller.rb` | Eager load reactions in `show` |
| `test/controllers/omniauth_callbacks_controller_test.rb` | New test for nil auth |
| `test/controllers/replies_controller_test.rb` | New tests: reply to removed post; banned user edit |
| `test/models/user_test.rb` | New test: existing user email not overwritten on re-login |
| `test/services/notification_service_test.rb` | New test: reply_in_thread notifiable is Reply with correct anchor |
| `test/controllers/posts_controller_test.rb` | New test: reactions preloaded (assert query count) |

---

## Task 1: OmniAuth nil crash — guard against missing auth hash

**Bug:** Hitting `/auth/google_oauth2/callback` directly (no OAuth flow) sets `auth = nil`. Line 9 then calls `auth.provider` → `NoMethodError` → 500.

**Files:**
- Modify: `app/controllers/omniauth_callbacks_controller.rb:7-9`
- Test: `test/controllers/omniauth_callbacks_controller_test.rb`

- [ ] **Step 1: Write the failing test**

> **Why `ActionController::TestCase` here:** OmniAuth's test middleware always sets `request.env["omniauth.auth"]` from the mock hash before the request reaches the controller. An `ActionDispatch::IntegrationTest` cannot bypass this. `ActionController::TestCase` calls the action directly, without any Rack middleware in the stack, so we can inject `nil` into `request.env["omniauth.auth"]` ourselves.

Add a new test class at the bottom of `test/controllers/omniauth_callbacks_controller_test.rb`:

```ruby
class OmniauthCallbacksHandleUnitTest < ActionController::TestCase
  tests OmniauthCallbacksController

  setup do
    Provider.find_or_create_by!(id: 1, name: "google")
    Provider.find_or_create_by!(id: 3, name: "internal")
  end

  test "handle redirects to login when omniauth.auth is nil" do
    request.env["omniauth.auth"] = nil
    get :handle
    assert_redirected_to login_path
    assert_equal "Authentication error. Please try signing in again.", flash[:alert]
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

```bash
bin/rails test test/controllers/omniauth_callbacks_controller_test.rb -n "test_handle_redirects_to_login_when_omniauth.auth_is_nil"
```

Expected: FAIL (NoMethodError: `undefined method 'provider' for nil`)

- [ ] **Step 3: Add the nil guard**

In `app/controllers/omniauth_callbacks_controller.rb`, add this as the first line of `handle`:

```ruby
def handle
  auth = request.env["omniauth.auth"]

  unless auth
    redirect_to login_path, alert: "Authentication error. Please try signing in again."
    return
  end

  provider_id = PROVIDER_IDS[auth.provider]
  # ... rest unchanged
```

- [ ] **Step 4: Run test to verify it passes**

```bash
bin/rails test test/controllers/omniauth_callbacks_controller_test.rb
```

Expected: all tests PASS

- [ ] **Step 5: Commit**

```bash
git add app/controllers/omniauth_callbacks_controller.rb \
        test/controllers/omniauth_callbacks_controller_test.rb
git commit -m "fix: guard OmniAuth callback against nil auth hash"
```

---

## Task 2: Replies can be posted to removed posts

**Bug:** `RepliesController#create` has no check that the parent post is not removed. `check_post_not_removed` only runs for `[:edit, :update]`. A user can POST to `/posts/:id/replies` of a soft-deleted post.

**Files:**
- Modify: `app/controllers/replies_controller.rb:1-15`
- Test: `test/controllers/replies_controller_test.rb`

- [ ] **Step 1: Write the failing test**

Add to `test/controllers/replies_controller_test.rb`:

```ruby
test "POST /posts/:post_id/replies is rejected when post is removed" do
  post login_path, params: { email: "u@example.com", password: "pass123" }
  @post.update!(removed_at: Time.current, removed_by: @user)
  assert_no_difference "Reply.count" do
    post post_replies_path(@post), params: { reply: { body: "sneaky reply" } }
  end
  assert_redirected_to posts_path
  assert_match "no longer available", flash[:alert]
end
```

- [ ] **Step 2: Run test to verify it fails**

```bash
bin/rails test test/controllers/replies_controller_test.rb -n "test_POST_/posts/:post_id/replies_is_rejected_when_post_is_removed"
```

Expected: FAIL (reply is created, no redirect)

- [ ] **Step 3: Add `set_post` before_action and extend `check_post_not_removed`**

In `app/controllers/replies_controller.rb`, make these two changes:

1. Add `before_action :set_post, only: [:create]` and extend `check_post_not_removed` to include `:create`:

```ruby
before_action :require_login
before_action :check_not_banned,       only: [ :create ]
before_action :check_rate_limit,       only: [ :create ]
before_action :set_post,               only: [ :create ]
before_action :check_post_not_removed, only: [ :create, :edit, :update ]
before_action :set_reply,              only: [ :edit, :update, :restore ]
before_action :require_moderator,      only: [ :restore ]
before_action :check_ownership,        only: [ :edit, :update ]
before_action :check_edit_window,      only: [ :edit, :update ]
```

2. Add a `set_post` private method (separate from `set_reply` — this only sets `@post` for the `create` action):

```ruby
def set_post
  @post = Post.find(params[:post_id])
end
```

3. Remove the duplicate `@post = Post.find(params[:post_id])` line from the top of `create`:

```ruby
def create
  @reply = @post.replies.build(reply_params.merge(user: current_user))
  # ... rest unchanged
```

> **Note:** `set_reply` (for edit/update/restore) also sets `@post`, so no conflict there. `check_post_not_removed` uses `@post` which is now set by either `set_post` (for create) or `set_reply` (for edit/update).

- [ ] **Step 4: Run test to verify it passes**

```bash
bin/rails test test/controllers/replies_controller_test.rb
```

Expected: all tests PASS

- [ ] **Step 5: Commit**

```bash
git add app/controllers/replies_controller.rb \
        test/controllers/replies_controller_test.rb
git commit -m "fix: prevent replies from being posted to removed posts"
```

---

## Task 3: Reactions N+1 — eager load and compute in Ruby

**Bug:** `_reactions.html.erb` fires 2 SQL queries per reactionable (`find_by` + `group().count`). With 20 replies on a page this is 42 unindexed queries inside a loop.

**Fix strategy:** Eager load reactions in `PostsController#show`. Change the partial to compute counts and user_reaction in Ruby from the preloaded association (no new SQL).

**Files:**
- Modify: `app/controllers/posts_controller.rb:40`
- Modify: `app/views/reactions/_reactions.html.erb:2-3`
- Test: `test/controllers/posts_controller_test.rb`

- [ ] **Step 1: Write the failing test**

Add to `test/controllers/posts_controller_test.rb`. This test verifies no extra queries are fired for reactions after eager loading:

```ruby
test "GET /posts/:id does not fire per-reply reaction queries" do
  post login_path, params: { email: "u@example.com", password: "pass123" }
  reply1 = Reply.create!(post: @post, user: @user, body: "reply 1")
  reply2 = Reply.create!(post: @post, user: @user, body: "reply 2")
  Reaction.create!(user: @user, reactionable: reply1, emoji: "👍")
  Reaction.create!(user: @user, reactionable: reply2, emoji: "❤️")

  query_count = 0
  counter = ->(*, **) { query_count += 1 }
  ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
    get post_path(@post)
  end
  assert_response :ok
  # reactions should be loaded in bulk, not per-reply
  # With N replies, we should not see more than ~10 total queries (not 2N+base)
  assert query_count < 12, "Expected <12 queries, got #{query_count} — possible N+1 on reactions"
end
```

- [ ] **Step 2: Run test to verify it fails**

```bash
bin/rails test test/controllers/posts_controller_test.rb -n "test_GET_/posts/:id_does_not_fire_per-reply_reaction_queries"
```

Expected: FAIL (query_count > 12)

- [ ] **Step 3: Eager load reactions in `PostsController#show`**

In `app/controllers/posts_controller.rb` make two changes:

**Change 1** — line 34: add `:reactions` to the post includes so post-level reactions are preloaded:

```ruby
@post = Post.includes(:category, :reactions).find(params[:id])
```

**Change 2** — line 40: add `:reactions` to the replies includes:

```ruby
@replies = @post.replies.visible
                .includes(:user, :reactions)
                .order(:created_at)
                .limit(take + 1)
                .offset((page - 1) * take)
```

- [ ] **Step 4: Update the reactions partial to use preloaded data**

Replace the two query lines at the top of `app/views/reactions/_reactions.html.erb`:

**Before:**
```erb
<% user_reaction   = logged_in? ? reactionable.reactions.find_by(user_id: current_user.id) : nil %>
<% reaction_counts = reactionable.reactions.group(:emoji).count %>
```

**After:**
```erb
<% user_reaction   = logged_in? ? reactionable.reactions.find { |r| r.user_id == current_user.id } : nil %>
<% reaction_counts = reactionable.reactions.group_by(&:emoji).transform_values(&:count) %>
```

> When `reactions` is already loaded (via `includes`), calling `.find { }` and `.group_by` runs in Ruby with no SQL. When rendered in a Turbo frame update from `ReactionsController` (single reactionable, no preload needed), the same code fires 1 query to load reactions — still correct, just not bulk.

- [ ] **Step 5: Run tests to verify it passes**

```bash
bin/rails test test/controllers/posts_controller_test.rb
```

Expected: all tests PASS

- [ ] **Step 6: Commit**

```bash
git add app/controllers/posts_controller.rb \
        app/views/reactions/_reactions.html.erb \
        test/controllers/posts_controller_test.rb
git commit -m "fix: eager load reactions to eliminate N+1 on post show page"
```

---

## Task 4: OAuth login silently overwrites email and name

**Bug:** `User.from_omniauth` calls `user.email = auth.info.email` and `user.name = auth.info.name` unconditionally on every login — including for existing users. A provider-side email change silently migrates the Rails user account.

**Fix:** Only set `email` and `name` for new (unsaved) records. Always refresh `avatar_url` since it's cosmetic.

**Files:**
- Modify: `app/models/user.rb:28-36`
- Test: `test/models/user_test.rb`

- [ ] **Step 1: Write the failing test**

Add to `test/models/user_test.rb`:

```ruby
test "from_omniauth does not overwrite email or name on subsequent logins" do
  provider_id = Provider.find_or_create_by!(id: 1, name: "google").id
  auth = OmniAuth::AuthHash.new(
    uid: "google-uid-abc",
    info: { email: "original@example.com", name: "Original Name", image: "https://img.example.com/1.jpg" }
  )
  user = User.from_omniauth(auth, provider_id)
  assert_equal "original@example.com", user.email
  assert_equal "Original Name", user.name

  # Simulate provider-side email/name change
  changed_auth = OmniAuth::AuthHash.new(
    uid: "google-uid-abc",
    info: { email: "changed@example.com", name: "Changed Name", image: "https://img.example.com/2.jpg" }
  )
  same_user = User.from_omniauth(changed_auth, provider_id)
  assert_equal user.id, same_user.id
  assert_equal "original@example.com", same_user.email,   "email must not be overwritten"
  assert_equal "Original Name",        same_user.name,    "name must not be overwritten"
  assert_equal "https://img.example.com/2.jpg", same_user.avatar_url, "avatar_url should refresh"
end
```

- [ ] **Step 2: Run test to verify it fails**

```bash
bin/rails test test/models/user_test.rb -n "test_from_omniauth_does_not_overwrite_email_or_name_on_subsequent_logins"
```

Expected: FAIL (email and name are overwritten)

- [ ] **Step 3: Update `from_omniauth` to guard existing records**

In `app/models/user.rb`, replace the `from_omniauth` method:

```ruby
def self.from_omniauth(auth, provider_id)
  raise ArgumentError, "OAuth response missing email" unless auth.info.email.present?
  find_or_initialize_by(uid: auth.uid, provider_id: provider_id).tap do |user|
    if user.new_record?
      user.email = auth.info.email
      user.name  = auth.info.name
    end
    user.avatar_url = auth.info.image
    user.save!
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

```bash
bin/rails test test/models/user_test.rb
```

Expected: all tests PASS

- [ ] **Step 5: Commit**

```bash
git add app/models/user.rb test/models/user_test.rb
git commit -m "fix: stop OAuth login from overwriting existing user email and name"
```

---

## Task 5: Turbo broadcasts missing `flagged_reply_ids` local

**Bug:** `broadcast_reply_created`, `broadcast_reply_updated`, and `broadcast_reply_soft_deleted` all omit the `flagged_reply_ids` local. The `_reply.html.erb` partial references `flagged_reply_ids` on line 50 (inside `if logged_in? && !reply.removed?`). For created/updated replies this block executes → `ActionView::Template::Error: undefined local variable 'flagged_reply_ids'` for every connected viewer.

**Fix:** Pass `flagged_reply_ids: Set.new` in all broadcast calls. `Set.new` is correct because server-side broadcasts have no per-viewer flag state — each viewer's own flag indicators are handled by the Turbo frame on initial page load, not by broadcasts.

**Files:**
- Modify: `app/controllers/replies_controller.rb:109-136`
- Test: `test/controllers/replies_controller_test.rb`

- [ ] **Step 1: Write the failing test**

Add to `test/controllers/replies_controller_test.rb`. This test checks that the broadcast doesn't raise by verifying the broadcast is attempted with the required local:

```ruby
test "POST /posts/:post_id/replies broadcasts reply with flagged_reply_ids local" do
  post login_path, params: { email: "u@example.com", password: "pass123" }
  # If flagged_reply_ids is missing, the partial render raises and the broadcast fails silently.
  # We verify the broadcast is enqueued with the correct locals by stubbing.
  broadcast_calls = []
  # Turbo's broadcast_append_to uses *streamables, **rendering — use splat to match
  stub = ->(*_args, **kwargs) {
    broadcast_calls << kwargs[:locals] if kwargs[:partial]&.include?("reply")
  }
  Turbo::StreamsChannel.stub(:broadcast_append_to, stub) do
    post post_replies_path(@post), params: { reply: { body: "hello world" } }
  end
  assert_equal 1, broadcast_calls.size
  assert broadcast_calls.first.key?(:flagged_reply_ids),
    "broadcast must pass flagged_reply_ids local to avoid NameError in partial"
end
```

- [ ] **Step 2: Run test to verify it fails**

```bash
bin/rails test test/controllers/replies_controller_test.rb -n "test_POST_/posts/:post_id/replies_broadcasts_reply_with_flagged_reply_ids_local"
```

Expected: FAIL (key not present)

- [ ] **Step 3: Add `flagged_reply_ids: Set.new` to all broadcast methods**

In `app/controllers/replies_controller.rb`, update all three broadcast methods:

```ruby
def broadcast_reply_created
  Turbo::StreamsChannel.broadcast_append_to(
    [ @post, :replies ],
    target: "replies-list-#{@post.id}",
    partial: "replies/reply",
    locals: { reply: @reply, post: @post, flagged_reply_ids: Set.new }
  )
  broadcast_reply_count
end

def broadcast_reply_updated
  Turbo::StreamsChannel.broadcast_replace_to(
    [ @post, :replies ],
    target: "reply-#{@reply.id}",
    partial: "replies/reply",
    locals: { reply: @reply, post: @post, flagged_reply_ids: Set.new }
  )
end

def broadcast_reply_soft_deleted
  Turbo::StreamsChannel.broadcast_replace_to(
    [ @post, :replies ],
    target: "reply-#{@reply.id}",
    partial: "replies/reply",
    locals: { reply: @reply, post: @post, flagged_reply_ids: Set.new }
  )
  broadcast_reply_count
end
```

(`broadcast_reply_restored` already passes `flagged_reply_ids: Set.new` — no change needed.)

- [ ] **Step 4: Run tests to verify they pass**

```bash
bin/rails test test/controllers/replies_controller_test.rb
```

Expected: all tests PASS

- [ ] **Step 5: Commit**

```bash
git add app/controllers/replies_controller.rb \
        test/controllers/replies_controller_test.rb
git commit -m "fix: pass flagged_reply_ids to all Turbo broadcast partials"
```

---

## Task 6: `reply_in_thread` notifications link to post top, not the reply

**Bug:** `NotificationService.reply_created` creates `reply_in_thread` notifications with `notifiable_type: "Post"`. The notifications view generates an anchor only when `n.notifiable.is_a?(Reply)`. So `reply_in_thread` notifications always link to the top of the thread instead of the specific reply.

**Fix:** Store the reply as the notifiable for `reply_in_thread`. Update the dedup query (which previously searched by `notifiable_type: "Post"`) to search for replies belonging to the same post.

**Files:**
- Modify: `app/services/notification_service.rb:24-45`
- Test: `test/services/notification_service_test.rb`

- [ ] **Step 1: Write the failing test**

Add to `test/services/notification_service_test.rb`:

```ruby
test "reply_in_thread notification points to the reply, not the post" do
  NotificationService.reply_created(@reply, current_user: @replier)
  n = Notification.find_by(user: @participant, event_type: :reply_in_thread)
  assert_not_nil n
  assert_equal "Reply", n.notifiable_type,
    "reply_in_thread notifiable must be a Reply so the view can anchor to it"
  assert_equal @reply.id, n.notifiable_id
end

test "reply_in_thread dedup still works after notifiable change" do
  # First reply — notification created
  NotificationService.reply_created(@reply, current_user: @replier)
  assert_equal 1, Notification.where(user: @participant, event_type: :reply_in_thread).count

  # Second reply within 24h — should NOT create another notification for same participant
  reply2 = Reply.create!(post: @post, user: @replier, body: "follow-up reply")
  assert_no_difference "Notification.where(user: @participant, event_type: :reply_in_thread).count" do
    NotificationService.reply_created(reply2, current_user: @replier)
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
bin/rails test test/services/notification_service_test.rb -n "test_reply_in_thread_notification_points_to_the_reply,_not_the_post"
```

Expected: FAIL (notifiable_type is "Post", not "Reply")

- [ ] **Step 2b: Remove the existing dedup test that uses `notifiable: @post`**

The test "does not send reply_in_thread if already notified within 24 hours" (lines ~48–59 in `notification_service_test.rb`) pre-creates a notification with `notifiable: @post` (type `"Post"`). After this fix the dedup query searches by `notifiable_type: "Reply"`, so that pre-created `Post` notification will no longer match — the test will fail incorrectly. **Delete that test** and rely on the new "reply_in_thread dedup still works after notifiable change" test added in Step 1 instead.

- [ ] **Step 3: Update `NotificationService.reply_created`**

In `app/services/notification_service.rb`, update sections 2 (dedup query) and the notification create call:

```ruby
# 2. reply_in_thread — notify prior participants (deduplicated per 24h)
reply_ids_in_post = post.replies.pluck(:id)
recent_thread_notified_ids = Notification
  .where(notifiable_type: "Reply", notifiable_id: reply_ids_in_post, event_type: :reply_in_thread)
  .where("created_at > ?", 24.hours.ago)
  .pluck(:user_id)

excluded_ids = [ actor.id ] + already_notified.to_a + recent_thread_notified_ids

participant_ids = post.replies
                     .where.not(id: reply.id)
                     .where.not(user_id: excluded_ids)
                     .distinct
                     .pluck(:user_id)

participant_ids.each do |uid|
  Notification.create!(
    user_id:          uid,
    actor_id:         actor.id,
    notifiable_type:  "Reply",
    notifiable_id:    reply.id,
    event_type:       :reply_in_thread
  )
  already_notified.add(uid)
end
```

- [ ] **Step 4: Run all notification tests to verify they pass**

```bash
bin/rails test test/services/notification_service_test.rb
```

Expected: all tests PASS (including the existing dedup test)

- [ ] **Step 5: Commit**

```bash
git add app/services/notification_service.rb \
        test/services/notification_service_test.rb
git commit -m "fix: reply_in_thread notifications now anchor to the specific reply"
```

---

## Task 7: Unread notification count fires a DB query on every page load

**Bug:** `app/views/layouts/application.html.erb:66` contains `current_user.notifications.where(read_at: nil).count` as an inline ERB expression. This fires a raw SQL query on every page request for every logged-in user. It is also inconsistent with the `.unread` scope used elsewhere.

**Fix:** Move to a memoised helper method on `ApplicationController`. The layout calls the helper; `NotificationsController#index` reuses the same method.

**Files:**
- Modify: `app/controllers/application_controller.rb`
- Modify: `app/views/layouts/application.html.erb:66`
- Test: (no dedicated test needed — the helper is thin; integration coverage via existing controller tests)

- [ ] **Step 1: Add `unread_notification_count` helper method to `ApplicationController`**

In `app/controllers/application_controller.rb`:

1. Add `unread_notification_count` to `helper_method`:

```ruby
helper_method :current_user, :logged_in?, :can_moderate?, :unread_notification_count
```

2. Add the method in the `private` section:

```ruby
def unread_notification_count
  return 0 unless logged_in?
  @unread_notification_count ||= current_user.notifications.unread.count
end
```

- [ ] **Step 2: Update the layout to use the helper**

In `app/views/layouts/application.html.erb`, replace line 66:

**Before:**
```erb
<% unread_count = current_user.notifications.where(read_at: nil).count %>
```

**After:**
```erb
<% unread_count = unread_notification_count %>
```

- [ ] **Step 3: Run the full test suite**

```bash
bin/rails test
```

Expected: all tests PASS

- [ ] **Step 4: Commit**

```bash
git add app/controllers/application_controller.rb \
        app/views/layouts/application.html.erb
git commit -m "fix: memoize unread notification count, remove inline DB query from layout"
```

---

## Task 8: Banned users can edit existing replies

**Bug:** `before_action :check_not_banned, only: [:create]` in `RepliesController` does not cover `:edit` and `:update`. A banned user can load the edit form and submit changes to an existing reply.

**Fix:** Extend `check_not_banned` to cover `[:create, :edit, :update]`.

**Files:**
- Modify: `app/controllers/replies_controller.rb:6`
- Test: `test/controllers/replies_controller_test.rb`

- [ ] **Step 1: Write the failing test**

Add to `test/controllers/replies_controller_test.rb`. You'll need a ban setup helper inline:

```ruby
test "GET edit reply is blocked for banned user" do
  reply = Reply.create!(post: @post, user: @user, body: "my reply")
  UserBan.create!(
    user: @user,
    banned_by: @admin,
    ban_reason: BanReason.find_or_create_by!(name: "Spam"),
    banned_from: Time.current,
    banned_until: 2.hours.from_now
  )
  post login_path, params: { email: "u@example.com", password: "pass123" }
  get edit_post_reply_path(@post, reply)
  assert_redirected_to post_path(@post)
  assert_match "banned", flash[:alert]
end

test "PATCH update reply is blocked for banned user" do
  reply = Reply.create!(post: @post, user: @user, body: "my reply")
  UserBan.create!(
    user: @user,
    banned_by: @admin,
    ban_reason: BanReason.find_or_create_by!(name: "Spam"),
    banned_from: Time.current,
    banned_until: 2.hours.from_now
  )
  post login_path, params: { email: "u@example.com", password: "pass123" }
  patch post_reply_path(@post, reply), params: { reply: { body: "edited" } }
  assert_redirected_to post_path(@post)
  assert_match "banned", flash[:alert]
  assert_equal "my reply", reply.reload.body
end
```

> Check your test fixtures for `BanReason.first!` — if none exist, create one inline: `BanReason.find_or_create_by!(name: "spam")`.

- [ ] **Step 2: Run tests to verify they fail**

```bash
bin/rails test test/controllers/replies_controller_test.rb -n "test_GET_edit_reply_is_blocked_for_banned_user"
```

Expected: FAIL (edit/update proceed normally for banned user)

- [ ] **Step 3: Extend `check_not_banned` to cover edit and update**

In `app/controllers/replies_controller.rb`, change line 6:

**Before:**
```ruby
before_action :check_not_banned, only: [ :create ]
```

**After:**
```ruby
before_action :check_not_banned, only: [ :create, :edit, :update ]
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
bin/rails test test/controllers/replies_controller_test.rb
```

Expected: all tests PASS

- [ ] **Step 5: Run the full test suite to catch regressions**

```bash
bin/rails test
```

Expected: all tests PASS

- [ ] **Step 6: Commit**

```bash
git add app/controllers/replies_controller.rb \
        test/controllers/replies_controller_test.rb
git commit -m "fix: banned users can no longer edit or update existing replies"
```

---

## Final verification

- [ ] **Run full CI pipeline**

```bash
./bin/ci
```

Expected: lint clean, security audit clean, all tests PASS, seed check passes.
