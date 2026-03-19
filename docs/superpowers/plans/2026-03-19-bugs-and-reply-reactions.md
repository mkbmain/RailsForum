# Bugs and Reply Reactions Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix two reply-pagination/count bugs, add anchor deep-links to reply notifications, and add emoji reactions to replies (currently only on posts).

**Architecture:** Bugs are targeted one-liners. Deep-links add an `id` attribute to reply cards and an anchor fragment in the notifications view — no model changes. Reply reactions require making the `Reaction` model polymorphic (`reactionable_type`/`reactionable_id` instead of `post_id`), a shared `reactions/_reactions` partial with a `ReactionsHelper`, and nesting reaction routes under replies as well as posts.

**Tech Stack:** Rails 8.1, PostgreSQL, Minitest, Hotwire Turbo Streams, Tailwind CSS

---

### Task 1: Bug — Reply pagination false "Next" link

**Files:**
- Modify: `app/controllers/posts_controller.rb`
- Modify: `app/views/posts/show.html.erb`
- Test: `test/controllers/posts_controller_test.rb`

- [ ] **Step 1: Write failing tests**

Add to `test/controllers/posts_controller_test.rb` inside the existing class:

```ruby
test "GET /posts/:id Next link is not shown when exactly @take replies exist" do
  reply_user = User.create!(email: "rp1@example.com", name: "RP1",
                             password: "pass123", password_confirmation: "pass123", provider_id: 3)
  20.times { |i| Reply.create!(post: @post, user: reply_user, body: "reply #{i}") }
  get post_path(@post), params: { take: 20 }
  assert_response :success
  assert_select "a", text: /Next/, count: 0
end

test "GET /posts/:id Next link is shown when more replies exist" do
  reply_user = User.create!(email: "rp2@example.com", name: "RP2",
                             password: "pass123", password_confirmation: "pass123", provider_id: 3)
  21.times { |i| Reply.create!(post: @post, user: reply_user, body: "reply #{i}") }
  get post_path(@post), params: { take: 20 }
  assert_response :success
  assert_select "a", text: /Next/
end

test "GET /posts/:id only @take replies are rendered even when probe record is loaded" do
  reply_user = User.create!(email: "rp3@example.com", name: "RP3",
                             password: "pass123", password_confirmation: "pass123", provider_id: 3)
  21.times { |i| Reply.create!(post: @post, user: reply_user, body: "reply #{i}") }
  get post_path(@post), params: { take: 20 }
  assert_response :success
  assert_select ".bg-gray-50.border-gray-200", count: 20
end
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
bin/rails test test/controllers/posts_controller_test.rb
```

Expected: "Next link is not shown" test fails (Next is incorrectly shown when exactly 20 replies exist).

- [ ] **Step 3: Fix the controller — load `@take + 1` replies**

In `app/controllers/posts_controller.rb`, change line 35:

```ruby
# Before
@replies = @post.replies.includes(:user).order(:created_at).limit(take).offset((page - 1) * take)

# After — .visible added so removed replies are excluded; +1 probes for next page
@replies = @post.replies.visible.includes(:user).order(:created_at).limit(take + 1).offset((page - 1) * take)
```

- [ ] **Step 4: Fix the view — probe detection and rendering**

In `app/views/posts/show.html.erb`:

Change line 114:
```erb
<%# Before %>
<% if @replies.size >= @take %>

<%# After %>
<% if @replies.size > @take %>
```

Change line 59:
```erb
<%# Before %>
<% @replies.each do |reply| %>

<%# After %>
<% @replies.first(@take).each do |reply| %>
```

- [ ] **Step 5: Run tests to verify they pass**

```bash
bin/rails test test/controllers/posts_controller_test.rb
```

Expected: all green.

- [ ] **Step 6: Commit**

```bash
git add app/controllers/posts_controller.rb app/views/posts/show.html.erb \
        test/controllers/posts_controller_test.rb
git commit -m "fix: apply +1 probe to reply pagination in posts#show"
```

---

### Task 2: Bug — Reply count includes removed replies

