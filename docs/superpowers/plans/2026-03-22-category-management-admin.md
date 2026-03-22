# Category Management Admin Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give admins a UI to create, rename, reorder (up/down), and safely delete forum categories from `/admin/categories`.

**Architecture:** Standard Rails CRUD under the existing `Admin::` namespace. A `position smallint` column is added to `categories` and a `default_scope` keeps every caller ordered automatically. Up/down reordering swaps adjacent positions in a transaction. Deletion is blocked at the application layer when posts exist.

**Tech Stack:** Rails 8.1, PostgreSQL, Minitest (integration tests), Tailwind CSS, importmap (no npm/JS required).

**Spec:** `docs/superpowers/specs/2026-03-22-category-management-admin-design.md`

---

## File Map

| File | Action | Purpose |
|------|--------|---------|
| `db/migrate/TIMESTAMP_add_position_to_categories.rb` | Create | Add position column + backfill |
| `app/models/category.rb` | Modify | default_scope + position validation |
| `config/routes.rb` | Modify | Admin categories resources + move_up/move_down |
| `app/controllers/admin/categories_controller.rb` | Create | All CRUD + move_up + move_down |
| `app/views/admin/categories/index.html.erb` | Create | Table with reorder/edit/delete actions |
| `app/views/admin/categories/_form.html.erb` | Create | Shared name field form partial |
| `app/views/admin/categories/new.html.erb` | Create | Wraps form partial |
| `app/views/admin/categories/edit.html.erb` | Create | Wraps form partial |
| `app/views/layouts/admin.html.erb` | Modify | Add Categories nav link |
| `test/controllers/admin/categories_controller_test.rb` | Create | Full controller test suite |

---

## Task 1: Migration — add `position` to `categories`

**Files:**
- Create: `db/migrate/TIMESTAMP_add_position_to_categories.rb`

- [ ] **Step 1: Generate the migration**

```bash
bin/rails generate migration AddPositionToCategories
```

- [ ] **Step 2: Fill in the migration body**

Replace the generated file body with:

```ruby
class AddPositionToCategories < ActiveRecord::Migration[8.1]
  def up
    add_column :categories, :position, :integer, limit: 2, null: false, default: 0

    execute <<~SQL
      UPDATE categories SET position = 1 WHERE id = 2;
      UPDATE categories SET position = 2 WHERE id = 3;
      UPDATE categories SET position = 3 WHERE id = 4;
    SQL

    change_column_default :categories, :position, from: 0, to: nil
  end

  def down
    remove_column :categories, :position
  end
end
```

- [ ] **Step 3: Run the migration**

```bash
bin/rails db:migrate
```

Expected: migration runs without error.

- [ ] **Step 4: Verify the column exists**

```bash
bin/rails runner "puts Category.order(:position).pluck(:id, :name, :position).inspect"
```

Expected output like: `[[2, "Tech", 1], [3, "Life Style", 2], [4, "Off Topic", 3]]`

- [ ] **Step 5: Run the full test suite**

```bash
bin/rails test
```

Expected: all existing tests pass (no failures from the new column).

- [ ] **Step 6: Commit**

```bash
git add db/migrate/ db/structure.sql
git commit -m "feat: add position column to categories"
```

---

## Task 2: Model — default_scope and position validation

**Files:**
- Modify: `app/models/category.rb`

- [ ] **Step 1: Update the model**

Replace the full contents of `app/models/category.rb` with:

```ruby
class Category < ApplicationRecord
  has_many :posts

  default_scope { order(:position) }

  validates :name, presence: true, length: { maximum: 100 }, uniqueness: true
  validates :position, numericality: { only_integer: true, greater_than: 0 }
end
```

- [ ] **Step 2: Run the full test suite**

```bash
bin/rails test
```

Expected: all pass. The `default_scope` changes query order — verify nothing breaks.

- [ ] **Step 3: Commit**

```bash
git add app/models/category.rb
git commit -m "feat: add default_scope and position validation to Category"
```

---

## Task 3: Routes

**Files:**
- Modify: `config/routes.rb`

- [ ] **Step 1: Add categories to the admin namespace**

