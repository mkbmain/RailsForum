# Category Management Admin — Design Spec

## Goal

Give admins a UI to create, rename, reorder, and (where safe) delete forum categories without touching `db/seeds.rb` or running migrations.

## Scope & Constraints

- Admin-only — sub-admins cannot manage categories (consistent with promote/demote pattern)
- No pagination — category lists are expected to stay under a dozen entries
- Reordering via up/down buttons — no drag-and-drop; fits importmap/no-npm stack
- Deletion blocked at the application layer when posts exist (FK constraint makes DB-level deletion a migration concern, not an admin concern)

---

## Data Layer

### Migration

Add a `position smallint NOT NULL DEFAULT 0` column to `categories`.

Backfill existing rows with explicit positions:
- Tech → 1
- Life Style → 2
- Off Topic → 3 (highest — renders last, acts as catch-all)

No DB uniqueness constraint on `position`. The application handles ordering; swaps are done atomically in a transaction.

### Model changes (`app/models/category.rb`)

- Add `default_scope { order(:position) }` — all callers (forum dropdowns, admin list) get the admin-defined order for free
- On create, auto-assign `position = Category.maximum(:position).to_i + 1`
- Existing validations (`presence`, `uniqueness`, `length: { maximum: 100 }`) unchanged

---

## Controller & Routes

### Routes

Under the existing `namespace :admin` block:

```ruby
resources :categories, only: [:index, :new, :create, :edit, :update, :destroy] do
  member do
    patch :move_up
    patch :move_down
  end
end
```

### `Admin::CategoriesController`

Actions: `index`, `new`, `create`, `edit`, `update`, `destroy`, `move_up`, `move_down`.

Auth: `before_action :require_admin` on all actions.

**`destroy`** — checks `category.posts.exists?` before deleting. Redirects with an alert if posts exist; never deletes a category with posts.

**`move_up`** — swaps `position` with the previous category (lower position) in a transaction. No-op (redirect) if already first.

**`move_down`** — swaps `position` with the next category (higher position) in a transaction. No-op (redirect) if already last.

**`create`** — assigns `position = Category.maximum(:position).to_i + 1` before save.

---

## Views

### `admin/categories/index.html.erb`

- Page header: "Categories" h1 + "New Category" button (teal, top-right)
- White card table (stone border, consistent with admin users index style)
- Columns: Position, Name, Posts (count), Actions
- Each row actions: ▲ (hidden for first row), ▼ (hidden for last row), Edit link, Delete button
- Delete button: greyed out with a `title` tooltip ("Cannot delete: category has posts") when posts exist; active otherwise

### `admin/categories/new.html.erb` + `edit.html.erb`

Both render a shared `_form.html.erb` partial. Single field: Name. Submit label "Create Category" / "Update Category".

### `app/views/layouts/admin.html.erb`

Add a "Categories" nav link after "Users", using the same active-state pattern as existing links.

---

## Testing

`test/controllers/admin/categories_controller_test.rb`:

- Guest redirected to login
- Creator (logged-in, no role) redirected to root
- Sub-admin redirected to root (admin-only)
- Admin: GET index succeeds
- Admin: GET new succeeds
- Admin: POST create with valid params creates category and redirects
- Admin: POST create with invalid params re-renders form
- Admin: GET edit succeeds
- Admin: PATCH update with valid params updates and redirects
- Admin: PATCH update with invalid params re-renders form
- Admin: PATCH move_up swaps positions correctly
- Admin: PATCH move_down swaps positions correctly
- Admin: DELETE destroy succeeds when no posts
- Admin: DELETE destroy blocked (redirects with alert) when posts exist

No model tests needed — model stays minimal; existing validations already tested indirectly.

---

## File Map

| File | Action |
|------|--------|
| `db/migrate/TIMESTAMP_add_position_to_categories.rb` | Create |
| `app/models/category.rb` | Modify |
| `config/routes.rb` | Modify |
| `app/controllers/admin/categories_controller.rb` | Create |
| `app/views/admin/categories/index.html.erb` | Create |
| `app/views/admin/categories/new.html.erb` | Create |
| `app/views/admin/categories/edit.html.erb` | Create |
| `app/views/admin/categories/_form.html.erb` | Create |
| `app/views/layouts/admin.html.erb` | Modify |
| `test/controllers/admin/categories_controller_test.rb` | Create |