**Files:**
- Modify: `app/controllers/posts_controller.rb`
- Test: `test/controllers/posts_controller_test.rb`

- [ ] **Step 1: Write failing test**

Add to `test/controllers/posts_controller_test.rb`:

```ruby
test "GET /posts/:id reply count excludes removed replies" do
  reply_user = User.create!(email: "rc2@example.com", name: "RC2",
                             password: "pass123", password_confirmation: "pass123", provider_id: 3)
  Reply.create!(post: @post, user: reply_user, body: "visible reply")
  removed = Reply.create!(post: @post, user: reply_user, body: "removed reply")
  removed.update_columns(removed_at: Time.current, removed_by_id: @sub_admin.id)
  get post_path(@post)
  assert_response :success
  # Only 1 visible reply; the removed one must not be counted
  assert_select "h2", text: /Replies \(1\)/
end
```

- [ ] **Step 2: Run test to verify it fails**

```bash
bin/rails test test/controllers/posts_controller_test.rb
```

Expected: failure — page shows "Replies (2)".

- [ ] **Step 3: Fix the controller**

In `app/controllers/posts_controller.rb`, change line 36:

```ruby
# Before
@reply_count = @post.replies.count

# After
@reply_count = @post.replies.visible.count
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
bin/rails test test/controllers/posts_controller_test.rb
```

Expected: all green.

- [ ] **Step 5: Commit**

```bash
git add app/controllers/posts_controller.rb test/controllers/posts_controller_test.rb
git commit -m "fix: scope reply count to visible in posts#show"
```

---

### Task 3: Feature — Notification deep-links to specific reply

**Files:**
- Modify: `app/views/posts/show.html.erb`
- Modify: `app/views/notifications/index.html.erb`
- Test: `test/controllers/posts_controller_test.rb`
- Test: `test/controllers/notifications_controller_test.rb`

- [ ] **Step 1: Write failing tests**

Add to `test/controllers/posts_controller_test.rb`:

```ruby
test "GET /posts/:id reply cards have anchor ids" do
  reply_user = User.create!(email: "anc@example.com", name: "Anc",
                             password: "pass123", password_confirmation: "pass123", provider_id: 3)
  reply = Reply.create!(post: @post, user: reply_user, body: "anchor me")
  get post_path(@post)
  assert_response :success
  assert_select "div#reply-#{reply.id}"
end
```

Add to `test/controllers/notifications_controller_test.rb`:

```ruby
test "GET /notifications reply notification links to post with reply anchor" do
  post login_path, params: { email: "nuser@example.com", password: "pass123" }
  get notifications_path
  assert_response :success
  assert_select "a[href=?]", post_path(@post, anchor: "reply-#{@reply.id}")
end

test "GET /notifications post notification links to post without anchor" do
  @notif.update_column(:notifiable_type, "Post")
  @notif.update_column(:notifiable_id,   @post.id)
  post login_path, params: { email: "nuser@example.com", password: "pass123" }
  get notifications_path
  assert_response :success
  assert_select "a[href=?]", post_path(@post)
end
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
bin/rails test test/controllers/posts_controller_test.rb test/controllers/notifications_controller_test.rb
```

Expected: all three new tests fail.

- [ ] **Step 3: Add `id` attributes to reply cards in the show view**

In `app/views/posts/show.html.erb`, find the reply card div (around line 60):

```erb
<%# Before %>
<div class="bg-gray-50 border border-gray-200 rounded-lg p-4 mb-3">

<%# After %>
<div class="bg-gray-50 border border-gray-200 rounded-lg p-4 mb-3" id="reply-<%= reply.id %>">
```

- [ ] **Step 4: Add anchor fragment to notification links**

In `app/views/notifications/index.html.erb`, change line 18:

```erb
<%# Before %>
<% post_link = post_path(n.target_post) %>

<%# After %>
<% anchor = n.notifiable.is_a?(Reply) ? "reply-#{n.notifiable.id}" : nil %>
<% post_link = post_path(n.target_post, anchor: anchor) %>
```

- [ ] **Step 5: Run tests to verify they pass**

