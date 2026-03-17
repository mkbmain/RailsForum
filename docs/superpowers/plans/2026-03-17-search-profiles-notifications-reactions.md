# Search, Profiles, Notifications & Reactions — Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add full-text post search, editable user profiles, in-app notifications, and emoji post reactions to the Rails 8.1 forum app.

**Architecture:** Four independent features sharing one migration batch. Reactions use a Turbo Frame + turbo_stream response for instant UI updates. Notification fan-out runs synchronously from controllers via a `NotificationService` class. Search and profiles are plain server-rendered pages.

**Tech Stack:** Rails 8.1, PostgreSQL, Hotwire Turbo (Turbo Frames + Turbo Streams), Tailwind CSS, Minitest.

---

## File Map

**New files:**
- `db/migrate/*_add_bio_to_users.rb` — add `bio` column to users
- `db/migrate/*_create_reactions.rb` — reactions table + indexes
- `db/migrate/*_create_notifications.rb` — notifications table + indexes
- `app/models/reaction.rb` — Reaction model with `ALLOWED_REACTIONS`, validation
- `app/models/notification.rb` — Notification model with enum, `read?` helper
- `app/services/notification_service.rb` — fan-out logic (reply_created, content_removed)
- `app/controllers/search_controller.rb` — single `index` action
- `app/controllers/reactions_controller.rb` — `create` + `destroy` with turbo_stream
- `app/controllers/notifications_controller.rb` — `index`, `read`, `read_all`
- `app/views/search/index.html.erb` — search results page
- `app/views/posts/_reactions.html.erb` — reactions row partial (used in Turbo Frame)
- `app/views/users/show.html.erb` — public profile page
- `app/views/users/edit.html.erb` — edit profile form
- `app/views/notifications/index.html.erb` — notifications list
- `test/models/reaction_test.rb`
- `test/models/notification_test.rb`
- `test/services/notification_service_test.rb`
- `test/controllers/search_controller_test.rb`
- `test/controllers/reactions_controller_test.rb`
- `test/controllers/notifications_controller_test.rb`

**Modified files:**
- `config/routes.rb` — add search, users show/edit/update, notifications, reactions
- `app/views/layouts/application.html.erb` — search form, notification bell, profile link
- `app/views/posts/show.html.erb` — add reactions Turbo Frame above replies
- `app/controllers/users_controller.rb` — add show, edit, update
- `app/controllers/replies_controller.rb` — call NotificationService after create, and on moderator destroy
- `app/controllers/posts_controller.rb` — call NotificationService on destroy
- `app/models/user.rb` — add `has_many :reactions`, `has_many :notifications`
- `app/models/post.rb` — add `has_many :reactions`
- `test/controllers/users_controller_test.rb` — add show/edit/update tests

---

## Task 1: Migrations

**Files:**
- Create: `db/migrate/*_add_bio_to_users.rb`
- Create: `db/migrate/*_create_reactions.rb`
- Create: `db/migrate/*_create_notifications.rb`

- [ ] **Step 1: Generate the three migrations**

```bash
bin/rails generate migration AddBioToUsers bio:text
bin/rails generate migration CreateReactions
bin/rails generate migration CreateNotifications
```

- [ ] **Step 2: Fill in the reactions migration**

Open the generated `db/migrate/*_create_reactions.rb` and replace its body with:

```ruby
class CreateReactions < ActiveRecord::Migration[8.1]
  def change
    create_table :reactions do |t|
      t.references :user, null: false, foreign_key: true
      t.references :post, null: false, foreign_key: true
      t.string :emoji, limit: 10, null: false
      t.timestamps
    end

    add_index :reactions, [:user_id, :post_id], unique: true
  end
end
```

- [ ] **Step 3: Fill in the notifications migration**

Open the generated `db/migrate/*_create_notifications.rb` and replace its body with:

```ruby
class CreateNotifications < ActiveRecord::Migration[8.1]
  def change
    create_table :notifications do |t|
      t.references :user,  null: false, foreign_key: true
      t.references :actor, null: false, foreign_key: { to_table: :users }
      t.references :notifiable, polymorphic: true, null: false
      t.integer :event_type, limit: 2, null: false
      t.datetime :read_at
      t.timestamps
    end

    # Partial index for fast unread counts — only indexes unread rows
    add_index :notifications, :user_id,
              where: "read_at IS NULL",
              name: "index_notifications_on_user_id_unread"

    # Index for 24-hour reply_in_thread deduplication query
    add_index :notifications,
              [:user_id, :notifiable_id, :notifiable_type, :event_type, :created_at],
              name: "index_notifications_on_dedup_fields"
  end
end
```

- [ ] **Step 4: Run migrations**

```bash
bin/rails db:migrate
```

Expected: three migrations run, `db/structure.sql` updated.

- [ ] **Step 5: Commit**

```bash
git add db/migrate/ db/structure.sql
git commit -m "db: add reactions, notifications tables and bio column"
```

---

## Task 2: Routes

**Files:**
- Modify: `config/routes.rb`

- [ ] **Step 1: Replace the existing users and posts resource blocks**

In `config/routes.rb`, the existing code has:
```ruby
resources :posts do
  resources :replies, only: [ :create, :destroy, :edit, :update ]
end

resources :users, only: [] do
  resources :bans, only: [ :new, :create ]
end
```

Replace with:

```ruby
get "/search", to: "search#index"

resources :posts do
  resources :reactions, only: [ :create, :destroy ]
  resources :replies,   only: [ :create, :destroy, :edit, :update ]
end

resources :users, only: [ :show, :edit, :update ] do
  resources :bans, only: [ :new, :create ]
end

resources :notifications, only: [ :index ] do
  collection { patch :read_all }
  member     { patch :read }
end
```

- [ ] **Step 2: Verify routes are correct**

```bash
bin/rails routes | grep -E "search|reactions|notifications|users"
```

Expected output includes:
```
search          GET    /search(.:format)                       search#index
post_reactions  POST   /posts/:post_id/reactions(.:format)     reactions#create
post_reaction   DELETE /posts/:post_id/reactions/:id(.:format) reactions#destroy
user            GET    /users/:id(.:format)                    users#show
edit_user       GET    /users/:id/edit(.:format)               users#edit
                PATCH  /users/:id(.:format)                    users#update
notifications   GET    /notifications(.:format)                notifications#index
read_all_notifications PATCH /notifications/read_all(.:format) notifications#read_all
read_notification      PATCH /notifications/:id/read(.:format) notifications#read
```

- [ ] **Step 3: Commit**

```bash
git add config/routes.rb
git commit -m "routes: add search, reactions, user profiles, notifications"
```

---

## Task 3: Reaction Model

**Files:**
- Create: `test/models/reaction_test.rb`
- Create: `app/models/reaction.rb`
- Modify: `app/models/user.rb`
- Modify: `app/models/post.rb`

- [ ] **Step 1: Write failing tests**

Create `test/models/reaction_test.rb`:

```ruby
require "test_helper"

class ReactionTest < ActiveSupport::TestCase
  setup do
    Provider.find_or_create_by!(id: 3, name: "internal")
    @user = User.create!(email: "reactor@example.com", name: "Reactor",
                         password: "pass123", password_confirmation: "pass123",
                         provider_id: 3)
    @post = Post.create!(user: @user, title: "Post", body: "Body")
  end

  test "valid with an allowed emoji" do
    r = Reaction.new(user: @user, post: @post, emoji: "👍")
    assert r.valid?, r.errors.full_messages.inspect
  end

  test "invalid with an unknown emoji" do
    r = Reaction.new(user: @user, post: @post, emoji: "🦄")
    assert_not r.valid?
    assert_includes r.errors[:emoji], "is not included in the list"
  end

  test "invalid without emoji" do
    r = Reaction.new(user: @user, post: @post, emoji: nil)
    assert_not r.valid?
  end

  test "only one reaction per user per post" do
    Reaction.create!(user: @user, post: @post, emoji: "👍")
    dup = Reaction.new(user: @user, post: @post, emoji: "❤️")
    assert_not dup.valid?
  end

  test "ALLOWED_REACTIONS contains the four expected emoji" do
    assert_equal %w[👍 ❤️ 😂 😮], Reaction::ALLOWED_REACTIONS
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
bin/rails test test/models/reaction_test.rb
```

