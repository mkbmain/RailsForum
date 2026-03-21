# Admin Panel Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a `/admin` namespace with dashboard, users list, user detail (all posts/replies/bans/moderation activity), and admin-only promote/demote for creator↔sub_admin.

**Architecture:** Dedicated `Admin::` controller namespace inheriting from `Admin::BaseController` for auth. Separate `admin.html.erb` sidebar layout. No new models — queries against existing tables. Manual offset/limit pagination consistent with existing code.

**Tech Stack:** Rails 8.1, PostgreSQL (ILIKE search), Tailwind CSS, Minitest integration tests, no new gems.

**Known simplification:** The spec calls for separate pagination params per tab (`posts_page`, `replies_page`, etc.). This plan uses a single `page` param reset on tab switch via the tab links. Switching tabs always returns to page 1. The activity tab uses a hard limit of 30 per sub-section with no pagination. Both are intentional simplifications.

---

## File Map

### Create
- `app/controllers/admin/base_controller.rb` — require_login + require_moderator + admin layout
- `app/controllers/admin/dashboard_controller.rb` — stats + activity feed
- `app/controllers/admin/users_controller.rb` — index, show, promote, demote
- `app/views/layouts/admin.html.erb` — sidebar layout
- `app/views/admin/dashboard/index.html.erb` — stat cards + activity feed
- `app/views/admin/users/index.html.erb` — search + paginated table
- `app/views/admin/users/show.html.erb` — header, role controls, 4 tabs
- `test/controllers/admin/dashboard_controller_test.rb`
- `test/controllers/admin/users_controller_test.rb`

### Modify
- `config/routes.rb` — add admin namespace
- `app/views/layouts/application.html.erb` — admin nav link for moderators

---

## Task 1: Routes, base controller, auth

**Files:**
- Create: `app/controllers/admin/base_controller.rb`
- Modify: `config/routes.rb`
- Test: `test/controllers/admin/dashboard_controller_test.rb`

- [ ] **Step 1: Write failing auth tests**

```ruby
# test/controllers/admin/dashboard_controller_test.rb
require "test_helper"

class Admin::DashboardControllerTest < ActionDispatch::IntegrationTest
  setup do
    Provider.find_or_create_by!(id: 3, name: "internal")
    @creator = User.create!(email: "creator@example.com", name: "Creator",
                            password: "pass123", password_confirmation: "pass123",
                            provider_id: 3)
    @sub_admin = User.create!(email: "sub@example.com", name: "Sub",
                              password: "pass123", password_confirmation: "pass123",
                              provider_id: 3)
    @sub_admin.roles << Role.find_by!(name: Role::SUB_ADMIN)
    @admin = User.create!(email: "admin@example.com", name: "Admin",
                          password: "pass123", password_confirmation: "pass123",
                          provider_id: 3)
    @admin.roles << Role.find_by!(name: Role::ADMIN)
  end

  test "GET /admin redirects guest to login" do
    get admin_root_path
    assert_redirected_to login_path
  end

  test "GET /admin redirects creator to root" do
    post login_path, params: { email: "creator@example.com", password: "pass123" }
    get admin_root_path
    assert_redirected_to root_path
  end

  test "GET /admin is accessible to sub_admin" do
    post login_path, params: { email: "sub@example.com", password: "pass123" }
    get admin_root_path
    assert_response :success
  end

  test "GET /admin is accessible to admin" do
    post login_path, params: { email: "admin@example.com", password: "pass123" }
    get admin_root_path
    assert_response :success
  end
end
```

- [ ] **Step 2: Run to confirm they fail**

```bash
bin/rails test test/controllers/admin/dashboard_controller_test.rb
```
Expected: routing errors / missing constants.

- [ ] **Step 3: Add admin namespace to routes**

In `config/routes.rb`, add inside `Rails.application.routes.draw do`:

```ruby
namespace :admin do
  root to: "dashboard#index"
  resources :users, only: [:index, :show] do
    member do
      patch :promote
      patch :demote
    end
  end
end
```

- [ ] **Step 4: Create Admin::BaseController**

```ruby
# app/controllers/admin/base_controller.rb
class Admin::BaseController < ApplicationController
  before_action :require_login
  before_action :require_moderator
  layout "admin"
end
```

- [ ] **Step 5: Create stub DashboardController and view**

```ruby
# app/controllers/admin/dashboard_controller.rb
class Admin::DashboardController < Admin::BaseController
  def index
  end
end
```

```erb
<%# app/views/admin/dashboard/index.html.erb %>
<p>Admin Dashboard</p>
```

- [ ] **Step 6: Run auth tests — expect all 4 to pass**

```bash
bin/rails test test/controllers/admin/dashboard_controller_test.rb
```

- [ ] **Step 7: Add admin nav link to main layout**

In `app/views/layouts/application.html.erb`, inside the `<% if logged_in? %>` block, add before the "New Post" link:

```erb
<% if current_user.moderator? %>
  <%= link_to "Admin Panel", admin_root_path,
        class: "bg-teal-900 text-white font-semibold rounded-lg px-4 py-1.5 hover:bg-teal-800" %>
<% end %>
```

- [ ] **Step 8: Commit**

```bash
git add app/controllers/admin/ config/routes.rb app/views/layouts/application.html.erb test/controllers/admin/
git commit -m "feat: admin namespace, base controller, auth gates, nav link"
```

---

## Task 2: Admin layout

**Files:**
- Create: `app/views/layouts/admin.html.erb`

- [ ] **Step 1: Create the layout**