In `config/routes.rb`, inside the `namespace :admin do` block, add after `resources :flags`:

```ruby
resources :categories, only: [ :index, :new, :create, :edit, :update, :destroy ] do
  member do
    patch :move_up
    patch :move_down
  end
end
```

- [ ] **Step 2: Verify routes exist**

```bash
bin/rails routes | grep admin.*categor
```

Expected output includes lines for:
- `GET    /admin/categories`
- `GET    /admin/categories/new`
- `POST   /admin/categories`
- `GET    /admin/categories/:id/edit`
- `PATCH  /admin/categories/:id`
- `DELETE /admin/categories/:id`
- `PATCH  /admin/categories/:id/move_up`
- `PATCH  /admin/categories/:id/move_down`

- [ ] **Step 3: Commit**

```bash
git add config/routes.rb
git commit -m "feat: add admin categories routes with move_up/move_down"
```

---

## Task 4: Controller with tests (TDD)

**Files:**
- Create: `test/controllers/admin/categories_controller_test.rb`
- Create: `app/controllers/admin/categories_controller.rb`

- [ ] **Step 1: Write the failing tests**

Create `test/controllers/admin/categories_controller_test.rb`:

```ruby
require "test_helper"

class Admin::CategoriesControllerTest < ActionDispatch::IntegrationTest
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

    # Use unscoped to avoid default_scope ordering issues in setup
    Category.unscoped.delete_all
    @cat_a = Category.create!(name: "Alpha", position: 1)
    @cat_b = Category.create!(name: "Beta",  position: 2)
    @cat_c = Category.create!(name: "Gamma", position: 3)
  end

  # --- auth ---

  test "index redirects guest to login" do
    get admin_categories_path
    assert_redirected_to login_path
  end

  test "index redirects creator to root" do
    post login_path, params: { email: "creator@example.com", password: "pass123" }
    get admin_categories_path
    assert_redirected_to root_path
  end

  test "index redirects sub_admin to root" do
    post login_path, params: { email: "sub@example.com", password: "pass123" }
    get admin_categories_path
    assert_redirected_to root_path
  end

  test "index is accessible to admin" do
    post login_path, params: { email: "admin@example.com", password: "pass123" }
    get admin_categories_path
    assert_response :success
  end

  # --- index ---

  test "index lists all categories" do
    post login_path, params: { email: "admin@example.com", password: "pass123" }
    get admin_categories_path
    assert_response :success
    assert_match "Alpha", response.body
    assert_match "Beta", response.body
    assert_match "Gamma", response.body
  end

  # --- new ---

  test "new renders form" do
    post login_path, params: { email: "admin@example.com", password: "pass123" }
    get new_admin_category_path
    assert_response :success
  end

  # --- create ---

  test "create with valid params creates category and redirects" do
    post login_path, params: { email: "admin@example.com", password: "pass123" }
    assert_difference "Category.count", 1 do
      post admin_categories_path, params: { category: { name: "New Category" } }
    end
    assert_redirected_to admin_categories_path
    assert_equal "Category created.", flash[:notice]
  end

  test "create assigns next position automatically" do
    post login_path, params: { email: "admin@example.com", password: "pass123" }
    post admin_categories_path, params: { category: { name: "New Category" } }
    assert_equal 4, Category.find_by!(name: "New Category").position
  end

  test "create with blank name re-renders form" do
    post login_path, params: { email: "admin@example.com", password: "pass123" }
    assert_no_difference "Category.count" do
      post admin_categories_path, params: { category: { name: "" } }
    end
    assert_response :unprocessable_entity
  end

  test "create with duplicate name re-renders form" do
    post login_path, params: { email: "admin@example.com", password: "pass123" }
    assert_no_difference "Category.count" do
      post admin_categories_path, params: { category: { name: "Alpha" } }
    end
    assert_response :unprocessable_entity
  end

  # --- edit ---

  test "edit renders form" do
    post login_path, params: { email: "admin@example.com", password: "pass123" }
    get edit_admin_category_path(@cat_a)
    assert_response :success
  end

  # --- update ---

  test "update with valid params updates and redirects" do
    post login_path, params: { email: "admin@example.com", password: "pass123" }
    patch admin_category_path(@cat_a), params: { category: { name: "Renamed" } }
    assert_redirected_to admin_categories_path
    assert_equal "Category updated.", flash[:notice]
    assert_equal "Renamed", @cat_a.reload.name
  end

  test "update with blank name re-renders form" do
    post login_path, params: { email: "admin@example.com", password: "pass123" }
    patch admin_category_path(@cat_a), params: { category: { name: "" } }
    assert_response :unprocessable_entity
  end

  test "update with duplicate name re-renders form" do
    post login_path, params: { email: "admin@example.com", password: "pass123" }
    patch admin_category_path(@cat_a), params: { category: { name: "Beta" } }
    assert_response :unprocessable_entity
  end

  # --- move_up ---

  test "move_up swaps position with previous category" do
    post login_path, params: { email: "admin@example.com", password: "pass123" }
    patch move_up_admin_category_path(@cat_b)
    assert_redirected_to admin_categories_path
    assert_equal 1, @cat_b.reload.position
    assert_equal 2, @cat_a.reload.position
  end

  test "move_up on first category is a no-op" do
    post login_path, params: { email: "admin@example.com", password: "pass123" }
    patch move_up_admin_category_path(@cat_a)
    assert_redirected_to admin_categories_path
    assert_equal 1, @cat_a.reload.position
  end

  # --- move_down ---

  test "move_down swaps position with next category" do
    post login_path, params: { email: "admin@example.com", password: "pass123" }
    patch move_down_admin_category_path(@cat_b)
    assert_redirected_to admin_categories_path
    assert_equal 3, @cat_b.reload.position
    assert_equal 2, @cat_c.reload.position
  end

  test "move_down on last category is a no-op" do
    post login_path, params: { email: "admin@example.com", password: "pass123" }
    patch move_down_admin_category_path(@cat_c)
    assert_redirected_to admin_categories_path
    assert_equal 3, @cat_c.reload.position
  end

  # --- destroy ---

  test "destroy deletes category with no posts and redirects" do
    post login_path, params: { email: "admin@example.com", password: "pass123" }
    assert_difference "Category.count", -1 do
      delete admin_category_path(@cat_a)
    end
    assert_redirected_to admin_categories_path
    assert_equal "Category deleted.", flash[:notice]
  end

  test "destroy is blocked when category has posts" do
    post login_path, params: { email: "admin@example.com", password: "pass123" }
    post_record = Post.create!(user: @creator, title: "Post", body: "Body", category: @cat_a)
    assert_no_difference "Category.count" do
      delete admin_category_path(@cat_a)
    end
    assert_redirected_to admin_categories_path
    assert_match "Cannot delete", flash[:alert]
    post_record.destroy
  end
end
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
bin/rails test test/controllers/admin/categories_controller_test.rb
```