Expected: errors (constant/model not found).

- [ ] **Step 3: Implement the Reaction model**

Create `app/models/reaction.rb`:

```ruby
class Reaction < ApplicationRecord
  ALLOWED_REACTIONS = %w[👍 ❤️ 😂 😮].freeze

  belongs_to :user
  belongs_to :post

  validates :emoji, presence: true, inclusion: { in: ALLOWED_REACTIONS }
  validates :user_id, uniqueness: { scope: :post_id, message: "has already reacted to this post" }
end
```

- [ ] **Step 4: Add associations to User and Post**

In `app/models/user.rb`, add after the existing `has_many :replies` line:
```ruby
has_many :reactions, dependent: :destroy
has_many :notifications, dependent: :destroy
has_many :sent_notifications, class_name: "Notification", foreign_key: :actor_id, dependent: :destroy
```

In `app/models/post.rb`, add after the existing `has_many :replies` line:
```ruby
has_many :reactions, dependent: :destroy
```

- [ ] **Step 5: Run tests to verify they pass**

```bash
bin/rails test test/models/reaction_test.rb
```

Expected: 5 tests pass.

- [ ] **Step 6: Commit**

```bash
git add app/models/reaction.rb app/models/user.rb app/models/post.rb test/models/reaction_test.rb
git commit -m "feat: add Reaction model with allowed emoji validation"
```

---

## Task 4: Reactions Controller & Views

**Files:**
- Create: `test/controllers/reactions_controller_test.rb`
- Create: `app/controllers/reactions_controller.rb`
- Create: `app/views/posts/_reactions.html.erb`
- Modify: `app/views/posts/show.html.erb`

- [ ] **Step 1: Write failing controller tests**

Create `test/controllers/reactions_controller_test.rb`:

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
  end

  test "POST creates a reaction when logged in" do
    post login_path, params: { email: "u@example.com", password: "pass123" }
    assert_difference "Reaction.count", 1 do
      post post_reactions_path(@post), params: { emoji: "👍" }
    end
  end

  test "POST rejects invalid emoji with 422" do
    post login_path, params: { email: "u@example.com", password: "pass123" }
    assert_no_difference "Reaction.count" do
      post post_reactions_path(@post), params: { emoji: "🦄" }
    end
    assert_response :unprocessable_entity
  end

  test "POST upserts — changes emoji rather than creating a second row" do
    post login_path, params: { email: "u@example.com", password: "pass123" }
    post post_reactions_path(@post), params: { emoji: "👍" }
    assert_no_difference "Reaction.count" do
      post post_reactions_path(@post), params: { emoji: "❤️" }
    end
    assert_equal "❤️", Reaction.find_by(user: @user, post: @post).emoji
  end

  test "POST requires login" do
    assert_no_difference "Reaction.count" do
      post post_reactions_path(@post), params: { emoji: "👍" }
    end
    assert_redirected_to login_path
  end

  test "DELETE destroys own reaction" do
    post login_path, params: { email: "u@example.com", password: "pass123" }
    reaction = Reaction.create!(user: @user, post: @post, emoji: "👍")
    assert_difference "Reaction.count", -1 do
      delete post_reaction_path(@post, reaction)
    end
  end

  test "DELETE cannot destroy another user's reaction" do
    reaction = Reaction.create!(user: @other, post: @post, emoji: "👍")
    post login_path, params: { email: "u@example.com", password: "pass123" }
    assert_no_difference "Reaction.count" do
      delete post_reaction_path(@post, reaction)
    end
    assert_response :not_found
  end

  test "DELETE requires login" do
    reaction = Reaction.create!(user: @user, post: @post, emoji: "👍")
    assert_no_difference "Reaction.count" do
      delete post_reaction_path(@post, reaction)
    end
    assert_redirected_to login_path
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
bin/rails test test/controllers/reactions_controller_test.rb
```

Expected: errors (controller not found).

- [ ] **Step 3: Implement ReactionsController**

Create `app/controllers/reactions_controller.rb`:

```ruby
class ReactionsController < ApplicationController
  before_action :require_login
  before_action :set_post

  def create
    emoji = params[:emoji].to_s
    unless Reaction::ALLOWED_REACTIONS.include?(emoji)
      head :unprocessable_entity and return
    end

    Reaction.upsert(
      { user_id: current_user.id, post_id: @post.id, emoji: emoji, created_at: Time.current, updated_at: Time.current },
      unique_by: %i[user_id post_id]
    )

    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.update("post_reactions_#{@post.id}", partial: "posts/reactions", locals: { post: @post }) }
      format.html         { redirect_to @post }
    end
  end

  def destroy
    reaction = @post.reactions.find_by(id: params[:id], user_id: current_user.id)
    return head :not_found unless reaction

    reaction.destroy

    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.update("post_reactions_#{@post.id}", partial: "posts/reactions", locals: { post: @post }) }
      format.html         { redirect_to @post }
    end
  end

  private

  def set_post
    @post = Post.find(params[:post_id])
  end
end
```

- [ ] **Step 4: Create the reactions partial**

Create `app/views/posts/_reactions.html.erb`:

```erb
<%# app/views/posts/_reactions.html.erb %>
<% user_reaction = logged_in? ? post.reactions.find_by(user_id: current_user.id) : nil %>
<% reaction_counts = post.reactions.group(:emoji).count %>

<div class="flex flex-wrap gap-2 py-3">
  <% Reaction::ALLOWED_REACTIONS.each do |emoji| %>
    <% count = reaction_counts[emoji].to_i %>
    <% is_mine = user_reaction&.emoji == emoji %>
    <% if logged_in? %>
      <% if is_mine %>
        <%= button_to "#{emoji}#{count > 0 ? " #{count}" : ""}",
              post_reaction_path(post, user_reaction),
              method: :delete,
              class: "inline-flex items-center gap-1 px-3 py-1 rounded-full text-sm border-2 border-teal-500 bg-teal-50 text-teal-700 font-semibold hover:bg-teal-100 cursor-pointer" %>
      <% else %>
        <%= button_to "#{emoji}#{count > 0 ? " #{count}" : ""}",
              post_reactions_path(post),
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

- [ ] **Step 5: Add the Turbo Frame to posts/show**

In `app/views/posts/show.html.erb`, find the end of the post body section — after the `<% if @post.edited? %>` block and before `<% end %>` (closing the `<% else %>` block for removed posts). Insert the reactions frame just before that closing `<% end %>`:

Find this section (around line 44–48):
```erb
    <div class="mt-4 text-gray-800 whitespace-pre-wrap"><%= @post.body %></div>
    <% if @post.edited? %>
      <p class="text-xs text-gray-400 mt-2 last-edited-at">last edited at <%= @post.last_edited_at.strftime("%-d %b %Y %H:%M") %></p>
    <% end %>
  <% end %>
```

