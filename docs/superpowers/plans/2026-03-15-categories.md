# Categories Feature Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `categories` table with a FK on `posts` so users can tag posts with a single category and filter the post index by category via query params.

**Architecture:** Two migrations create the `categories` table (seeded with "Other" as id 1) and add `category_id` to `posts` with a NOT NULL DEFAULT 1 FK — existing posts automatically become "Other". The `PostsController#index` gains `?category`, `?take`, and `?page` params; `#new`/`#create`/`#show` are updated for the category dropdown and badge. All changes follow TDD.

**Tech Stack:** Rails 8.1.2, PostgreSQL, Minitest, Tailwind CSS (existing), no new gems.

**Working directory:** `/root/RubymineProjects/RailsApps/forum`

**Run tests with:** `bin/rails test` from the forum directory.

---

## Chunk 1: Migrations & Test Fixtures

### Task 1: Create the `create_categories` migration

**Note:** The existing codebase uses raw SQL for migrations with custom PK types (see `db/migrate/20260314203844_create_providers.rb`). This plan follows the same pattern for consistency — the app uses `structure.sql` so the schema is captured correctly regardless.

**Files:**
- Create: `db/migrate/20260315000001_create_categories.rb`

- [ ] **Step 1: Write the migration file**

```ruby
# db/migrate/20260315000001_create_categories.rb
class CreateCategories < ActiveRecord::Migration[8.0]
  def up
    execute <<~SQL
      CREATE TABLE categories (
        id SMALLINT PRIMARY KEY,
        name VARCHAR(100) NOT NULL,
        CONSTRAINT categories_name_unique UNIQUE (name)
      )
    SQL
    execute "INSERT INTO categories (id, name) VALUES (1, 'Other')"
  end

  def down
    drop_table :categories
  end
end
```

- [ ] **Step 2: Verify the file exists**

```bash
ls db/migrate/20260315000001_create_categories.rb
```

Expected: file listed.

- [ ] **Step 3: Commit**

```bash
git add db/migrate/20260315000001_create_categories.rb
git commit -m "feat: add create_categories migration"
```

---

### Task 2: Create the `add_category_to_posts` migration

**Files:**
- Create: `db/migrate/20260315000002_add_category_to_posts.rb`

- [ ] **Step 1: Write the migration file**

```ruby
# db/migrate/20260315000002_add_category_to_posts.rb
class AddCategoryToPosts < ActiveRecord::Migration[8.0]
  def up
    add_column :posts, :category_id, :integer, limit: 2, null: false, default: 1
    add_foreign_key :posts, :categories, column: :category_id
    add_index :posts, :category_id
  end

  def down
    remove_index :posts, :category_id
    remove_foreign_key :posts, column: :category_id
    remove_column :posts, :category_id
  end
end
```

- [ ] **Step 2: Run both migrations**

```bash
bin/rails db:migrate
```

Expected output includes both migration class names with "migrated".

- [ ] **Step 3: Verify migration status**

```bash
bin/rails db:migrate:status
```

Expected: `20260315000001` and `20260315000002` both show `up`.

- [ ] **Step 4: Prepare the test database**

```bash
bin/rails db:test:prepare
```

Expected: exits cleanly.

- [ ] **Step 5: Commit**

```bash
git add db/migrate/20260315000002_add_category_to_posts.rb db/structure.sql
git commit -m "feat: add category_id FK column to posts"
```

---

### Task 3: Add categories fixture

`test_helper.rb` has `fixtures :all` active. Since `categories` is now a real table, we need a fixture file so the test DB has the "Other" row available. Fixture files are loaded before each test (within a transaction), so this ensures `category_id: 1` is always valid.

**Files:**
- Create: `test/fixtures/categories.yml`

- [ ] **Step 1: Write the fixture file**

```yaml
# test/fixtures/categories.yml
other:
  id: 1
  name: Other
```

- [ ] **Step 2: Verify the test suite still loads**

```bash
bin/rails test test/models/user_test.rb
```

Expected: no errors about category fixtures (passing or failing tests — we just want no fixture load errors).

- [ ] **Step 3: Commit**

```bash
git add test/fixtures/categories.yml
git commit -m "test: add categories fixture with Other row"
```