```bash
bin/rails test test/controllers/posts_controller_test.rb test/controllers/notifications_controller_test.rb
```

Expected: all green.

- [ ] **Step 6: Commit**

```bash
git add app/views/posts/show.html.erb app/views/notifications/index.html.erb \
        test/controllers/posts_controller_test.rb test/controllers/notifications_controller_test.rb
git commit -m "feat: deep-link reply notifications to reply anchor in posts#show"
```

---

### Task 4: Feature — Reactions on replies

This task makes reactions polymorphic so they can belong to either a Post or a Reply. It involves a DB migration, model changes, a shared partial with helper, controller refactor, and new routes. All code changes and tests are written before committing as a single atomic change.

**Files:**
- Create: `db/migrate/<timestamp>_make_reactions_polymorphic.rb`
- Modify: `db/structure.sql` (auto-updated by `bin/rails db:migrate`)
- Modify: `app/models/reaction.rb`
- Modify: `app/models/post.rb`
- Modify: `app/models/reply.rb`
- Create: `app/helpers/reactions_helper.rb`
- Create: `app/views/reactions/_reactions.html.erb`
- Delete: `app/views/posts/_reactions.html.erb`
- Modify: `app/controllers/reactions_controller.rb`
- Modify: `config/routes.rb`
- Modify: `app/views/posts/show.html.erb`
- Modify: `test/models/reaction_test.rb`
- Modify: `test/controllers/reactions_controller_test.rb`

#### Step A: Write new and updated tests first

- [ ] **Step A1: Update `test/models/reaction_test.rb` to use polymorphic interface**

Replace `post:` with `reactionable:` throughout the file and add a reply reaction test:

```ruby
require "test_helper"

class ReactionTest < ActiveSupport::TestCase
  setup do
    Provider.find_or_create_by!(id: 3, name: "internal")
    @user = User.create!(email: "reactor@example.com", name: "Reactor",
                         password: "pass123", password_confirmation: "pass123",
                         provider_id: 3)
    @post  = Post.create!(user: @user, title: "Post", body: "Body")
    @reply = Reply.create!(post: @post, user: @user, body: "Reply")
  end

  test "valid with an allowed emoji on a post" do
    r = Reaction.new(user: @user, reactionable: @post, emoji: "👍")
    assert r.valid?, r.errors.full_messages.inspect
  end

  test "valid with an allowed emoji on a reply" do
    r = Reaction.new(user: @user, reactionable: @reply, emoji: "❤️")
    assert r.valid?, r.errors.full_messages.inspect
  end

  test "invalid with an unknown emoji" do
    r = Reaction.new(user: @user, reactionable: @post, emoji: "🦄")
    assert_not r.valid?
    assert_includes r.errors[:emoji], "is not included in the list"
  end

  test "invalid without emoji" do
    r = Reaction.new(user: @user, reactionable: @post, emoji: nil)
    assert_not r.valid?
  end

  test "only one reaction per user per post" do
    Reaction.create!(user: @user, reactionable: @post, emoji: "👍")
    dup = Reaction.new(user: @user, reactionable: @post, emoji: "❤️")
    assert_not dup.valid?
  end

  test "only one reaction per user per reply" do
    Reaction.create!(user: @user, reactionable: @reply, emoji: "👍")
    dup = Reaction.new(user: @user, reactionable: @reply, emoji: "❤️")
    assert_not dup.valid?
  end

  test "same user can react to both post and reply independently" do
    Reaction.create!(user: @user, reactionable: @post,  emoji: "👍")
    r = Reaction.new(user: @user, reactionable: @reply, emoji: "👍")
    assert r.valid?
  end

  test "ALLOWED_REACTIONS contains the four expected emoji" do
    assert_equal %w[👍 ❤️ 😂 😮], Reaction::ALLOWED_REACTIONS
  end
end
```

- [ ] **Step A2: Update and extend `test/controllers/reactions_controller_test.rb`**

Replace the full file content:

```ruby
require "test_helper"

class ReactionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    Provider.find_or_create_by!(id: 3, name: "internal")
    @user  = User.create!(email: "u@example.com", name: "User",
                          password: "pass123", password_confirmation: "pass123",
                          provider_id: 3)
    @other = User.create!(email: "other@example.com", name: "Other",
                          password: "pass123", password_confirmation: "pass123",
                          provider_id: 3)
    @post  = Post.create!(user: @user, title: "Post", body: "Body")
    @reply = Reply.create!(post: @post, user: @other, body: "A reply")
  end

  # --- Post reactions (existing behaviour preserved) ---

  test "POST creates a reaction on a post when logged in" do
    post login_path, params: { email: "u@example.com", password: "pass123" }
    assert_difference "Reaction.count", 1 do
      post post_reactions_path(@post), params: { emoji: "👍" }
    end
  end

  test "POST rejects invalid emoji with 422 on a post" do
    post login_path, params: { email: "u@example.com", password: "pass123" }
    assert_no_difference "Reaction.count" do
      post post_reactions_path(@post), params: { emoji: "🦄" }
    end
    assert_response :unprocessable_entity
  end

  test "POST upserts on a post — changes emoji rather than creating a second row" do
    post login_path, params: { email: "u@example.com", password: "pass123" }
    post post_reactions_path(@post), params: { emoji: "👍" }
    assert_no_difference "Reaction.count" do
      post post_reactions_path(@post), params: { emoji: "❤️" }
    end
    assert_equal "❤️", Reaction.find_by(user: @user, reactionable: @post).emoji
  end

  test "POST on a post requires login" do
    assert_no_difference "Reaction.count" do
      post post_reactions_path(@post), params: { emoji: "👍" }
    end
    assert_redirected_to login_path
  end

  test "DELETE destroys own post reaction" do
    post login_path, params: { email: "u@example.com", password: "pass123" }
    reaction = Reaction.create!(user: @user, reactionable: @post, emoji: "👍")
    assert_difference "Reaction.count", -1 do
      delete post_reaction_path(@post, reaction)
    end
  end

  test "DELETE cannot destroy another user's post reaction" do
    reaction = Reaction.create!(user: @other, reactionable: @post, emoji: "👍")
    post login_path, params: { email: "u@example.com", password: "pass123" }
    assert_no_difference "Reaction.count" do
      delete post_reaction_path(@post, reaction)
    end
    assert_response :not_found
  end

  test "DELETE on a post requires login" do
    reaction = Reaction.create!(user: @user, reactionable: @post, emoji: "👍")
    assert_no_difference "Reaction.count" do
      delete post_reaction_path(@post, reaction)
    end
    assert_redirected_to login_path
  end

  test "POST on hidden post returns 404" do
    @post.update_column(:removed_at, Time.current)
    post login_path, params: { email: "u@example.com", password: "pass123" }
    post post_reactions_path(@post), params: { emoji: "👍" }
    assert_response :not_found
  end

  test "DELETE on hidden post returns 404" do
    reaction = Reaction.create!(user: @user, reactionable: @post, emoji: "👍")
    @post.update_column(:removed_at, Time.current)
    post login_path, params: { email: "u@example.com", password: "pass123" }
    assert_no_difference "Reaction.count" do
      delete post_reaction_path(@post, reaction)
    end
    assert_response :not_found
  end

  # --- Reply reactions (new) ---

  test "POST creates a reaction on a reply when logged in" do
    post login_path, params: { email: "u@example.com", password: "pass123" }
    assert_difference "Reaction.count", 1 do
      post post_reply_reactions_path(@post, @reply), params: { emoji: "👍" }
    end
    assert_equal "Reply", Reaction.last.reactionable_type
    assert_equal @reply.id, Reaction.last.reactionable_id
  end

  test "POST rejects invalid emoji on a reply with 422" do
    post login_path, params: { email: "u@example.com", password: "pass123" }
    assert_no_difference "Reaction.count" do
      post post_reply_reactions_path(@post, @reply), params: { emoji: "🦄" }
    end
    assert_response :unprocessable_entity
  end

  test "POST upserts on a reply — changes emoji rather than creating a second row" do
    post login_path, params: { email: "u@example.com", password: "pass123" }
    post post_reply_reactions_path(@post, @reply), params: { emoji: "👍" }
    assert_no_difference "Reaction.count" do
      post post_reply_reactions_path(@post, @reply), params: { emoji: "❤️" }
    end
    assert_equal "❤️", Reaction.find_by(user: @user, reactionable: @reply).emoji
  end

  test "POST on a reply requires login" do
    assert_no_difference "Reaction.count" do
      post post_reply_reactions_path(@post, @reply), params: { emoji: "👍" }
    end
    assert_redirected_to login_path
  end

  test "DELETE destroys own reply reaction" do
    post login_path, params: { email: "u@example.com", password: "pass123" }
    reaction = Reaction.create!(user: @user, reactionable: @reply, emoji: "👍")
    assert_difference "Reaction.count", -1 do
      delete post_reply_reaction_path(@post, @reply, reaction)
    end
  end

  test "DELETE cannot destroy another user's reply reaction" do
    reaction = Reaction.create!(user: @other, reactionable: @reply, emoji: "👍")
    post login_path, params: { email: "u@example.com", password: "pass123" }
    assert_no_difference "Reaction.count" do
      delete post_reply_reaction_path(@post, @reply, reaction)
    end
    assert_response :not_found
  end

  test "POST on a reply of a hidden post returns 404" do
    @post.update_column(:removed_at, Time.current)
    post login_path, params: { email: "u@example.com", password: "pass123" }
    post post_reply_reactions_path(@post, @reply), params: { emoji: "👍" }
    assert_response :not_found
  end

  test "POST on a hidden reply returns 404" do
    @reply.update_column(:removed_at, Time.current)
    post login_path, params: { email: "u@example.com", password: "pass123" }
    post post_reply_reactions_path(@post, @reply), params: { emoji: "👍" }
    assert_response :not_found
  end

  test "DELETE on a hidden reply returns 404" do
    reaction = Reaction.create!(user: @user, reactionable: @reply, emoji: "👍")
    @reply.update_column(:removed_at, Time.current)
    post login_path, params: { email: "u@example.com", password: "pass123" }
    assert_no_difference "Reaction.count" do
      delete post_reply_reaction_path(@post, @reply, reaction)
    end
    assert_response :not_found
  end
end
```

