# Ban Reason Visible to Banned User

## Goal

Show the ban reason name in the flash alert when a banned user is blocked from posting or replying.

## Current Behaviour

`Bannable#check_not_banned` sets:
```
"You are banned until [date]."
```
The `BanReason` name is never surfaced.

## Desired Behaviour

```
"You are banned until [date]. Reason: [BanReason#name]."
```

## Changes

### `app/services/ban_checker.rb`

Add one public method:

```ruby
def ban_reason
  active_ban&.ban_reason&.name
end
```

### `app/controllers/concerns/bannable.rb`

Update the flash line:

```ruby
flash[:alert] = "You are banned until #{checker.banned_until.strftime("%B %-d, %Y")}. Reason: #{checker.ban_reason}."
```

## Null safety note

`ban_reason` is only called inside the `if checker.banned?` branch in `bannable.rb`, so `active_ban` is always non-nil at that point. `UserBan#ban_reason` is a required `belongs_to` (no `optional: true`), enforced by the DB foreign key, so the safe-navigation operators are purely defensive. The flash string will never contain "Reason: .".

When a user has multiple active bans, `active_ban` returns the one with the latest `banned_until` (per `BanChecker`'s existing ordering). The reason shown is that ban's reason — intentional, consistent with how `banned_until` is already selected.

## Tests

### `test/services/ban_checker_test.rb`

Add one test:
```ruby
test "ban_reason returns the reason name of the active ban" do
  UserBan.create!(user: @user, ban_reason: @reason, banned_until: 1.day.from_now, banned_by: @user)
  assert_equal "Spam", BanChecker.new(@user).ban_reason
end
```

### `test/controllers/posts_controller_test.rb`

Update the existing `"POST /posts ban flash includes the expiry date"` test to also assert:
```ruby
assert_match @reason.name, flash[:alert]
```

### `test/controllers/replies_controller_test.rb`

Update the existing banned-user flash test similarly.

## Out of Scope

- i18n / humanised reason labels
- Separate banned-user page or detailed messaging