Expected: routing errors or `uninitialized constant Admin::CategoriesController`.

- [ ] **Step 3: Create the controller**

Create `app/controllers/admin/categories_controller.rb`:

```ruby
class Admin::CategoriesController < Admin::BaseController
  before_action :require_admin
  before_action :set_category, only: [ :edit, :update, :destroy, :move_up, :move_down ]

  def index
    @categories  = Category.all
    @post_counts = Post.group(:category_id).count
  end

  def new
    @category = Category.new
  end

  def create
    @category = Category.new(category_params)
    @category.position = Category.unscoped.maximum(:position).to_i + 1
    if @category.save
      redirect_to admin_categories_path, notice: "Category created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @category.update(category_params)
      redirect_to admin_categories_path, notice: "Category updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @category.posts.exists?
      redirect_to admin_categories_path, alert: "Cannot delete: category has posts." and return
    end
    @category.destroy
    redirect_to admin_categories_path, notice: "Category deleted."
  end

  def move_up
    prev_cat = Category.unscoped.where("position < ?", @category.position).order(position: :desc).first
    if prev_cat
      ActiveRecord::Base.transaction do
        pos = @category.position
        @category.update!(position: prev_cat.position)
        prev_cat.update!(position: pos)
      end
    end
    redirect_to admin_categories_path
  rescue ActiveRecord::RecordInvalid
    redirect_to admin_categories_path, alert: "Could not reorder categories. Please try again."
  end

  def move_down
    next_cat = Category.unscoped.where("position > ?", @category.position).order(position: :asc).first
    if next_cat
      ActiveRecord::Base.transaction do
        pos = @category.position
        @category.update!(position: next_cat.position)
        next_cat.update!(position: pos)
      end
    end
    redirect_to admin_categories_path
  rescue ActiveRecord::RecordInvalid
    redirect_to admin_categories_path, alert: "Could not reorder categories. Please try again."
  end

  private

  def set_category
    @category = Category.unscoped.find(params[:id])
  end

  def category_params
    params.require(:category).permit(:name)
  end
end
```