```erb
<%# app/views/layouts/admin.html.erb %>
<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title><%= content_for(:title).presence || "Admin Panel" %></title>
    <%= csrf_meta_tags %>
    <%= csp_meta_tag %>
    <%= stylesheet_link_tag "application", "data-turbo-track": "reload" %>
    <%= stylesheet_link_tag "tailwind", "data-turbo-track": "reload" %>
    <%= javascript_importmap_tags %>
  </head>
  <body class="bg-stone-100 min-h-screen flex">
    <aside class="w-56 bg-gray-900 text-white flex-shrink-0 min-h-screen flex flex-col">
      <div class="px-4 py-5 border-b border-gray-700">
        <%= link_to "Admin Panel", admin_root_path, class: "text-lg font-bold text-white" %>
        <div class="text-xs text-gray-400 mt-0.5"><%= current_user.name %></div>
      </div>
      <nav class="flex-1 px-2 py-4 space-y-1">
        <%= link_to "Dashboard", admin_root_path,
              class: "flex items-center px-3 py-2 rounded-lg text-sm font-medium #{
                request.path == admin_root_path ? 'bg-gray-700 text-white' : 'text-gray-300 hover:bg-gray-700 hover:text-white'
              }" %>
        <%= link_to "Users", admin_users_path,
              class: "flex items-center px-3 py-2 rounded-lg text-sm font-medium #{
                request.path.start_with?(admin_users_path) ? 'bg-gray-700 text-white' : 'text-gray-300 hover:bg-gray-700 hover:text-white'
              }" %>
      </nav>
      <div class="px-4 py-4 border-t border-gray-700">
        <%= link_to "← Forum", root_path, class: "text-xs text-gray-400 hover:text-white" %>
      </div>
    </aside>
    <div class="flex-1 flex flex-col min-h-screen">
      <% if notice.present? %>
        <div class="mx-6 mt-4">
          <div class="bg-green-50 border border-green-200 text-green-800 px-4 py-3 rounded-lg text-sm">
            <%= notice %>
          </div>
        </div>
      <% end %>
      <% if alert.present? %>
        <div class="mx-6 mt-4">
          <div class="bg-red-50 border border-red-200 text-red-700 px-4 py-3 rounded-lg text-sm">
            <%= alert %>
          </div>
        </div>
      <% end %>
      <main class="flex-1 p-6"><%= yield %></main>
    </div>
  </body>
</html>
```

- [ ] **Step 2: Verify auth tests still pass**

```bash
bin/rails test test/controllers/admin/dashboard_controller_test.rb
```

- [ ] **Step 3: Commit**

```bash
git add app/views/layouts/admin.html.erb
git commit -m "feat: admin sidebar layout"
```

---

## Task 3: Dashboard

**Files:**
- Modify: `app/controllers/admin/dashboard_controller.rb`
- Modify: `app/views/admin/dashboard/index.html.erb`
- Modify: `test/controllers/admin/dashboard_controller_test.rb`

- [ ] **Step 1: Write failing dashboard tests**

Add to `test/controllers/admin/dashboard_controller_test.rb`:

```ruby
test "GET /admin shows stat counts including removed posts" do
  post login_path, params: { email: "admin@example.com", password: "pass123" }
  category = Category.find_or_create_by!(name: "General")
  @creator.posts.create!(title: "Visible Post", body: "body text here ok", category: category)
  removed = @creator.posts.create!(title: "Removed Post", body: "body text here ok", category: category)
  removed.update_columns(removed_at: Time.current, removed_by_id: @admin.id)
  get admin_root_path
  assert_response :success
  assert_match "2", response.body
end

test "GET /admin shows activity feed with ban and removed post" do
  post login_path, params: { email: "admin@example.com", password: "pass123" }
  BanReason.find_or_create_by!(name: "Spam")
  ban_reason = BanReason.find_by!(name: "Spam")
  UserBan.create!(user: @creator, ban_reason: ban_reason, banned_by: @admin,
                  banned_from: Time.current, banned_until: 2.hours.from_now)
  category = Category.find_or_create_by!(name: "General")
  p = @creator.posts.create!(title: "Doomed Post", body: "body text here ok", category: category)
  p.update_columns(removed_at: Time.current, removed_by_id: @admin.id)
  get admin_root_path
  assert_response :success
  assert_match "Spam", response.body
  assert_match "Doomed Post", response.body
end
```

- [ ] **Step 2: Run to confirm they fail**

```bash
bin/rails test test/controllers/admin/dashboard_controller_test.rb
```

- [ ] **Step 3: Implement DashboardController**

```ruby
# app/controllers/admin/dashboard_controller.rb
class Admin::DashboardController < Admin::BaseController
  def index
    @total_users   = User.count
    @total_posts   = Post.count
    @total_replies = Reply.count
    @banned_users  = UserBan.where("banned_until >= ?", Time.current).count

    bans = UserBan.includes(:banned_by, :user, :ban_reason)
                  .order(banned_from: :desc).limit(20)
                  .map { |b| { type: :ban, time: b.banned_from, record: b } }

    removed_posts = Post.where.not(removed_at: nil)
                        .includes(:removed_by)
                        .order(removed_at: :desc).limit(20)
                        .map { |p| { type: :removed_post, time: p.removed_at, record: p } }

    removed_replies = Reply.where.not(removed_at: nil)
                           .includes(:removed_by, :post)
                           .order(removed_at: :desc).limit(20)
                           .map { |r| { type: :removed_reply, time: r.removed_at, record: r } }

    @activity = (bans + removed_posts + removed_replies)
                  .sort_by { |item| -item[:time].to_i }
                  .first(20)
  end
end
```

- [ ] **Step 4: Implement dashboard view**