- [ ] **Step A3: Run tests to verify they fail**

```bash
bin/rails test test/models/reaction_test.rb test/controllers/reactions_controller_test.rb
```

Expected: most tests fail because `reactionable` attribute and reply reaction routes don't exist yet.

#### Step B: Migration

- [ ] **Step B1: Generate migration**

```bash
bin/rails generate migration MakeReactionsPolymorphic
```

- [ ] **Step B2: Fill in the migration**

Open the newly-created file in `db/migrate/` (timestamp will vary) and replace its contents with:

```ruby
class MakeReactionsPolymorphic < ActiveRecord::Migration[8.1]
  def change
    # Remove FK and old indexes before touching the column
    remove_foreign_key :reactions, :posts
    remove_index :reactions, name: :index_reactions_on_post_id
    remove_index :reactions, name: :index_reactions_on_user_id_and_post_id

    # Rename post_id to reactionable_id and add the type column
    rename_column :reactions, :post_id, :reactionable_id
    add_column    :reactions, :reactionable_type, :string

    # Backfill all existing rows as Post reactions
    reversible do |dir|
      dir.up { execute "UPDATE reactions SET reactionable_type = 'Post'" }
    end

    # Enforce not-null now that every row has a type
    change_column_null :reactions, :reactionable_type, false

    # Polymorphic indexes
    add_index :reactions, [:reactionable_type, :reactionable_id],
              name: :index_reactions_on_reactionable
    add_index :reactions, [:user_id, :reactionable_type, :reactionable_id],
              unique: true, name: :index_reactions_on_user_and_reactionable
  end
end
```

- [ ] **Step B3: Run the migration**

```bash
bin/rails db:migrate
```

Expected: no errors.

#### Step C: Update models

- [ ] **Step C1: Rewrite `app/models/reaction.rb`**

