# Content Flagging Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Allow logged-in users to flag posts/replies for moderator review, and give moderators a dedicated admin queue to dismiss flags.

**Architecture:** A `content_types` lookup table (smallint PK, mirrors `categories`/`providers`) plus a `flags` table with a composite unique index enforcing one flag per user per content item. A `FlagsController` handles creation; `Admin::FlagsController` handles the queue and dismiss action. No polymorphic string columns — `content_type_id` is a smallint FK.

**Tech Stack:** Rails 8.1, PostgreSQL, Minitest, Tailwind CSS, standard Rails `form_with` (no Turbo streams for flags).

**Spec:** `docs/superpowers/specs/2026-03-21-content-flagging-design.md`

---

## File Map

| File | Action | Purpose |
|------|--------|---------|
| `db/migrate/TIMESTAMP_create_content_types_and_flags.rb` | Create | Tables + indexes + seed inserts |
| `app/models/content_type.rb` | Create | Lookup model with constants |
| `app/models/flag.rb` | Create | Flag model, enum, validations, `flaggable` method |
| `app/models/post.rb` | Modify | Add `has_many :flags` |
| `app/models/reply.rb` | Modify | Add `has_many :flags` |
| `config/routes.rb` | Modify | Add `resources :flags` under posts/replies + admin namespace |
| `app/controllers/flags_controller.rb` | Create | `create` action (user-facing) |
| `app/controllers/admin/flags_controller.rb` | Create | `index` + `dismiss` actions |
| `app/controllers/admin/dashboard_controller.rb` | Modify | Add `@pending_flags_count` |
| `app/views/posts/show.html.erb` | Modify | Add flag button to post |
| `app/views/replies/_reply.html.erb` | Modify | Add flag button to reply |
| `app/views/admin/flags/index.html.erb` | Create | Pending flags queue |
| `app/views/admin/dashboard/index.html.erb` | Modify | Pending reports stat + link |
| `app/views/layouts/admin.html.erb` | Modify | Add "Reports" nav link |
| `test/fixtures/content_types.yml` | Create | Post (1) and Reply (2) rows |
| `test/fixtures/flags.yml` | — | Not created (no users.yml fixture; all tests use setup blocks) |
| `test/models/flag_test.rb` | Create | Model unit tests |
| `test/controllers/flags_controller_test.rb` | Create | User-facing controller tests |
| `test/controllers/admin/flags_controller_test.rb` | Create | Admin controller tests |

---

## Task 1: Migration — create `content_types` and `flags` tables

**Files:**
- Create: `db/migrate/TIMESTAMP_create_content_types_and_flags.rb`

- [ ] **Step 1: Generate the migration**

```bash
bin/rails generate migration CreateContentTypesAndFlags
```

- [ ] **Step 2: Fill in the migration**

Replace the generated file body with:

```ruby
class CreateContentTypesAndFlags < ActiveRecord::Migration[8.1]
  def up
    create_table :content_types, id: :integer, force: :cascade do |t|
      t.string :name, limit: 50, null: false
    end

    execute <<~SQL
      INSERT INTO content_types (id, name) VALUES (1, 'Post'), (2, 'Reply');
    SQL

    create_table :flags, id: :integer, force: :cascade do |t|
      t.bigint  :user_id,          null: false
      t.integer :content_type_id,  null: false, limit: 2
      t.bigint  :flaggable_id,     null: false
      t.integer :reason,           null: false, limit: 2
      t.datetime :resolved_at
      t.bigint  :resolved_by_id
      t.timestamps
    end

    add_index :flags, [ :user_id, :content_type_id, :flaggable_id ], unique: true,
              name: "index_flags_on_user_content_flaggable"
    add_index :flags, [ :content_type_id, :flaggable_id ],
              name: "index_flags_on_content_type_and_flaggable"
    add_index :flags, :created_at, where: "resolved_at IS NULL",
              name: "index_flags_pending_by_created_at"

    add_foreign_key :flags, :users, column: :user_id
    add_foreign_key :flags, :content_types, column: :content_type_id
    add_foreign_key :flags, :users, column: :resolved_by_id
  end

  def down
    drop_table :flags
    drop_table :content_types
  end
end
```

- [ ] **Step 3: Run the migration**

```bash
bin/rails db:migrate
```

Expected: migration runs without error. Check `db/structure.sql` for `content_types` and `flags` tables.

- [ ] **Step 4: Verify structure**

```bash
grep -A5 "CREATE TABLE public.content_types" db/structure.sql
grep -A5 "CREATE TABLE public.flags" db/structure.sql
```

Expected: both tables present.

- [ ] **Step 5: Commit**

```bash
git add db/migrate/ db/structure.sql
git commit -m "feat: add content_types and flags tables"
```

---

## Task 2: `ContentType` and `Flag` models + fixtures