```erb
<%# app/views/admin/dashboard/index.html.erb %>
<% content_for :title, "Dashboard – Admin Panel" %>

<h1 class="text-2xl font-bold text-gray-900 mb-6">Dashboard</h1>

<div class="grid grid-cols-2 lg:grid-cols-4 gap-4 mb-8">
  <div class="bg-white rounded-xl shadow-sm border border-stone-200 p-5">
    <div class="text-sm text-gray-500 font-medium">Total Users</div>
    <div class="text-3xl font-bold text-gray-900 mt-1"><%= @total_users %></div>
  </div>
  <div class="bg-white rounded-xl shadow-sm border border-stone-200 p-5">
    <div class="text-sm text-gray-500 font-medium">Total Posts</div>
    <div class="text-3xl font-bold text-gray-900 mt-1"><%= @total_posts %></div>
  </div>
  <div class="bg-white rounded-xl shadow-sm border border-stone-200 p-5">
    <div class="text-sm text-gray-500 font-medium">Total Replies</div>
    <div class="text-3xl font-bold text-gray-900 mt-1"><%= @total_replies %></div>
  </div>
  <div class="bg-white rounded-xl shadow-sm border border-stone-200 p-5">
    <div class="text-sm text-gray-500 font-medium">Currently Banned</div>
    <div class="text-3xl font-bold text-red-600 mt-1"><%= @banned_users %></div>
  </div>
</div>

<div class="bg-white rounded-xl shadow-sm border border-stone-200">
  <div class="px-5 py-4 border-b border-stone-200">
    <h2 class="text-base font-semibold text-gray-900">Recent Moderation Activity</h2>
  </div>
  <% if @activity.empty? %>
    <p class="px-5 py-6 text-sm text-gray-500">No recent moderation activity.</p>
  <% else %>
    <ul class="divide-y divide-stone-100">
      <% @activity.each do |item| %>
        <li class="px-5 py-3 text-sm flex items-center justify-between gap-4">
          <span>
            <% case item[:type] %>
            <% when :ban %>
              <% ban = item[:record] %>
              <% hours = ((ban.banned_until - ban.banned_from) / 3600).round %>
              <% if ban.banned_by %>
                <%= link_to ban.banned_by.name, admin_user_path(ban.banned_by), class: "font-medium text-teal-700 hover:underline" %>
              <% else %>
                <span class="font-medium">Unknown</span>
              <% end %>
              banned <span class="font-medium"><%= ban.user.name %></span>
              for <%= hours %> hour<%= hours == 1 ? "" : "s" %>
              (<%= ban.ban_reason.name %>)
            <% when :removed_post %>
              <% p = item[:record] %>
              <% if p.removed_by %>
                <%= link_to p.removed_by.name, admin_user_path(p.removed_by), class: "font-medium text-teal-700 hover:underline" %>
              <% else %>
                <span class="font-medium">Unknown</span>
              <% end %>
              removed post: <span class="font-medium"><%= p.title %></span>
            <% when :removed_reply %>
              <% r = item[:record] %>
              <% if r.removed_by %>
                <%= link_to r.removed_by.name, admin_user_path(r.removed_by), class: "font-medium text-teal-700 hover:underline" %>
              <% else %>
                <span class="font-medium">Unknown</span>
              <% end %>
              removed reply on: <span class="font-medium"><%= r.post.title %></span>
            <% end %>
          </span>
          <span class="text-gray-400 shrink-0 text-xs"><%= item[:time].strftime("%b %-d, %H:%M") %></span>
        </li>
      <% end %>
    </ul>
  <% end %>
</div>
```

- [ ] **Step 5: Run all dashboard tests**

```bash
bin/rails test test/controllers/admin/dashboard_controller_test.rb
```
Expected: all 6 pass.

- [ ] **Step 6: Commit**

```bash
git add app/controllers/admin/dashboard_controller.rb app/views/admin/dashboard/index.html.erb test/controllers/admin/dashboard_controller_test.rb
git commit -m "feat: admin dashboard with stats and activity feed"
```

---

## Task 4: Users list

**Files:**
- Create: `app/controllers/admin/users_controller.rb`
- Create: `app/views/admin/users/index.html.erb`
- Create: `test/controllers/admin/users_controller_test.rb`

- [ ] **Step 1: Write failing tests**

```ruby
# test/controllers/admin/users_controller_test.rb
require "test_helper"

class Admin::UsersControllerTest < ActionDispatch::IntegrationTest
  setup do
    Provider.find_or_create_by!(id: 3, name: "internal")
    @creator = User.create!(email: "creator@example.com", name: "Alice Creator",
                            password: "pass123", password_confirmation: "pass123",
                            provider_id: 3)
    @sub_admin = User.create!(email: "sub@example.com", name: "Bob Sub",
                              password: "pass123", password_confirmation: "pass123",
                              provider_id: 3)
    @sub_admin.roles << Role.find_by!(name: Role::SUB_ADMIN)
    @admin = User.create!(email: "admin@example.com", name: "Carol Admin",
                          password: "pass123", password_confirmation: "pass123",
                          provider_id: 3)
    @admin.roles << Role.find_by!(name: Role::ADMIN)
  end

  test "GET /admin/users redirects guest" do
    get admin_users_path
    assert_redirected_to login_path
  end

  test "GET /admin/users lists all users" do
    post login_path, params: { email: "admin@example.com", password: "pass123" }
    get admin_users_path
    assert_response :success
    assert_match "Alice Creator", response.body
    assert_match "Bob Sub", response.body
    assert_match "Carol Admin", response.body
  end

  test "GET /admin/users filters by name (case-insensitive)" do
    post login_path, params: { email: "admin@example.com", password: "pass123" }
    get admin_users_path, params: { q: "alice" }
    assert_response :success
    assert_match "Alice Creator", response.body
    assert_no_match "Bob Sub", response.body
  end

  test "GET /admin/users filters by email" do
    post login_path, params: { email: "admin@example.com", password: "pass123" }
    get admin_users_path, params: { q: "sub@example" }
    assert_response :success
    assert_match "Bob Sub", response.body
    assert_no_match "Alice Creator", response.body
  end
end
```

