# Forum

A modern, full-featured internet forum built with Ruby on Rails — designed as a spiritual successor to the classic PHP forums of the early 2000s (phpBB, vBulletin, and friends). This project is an experiment in AI-assisted development and a love letter to the era of threaded discussion boards.

> **Note:** This application was written entirely by [Claude](https://claude.ai) (Anthropic's AI assistant). Every line of code, every feature, every architectural decision — all Claude. This project exists as a learning exercise and a demonstration of what AI-assisted software development looks like in practice.

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

## Philosophy

This project is intentionally a throwback. The forums of the early internet — phpBB boards, vBulletin communities, forum.site.net/index.php — were where a generation learned to have discussions online. They were rough around the edges but full of character.

This is an attempt to rebuild that experience with modern tooling: proper security, real-time updates, and a clean architecture — but the same soul.

It is also an experiment. Every feature was built through conversation with Claude, an AI assistant. The goal was to see how far you could get building a real, production-quality Rails app through AI pair programming. The answer, it turns out, is: pretty far.

---

## License

This software is released into the public domain under the **Unlicense**.

Do whatever you want with it. No restrictions. No attribution required.

**However:** This software is provided "as is", without warranty of any kind, express or implied. The authors accept no responsibility whatsoever for anything this software does or fails to do. Use it at your own risk. We are not liable for any damages, data loss, security incidents, or other consequences arising from the use of this software.

See [https://unlicense.org](https://unlicense.org) for the full Unlicense text.

---

*Built entirely by [Claude](https://claude.ai) — Anthropic's AI assistant — as a learning experiment.*
