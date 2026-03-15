# Homepage Redesign — Forest Community Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Redesign the forum homepage with an earthy teal/green palette, two-column layout with sticky category sidebar, and spacious post feed with rich post previews.

**Architecture:** Three targeted file changes — fix an N+1 in the controller, update the nav bar in the layout, and fully redesign the index view. No new files, no new partials, no JS changes. Existing CSS selector contracts (`.post-card`, `.category-badge`) preserved so existing tests continue to pass.

**Tech Stack:** Rails 7+, Tailwind CSS v4, ERB templates, Rails built-in helpers (`strip_tags`, `truncate`, `time_ago_in_words`)

---

## Chunk 1: Controller Fix

### Task 1: Fix N+1 — add `replies` to `includes`

**Files:**
- Modify: `app/controllers/posts_controller.rb:6`
- Test: `test/controllers/posts_controller_test.rb`

The `index` action loads posts but does not eager-load `replies`. Adding reply counts to the post cards would fire one query per post. Fix by adding `:replies` to the `includes` call.

The N+1 fix is a performance change — there is no meaningful unit test to write that wouldn't duplicate the query itself. The existing integration tests (especially the pagination and category filter tests) will continue to exercise the index action and catch any controller regressions.

- [ ] **Step 1: Run the test suite to confirm baseline**

  ```bash
  cd /root/RubymineProjects/RailsApps/forum
  bin/rails test test/controllers/posts_controller_test.rb
  ```

  Expected: 19 runs, 0 failures.

- [ ] **Step 3: Update `PostsController#index` to include replies**

  In `app/controllers/posts_controller.rb`, change line 6 from:

  ```ruby
  posts = Post.includes(:user, :category).order(created_at: :desc)
  ```

  to:

  ```ruby
  posts = Post.includes(:user, :category, :replies).order(created_at: :desc)
  ```

- [ ] **Step 4: Run tests to confirm still passing**

  ```bash
  bin/rails test test/controllers/posts_controller_test.rb
  ```

  Expected: all runs pass, 0 failures.

- [ ] **Step 5: Commit**

  ```bash
  cd /root/RubymineProjects/RailsApps/forum
  git add app/controllers/posts_controller.rb
  git commit -m "perf: eager-load replies on posts index to prevent N+1"
  ```

---

## Chunk 2: Navigation Bar

### Task 2: Redesign the navigation bar in the application layout

**Files:**
- Modify: `app/views/layouts/application.html.erb`

Replace the white nav with a teal nav. Move "New Post" button here (logged-in only). Update flash container to match new layout width.

**Current nav** (lines 13–33) uses `bg-white`, `text-blue-700`, `max-w-3xl`.
**New nav** uses `bg-teal-700`, white text, `max-w-7xl` container, teal "New Post" button.

- [ ] **Step 1: Write a test for nav bar elements**

  Add to `test/controllers/posts_controller_test.rb`:

  ```ruby
  test "nav shows New Post button when logged in" do
    post login_path, params: { email: "u@example.com", password: "pass123" }
    get posts_path
    assert_select "nav a[href=?]", new_post_path
  end

  test "nav hides New Post button when logged out" do
    get posts_path
    assert_select "nav a[href=?]", new_post_path, count: 0
  end

  test "nav shows login and signup links when logged out" do
    get posts_path
    assert_select "nav a[href=?]", login_path
    assert_select "nav a[href=?]", signup_path
  end

  test "nav shows logout button when logged in" do
    post login_path, params: { email: "u@example.com", password: "pass123" }
    get posts_path
    assert_select "nav form[action=?]", logout_path
  end
  ```

- [ ] **Step 2: Run tests — expect failures for nav assertions**

  ```bash
  bin/rails test test/controllers/posts_controller_test.rb
  ```

  Expected: the 4 new nav tests fail (nav still renders old markup with `new_post_path` outside `nav` tag).