- [ ] **Step 2: Run to confirm they fail**

```bash
bin/rails test test/controllers/admin/users_controller_test.rb
```

- [ ] **Step 3: Create Admin::UsersController with index and stubs**

```ruby
# app/controllers/admin/users_controller.rb
class Admin::UsersController < Admin::BaseController
  PER_PAGE     = 20
  TAB_PER_PAGE = 30

  def index
    scope = User.includes(:roles, :user_bans)
    if params[:q].present?
      term  = params[:q].strip
      scope = scope.where("name ILIKE ? OR email ILIKE ?", "%#{term}%", "%#{term}%")
    end
    page      = [ (params[:page] || 1).to_i, 1 ].max
    users     = scope.order(:name).limit(PER_PAGE + 1).offset((page - 1) * PER_PAGE).to_a
    @has_more = users.size > PER_PAGE
    @users    = users.first(PER_PAGE)
    @page     = page
    @q        = params[:q].to_s

    user_ids     = @users.map(&:id)
    @post_counts = Post.where(user_id: user_ids).group(:user_id).count
  end

  def show
  end

  def promote
    redirect_to admin_root_path
  end

  def demote
    redirect_to admin_root_path
  end
end
```

- [ ] **Step 4: Create users index view**

```erb
<%# app/views/admin/users/index.html.erb %>
<% content_for :title, "Users – Admin Panel" %>

<div class="flex items-center justify-between mb-6">
  <h1 class="text-2xl font-bold text-gray-900">Users</h1>
  <%= form_with url: admin_users_path, method: :get, class: "flex gap-2" do |f| %>
    <%= f.text_field :q, value: @q, placeholder: "Search by name or email…",
          class: "px-3 py-2 rounded-lg border border-stone-300 text-sm focus:outline-none focus:ring-2 focus:ring-teal-400 w-64" %>
    <%= f.submit "Search",
          class: "bg-teal-700 text-white px-4 py-2 rounded-lg text-sm hover:bg-teal-600 cursor-pointer" %>
    <% if @q.present? %>
      <%= link_to "Clear", admin_users_path, class: "text-sm text-gray-500 hover:text-gray-700 px-2 py-2" %>
    <% end %>
  <% end %>
</div>

<div class="bg-white rounded-xl shadow-sm border border-stone-200 overflow-hidden">
  <table class="w-full text-sm">
    <thead class="bg-stone-50 border-b border-stone-200">
      <tr>
        <th class="text-left px-4 py-3 font-medium text-gray-600">Name</th>
        <th class="text-left px-4 py-3 font-medium text-gray-600">Email</th>
        <th class="text-left px-4 py-3 font-medium text-gray-600">Role</th>
        <th class="text-left px-4 py-3 font-medium text-gray-600">Joined</th>
        <th class="text-right px-4 py-3 font-medium text-gray-600">Posts</th>
        <th class="text-left px-4 py-3 font-medium text-gray-600">Ban Status</th>
      </tr>
    </thead>
    <tbody class="divide-y divide-stone-100">
      <% @users.each do |user| %>
        <% active_ban = user.user_bans.find { |b| b.banned_until >= Time.current } %>
        <tr class="hover:bg-stone-50">
          <td class="px-4 py-3">
            <%= link_to user.name, admin_user_path(user), class: "font-medium text-teal-700 hover:underline" %>
          </td>
          <td class="px-4 py-3 text-gray-600"><%= user.email %></td>
          <td class="px-4 py-3">
            <% if user.admin? %>
              <span class="inline-flex px-2 py-0.5 rounded text-xs font-semibold bg-purple-100 text-purple-800">Admin</span>
            <% elsif user.sub_admin? %>
              <span class="inline-flex px-2 py-0.5 rounded text-xs font-semibold bg-blue-100 text-blue-800">Sub-admin</span>
            <% else %>
              <span class="inline-flex px-2 py-0.5 rounded text-xs font-semibold bg-stone-100 text-stone-600">Creator</span>
            <% end %>
          </td>
          <td class="px-4 py-3 text-gray-500"><%= user.created_at.strftime("%b %-d, %Y") %></td>
          <td class="px-4 py-3 text-right text-gray-700"><%= @post_counts[user.id].to_i %></td>
          <td class="px-4 py-3">
            <% if active_ban %>
              <span class="text-red-600 font-medium text-xs">
                Banned until <%= active_ban.banned_until.strftime("%b %-d, %H:%M") %>
              </span>
            <% end %>
          </td>
        </tr>
      <% end %>
      <% if @users.empty? %>
        <tr>
          <td colspan="6" class="px-4 py-8 text-center text-gray-500">No users found.</td>
        </tr>
      <% end %>
    </tbody>
  </table>
</div>

<div class="flex justify-between items-center mt-4 text-sm text-gray-600">
  <% if @page > 1 %>
    <%= link_to "← Previous", admin_users_path(q: @q, page: @page - 1),
          class: "px-4 py-2 bg-white border border-stone-300 rounded-lg hover:bg-stone-50" %>
  <% else %>
    <span></span>
  <% end %>
  <span>Page <%= @page %></span>
  <% if @has_more %>
    <%= link_to "Next →", admin_users_path(q: @q, page: @page + 1),
          class: "px-4 py-2 bg-white border border-stone-300 rounded-lg hover:bg-stone-50" %>
  <% else %>
    <span></span>
  <% end %>
</div>
```

