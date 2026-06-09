# @Mention Autocomplete Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an @mention autocomplete dropdown to the reply textarea that shows thread participants as the user types `@`, inserting `@Token` (spaces-as-underscores) which NotificationService resolves back to the user.

**Architecture:** Inline data approach — thread participants are serialized to a `data-` attribute on the reply form wrapper at render time; a new Stimulus controller reads that value and handles all dropdown logic client-side. No API endpoints added. The `User` model sanitizes underscores-to-spaces on save so tokens never collide with literal-underscore names. `NotificationService` already resolves `@(\w+)` patterns and is updated to convert underscores-to-spaces before the DB lookup.

**Tech Stack:** Rails 8.1, Minitest, Stimulus (Hotwire), Tailwind CSS, importmap (no npm/bundler for JS).

---

## Files

| File | Action |
|------|--------|
| `app/models/user.rb` | Add `before_validation :sanitize_name` private method |
| `app/services/notification_service.rb` | Change line 50: add `.gsub('_', ' ')` to username before lookup |
| `app/controllers/posts_controller.rb` | Add `@mention_users` query in `show` action |
| `app/views/posts/show.html.erb` | Extend controller div (line 108) + textarea data attributes |
| `app/javascript/controllers/mention_autocomplete_controller.js` | New Stimulus controller |
| `test/models/user_test.rb` | Add sanitize_name and from_omniauth underscore tests |
| `test/controllers/posts_controller_test.rb` | Add `@mention_users` assignment tests |
| `test/services/notification_service_test.rb` | Add multi-word mention resolution tests |

---

## Task 1: User model — sanitize underscores in name

**Files:**
- Modify: `app/models/user.rb`
- Test: `test/models/user_test.rb`

- [ ] **Step 1: Write failing tests**

Add to `test/models/user_test.rb` (before the closing `end`):

```ruby
test "underscore in name is replaced with space on save" do
  user = User.new(email: "under@example.com", name: "Jane_Doe",
                  password: "pass123", password_confirmation: "pass123",
                  provider_id: 3)
  user.valid?
  assert_equal "Jane Doe", user.name
end

test "name without underscore is unchanged on save" do
  user = User.new(email: "plain@example.com", name: "Jane Doe",
                  password: "pass123", password_confirmation: "pass123",
                  provider_id: 3)
  user.valid?
  assert_equal "Jane Doe", user.name
end

test "from_omniauth with underscore name saves with underscores replaced by spaces" do
  auth = OpenStruct.new(
    uid: "google-underscore",
    info: OpenStruct.new(email: "under2@example.com", name: "Jane_Doe", image: nil)
  )
  user = User.from_omniauth(auth, 1)
  assert_equal "Jane Doe", user.name
end
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
bin/rails test test/models/user_test.rb
```

Expected: 3 failures — `sanitize_name` not defined.

- [ ] **Step 3: Implement `sanitize_name` in `User`**

In `app/models/user.rb`, inside the `private` section (after `password_matches_confirmation`):

```ruby
def sanitize_name
  self.name = name.gsub("_", " ") if name.present?
end
```

And add before the `private` keyword (with existing callbacks):

```ruby
before_validation :sanitize_name
```

- [ ] **Step 4: Run tests to confirm they pass**

```bash
bin/rails test test/models/user_test.rb
```

Expected: all green.

- [ ] **Step 5: Run full suite to check for regressions**

```bash
bin/rails test
```

Expected: all green.

- [ ] **Step 6: Commit**

```bash
git add app/models/user.rb test/models/user_test.rb
git commit -m "feat: sanitize underscores-to-spaces in User#name on save"
```

---

## Task 2: NotificationService — resolve underscore tokens

**Files:**
- Modify: `app/services/notification_service.rb:50`
- Test: `test/services/notification_service_test.rb`

- [ ] **Step 1: Write failing tests**

Add to `test/services/notification_service_test.rb` (before the final `end`):

```ruby
test "multi-word mention @Jane_Doe notifies user named 'Jane Doe'" do
  jane = User.create!(email: "jane@example.com", name: "Jane Doe",
                      password: "pass123", password_confirmation: "pass123", provider_id: 3)
  reply_with_mention = Reply.create!(post: @post, user: @replier, body: "hey @Jane_Doe nice work")
  assert_difference "Notification.where(event_type: :mention).count", 1 do
    NotificationService.reply_created(reply_with_mention, current_user: @replier)
  end
  assert_not_nil Notification.find_by(user: jane, event_type: :mention)
end

test "single-word mention still resolves correctly after gsub change" do
  new_user = User.create!(email: "solo@example.com", name: "soloist",
                          password: "pass123", password_confirmation: "pass123", provider_id: 3)
  reply_with_mention = Reply.create!(post: @post, user: @replier, body: "good job @soloist")
  assert_difference "Notification.where(event_type: :mention).count", 1 do
    NotificationService.reply_created(reply_with_mention, current_user: @replier)
  end
  assert_not_nil Notification.find_by(user: new_user, event_type: :mention)
end
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
bin/rails test test/services/notification_service_test.rb
```

