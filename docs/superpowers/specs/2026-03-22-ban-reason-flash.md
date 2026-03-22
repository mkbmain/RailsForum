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

## Tests

- `test/services/ban_checker_test.rb` — add: `ban_reason returns the reason name of the active ban`
- Controller tests for `PostsController` or `RepliesController` — update existing banned-user flash assertion to include the reason string.

## Out of Scope

- i18n / humanised reason labels
- Separate banned-user page or detailed messaging