- [ ] **Step 4: Run the controller tests**

```bash
bin/rails test test/controllers/admin/categories_controller_test.rb
```

Expected: all pass.

- [ ] **Step 5: Run the full suite**

```bash
bin/rails test
```

Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add app/controllers/admin/categories_controller.rb \
        test/controllers/admin/categories_controller_test.rb
git commit -m "feat: Admin::CategoriesController with tests"
```

---

## Task 5: Views

**Files:**
- Create: `app/views/admin/categories/index.html.erb`
- Create: `app/views/admin/categories/_form.html.erb`
- Create: `app/views/admin/categories/new.html.erb`
- Create: `app/views/admin/categories/edit.html.erb`

- [ ] **Step 1: Create the index view**

Create `app/views/admin/categories/index.html.erb`:

```erb
<%# app/views/admin/categories/index.html.erb %>
<% content_for :title, "Categories – Admin Panel" %>

<div class="flex items-center justify-between mb-6">
  <h1 class="text-2xl font-bold text-gray-900">Categories</h1>
  <%= link_to "New Category", new_admin_category_path,
        class: "bg-teal-700 text-white px-4 py-2 rounded-lg text-sm hover:bg-teal-600" %>
</div>

<div class="bg-white rounded-xl shadow-sm border border-stone-200 overflow-hidden">
  <table class="w-full text-sm">
    <thead class="bg-stone-50 border-b border-stone-200">
      <tr>
        <th class="text-left px-4 py-3 font-medium text-gray-600">Position</th>
        <th class="text-left px-4 py-3 font-medium text-gray-600">Name</th>
        <th class="text-right px-4 py-3 font-medium text-gray-600">Posts</th>
        <th class="px-4 py-3"></th>
      </tr>
    </thead>
    <tbody class="divide-y divide-stone-100">
      <% @categories.each_with_index do |category, index| %>
        <tr class="hover:bg-stone-50">
          <td class="px-4 py-3 text-gray-500"><%= category.position %></td>
          <td class="px-4 py-3 font-medium text-gray-900"><%= category.name %></td>
          <td class="px-4 py-3 text-right text-gray-700"><%= @post_counts[category.id].to_i %></td>
          <td class="px-4 py-3">
            <div class="flex items-center justify-end gap-2">
              <%= button_to "▲", move_up_admin_category_path(category), method: :patch,
                    class: "text-gray-400 hover:text-gray-700 px-1 #{index == 0 ? 'hidden' : ''}" %>
              <%= button_to "▼", move_down_admin_category_path(category), method: :patch,
                    class: "text-gray-400 hover:text-gray-700 px-1 #{index == @categories.length - 1 ? 'hidden' : ''}" %>
              <%= link_to "Edit", edit_admin_category_path(category),
                    class: "text-teal-700 hover:underline" %>
              <% if @post_counts[category.id].to_i > 0 %>
                <button disabled title="Cannot delete: category has posts"
                        class="text-red-300 opacity-50 cursor-not-allowed">Delete</button>
              <% else %>
                <%= button_to "Delete", admin_category_path(category), method: :delete,
                      data: { turbo_confirm: "Delete #{category.name}? This cannot be undone." },
                      class: "text-red-600 hover:text-red-800" %>
              <% end %>
            </div>
          </td>
        </tr>
      <% end %>
      <% if @categories.empty? %>
        <tr>
          <td colspan="4" class="px-4 py-8 text-center text-gray-500">No categories yet.</td>
        </tr>
      <% end %>
    </tbody>
  </table>