**Files:**
- Create: `app/models/content_type.rb`
- Create: `app/models/flag.rb`
- Create: `test/fixtures/content_types.yml`
- Create: `test/models/flag_test.rb`

- [ ] **Step 1: Write the failing model tests**

Create `test/models/flag_test.rb`:

```ruby
require "test_helper"

class FlagTest < ActiveSupport::TestCase
  setup do
    Provider.find_or_create_by!(id: 3, name: "internal")
    @user  = User.create!(email: "flagger@example.com", name: "Flagger",
                          password: "pass123", password_confirmation: "pass123",
                          provider_id: 3)
    @post  = Post.create!(user: @user, title: "Post", body: "Body")
    @reply = Reply.create!(post: @post, user: @user, body: "Reply body")
  end

  test "valid flag on a post" do
    f = Flag.new(user: @user, content_type_id: ContentType::CONTENT_POST,
                 flaggable_id: @post.id, reason: :spam)
    assert f.valid?, f.errors.full_messages.inspect
  end

  test "valid flag on a reply" do
    f = Flag.new(user: @user, content_type_id: ContentType::CONTENT_REPLY,
                 flaggable_id: @reply.id, reason: :harassment)
    assert f.valid?, f.errors.full_messages.inspect
  end

  test "invalid without content_type_id" do
    f = Flag.new(user: @user, flaggable_id: @post.id, reason: :spam)
    assert_not f.valid?
    assert f.errors[:content_type_id].any?
  end

  test "invalid with unknown content_type_id" do
    f = Flag.new(user: @user, content_type_id: 99,
                 flaggable_id: @post.id, reason: :spam)
    assert_not f.valid?
    assert f.errors[:content_type_id].any?
  end

  test "invalid without flaggable_id" do
    f = Flag.new(user: @user, content_type_id: ContentType::CONTENT_POST, reason: :spam)
    assert_not f.valid?
    assert f.errors[:flaggable_id].any?
  end

  test "one flag per user per content item regardless of reason" do
    Flag.create!(user: @user, content_type_id: ContentType::CONTENT_POST,
                 flaggable_id: @post.id, reason: :spam)
    dup = Flag.new(user: @user, content_type_id: ContentType::CONTENT_POST,
                   flaggable_id: @post.id, reason: :harassment)
    assert_not dup.valid?
    assert_includes dup.errors[:user_id], "has already flagged this content"
  end

  test "same user can flag a post and a reply independently" do
    Flag.create!(user: @user, content_type_id: ContentType::CONTENT_POST,
                 flaggable_id: @post.id, reason: :spam)
    f = Flag.new(user: @user, content_type_id: ContentType::CONTENT_REPLY,
                 flaggable_id: @reply.id, reason: :spam)
    assert f.valid?
  end

  test "reason enum has all four values" do
    assert_equal({ "spam" => 0, "harassment" => 1, "misinformation" => 2, "other" => 3 },
                 Flag.reasons)
  end

  test "flaggable returns the Post for a post flag" do
    f = Flag.create!(user: @user, content_type_id: ContentType::CONTENT_POST,
                     flaggable_id: @post.id, reason: :spam)
    assert_equal @post, f.flaggable
  end

  test "flaggable returns the Reply for a reply flag" do
    f = Flag.create!(user: @user, content_type_id: ContentType::CONTENT_REPLY,
                     flaggable_id: @reply.id, reason: :spam)
    assert_equal @reply, f.flaggable
  end

  test "flaggable returns nil when content has been hard-deleted" do
    f = Flag.create!(user: @user, content_type_id: ContentType::CONTENT_POST,
                     flaggable_id: @post.id, reason: :spam)
    @post.delete  # bypass callbacks, remove the row directly
    assert_nil f.reload.flaggable
  end

  test "flaggable returns the soft-deleted record when content has been soft-deleted" do
    f = Flag.create!(user: @user, content_type_id: ContentType::CONTENT_POST,
                     flaggable_id: @post.id, reason: :spam)
    @post.update_column(:removed_at, Time.current)
    assert_equal @post, f.reload.flaggable
  end

  test "pending scope returns unresolved flags" do
    f1 = Flag.create!(user: @user, content_type_id: ContentType::CONTENT_POST,
                      flaggable_id: @post.id, reason: :spam)
    other = User.create!(email: "other@example.com", name: "Other",
                         password: "pass123", password_confirmation: "pass123",
                         provider_id: 3)
    f2 = Flag.create!(user: other, content_type_id: ContentType::CONTENT_POST,
                      flaggable_id: @post.id, reason: :harassment,
                      resolved_at: Time.current, resolved_by: other)
    assert_includes Flag.pending, f1
    assert_not_includes Flag.pending, f2
  end

  test "resolved scope returns resolved flags" do
    resolver = User.create!(email: "r@example.com", name: "R",
                             password: "pass123", password_confirmation: "pass123",
                             provider_id: 3)
    f = Flag.create!(user: @user, content_type_id: ContentType::CONTENT_POST,
                     flaggable_id: @post.id, reason: :spam,
                     resolved_at: Time.current, resolved_by: resolver)
    assert_includes Flag.resolved, f
    assert_not_includes Flag.pending, f
  end
end
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
bin/rails test test/models/flag_test.rb 2>&1 | head -20
```