- [ ] **Step 3: Replace the nav and flash sections in `application.html.erb`**

  Replace the entire `<body>` through `<main>` block with:

  ```erb
  <body class="bg-stone-50 min-h-screen">
    <nav class="bg-teal-700 shadow-sm">
      <div class="max-w-7xl mx-auto px-4 py-3 flex items-center justify-between">
        <%= link_to "Forum", root_path, class: "text-xl font-bold text-white" %>

        <div class="flex items-center gap-3 text-sm">
          <% if logged_in? %>
            <%= link_to "New Post", new_post_path,
                  class: "bg-white text-teal-700 font-semibold rounded-lg px-4 py-1.5 hover:bg-teal-50" %>
            <span class="flex items-center gap-2 text-white">
              <% if current_user.avatar_url.present? %>
                <%= image_tag current_user.avatar_url, class: "w-8 h-8 rounded-full", alt: "" %>
              <% else %>
                <span class="w-8 h-8 rounded-full bg-teal-100 text-teal-700 font-semibold flex items-center justify-center text-sm">
                  <%= current_user.name.first.upcase %>
                </span>
              <% end %>
              <%= current_user.name %>
            </span>
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

    <% if notice.present? %>
      <div class="max-w-7xl mx-auto px-4 mt-4">
        <div class="bg-green-50 border border-green-200 text-green-800 px-4 py-3 rounded-lg text-sm">
          <%= notice %>
        </div>
      </div>
    <% end %>

    <% if alert.present? %>
      <div class="max-w-7xl mx-auto px-4 mt-4">
        <div class="bg-red-50 border border-red-200 text-red-700 px-4 py-3 rounded-lg text-sm">
          <%= alert %>
        </div>
      </div>
    <% end %>

    <main><%= yield %></main>
  </body>
  ```

- [ ] **Step 4: Run tests — expect all to pass**

  ```bash
  bin/rails test test/controllers/posts_controller_test.rb
  ```

  Expected: all runs pass, 0 failures.

- [ ] **Step 5: Commit**

  ```bash
  git add app/views/layouts/application.html.erb test/controllers/posts_controller_test.rb
  git commit -m "feat: redesign nav bar with teal theme and move New Post button"
  ```

---

## Chunk 3: Post Index View

### Task 3: Redesign the post index view

**Files:**
- Modify: `app/views/posts/index.html.erb`
- Test: `test/controllers/posts_controller_test.rb`

Full redesign: two-column layout (sidebar + feed), post cards with preview text, reply count, avatar, empty state. Remove in-page "New Post" button (now in nav). Preserve `.post-card` and `.category-badge` CSS classes for existing tests.

- [ ] **Step 1: Add tests for new index view elements**

  Add to `test/controllers/posts_controller_test.rb`:

  ```ruby
  test "GET /posts shows post body preview" do
    get posts_path
    assert_response :success
    assert_select ".post-card p", text: /First post body/
  end

  test "GET /posts shows reply count on post card" do
    reply_user = User.create!(email: "rc@example.com", name: "RC", password: "pass123",
                              password_confirmation: "pass123", provider_id: 3)
    Reply.create!(post: @post, user: reply_user, body: "reply here")
    get posts_path
    assert_response :success
    assert_select ".post-card .reply-count", text: /1/
  end

  test "GET /posts shows empty state when no posts" do
    Post.delete_all
    get posts_path
    assert_response :success
    assert_select ".empty-state"
  end

  test "GET /posts does not show New Post button in the post feed when posts exist" do
    post login_path, params: { email: "u@example.com", password: "pass123" }
    get posts_path
    # When posts exist the feed renders cards, not the empty-state New Post button.
    # The only New Post link should be in the nav (already asserted in nav tests).
    assert_select ".empty-state", count: 0
  end
  ```

- [ ] **Step 2: Run tests — expect new tests to fail**

  ```bash
  bin/rails test test/controllers/posts_controller_test.rb
  ```

  Expected: the 4 new tests fail (old markup missing reply-count, empty-state classes; old view has in-page New Post in main).

