# Roles Design

**Date:** 2026-03-17
**Status:** Approved

## Overview

Introduce a many-to-many role system with three roles: `creator` (every user), `sub_admin`, and `admin`. Roles gate content moderation (soft-delete posts/replies with tombstone) and ban issuance (sub admins up to 48 hours, admins unlimited). Role assignment is manual via console/SQL for now; an admin panel is planned separately.

---

## Database

### `roles` table

Lookup table of available roles.

| Column | Type | Constraints |
|---|---|---|
| id | smallint | PK |
| name | string | not null, unique |
| created_at | datetime | not null |
| updated_at | datetime | not null |

Seeded with: `creator`, `sub_admin`, `admin`.

### `user_roles` join table

No `updated_at` — role assignments are immutable (see model note).

| Column | Type | Constraints |
|---|---|---|
| id | int | PK |
| user_id | bigint | not null, FK → users |
| role_id | smallint | not null, FK → roles |
| created_at | datetime | not null |

Unique index on `(user_id, role_id)` to prevent duplicate assignments.

### Changes to `posts`

| Column | Type | Constraints |
|---|---|---|
| removed_at | datetime | nullable |
| removed_by_id | bigint | nullable, FK → users |

### Changes to `replies`

| Column | Type | Constraints |
|---|---|---|
| removed_at | datetime | nullable |
| removed_by_id | bigint | nullable, FK → users |

### Changes to `user_bans`

| Column | Type | Constraints |
|---|---|---|
| banned_by_id | bigint | **nullable**, FK → users |

`banned_by_id` is nullable in the database because existing ban rows predate this feature and have no issuer. All bans created after this feature ships are required to have a `banned_by` (enforced at the model level). A data migration backfills no value for historical rows — they remain null.

### Changes to `ban_reasons`

Seed gains `"Other"`.

### Migration sketch

```ruby
create_table :roles, id: :smallint do |t|
  t.string :name, null: false
  t.timestamps
end
add_index :roles, :name, unique: true

create_table :user_roles, id: :integer do |t|
  t.bigint   :user_id, null: false
  t.column   :role_id, :smallint, null: false
  t.datetime :created_at, null: false
end
add_index :user_roles, [:user_id, :role_id], unique: true
add_foreign_key :user_roles, :users, column: :user_id
add_foreign_key :user_roles, :roles, column: :role_id

add_column :posts, :removed_at,    :datetime
add_column :posts, :removed_by_id, :bigint
add_foreign_key :posts, :users, column: :removed_by_id

add_column :replies, :removed_at,    :datetime
add_column :replies, :removed_by_id, :bigint
add_foreign_key :replies, :users, column: :removed_by_id

add_column :user_bans, :banned_by_id, :bigint
add_foreign_key :user_bans, :users, column: :banned_by_id
```

Note: `t.references` with a custom `type:` is silently ignored by Rails for FK generation. All FK columns in `user_roles` are declared explicitly and foreign keys added separately.

---

## Models

### `Role` (`app/models/role.rb`)

```ruby
class Role < ApplicationRecord
  CREATOR   = "creator"
  SUB_ADMIN = "sub_admin"
  ADMIN     = "admin"

  has_many :user_roles
  has_many :users, through: :user_roles

  validates :name, presence: true, uniqueness: true
end
```

### `UserRole` (`app/models/user_role.rb`)

```ruby
class UserRole < ApplicationRecord
  self.record_timestamps = false  # table has created_at only, no updated_at

  belongs_to :user
  belongs_to :role
end
```

### `User` additions

`has_role?` uses `roles.exists?` to push the check to the database rather than loading the full association. This avoids N+1 queries regardless of whether roles are eager-loaded.

```ruby
has_many :user_roles
has_many :roles, through: :user_roles

after_create :assign_creator_role

def has_role?(name)
  roles.exists?(name: name)
end

def creator?   = has_role?(Role::CREATOR)
def sub_admin? = has_role?(Role::SUB_ADMIN)
def admin?     = has_role?(Role::ADMIN)
def moderator? = sub_admin? || admin?

private

def assign_creator_role
  roles << Role.find_by!(name: Role::CREATOR)
end
```

