# Forum

A modern, full-featured internet forum built with Ruby on Rails — designed as a spiritual successor to the classic PHP forums of the early 2000s (phpBB, vBulletin, and friends). This project is an experiment in AI-assisted development and a love letter to the era of threaded discussion boards.

> **Note:** This application was written entirely by [Claude](https://claude.ai) (Anthropic's AI assistant). Every line of code, every feature, every architectural decision with some human steering — all Claude. This project exists as a learning exercise and a demonstration of what AI-assisted software development looks like in practice.

---

## Features

### Core Forum

- **Posts & Replies** — Create threaded discussions with posts and nested replies, organised into categories
- **Categories** — Organise discussions into topic areas, manageable from the admin panel
- **Markdown support** — Format posts and replies with Markdown
- **Post editing** — Edit your posts and replies; edited content is marked with an "edited" indicator
- **Activity sorting** — Thread list sorted by most recent activity (last reply time)
- **Pagination** — Paginated post and reply listings

### Authentication

- **Email/password registration** — Traditional sign-up with bcrypt password hashing
- **OAuth login** — Sign in with Google or Microsoft via OmniAuth (no password needed)
- **Unified accounts** — Internal and OAuth accounts share the same user model

### Notifications

- **Reply to your post** — Get notified when someone replies to a thread you started
- **Reply in thread** — Get notified when someone replies to a thread you participated in (deduplicated per 24h window to avoid spam)
- **@Mentions** — Tag users with `@username` in a reply; they receive a mention notification
- **Mention autocomplete** — Type `@` in a reply box to get a live autocomplete dropdown of users
- **Moderation notices** — Notified when your content is removed by a moderator
- **Unread badge** — Bell icon in the nav shows unread notification count in real time

### Reactions

- React to posts and replies with emoji: 👍 ❤️ 😂 😮
- One reaction per user per piece of content
- Live-updating reaction counts via Turbo Streams

### Search

- Full-text search across post titles and bodies (case-insensitive)
- Filter search results by category
- Paginated search results

### Moderation

- **Content removal** — Moderators can soft-delete posts and replies (content hidden, not hard-deleted)
- **User banning** — Ban users for a set duration with a selectable reason; banned users cannot post or reply
- **Content flagging** — Users can flag posts and replies (spam, harassment, misinformation, other)
- **Flag queue** — Moderators see a queue of pending flags to review and resolve

### Admin Panel

- **Dashboard** — Overview stats: total users, posts, replies, active bans, pending flags; recent moderation activity feed
- **User management** — Browse all users, assign roles, manage bans
- **Category management** — Create, edit, and delete categories
- **Flag management** — Review and resolve reported content

### Roles

- **Creator** — Automatically assigned to the first registered user; full admin access
- **Admin** — Full moderation and admin panel access
- **Sub-admin** — Moderator-level access without full admin privileges
- **Regular user** — Default role for all new registrations

### Rate Limiting

- Dynamic posting rate limit to discourage spam: new accounts start at 5 posts/replies per 15 minutes
- Limit scales up automatically with account age (up to 15 per 15 minutes for established users)

### Real-time UI

- Built with **Hotwire** (Turbo Drive + Turbo Streams + Stimulus) for SPA-like interactivity without a JavaScript framework
- Reaction updates, notification badges, and form interactions are all live without full page reloads

---

## Tech Stack

| Layer | Technology |
|---|---|
| Framework | Ruby on Rails 8.1 |
| Database | PostgreSQL |
| Frontend | Hotwire (Turbo + Stimulus), Tailwind CSS |
| Asset pipeline | Importmap (no Node.js / npm required) |
| Auth | bcrypt + OmniAuth (Google, Microsoft) |
| Tests | Minitest with fixtures |

---

## Getting Started

### Prerequisites

- Ruby (see `.ruby-version`)
- PostgreSQL 9.3+
- Bundler

---

### 1. PostgreSQL Setup

You need a running PostgreSQL server and a role (user) that can create databases.

#### Install PostgreSQL

**Ubuntu/Debian:**
```bash
sudo apt install postgresql postgresql-contrib
sudo systemctl start postgresql
```

**macOS (Homebrew):**
```bash
brew install postgresql@16
brew services start postgresql@16
```

**Arch Linux:**
```bash
sudo pacman -S postgresql
sudo systemctl start postgresql
```

#### Create a database role

By default, Rails connects using your OS username as the PostgreSQL role. If that role doesn't exist yet, create it:

```bash
sudo -u postgres createuser --superuser $USER
```

Or, to create a dedicated `forum` role with a password (recommended for production):

```bash
sudo -u postgres psql -c "CREATE ROLE forum WITH LOGIN PASSWORD 'yourpassword' CREATEDB;"
```

If you use a named role, uncomment and fill in the `username` and `password` lines in `config/database.yml`:

```yaml
development:
  <<: *default
  database: forum_development
  username: forum
  password: yourpassword
  host: localhost
```

For production, **never** put credentials in the file — use an environment variable instead:

```bash
export DATABASE_URL="postgres://forum:yourpassword@localhost/forum_production"
# or the app-specific variable:
export FORUM_DATABASE_PASSWORD="yourpassword"
```

---

### 2. Application Setup

```bash
git clone <repo-url>
cd forum
bundle install
```

---

### 3. Create the Databases

This creates `forum_development` and `forum_test`:

```bash
bin/rails db:create
```

---

### 4. Run Migrations

This app uses `db/structure.sql` (not `schema.rb`) because it relies on PostgreSQL-specific features like `CHECK` constraints. The migrate command loads the schema and runs all pending migrations:

```bash
bin/rails db:migrate
```

To check the status of migrations at any time:

```bash
bin/rails db:migrate:status
```

To roll back the last migration:

```bash
bin/rails db:rollback
```

To roll back multiple steps:

```bash
bin/rails db:rollback STEP=3
```

---

### 5. Seed the Database

The seed file populates the required lookup tables that the app depends on: roles, auth providers, content types, ban reasons, and default categories. **You must run this before using the app.**

```bash
bin/rails db:seed
```

This creates:
- **Roles:** `creator`, `sub_admin`, `admin`
- **Providers:** `google`, `microsoft`, `internal`
- **Content types:** `Post`, `Reply`
- **Ban reasons:** Spam, Harassment, Against Guidelines, Other
- **Default categories:** Tech, Life Style, Off Topic, Other

The first user to register will automatically be assigned the `creator` role (full admin access).

To reset the database entirely and re-seed from scratch:

```bash
bin/rails db:reset   # drops, creates, migrates, and seeds
```

Or step by step:

```bash
bin/rails db:drop db:create db:migrate db:seed
```

---

### 6. Start the Dev Server

```bash
bin/dev
```

`bin/dev` starts the Rails server and the Tailwind CSS watcher together. Visit `http://localhost:3000`.

### Running Tests

```bash
# Full test suite
bin/rails test

# Single file
bin/rails test test/models/user_test.rb

# Single test by line number
bin/rails test test/models/user_test.rb:42
```

### Linting & Security

```bash
./bin/rubocop         # Style linting (Rails Omakase)
./bin/brakeman        # Security static analysis
./bin/bundler-audit   # Dependency vulnerability check
./bin/ci              # Full CI pipeline (lint + security + tests)
```

### OAuth Setup (optional)

To enable Google/Microsoft login, set the following environment variables:

```
GOOGLE_CLIENT_ID=...
GOOGLE_CLIENT_SECRET=...
MICROSOFT_CLIENT_ID=...
MICROSOFT_CLIENT_SECRET=...
```

---

## Philosophy & Origin

This project is intentionally a throwback. The forums of the early internet — phpBB boards, vBulletin communities, `forum.site.net/index.php` — were where a generation learned to have discussions online. They were rough around the edges but full of character. This is an attempt to rebuild that experience with modern tooling: proper security, real-time updates, and a clean architecture — but the same soul.

It is also an experiment in AI-assisted software development. The human owner of this project described what they wanted at a high level. Claude (Anthropic's AI assistant) made every architectural decision with in reason few push backs, chose every pattern, wrote every line of code, and designed every feature — with only minimal course corrections from the human along the way.

---

### PostgreSQL + `structure.sql` over `schema.rb`

Rails defaults to `schema.rb`, which is database-agnostic. This app deliberately uses `db/structure.sql` instead. The reason: PostgreSQL `CHECK` constraints were chosen to enforce the 1000-character body limit on posts and replies at the database level — not just in Rails validations. `schema.rb` cannot represent those constraints, so `structure.sql` was the correct choice. The constraint lives in the database and will be enforced even if someone bypasses Rails entirely.

### Service objects for cross-cutting logic

Rather than stuffing complex logic into models or controllers, two service objects were introduced:

- **`NotificationService`** — handles all notification fan-out when a reply is created. It's designed as a clean boundary: callers invoke a single class method, and in future the internals could be swapped for an event bus with no changes elsewhere in the app.
- **`PostRateLimiter`** — encapsulates the dynamic rate-limit calculation. New accounts are limited to 5 posts+replies per 15 minutes; that limit scales up automatically with account age (weeks and months of membership), capping at 15. The algorithm lives in one place, tested in isolation.
- **`BanChecker`** — a thin service that checks whether a user has an active ban. Extracted so the ban check logic is not duplicated between posts and replies.

### Controller concerns via `prepend`

Ban checking and rate limiting are enforced via `Bannable` and `RateLimitable` controller concerns, prepended (not included) into `PostsController` and `RepliesController`. Prepend was chosen so the concern's `before_action` runs before the controller's own callbacks — a subtle but important distinction that prevents any possibility of the check being bypassed by controller-level ordering.

### Soft deletion, not hard deletion

When a moderator removes a post or reply, the content is soft-deleted: a `removed_at` timestamp is set and a `removed_by` foreign key recorded. The record stays in the database. This was a deliberate choice over hard deletion for several reasons: audit trail, the ability to restore content (a restore action exists), and the ability to notify the content owner of the removal. Hard deletion would lose all of that.

### Polymorphic reactions and flags

Both reactions (👍 ❤️ 😂 😮) and content flags (spam, harassment, etc.) use polymorphic associations so they work identically on both posts and replies without duplicating tables or logic. `Reaction` belongs to `reactionable`, `Flag` belongs to its `flaggable_id` + `content_type`. A `ContentType` lookup table was introduced rather than relying on Rails' string-based polymorphic type column for flags, giving a stable numeric FK for the constraint.

### Notification deduplication

The notification system has a subtle 24-hour deduplication window for "reply in thread" notifications. If you've already been notified that a thread you participated in has a new reply, you won't be notified again for the same thread for another 24 hours. This prevents inbox flood in active threads. The logic lives entirely in `NotificationService` and was designed intentionally — not as an afterthought.

### Hotwire over a JavaScript framework

No React, no Vue, no npm. The entire real-time UI — live reaction counts, notification badges, Turbo Stream form responses, mention autocomplete — is built with Hotwire (Turbo + Stimulus) and served over importmap. This keeps the asset pipeline simple and the deployment story clean. The tradeoff is a less flexible client, but for a forum that's a fine tradeoff.

### Roles as a table, not an enum

User roles (`creator`, `admin`, `sub_admin`) are stored in a `roles` table with a join table `user_roles`, not as an enum column on `User`. This supports multiple roles per user and makes the role system extensible without a migration to add enum values. The `creator` role is assigned automatically to the first user who registers.

### Session timeout in the application layer

Idle session timeout (defaulting to a configurable `SESSION_TIMEOUT_MINUTES`) is enforced in `ApplicationController`, not at the web server or rack layer. A `last_active_at` timestamp is written to the session on each request; if the gap exceeds the limit, the session is cleared and the user is redirected to login. This was chosen over rack-level timeout because it gives the app full control over the user-facing message and redirect behaviour.

### Dark mode via Tailwind `dark:` variant + localStorage

Dark mode state is stored in `localStorage` and applied via a `<script>` tag in `<head>` (before the page renders) to prevent the white flash on load. A Stimulus controller handles the toggle and keeps `localStorage` in sync. Tailwind's `dark:` variant classes are used throughout — no CSS custom properties or separate stylesheets. The `darkMode: 'class'` strategy was chosen over `'media'` to give the user explicit control independent of their OS preference.

---

## License

This software is released into the public domain under the **Unlicense**.

Do whatever you want with it. No restrictions. No attribution required.

**However:** This software is provided "as is", without warranty of any kind, express or implied. The authors accept no responsibility whatsoever for anything this software does or fails to do. Use it at your own risk. We are not liable for any damages, data loss, security incidents, or other consequences arising from the use of this software.

See [https://unlicense.org](https://unlicense.org) for the full Unlicense text.

---

*Built entirely by [Claude](https://claude.ai) — Anthropic's AI assistant — as a learning experiment.*