```ruby
class Reaction < ApplicationRecord
  ALLOWED_REACTIONS = %w[👍 ❤️ 😂 😮].freeze

  belongs_to :user
  belongs_to :reactionable, polymorphic: true

  validates :emoji, presence: true, inclusion: { in: ALLOWED_REACTIONS }
  validates :user_id, uniqueness: { scope: [:reactionable_type, :reactionable_id],
                                    message: "has already reacted" }
end
```

- [ ] **Step C2: Update `app/models/post.rb` — polymorphic association**

Change:
```ruby
# Before
has_many :reactions, dependent: :destroy

# After
has_many :reactions, as: :reactionable, dependent: :destroy
```

- [ ] **Step C3: Update `app/models/reply.rb` — add reactions**

Add after the `scope :visible` line:

```ruby
has_many :reactions, as: :reactionable, dependent: :destroy
```

#### Step D: Helper and shared partial

- [ ] **Step D1: Create `app/helpers/reactions_helper.rb`**

```ruby
module ReactionsHelper
  include ActionView::RecordIdentifier  # gives dom_id to both views and the controller

  # Path to POST a new reaction (create)
  def reaction_create_path(reactionable)
    case reactionable
    when Post  then post_reactions_path(reactionable)
    when Reply then post_reply_reactions_path(reactionable.post, reactionable)
    end
  end

  # Path to DELETE an existing reaction
  def reaction_destroy_path(reactionable, reaction)
    case reactionable
    when Post  then post_reaction_path(reactionable, reaction)
    when Reply then post_reply_reaction_path(reactionable.post, reactionable, reaction)
    end
  end

  # Turbo Frame ID for the reactions widget of any reactionable
  def reactions_frame_id(reactionable)
    "#{dom_id(reactionable)}_reactions"
  end
end
```

- [ ] **Step D2: Create `app/views/reactions/_reactions.html.erb`**

```erb
<%# app/views/reactions/_reactions.html.erb %>
<% user_reaction   = logged_in? ? reactionable.reactions.find_by(user_id: current_user.id) : nil %>
<% reaction_counts = reactionable.reactions.group(:emoji).count %>

<div class="flex flex-wrap gap-2 py-3">
  <% Reaction::ALLOWED_REACTIONS.each do |emoji| %>
    <% count   = reaction_counts[emoji].to_i %>
    <% is_mine = user_reaction&.emoji == emoji %>
    <% if logged_in? %>
      <% if is_mine %>
        <%= button_to "#{emoji}#{count > 0 ? " #{count}" : ""}",
              reaction_destroy_path(reactionable, user_reaction),
              method: :delete,
              class: "inline-flex items-center gap-1 px-3 py-1 rounded-full text-sm border-2 border-teal-500 bg-teal-50 text-teal-700 font-semibold hover:bg-teal-100 cursor-pointer" %>
      <% else %>
        <%= button_to "#{emoji}#{count > 0 ? " #{count}" : ""}",
              reaction_create_path(reactionable),
              params: { emoji: emoji },
              method: :post,
              class: "inline-flex items-center gap-1 px-3 py-1 rounded-full text-sm border border-stone-200 bg-white text-stone-600 hover:border-teal-400 hover:bg-teal-50 cursor-pointer" %>
      <% end %>
    <% else %>
      <span class="inline-flex items-center gap-1 px-3 py-1 rounded-full text-sm border border-stone-200 bg-white text-stone-500">
        <%= emoji %><%= count > 0 ? " #{count}" : "" %>
      </span>
    <% end %>
  <% end %>
</div>
```

- [ ] **Step D3: Delete the now-superseded post-specific partial**

```bash
git rm app/views/posts/_reactions.html.erb
```

#### Step E: Update the controller

- [ ] **Step E1: Rewrite `app/controllers/reactions_controller.rb`**

