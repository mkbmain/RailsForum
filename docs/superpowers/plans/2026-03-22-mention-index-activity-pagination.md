# Mention Index + Activity Pagination Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix two performance bugs — a missing functional index for case-insensitive @mention lookup, and an O(n) profile activity pagination that loads excess rows per page.

**Architecture:** Task 1 is a single migration adding a `LOWER(name)` functional index on `users`; no application code changes required. Task 2 replaces the Ruby-merge pagination in `UsersController#show` with a `UNION ALL` SQL query that fetches exactly `per + 1` rows from the DB regardless of page number, then loads associated records in two targeted queries.

**Tech Stack:** Rails 8.1, PostgreSQL, Minitest

---

## File Map

| File | Change |
|------|--------|
| `db/migrate/TIMESTAMP_add_lower_name_index_to_users.rb` | New — functional index on `LOWER(name)` |
| `db/structure.sql` | Auto-updated by migration |
| `app/controllers/users_controller.rb` | Modify `show` + add private `fetch_activity_rows` |
| `test/controllers/users_controller_test.rb` | Add pagination behaviour tests |

---

## Task 1: Functional index on `LOWER(users.name)`

**Files:**
- Create: `db/migrate/TIMESTAMP_add_lower_name_index_to_users.rb`
- Auto-modified: `db/structure.sql`

- [ ] **Step 1: Generate migration**

```bash
bin/rails generate migration AddLowerNameIndexToUsers
```

- [ ] **Step 2: Fill in migration body**

Open the generated file and replace the empty `change` method:

```ruby
def change
  add_index :users, "LOWER(name)", name: "index_users_on_lower_name"
end
```

- [ ] **Step 3: Run migration**

```bash
bin/rails db:migrate
```

- [ ] **Step 4: Verify index appears in structure.sql**

```bash
grep "index_users_on_lower_name" db/structure.sql
```

Expected: one line like `CREATE INDEX index_users_on_lower_name ON public.users USING btree (lower((name)::text));`

- [ ] **Step 5: Run full test suite to confirm nothing broke**

```bash
bin/rails test
```

Expected: all green, same count as before.

- [ ] **Step 6: Commit**

```bash
git add db/migrate/*_add_lower_name_index_to_users.rb db/structure.sql
git commit -m "perf: add functional index on LOWER(users.name) for mention lookup"
```

---

## Task 2: O(1)-per-page profile activity pagination

**Files:**
- Modify: `app/controllers/users_controller.rb` — `show` action (lines 47–64) + new private `fetch_activity_rows`
- Modify: `test/controllers/users_controller_test.rb` — add pagination tests

### How the tests assert behaviour

`UsersController` tests use `ActionDispatch::IntegrationTest`, which does **not** expose `assigns()`. Assert via the rendered HTML instead:

- Activity item count: each item renders a `<span>` badge with text exactly `"Post"` or `"Reply"` — count these spans.
- Pagination link presence: the view renders `<a>Older →</a>` when `@has_more` is true.
- Visibility: removed posts' titles never appear as link text.

The fixture `categories(:other)` (id: 1, name: "Other") is available in all tests without creation.

### Step 1 — Write failing tests first

- [ ] **Step 1: Add pagination tests**

Add these tests to `test/controllers/users_controller_test.rb`, before the final `end`:

```ruby
# ---- Activity pagination tests ----

def create_active_user(email:, name:)
  User.create!(email: email, name: name,
               password: "pass123", password_confirmation: "pass123",
               provider_id: 3)
end

test "GET /users/:id page 1 shows 20 items and has_more link when 22 total" do
  user     = create_active_user(email: "pg1@example.com", name: "Pg1User")
  category = categories(:other)

  # 12 posts + 10 replies = 22 items; page 1 should show 20
  posts = (1..12).map { |i| Post.create!(title: "Post #{i}", body: "body", user: user, category: category, created_at: i.days.ago) }
  (1..10).map { |i| Reply.create!(body: "reply #{i}", user: user, post: posts.first, created_at: (i + 0.5).days.ago) }

  get user_path(user)
  assert_response :success

  post_badges  = css_select("span", text: "Post").size
  reply_badges = css_select("span", text: "Reply").size
  assert_equal 20, post_badges + reply_badges, "expected 20 activity items on page 1"
  assert_select "a", text: "Older →", count: 1
end

test "GET /users/:id page 2 shows remaining 2 items and no has_more link" do
  user     = create_active_user(email: "pg2@example.com", name: "Pg2User")
  category = categories(:other)

  posts = (1..12).map { |i| Post.create!(title: "Post #{i}", body: "body", user: user, category: category, created_at: i.days.ago) }
  (1..10).map { |i| Reply.create!(body: "reply #{i}", user: user, post: posts.first, created_at: (i + 0.5).days.ago) }

  get user_path(user, page: 2)
  assert_response :success

  post_badges  = css_select("span", text: "Post").size
  reply_badges = css_select("span", text: "Reply").size
  assert_equal 2, post_badges + reply_badges, "expected 2 activity items on page 2"
  assert_select "a", text: "Older →", count: 0
end

test "GET /users/:id activity excludes removed posts" do
  user     = create_active_user(email: "vis@example.com", name: "VisUser")
  category = categories(:other)

  Post.create!(title: "VisiblePost", body: "body", user: user, category: category)
  Post.create!(title: "RemovedPost", body: "body", user: user, category: category, removed_at: 1.hour.ago)

  get user_path(user)
  assert_response :success
  assert_select "a", text: "VisiblePost"
  assert_select "a", text: "RemovedPost", count: 0
end
```

- [ ] **Step 2: Run new tests to confirm they fail (or that existing pass)**

```bash
bin/rails test test/controllers/users_controller_test.rb
```

Expected: the three new pagination tests FAIL; all pre-existing tests still pass. (The failure mode: the current implementation loads `per * page + 1` records from each table and may return counts that differ from what we assert.)

### Step 2 — Implement the fix

- [ ] **Step 3: Replace `show` in `users_controller.rb`**

Replace the entire `show` method (lines 46–65) with:

```ruby
def show
  page = [ (params[:page] || 1).to_i, 1 ].max
  per  = 20

  rows      = fetch_activity_rows(@profile_user, page: page, per: per)
  @has_more = rows.size > per
  rows      = rows.first(per)

  post_ids   = rows.select { |r| r["kind"] == "post"  }.map { |r| r["id"].to_i }
  reply_ids  = rows.select { |r| r["kind"] == "reply" }.map { |r| r["id"].to_i }

  posts_by_id   = Post.includes(:category).where(id: post_ids).index_by(&:id)
  replies_by_id = Reply.includes(:post).where(id: reply_ids).index_by(&:id)

  @activity = rows.map do |r|
    if r["kind"] == "post"
      { type: :post,  record: posts_by_id[r["id"].to_i],   created_at: r["created_at"] }
    else
      { type: :reply, record: replies_by_id[r["id"].to_i], created_at: r["created_at"] }
    end
  end

  @post_count  = @profile_user.posts.visible.count
  @reply_count = @profile_user.replies.visible.count
  @page        = page
end
```

- [ ] **Step 4: Add `fetch_activity_rows` private method**

Add this directly after the `require_owner` method, before the final `end` of the class:

```ruby
def fetch_activity_rows(user, page:, per:)
  offset      = (page - 1) * per
  posts_sql   = Post.visible.where(user: user).select("'post' AS kind, id, created_at").to_sql
  replies_sql = Reply.visible.where(user: user).select("'reply' AS kind, id, created_at").to_sql

  # LIMIT and OFFSET are computed Ruby integers (never user-supplied strings) — safe to interpolate.
  # .to_sql embeds the user_id literal from ActiveRecord — no injection vector.
  ActiveRecord::Base.connection.exec_query(<<~SQL)
    (#{posts_sql}) UNION ALL (#{replies_sql})
    ORDER BY created_at DESC
    LIMIT #{per + 1} OFFSET #{offset}
  SQL
end
```

- [ ] **Step 5: Run the new tests**

```bash
bin/rails test test/controllers/users_controller_test.rb
```

Expected: all tests pass, including the three new ones.

- [ ] **Step 6: Run full test suite**

```bash
bin/rails test
```

Expected: all green.

- [ ] **Step 7: Commit**

```bash
git add app/controllers/users_controller.rb test/controllers/users_controller_test.rb
git commit -m "perf: replace O(n) activity pagination with UNION ALL SQL query"
```
