# Edit Posts & Replies Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Allow users to edit their own posts and replies within a configurable time window (default 1 hour), with a "last edited at" timestamp shown in the UI when a post or reply has been modified.

**Architecture:** Add a `last_edited_at` datetime column to both `posts` and `replies` (NOT NULL, DB default of `NOW()`). Expose `edit`/`update` actions on both controllers gated by ownership and an edit-window check. Update `posts/show` to render edit links and "last edited at" timestamps. Post ordering is untouched.

**Tech Stack:** Ruby on Rails, PostgreSQL, Minitest, ERB/Tailwind CSS

---

## File Structure

**New files:**
- `config/initializers/forum_settings.rb` — `EDIT_WINDOW_SECONDS` constant
- `db/migrate/*_add_last_edited_at_to_posts.rb` — migration for posts
- `db/migrate/*_add_last_edited_at_to_replies.rb` — migration for replies
- `app/views/posts/edit.html.erb` — edit form for posts
- `app/views/replies/edit.html.erb` — edit form for replies

**Modified files:**
- `app/models/post.rb` — add `edited?` helper
- `app/models/reply.rb` — add `edited?` helper
- `config/routes.rb` — add `edit`/`update` to replies resource
- `app/controllers/posts_controller.rb` — add `edit`/`update`, `set_post`, `check_ownership`, `check_edit_window`
- `app/controllers/replies_controller.rb` — add `edit`/`update`, `set_reply`, `check_ownership`, `check_edit_window`
- `app/views/posts/show.html.erb` — edit links + "last edited at" display

**Test files:**
- `test/models/post_test.rb` — `edited?` tests
- `test/models/reply_test.rb` — `edited?` tests
- `test/controllers/posts_controller_test.rb` — edit/update action tests + view tests
- `test/controllers/replies_controller_test.rb` — edit/update action tests + view tests

---

## Chunk 1: Foundation — Config, Migrations, Models

### Task 1: Create the forum settings initializer

**Files:**
- Create: `config/initializers/forum_settings.rb`

- [ ] **Step 1: Create the initializer**

```ruby
# config/initializers/forum_settings.rb
EDIT_WINDOW_SECONDS = ENV.fetch("EDIT_WINDOW_SECONDS", 3600).to_i
```

- [ ] **Step 2: Commit**

```bash
git add config/initializers/forum_settings.rb
git commit -m "config: add EDIT_WINDOW_SECONDS initializer (default 1 hour)"
```

---

### Task 2: Migrate — add `last_edited_at` to posts

**Files:**
- Create: `db/migrate/*_add_last_edited_at_to_posts.rb`

- [ ] **Step 1: Generate the migration**

```bash
rails generate migration AddLastEditedAtToPosts
```

This creates `db/migrate/YYYYMMDDHHMMSS_add_last_edited_at_to_posts.rb`. Open that file and replace its contents with:

```ruby
class AddLastEditedAtToPosts < ActiveRecord::Migration[8.0]
  def up
    # Add nullable first so existing rows don't violate NOT NULL
    add_column :posts, :last_edited_at, :datetime, default: -> { "NOW()" }
    # Backfill: set existing rows to their created_at
    execute "UPDATE posts SET last_edited_at = created_at"
    # Now enforce NOT NULL (brief table lock — acceptable for this small app)
    change_column_null :posts, :last_edited_at, false
  end

  def down
    remove_column :posts, :last_edited_at
  end
end
```

- [ ] **Step 2: Run the migration**

```bash
rails db:migrate
```

Expected: migration runs without error. `db/structure.sql` updated with `last_edited_at` column on `posts`.

- [ ] **Step 3: Prepare test database**

```bash
rails db:test:prepare
```

---

### Task 3: Migrate — add `last_edited_at` to replies

**Files:**
- Create: `db/migrate/*_add_last_edited_at_to_replies.rb`

- [ ] **Step 1: Generate the migration**

```bash
rails generate migration AddLastEditedAtToReplies
```

Open the generated file and replace its contents with:

```ruby
class AddLastEditedAtToReplies < ActiveRecord::Migration[8.0]
  def up
    add_column :replies, :last_edited_at, :datetime, default: -> { "NOW()" }
    execute "UPDATE replies SET last_edited_at = created_at"
    change_column_null :replies, :last_edited_at, false
  end

  def down
    remove_column :replies, :last_edited_at
  end
end
```

- [ ] **Step 2: Run the migration**

