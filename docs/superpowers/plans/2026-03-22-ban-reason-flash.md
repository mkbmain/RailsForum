# Ban Reason Visible in Flash Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Surface the `BanReason#name` in the flash alert shown to banned users when they attempt to post or reply.

**Architecture:** Add `ban_reason` to `BanChecker` (delegates to `active_ban.ban_reason.name`), then interpolate it into the existing flash string in `Bannable#check_not_banned`. No schema changes required.

**Tech Stack:** Rails 8.1, Minitest

---

## File Map

| File | Change |
|------|--------|
| `app/services/ban_checker.rb` | Add public `ban_reason` method |
| `app/controllers/concerns/bannable.rb` | Update flash string to include reason |
| `test/services/ban_checker_test.rb` | Add test for `ban_reason` |
| `test/controllers/posts_controller_test.rb` | Update flash assertion to include reason |
| `test/controllers/replies_controller_test.rb` | Update flash assertion to include reason |

---

## Task 1: Add `ban_reason` to `BanChecker`

**Files:**
- Modify: `app/services/ban_checker.rb`
- Modify: `test/services/ban_checker_test.rb`

- [ ] **Step 1: Write the failing test**

Open `test/services/ban_checker_test.rb` and add this test before the final `end`:

```ruby
test "ban_reason returns the reason name of the active ban" do
  UserBan.create!(user: @user, ban_reason: @reason, banned_until: 1.day.from_now,
                  banned_by: @user)
  assert_equal "Spam", BanChecker.new(@user).ban_reason
end
```

- [ ] **Step 2: Run the test to confirm it fails**

```bash
bin/rails test test/services/ban_checker_test.rb
```

Expected: the new test fails with `NoMethodError: undefined method 'ban_reason'`.

- [ ] **Step 3: Add `ban_reason` to `BanChecker`**

Open `app/services/ban_checker.rb` and add this method after `banned_until`:

```ruby
def ban_reason
  active_ban&.ban_reason&.name
end
```

The file should now look like:

```ruby
class BanChecker
  def initialize(user)
    @user = user
  end

  def banned?
    active_ban.present?
  end

  def banned_until
    active_ban&.banned_until
  end

  def ban_reason
    active_ban&.ban_reason&.name
  end

  private

  def active_ban
    @active_ban ||= @user.user_bans
                         .where("banned_until >= ?", Time.current)
                         .order(banned_until: :desc)
                         .first
  end
end
```

- [ ] **Step 4: Run the test to confirm it passes**

```bash
bin/rails test test/services/ban_checker_test.rb
```

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add app/services/ban_checker.rb test/services/ban_checker_test.rb
git commit -m "feat: add ban_reason method to BanChecker"
```

---

## Task 2: Surface reason in flash + update controller tests

**Files:**
- Modify: `app/controllers/concerns/bannable.rb`
- Modify: `test/controllers/posts_controller_test.rb`
- Modify: `test/controllers/replies_controller_test.rb`

- [ ] **Step 1: Update existing controller flash assertions to fail**

In `test/controllers/posts_controller_test.rb`, find the test `"POST /posts ban flash includes the expiry date"` (around line 312). Add this assertion at the end of that test:

```ruby
assert_match ban_reason.name, flash[:alert]
```

In `test/controllers/replies_controller_test.rb`, find the test `"POST /posts/:post_id/replies is blocked when user is banned"` (around line 113). Add this assertion after the existing `assert_match /banned until/, flash[:alert]` line:

```ruby
assert_match ban_reason.name, flash[:alert]
```

- [ ] **Step 2: Run the controller tests to confirm new assertions fail**

```bash
bin/rails test test/controllers/posts_controller_test.rb test/controllers/replies_controller_test.rb
```

Expected: the two updated tests fail because the flash does not yet include the reason.

- [ ] **Step 3: Update the flash message in `bannable.rb`**

Open `app/controllers/concerns/bannable.rb`. Replace line 10:

```ruby
flash[:alert] = "You are banned until #{checker.banned_until.strftime("%B %-d, %Y")}."
```

with:

```ruby
flash[:alert] = "You are banned until #{checker.banned_until.strftime("%B %-d, %Y")}. Reason: #{checker.ban_reason}."
```

- [ ] **Step 4: Run the controller tests to confirm they pass**

```bash
bin/rails test test/controllers/posts_controller_test.rb test/controllers/replies_controller_test.rb
```

Expected: all tests pass.

- [ ] **Step 5: Run the full test suite**

```bash
bin/rails test
```

Expected: all green.

- [ ] **Step 6: Commit**

```bash
git add app/controllers/concerns/bannable.rb \
        test/controllers/posts_controller_test.rb \
        test/controllers/replies_controller_test.rb
git commit -m "feat: include ban reason in banned-user flash message"
```