`find_by!` requires role seeds to have run before any `User.create!` call. This is guaranteed in production (seeds always run before the app is used) and in test setup (see Seeds section). The `roles` table is a small, static lookup table — it is not appropriate for `find_or_create_by!` which is non-atomic under concurrent load and would silently create duplicate role names if the unique index were absent.

### `Post` additions

```ruby
belongs_to :removed_by, class_name: "User", optional: true

scope :visible, -> { where(removed_at: nil) }

def removed? = removed_at.present?
```

### `Reply` additions

```ruby
belongs_to :removed_by, class_name: "User", optional: true

scope :visible, -> { where(removed_at: nil) }

def removed? = removed_at.present?
```

`Reply.visible` is defined so that reply counts in the index (and any future query) exclude removed replies.

The existing `after_destroy :recalculate_post_last_replied_at` callback only fires on hard-delete, never on a soft-delete. When a moderator removes a reply, `last_replied_at` on the post would otherwise retain the removed reply's timestamp (incorrect sort order on the index). The `RepliesController#destroy` moderator path must therefore manually recalculate:

```ruby
post.update_column(:last_replied_at, post.replies.visible.maximum(:created_at))
```

This replaces the old `after_destroy` logic for the soft-delete case only. The existing hard-delete path (`after_destroy` callback) remains unchanged for owner-deleted replies.

### `UserBan` additions

```ruby
belongs_to :banned_by, class_name: "User", optional: true
validates :banned_by, presence: true, on: :create
```

`on: :create` ensures the presence validation only fires for new bans. Historical bans with `banned_by_id = NULL` remain valid records.

---

## Controller Concern: `Moderatable`

Named `Moderatable` to match the existing `Bannable` convention.

`app/controllers/concerns/moderatable.rb`

```ruby
module Moderatable
  extend ActiveSupport::Concern

  private

  def require_moderator
    redirect_to root_path, alert: "Not authorized." and return unless current_user&.moderator?
  end

  def require_admin
    redirect_to root_path, alert: "Not authorized." and return unless current_user&.admin?
  end

  def can_moderate?(target_user)
    return false unless current_user&.moderator?
    return false if current_user == target_user  # cannot moderate yourself
    return true if current_user.admin?
    # Sub admins can only act on creators (not other sub_admins or admins)
    !target_user.sub_admin? && !target_user.admin?
  end
end
```

`ApplicationController` gains `include Moderatable`.

### `require_login` fix

Rails halts the filter chain when a response is committed (i.e., `redirect_to` or `render` is called), so a subsequent before_action will not execute after a redirect. However, if two before_actions both reach a `redirect_to` in the same request cycle (e.g., due to a future filter ordering change), Rails raises `AbstractController::DoubleRenderError`. The `and return` pattern is the standard defensive guard against this. The existing `require_login` is missing it:

```ruby
def require_login
  redirect_to login_path, alert: "Please log in first." and return unless logged_in?
end
```

---

## Content Removal

### `PostsController` — new `destroy` action

```ruby
before_action :require_login,     only: [:destroy]
before_action :require_moderator, only: [:destroy]

def destroy
  @post = Post.find(params[:id])
  unless can_moderate?(@post.user)
    redirect_to @post, alert: "Not authorized to remove this post."
    return
  end
  @post.update!(removed_at: Time.current, removed_by: current_user)
  redirect_to @post, notice: "Post removed."
end
```

Route: `resources :posts` already covers `DELETE /posts/:id`.

### `RepliesController#destroy` — extended

The existing owner hard-delete path is preserved. The moderator soft-delete path is checked first; if the current user is not a moderator (or the hierarchy check fails), fall through to the owner check.

```ruby
def destroy
  @post  = Post.find(params[:post_id])
  @reply = @post.replies.find(params[:id])

  if current_user.moderator? && can_moderate?(@reply.user)
    @reply.update!(removed_at: Time.current, removed_by: current_user)
    redirect_to @post, notice: "Reply removed."
  elsif @reply.user == current_user
    @reply.destroy
    redirect_to @post, notice: "Reply deleted."
  else
    redirect_to @post, alert: "Not authorized.", status: :see_other
  end
end
```

### Views