</div>
```

- [ ] **Step 2: Create the form partial**

Create `app/views/admin/categories/_form.html.erb`:

```erb
<%# app/views/admin/categories/_form.html.erb %>
<%= form_with model: [ :admin, category ], class: "space-y-4" do |f| %>
  <% if category.errors.any? %>
    <div class="bg-red-50 border border-red-200 text-red-700 px-4 py-3 rounded-lg text-sm">
      <ul class="list-disc list-inside">
        <% category.errors.full_messages.each do |msg| %>
          <li><%= msg %></li>
        <% end %>
      </ul>
    </div>
  <% end %>

  <div>
    <%= f.label :name, class: "block text-sm font-medium text-gray-700 mb-1" %>
    <%= f.text_field :name,
          class: "w-full px-3 py-2 rounded-lg border border-stone-300 text-sm focus:outline-none focus:ring-2 focus:ring-teal-400",
          autofocus: true %>
  </div>

  <div class="flex gap-3">
    <%= f.submit class: "bg-teal-700 text-white px-4 py-2 rounded-lg text-sm hover:bg-teal-600 cursor-pointer" %>
    <%= link_to "Cancel", admin_categories_path, class: "text-sm text-gray-500 hover:text-gray-700 px-2 py-2" %>
  </div>
<% end %>
```

- [ ] **Step 3: Create new.html.erb**

Create `app/views/admin/categories/new.html.erb`:

```erb
<%# app/views/admin/categories/new.html.erb %>
<% content_for :title, "New Category – Admin Panel" %>

<div class="flex items-center justify-between mb-6">
  <h1 class="text-2xl font-bold text-gray-900">New Category</h1>
</div>

<div class="bg-white rounded-xl shadow-sm border border-stone-200 p-6 max-w-lg">
  <%= render "form", category: @category %>
</div>
```

- [ ] **Step 4: Create edit.html.erb**

Create `app/views/admin/categories/edit.html.erb`:

```erb
<%# app/views/admin/categories/edit.html.erb %>
<% content_for :title, "Edit Category – Admin Panel" %>

<div class="flex items-center justify-between mb-6">
  <h1 class="text-2xl font-bold text-gray-900">Edit Category</h1>
</div>

<div class="bg-white rounded-xl shadow-sm border border-stone-200 p-6 max-w-lg">
  <%= render "form", category: @category %>
</div>
```

- [ ] **Step 5: Run the full test suite**

```bash
bin/rails test
```

Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add app/views/admin/categories/
git commit -m "feat: admin categories views (index, new, edit, form partial)"
```

---

## Task 6: Admin nav link

**Files:**
- Modify: `app/views/layouts/admin.html.erb`

- [ ] **Step 1: Add the Categories nav link**

In `app/views/layouts/admin.html.erb`, after the "Users" link and before the "Reports" link, add:

```erb
        <%= link_to "Categories", admin_categories_path,
              class: "flex items-center px-3 py-2 rounded-lg text-sm font-medium #{
                request.path.start_with?(admin_categories_path) ? 'bg-gray-700 text-white' : 'text-gray-300 hover:bg-gray-700 hover:text-white'
              }" %>
```

- [ ] **Step 2: Run the full test suite**

```bash
bin/rails test
```

Expected: all pass.

- [ ] **Step 3: Commit**

```bash
git add app/views/layouts/admin.html.erb
git commit -m "feat: add Categories link to admin sidebar nav"
```

---

## Task 7: CI and final check

- [ ] **Step 1: Run the full CI pipeline**

```bash
bin/ci
```

Expected: lint, security, and all tests pass.

- [ ] **Step 2: Fix any Rubocop offences**

```bash
./bin/rubocop -a
git add -p
git commit -m "style: rubocop fixes for category admin"
```

Only run step 2 if step 1 reported Rubocop offences.