Replace with:
```erb
    <div class="mt-4 text-gray-800 whitespace-pre-wrap"><%= @post.body %></div>
    <% if @post.edited? %>
      <p class="text-xs text-gray-400 mt-2 last-edited-at">last edited at <%= @post.last_edited_at.strftime("%-d %b %Y %H:%M") %></p>
    <% end %>
    <%= turbo_frame_tag "post_reactions_#{@post.id}" do %>
      <%= render "posts/reactions", post: @post %>
    <% end %>
  <% end %>
```

- [ ] **Step 6: Run tests**

```bash
bin/rails test test/controllers/reactions_controller_test.rb
```

Expected: 7 tests pass.

- [ ] **Step 7: Run full suite to check for regressions**

```bash
bin/rails test
```

Expected: all tests pass.

- [ ] **Step 8: Commit**

```bash
git add app/controllers/reactions_controller.rb app/views/posts/_reactions.html.erb app/views/posts/show.html.erb test/controllers/reactions_controller_test.rb
git commit -m "feat: add emoji reactions to posts with Turbo Frame updates"
```

---

## Task 5: Search

**Files:**
- Create: `test/controllers/search_controller_test.rb`
- Create: `app/controllers/search_controller.rb`
- Create: `app/views/search/index.html.erb`

- [ ] **Step 1: Write failing tests**

Create `test/controllers/search_controller_test.rb`:

```ruby
require "test_helper"

class SearchControllerTest < ActionDispatch::IntegrationTest
  setup do
    Provider.find_or_create_by!(id: 3, name: "internal")
    @user = User.create!(email: "searcher@example.com", name: "Searcher",
                         password: "pass123", password_confirmation: "pass123",
                         provider_id: 3)
    @post = Post.create!(user: @user, title: "Ruby on Rails tips", body: "Use strong params always")
  end

  test "GET /search renders page" do
    get search_path
    assert_response :success
  end

  test "GET /search with query returns matching posts" do
    get search_path, params: { q: "Rails" }
    assert_response :success
    assert_select "a", text: /Ruby on Rails tips/
  end

  test "GET /search matches on body text" do
    get search_path, params: { q: "strong params" }
    assert_response :success
    assert_select "a", text: /Ruby on Rails tips/
  end

  test "GET /search is case-insensitive" do
    get search_path, params: { q: "ruby on rails" }
    assert_response :success
    assert_select "a", text: /Ruby on Rails tips/
  end

  test "GET /search excludes removed posts" do
    @post.update_column(:removed_at, Time.current)
    get search_path, params: { q: "Rails" }
    assert_response :success
    assert_select "a", text: /Ruby on Rails tips/, count: 0
  end

  test "GET /search with no results shows empty state" do
    get search_path, params: { q: "xyzzy123notfound" }
    assert_response :success
    assert_select "p", text: /No posts found/
  end

  test "GET /search filters by category" do
    cat2 = Category.create!(name: "Meta")
    other = Post.create!(user: @user, title: "Rails and Meta", body: "body", category_id: cat2.id)
    get search_path, params: { q: "Rails", category: cat2.id }
    assert_response :success
    assert_select "a", text: /Rails and Meta/
    assert_select "a", text: /Ruby on Rails tips/, count: 0
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
bin/rails test test/controllers/search_controller_test.rb
```

Expected: errors (controller not found).

- [ ] **Step 3: Implement SearchController**

Create `app/controllers/search_controller.rb`:

```ruby
class SearchController < ApplicationController
  def index
    @query      = params[:q].to_s.strip
    @categories = Category.all.order(:name)
    @take       = (params[:take] || 10).to_i.clamp(1, 100)
    @page       = [ (params[:page] || 1).to_i, 1 ].max

    if @query.present?
      posts = Post.visible
                  .includes(:user, :category)
                  .where("title ILIKE :q OR body ILIKE :q", q: "%#{@query}%")

      category_id = params[:category].to_i
      posts = posts.where(category_id: category_id) if category_id > 0

      posts = posts.order(Arel.sql("COALESCE(last_replied_at, created_at) DESC"))
      @total = posts.count
      @posts = posts.limit(@take).offset((@page - 1) * @take)
    else
      @posts = []
      @total = 0
    end
  end
end
```

- [ ] **Step 4: Create the search results view**

Create `app/views/search/index.html.erb`:

```erb
<%# app/views/search/index.html.erb %>
<div class="max-w-7xl mx-auto mt-8 px-4 pb-12">
  <div class="flex gap-8">

    <%# Sidebar %>
    <aside class="hidden lg:block w-64 shrink-0">
      <div class="sticky top-4">
        <p class="text-xs font-semibold uppercase tracking-wide text-stone-400 mb-3">Filter by Category</p>
        <nav class="flex flex-col gap-1">
          <%= link_to "All Categories", search_path(q: @query, take: @take),
                class: "px-3 py-2 rounded-lg text-sm block #{params[:category].blank? ? 'bg-teal-50 text-teal-700 font-semibold' : 'text-stone-600 hover:bg-stone-100'}" %>
          <% @categories.each do |cat| %>
            <%= link_to cat.name, search_path(q: @query, category: cat.id, take: @take),
                  class: "px-3 py-2 rounded-lg text-sm block #{params[:category].to_i == cat.id ? 'bg-teal-50 text-teal-700 font-semibold' : 'text-stone-600 hover:bg-stone-100'}" %>
          <% end %>
        </nav>
      </div>
    </aside>

    <%# Results %>
    <div class="flex-1 min-w-0">

      <% if @query.present? %>
        <p class="text-sm text-stone-500 mb-4">
          <% if @total > 0 %>
            <%= @total %> result<%= @total == 1 ? "" : "s" %> for <strong>"<%= @query %>"</strong>
          <% end %>
        </p>
      <% end %>

      <% if @posts.empty? %>
        <div class="bg-white border border-stone-200 rounded-xl p-8 text-center">
          <% if @query.present? %>
            <p class="text-stone-400 text-sm">No posts found for "<%= @query %>".</p>
          <% else %>
            <p class="text-stone-400 text-sm">Enter a search term above to find posts.</p>
          <% end %>
        </div>
      <% else %>
        <div class="space-y-4">
          <% @posts.each do |post| %>
            <div class="bg-white border border-stone-200 rounded-xl shadow-sm p-5 hover:border-teal-300 hover:shadow-md transition-all">
              <div class="flex items-center justify-between mb-2">
                <%= link_to post.category.name,
                      search_path(q: @query, category: post.category_id, take: @take),
                      class: "bg-teal-100 text-teal-800 text-xs font-medium px-2 py-0.5 rounded-full hover:bg-teal-200" %>
                <span class="text-xs text-stone-400"><%= time_ago_in_words(post.last_activity_at) %> ago</span>
              </div>
              <h2 class="text-lg font-semibold">
                <%= link_to post.title, post_path(post), class: "text-stone-900 hover:text-teal-700" %>
              </h2>
              <p class="text-sm text-stone-500 line-clamp-2 mt-1">
                <%= truncate(strip_tags(post.body), length: 200) %>
              </p>
              <div class="flex items-center gap-2 mt-3 pt-3 border-t border-stone-100">
                <span class="text-sm font-medium text-stone-700"><%= post.user.name %></span>
              </div>
            </div>
          <% end %>
        </div>

        <div class="flex justify-between mt-6">
          <% if @page > 1 %>
            <%= link_to "← Previous", search_path(q: @query, category: params[:category], take: @take, page: @page - 1),
                  class: "text-teal-700 hover:underline font-medium text-sm" %>
          <% else %>
            <span></span>
          <% end %>
          <% if @posts.size >= @take %>
            <%= link_to "Next →", search_path(q: @query, category: params[:category], take: @take, page: @page + 1),
                  class: "text-teal-700 hover:underline font-medium text-sm" %>
          <% end %>
        </div>
      <% end %>

    </div>
  </div>
</div>
```