Expected: error about uninitialized constant `ContentType` or `Flag`.

- [ ] **Step 3: Create `app/models/content_type.rb`**

```ruby
class ContentType < ApplicationRecord
  self.primary_key = :id

  CONTENT_POST  = 1
  CONTENT_REPLY = 2
end
```

- [ ] **Step 4: Create `app/models/flag.rb`**

```ruby
class Flag < ApplicationRecord
  belongs_to :user
  belongs_to :content_type
  belongs_to :resolved_by, class_name: "User", optional: true

  enum :reason, { spam: 0, harassment: 1, misinformation: 2, other: 3 }

  scope :pending,  -> { where(resolved_at: nil) }
  scope :resolved, -> { where.not(resolved_at: nil) }

  validates :flaggable_id,    presence: true
  validates :reason,          presence: true
  validates :content_type_id, presence: true,
                              inclusion: { in: [ ContentType::CONTENT_POST, ContentType::CONTENT_REPLY ] }
  validates :user_id, uniqueness: { scope: [ :content_type_id, :flaggable_id ],
                                    message: "has already flagged this content" }

  # Resolves the flagged record. Returns nil if hard-deleted; returns record (possibly
  # soft-deleted) if it still exists.
  def flaggable
    case content_type_id
    when ContentType::CONTENT_POST  then Post.find_by(id: flaggable_id)
    when ContentType::CONTENT_REPLY then Reply.find_by(id: flaggable_id)
    end
  end
end
```

- [ ] **Step 5: Create `test/fixtures/content_types.yml`**

```yaml
post_type:
  id: 1
  name: Post

reply_type:
  id: 2
  name: Reply
```

- [ ] **Step 6: Run model tests**

```bash
bin/rails test test/models/flag_test.rb
```

Expected: all pass.

- [ ] **Step 7: Run full suite to check nothing broken**

```bash
bin/rails test
```

Expected: all existing tests still pass.

- [ ] **Step 8: Commit**

```bash
git add app/models/content_type.rb app/models/flag.rb \
        test/models/flag_test.rb \
        test/fixtures/content_types.yml
git commit -m "feat: ContentType and Flag models with tests"
```

---

## Task 3: Add `has_many :flags` to `Post`, `Reply`, and `User`

**Files:**
- Modify: `app/models/post.rb`
- Modify: `app/models/reply.rb`
- Modify: `app/models/user.rb`

- [ ] **Step 1: Add to `Post`**

In `app/models/post.rb`, add after the existing `has_many :reactions` line:

```ruby
has_many :flags, -> { where(content_type_id: ContentType::CONTENT_POST) },
         class_name: "Flag", foreign_key: :flaggable_id, dependent: :destroy
```

- [ ] **Step 2: Add to `Reply`**

In `app/models/reply.rb`, add after the existing `has_many :reactions` line:

```ruby
has_many :flags, -> { where(content_type_id: ContentType::CONTENT_REPLY) },
         class_name: "Flag", foreign_key: :flaggable_id, dependent: :destroy
```

- [ ] **Step 3: Add to `User`**

In `app/models/user.rb`, add after the existing `has_many :reactions` line:

```ruby
has_many :flags, dependent: :destroy
```

This allows `current_user.flags.exists?(...)` in the views.

- [ ] **Step 4: Run full suite**

```bash
bin/rails test
```

Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add app/models/post.rb app/models/reply.rb app/models/user.rb
git commit -m "feat: add has_many :flags to Post, Reply, and User"
```

---

## Task 4: Routes

**Files:**
- Modify: `config/routes.rb`

- [ ] **Step 1: Add user-facing flag routes**

Inside `resources :posts do`, add `resources :flags, only: [:create]` directly, and also inside `resources :replies do`:

```ruby
resources :posts do
  resources :flags,   only: [ :create ]
  resources :reactions, only: [ :create, :destroy ]
  resources :replies,   only: [ :create, :destroy, :edit, :update ] do
    resources :reactions, only: [ :create, :destroy ]
    resources :flags,     only: [ :create ]
  end
end
```

- [ ] **Step 2: Add admin flag routes**

Inside `namespace :admin do`, add:

```ruby
resources :flags, only: [ :index ] do
  member { patch :dismiss }