```bash
rails db:migrate
```

Expected: migration runs without error.

- [ ] **Step 3: Prepare the test database**

```bash
rails db:test:prepare
```

- [ ] **Step 4: Commit**

```bash
git add db/migrate/ db/structure.sql
git commit -m "db: add last_edited_at to posts and replies (NOT NULL, defaults to NOW())"
```

---

### Task 4: Add `edited?` to Post and Reply models (TDD)

**Files:**
- Modify: `test/models/post_test.rb`
- Modify: `test/models/reply_test.rb`
- Modify: `app/models/post.rb`
- Modify: `app/models/reply.rb`

**Note on `edited?` reliability:** PostgreSQL evaluates the `NOW()` DB default and Rails' `created_at` within the same INSERT statement — both are set to the same transaction timestamp, so they will be exactly equal on new records. No application-level callback is needed.

- [ ] **Step 1: Write failing tests for Post#edited?**

Add to the bottom of `test/models/post_test.rb` (inside the class, before the final `end`):

```ruby
  test "edited? returns false for a new post" do
    post = Post.create!(user: @user, title: "Fresh", body: "body")
    assert_not post.reload.edited?
  end

  test "edited? returns true after last_edited_at is updated" do
    post = Post.create!(user: @user, title: "Fresh", body: "body")
    post.update_column(:last_edited_at, post.created_at + 1.second)
    assert post.reload.edited?
  end
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
rails test test/models/post_test.rb
```

Expected: 2 failures — `NoMethodError: undefined method 'edited?'`

- [ ] **Step 3: Add `edited?` to Post model**

In `app/models/post.rb`, add after `def last_activity_at`:

```ruby
  def edited?
    last_edited_at != created_at
  end
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
rails test test/models/post_test.rb
```

Expected: all tests pass.

- [ ] **Step 5: Write failing tests for Reply#edited?**

Add to the bottom of `test/models/reply_test.rb` (inside the class, before the final `end`). Note: `@post` and `@user` are already defined in this file's `setup` block.

```ruby
  test "edited? returns false for a new reply" do
    reply = Reply.create!(post: @post, user: @user, body: "fresh reply")
    assert_not reply.reload.edited?
  end

  test "edited? returns true after last_edited_at is updated" do
    reply = Reply.create!(post: @post, user: @user, body: "fresh reply")
    reply.update_column(:last_edited_at, reply.created_at + 1.second)
    assert reply.reload.edited?
  end
```

- [ ] **Step 6: Run tests to verify they fail**

```bash
rails test test/models/reply_test.rb
```

Expected: 2 failures — `NoMethodError: undefined method 'edited?'`

- [ ] **Step 7: Add `edited?` to Reply model**

In `app/models/reply.rb`, add the public method before the `private` keyword:

```ruby
  def edited?
    last_edited_at != created_at
  end
```

- [ ] **Step 8: Run all model tests**

```bash
rails test test/models/
```

Expected: all pass.

- [ ] **Step 9: Commit**

```bash
git add app/models/post.rb app/models/reply.rb \
        test/models/post_test.rb test/models/reply_test.rb
git commit -m "feat: add edited? helper to Post and Reply models"
```

---

## Chunk 2: Controllers & Routes

### Task 5: Update routes

**Files:**
- Modify: `config/routes.rb`

- [ ] **Step 1: Add edit/update to replies resource**

In `config/routes.rb`, change:

```ruby
    resources :replies, only: [:create, :destroy]
```

to:

```ruby
    resources :replies, only: [:create, :destroy, :edit, :update]
```

- [ ] **Step 2: Verify routes**

```bash
rails routes | grep repl
```

Expected output includes:
```
edit_post_reply  GET    /posts/:post_id/replies/:id/edit
     post_reply  PATCH  /posts/:post_id/replies/:id
```

- [ ] **Step 3: Commit**

```bash
git add config/routes.rb
git commit -m "routes: add edit/update to replies resource"
```

---

### Task 6: PostsController — edit and update actions (TDD)

**Files:**
- Modify: `test/controllers/posts_controller_test.rb`
- Modify: `app/controllers/posts_controller.rb`

- [ ] **Step 1: Write failing tests**

Add the following section to `test/controllers/posts_controller_test.rb` (inside the class, before the final `end`):

