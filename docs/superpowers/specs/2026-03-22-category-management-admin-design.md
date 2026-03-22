# Category Management Admin — Design Spec

## Goal

Give admins a UI to create, rename, reorder, and (where safe) delete forum categories without touching `db/seeds.rb` or running migrations.

## Scope & Constraints

- **Admin-only** — all actions require full admin role. Sub-admins cannot manage categories (consistent with promote/demote pattern in `Admin::UsersController`). `Admin::BaseController` already enforces `require_login` + `require_moderator`; `require_admin` is the additional check added to all actions in this controller.
- No pagination — category lists stay under a dozen entries
- Reordering via up/down buttons — no drag-and-drop; fits importmap/no-npm stack
- Deletion blocked at the application layer when posts exist. PostgreSQL's FK constraint on `posts.category_id` has default RESTRICT behavior, so the DB would also reject the delete — the application check is both defensive and communicates a clear error to the admin instead of a 500.

---

## Data Layer

### Migration

Add a `position smallint NOT NULL` column (smallint = 2 bytes, −32,768 to 32,767; adequate for ≤ a dozen categories). A temporary `DEFAULT 0` is used during the migration so the NOT NULL constraint is satisfied for existing rows before the backfill runs. The default is removed after backfill so the application is the sole source of position assignment.

Migration steps:
1. Add column with `default: 0, null: false, limit: 2`
2. Backfill existing rows by ID using `execute` SQL (bypasses ActiveRecord validations): id=2 (Tech) → position 1, id=3 (Life Style) → position 2, id=4 (Off Topic) → position 3
3. Remove the DB default: `change_column_default :categories, :position, from: 0, to: nil`

### Model changes (`app/models/category.rb`)

- Add `default_scope { order(:position) }` — all callers (forum dropdowns, admin list) get the admin-defined order for free
- Add `validates :position, numericality: { only_integer: true, greater_than: 0 }` — prevents a zero or negative position from being saved
- On create, auto-assign `position = Category.maximum(:position).to_i + 1` in the controller before save. Concurrent creation by two admins is an accepted limitation given the usage context (admin panel, tiny category list).
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

**`create`** — assigns `@category.position = Category.maximum(:position).to_i + 1` before save.

**`destroy`** — checks `category.posts.exists?` before deleting. Redirects with an alert if posts exist; never deletes a category that has posts.

**`move_up`** — finds the category with the next-lower position value. If none exists (already first, or only one category), redirects silently. Otherwise wraps the position swap in `ActiveRecord::Base.transaction`. Rescues `ActiveRecord::RecordNotFound` and `ActiveRecord::RecordInvalid` and redirects with alert: `"Could not reorder categories. Please try again."`.

**`move_down`** — same logic as move_up but finds the next-higher position. If already last (including the single-category case), redirects silently.

---

## Views

### `admin/categories/index.html.erb`

- Page header: `<div class="flex items-center justify-between mb-6">` containing "Categories" h1 (left) and "New Category" button (teal, right) — same layout pattern as admin users index
- White card table (stone border, consistent with admin style)
- Columns: Position, Name, Posts (count), Actions
- Each row actions:
  - ▲ button — `PATCH move_up`; hidden (`hidden` class) on first row
  - ▼ button — `PATCH move_down`; hidden on last row
  - Edit link
  - Delete button — uses `disabled` attribute + `opacity-50 cursor-not-allowed` + `title="Cannot delete: category has posts"` tooltip when posts exist; active delete button (red, same teal-adjacent danger style as other admin destructive actions) when empty

### `admin/categories/new.html.erb` + `edit.html.erb`

Both render a shared `_form.html.erb` partial. Single field: Name. Submit label "Create Category" / "Update Category".

### `app/views/layouts/admin.html.erb`

Add a "Categories" nav link after "Users":

```erb
<%= link_to "Categories", admin_categories_path,
      class: "flex items-center px-3 py-2 rounded-lg text-sm font-medium #{
        request.path.start_with?(admin_categories_path) ? 'bg-gray-700 text-white' : 'text-gray-300 hover:bg-gray-700 hover:text-white'
      }" %>
```

---

## Testing

`test/controllers/admin/categories_controller_test.rb`:

- Guest redirected to login
- Creator (logged-in, no role) redirected to root
- Sub-admin redirected to root (admin-only)
- Admin: GET index succeeds
- Admin: GET new succeeds
- Admin: POST create with valid params creates category and redirects
- Admin: POST create with invalid params (blank name) re-renders form
- Admin: POST create with duplicate name re-renders form (uniqueness validation)
- Admin: GET edit succeeds
- Admin: PATCH update with valid params updates and redirects
- Admin: PATCH update with invalid params re-renders form
- Admin: PATCH update with duplicate name re-renders form
- Admin: PATCH move_up swaps positions correctly
- Admin: PATCH move_down swaps positions correctly
- Admin: PATCH move_up on first item is a no-op (redirects without error)
- Admin: PATCH move_down on last item is a no-op (redirects without error)
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