- **Post body / reply body:** if `removed?`, display `[removed by moderator]` in place of body content
- **Moderators only:** removed content shown greyed out with "Removed by [name] on [date]" beneath
- **Post title:** always visible even when post is removed
- **Index:** removed posts excluded via `Post.visible` scope; reply counts use `replies.visible.count`
- **Show (direct URL):** a removed post remains accessible at its URL; the body is tombstoned but the page renders normally. This is intentional — the title and thread context remain visible

---

## Banning UI

### Routes

```ruby
resources :users, only: [] do
  resources :bans, only: [:new, :create]
end
```

### `BansController` (`app/controllers/bans_controller.rb`)

```ruby
class BansController < ApplicationController
  before_action :require_login
  before_action :require_moderator
  before_action :set_target_user
  before_action :check_hierarchy

  def new
    @ban = UserBan.new
    @ban_reasons = BanReason.all.order(:name)
    @max_hours = current_user.admin? ? nil : 48
  end

  def create
    duration_hours = params[:duration_hours].to_i
    if duration_hours < 1
      redirect_to new_user_ban_path(@target_user), alert: "Duration must be at least 1 hour."
      return
    end
    if !current_user.admin? && duration_hours > 48
      redirect_to new_user_ban_path(@target_user), alert: "Sub admins can ban for 48 hours maximum."
      return
    end
    ban_reason = BanReason.find_by(id: params[:ban_reason_id])
    unless ban_reason
      redirect_to new_user_ban_path(@target_user), alert: "Please select a valid ban reason."
      return
    end
    @ban = UserBan.new(
      user:        @target_user,
      ban_reason:  ban_reason,
      banned_by:   current_user,
      banned_until: Time.current + duration_hours.hours
    )
    if @ban.save
      redirect_to root_path, notice: "#{@target_user.name} has been banned."
    else
      @ban_reasons = BanReason.all.order(:name)
      @max_hours = current_user.admin? ? nil : 48
      render :new, status: :unprocessable_entity
    end
  end

  private

  def set_target_user
    @target_user = User.find(params[:user_id])
  end

  def check_hierarchy
    unless can_moderate?(@target_user)
      redirect_to root_path, alert: "Not authorized to ban this user." and return
    end
  end
end
```

### Ban form trigger

A "Ban user" link is shown next to posts/replies for users the current moderator `can_moderate?`. Links to `new_user_ban_path(user_id: author.id)`.

---

## Seeds

Roles must be seeded before users, since `assign_creator_role` runs on `User.create!`. Although `find_or_create_by!` in the callback handles an unseeded DB gracefully, explicit ordering in seeds is cleaner.

```ruby
# Roles — must run before any user seeds
[Role::CREATOR, Role::SUB_ADMIN, Role::ADMIN].each do |name|
  Role.find_or_create_by!(name: name)
end

# Ban reasons
["Spam", "Harassment", "Against Guidelines", "Other"].each do |name|
  BanReason.find_or_create_by!(name: name)
end
```

**Backfill for existing users:** The `after_create` callback only fires on new records. A data migration backfills the `creator` role for all existing users who have no roles:

```ruby
creator = Role.find_or_create_by!(name: Role::CREATOR)
User.left_joins(:user_roles).where(user_roles: { id: nil }).find_each do |user|
  user.roles << creator
end
```

**Test suite:** Every existing test that calls `User.create!` will trigger `assign_creator_role`, which calls `Role.find_by!(name: Role::CREATOR)`. Without a matching row in the test DB, all such tests will raise `ActiveRecord::RecordNotFound`. The fix is to add a `roles` fixture at `test/fixtures/roles.yml`:

```yaml
creator:
  id: 1
  name: creator

sub_admin:
  id: 2
  name: sub_admin

admin:
  id: 3
  name: admin
```

Rails loads all fixtures before each test, so this ensures the `creator` role row exists before any `User.create!` runs. No changes to existing test files are needed.

### Role assignment (manual, console/SQL)

```ruby
user = User.find_by(email: "admin@example.com")
user.roles << Role.find_by(name: Role::ADMIN)
```

---

## What Is Out of Scope

- Admin panel UI for promoting/demoting users (planned separately)
- Appealing content removals or bans
- Moderator audit log UI (data is stored, not yet surfaced)
- Removing the creator role from a user
- Permanent bans with no expiry date