- [ ] **Step 5: Run tests**

```bash
bin/rails test test/controllers/search_controller_test.rb
```

Expected: 7 tests pass.

- [ ] **Step 6: Commit**

```bash
git add app/controllers/search_controller.rb app/views/search/ test/controllers/search_controller_test.rb
git commit -m "feat: add post search by title and body"
```

---

## Task 6: User Profiles — Show

**Files:**
- Modify: `test/controllers/users_controller_test.rb`
- Modify: `app/controllers/users_controller.rb`
- Create: `app/views/users/show.html.erb`

- [ ] **Step 1: Write failing tests**

Open `test/controllers/users_controller_test.rb` and add these tests after the existing ones:

```ruby
  test "GET /users/:id shows public profile" do
    Provider.find_or_create_by!(id: 3, name: "internal")
    user = User.create!(email: "profile@example.com", name: "Profile User",
                        password: "pass123", password_confirmation: "pass123",
                        provider_id: 3)
    get user_path(user)
    assert_response :success
    assert_select "h1", text: /Profile User/
  end

  test "GET /users/:id shows profile without login" do
    Provider.find_or_create_by!(id: 3, name: "internal")
    user = User.create!(email: "pub@example.com", name: "Public User",
                        password: "pass123", password_confirmation: "pass123",
                        provider_id: 3)
    get user_path(user)
    assert_response :success
  end
```

- [ ] **Step 2: Run new tests to verify they fail**

```bash
bin/rails test test/controllers/users_controller_test.rb
```

Expected: the two new tests fail with routing or action errors.

- [ ] **Step 3: Add show action and helpers to UsersController**

In `app/controllers/users_controller.rb`, add the following before the `private` section (or after the existing `create` action):

```ruby
  before_action :set_profile_user, only: [ :show, :edit, :update ]
  before_action :require_owner,    only: [ :edit, :update ]

  def show
    page = [ (params[:page] || 1).to_i, 1 ].max
    per  = 20

    recent_posts   = @profile_user.posts.visible.includes(:category)
                                   .order(created_at: :desc).limit(per * page + 1).to_a
    recent_replies = @profile_user.replies.visible.includes(:post)
                                   .order(created_at: :desc).limit(per * page + 1).to_a

    combined = (recent_posts.map  { |p| { type: :post,  record: p, created_at: p.created_at } } +
                recent_replies.map { |r| { type: :reply, record: r, created_at: r.created_at } })
               .sort_by { |item| -item[:created_at].to_i }

    offset        = (page - 1) * per
    @has_more     = combined.size > offset + per
    @activity     = combined[offset, per] || []
    @post_count   = @profile_user.posts.visible.count
    @reply_count  = @profile_user.replies.visible.count
    @page         = page
  end
```

And add to the `private` section:

```ruby
  def set_profile_user
    @profile_user = User.find(params[:id])
  end

  def require_owner
    unless @profile_user == current_user
      redirect_to root_path, alert: "Not authorized."
    end
  end
```

Also add `before_action :require_login` to the existing before_action for `new` and `create` — check what's currently there and extend it to cover edit/update. It should become:

```ruby
before_action :require_login, only: [ :new, :create, :edit, :update ]
```

- [ ] **Step 4: Create the profile view**

Create `app/views/users/show.html.erb`:

```erb
<%# app/views/users/show.html.erb %>
<div class="max-w-3xl mx-auto mt-8 px-4 pb-12">
  <%= link_to "← Back to Forum", posts_path, class: "text-blue-600 hover:underline text-sm" %>

  <%# Profile header %>
  <div class="bg-white border border-stone-200 rounded-xl p-6 mt-4">
    <div class="flex items-start gap-4">
      <% if @profile_user.avatar_url.present? %>
        <%= image_tag @profile_user.avatar_url, class: "w-16 h-16 rounded-full", alt: "" %>
      <% else %>
        <span class="w-16 h-16 rounded-full bg-teal-100 text-teal-700 font-bold flex items-center justify-center text-2xl">
          <%= (@profile_user.name.presence || "?").first.upcase %>
        </span>
      <% end %>
      <div class="flex-1 min-w-0">
        <div class="flex items-center justify-between">
          <h1 class="text-2xl font-bold text-stone-900"><%= @profile_user.name %></h1>
          <% if logged_in? && current_user == @profile_user %>
            <%= link_to "Edit Profile", edit_user_path(@profile_user),
                  class: "text-sm text-blue-500 hover:underline" %>
          <% end %>
        </div>
        <p class="text-sm text-stone-400 mt-0.5">
          Member since <%= @profile_user.created_at.strftime("%B %Y") %>
        </p>
        <div class="flex gap-4 mt-1 text-sm text-stone-500">
          <span><strong class="text-stone-700"><%= @post_count %></strong> posts</span>
          <span><strong class="text-stone-700"><%= @reply_count %></strong> replies</span>
        </div>
        <% if @profile_user.bio.present? %>
          <p class="mt-3 text-stone-700 text-sm"><%= @profile_user.bio %></p>
        <% end %>
      </div>
    </div>
  </div>

  <%# Activity feed %>
  <div class="mt-8">
    <h2 class="text-lg font-semibold text-stone-800 mb-4">Activity</h2>

    <% if @activity.empty? %>
      <p class="text-stone-400 text-sm">No activity yet.</p>
    <% else %>
      <div class="space-y-3">
        <% @activity.each do |item| %>
          <% if item[:type] == :post %>
            <% p = item[:record] %>
            <div class="bg-white border border-stone-200 rounded-xl p-4">
              <div class="flex items-center gap-2 mb-1">
                <span class="text-xs px-2 py-0.5 bg-teal-100 text-teal-700 rounded-full font-medium">Post</span>
                <span class="text-xs text-stone-400"><%= time_ago_in_words(p.created_at) %> ago</span>
              </div>
              <h3 class="font-semibold">
                <%= link_to p.title, post_path(p), class: "text-stone-900 hover:text-teal-700" %>
              </h3>
            </div>
          <% else %>
            <% r = item[:record] %>
            <div class="bg-white border border-stone-200 rounded-xl p-4">
              <div class="flex items-center gap-2 mb-1">
                <span class="text-xs px-2 py-0.5 bg-stone-100 text-stone-600 rounded-full font-medium">Reply</span>
                <span class="text-xs text-stone-400"><%= time_ago_in_words(r.created_at) %> ago in</span>
                <%= link_to r.post.title, post_path(r.post), class: "text-xs text-blue-500 hover:underline truncate max-w-xs" %>
              </div>
              <p class="text-sm text-stone-600 line-clamp-2"><%= truncate(r.body, length: 150) %></p>
            </div>
          <% end %>
        <% end %>
      </div>

      <div class="flex justify-between mt-6">
        <% if @page > 1 %>
          <%= link_to "← Newer", user_path(@profile_user, page: @page - 1),
                class: "text-teal-700 hover:underline font-medium text-sm" %>
        <% else %>
          <span></span>
        <% end %>
        <% if @has_more %>
          <%= link_to "Older →", user_path(@profile_user, page: @page + 1),
                class: "text-teal-700 hover:underline font-medium text-sm" %>
        <% end %>
      </div>
    <% end %>
  </div>
</div>
```

- [ ] **Step 5: Run tests**

```bash
bin/rails test test/controllers/users_controller_test.rb
```

Expected: all tests pass, including the two new ones.

- [ ] **Step 6: Commit**

```bash
git add app/controllers/users_controller.rb app/views/users/show.html.erb test/controllers/users_controller_test.rb
git commit -m "feat: add public user profile pages"
```

---

## Task 7: User Profiles — Edit & Update