end
```

- [ ] **Step 3: Verify routes**

```bash
bin/rails routes | grep flag
```

Expected output includes:
```
post_flags       POST   /posts/:post_id/flags(.:format)
post_reply_flags POST   /posts/:post_id/replies/:reply_id/flags(.:format)
admin_flags      GET    /admin/flags(.:format)
dismiss_admin_flag PATCH /admin/flags/:id/dismiss(.:format)
```

- [ ] **Step 4: Run full suite**

```bash
bin/rails test
```

Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add config/routes.rb
git commit -m "feat: add flag routes for users and admin"
```

---

## Task 5: `FlagsController` (user-facing)

**Files:**
- Create: `app/controllers/flags_controller.rb`
- Create: `test/controllers/flags_controller_test.rb`

- [ ] **Step 1: Write the failing controller tests**

Create `test/controllers/flags_controller_test.rb`:

```ruby
require "test_helper"

class FlagsControllerTest < ActionDispatch::IntegrationTest
  setup do
    Provider.find_or_create_by!(id: 3, name: "internal")
    @user  = User.create!(email: "u@example.com", name: "User",
                          password: "pass123", password_confirmation: "pass123",
                          provider_id: 3)
    @other = User.create!(email: "other@example.com", name: "Other",
                          password: "pass123", password_confirmation: "pass123",
                          provider_id: 3)
    @post  = Post.create!(user: @other, title: "Post", body: "Body")
    @reply = Reply.create!(post: @post, user: @other, body: "Reply")
  end

  # --- Auth ---

  test "requires login to flag a post" do
    assert_no_difference "Flag.count" do
      post post_flags_path(@post), params: { flag: { reason: "spam" } }
    end
    assert_redirected_to login_path
  end

  test "requires login to flag a reply" do
    assert_no_difference "Flag.count" do
      post post_reply_flags_path(@post, @reply), params: { flag: { reason: "spam" } }
    end
    assert_redirected_to login_path
  end

  # --- Create on post ---

  test "creates a flag on a post" do
    post login_path, params: { email: "u@example.com", password: "pass123" }
    assert_difference "Flag.count", 1 do
      post post_flags_path(@post), params: { flag: { reason: "spam" } }
    end
    f = Flag.last
    assert_equal @user,                    f.user
    assert_equal ContentType::CONTENT_POST, f.content_type_id
    assert_equal @post.id,                 f.flaggable_id
    assert_equal "spam",                   f.reason
    assert_redirected_to post_path(@post)
    assert_equal "Content reported.", flash[:notice]
  end

  test "duplicate flag on a post redirects with alert" do
    Flag.create!(user: @user, content_type_id: ContentType::CONTENT_POST,
                 flaggable_id: @post.id, reason: :spam)
    post login_path, params: { email: "u@example.com", password: "pass123" }
    assert_no_difference "Flag.count" do
      post post_flags_path(@post), params: { flag: { reason: "other" } }
    end
    assert_includes flash[:alert], "already flagged"
  end

  test "cannot flag a soft-deleted post" do
    @post.update_column(:removed_at, Time.current)
    post login_path, params: { email: "u@example.com", password: "pass123" }
    assert_no_difference "Flag.count" do
      post post_flags_path(@post), params: { flag: { reason: "spam" } }
    end
    assert_includes flash[:alert], "Content not found"
  end

  # --- Create on reply ---

  test "creates a flag on a reply" do
    post login_path, params: { email: "u@example.com", password: "pass123" }
    assert_difference "Flag.count", 1 do
      post post_reply_flags_path(@post, @reply), params: { flag: { reason: "harassment" } }
    end
    f = Flag.last
    assert_equal @user,                     f.user
    assert_equal ContentType::CONTENT_REPLY, f.content_type_id
    assert_equal @reply.id,                 f.flaggable_id
    assert_equal "harassment",              f.reason
  end

  test "reply flag is scoped to parent post — wrong post redirects with alert" do
    other_post = Post.create!(user: @other, title: "Other", body: "Body")
    post login_path, params: { email: "u@example.com", password: "pass123" }
    assert_no_difference "Flag.count" do
      post post_reply_flags_path(other_post, @reply), params: { flag: { reason: "spam" } }
    end
    assert_includes flash[:alert], "Content not found"
  end

  test "cannot flag a soft-deleted reply" do
    @reply.update_column(:removed_at, Time.current)
    post login_path, params: { email: "u@example.com", password: "pass123" }
    assert_no_difference "Flag.count" do
      post post_reply_flags_path(@post, @reply), params: { flag: { reason: "spam" } }
    end
    assert_includes flash[:alert], "Content not found"
  end

  # --- User can flag their own content ---

  test "user can flag their own post" do
    own_post = Post.create!(user: @user, title: "Mine", body: "Body")
    post login_path, params: { email: "u@example.com", password: "pass123" }
    assert_difference "Flag.count", 1 do
      post post_flags_path(own_post), params: { flag: { reason: "spam" } }
    end
  end
end
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
bin/rails test test/controllers/flags_controller_test.rb 2>&1 | head -10
```

