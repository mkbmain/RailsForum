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
| `Admin::BaseController` | `ApplicationController` | Auth gate (requires moderator). Exposes `require_admin` for role actions. |
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

### No New Models

All data comes from existing models: `User`, `Post`, `Reply`, `UserBan`, `UserRole`, `Role`, `BanReason`.

## Pages

### Dashboard (`GET /admin`)

**Stats cards (4):**
- Total users
- Total posts (including removed)
- Total replies (including removed)
- Currently banned users (active bans: `banned_until >= Time.current`)

**Recent activity feed** (~20 most recent moderation actions, combined and sorted by time):
- Bans issued: "X banned Y for Z hours (reason)"
- Posts removed: "X removed post: [title]"
- Replies removed: "X removed reply on: [post title]"

Each feed item links to the relevant user or content in the admin panel.

### Users List (`GET /admin/users`)

**Table columns:**
- Name (links to `/admin/users/:id`)
- Email
- Role badge (colour-coded: Admin / Sub-admin / Creator)
- Joined date
- Post count (visible posts only)
- Ban status (active ban indicator + expiry time if currently banned)

**Controls:**
- Search input: filters by name or email (server-side)
- Pagination: 20 per page

### User Detail (`GET /admin/users/:id`)

**Header:** Avatar, name, email, role badge, join date.

**Role controls** (admin only, not shown to sub-admins):
- User is a creator → "Promote to Sub-admin" button
- User is a sub-admin → "Demote to Creator" button
- User is the viewing admin themselves → no controls
- User is another admin → no controls
- Promoting to admin or demoting from admin is not available in the UI

**Tabs:**

1. **Posts** — all posts including removed. Removed posts show a "Removed" badge (greyed out) with remover name and timestamp. Each visible post links to the live post.
2. **Replies** — all replies including removed. Same removed treatment as posts. Shows parent post title as context.
3. **Bans received** — full ban history for this user: reason, duration, who issued it, when.
4. **Moderation activity** — only visible if the viewed user is a sub-admin or admin. Three sub-sections:
   - Bans they have issued
   - Posts they have removed
   - Replies they have removed

## Permissions Summary

| Action | Creator | Sub-admin | Admin |
|---|---|---|---|
| Access `/admin` | No | Yes | Yes |
| View dashboard | No | Yes | Yes |
| View users list | No | Yes | Yes |
| View user detail (all content + bans) | No | Yes | Yes |
| Promote creator → sub-admin | No | No | Yes |
| Demote sub-admin → creator | No | No | Yes |
| Promote/demote admin roles | No | No | No (manual only) |

## Permission Enforcement

- `Admin::BaseController#before_action` calls `require_moderator` (existing concern method).
- `promote` and `demote` actions additionally call `require_admin`.
- Same-level protection: admin cannot modify another admin's role. Checked in the controller before applying the change.
- Role changes use `UserRole` join records directly (add or remove).
