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
| banned_by_id | bigint | not null, FK → users |

### Changes to `ban_reasons`

Seed gains `"Other"`.

### Migration sketch

```ruby
create_table :roles, id: :smallint do |t|
  t.string :name, null: false
  t.timestamps
end
add_index :roles, :name, unique: true

create_table :user_roles, id: :int do |t|
  t.references :user, null: false, foreign_key: true, type: :bigint
  t.references :role, null: false, foreign_key: true, type: :smallint
  t.datetime :created_at, null: false
end
add_index :user_roles, [:user_id, :role_id], unique: true

add_column :posts,  :removed_at,     :datetime
add_column :posts,  :removed_by_id,  :bigint
add_foreign_key :posts,  :users, column: :removed_by_id

add_column :replies, :removed_at,    :datetime
add_column :replies, :removed_by_id, :bigint
add_foreign_key :replies, :users, column: :removed_by_id

add_column :user_bans, :banned_by_id, :bigint, null: false
add_foreign_key :user_bans, :users, column: :banned_by_id
```

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
  belongs_to :user
  belongs_to :role
end
```

### `User` additions

```ruby
has_many :user_roles
has_many :roles, through: :user_roles

after_create :assign_creator_role

def has_role?(name)
  roles.any? { |r| r.name == name }
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

### `Post` additions

```ruby
belongs_to :removed_by, class_name: "User", optional: true

scope :visible, -> { where(removed_at: nil) }

def removed? = removed_at.present?
```

### `Reply` additions

```ruby
belongs_to :removed_by, class_name: "User", optional: true

def removed? = removed_at.present?
```

### `UserBan` additions

```ruby
belongs_to :banned_by, class_name: "User"
validates :banned_by, presence: true
```

---

## Controller Concern: `Authorizable`

`app/controllers/concerns/authorizable.rb`

```ruby
module Authorizable
  extend ActiveSupport::Concern

  private

  def require_moderator
    redirect_to root_path, alert: "Not authorized." unless current_user&.moderator?
  end

  def require_admin
    redirect_to root_path, alert: "Not authorized." unless current_user&.admin?
  end

  def can_moderate?(target_user)
    return false unless current_user&.moderator?
    return true if current_user.admin?
    # Sub admins can only act on creators (not other sub_admins or admins)
    !target_user.sub_admin? && !target_user.admin?
  end
end
```

`ApplicationController` gains `include Authorizable`.

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

Current behaviour (owner hard-delete) is preserved. Moderator path added:

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
- **Index:** removed posts excluded via `Post.visible` scope

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
    if !current_user.admin? && duration_hours > 48
      redirect_to new_user_ban_path(@target_user), alert: "Sub admins can ban for 48 hours maximum."
      return
    end
    @ban = UserBan.new(
      user:       @target_user,
      ban_reason: BanReason.find(params[:ban_reason_id]),
      banned_by:  current_user,
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
      redirect_to root_path, alert: "Not authorized to ban this user."
    end
  end
end
```

### Ban form trigger

A "Ban user" link is shown next to posts/replies for users the current moderator `can_moderate?`. Links to `new_user_ban_path(user_id: author.id)`.

---

## Seeds

```ruby
# Roles
[Role::CREATOR, Role::SUB_ADMIN, Role::ADMIN].each do |name|
  Role.find_or_create_by!(name: name)
end

# Ban reasons
["Spam", "Harassment", "Against Guidelines", "Other"].each do |name|
  BanReason.find_or_create_by!(name: name)
end
```

**Backfill:** existing users at migration time are not auto-assigned the creator role by the `after_create` callback. A data migration assigns `creator` to all existing users with no roles.

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