Expected: routing error or uninitialized constant `FlagsController`.

- [ ] **Step 3: Create `app/controllers/flags_controller.rb`**

```ruby
class FlagsController < ApplicationController
  before_action :require_login

  def create
    if params[:reply_id]
      @post    = Post.visible.find(params[:post_id])
      flaggable = @post.replies.visible.find_by(id: params[:reply_id])
      content_type_id = ContentType::CONTENT_REPLY
      flaggable_id    = params[:reply_id].to_i
    else
      flaggable = Post.visible.find_by(id: params[:post_id])
      content_type_id = ContentType::CONTENT_POST
      flaggable_id    = params[:post_id].to_i
    end

    if flaggable.nil?
      redirect_back(fallback_location: posts_path, allow_other_host: false,
                    alert: "Content not found.") and return
    end

    flag = Flag.new(
      user:            current_user,
      content_type_id: content_type_id,
      flaggable_id:    flaggable_id,
      reason:          flag_params[:reason]
    )

    if flag.save
      redirect_back(fallback_location: post_path(params[:post_id]), allow_other_host: false,
                    notice: "Content reported.")
    else
      redirect_back(fallback_location: post_path(params[:post_id]), allow_other_host: false,
                    alert: flag.errors.full_messages.to_sentence)
    end
  end

  private

  def flag_params
    params.require(:flag).permit(:reason)
  end
end
```

- [ ] **Step 4: Run the controller tests**

```bash
bin/rails test test/controllers/flags_controller_test.rb
```

Expected: all pass.

- [ ] **Step 5: Run full suite**

```bash
bin/rails test
```

Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add app/controllers/flags_controller.rb test/controllers/flags_controller_test.rb
git commit -m "feat: FlagsController with tests"
```

---

## Task 6: Flag button on post show page

**Files:**
- Modify: `app/views/posts/show.html.erb`

The flag button sits alongside the edit link in the post header. It is hidden on removed posts and when the user has already flagged.

- [ ] **Step 1: Add the flag button**

In `app/views/posts/show.html.erb`, find the block that shows the Edit link:

```erb
      <% if logged_in? && current_user == @post.user && Time.current - @post.created_at <= EDIT_WINDOW_SECONDS %>
        <%= link_to "Edit", edit_post_path(@post), class: "text-xs text-blue-500 hover:underline ml-auto" %>
      <% end %>
```

Replace it with (adds the flag UI after the edit link):

```erb
      <% if logged_in? && current_user == @post.user && Time.current - @post.created_at <= EDIT_WINDOW_SECONDS %>
        <%= link_to "Edit", edit_post_path(@post), class: "text-xs text-blue-500 hover:underline ml-auto" %>
      <% end %>
      <% if logged_in? && !@post.removed? %>
        <% already_flagged = current_user.flags.exists?(content_type_id: ContentType::CONTENT_POST, flaggable_id: @post.id) %>
        <% if already_flagged %>
          <span class="text-xs text-gray-400 ml-auto">Flagged ✓</span>
        <% else %>
          <details class="relative ml-auto">
            <summary class="text-xs text-gray-400 hover:text-red-500 cursor-pointer list-none">Flag</summary>
            <div class="absolute right-0 top-5 z-10 bg-white border border-gray-200 rounded-lg shadow-lg p-3 w-48">
              <%= form_with url: post_flags_path(@post), method: :post do |f| %>
                <p class="text-xs font-medium text-gray-700 mb-2">Report reason</p>
                <% Flag.reasons.each_key do |reason| %>
                  <label class="flex items-center gap-2 text-xs text-gray-600 mb-1 cursor-pointer">
                    <%= f.radio_button :reason, reason, class: "accent-red-500" %>
                    <%= reason.humanize %>
                  </label>
                <% end %>
                <%= f.submit "Submit", class: "mt-2 w-full bg-red-500 text-white text-xs py-1 rounded hover:bg-red-600 cursor-pointer" %>
              <% end %>
            </div>
          </details>
        <% end %>
      <% end %>
```

- [ ] **Step 2: Start the dev server and manually verify**

```bash
bin/dev
```

Navigate to any post while logged in. Confirm:
- "Flag" dropdown appears on live posts
- Dropdown shows 4 radio buttons + Submit
- After flagging, "Flagged ✓" appears on reload
- No flag button on removed posts

- [ ] **Step 3: Run full suite**

```bash
bin/rails test
```

Expected: all pass.

- [ ] **Step 4: Commit**

```bash
git add app/views/posts/show.html.erb
git commit -m "feat: flag button on post show page"
```

---

## Task 7: Flag button on reply partial

**Files:**
- Modify: `app/views/replies/_reply.html.erb`

- [ ] **Step 1: Add the flag button to the reply partial**

In `app/views/replies/_reply.html.erb`, find the bottom action bar:

```erb
  <div class="flex items-center justify-between mt-2">
    <span></span>
    <div class="flex gap-3">