- [ ] **Step 5: Run users list tests**

```bash
bin/rails test test/controllers/admin/users_controller_test.rb
```
Expected: 4 tests pass.

- [ ] **Step 6: Commit**

```bash
git add app/controllers/admin/users_controller.rb app/views/admin/users/index.html.erb test/controllers/admin/users_controller_test.rb
git commit -m "feat: admin users list with search and pagination"
```

---

## Task 5: User detail page

**Files:**
- Modify: `app/controllers/admin/users_controller.rb`
- Create: `app/views/admin/users/show.html.erb`
- Modify: `test/controllers/admin/users_controller_test.rb`

- [ ] **Step 1: Write failing tests**

Add to `test/controllers/admin/users_controller_test.rb`:

```ruby
test "GET /admin/users/:id shows user header with email and role" do
  post login_path, params: { email: "admin@example.com", password: "pass123" }
  get admin_user_path(@creator)
  assert_response :success
  assert_match "Alice Creator", response.body
  assert_match "creator@example.com", response.body
  assert_match "Creator", response.body
end

test "GET /admin/users/:id shows active ban in header" do
  post login_path, params: { email: "admin@example.com", password: "pass123" }
  BanReason.find_or_create_by!(name: "Spam")
  ban_reason = BanReason.find_by!(name: "Spam")
  UserBan.create!(user: @creator, ban_reason: ban_reason, banned_by: @admin,
                  banned_from: Time.current, banned_until: 5.hours.from_now)
  get admin_user_path(@creator)
  assert_response :success
  assert_match "Banned until", response.body
end

test "GET /admin/users/:id posts tab shows all posts including removed" do
  post login_path, params: { email: "admin@example.com", password: "pass123" }
  category = Category.find_or_create_by!(name: "General")
  @creator.posts.create!(title: "Live Post", body: "body text here ok", category: category)
  removed = @creator.posts.create!(title: "Gone Post", body: "body text here ok", category: category)
  removed.update_columns(removed_at: Time.current, removed_by_id: @admin.id)
  get admin_user_path(@creator), params: { tab: "posts" }
  assert_response :success
  assert_match "Live Post", response.body
  assert_match "Gone Post", response.body
  assert_match "Removed", response.body
end

test "GET /admin/users/:id replies tab shows all replies including removed" do
  post login_path, params: { email: "admin@example.com", password: "pass123" }
  category = Category.find_or_create_by!(name: "General")
  parent = @admin.posts.create!(title: "Parent Post", body: "body text here ok", category: category)
  parent.replies.create!(body: "live reply body ok", user: @creator)
  removed = parent.replies.create!(body: "removed reply body ok", user: @creator)
  removed.update_columns(removed_at: Time.current, removed_by_id: @admin.id)
  get admin_user_path(@creator), params: { tab: "replies" }
  assert_response :success
  assert_match "live reply body ok", response.body
  assert_match "removed reply body ok", response.body
  assert_match "Parent Post", response.body
end

test "GET /admin/users/:id bans tab shows ban history" do
  post login_path, params: { email: "admin@example.com", password: "pass123" }
  BanReason.find_or_create_by!(name: "Spam")
  ban_reason = BanReason.find_by!(name: "Spam")
  UserBan.create!(user: @creator, ban_reason: ban_reason, banned_by: @admin,
                  banned_from: Time.current, banned_until: 3.hours.from_now)
  get admin_user_path(@creator), params: { tab: "bans" }
  assert_response :success
  assert_match "Spam", response.body
  assert_match "Carol Admin", response.body
end

test "GET /admin/users/:id activity tab shows bans issued by a moderator" do
  post login_path, params: { email: "admin@example.com", password: "pass123" }
  BanReason.find_or_create_by!(name: "Spam")
  ban_reason = BanReason.find_by!(name: "Spam")
  UserBan.create!(user: @creator, ban_reason: ban_reason, banned_by: @sub_admin,
                  banned_from: Time.current, banned_until: 3.hours.from_now)
  get admin_user_path(@sub_admin), params: { tab: "activity" }
  assert_response :success
  assert_match "Alice Creator", response.body
end

test "GET /admin/users/:id does not show activity tab for user with no moderation history" do
  post login_path, params: { email: "admin@example.com", password: "pass123" }
  get admin_user_path(@creator)
  assert_response :success
  assert_no_match "Moderation Activity", response.body
end
```

- [ ] **Step 2: Run to confirm they fail**

```bash
bin/rails test test/controllers/admin/users_controller_test.rb
```

- [ ] **Step 3: Implement show action**

Replace the stub `show` in `app/controllers/admin/users_controller.rb`:

```ruby
def show
  @user       = User.includes(:roles).find(params[:id])
  @tab        = params[:tab].presence_in(%w[posts replies bans activity]) || "posts"
  @active_ban = @user.user_bans.where("banned_until >= ?", Time.current)
                     .order(banned_until: :desc).first
  @has_moderation_history = UserBan.where(banned_by: @user).exists? ||
                            Post.where(removed_by: @user).exists? ||
                            Reply.where(removed_by: @user).exists?

  page = [ (params[:page] || 1).to_i, 1 ].max

  case @tab
  when "posts"
    scope     = @user.posts.includes(:removed_by).order(created_at: :desc)
    items     = scope.limit(TAB_PER_PAGE + 1).offset((page - 1) * TAB_PER_PAGE).to_a
    @has_more = items.size > TAB_PER_PAGE
    @items    = items.first(TAB_PER_PAGE)
  when "replies"
    scope     = @user.replies.includes(:post, :removed_by).order(created_at: :desc)
    items     = scope.limit(TAB_PER_PAGE + 1).offset((page - 1) * TAB_PER_PAGE).to_a
    @has_more = items.size > TAB_PER_PAGE
    @items    = items.first(TAB_PER_PAGE)
  when "bans"
    scope     = @user.user_bans.includes(:ban_reason, :banned_by).order(banned_from: :desc)
    items     = scope.limit(TAB_PER_PAGE + 1).offset((page - 1) * TAB_PER_PAGE).to_a
    @has_more = items.size > TAB_PER_PAGE
    @items    = items.first(TAB_PER_PAGE)
  when "activity"
    @bans_issued     = UserBan.where(banned_by: @user).includes(:user, :ban_reason)
                              .order(banned_from: :desc).limit(TAB_PER_PAGE)
    @posts_removed   = Post.where(removed_by: @user).includes(:user)
                           .order(removed_at: :desc).limit(TAB_PER_PAGE)
    @replies_removed = Reply.where(removed_by: @user).includes(:user, :post)
                            .order(removed_at: :desc).limit(TAB_PER_PAGE)
  end

  @page = page
end
```