---

## Chunk 2: Models

### Task 4: Create the Category model

**Files:**
- Create: `app/models/category.rb`
- Create: `test/models/category_test.rb`

- [ ] **Step 1: Write the failing tests**

```ruby
# test/models/category_test.rb
require "test_helper"

class CategoryTest < ActiveSupport::TestCase
  test "valid with id and name" do
    cat = Category.new(id: 2, name: "Tech")
    assert cat.valid?
  end

  test "invalid without name" do
    cat = Category.new(id: 2)
    assert_not cat.valid?
    assert_includes cat.errors[:name], "can't be blank"
  end

  test "name must be unique" do
    # 'other' fixture (id:1, name:'Other') is already loaded
    dup = Category.new(id: 2, name: "Other")
    assert_not dup.valid?
    assert_includes dup.errors.full_messages, "Name has already been taken"
  end

  test "name max 100 characters" do
    cat = Category.new(id: 2, name: "a" * 101)
    assert_not cat.valid?
    assert_includes cat.errors[:name], "is too long (maximum is 100 characters)"
  end

  test "has many posts association" do
    assert_respond_to Category.new, :posts
  end
end
```

- [ ] **Step 2: Run tests to confirm failure**

```bash
bin/rails test test/models/category_test.rb
```

Expected: errors like `uninitialized constant CategoryTest::Category`.

- [ ] **Step 3: Create the Category model**

```ruby
# app/models/category.rb
class Category < ApplicationRecord
  has_many :posts

  validates :name, presence: true, length: { maximum: 100 }, uniqueness: true
end
```

- [ ] **Step 4: Run tests to confirm they pass**

```bash
bin/rails test test/models/category_test.rb
```

Expected: 5 tests, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add app/models/category.rb test/models/category_test.rb
git commit -m "feat: add Category model with validations"
```

---

### Task 5: Update the Post model

**Files:**
- Modify: `app/models/post.rb`

- [ ] **Step 1: Update the Post model**

```ruby
# app/models/post.rb
class Post < ApplicationRecord
  belongs_to :user
  belongs_to :category

  has_many :replies, dependent: :destroy

  attribute :category_id, :integer, default: 1

  validates :title, presence: true, length: { maximum: 200 }
  validates :body, presence: true
end
```

- [ ] **Step 2: Run the full test suite to confirm nothing broke**

```bash
bin/rails test
```

Expected: all existing tests pass. (The `categories.yml` fixture loaded by `fixtures :all` ensures `category_id: 1` is valid for any `Post.create!` call.)

- [ ] **Step 3: Commit**

```bash
git add app/models/post.rb
git commit -m "feat: add belongs_to category to Post model"
```

---

## Chunk 3: Controller

### Task 6: Update PostsController and tests

**Files:**
- Modify: `app/controllers/posts_controller.rb`
- Modify: `test/controllers/posts_controller_test.rb`
- Modify: `test/controllers/replies_controller_test.rb`

- [ ] **Step 1: Write failing controller tests**

Append these tests to `test/controllers/posts_controller_test.rb` (inside the class, before the final `end`):

```ruby
  # ---- category filter ----

  test "GET /posts filters by category" do
    tech = Category.create!(id: 2, name: "Tech")
    Post.create!(user: @user, title: "Tech Post", body: "body", category_id: 2)
    get posts_path, params: { category: 2 }
    assert_response :success
    assert_select "h2 a", text: /Tech Post/
    assert_select "h2 a", text: /Hello World/, count: 0
  end

  test "GET /posts with unknown category returns empty results" do
    get posts_path, params: { category: 999 }
    assert_response :success
    assert_select ".post-card", count: 0
  end

  test "GET /posts with no category shows all posts" do
    get posts_path
    assert_response :success
    assert_select "h2 a", text: /Hello World/
  end

  test "GET /posts paginates: take=1 page=1 returns 1 post" do
    Post.create!(user: @user, title: "Post 2", body: "body")
    get posts_path, params: { take: 1, page: 1 }
    assert_response :success
    assert_select ".post-card", count: 1
  end

  test "GET /posts clamps take to minimum 1" do
    get posts_path, params: { take: 0 }
    assert_response :success
  end

  test "GET /posts clamps take to maximum 100" do
    get posts_path, params: { take: 999 }
    assert_response :success
  end

  # ---- new post form ----

  test "GET /posts/new renders category dropdown" do
    post login_path, params: { email: "u@example.com", password: "pass123" }
    get new_post_path
    assert_response :success
    assert_select "select[name=?]", "post[category_id]"
    assert_select "option", text: "Other"
  end

  # ---- create with category ----

  test "POST /posts with category_id saves correctly" do
    Category.create!(id: 2, name: "Tech")
    post login_path, params: { email: "u@example.com", password: "pass123" }
    post posts_path, params: { post: { title: "Tech Post", body: "Some content", category_id: 2 } }
    assert_equal 2, Post.last.category_id
  end

  test "POST /posts with invalid params re-renders with category dropdown" do
    post login_path, params: { email: "u@example.com", password: "pass123" }
    post posts_path, params: { post: { title: "", body: "" } }
    assert_response :unprocessable_entity
    assert_select "select[name=?]", "post[category_id]"
  end

  # ---- show includes category ----

  test "GET /posts/:id shows category badge" do
    get post_path(@post)
    assert_response :success
    assert_select ".category-badge"
  end