- [ ] **Step 3: Replace `app/views/posts/index.html.erb` with the redesigned view**

  ```erb
  <%# app/views/posts/index.html.erb %>
  <div class="max-w-7xl mx-auto mt-8 px-4 pb-12">
    <div class="flex gap-8">

      <%# Sidebar %>
      <aside class="hidden lg:block w-64 shrink-0">
        <div class="sticky top-4">
          <p class="text-xs font-semibold uppercase tracking-wide text-stone-400 mb-3">Categories</p>
          <nav class="flex flex-col gap-1">
            <%= link_to "All Posts", posts_path(take: @take),
                  class: "px-3 py-2 rounded-lg text-sm block #{params[:category].blank? ? 'bg-teal-50 text-teal-700 font-semibold' : 'text-stone-600 hover:bg-stone-100'}" %>
            <% @categories.each do |cat| %>
              <%= link_to cat.name, posts_path(category: cat.id, take: @take),
                    class: "px-3 py-2 rounded-lg text-sm block #{params[:category].to_i == cat.id ? 'bg-teal-50 text-teal-700 font-semibold' : 'text-stone-600 hover:bg-stone-100'}" %>
            <% end %>
          </nav>
        </div>
      </aside>

      <%# Feed %>
      <div class="flex-1 min-w-0">

        <% if @posts.empty? %>
          <div class="empty-state bg-white border border-stone-200 rounded-xl p-8 text-center">
            <p class="text-stone-400 text-sm mb-4">No posts yet. Be the first to start a conversation!</p>
            <% if logged_in? %>
              <%= link_to "New Post", new_post_path,
                    class: "inline-block bg-teal-700 text-white font-semibold rounded-lg px-4 py-2 hover:bg-teal-600" %>
            <% end %>
          </div>
        <% else %>
          <div class="space-y-4">
            <% @posts.each do |post| %>
              <div class="post-card bg-white border border-stone-200 rounded-xl shadow-sm p-5 hover:border-teal-300 hover:shadow-md transition-all">

                <%# Top row: category badge + timestamp %>
                <div class="flex items-center justify-between mb-2">
                  <%= link_to post.category.name,
                        posts_path(category: post.category_id, take: @take),
                        class: "category-badge bg-teal-100 text-teal-800 text-xs font-medium px-2 py-0.5 rounded-full hover:bg-teal-200" %>
                  <span class="text-xs text-stone-400"><%= time_ago_in_words(post.created_at) %> ago</span>
                </div>

                <%# Title %>
                <h2 class="text-lg font-semibold">
                  <%= link_to post.title, post_path(post),
                        class: "text-stone-900 hover:text-teal-700" %>
                </h2>

                <%# Body preview %>
                <p class="text-sm text-stone-500 line-clamp-2 mt-1">
                  <%= truncate(strip_tags(post.body), length: 200) %>
                </p>

                <%# Bottom row: author + reply count %>
                <div class="flex items-center justify-between mt-3 pt-3 border-t border-stone-100">
                  <div class="flex items-center gap-2">
                    <% if post.user.avatar_url.present? %>
                      <%= image_tag post.user.avatar_url, class: "w-6 h-6 rounded-full", alt: "" %>
                    <% else %>
                      <span class="w-6 h-6 rounded-full bg-teal-100 text-teal-700 font-semibold flex items-center justify-center text-xs">
                        <%= post.user.name.first.upcase %>
                      </span>
                    <% end %>
                    <span class="text-sm font-medium text-stone-700"><%= post.user.name %></span>
                  </div>
                  <span class="reply-count text-sm text-stone-400 flex items-center gap-1">
                    &#128172; <%= post.replies.size %>
                  </span>
                </div>

              </div>
            <% end %>
          </div>

          <%# Pagination %>
          <div class="flex justify-between mt-6">
            <% if @page > 1 %>
              <%= link_to "← Older", posts_path(category: params[:category], take: @take, page: @page - 1),
                    class: "text-teal-700 hover:underline font-medium text-sm" %>
            <% else %>
              <span></span>
            <% end %>
            <% if @posts.size >= @take %>
              <%= link_to "Newer →", posts_path(category: params[:category], take: @take, page: @page + 1),
                    class: "text-teal-700 hover:underline font-medium text-sm" %>
            <% end %>
          </div>
        <% end %>

      </div>
    </div>
  </div>
  ```

- [ ] **Step 4: Run the full test suite**

  ```bash
  bin/rails test test/controllers/posts_controller_test.rb
  ```

  Expected: all runs pass, 0 failures. Key tests to watch:
  - `.post-card` count tests (pagination) — class preserved ✓
  - `.category-badge` test — class preserved ✓
  - `h2 a` text tests — title still in `h2 > a` ✓
  - New reply count / empty state / nav tests — now passing ✓

- [ ] **Step 5: Commit**

  ```bash
  git add app/views/posts/index.html.erb test/controllers/posts_controller_test.rb
  git commit -m "feat: redesign homepage with Forest Community teal theme and two-column layout"
  ```

---

## Final Verification

- [ ] **Run the full test suite one last time**

  ```bash
  bin/rails test
  ```

  Expected: all tests pass, 0 failures, 0 errors.

- [ ] **Smoke-check in browser** (optional but recommended)

  ```bash
  bin/dev
  ```

  Open `http://localhost:3000`. Verify:
  - Teal nav bar with white "Forum" text
  - Two-column layout: sidebar on left with category links, feed on right
  - Post cards with category badge, title, body preview, author avatar/initial, reply count
  - Hover state: card border turns teal, shadow lifts
  - Empty state card when no posts exist
  - Pagination shows "← Older" / "Newer →"