```

Add the flag button inside the `<div class="flex gap-3">` block, after the existing Remove/Ban buttons:

```erb
      <% if logged_in? && !reply.removed? %>
        <% already_flagged = current_user.flags.exists?(content_type_id: ContentType::CONTENT_REPLY, flaggable_id: reply.id) %>
        <% if already_flagged %>
          <span class="text-xs text-gray-400">Flagged ✓</span>
        <% else %>
          <details class="relative">
            <summary class="text-xs text-gray-400 hover:text-red-500 cursor-pointer list-none">Flag</summary>
            <div class="absolute right-0 bottom-5 z-10 bg-white border border-gray-200 rounded-lg shadow-lg p-3 w-48">
              <%= form_with url: post_reply_flags_path(post, reply), method: :post do |f| %>
                <p class="text-xs font-medium text-gray-700 mb-2">Report reason</p>
                <% Flag.reasons.each_key do |reason| %>
                  <label class="flex items-center gap-2 text-xs text-gray-600 mb-1 cursor-pointer">
                    <%= f.radio_button :reason, reason, class: "accent-red-500" %>
                    <%= reason.humanize %>
                  </label>
                <% end %>
                <%= f.submit "Submit", class: "mt-2 w-full bg-red-500 text-white text-xs py-1 rounded hover:bg-red-600 cursor-pointer" %>
              <% end %>
            </div>
          </details>
        <% end %>
      <% end %>
```

- [ ] **Step 2: Run full suite**

```bash
bin/rails test
```

Expected: all pass.

- [ ] **Step 3: Commit**

```bash
git add app/views/replies/_reply.html.erb
git commit -m "feat: flag button on reply partial"
```

---

## Task 8: `Admin::FlagsController`

**Files:**
- Create: `app/controllers/admin/flags_controller.rb`
- Create: `test/controllers/admin/flags_controller_test.rb`

- [ ] **Step 1: Write the failing admin controller tests**

Create `test/controllers/admin/flags_controller_test.rb`:

```ruby
require "test_helper"