```

- [ ] **Step 2: Run failing tests to confirm they fail**

```bash
bin/rails test test/controllers/posts_controller_test.rb
```

Expected: multiple failures — `.post-card` not found, `select[name=post[category_id]]` not found, `.category-badge` not found.

- [ ] **Step 3: Update PostsController**

Replace `app/controllers/posts_controller.rb` entirely:

```ruby
class PostsController < ApplicationController
  before_action :require_login, only: [:new, :create]

  def index
    @categories = Category.all.order(:name)
    posts = Post.includes(:user, :category).order(created_at: :desc)

    category_id = params[:category].to_i
    posts = posts.where(category_id: category_id) if category_id > 0

    take = (params[:take] || 10).to_i.clamp(1, 100)
    page = [(params[:page] || 1).to_i, 1].max

    @posts = posts.limit(take).offset((page - 1) * take)
    @take  = take
    @page  = page
  end

  def show
    @post  = Post.includes(:category, replies: :user).find(params[:id])
    @reply = Reply.new
  end

  def new
    @post       = Post.new
    @categories = Category.all.order(:name)
  end

  def create
    @post = current_user.posts.build(post_params)
    if @post.save
      redirect_to @post, notice: "Post created!"
    else
      @categories = Category.all.order(:name)
      render :new, status: :unprocessable_entity
    end
  end

  private

  def post_params
    params.require(:post).permit(:title, :body, :category_id)
  end