**Files:**
- Modify: `test/controllers/users_controller_test.rb`
- Modify: `app/controllers/users_controller.rb`
- Create: `app/views/users/edit.html.erb`

- [ ] **Step 1: Write failing tests**

Add to `test/controllers/users_controller_test.rb`:

```ruby
  test "GET /users/:id/edit requires login" do
    Provider.find_or_create_by!(id: 3, name: "internal")
    user = User.create!(email: "edit@example.com", name: "Edit User",
                        password: "pass123", password_confirmation: "pass123",
                        provider_id: 3)
    get edit_user_path(user)
    assert_redirected_to login_path
  end

  test "GET /users/:id/edit is forbidden for other users" do
    Provider.find_or_create_by!(id: 3, name: "internal")
    owner = User.create!(email: "owner@example.com", name: "Owner",
                         password: "pass123", password_confirmation: "pass123",
                         provider_id: 3)
    other = User.create!(email: "intruder@example.com", name: "Intruder",
                         password: "pass123", password_confirmation: "pass123",
                         provider_id: 3)
    post login_path, params: { email: "intruder@example.com", password: "pass123" }
    get edit_user_path(owner)
    assert_redirected_to root_path
  end

  test "PATCH /users/:id updates name and bio" do
    Provider.find_or_create_by!(id: 3, name: "internal")
    user = User.create!(email: "patch@example.com", name: "Old Name",
                        password: "pass123", password_confirmation: "pass123",
                        provider_id: 3)
    post login_path, params: { email: "patch@example.com", password: "pass123" }
    patch user_path(user), params: { user: { name: "New Name", bio: "Hello!" } }
    assert_redirected_to user_path(user)
    assert_equal "New Name", user.reload.name
    assert_equal "Hello!",   user.reload.bio
  end

  test "PATCH /users/:id changes password with correct current password" do
    Provider.find_or_create_by!(id: 3, name: "internal")
    user = User.create!(email: "pwchange@example.com", name: "PW User",
                        password: "pass123", password_confirmation: "pass123",
                        provider_id: 3)
    post login_path, params: { email: "pwchange@example.com", password: "pass123" }
    patch user_path(user), params: { user: { name: "PW User", current_password: "pass123",
                                              password: "newpass456", password_confirmation: "newpass456" } }
    assert_redirected_to user_path(user)
    assert user.reload.authenticate("newpass456")
  end

  test "PATCH /users/:id rejects wrong current password" do
    Provider.find_or_create_by!(id: 3, name: "internal")
    user = User.create!(email: "badpw@example.com", name: "Bad PW",
                        password: "pass123", password_confirmation: "pass123",
                        provider_id: 3)
    post login_path, params: { email: "badpw@example.com", password: "pass123" }
    patch user_path(user), params: { user: { name: "Bad PW", current_password: "WRONG",
                                              password: "newpass456", password_confirmation: "newpass456" } }
    assert_response :unprocessable_entity
    assert user.reload.authenticate("pass123"), "Password should not have changed"
  end
```

- [ ] **Step 2: Run to verify they fail**

```bash
bin/rails test test/controllers/users_controller_test.rb
```

Expected: new tests fail.

- [ ] **Step 3: Implement edit and update in UsersController**

Add these actions to `app/controllers/users_controller.rb`:

```ruby
  def edit
  end

  def update
    permitted = params.require(:user).permit(:name, :bio, :current_password, :password, :password_confirmation)

    if permitted[:password].present?
      unless @profile_user.authenticate(permitted[:current_password].to_s)
        @profile_user.errors.add(:base, "Current password is incorrect")
        render :edit, status: :unprocessable_entity and return
      end
      attrs = permitted.except(:current_password).to_h
    else
      attrs = permitted.slice(:name, :bio).to_h
    end

    if @profile_user.update(attrs)
      redirect_to user_path(@profile_user), notice: "Profile updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end
```

- [ ] **Step 4: Create the edit view**

Create `app/views/users/edit.html.erb`:

```erb
<%# app/views/users/edit.html.erb %>
<div class="max-w-lg mx-auto mt-8 px-4 pb-12">
  <%= link_to "← Back to Profile", user_path(@profile_user), class: "text-blue-600 hover:underline text-sm" %>

  <div class="bg-white border border-stone-200 rounded-xl p-6 mt-4">
    <h1 class="text-xl font-bold mb-6">Edit Profile</h1>

    <%= form_with model: @profile_user, url: user_path(@profile_user), method: :patch, class: "space-y-5" do |f| %>
      <% if @profile_user.errors.any? %>
        <div class="bg-red-50 border border-red-200 text-red-700 px-3 py-2 rounded text-sm">
          <%= @profile_user.errors.full_messages.to_sentence %>
        </div>
      <% end %>

      <div>
        <%= f.label :name, class: "block text-sm font-medium text-stone-700 mb-1" %>
        <%= f.text_field :name, class: "w-full border border-stone-300 rounded-md px-3 py-2 focus:outline-none focus:ring-2 focus:ring-teal-500" %>
      </div>

      <div>
        <%= f.label :bio, class: "block text-sm font-medium text-stone-700 mb-1" %>
        <%= f.text_area :bio, rows: 3, placeholder: "Tell people a bit about yourself...",
              class: "w-full border border-stone-300 rounded-md px-3 py-2 focus:outline-none focus:ring-2 focus:ring-teal-500" %>
      </div>

      <% if @profile_user.internal? %>
        <div class="border-t border-stone-200 pt-5">
          <h2 class="text-sm font-semibold text-stone-700 mb-3">Change Password</h2>
          <div class="space-y-3">
            <div>
              <%= f.label :current_password, "Current Password", class: "block text-sm font-medium text-stone-700 mb-1" %>
              <%= f.password_field :current_password, autocomplete: "current-password",
                    class: "w-full border border-stone-300 rounded-md px-3 py-2 focus:outline-none focus:ring-2 focus:ring-teal-500" %>
            </div>
            <div>
              <%= f.label :password, "New Password", class: "block text-sm font-medium text-stone-700 mb-1" %>
              <%= f.password_field :password, autocomplete: "new-password",
                    class: "w-full border border-stone-300 rounded-md px-3 py-2 focus:outline-none focus:ring-2 focus:ring-teal-500" %>
            </div>
            <div>
              <%= f.label :password_confirmation, "Confirm New Password", class: "block text-sm font-medium text-stone-700 mb-1" %>
              <%= f.password_field :password_confirmation, autocomplete: "new-password",
                    class: "w-full border border-stone-300 rounded-md px-3 py-2 focus:outline-none focus:ring-2 focus:ring-teal-500" %>
            </div>
          </div>
        </div>
      <% end %>

      <%= f.submit "Save Changes",
            class: "bg-teal-700 text-white px-5 py-2 rounded-lg hover:bg-teal-600 font-semibold" %>
    <% end %>
  </div>
</div>
```

- [ ] **Step 5: Run tests**

```bash
bin/rails test test/controllers/users_controller_test.rb
```

Expected: all tests pass.

- [ ] **Step 6: Run full suite**

```bash
bin/rails test
```

Expected: all tests pass.

- [ ] **Step 7: Commit**

```bash
git add app/controllers/users_controller.rb app/views/users/edit.html.erb test/controllers/users_controller_test.rb
git commit -m "feat: add user profile edit with bio and password change"
```

---

## Task 8: Notification Model

**Files:**
- Create: `test/models/notification_test.rb`
- Create: `app/models/notification.rb`

- [ ] **Step 1: Write failing tests**

Create `test/models/notification_test.rb`:

```ruby
require "test_helper"

class NotificationTest < ActiveSupport::TestCase
  setup do
    Provider.find_or_create_by!(id: 3, name: "internal")
    @user  = User.create!(email: "notif@example.com",  name: "Notif User",
                          password: "pass123", password_confirmation: "pass123", provider_id: 3)
    @actor = User.create!(email: "actor@example.com", name: "Actor",
                          password: "pass123", password_confirmation: "pass123", provider_id: 3)
    @post  = Post.create!(user: @user, title: "Post", body: "Body")
    @reply = Reply.create!(post: @post, user: @actor, body: "A reply")
  end

  test "valid notification" do
    n = Notification.new(user: @user, actor: @actor, notifiable: @reply, event_type: :reply_to_post)
    assert n.valid?, n.errors.full_messages.inspect
  end

  test "requires user" do
    n = Notification.new(actor: @actor, notifiable: @reply, event_type: :reply_to_post)
    assert_not n.valid?
  end

  test "requires actor" do
    n = Notification.new(user: @user, notifiable: @reply, event_type: :reply_to_post)
    assert_not n.valid?
  end

  test "requires notifiable" do
    n = Notification.new(user: @user, actor: @actor, event_type: :reply_to_post)
    assert_not n.valid?
  end

  test "read? returns false when read_at is nil" do
    n = Notification.create!(user: @user, actor: @actor, notifiable: @reply, event_type: :reply_to_post)
    assert_not n.read?
  end

  test "read? returns true when read_at is set" do
    n = Notification.create!(user: @user, actor: @actor, notifiable: @reply, event_type: :reply_to_post)
    n.update_column(:read_at, Time.current)
    assert n.read?
  end

  test "all event_type values are accessible" do
    %i[reply_to_post reply_in_thread mention moderation].each do |type|
      n = Notification.new(user: @user, actor: @actor, notifiable: @reply, event_type: type)
      assert n.valid?, "Expected #{type} to be valid: #{n.errors.full_messages}"
    end
  end
end
```

- [ ] **Step 2: Run to verify failure**

```bash
bin/rails test test/models/notification_test.rb
```

Expected: errors (model not found).

- [ ] **Step 3: Implement the Notification model**

Create `app/models/notification.rb`:

```ruby
class Notification < ApplicationRecord
  belongs_to :user
  belongs_to :actor, class_name: "User"
  belongs_to :notifiable, polymorphic: true

  enum :event_type, { reply_to_post: 0, reply_in_thread: 1, mention: 2, moderation: 3 }

  def read?
    read_at.present?
  end
end
```

- [ ] **Step 4: Run tests**

```bash
bin/rails test test/models/notification_test.rb
```

Expected: 7 tests pass.

- [ ] **Step 5: Commit**

```bash
git add app/models/notification.rb test/models/notification_test.rb
git commit -m "feat: add Notification model with event_type enum"
```

---

## Task 9: NotificationService

**Files:**
- Create: `test/services/notification_service_test.rb`
- Create: `app/services/notification_service.rb`

- [ ] **Step 1: Write failing tests**

Create `test/services/notification_service_test.rb`:

```ruby
require "test_helper"

class NotificationServiceTest < ActiveSupport::TestCase
  setup do
    Provider.find_or_create_by!(id: 3, name: "internal")
    @post_owner = User.create!(email: "owner@example.com", name: "owner",
                               password: "pass123", password_confirmation: "pass123", provider_id: 3)
    @replier    = User.create!(email: "replier@example.com", name: "replier",
                               password: "pass123", password_confirmation: "pass123", provider_id: 3)
    @participant = User.create!(email: "part@example.com", name: "participant",
                                password: "pass123", password_confirmation: "pass123", provider_id: 3)
    @post  = Post.create!(user: @post_owner, title: "My Post", body: "content")
    # participant has previously replied
    Reply.create!(post: @post, user: @participant, body: "earlier reply")
    @reply = Reply.create!(post: @post, user: @replier, body: "new reply")
  end

  # --- reply_created ---

  test "notifies post owner with reply_to_post" do
    assert_difference "Notification.where(event_type: :reply_to_post).count", 1 do
      NotificationService.reply_created(@reply, current_user: @replier)
    end
    n = Notification.find_by(user: @post_owner, event_type: :reply_to_post)
    assert_not_nil n
    assert_equal @replier, n.actor
    assert_equal @reply, n.notifiable
  end

  test "does not notify post owner with reply_in_thread (only reply_to_post)" do
    NotificationService.reply_created(@reply, current_user: @replier)
    assert_nil Notification.find_by(user: @post_owner, event_type: :reply_in_thread)
  end

  test "notifies thread participant with reply_in_thread" do
    assert_difference "Notification.where(event_type: :reply_in_thread).count", 1 do
      NotificationService.reply_created(@reply, current_user: @replier)
    end
    n = Notification.find_by(user: @participant, event_type: :reply_in_thread)
    assert_not_nil n
  end

  test "does not notify actor about their own reply" do
    NotificationService.reply_created(@reply, current_user: @replier)
    assert_nil Notification.find_by(user: @replier)
  end

  test "does not send reply_in_thread if already notified within 24 hours" do
    # Pre-create a recent notification for the participant on this post
    Notification.create!(
      user: @participant, actor: @replier,
      notifiable: @post, event_type: :reply_in_thread,
      created_at: 1.hour.ago
    )
    assert_no_difference "Notification.where(event_type: :reply_in_thread, user: @participant).count" do
      reply2 = Reply.create!(post: @post, user: @replier, body: "another reply")
      NotificationService.reply_created(reply2, current_user: @replier)
    end
  end

  test "notifies mentioned user" do
    mention_reply = Reply.create!(post: @post, user: @replier, body: "hey @#{@participant.name} check this")
    # participant is already a thread participant — but they should get :mention not :reply_in_thread
    # Actually the test here is for a new user being mentioned who hasn't replied
    new_user = User.create!(email: "new@example.com", name: "newbie",
                            password: "pass123", password_confirmation: "pass123", provider_id: 3)
    reply_with_mention = Reply.create!(post: @post, user: @replier, body: "hey @newbie come look")
    assert_difference "Notification.where(event_type: :mention).count", 1 do
      NotificationService.reply_created(reply_with_mention, current_user: @replier)
    end
    n = Notification.find_by(user: new_user, event_type: :mention)
    assert_not_nil n
  end

  test "does not double-notify: mention does not re-notify a user already notified" do
    # post_owner is already notified via reply_to_post
    reply_mentioning_owner = Reply.create!(post: @post, user: @replier,
                                           body: "hey @#{@post_owner.name} nice post")
    assert_no_difference "Notification.where(user: @post_owner).count" do
      # post_owner already received reply_to_post notification in a previous call;
      # in this single call, they receive reply_to_post, and mention is skipped
      before = Notification.where(user: @post_owner).count
      NotificationService.reply_created(reply_mentioning_owner, current_user: @replier)
      after = Notification.where(user: @post_owner).count
      # only one notification created (reply_to_post), not two
      assert_equal 1, after - before
    end
  end

  test "does not notify for unknown @mention" do
    reply = Reply.create!(post: @post, user: @replier, body: "@nobody_exists here")
    assert_no_difference "Notification.where(event_type: :mention).count" do
      NotificationService.reply_created(reply, current_user: @replier)
    end
  end

  # --- content_removed ---

  test "notifies content owner on moderation" do
    assert_difference "Notification.where(event_type: :moderation).count", 1 do
      NotificationService.content_removed(@post, removed_by: @replier)
    end
    n = Notification.find_by(user: @post_owner, event_type: :moderation)
    assert_equal @replier, n.actor
    assert_equal @post, n.notifiable
  end

  test "does not notify if moderator removes own content" do
    assert_no_difference "Notification.count" do
      NotificationService.content_removed(@post, removed_by: @post_owner)
    end
  end
end
```

