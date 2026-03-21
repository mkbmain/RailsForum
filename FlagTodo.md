# Content Flagging — Continuation State

**Date paused:** 2026-03-21
**Branch:** main
**Last commit:** 50489d2 (feat: seed content_types in seeds.rb)
**Base SHA (before any flagging work):** a8635e8

## Reference Files

- Spec: `docs/superpowers/specs/2026-03-21-content-flagging-design.md`
- Plan: `docs/superpowers/plans/2026-03-21-content-flagging.md`

---

## Progress

- [x] **Task 1: Migration** — `db/migrate/20260321021906_create_content_types_and_flags.rb`
  - `content_types` table (integer PK, varchar(50) name, no timestamps, seeded via INSERT in migration)
  - `flags` table: integer PK, bigint user_id, smallint content_type_id, bigint flaggable_id, smallint reason, datetime resolved_at, bigint resolved_by_id, timestamps
  - Indexes: unique `(user_id, content_type_id, flaggable_id)`, `(content_type_id, flaggable_id)`, partial `(created_at) WHERE resolved_at IS NULL`
  - FK constraints: `user_id → users`, `content_type_id → content_types`, `resolved_by_id → users`
  - `db/seeds.rb` updated with `ContentType.find_or_create_by!(id: 1)` and `find_or_create_by!(id: 2)`
  - Passed spec compliance ✅ and code quality ✅ review

- [ ] **Task 2: ContentType + Flag models + fixture + model tests**
  - Create `app/models/content_type.rb`
  - Create `app/models/flag.rb`
  - Create `test/fixtures/content_types.yml`
  - Create `test/models/flag_test.rb`

- [ ] **Task 3: has_many :flags on Post, Reply, User**
  - Modify `app/models/post.rb`
  - Modify `app/models/reply.rb`
  - Modify `app/models/user.rb` (dependent: :destroy)

- [ ] **Task 4: Routes**
  - Modify `config/routes.rb`
  - `resources :flags, only: [:create]` nested under `resources :posts` and under `resources :replies` inside posts
  - `namespace :admin` → `resources :flags, only: [:index]` with `member { patch :dismiss }`

- [ ] **Task 5: FlagsController (user-facing) + tests**
  - Create `app/controllers/flags_controller.rb` — `create` action only
  - Create `test/controllers/flags_controller_test.rb`

- [ ] **Task 6: Flag button on post show page**
  - Modify `app/views/posts/show.html.erb`
  - `<details>`/`<summary>` dropdown, 4 reason radio buttons, shown only to logged-in users who haven't flagged yet; disabled "Flagged ✓" if already flagged; hidden on soft-deleted content

- [ ] **Task 7: Flag button on reply partial**
  - Modify `app/views/replies/_reply.html.erb`
  - Same pattern as post flag button

- [ ] **Task 8: Admin::FlagsController + tests**
  - Create `app/controllers/admin/flags_controller.rb` — `index` + `dismiss` actions
  - Create `test/controllers/admin/flags_controller_test.rb`
  - `index`: limit+1 pagination (20/page), composite-keyed `@flaggables` hash to avoid N+1 and id collision
  - `dismiss`: sets `resolved_at: Time.current`, `resolved_by: current_user`; already-resolved → "Already resolved"

- [ ] **Task 9: Admin flags queue view**
  - Create `app/views/admin/flags/index.html.erb`
  - Table: content type badge, truncated snippet (nil=removed, removed?=soft-deleted badge, live=body), reporter, reason, time ago, link, Dismiss `button_to`
  - Empty state: "No pending reports."
  - Pagination: prev/next links

- [ ] **Task 10: Admin dashboard — pending count + nav link**
  - Modify `app/controllers/admin/dashboard_controller.rb` — add `@pending_flags_count`
  - Modify `app/views/admin/dashboard/index.html.erb` — "Pending Reports" stat with link to `/admin/flags`
  - Modify `app/views/layouts/admin.html.erb` — add "Reports" nav link

- [ ] **Task 11: Run CI and final check**
  - `bin/ci`

---

## Key Design Decisions

- `content_type_id` is a smallint FK (not a Rails polymorphic string column)
- `ContentType::CONTENT_POST = 1`, `ContentType::CONTENT_REPLY = 2`
- One flag per user per content item enforced at DB (unique index) + model (uniqueness validation)
- `Flag#flaggable` is a manual method (not AR association) — returns nil if hard-deleted, soft-deleted record if removed
- `has_many :flags` on Post/Reply uses scoped lambda: `-> { where(content_type_id: ContentType::CONTENT_POST) }` with `foreign_key: :flaggable_id`
- Admin index N+1 avoided via composite-keyed hash: `@flaggables[[content_type_id, flaggable_id]]` — keyed on pair to prevent Post/Reply id collision
- Reply flags scoped through parent post (mirrors ReactionsController pattern): `@post.replies.visible.find_by(id: params[:reply_id])`
- No flags.yml fixture — tests use setup blocks (no users.yml fixture exists)
- Both `admin?` and `sub_admin?` access admin flags via inherited `require_moderator`
- `button_to` required for Dismiss (CSRF token needed for PATCH)

## Code Quality Notes (from Task 1 review)

- Migration has raw INSERT + seeds.rb both seeding content_types — harmless for static table, both are no-ops on repeat
- No `on_delete:` on FK constraints — plan doesn't specify; `resolved_by_id` could use `:nullify` if user deletion is ever a concern
- `content_types` sequence won't auto-advance past seeded rows — table is static, never auto-inserted at runtime