```ruby
  # ---- edit / update ----

  test "GET /posts/:id/edit requires login" do
    get edit_post_path(@post)
    assert_redirected_to login_path
  end

  test "GET /posts/:id/edit renders form when owner and within window" do
    post login_path, params: { email: "u@example.com", password: "pass123" }
    get edit_post_path(@post)
    assert_response :success
    assert_select "form[action=?]", post_path(@post)
    assert_select "select[name=?]", "post[category_id]"
  end

  test "GET /posts/:id/edit is forbidden for non-owner" do
    other = User.create!(email: "other@example.com", name: "Other",
                         password: "pass123", password_confirmation: "pass123", provider_id: 3)
    other_post = Post.create!(user: other, title: "Theirs", body: "their body")
    post login_path, params: { email: "u@example.com", password: "pass123" }
    get edit_post_path(other_post)
    assert_redirected_to post_path(other_post)
    assert_match /not authorized/i, flash[:alert]
  end

  test "GET /posts/:id/edit is blocked after edit window expires" do
    @post.update_column(:created_at, (EDIT_WINDOW_SECONDS + 1).seconds.ago)
    post login_path, params: { email: "u@example.com", password: "pass123" }
    get edit_post_path(@post)
    assert_redirected_to post_path(@post)
    assert_match /no longer be edited/i, flash[:alert]
  end

  test "PATCH /posts/:id updates post and sets last_edited_at" do
    post login_path, params: { email: "u@example.com", password: "pass123" }
    original_last_edited_at = @post.last_edited_at
    # travel forward to guarantee Time.current > created_at and avoid same-second flakiness
    travel_to 1.minute.from_now do
      patch post_path(@post), params: { post: { title: "Updated Title", body: "Updated body" } }
    end
    assert_redirected_to post_path(@post)
    @post.reload
    assert_equal "Updated Title", @post.title
    assert @post.last_edited_at > original_last_edited_at
  end

  test "PATCH /posts/:id does not change last_replied_at" do
    @post.update_column(:last_replied_at, 1.hour.ago)
    original_last_replied_at = @post.reload.last_replied_at
    post login_path, params: { email: "u@example.com", password: "pass123" }
    patch post_path(@post), params: { post: { title: "Edited", body: "Edited body" } }
    assert_in_delta original_last_replied_at.to_i, @post.reload.last_replied_at.to_i, 1
  end

  test "PATCH /posts/:id is forbidden for non-owner" do
    other = User.create!(email: "other2@example.com", name: "Other2",
                         password: "pass123", password_confirmation: "pass123", provider_id: 3)
    other_post = Post.create!(user: other, title: "Theirs", body: "their body")
    post login_path, params: { email: "u@example.com", password: "pass123" }
    patch post_path(other_post), params: { post: { title: "Hacked", body: "hacked" } }
    assert_redirected_to post_path(other_post)
    assert_match /not authorized/i, flash[:alert]
  end

  test "PATCH /posts/:id with invalid params re-renders edit with category dropdown" do
    post login_path, params: { email: "u@example.com", password: "pass123" }
    patch post_path(@post), params: { post: { title: "", body: "" } }
    assert_response :unprocessable_entity
    assert_select "select[name=?]", "post[category_id]"
  end

  test "PATCH /posts/:id is blocked after edit window expires" do
    @post.update_column(:created_at, (EDIT_WINDOW_SECONDS + 1).seconds.ago)
    post login_path, params: { email: "u@example.com", password: "pass123" }
    patch post_path(@post), params: { post: { title: "Late Edit", body: "too late" } }
    assert_redirected_to post_path(@post)
    assert_match /no longer be edited/i, flash[:alert]
  end
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
rails test test/controllers/posts_controller_test.rb
```

Expected: 8 new failures — `AbstractController::ActionNotFound` for `edit`/`update`, or routing errors.

- [ ] **Step 3: Implement edit and update in PostsController**

Replace the full content of `app/controllers/posts_controller.rb` with:

```ruby
class PostsController < ApplicationController
  include RateLimitable
  include Bannable

  before_action :require_login, only: [:new, :create, :edit, :update]
  before_action :check_not_banned, only: [:create]
  before_action :check_rate_limit, only: [:create]
  before_action :set_post, only: [:edit, :update]
  before_action :check_ownership, only: [:edit, :update]
  before_action :check_edit_window, only: [:edit, :update]

  def index
    @categories = Category.all.order(:name)
    posts = Post.includes(:user, :category, :replies).order(Arel.sql("COALESCE(last_replied_at, created_at) DESC"))

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

  def edit
    @categories = Category.all.order(:name)
  end

  def update
    if @post.update(post_params.merge(last_edited_at: Time.current))
      redirect_to @post, notice: "Post updated!"
    else
      @categories = Category.all.order(:name)
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def set_post
    @post = Post.find(params[:id])
  end

  def check_ownership
    unless @post.user == current_user
      redirect_to @post, alert: "Not authorized to edit this post."
    end
  end

  def check_edit_window
    if Time.current - @post.created_at > EDIT_WINDOW_SECONDS
      redirect_to @post, alert: "This post can no longer be edited (edit window has expired)."
    end
  end

  def post_params
    params.require(:post).permit(:title, :body, :category_id)
  end

  def rate_limit_redirect_path
    new_post_path
  end

  def ban_redirect_path
    new_post_path
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
rails test test/controllers/posts_controller_test.rb
```

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add app/controllers/posts_controller.rb test/controllers/posts_controller_test.rb
git commit -m "feat: add edit/update to PostsController with ownership and edit-window guards"
```

---

### Task 7: RepliesController — edit and update actions (TDD)

**Files:**
- Modify: `test/controllers/replies_controller_test.rb`
- Modify: `app/controllers/replies_controller.rb`

- [ ] **Step 1: Write failing tests**

Add the following section to `test/controllers/replies_controller_test.rb` (inside the class, before the final `end`):

```ruby
  # ---- edit / update ----

  test "GET /posts/:post_id/replies/:id/edit requires login" do
    reply = Reply.create!(post: @post, user: @user, body: "A reply")
    get edit_post_reply_path(@post, reply)
    assert_redirected_to login_path
  end

  test "GET /posts/:post_id/replies/:id/edit renders form when owner and within window" do
    post login_path, params: { email: "u@example.com", password: "pass123" }
    reply = Reply.create!(post: @post, user: @user, body: "My reply")
    get edit_post_reply_path(@post, reply)
    assert_response :success
    assert_select "form[action=?]", post_reply_path(@post, reply)
    assert_select "textarea[name=?]", "reply[body]"
  end

  test "GET /posts/:post_id/replies/:id/edit is forbidden for non-owner" do
    other = User.create!(email: "other@example.com", name: "Other",
                         password: "pass123", password_confirmation: "pass123", provider_id: 3)
    reply = Reply.create!(post: @post, user: other, body: "Their reply")
    post login_path, params: { email: "u@example.com", password: "pass123" }
    get edit_post_reply_path(@post, reply)
    assert_redirected_to post_path(@post)
    assert_match /not authorized/i, flash[:alert]
  end

  test "GET /posts/:post_id/replies/:id/edit is blocked after edit window expires" do
    post login_path, params: { email: "u@example.com", password: "pass123" }
    reply = Reply.create!(post: @post, user: @user, body: "Old reply")
    reply.update_column(:created_at, (EDIT_WINDOW_SECONDS + 1).seconds.ago)
    get edit_post_reply_path(@post, reply)
    assert_redirected_to post_path(@post)
    assert_match /no longer be edited/i, flash[:alert]
  end

  test "PATCH /posts/:post_id/replies/:id updates reply and sets last_edited_at" do
    post login_path, params: { email: "u@example.com", password: "pass123" }
    reply = Reply.create!(post: @post, user: @user, body: "Original body")
    original_last_edited_at = reply.last_edited_at
    # travel forward to guarantee Time.current > created_at and avoid same-second flakiness
    travel_to 1.minute.from_now do
      patch post_reply_path(@post, reply), params: { reply: { body: "Updated body" } }
    end
    assert_redirected_to post_path(@post)
    reply.reload
    assert_equal "Updated body", reply.body
    assert reply.last_edited_at > original_last_edited_at
  end

  test "PATCH /posts/:post_id/replies/:id does not change post last_replied_at" do
    post login_path, params: { email: "u@example.com", password: "pass123" }
    # Create reply first (after_create sets last_replied_at), then set our known baseline
    reply = Reply.create!(post: @post, user: @user, body: "A reply")
    @post.update_column(:last_replied_at, 1.hour.ago)
    original_last_replied_at = @post.reload.last_replied_at
    patch post_reply_path(@post, reply), params: { reply: { body: "Edited" } }
    assert_in_delta original_last_replied_at.to_i, @post.reload.last_replied_at.to_i, 1
  end

  test "PATCH /posts/:post_id/replies/:id is forbidden for non-owner" do
    other = User.create!(email: "other2@example.com", name: "Other2",
                         password: "pass123", password_confirmation: "pass123", provider_id: 3)
    reply = Reply.create!(post: @post, user: other, body: "Their reply")
    post login_path, params: { email: "u@example.com", password: "pass123" }
    patch post_reply_path(@post, reply), params: { reply: { body: "Hacked" } }
    assert_redirected_to post_path(@post)
    assert_match /not authorized/i, flash[:alert]
  end

  test "PATCH /posts/:post_id/replies/:id with blank body re-renders edit" do
    post login_path, params: { email: "u@example.com", password: "pass123" }
    reply = Reply.create!(post: @post, user: @user, body: "Valid body")
    patch post_reply_path(@post, reply), params: { reply: { body: "" } }
    assert_response :unprocessable_entity
  end

  test "PATCH /posts/:post_id/replies/:id is blocked after edit window expires" do
    post login_path, params: { email: "u@example.com", password: "pass123" }
    reply = Reply.create!(post: @post, user: @user, body: "Old reply")
    reply.update_column(:created_at, (EDIT_WINDOW_SECONDS + 1).seconds.ago)
    patch post_reply_path(@post, reply), params: { reply: { body: "Too late" } }
    assert_redirected_to post_path(@post)
    assert_match /no longer be edited/i, flash[:alert]
  end
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
rails test test/controllers/replies_controller_test.rb
```

Expected: 8 new failures.

- [ ] **Step 3: Implement edit and update in RepliesController**

Replace the full content of `app/controllers/replies_controller.rb` with:

```ruby
class RepliesController < ApplicationController
  include RateLimitable
  include Bannable

  before_action :require_login
  before_action :check_not_banned, only: [:create]
  before_action :check_rate_limit, only: [:create]
  before_action :set_reply, only: [:edit, :update]
  before_action :check_ownership, only: [:edit, :update]
  before_action :check_edit_window, only: [:edit, :update]

  def create
    @post = Post.find(params[:post_id])
    @reply = @post.replies.build(reply_params.merge(user: current_user))
    if @reply.save
      redirect_to @post, notice: "Reply posted!"
    else
      @post = Post.includes(replies: :user).find(params[:post_id])
      render "posts/show", status: :unprocessable_entity
    end
  end

  def destroy
    @post = Post.find(params[:post_id])
    @reply = @post.replies.find(params[:id])
    unless @reply.user == current_user
      redirect_to @post, alert: "Not authorized to delete this reply.", status: :see_other
      return
    end
    @reply.destroy
    redirect_to @post, notice: "Reply deleted."
  end

  def edit
  end

  def update
    if @reply.update(reply_params.merge(last_edited_at: Time.current))
      redirect_to @post, notice: "Reply updated!"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def set_reply
    @post  = Post.find(params[:post_id])
    @reply = @post.replies.find(params[:id])
  end

  def check_ownership
    unless @reply.user == current_user
      redirect_to @post, alert: "Not authorized to edit this reply."
    end
  end

  def check_edit_window
    if Time.current - @reply.created_at > EDIT_WINDOW_SECONDS
      redirect_to @post, alert: "This reply can no longer be edited (edit window has expired)."
    end
  end

  def reply_params
    params.require(:reply).permit(:body)
  end

  def rate_limit_redirect_path
    post_path(params[:post_id])
  end

  def ban_redirect_path
    post_path(params[:post_id])
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
rails test test/controllers/replies_controller_test.rb
```

Expected: all tests pass.

- [ ] **Step 5: Run the full test suite**

```bash
rails test
```

Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
git add app/controllers/replies_controller.rb test/controllers/replies_controller_test.rb
git commit -m "feat: add edit/update to RepliesController with ownership and edit-window guards"
```