- [ ] **Step 4: Create show view**

```erb
<%# app/views/admin/users/show.html.erb %>
<% content_for :title, "#{@user.name} – Admin Panel" %>

<nav class="text-sm text-gray-500 mb-4">
  <%= link_to "Users", admin_users_path, class: "hover:text-teal-700" %> /
  <span class="text-gray-900"><%= @user.name %></span>
</nav>

<%# Header %>
<div class="bg-white rounded-xl shadow-sm border border-stone-200 p-6 mb-6">
  <div class="flex items-start justify-between gap-4">
    <div class="flex items-center gap-4">
      <% if @user.avatar_url.present? %>
        <%= image_tag @user.avatar_url, class: "w-16 h-16 rounded-full", alt: "" %>
      <% else %>
        <span class="w-16 h-16 rounded-full bg-teal-100 text-teal-700 font-bold text-2xl flex items-center justify-center">
          <%= (@user.name.presence || "?").first.upcase %>
        </span>
      <% end %>
      <div>
        <h1 class="text-xl font-bold text-gray-900"><%= @user.name %></h1>
        <div class="text-sm text-gray-500"><%= @user.email %></div>
        <div class="flex flex-wrap items-center gap-2 mt-1">
          <% if @user.admin? %>
            <span class="inline-flex px-2 py-0.5 rounded text-xs font-semibold bg-purple-100 text-purple-800">Admin</span>
          <% elsif @user.sub_admin? %>
            <span class="inline-flex px-2 py-0.5 rounded text-xs font-semibold bg-blue-100 text-blue-800">Sub-admin</span>
          <% else %>
            <span class="inline-flex px-2 py-0.5 rounded text-xs font-semibold bg-stone-100 text-stone-600">Creator</span>
          <% end %>
          <span class="text-xs text-gray-400">Joined <%= @user.created_at.strftime("%b %-d, %Y") %></span>
          <% if @active_ban %>
            <span class="text-xs font-medium text-red-600">
              Banned until <%= @active_ban.banned_until.strftime("%b %-d, %H:%M") %>
            </span>
          <% end %>
        </div>
      </div>
    </div>

    <%# Role controls — admin only, not for self or another admin %>
    <% if current_user.admin? && @user != current_user && !@user.admin? %>
      <div class="flex gap-2 shrink-0">
        <% if @user.sub_admin? %>
          <%= button_to "Demote to Creator", demote_admin_user_path(@user), method: :patch,
                class: "bg-orange-100 text-orange-800 text-sm font-medium px-4 py-2 rounded-lg hover:bg-orange-200 cursor-pointer",
                data: { turbo_confirm: "Demote #{@user.name} to Creator?" } %>
        <% else %>
          <%= button_to "Promote to Sub-admin", promote_admin_user_path(@user), method: :patch,
                class: "bg-blue-100 text-blue-800 text-sm font-medium px-4 py-2 rounded-lg hover:bg-blue-200 cursor-pointer",
                data: { turbo_confirm: "Promote #{@user.name} to Sub-admin?" } %>
        <% end %>
      </div>
    <% end %>
  </div>
</div>

<%# Tabs %>
<div class="border-b border-stone-200 mb-6">
  <nav class="flex gap-1 -mb-px">
    <% [["posts", "Posts"], ["replies", "Replies"], ["bans", "Bans Received"], ["activity", "Moderation Activity"]].each do |key, label| %>
      <% next if key == "activity" && !@has_moderation_history %>
      <%= link_to label, admin_user_path(@user, tab: key),
            class: "px-4 py-2 text-sm font-medium border-b-2 #{
              @tab == key ? 'border-teal-600 text-teal-700' : 'border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300'
            }" %>
    <% end %>
  </nav>
</div>

<%# Tab content %>
<div class="bg-white rounded-xl shadow-sm border border-stone-200">
  <% case @tab %>
  <% when "posts" %>
    <% if @items.empty? %>
      <p class="px-5 py-8 text-sm text-gray-500 text-center">No posts.</p>
    <% else %>
      <ul class="divide-y divide-stone-100">
        <% @items.each do |post| %>
          <li class="px-5 py-4 <%= 'opacity-60' if post.removed? %>">
            <div class="flex items-start justify-between gap-4">
              <div>
                <% if post.removed? %>
                  <span class="inline-flex px-1.5 py-0.5 rounded text-xs font-semibold bg-red-100 text-red-700 mr-2">Removed</span>
                  <span class="font-medium text-gray-500"><%= post.title %></span>
                <% else %>
                  <%= link_to post.title, post_path(post), class: "font-medium text-teal-700 hover:underline", target: "_blank" %>
                <% end %>
              </div>
              <span class="text-xs text-gray-400 shrink-0"><%= post.created_at.strftime("%b %-d, %Y") %></span>
            </div>
            <% if post.removed? %>
              <div class="text-xs text-gray-400 mt-1">
                Removed by <%= post.removed_by&.name || "Unknown" %>
                on <%= post.removed_at.strftime("%b %-d, %Y %H:%M") %>
              </div>
            <% end %>
          </li>
        <% end %>
      </ul>
    <% end %>

  <% when "replies" %>
    <% if @items.empty? %>
      <p class="px-5 py-8 text-sm text-gray-500 text-center">No replies.</p>
    <% else %>
      <ul class="divide-y divide-stone-100">
        <% @items.each do |reply| %>
          <li class="px-5 py-4 <%= 'opacity-60' if reply.removed? %>">
            <div class="flex items-start justify-between gap-4">
              <div class="flex-1 min-w-0">
                <div class="text-xs text-gray-400 mb-1">
                  on <%= link_to reply.post.title, post_path(reply.post), class: "text-teal-700 hover:underline", target: "_blank" %>
                </div>
                <% if reply.removed? %>
                  <span class="inline-flex px-1.5 py-0.5 rounded text-xs font-semibold bg-red-100 text-red-700 mr-1">Removed</span>
                <% end %>
                <span class="text-sm <%= reply.removed? ? 'text-gray-400' : 'text-gray-800' %>">
                  <%= truncate(reply.body, length: 120) %>
                </span>
              </div>
              <span class="text-xs text-gray-400 shrink-0"><%= reply.created_at.strftime("%b %-d, %Y") %></span>
            </div>
            <% if reply.removed? %>
              <div class="text-xs text-gray-400 mt-1">
                Removed by <%= reply.removed_by&.name || "Unknown" %>
                on <%= reply.removed_at.strftime("%b %-d, %Y %H:%M") %>
              </div>
            <% end %>
          </li>
        <% end %>
      </ul>
    <% end %>

  <% when "bans" %>
    <% if @items.empty? %>
      <p class="px-5 py-8 text-sm text-gray-500 text-center">No bans.</p>
    <% else %>
      <ul class="divide-y divide-stone-100">
        <% @items.each do |ban| %>
          <% hours = ((ban.banned_until - ban.banned_from) / 3600).round %>
          <li class="px-5 py-4">
            <div class="flex items-start justify-between gap-4">
              <div>
                <span class="font-medium text-gray-800"><%= ban.ban_reason.name %></span>
                <span class="text-gray-500 ml-2">(<%= hours %> hour<%= hours == 1 ? "" : "s" %>)</span>
              </div>
              <span class="text-xs text-gray-400 shrink-0"><%= ban.banned_from.strftime("%b %-d, %Y %H:%M") %></span>
            </div>
            <div class="text-xs text-gray-500 mt-1">
              Issued by
              <% if ban.banned_by %>
                <%= link_to ban.banned_by.name, admin_user_path(ban.banned_by), class: "text-teal-700 hover:underline" %>
              <% else %>
                Unknown
              <% end %>
            </div>
          </li>
        <% end %>
      </ul>
    <% end %>

  <% when "activity" %>
    <div class="px-5 py-4 border-b border-stone-100">
      <h3 class="text-sm font-semibold text-gray-700 mb-3">Bans Issued</h3>
      <% if @bans_issued.empty? %>
        <p class="text-sm text-gray-400">None.</p>
      <% else %>
        <ul class="space-y-2">
          <% @bans_issued.each do |ban| %>
            <% hours = ((ban.banned_until - ban.banned_from) / 3600).round %>
            <li class="text-sm">
              Banned
              <%= link_to ban.user.name, admin_user_path(ban.user), class: "font-medium text-teal-700 hover:underline" %>
              for <%= hours %> hour<%= hours == 1 ? "" : "s" %>
              (<%= ban.ban_reason.name %>)
              <span class="text-gray-400 ml-1"><%= ban.banned_from.strftime("%b %-d, %Y") %></span>
            </li>
          <% end %>
        </ul>
      <% end %>
    </div>
    <div class="px-5 py-4 border-b border-stone-100">
      <h3 class="text-sm font-semibold text-gray-700 mb-3">Posts Removed</h3>
      <% if @posts_removed.empty? %>
        <p class="text-sm text-gray-400">None.</p>
      <% else %>
        <ul class="space-y-2">
          <% @posts_removed.each do |p| %>
            <li class="text-sm">
              <span class="font-medium"><%= p.title %></span>
              <span class="text-gray-400 ml-1">(<%= p.removed_at.strftime("%b %-d, %Y") %>)</span>
            </li>
          <% end %>
        </ul>
      <% end %>
    </div>
    <div class="px-5 py-4">
      <h3 class="text-sm font-semibold text-gray-700 mb-3">Replies Removed</h3>
      <% if @replies_removed.empty? %>
        <p class="text-sm text-gray-400">None.</p>
      <% else %>
        <ul class="space-y-2">
          <% @replies_removed.each do |r| %>
            <li class="text-sm">
              Reply on
              <%= link_to r.post.title, post_path(r.post), class: "text-teal-700 hover:underline", target: "_blank" %>
              <span class="text-gray-400 ml-1">(<%= r.removed_at.strftime("%b %-d, %Y") %>)</span>
            </li>
          <% end %>
        </ul>
      <% end %>
    </div>
  <% end %>
</div>

<%# Pagination (posts, replies, bans tabs only) %>
<% if %w[posts replies bans].include?(@tab) %>
  <div class="flex justify-between items-center mt-4 text-sm text-gray-600">
    <% if @page > 1 %>
      <%= link_to "← Previous", admin_user_path(@user, tab: @tab, page: @page - 1),
            class: "px-4 py-2 bg-white border border-stone-300 rounded-lg hover:bg-stone-50" %>
    <% else %>
      <span></span>
    <% end %>
    <span>Page <%= @page %></span>
    <% if @has_more %>
      <%= link_to "Next →", admin_user_path(@user, tab: @tab, page: @page + 1),
            class: "px-4 py-2 bg-white border border-stone-300 rounded-lg hover:bg-stone-50" %>
    <% else %>
      <span></span>
    <% end %>
  </div>
<% end %>
```