- [ ] **Step 2: Run to verify failure**

```bash
bin/rails test test/services/notification_service_test.rb
```

Expected: errors (service not found).

- [ ] **Step 3: Implement NotificationService**

Create `app/services/notification_service.rb`:

```ruby
# NotificationService — handles all in-app notification fan-out.
#
# Designed as a clean boundary: callers invoke class methods here.
# In future, callers can publish to an event bus instead, with no other
# changes required in the rest of the app.
class NotificationService
  def self.reply_created(reply, current_user:)
    actor             = current_user
    post              = reply.post
    already_notified  = Set.new

    # 1. reply_to_post — notify post owner
    if post.user != actor
      Notification.create!(
        user:       post.user,
        actor:      actor,
        notifiable: reply,
        event_type: :reply_to_post
      )
      already_notified.add(post.user.id)
    end

    # 2. reply_in_thread — notify prior participants (deduplicated per 24h)
    recent_thread_notified_ids = Notification
      .where(notifiable_type: "Post", notifiable_id: post.id, event_type: :reply_in_thread)
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
        notifiable_type:  "Post",
        notifiable_id:    post.id,
        event_type:       :reply_in_thread
      )
      already_notified.add(uid)
    end

    # 3. mention — parse @username patterns
    reply.body.scan(/@(\w+)/i).flatten.uniq.each do |username|
      mentioned = User.find_by("LOWER(name) = LOWER(?)", username)
      next unless mentioned
      next if mentioned == actor
      next if already_notified.include?(mentioned.id)

      Notification.create!(
        user:       mentioned,
        actor:      actor,
        notifiable: reply,
        event_type: :mention
      )
      already_notified.add(mentioned.id)
    end
  end

  def self.content_removed(content, removed_by:)
    return if content.user == removed_by

    Notification.create!(
      user:       content.user,
      actor:      removed_by,
      notifiable: content,
      event_type: :moderation
    )
  end
end
```

- [ ] **Step 4: Run tests**

```bash
bin/rails test test/services/notification_service_test.rb
```

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add app/services/notification_service.rb test/services/notification_service_test.rb
git commit -m "feat: add NotificationService with fan-out and deduplication"
```

---

## Task 10: Wire Notification Triggers into Controllers

**Files:**
- Modify: `app/controllers/replies_controller.rb`
- Modify: `app/controllers/posts_controller.rb`
- Modify: `test/controllers/replies_controller_test.rb` (add notification assertions)

- [ ] **Step 1: Add trigger in RepliesController#create**

In `app/controllers/replies_controller.rb`, find the `create` action. After `if @reply.save`, add the notification call:

Find:
```ruby
    if @reply.save
      redirect_to @post, notice: "Reply posted!"
```

Replace with:
```ruby
    if @reply.save
      NotificationService.reply_created(@reply, current_user: current_user)
      redirect_to @post, notice: "Reply posted!"
```

- [ ] **Step 2: Add trigger on moderator destroy in RepliesController#destroy**

In `app/controllers/replies_controller.rb`, find the moderator soft-delete branch:

Find:
```ruby
    if current_user.moderator? && can_moderate?(@reply.user)
      @reply.update!(removed_at: Time.current, removed_by: current_user)
      @post.update_column(:last_replied_at, @post.replies.visible.maximum(:created_at))
      redirect_to @post, notice: "Reply removed."
```

Replace with:
```ruby
    if current_user.moderator? && can_moderate?(@reply.user)
      @reply.update!(removed_at: Time.current, removed_by: current_user)
      @post.update_column(:last_replied_at, @post.replies.visible.maximum(:created_at))
      NotificationService.content_removed(@reply, removed_by: current_user)
      redirect_to @post, notice: "Reply removed."
```

- [ ] **Step 3: Add trigger in PostsController#destroy**

In `app/controllers/posts_controller.rb`, find the `destroy` action. After `@post.update!`:

Find:
```ruby
    @post.update!(removed_at: Time.current, removed_by: current_user)
    redirect_to @post, notice: "Post removed."
```

Replace with:
```ruby
    @post.update!(removed_at: Time.current, removed_by: current_user)
    NotificationService.content_removed(@post, removed_by: current_user)
    redirect_to @post, notice: "Post removed."
```

- [ ] **Step 4: Run the full test suite to check for regressions**

```bash
bin/rails test
```

Expected: all tests pass. (The NotificationService calls won't break existing tests since they create notifications silently — no assertions in existing tests check notification counts.)

- [ ] **Step 5: Commit**

```bash
git add app/controllers/replies_controller.rb app/controllers/posts_controller.rb
git commit -m "feat: wire NotificationService triggers into reply and post controllers"
```

---

## Task 11: Notifications Controller & View

**Files:**
- Create: `test/controllers/notifications_controller_test.rb`
- Create: `app/controllers/notifications_controller.rb`
- Create: `app/views/notifications/index.html.erb`

- [ ] **Step 1: Write failing tests**

Create `test/controllers/notifications_controller_test.rb`:

```ruby
require "test_helper"

class NotificationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    Provider.find_or_create_by!(id: 3, name: "internal")
    @user  = User.create!(email: "nuser@example.com", name: "Nuser",
                          password: "pass123", password_confirmation: "pass123", provider_id: 3)
    @actor = User.create!(email: "nactor@example.com", name: "NActor",
                          password: "pass123", password_confirmation: "pass123", provider_id: 3)
    @post  = Post.create!(user: @user, title: "Post", body: "Body")
    @reply = Reply.create!(post: @post, user: @actor, body: "reply")
    @notif = Notification.create!(user: @user, actor: @actor, notifiable: @reply,
                                  event_type: :reply_to_post)
  end

  test "GET /notifications requires login" do
    get notifications_path
    assert_redirected_to login_path
  end

  test "GET /notifications shows notifications for current user" do
    post login_path, params: { email: "nuser@example.com", password: "pass123" }
    get notifications_path
    assert_response :success
    assert_select "a", text: /NActor/
  end

  test "PATCH /notifications/:id/read marks one notification as read" do
    post login_path, params: { email: "nuser@example.com", password: "pass123" }
    assert_nil @notif.read_at
    patch read_notification_path(@notif)
    assert_redirected_to notifications_path
    assert_not_nil @notif.reload.read_at
  end

  test "PATCH /notifications/:id/read cannot mark another user's notification" do
    other = User.create!(email: "sneaky@example.com", name: "Sneaky",
                         password: "pass123", password_confirmation: "pass123", provider_id: 3)
    post login_path, params: { email: "sneaky@example.com", password: "pass123" }
    patch read_notification_path(@notif)
    assert_nil @notif.reload.read_at
  end

  test "PATCH /notifications/read_all marks all unread notifications as read" do
    notif2 = Notification.create!(user: @user, actor: @actor, notifiable: @reply,
                                   event_type: :mention)
    post login_path, params: { email: "nuser@example.com", password: "pass123" }
    patch read_all_notifications_path
    assert_redirected_to notifications_path
    assert_not_nil @notif.reload.read_at
    assert_not_nil notif2.reload.read_at
  end
end
```

- [ ] **Step 2: Run to verify failure**

```bash
bin/rails test test/controllers/notifications_controller_test.rb
```

Expected: errors (controller not found).

- [ ] **Step 3: Implement NotificationsController**

Create `app/controllers/notifications_controller.rb`:

```ruby
class NotificationsController < ApplicationController
  before_action :require_login

  def index
    @notifications = current_user.notifications
                                  .includes(:actor, :notifiable)
                                  .order(created_at: :desc)
                                  .limit(30)
    @unread_count  = current_user.notifications.where(read_at: nil).count
  end

  def read
    notification = current_user.notifications.find_by(id: params[:id])
    notification&.update(read_at: Time.current)
    redirect_to notifications_path
  end

  def read_all
    current_user.notifications.where(read_at: nil).update_all(read_at: Time.current)
    redirect_to notifications_path
  end