---

## Chunk 3: Views

### Task 8: Create posts/edit.html.erb

**Files:**
- Create: `app/views/posts/edit.html.erb`

- [ ] **Step 1: Create the edit form**

```erb
<%# app/views/posts/edit.html.erb %>
<div class="max-w-2xl mx-auto mt-8 px-4">
  <h1 class="text-2xl font-bold mb-6">Edit Post</h1>

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
    <div class="flex gap-3">
      <%= f.submit "Update Post", class: "bg-blue-600 text-white px-4 py-2 rounded-md hover:bg-blue-700 font-medium" %>
      <%= link_to "Cancel", @post, class: "text-gray-600 hover:underline px-4 py-2" %>
    </div>
  <% end %>
</div>
```

---

### Task 9: Create replies/edit.html.erb

**Files:**
- Create: `app/views/replies/edit.html.erb`

- [ ] **Step 1: Create the edit form**

```erb
<%# app/views/replies/edit.html.erb %>
<div class="max-w-2xl mx-auto mt-8 px-4">
  <h1 class="text-2xl font-bold mb-6">Edit Reply</h1>

  <%= form_with model: [@post, @reply], class: "space-y-4 bg-white border border-gray-200 rounded-lg p-6" do |f| %>
    <% if @reply.errors.any? %>
      <div class="bg-red-50 border border-red-200 text-red-700 px-4 py-3 rounded text-sm">
        <ul class="list-disc list-inside">
          <% @reply.errors.full_messages.each do |msg| %>
            <li><%= msg %></li>
          <% end %>
        </ul>
      </div>
    <% end %>

    <div>
      <%= f.label :body, "Reply", class: "block text-sm font-medium text-gray-700" %>
      <%= f.text_area :body, rows: 6, class: "mt-1 block w-full border border-gray-300 rounded-md px-3 py-2 focus:outline-none focus:ring-2 focus:ring-blue-500" %>
    </div>
    <div class="flex gap-3">
      <%= f.submit "Update Reply", class: "bg-blue-600 text-white px-4 py-2 rounded-md hover:bg-blue-700 font-medium" %>
      <%= link_to "Cancel", @post, class: "text-gray-600 hover:underline px-4 py-2" %>
    </div>
  <% end %>
</div>
```