end
```

- [ ] **Step 4: Run post controller tests (some view-dependent tests will still fail — that is expected)**

```bash
bin/rails test test/controllers/posts_controller_test.rb
```

Expected: filter/pagination/clamping tests pass; `.post-card`, `.category-badge`, and dropdown tests fail (views not updated yet).

- [ ] **Step 5: Commit the controller**

```bash
git add app/controllers/posts_controller.rb test/controllers/posts_controller_test.rb
git commit -m "feat: update PostsController with category filter and pagination"
```

---

## Chunk 4: Views

### Task 7: Update posts/index

**Files:**
- Modify: `app/views/posts/index.html.erb`

- [ ] **Step 1: Replace the index view**

```erb
<%# app/views/posts/index.html.erb %>
<div class="max-w-3xl mx-auto mt-8 px-4">
  <div class="flex items-center justify-between mb-4">
    <h1 class="text-3xl font-bold">Forum</h1>
    <% if logged_in? %>
      <%= link_to "New Post", new_post_path, class: "bg-blue-600 text-white px-4 py-2 rounded-md hover:bg-blue-700 font-medium" %>
    <% end %>
  </div>

  <%# Category filter bar %>
  <div class="flex flex-wrap gap-2 mb-6">
    <%= link_to "All", posts_path(take: @take),
          class: "px-3 py-1 rounded-full text-sm font-medium border #{params[:category].blank? ? 'bg-blue-600 text-white border-blue-600' : 'bg-white text-gray-600 border-gray-300 hover:border-blue-400'}" %>
    <% @categories.each do |cat| %>
      <%= link_to cat.name, posts_path(category: cat.id, take: @take),
            class: "px-3 py-1 rounded-full text-sm font-medium border #{params[:category].to_i == cat.id ? 'bg-blue-600 text-white border-blue-600' : 'bg-white text-gray-600 border-gray-300 hover:border-blue-400'}" %>
    <% end %>
  </div>

  <% if @posts.empty? %>
    <p class="text-gray-500">No posts yet. Be the first!</p>
  <% else %>
    <div class="space-y-4">
      <% @posts.each do |post| %>
        <div class="bg-white border border-gray-200 rounded-lg p-4 hover:shadow-sm transition post-card">
          <div class="flex items-center gap-2 mb-1">
            <h2 class="text-lg font-semibold">
              <%= link_to post.title, post_path(post), class: "text-blue-700 hover:underline" %>
            </h2>
            <%= link_to post.category.name,
                  posts_path(category: post.category_id, take: @take),
                  class: "text-xs px-2 py-0.5 rounded-full bg-gray-100 text-gray-600 hover:bg-gray-200 category-badge" %>
          </div>
          <p class="text-sm text-gray-500">
            by <%= post.user.name %> &middot; <%= time_ago_in_words(post.created_at) %> ago
          </p>
          <p class="mt-2 text-gray-700 line-clamp-2"><%= post.body %></p>
        </div>
      <% end %>
    </div>

    <%# Pagination controls %>
    <div class="flex justify-between mt-6">
      <% if @page > 1 %>
        <%= link_to "← Previous", posts_path(category: params[:category], take: @take, page: @page - 1),
              class: "text-blue-600 hover:underline text-sm" %>
      <% else %>
        <span></span>
      <% end %>

      <% if @posts.size >= @take %>
        <%= link_to "Next →", posts_path(category: params[:category], take: @take, page: @page + 1),
              class: "text-blue-600 hover:underline text-sm" %>
      <% end %>
    </div>
  <% end %>
</div>
```

- [ ] **Step 2: Run index-related tests**

```bash
bin/rails test test/controllers/posts_controller_test.rb -n "/lists posts|filter|paginate|clamp|unknown category/"
```

Expected: these tests pass.

- [ ] **Step 3: Commit**

```bash
git add app/views/posts/index.html.erb
git commit -m "feat: add category filter bar and pagination to posts index"
```

---

### Task 8: Update posts/new

**Files:**
- Modify: `app/views/posts/new.html.erb`

- [ ] **Step 1: Replace the new post view**

```erb
<%# app/views/posts/new.html.erb %>
<div class="max-w-2xl mx-auto mt-8 px-4">
  <h1 class="text-2xl font-bold mb-6">New Post</h1>

  <%= form_with model: @post, class: "space-y-4 bg-white border border-gray-200 rounded-lg p-6" do |f| %>
    <% if @post.errors.any? %>
      <div class="bg-red-50 border border-red-200 text-red-700 px-4 py-3 rounded text-sm">
        <ul class="list-disc list-inside">
          <% @post.errors.full_messages.each do |msg| %>
            <li><%= msg %></li>
          <% end %>
        </ul>
      </div>
    <% end %>

    <div>
      <%= f.label :category_id, "Category", class: "block text-sm font-medium text-gray-700" %>
      <%= f.select :category_id,
            @categories.map { |c| [c.name, c.id] },
            { selected: @post.category_id },
            class: "mt-1 block w-full border border-gray-300 rounded-md px-3 py-2 focus:outline-none focus:ring-2 focus:ring-blue-500" %>
    </div>
    <div>
      <%= f.label :title, class: "block text-sm font-medium text-gray-700" %>
      <%= f.text_field :title, class: "mt-1 block w-full border border-gray-300 rounded-md px-3 py-2 focus:outline-none focus:ring-2 focus:ring-blue-500" %>
    </div>
    <div>
      <%= f.label :body, class: "block text-sm font-medium text-gray-700" %>
      <%= f.text_area :body, rows: 8, class: "mt-1 block w-full border border-gray-300 rounded-md px-3 py-2 focus:outline-none focus:ring-2 focus:ring-blue-500" %>
    </div>
    <%= f.submit "Create Post", class: "bg-blue-600 text-white px-4 py-2 rounded-md hover:bg-blue-700 font-medium" %>
  <% end %>