end
```

- [ ] **Step 4: Create the notifications view**

Create `app/views/notifications/index.html.erb`:

```erb
<%# app/views/notifications/index.html.erb %>
<div class="max-w-2xl mx-auto mt-8 px-4 pb-12">
  <div class="flex items-center justify-between mb-6">
    <h1 class="text-2xl font-bold text-stone-900">Notifications</h1>
    <% if @unread_count > 0 %>
      <%= button_to "Mark all read", read_all_notifications_path, method: :patch,
            class: "text-sm text-teal-700 hover:underline bg-transparent border-0 p-0 cursor-pointer font-medium" %>
    <% end %>
  </div>

  <% if @notifications.empty? %>
    <div class="bg-white border border-stone-200 rounded-xl p-8 text-center">
      <p class="text-stone-400 text-sm">No notifications yet.</p>
    </div>
  <% else %>
    <div class="space-y-2">
      <% @notifications.each do |n| %>
        <% post_link = n.notifiable.is_a?(Post) ? post_path(n.notifiable) : post_path(n.notifiable.post) %>
        <div class="bg-white border border-stone-200 rounded-xl p-4 flex items-start gap-3 <%= n.read? ? '' : 'bg-teal-50 border-teal-200' %>">
          <%# Actor avatar %>
          <% if n.actor.avatar_url.present? %>
            <%= image_tag n.actor.avatar_url, class: "w-8 h-8 rounded-full shrink-0 mt-0.5", alt: "" %>
          <% else %>
            <span class="w-8 h-8 rounded-full bg-teal-100 text-teal-700 font-semibold flex items-center justify-center text-sm shrink-0 mt-0.5">
              <%= (n.actor.name.presence || "?").first.upcase %>
            </span>
          <% end %>

          <div class="flex-1 min-w-0">
            <p class="text-sm text-stone-700">
              <strong><%= n.actor.name %></strong>
              <%= case n.event_type
                  when "reply_to_post"  then "replied to your post"
                  when "reply_in_thread" then "replied in a thread you participated in"
                  when "mention"        then "mentioned you"
                  when "moderation"     then "removed your content"
                  end %>
              &mdash;
              <%= link_to "view", post_link, class: "text-blue-500 hover:underline" %>
            </p>
            <p class="text-xs text-stone-400 mt-0.5"><%= time_ago_in_words(n.created_at) %> ago</p>
          </div>

          <% unless n.read? %>
            <%= button_to "✓", read_notification_path(n), method: :patch,
                  class: "text-xs text-teal-600 hover:text-teal-800 bg-transparent border-0 p-0 cursor-pointer shrink-0",
                  title: "Mark as read" %>
          <% end %>
        </div>
      <% end %>
    </div>
  <% end %>
</div>
```

- [ ] **Step 5: Run tests**

```bash
bin/rails test test/controllers/notifications_controller_test.rb
```

Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
git add app/controllers/notifications_controller.rb app/views/notifications/ test/controllers/notifications_controller_test.rb
git commit -m "feat: add notifications index with mark-read actions"
```

---

## Task 12: Nav Bar Updates

**Files:**
- Modify: `app/views/layouts/application.html.erb`

This task has no dedicated test — the nav is exercised by all existing controller tests.

- [ ] **Step 1: Update the application layout**

In `app/views/layouts/application.html.erb`, replace the entire `<nav>` block with:

```erb
<nav class="bg-teal-700 shadow-sm">
  <div class="max-w-7xl mx-auto px-4 py-3 flex items-center gap-4 justify-between">
    <%= link_to "Forum", root_path, class: "text-xl font-bold text-white shrink-0" %>

    <%# Search form %>
    <%= form_with url: search_path, method: :get, class: "flex-1 max-w-sm" do |f| %>
      <div class="flex">
        <%= f.text_field :q, value: params[:q],
              placeholder: "Search posts…",
              class: "w-full px-3 py-1.5 rounded-l-lg text-sm text-stone-900 focus:outline-none focus:ring-2 focus:ring-teal-300 border-0" %>
        <%= f.submit "Search",
              class: "bg-teal-600 hover:bg-teal-500 text-white text-sm px-3 py-1.5 rounded-r-lg cursor-pointer border-0" %>
      </div>
    <% end %>

    <div class="flex items-center gap-3 text-sm shrink-0">
      <% if logged_in? %>
        <%= link_to "New Post", new_post_path,
              class: "bg-white text-teal-700 font-semibold rounded-lg px-4 py-1.5 hover:bg-teal-50" %>

        <%# Notification bell %>
        <% unread_count = current_user.notifications.where(read_at: nil).count %>
        <%= link_to notifications_path, class: "relative inline-flex items-center text-teal-100 hover:text-white" do %>
          <svg xmlns="http://www.w3.org/2000/svg" class="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2"
              d="M15 17h5l-1.405-1.405A2.032 2.032 0 0118 14.158V11a6 6 0 00-5-5.917V4a1 1 0 10-2 0v1.083A6 6 0 006 11v3.159c0 .538-.214 1.055-.595 1.436L4 17h5m6 0v1a3 3 0 11-6 0v-1m6 0H9" />
          </svg>
          <% if unread_count > 0 %>
            <span class="absolute -top-1 -right-1 bg-red-500 text-white text-xs rounded-full w-4 h-4 flex items-center justify-center leading-none font-bold">
              <%= unread_count > 9 ? "9+" : unread_count %>
            </span>
          <% end %>
        <% end %>

        <%# Profile link %>
        <%= link_to user_path(current_user), class: "flex items-center gap-2 text-white hover:text-teal-200" do %>
          <% if current_user.avatar_url.present? %>
            <%= image_tag current_user.avatar_url, class: "w-8 h-8 rounded-full", alt: "" %>
          <% else %>
            <span class="w-8 h-8 rounded-full bg-teal-100 text-teal-700 font-semibold flex items-center justify-center text-sm">
              <%= (current_user.name.presence || "?").first.upcase %>
            </span>
          <% end %>
          <span class="hidden sm:inline"><%= current_user.name %></span>
        <% end %>

        <%= button_to "Log Out", logout_path, method: :delete,
              class: "text-teal-100 hover:text-white" %>
      <% else %>
        <%= link_to "Log In", login_path, class: "text-teal-100 hover:text-white" %>
        <%= link_to "Sign Up", signup_path,
              class: "bg-white text-teal-700 font-semibold px-3 py-1.5 rounded-lg hover:bg-teal-50" %>
      <% end %>
    </div>
  </div>
</nav>
```

- [ ] **Step 2: Run the full test suite**

```bash
bin/rails test
```

Expected: all tests pass.

- [ ] **Step 3: Commit**

```bash
git add app/views/layouts/application.html.erb
git commit -m "feat: add search form, notification bell, and profile link to nav"
```

---

## Task 13: Final Verification

- [ ] **Step 1: Run linter**

```bash
./bin/rubocop
```

Fix any offences before proceeding.

- [ ] **Step 2: Run security audit**

```bash
./bin/brakeman
./bin/bundler-audit
```

Address any high-severity findings.

- [ ] **Step 3: Run full CI pipeline**

```bash
./bin/ci
```

Expected: all checks pass.

- [ ] **Step 4: Final commit if any lint fixes were made**

```bash
git add -p
git commit -m "chore: rubocop fixes for new features"
```