class Admin::FlagsControllerTest < ActionDispatch::IntegrationTest
  setup do
    Provider.find_or_create_by!(id: 3, name: "internal")
    @user = User.create!(email: "u@example.com", name: "User",
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
    @post  = Post.create!(user: @user, title: "Post", body: "Body")
    @flag  = Flag.create!(user: @user, content_type_id: ContentType::CONTENT_POST,
                          flaggable_id: @post.id, reason: :spam)
  end

  # --- index auth ---

  test "index is accessible to sub_admin" do
    post login_path, params: { email: "sub@example.com", password: "pass123" }
    get admin_flags_path
    assert_response :success
  end

  test "index is accessible to admin" do
    post login_path, params: { email: "admin@example.com", password: "pass123" }
    get admin_flags_path
    assert_response :success
  end

  test "index redirects regular users" do
    post login_path, params: { email: "u@example.com", password: "pass123" }
    get admin_flags_path
    assert_redirected_to root_path
  end

  test "index redirects guests" do
    get admin_flags_path
    assert_redirected_to login_path
  end

  # --- dismiss ---

  test "dismiss sets resolved_at and resolved_by_id" do
    post login_path, params: { email: "sub@example.com", password: "pass123" }
    patch dismiss_admin_flag_path(@flag)
    @flag.reload
    assert_not_nil @flag.resolved_at
    assert_equal @sub_admin.id, @flag.resolved_by_id
    assert_redirected_to admin_flags_path
    assert_equal "Flag dismissed.", flash[:notice]
  end

  test "dismiss on already-resolved flag returns Already resolved notice" do
    @flag.update!(resolved_at: Time.current, resolved_by: @admin)
    post login_path, params: { email: "sub@example.com", password: "pass123" }
    patch dismiss_admin_flag_path(@flag)
    assert_redirected_to admin_flags_path
    assert_equal "Already resolved.", flash[:notice]
  end

  test "dismiss on missing flag returns Already resolved notice" do
    post login_path, params: { email: "sub@example.com", password: "pass123" }
    patch dismiss_admin_flag_path(id: 99999)
    assert_redirected_to admin_flags_path
    assert_equal "Already resolved.", flash[:notice]
  end

  test "dismiss is rejected for regular users" do
    post login_path, params: { email: "u@example.com", password: "pass123" }
    patch dismiss_admin_flag_path(@flag)
    assert_redirected_to root_path
    @flag.reload
    assert_nil @flag.resolved_at
  end
end
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
bin/rails test test/controllers/admin/flags_controller_test.rb 2>&1 | head -10
```

Expected: routing/constant error.

- [ ] **Step 3: Create `app/controllers/admin/flags_controller.rb`**

```ruby
class Admin::FlagsController < Admin::BaseController
  PER_PAGE = 20

  def index
    page  = [ (params[:page] || 1).to_i, 1 ].max
    flags = Flag.pending
                .includes(:user, :content_type)
                .order(created_at: :asc)
                .limit(PER_PAGE + 1).offset((page - 1) * PER_PAGE)
                .to_a

    @has_more = flags.size > PER_PAGE
    @flags    = flags.first(PER_PAGE)
    @page     = page

    post_flaggable_ids  = @flags.select { |f| f.content_type_id == ContentType::CONTENT_POST  }.map(&:flaggable_id)
    reply_flaggable_ids = @flags.select { |f| f.content_type_id == ContentType::CONTENT_REPLY }.map(&:flaggable_id)

    @flaggables = {}
    Post.where(id: post_flaggable_ids).each do |r|
      @flaggables[[ ContentType::CONTENT_POST, r.id ]] = r
    end
    Reply.where(id: reply_flaggable_ids).includes(:post).each do |r|
      @flaggables[[ ContentType::CONTENT_REPLY, r.id ]] = r
    end
  end

  def dismiss
    flag = Flag.find_by(id: params[:id])
    if flag.nil? || flag.resolved_at.present?
      redirect_to admin_flags_path, notice: "Already resolved." and return
    end
    flag.update!(resolved_at: Time.current, resolved_by: current_user)
    redirect_to admin_flags_path, notice: "Flag dismissed."
  end
end
```

- [ ] **Step 4: Run the admin controller tests**

```bash
bin/rails test test/controllers/admin/flags_controller_test.rb
```

Expected: all pass.

- [ ] **Step 5: Run full suite**

```bash
bin/rails test
```

Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add app/controllers/admin/flags_controller.rb \
        test/controllers/admin/flags_controller_test.rb
git commit -m "feat: Admin::FlagsController with tests"
```

---

## Task 9: Admin flags queue view

**Files:**
- Create: `app/views/admin/flags/index.html.erb`

- [ ] **Step 1: Create the view**

Create `app/views/admin/flags/index.html.erb`:

```erb
<%# app/views/admin/flags/index.html.erb %>
<% content_for :title, "Pending Reports – Admin Panel" %>

<h1 class="text-2xl font-bold text-gray-900 mb-6">Pending Reports</h1>

<% if @flags.empty? %>
  <div class="bg-white rounded-xl shadow-sm border border-stone-200 p-8 text-center">
    <p class="text-sm text-gray-500">No pending reports.</p>
  </div>
<% else %>
  <div class="bg-white rounded-xl shadow-sm border border-stone-200 overflow-hidden">
    <table class="w-full text-sm">
      <thead class="bg-stone-50 border-b border-stone-200">
        <tr>
          <th class="text-left px-4 py-3 font-medium text-gray-600">Type</th>
          <th class="text-left px-4 py-3 font-medium text-gray-600">Content</th>
          <th class="text-left px-4 py-3 font-medium text-gray-600">Reporter</th>
          <th class="text-left px-4 py-3 font-medium text-gray-600">Reason</th>
          <th class="text-left px-4 py-3 font-medium text-gray-600">Reported</th>
          <th class="text-left px-4 py-3 font-medium text-gray-600">Link</th>
          <th class="px-4 py-3"></th>
        </tr>
      </thead>
      <tbody class="divide-y divide-stone-100">
        <% @flags.each do |flag| %>
          <% flaggable = @flaggables[[ flag.content_type_id, flag.flaggable_id ]] %>
          <tr>
            <td class="px-4 py-3">
              <% if flag.content_type_id == ContentType::CONTENT_POST %>
                <span class="inline-flex px-2 py-0.5 rounded text-xs font-semibold bg-blue-100 text-blue-800">Post</span>
              <% else %>
                <span class="inline-flex px-2 py-0.5 rounded text-xs font-semibold bg-purple-100 text-purple-800">Reply</span>
              <% end %>
            </td>
            <td class="px-4 py-3 max-w-xs">
              <% if flaggable.nil? %>
                <span class="text-gray-400 italic">[content removed]</span>
              <% elsif flaggable.removed? %>
                <span class="text-gray-400 italic truncate block"><%= truncate(flaggable.body, length: 80) %></span>
                <span class="inline-flex px-1 py-0.5 rounded text-xs bg-red-100 text-red-700 mt-0.5">[removed]</span>
              <% else %>
                <span class="text-gray-700 truncate block"><%= truncate(flaggable.is_a?(Post) ? flaggable.title : flaggable.body, length: 80) %></span>
              <% end %>
            </td>
            <td class="px-4 py-3 text-gray-700"><%= flag.user.name %></td>
            <td class="px-4 py-3 text-gray-700"><%= flag.reason.humanize %></td>
            <td class="px-4 py-3 text-gray-400 text-xs"><%= time_ago_in_words(flag.created_at) %> ago</td>
            <td class="px-4 py-3">
              <% if flaggable %>
                <% target_post = flaggable.is_a?(Post) ? flaggable : flaggable.post %>
                <% anchor = flaggable.is_a?(Reply) ? "reply-#{flaggable.id}" : nil %>
                <%= link_to "View", post_path(target_post, anchor: anchor),
                      class: "text-teal-700 hover:underline text-xs" %>
              <% end %>
            </td>
            <td class="px-4 py-3 text-right">
              <%= button_to "Dismiss", dismiss_admin_flag_path(flag), method: :patch,
                    class: "text-xs text-red-600 hover:underline bg-transparent border-0 p-0 cursor-pointer",
                    data: { confirm: "Dismiss this flag?" } %>
            </td>
          </tr>
        <% end %>
      </tbody>
    </table>
  </div>

  <div class="flex justify-between mt-4">
    <% if @page > 1 %>
      <%= link_to "← Previous", admin_flags_path(page: @page - 1),
            class: "text-teal-700 hover:underline font-medium text-sm" %>
    <% else %>
      <span></span>
    <% end %>
    <% if @has_more %>
      <%= link_to "Next →", admin_flags_path(page: @page + 1),
            class: "text-teal-700 hover:underline font-medium text-sm" %>
    <% end %>
  </div>
<% end %>
```

- [ ] **Step 2: Run full suite**

```bash
bin/rails test
```

Expected: all pass.

- [ ] **Step 3: Manually verify in browser**

Start `bin/dev`, log in as a moderator, visit `/admin/flags`. Confirm the queue renders, flag snippets display, Dismiss button works.

- [ ] **Step 4: Commit**

```bash
git add app/views/admin/flags/index.html.erb
git commit -m "feat: admin flags queue view"
```

---

## Task 10: Admin dashboard — pending count + link, and nav link

**Files:**
- Modify: `app/controllers/admin/dashboard_controller.rb`
- Modify: `app/views/admin/dashboard/index.html.erb`
- Modify: `app/views/layouts/admin.html.erb`

- [ ] **Step 1: Add `@pending_flags_count` to dashboard controller**

In `app/controllers/admin/dashboard_controller.rb`, add to the `index` action (after `@banned_users`):

```ruby
@pending_flags_count = Flag.pending.count
```

- [ ] **Step 2: Add pending reports stat to dashboard view**

In `app/views/admin/dashboard/index.html.erb`, add a fifth stat card in the grid after the "Currently Banned" card:

```erb
  <div class="bg-white rounded-xl shadow-sm border border-stone-200 p-5">
    <div class="text-sm text-gray-500 font-medium">Pending Reports</div>
    <div class="text-3xl font-bold text-orange-600 mt-1"><%= @pending_flags_count %></div>
    <% if @pending_flags_count > 0 %>
      <%= link_to "Review →", admin_flags_path, class: "text-xs text-teal-700 hover:underline mt-1 inline-block" %>
    <% end %>
  </div>
```

Also update the grid class from `grid-cols-2 lg:grid-cols-4` to `grid-cols-2 lg:grid-cols-5` to fit the fifth card:

```erb
<div class="grid grid-cols-2 lg:grid-cols-5 gap-4 mb-8">
```

- [ ] **Step 3: Add "Reports" link to admin sidebar nav**

In `app/views/layouts/admin.html.erb`, add after the "Users" link:

```erb
        <%= link_to "Reports", admin_flags_path,
              class: "flex items-center px-3 py-2 rounded-lg text-sm font-medium #{
                request.path.start_with?(admin_flags_path) ? 'bg-gray-700 text-white' : 'text-gray-300 hover:bg-gray-700 hover:text-white'
              }" %>
```

- [ ] **Step 4: Run full suite**

```bash
bin/rails test
```

Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add app/controllers/admin/dashboard_controller.rb \
        app/views/admin/dashboard/index.html.erb \
        app/views/layouts/admin.html.erb
git commit -m "feat: pending reports count on admin dashboard and nav link"
```

---

## Task 11: Run CI and final check

- [ ] **Step 1: Run full CI pipeline**

```bash
bin/ci
```

Expected: lint, security, and all tests pass.

- [ ] **Step 2: Fix any Rubocop offences**

```bash
./bin/rubocop -a
git add -A && git commit -m "style: rubocop autocorrect for content flagging"
```

Only run this if `bin/ci` reported lint failures.