</div>
```

- [ ] **Step 2: Run new/create tests**

```bash
bin/rails test test/controllers/posts_controller_test.rb -n "/new|create/"
```

Expected: all new/create tests pass including dropdown and re-render tests.

- [ ] **Step 3: Commit**

```bash
git add app/views/posts/new.html.erb
git commit -m "feat: add category dropdown to new post form"
```

---

### Task 9: Update posts/show

**Files:**
- Modify: `app/views/posts/show.html.erb`

- [ ] **Step 1: Replace the show view**

```erb
<%# app/views/posts/show.html.erb %>
<div class="max-w-3xl mx-auto mt-8 px-4">
  <%= link_to "← Back to Forum", posts_path, class: "text-blue-600 hover:underline text-sm" %>

  <div class="bg-white border border-gray-200 rounded-lg p-6 mt-4">
    <h1 class="text-2xl font-bold"><%= @post.title %></h1>
    <div class="flex items-center gap-2 mt-1">
      <%= link_to @post.category.name,
            posts_path(category: @post.category_id),
            class: "text-xs px-2 py-0.5 rounded-full bg-gray-100 text-gray-600 hover:bg-gray-200 category-badge" %>
      <p class="text-sm text-gray-500">
        by <%= @post.user.name %> &middot; <%= time_ago_in_words(@post.created_at) %> ago
      </p>
    </div>
    <div class="mt-4 text-gray-800 whitespace-pre-wrap"><%= @post.body %></div>
  </div>

  <div class="mt-8">
    <h2 class="text-xl font-semibold mb-4">
      Replies (<%= @post.replies.size %>)
    </h2>

    <% @post.replies.each do |reply| %>
      <div class="bg-gray-50 border border-gray-200 rounded-lg p-4 mb-3">
        <p class="text-gray-800 whitespace-pre-wrap"><%= reply.body %></p>
        <p class="text-sm text-gray-500 mt-2">
          &mdash; <%= reply.user.name %>, <%= time_ago_in_words(reply.created_at) %> ago
        </p>
      </div>
    <% end %>

    <% if logged_in? %>
      <div class="mt-6 bg-white border border-gray-200 rounded-lg p-4">
        <h3 class="font-medium mb-3">Leave a Reply</h3>
        <%= form_with model: [@post, @reply], class: "space-y-3" do |f| %>
          <% if @reply.errors.any? %>
            <div class="bg-red-50 border border-red-200 text-red-700 px-3 py-2 rounded text-sm">
              <%= @reply.errors.full_messages.to_sentence %>
            </div>
          <% end %>
          <%= f.text_area :body, rows: 4, placeholder: "Write your reply...",
                class: "w-full border border-gray-300 rounded-md px-3 py-2 focus:outline-none focus:ring-2 focus:ring-blue-500" %>
          <%= f.submit "Post Reply", class: "bg-blue-600 text-white px-4 py-2 rounded-md hover:bg-blue-700 font-medium" %>
        <% end %>
      </div>
    <% else %>
      <p class="mt-6 text-gray-600 text-sm">
        <%= link_to "Log in", login_path, class: "text-blue-600 hover:underline" %> to reply.
      </p>
    <% end %>
  </div>
</div>
```

- [ ] **Step 2: Run the full test suite**

```bash
bin/rails test
```

Expected: all tests pass. Zero failures.

- [ ] **Step 3: Commit**

```bash
git add app/views/posts/show.html.erb
git commit -m "feat: add category badge to post show page"
```

---

## Final Verification

- [ ] **Run the full test suite**

```bash
bin/rails test
```

Expected: all tests green.

- [ ] **Start the server and smoke test manually**

```bash
bin/dev
```

Open browser and verify:
1. Posts index shows a category filter bar with "All" and "Other"
2. Clicking "Other" filters to `?category=1`
3. Creating a new post shows a category dropdown defaulting to "Other"
4. Post show page displays a category badge linking back to filtered index

---

## Spec Reference

`docs/superpowers/specs/2026-03-15-category-topic-design.md`
