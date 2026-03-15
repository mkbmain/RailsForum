# Category/Topic Feature Design

**Date:** 2026-03-15
**App:** Rails 8.1.2 Forum (`/root/RubymineProjects/RailsApps/forum`)

---

## Overview

Add a `categories` table to the forum database so posts can be tagged with a single category. Users can filter the post index by category via query params. Existing posts default to the "Other" category (id: 1).

---

## Database

### New `categories` table

- `id` — smallint primary key
- `name` — varchar(100), not null, unique index

The `create_categories` migration inserts `(1, 'Other')` via raw SQL inside the migration itself (not seeds), so the row exists before the second migration adds the FK.

### Alter `posts` table

Add `category_id smallint NOT NULL DEFAULT 1` with a foreign key constraint to `categories(id)` and an index.

- The `DEFAULT 1` means all existing rows automatically belong to "Other" — no data migration needed.
- The FK migration runs after `create_categories` (which has already inserted id=1).
- Both column and PK use smallint (`:integer, limit: 2`); PostgreSQL FK type resolution is compatible.

**Migration order (critical):**
1. `create_categories` (creates table + inserts `(1, 'Other')`)
2. `add_category_to_posts` (adds FK column referencing categories)

Rollback is safe: Rails reverses migration order automatically, so `add_category_to_posts` is rolled back before `create_categories`.

---

## Models

### `Category`

```ruby
class Category < ApplicationRecord
  has_many :posts
  validates :name, presence: true, length: { maximum: 100 }, uniqueness: true
end
```

### `Post` (additions)

```ruby
belongs_to :category
attribute :category_id, :integer, default: 1
```

`belongs_to :category` enforces presence at the model level (Rails 5+ default). This is intentional — posts must always have a category. The explicit `attribute` default ensures `Post.new` has `category_id: 1` at the Ruby level without relying on DB inference.

A tampered or nonexistent `category_id` submitted via the form will fail the `belongs_to` validation (record not found → validation error) and re-render the form with an error message. No additional controller-level guard is required.

---

## Controller

### `PostsController#index`

Accepted query params:

| Param      | Type    | Default | Description                        |
|------------|---------|---------|------------------------------------|
| `category` | integer | nil     | Filter by category id              |
| `take`     | integer | 10      | Number of posts per page (limit)   |
| `page`     | integer | 1       | Page number (drives offset)        |

`take` is clamped between 1 and 100. `page` is clamped to a minimum of 1. `category` is cast to integer; values <= 0 are ignored (no filter applied). An unrecognised positive category id returns an empty result set (not a 404).

```ruby
def index
  @categories = Category.all.order(:name)
  posts = Post.includes(:user, :category).order(created_at: :desc)
  # :user is an existing association, unchanged

  category_id = params[:category].to_i
  posts = posts.where(category_id: category_id) if category_id > 0

  take = (params[:take] || 10).to_i.clamp(1, 100)
  page = [(params[:page] || 1).to_i, 1].max

  @posts = posts.limit(take).offset((page - 1) * take)
  @take  = take
  @page  = page
end
```

### `PostsController#new`

```ruby
def new
  @post       = Post.new
  @categories = Category.all.order(:name)
end
```

### `PostsController#create`

`category_id` must be permitted in strong parameters. If validation fails, `@categories` must be assigned before re-rendering `new` (otherwise the dropdown raises `NoMethodError`):

```ruby
def create
  @post = current_user.posts.build(post_params)
  if @post.save
    redirect_to @post
  else
    @categories = Category.all.order(:name)
    render :new, status: :unprocessable_entity
  end
end

def post_params
  params.require(:post).permit(:title, :body, :category_id)
end
```

### `PostsController#show`

Must include `:category` to avoid an N+1 query when rendering the category badge:

```ruby
def show
  @post = Post.includes(replies: :user, category: []).find(params[:id])
  # ... rest of existing action
end
```

Or equivalently: `@post = Post.includes(:category, replies: :user).find(params[:id])`

### `PostsController#edit` / `#update`

These actions do not exist in the current app and are out of scope.

---

## Views

### `posts/index`

- Category filter bar listing all categories; clicking one sets `?category=<id>` on `/posts` (root path maps to `posts#index`). Active category is highlighted.
- Each post row shows its category name alongside title/author/time.
- Pagination controls:
  - "Previous" is hidden on page 1.
  - "Next" is hidden when the current page returned fewer than `take` results. Known trade-off: if exactly `take` results land on the last page, "Next" still appears (one extra blank page). Accepted to avoid a total-count query.
  - On a blank page, "Next" is hidden and only "Previous" shows.
  - Both controls preserve existing `category` and `take` params.

### `posts/new`

- `<select>` dropdown populated from `@categories`, pre-selected via `selected: @post.category_id` (which is `1` by default).

### `posts/show`

- Category name displayed as a badge near the post title. Clicking it links to `/posts?category=<id>`.

---

## Migrations

`execute` statements are not automatically reversible. Both migrations use `up`/`down` methods.

### 1. `create_categories`

```ruby
def up
  create_table :categories, id: false do |t|
    t.column :id, :smallint, null: false
    t.string :name, limit: 100, null: false
  end
  execute "ALTER TABLE categories ADD PRIMARY KEY (id)"
  add_index :categories, :name, unique: true
  execute "INSERT INTO categories (id, name) VALUES (1, 'Other')"
end

def down
  drop_table :categories
end
```

> `id: false` suppresses the auto-generated bigint PK; the smallint PK is added via raw SQL for PostgreSQL compatibility.

### 2. `add_category_to_posts`

```ruby
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
```

---

## Testing

### Test setup

All existing tests that call `Post.create!` rely on a `categories` row with `id: 1` being present (due to the NOT NULL DEFAULT 1 FK). The test setup block must seed this row:

```ruby
setup do
  Category.find_or_create_by!(id: 1) { |c| c.name = 'Other' }
  # ... existing setup
end
```

Alternatively, add a `categories` fixture file with the "Other" row.

### New test cases

- **Category filter:** `GET /posts?category=<id>` returns only posts in that category
- **Unknown category:** `GET /posts?category=999` returns empty result (no 404)
- **Pagination:** `GET /posts?take=2&page=2` returns the correct offset slice
- **`take` clamping:** `?take=0` returns 1 result; `?take=999` returns at most 100
- **Dropdown in new post form:** `GET /posts/new` renders a `<select>` with category options, defaulting to "Other"
- **Create with category:** `POST /posts` with `category_id: <id>` saves correctly
- **Create validation failure:** failed `POST /posts` re-renders form without raising (i.e., `@categories` is set)
- **Show category badge:** `GET /posts/:id` includes the category name without N+1 queries

---

## Out of Scope (YAGNI)

- Admin UI for creating/managing categories
- User-created categories
- Multiple categories per post
- Full-text search
- Total page count / last-page detection
- `edit`/`update` actions for posts
