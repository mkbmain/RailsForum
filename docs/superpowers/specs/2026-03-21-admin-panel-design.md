# Admin Panel Design

**Date:** 2026-03-21
**Status:** Approved

## Overview

A dedicated `/admin` namespace providing moderation and oversight tools for the forum. Accessible to admins and sub-admins only. Creators (regular users) have no access.

## Role Hierarchy

```
admin > sub_admin > creator
```

- **creator** — base role assigned to every new user on registration. No admin panel access.
- **sub_admin** — read-only admin access: can view all content (including removed), ban history, and moderation activity. Cannot manage roles.
- **admin** — full access: everything sub-admin sees, plus promote/demote between creator and sub-admin. Promoting to admin or demoting from admin is done manually (console/DB) to prevent accidental lockout.

## Architecture

### New Controllers

| Controller | Base | Purpose |
|---|---|---|
| `Admin::BaseController` | `ApplicationController` | Auth gate (requires moderator). |
| `Admin::DashboardController` | `Admin::BaseController` | Stats cards + recent activity feed. |
| `Admin::UsersController` | `Admin::BaseController` | User list, user detail, promote, demote. |

### New Layout

`app/views/layouts/admin.html.erb` — sidebar layout, distinct from the forum layout. Sidebar contains: Admin Panel title, Dashboard link, Users link.

### Routes

```ruby
namespace :admin do
  root to: "dashboard#index"
  resources :users, only: [:index, :show] do
    member do
      patch :promote
      patch :demote
    end
  end
end
```

### Existing Auth Methods

Both `require_moderator` and `require_admin` already exist in `app/controllers/concerns/moderatable.rb` and are included via `ApplicationController`. `Admin::BaseController` inherits these — no new methods needed.

- `require_moderator` — passes for any user where `moderator?` is true, which means sub_admin or admin. Redirects creators and guests to root.
- `require_admin` — passes only for admins. Redirects sub-admins and below to root.

### No New Models

All data comes from existing models: `User`, `Post`, `Reply`, `UserBan`, `UserRole`, `Role`, `BanReason`.

## Pages

### Dashboard (`GET /admin`)

**Stats cards (4):**
- Total users
- Total posts (including removed)
- Total replies (including removed)
- Currently banned users (active bans: `banned_until >= Time.current`)

**Recent activity feed** — 20 most recent moderation actions system-wide, capped at 20 (no pagination). No feed items means "No recent moderation activity." Combined from three sources via union query and sorted by event time descending:

| Source | Event time | Display |
|---|---|---|
| `user_bans` (all) | `banned_from` | "X banned Y for Z hours (reason)" — duration derived from `banned_until - banned_from`, rounded to hours; reason displayed as `ban_reason.name` |
| `posts` where `removed_at IS NOT NULL` | `removed_at` | "X removed post: [title]" |
| `replies` where `removed_at IS NOT NULL` | `removed_at` | "X removed reply on: [post title]" |

Each feed item links to the admin detail page of the actor who performed the action: `banned_by` for bans, `removed_by` for post/reply removals.

The existing `BansController` sets minimum 1 hour, so no permanent bans exist.

### Users List (`GET /admin/users`)

**Table columns:**
- Name (links to `/admin/users/:id`)
- Email
- Role badge (colour-coded: Admin / Sub-admin / Creator)
- Joined date
- Post count (all posts, including removed)
- Ban status: "Banned until [datetime]" if active ban; blank otherwise

**Controls:**
- Search: case-insensitive name or email match (`ILIKE`), ignores leading/trailing whitespace
- Pagination: 20 per page

### User Detail (`GET /admin/users/:id`)

**Header:** Avatar, name, email, role badge, join date. If the user has an active ban (`banned_until >= Time.current`), display "Banned until [datetime]" in the header.

**Role controls** — rendered via `if current_user.admin?` in the view (not a separate `before_action` on `show`). When visible:
- User is a creator → "Promote to Sub-admin" button
- User is a sub-admin → "Demote to Creator" button
- User is the viewing admin themselves → no controls shown
- User is another admin → no controls shown
- Promoting to admin or demoting from admin is not available in the UI

Role changes: permission guards (self-modification, admin target) are checked first, redirecting to `admin_user_path` with an **alert** on failure. If the target already has the intended role after guards pass (concurrent action), treat as a no-op and redirect to `admin_user_path` with an **alert** ("User already has that role"). On success, redirect to `admin_user_path` with a **notice** confirming the role change.

**Tabs** — default tab is Posts. Each tab is independently paginated at 30 per page using separate query params (`posts_page`, `replies_page`, `bans_page`, `activity_page`):

1. **Posts** — all posts including removed. Removed posts show a "Removed" badge (greyed out) with remover name and timestamp. Each visible post links to the live post. Empty state: "No posts."
2. **Replies** — all replies including removed. Same removed treatment as posts. Shows parent post title as context. Empty state: "No replies."
3. **Bans received** — full ban history: reason, duration (derived from `banned_until - banned_from`), who issued it, when. Empty state: "No bans."
4. **Moderation activity** — shown if the viewed user has ever issued a ban or removed any content (regardless of their current role). Both sub-admins and admins can view this tab on any user's detail page. Three sub-sections: bans issued, posts removed, replies removed. Empty state per sub-section: "None."

## Permissions Summary

| Action | Creator | Sub-admin | Admin |
|---|---|---|---|
| Access `/admin` | No | Yes | Yes |
| View dashboard | No | Yes | Yes |
| View users list | No | Yes | Yes |
| View user detail (all content + bans) | No | Yes | Yes |
| View moderation activity tab (any user's profile) | No | Yes | Yes |
| Promote creator → sub-admin | No | No | Yes (not on own profile or another admin) |
| Demote sub-admin → creator | No | No | Yes (not on own profile or another admin) |
| Promote/demote admin roles | No | No | No (manual only) |

## Permission Enforcement

- `Admin::BaseController` runs `before_action :require_login, :require_moderator` — redirects any non-moderator to root.
- `promote` and `demote` actions additionally run `before_action :require_admin`.
- Before applying any role change: check self-modification (redirect with alert if `params[:id]` == `current_user.id`), then check admin target (redirect with alert if target user is an admin).
- Role changes use `UserRole` join records directly: promote adds the `sub_admin` role record; demote removes it. The `creator` role record is never touched.
- Demoting the last remaining sub-admin or moderator is not guarded against — considered out of scope.