---

### Task 10: Update posts/show.html.erb — edit links and "last edited at"

**Files:**
- Modify: `app/views/posts/show.html.erb`
- Modify: `test/controllers/posts_controller_test.rb`

- [ ] **Step 1: Write failing view tests**

Add the following section to `test/controllers/posts_controller_test.rb` (inside the class, before the final `end`):

```ruby
  # ---- show view: edit link and last-edited display ----

  test "GET /posts/:id shows edit link for post owner within window" do
    post login_path, params: { email: "u@example.com", password: "pass123" }
    get post_path(@post)
    assert_select "a[href=?]", edit_post_path(@post)
  end

  test "GET /posts/:id hides edit link for non-owner" do
    other = User.create!(email: "other3@example.com", name: "Other3",
                         password: "pass123", password_confirmation: "pass123", provider_id: 3)
    other_post = Post.create!(user: other, title: "Theirs", body: "their body")
    post login_path, params: { email: "u@example.com", password: "pass123" }
    get post_path(other_post)
    assert_select "a[href=?]", edit_post_path(other_post), count: 0
  end

  test "GET /posts/:id hides edit link after edit window expires" do
    @post.update_column(:created_at, (EDIT_WINDOW_SECONDS + 1).seconds.ago)
    post login_path, params: { email: "u@example.com", password: "pass123" }
    get post_path(@post)
    assert_select "a[href=?]", edit_post_path(@post), count: 0
  end

  test "GET /posts/:id hides edit link when not logged in" do
    get post_path(@post)
    assert_select "a[href=?]", edit_post_path(@post), count: 0
  end

  test "GET /posts/:id shows last edited at when post has been edited" do
    @post.update_column(:last_edited_at, @post.created_at + 5.minutes)
    get post_path(@post)
    assert_select ".last-edited-at"
  end

  test "GET /posts/:id does not show last edited at on fresh post" do
    get post_path(@post)
    assert_select ".last-edited-at", count: 0
  end

  test "GET /posts/:id shows last edited at on reply that has been edited" do
    reply_user = User.create!(email: "rv2@example.com", name: "RV2",
                               password: "pass123", password_confirmation: "pass123", provider_id: 3)
    reply = Reply.create!(post: @post, user: reply_user, body: "a reply")
    reply.update_column(:last_edited_at, reply.created_at + 5.minutes)
    get post_path(@post)
    assert_select ".last-edited-at"
  end

  test "GET /posts/:id shows edit link for reply owner within window" do
    post login_path, params: { email: "u@example.com", password: "pass123" }
    reply = Reply.create!(post: @post, user: @user, body: "My reply")
    get post_path(@post)
    assert_select "a[href=?]", edit_post_reply_path(@post, reply)
  end

  test "GET /posts/:id hides edit link for reply non-owner" do
    other = User.create!(email: "other4@example.com", name: "Other4",
                         password: "pass123", password_confirmation: "pass123", provider_id: 3)
    reply = Reply.create!(post: @post, user: other, body: "Their reply")
    post login_path, params: { email: "u@example.com", password: "pass123" }
    get post_path(@post)
    assert_select "a[href=?]", edit_post_reply_path(@post, reply), count: 0
  end

  test "GET /posts/:id hides edit link for reply after edit window expires" do
    post login_path, params: { email: "u@example.com", password: "pass123" }
    reply = Reply.create!(post: @post, user: @user, body: "My reply")
    reply.update_column(:created_at, (EDIT_WINDOW_SECONDS + 1).seconds.ago)
    get post_path(@post)
    assert_select "a[href=?]", edit_post_reply_path(@post, reply), count: 0
  end
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
rails test test/controllers/posts_controller_test.rb
```