Expected: `multi-word mention` test fails (user not found via lookup); single-word test passes.

- [ ] **Step 3: Update NotificationService lookup**

Change line 50 of `app/services/notification_service.rb` from:

```ruby
mentioned = User.find_by("LOWER(name) = LOWER(?)", username)
```

to:

```ruby
mentioned = User.find_by("LOWER(name) = LOWER(?)", username.gsub("_", " "))
```

- [ ] **Step 4: Run tests to confirm they pass**

```bash
bin/rails test test/services/notification_service_test.rb
```

Expected: all green.

- [ ] **Step 5: Commit**

```bash
git add app/services/notification_service.rb test/services/notification_service_test.rb
git commit -m "feat: resolve @underscore_tokens to space-separated names in NotificationService"
```

---

## Task 3: PostsController — build `@mention_users`

**Files:**
- Modify: `app/controllers/posts_controller.rb:28-48`
- Test: `test/controllers/posts_controller_test.rb`

- [ ] **Step 1: Write failing tests**

Add to `test/controllers/posts_controller_test.rb` (before the final `end`):

```ruby
test "show sets @mention_users to post author and visible repliers, deduplicated" do
  replier_a = User.create!(email: "ra@example.com", name: "Replier A",
                            password: "pass123", password_confirmation: "pass123", provider_id: 3)
  replier_b = User.create!(email: "rb@example.com", name: "Replier B",
                            password: "pass123", password_confirmation: "pass123", provider_id: 3)
  Reply.create!(post: @post, user: replier_a, body: "reply one")
  Reply.create!(post: @post, user: replier_b, body: "reply two")
  # replier_a replies twice — should appear only once
  Reply.create!(post: @post, user: replier_a, body: "reply three")

  post login_path, params: { email: "u@example.com", password: "pass123" }
  get post_path(@post)

  assert_response :success
  mention_users = assigns(:mention_users)
  assert_not_nil mention_users
  assert_includes mention_users, @user       # post author
  assert_includes mention_users, replier_a
  assert_includes mention_users, replier_b
  assert_equal mention_users.map(&:id).uniq.length, mention_users.length
end

test "show excludes removed replies from @mention_users" do
  replier = User.create!(email: "gone@example.com", name: "Gone User",
                         password: "pass123", password_confirmation: "pass123", provider_id: 3)
  removed_reply = Reply.create!(post: @post, user: replier, body: "about to be removed",
                                removed_at: Time.current, removed_by: @admin)

  post login_path, params: { email: "u@example.com", password: "pass123" }
  get post_path(@post)

  assert_not_includes assigns(:mention_users), replier
end

test "show sets @mention_users to empty array for logged-out requests" do
  get post_path(@post)
  assert_equal [], assigns(:mention_users)
end
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
bin/rails test test/controllers/posts_controller_test.rb
```

Expected: new tests fail — `@mention_users` not assigned.

- [ ] **Step 3: Add `@mention_users` to `PostsController#show`**

In `app/controllers/posts_controller.rb`, after the `@flagged_reply_ids` assignment in `show` (after line 47), add:

```ruby
if logged_in?
  participant_ids = (@post.replies.visible.distinct.pluck(:user_id) + [@post.user_id]).uniq
  @mention_users = User.where(id: participant_ids)
else
  @mention_users = []
end
```

- [ ] **Step 4: Run tests to confirm they pass**

```bash
bin/rails test test/controllers/posts_controller_test.rb
```

Expected: all green.

- [ ] **Step 5: Commit**

```bash
git add app/controllers/posts_controller.rb test/controllers/posts_controller_test.rb
git commit -m "feat: assign @mention_users in PostsController#show for autocomplete"
```

---

## Task 4: View — wire up Stimulus controller and data attribute

**Files:**
- Modify: `app/views/posts/show.html.erb:108,119-121`
- Test: `test/controllers/posts_controller_test.rb` (integration assertion)

- [ ] **Step 1: Write failing integration test**

Add to `test/controllers/posts_controller_test.rb`:

```ruby
test "reply form renders mention autocomplete data attribute with correct JSON" do
  replier = User.create!(email: "rj@example.com", name: "Reply Jones",
                         password: "pass123", password_confirmation: "pass123", provider_id: 3)
  Reply.create!(post: @post, user: replier, body: "a reply")

  post login_path, params: { email: "u@example.com", password: "pass123" }
  get post_path(@post)

  assert_response :success
  # data attribute exists on the controller div
  assert_select "[data-controller~='mention-autocomplete']"
  # JSON contains expected entries
  assert_select "[data-mention-autocomplete-users-value]" do |elements|
    json = JSON.parse(elements.first["data-mention-autocomplete-users-value"])
    tokens = json.map { |e| e["token"] }
    displays = json.map { |e| e["display"] }
    assert_includes tokens, "Reply_Jones"
    assert_includes displays, "Reply Jones"
    assert_includes tokens, "User"       # post author (name "User" has no spaces)
    assert_includes displays, "User"
  end
end
```

- [ ] **Step 2: Run test to confirm it fails**

```bash
bin/rails test test/controllers/posts_controller_test.rb
```

Expected: fails — controller attribute not present.

- [ ] **Step 3: Update `show.html.erb`**

In `app/views/posts/show.html.erb`, change line 108 from:

```erb
          <div data-controller="markdown-preview">
```

to (use `html_escape` so the JSON value is safe in an HTML attribute, preventing injection from names containing `"` or `<`):

```erb
          <div data-controller="markdown-preview mention-autocomplete"
               data-mention-autocomplete-users-value="<%= html_escape(@mention_users.map { |u| { token: u.name.gsub(' ', '_'), display: u.name } }.to_json) %>">
```

Then change the textarea (lines 119-121) to add the `mention_autocomplete_target`:

```erb
            <%= f.text_area :body, rows: 4, placeholder: "Write your reply...",
                  class: "w-full border border-gray-300 dark:border-stone-600 rounded-md px-3 py-2 focus:outline-none focus:ring-2 focus:ring-blue-500 dark:focus:ring-blue-400 bg-white dark:bg-stone-700 text-stone-900 dark:text-stone-100",
                  data: {
                    markdown_preview_target: "textarea",
                    mention_autocomplete_target: "textarea"
                  } %>
```

- [ ] **Step 4: Run test to confirm it passes**

```bash
bin/rails test test/controllers/posts_controller_test.rb
```

Expected: all green.

- [ ] **Step 5: Commit**

```bash
git add app/views/posts/show.html.erb test/controllers/posts_controller_test.rb
git commit -m "feat: add mention-autocomplete controller and users data attribute to reply form"
```

---

## Task 5: Stimulus controller — mention autocomplete UI

**Files:**
- Create: `app/javascript/controllers/mention_autocomplete_controller.js`

There are no server-side tests for the Stimulus controller. Verify behavior manually in the browser after implementing. The controller is auto-discovered via `eagerLoadControllersFrom` in `index.js` — no registration needed.

- [ ] **Step 1: Create the controller file**

Create `app/javascript/controllers/mention_autocomplete_controller.js`:

```js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["textarea"]
  static values  = { users: Array }

  connect() {
    this._dropdown  = null
    this._matches   = []
    this._index     = -1
    this._onInput   = this._handleInput.bind(this)
    this._onKeydown = this._handleKeydown.bind(this)
    this._onBlur    = this._handleBlur.bind(this)
    this.textareaTarget.addEventListener("input",   this._onInput)
    this.textareaTarget.addEventListener("keydown", this._onKeydown)
    this.textareaTarget.addEventListener("blur",    this._onBlur)
  }

  disconnect() {
    this.textareaTarget.removeEventListener("input",   this._onInput)
    this.textareaTarget.removeEventListener("keydown", this._onKeydown)
    this.textareaTarget.removeEventListener("blur",    this._onBlur)
    this._removeDropdown()
  }

  // ── private ──────────────────────────────────────────────────────────────

  _handleInput() {
    const fragment = this._currentFragment()
    if (fragment === null) { this._removeDropdown(); return }
    this._matches = this._filter(fragment)
    this._matches.length ? this._showDropdown() : this._removeDropdown()
  }

  _handleKeydown(event) {
    if (!this._dropdown) return
    if (event.key === "ArrowDown") {
      event.preventDefault()
      this._index = Math.min(this._index + 1, this._matches.length - 1)
      this._updateHighlight()
    } else if (event.key === "ArrowUp") {
      event.preventDefault()
      this._index = Math.max(this._index - 1, 0)
      this._updateHighlight()
    } else if (event.key === "Enter") {
      if (this._index >= 0) {
        event.preventDefault()
        this._selectMatch(this._matches[this._index])
      }
    } else if (event.key === "Tab") {
      if (this._index >= 0) {
        event.preventDefault()
        this._selectMatch(this._matches[this._index])
      }
    } else if (event.key === "Escape") {
      this._removeDropdown()
    }
  }

  _handleBlur() {
    // Delay to let a click on a dropdown item register first
    setTimeout(() => this._removeDropdown(), 150)
  }

  _currentFragment() {
    const ta    = this.textareaTarget
    const value = ta.value
    const pos   = ta.selectionStart
    // Walk backward from cursor looking for @ with only \w chars between it and cursor
    const before = value.slice(0, pos)
    const match  = before.match(/@(\w*)$/)
    return match ? match[1] : null
  }

  _filter(fragment) {
    if (fragment === "") return this.usersValue.slice(0, 6)
    const lower = fragment.toLowerCase()
    return this.usersValue
      .filter(u => u.token.toLowerCase().includes(lower))
      .slice(0, 6)
  }

  _showDropdown() {
    this._removeDropdown()
    this._index = -1

    const rect = this.textareaTarget.getBoundingClientRect()
    const ul   = document.createElement("ul")
    ul.setAttribute("role", "listbox")
    ul.style.cssText = [
      "position:fixed",
      `top:${rect.bottom + 2}px`,
      `left:${rect.left}px`,
      "z-index:9999",
      "min-width:160px",
      "max-width:300px"
    ].join(";")
    ul.className = [
      "bg-white dark:bg-stone-800",
      "border border-gray-200 dark:border-stone-600",
      "rounded-md shadow-lg",
      "py-1",
      "text-sm"
    ].join(" ")

    this._matches.forEach((entry, i) => {
      const li = document.createElement("li")
      li.setAttribute("role", "option")
      li.dataset.index = i
      li.textContent   = entry.display
      li.className     = "px-3 py-1.5 cursor-pointer text-stone-800 dark:text-stone-100 hover:bg-blue-50 dark:hover:bg-stone-700"
      li.addEventListener("mousedown", (e) => {
        e.preventDefault()  // prevent textarea blur before click completes
        this._selectMatch(entry)
      })
      ul.appendChild(li)
    })

    document.body.appendChild(ul)
    this._dropdown = ul
  }

  _updateHighlight() {
    if (!this._dropdown) return
    Array.from(this._dropdown.children).forEach((li, i) => {
      if (i === this._index) {
        li.classList.add("bg-blue-100", "dark:bg-stone-600")
      } else {
        li.classList.remove("bg-blue-100", "dark:bg-stone-600")
      }
    })
  }

  _selectMatch(entry) {
    const ta    = this.textareaTarget
    const pos   = ta.selectionStart
    const value = ta.value
    // Find the @fragment before cursor and replace it with @token + space
    const before  = value.slice(0, pos)
    const after   = value.slice(pos)
    const replaced = before.replace(/@(\w*)$/, `@${entry.token} `)
    ta.value = replaced + after
    const newPos = replaced.length
    ta.setSelectionRange(newPos, newPos)
    ta.focus()
    this._removeDropdown()
  }

  _removeDropdown() {
    if (this._dropdown) {
      this._dropdown.remove()
      this._dropdown = null
    }
    this._matches = []
    this._index   = -1
  }
}
```

- [ ] **Step 2: Start the dev server and verify manually**

```bash
bin/dev
```

Open a post that has at least one reply. Log in. In the reply textarea:
- Type `@` — dropdown should appear showing all participants (up to 6)
- Type a letter — dropdown filters by substring match
- Use `↑`/`↓` to navigate, `Enter` to select — `@Token ` inserted at cursor
- Press `Escape` — dropdown dismisses
- Click a name — `@Token ` inserted
- Click "Preview" tab — dropdown dismisses
- `Tab` with highlight — selects item; `Tab` with no highlight — normal focus change

- [ ] **Step 3: Commit**

```bash
git add app/javascript/controllers/mention_autocomplete_controller.js
git commit -m "feat: mention autocomplete Stimulus controller"
```

---

## Task 6: Final verification

- [ ] **Step 1: Run the full test suite**

```bash
bin/rails test
```

Expected: all green, no regressions.

- [ ] **Step 2: Run linter**

```bash
./bin/rubocop
```

Expected: no offenses.

- [ ] **Step 3: Run CI**

```bash
./bin/ci
```

Expected: passes.

- [ ] **Step 4: Commit any lint fixes if needed, then final commit**

```bash
git add -p
git commit -m "chore: rubocop fixes for mention autocomplete"
```