- [ ] **Step 5: Run all user detail tests**

```bash
bin/rails test test/controllers/admin/users_controller_test.rb
```
Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
git add app/controllers/admin/users_controller.rb app/views/admin/users/show.html.erb test/controllers/admin/users_controller_test.rb
git commit -m "feat: admin user detail with all tabs (posts, replies, bans, moderation activity)"
```

---

## Task 6: Promote and demote

**Files:**
- Modify: `app/controllers/admin/users_controller.rb`
- Modify: `test/controllers/admin/users_controller_test.rb`

- [ ] **Step 1: Write failing tests**

Add to `test/controllers/admin/users_controller_test.rb`:

```ruby
test "PATCH promote grants sub_admin role to creator" do
  post login_path, params: { email: "admin@example.com", password: "pass123" }
  assert_not @creator.sub_admin?
  patch promote_admin_user_path(@creator)
  assert_redirected_to admin_user_path(@creator)
  assert @creator.reload.sub_admin?
  assert_match /promoted/i, flash[:notice]
end

test "PATCH demote removes sub_admin role" do
  post login_path, params: { email: "admin@example.com", password: "pass123" }
  assert @sub_admin.sub_admin?
  patch demote_admin_user_path(@sub_admin)
  assert_redirected_to admin_user_path(@sub_admin)
  assert_not @sub_admin.reload.sub_admin?
  assert_match /demoted/i, flash[:notice]