Expected: new test failures (edit links and `.last-edited-at` elements not present yet).

- [ ] **Step 3: Update posts/show.html.erb**

Replace the full content of `app/views/posts/show.html.erb` with:

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
      <div class="flex items-center gap-1.5">
        <% if @post.user.avatar_url.present? %>
          <%= image_tag @post.user.avatar_url, class: "w-5 h-5 rounded-full", alt: "" %>
        <% else %>
          <span class="w-5 h-5 rounded-full bg-teal-100 text-teal-700 font-semibold flex items-center justify-center text-xs">
            <%= (@post.user.name.presence || "?").first.upcase %>
          </span>
        <% end %>
        <p class="text-sm text-gray-500">
          <%= @post.user.name %> &middot; <%= time_ago_in_words(@post.created_at) %> ago
        </p>
      </div>
      <% if logged_in? && current_user == @post.user && Time.current - @post.created_at <= EDIT_WINDOW_SECONDS %>
        <%= link_to "Edit", edit_post_path(@post), class: "text-xs text-blue-500 hover:underline ml-auto" %>
      <% end %>
    </div>
    <div class="mt-4 text-gray-800 whitespace-pre-wrap"><%= @post.body %></div>
    <% if @post.edited? %>
      <p class="text-xs text-gray-400 mt-2 last-edited-at">last edited at <%= @post.last_edited_at.strftime("%-d %b %Y %H:%M") %></p>
    <% end %>
  </div>

  <div class="mt-8">
    <h2 class="text-xl font-semibold mb-4">
      Replies (<%= @post.replies.size %>)
    </h2>

    <% @post.replies.each do |reply| %>
      <div class="bg-gray-50 border border-gray-200 rounded-lg p-4 mb-3">
        <div class="flex items-center gap-2 mb-2">
          <% if reply.user.avatar_url.present? %>
            <%= image_tag reply.user.avatar_url, class: "w-6 h-6 rounded-full", alt: "" %>
          <% else %>
            <span class="w-6 h-6 rounded-full bg-teal-100 text-teal-700 font-semibold flex items-center justify-center text-xs">
              <%= (reply.user.name.presence || "?").first.upcase %>
            </span>
          <% end %>
          <span class="text-sm font-medium text-gray-700"><%= reply.user.name %></span>
          <span class="text-xs text-gray-400"><%= time_ago_in_words(reply.created_at) %> ago</span>
          <% if logged_in? && current_user == reply.user && Time.current - reply.created_at <= EDIT_WINDOW_SECONDS %>
            <%= link_to "Edit", edit_post_reply_path(@post, reply), class: "text-xs text-blue-500 hover:underline ml-auto" %>
          <% end %>
        </div>
        <p class="text-gray-800 whitespace-pre-wrap"><%= reply.body %></p>
        <% if reply.edited? %>
          <p class="text-xs text-gray-400 mt-1 last-edited-at">last edited at <%= reply.last_edited_at.strftime("%-d %b %Y %H:%M") %></p>
        <% end %>
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

- [ ] **Step 4: Run tests to verify they pass**

```bash
rails test test/controllers/posts_controller_test.rb
```

Expected: all tests pass.

- [ ] **Step 5: Run the full test suite**

```bash
rails test
```

Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
git add app/views/posts/edit.html.erb \
        app/views/replies/edit.html.erb \
        app/views/posts/show.html.erb \
        test/controllers/posts_controller_test.rb
git commit -m "feat: add edit views and last-edited-at display to posts/show"
```