```ruby
class ReactionsController < ApplicationController
  include ReactionsHelper  # gives controller access to reactions_frame_id

  before_action :require_login
  before_action :set_reactionable

  def create
    emoji = params[:emoji].to_s
    unless Reaction::ALLOWED_REACTIONS.include?(emoji)
      head :unprocessable_entity and return
    end

    Reaction.upsert(
      {
        user_id:           current_user.id,
        reactionable_type: @reactionable.class.name,
        reactionable_id:   @reactionable.id,
        emoji:             emoji,
        created_at:        Time.current,
        updated_at:        Time.current
      },
      unique_by: %i[user_id reactionable_type reactionable_id]
    )

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.update(
          reactions_frame_id(@reactionable),
          partial: "reactions/reactions",
          locals:  { reactionable: @reactionable }
        )
      end
      format.html { redirect_to @post }
    end
  end

  def destroy
    reaction = @reactionable.reactions.find_by(id: params[:id], user_id: current_user.id)
    return head :not_found unless reaction

    reaction.destroy

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.update(
          reactions_frame_id(@reactionable),
          partial: "reactions/reactions",
          locals:  { reactionable: @reactionable }
        )
      end
      format.html { redirect_to @post }
    end
  end

  private

  def set_reactionable
    if params[:reply_id]
      @post        = Post.visible.find(params[:post_id])
      @reactionable = @post.replies.visible.find(params[:reply_id])
    else
      @reactionable = Post.visible.find(params[:post_id])
      @post         = @reactionable
    end
  end
end
```

#### Step F: Update routes

- [ ] **Step F1: Nest reactions under replies in `config/routes.rb`**

Replace the entire `resources :posts` block (keep `resources :reactions` at the post level — only the `replies` line gains a nested block):

```ruby
# Before
resources :posts do
  resources :reactions, only: [ :create, :destroy ]
  resources :replies,   only: [ :create, :destroy, :edit, :update ]
end

# After
resources :posts do
  resources :reactions, only: [ :create, :destroy ]
  resources :replies,   only: [ :create, :destroy, :edit, :update ] do
    resources :reactions, only: [ :create, :destroy ]
  end
end
```

#### Step G: Update the show view

- [ ] **Step G1: Update `app/views/posts/show.html.erb`**

Replace the post reactions turbo frame (around line 48):

```erb
<%# Before %>
<%= turbo_frame_tag "post_reactions_#{@post.id}" do %>
  <%= render "posts/reactions", post: @post %>
<% end %>

<%# After %>
<%= turbo_frame_tag reactions_frame_id(@post) do %>
  <%= render "reactions/reactions", reactionable: @post %>
<% end %>
```

Add reply reactions inside each reply card, immediately after the `reply.edited?` block and before the closing `</div>` of the bottom-row actions section. The full reply card `<% else %>` branch (for non-removed replies) should look like this:

```erb
<%# replace the else branch in each reply card %>
<% else %>
  <p class="text-gray-800 whitespace-pre-wrap"><%= reply.body %></p>
  <% if reply.edited? %>
    <p class="text-xs text-gray-400 mt-1 last-edited-at">last edited at <%= reply.last_edited_at.strftime("%-d %b %Y %H:%M") %></p>
  <% end %>
  <%= turbo_frame_tag reactions_frame_id(reply) do %>
    <%= render "reactions/reactions", reactionable: reply %>
  <% end %>
<% end %>
```

#### Step H: Verify and commit

- [ ] **Step H1: Run the full reaction test suite**

```bash
bin/rails test test/models/reaction_test.rb test/controllers/reactions_controller_test.rb
```

Expected: all green.

- [ ] **Step H2: Run the full CI suite**

```bash
bin/ci
```

Expected: all tests pass, no rubocop violations, no security warnings.

- [ ] **Step H3: Commit**

```bash
git add app/models/reaction.rb app/models/post.rb app/models/reply.rb \
        app/helpers/reactions_helper.rb \
        app/views/reactions/_reactions.html.erb \
        app/controllers/reactions_controller.rb \
        config/routes.rb \
        app/views/posts/show.html.erb \
        db/migrate/ db/structure.sql \
        test/models/reaction_test.rb test/controllers/reactions_controller_test.rb
git commit -m "feat: make reactions polymorphic and add reactions to replies"
```