end

test "PATCH promote is forbidden for sub_admin actor" do
  post login_path, params: { email: "sub@example.com", password: "pass123" }
  patch promote_admin_user_path(@creator)
  assert_redirected_to root_path
  assert_not @creator.reload.sub_admin?
end

test "PATCH promote on self redirects with alert" do
  post login_path, params: { email: "admin@example.com", password: "pass123" }
  patch promote_admin_user_path(@admin)
  assert_redirected_to admin_user_path(@admin)
  assert_match /cannot/i, flash[:alert]
end

test "PATCH promote on another admin redirects with alert" do
  other = User.create!(email: "a2@example.com", name: "Other Admin",
                       password: "pass123", password_confirmation: "pass123",
                       provider_id: 3)
  other.roles << Role.find_by!(name: Role::ADMIN)
  post login_path, params: { email: "admin@example.com", password: "pass123" }
  patch promote_admin_user_path(other)
  assert_redirected_to admin_user_path(other)
  assert_match /cannot/i, flash[:alert]
end

test "PATCH promote is idempotent when user is already sub_admin" do
  post login_path, params: { email: "admin@example.com", password: "pass123" }
  patch promote_admin_user_path(@sub_admin)
  assert_redirected_to admin_user_path(@sub_admin)
  assert_match /already/i, flash[:alert]
end

test "PATCH demote is idempotent when user is already creator" do
  post login_path, params: { email: "admin@example.com", password: "pass123" }
  patch demote_admin_user_path(@creator)
  assert_redirected_to admin_user_path(@creator)
  assert_match /already/i, flash[:alert]
end
```

- [ ] **Step 2: Run to confirm they fail**

```bash
bin/rails test test/controllers/admin/users_controller_test.rb
```

- [ ] **Step 3: Implement promote and demote**

Replace the stub `promote` and `demote` methods in `app/controllers/admin/users_controller.rb`:

```ruby
def promote
  user = User.find(params[:id])
  if user == current_user || user.admin?
    redirect_to admin_user_path(user), alert: "You cannot change this user's role." and return
  end
  if user.sub_admin?
    redirect_to admin_user_path(user), alert: "User is already a Sub-admin." and return
  end
  user.roles << Role.find_by!(name: Role::SUB_ADMIN)
  redirect_to admin_user_path(user), notice: "#{user.name} has been promoted to Sub-admin."
end

def demote
  user = User.find(params[:id])
  if user == current_user || user.admin?
    redirect_to admin_user_path(user), alert: "You cannot change this user's role." and return
  end
  unless user.sub_admin?
    redirect_to admin_user_path(user), alert: "User is already a Creator." and return
  end
  UserRole.where(user: user, role: Role.find_by!(name: Role::SUB_ADMIN)).destroy_all
  redirect_to admin_user_path(user), notice: "#{user.name} has been demoted to Creator."
end
```

- [ ] **Step 4: Run promote/demote tests**

```bash
bin/rails test test/controllers/admin/users_controller_test.rb
```
Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add app/controllers/admin/users_controller.rb test/controllers/admin/users_controller_test.rb
git commit -m "feat: admin promote and demote creator<->sub_admin"
```

---

## Task 7: Full CI check

- [ ] **Step 1: Run full test suite**

```bash
bin/rails test
```
Expected: all tests pass, no regressions.

- [ ] **Step 2: Run CI pipeline**

```bash
./bin/ci
```
Expected: lint, security checks, and tests all pass.

- [ ] **Step 3: Fix any rubocop offences**

```bash
./bin/rubocop --autocorrect
```

- [ ] **Step 4: Commit lint fixes if any changes were made**

```bash
git add -A
git commit -m "style: rubocop autocorrect for admin panel"
```
