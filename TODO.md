# Forum TODO

## Must Have — Missing Features

- [ ] **Password reset ("Forgot password")**
  No forgot-password flow exists. Users who sign up via email/password and forget it are permanently locked out. Critical gap for any public forum.

- [ ] **Email notifications**
  `NotificationService` is entirely in-app. Users only discover replies/mentions if they actively visit the forum. A forum without email notifications has serious retention problems.

---

## Should Have

- [ ] **Rate limit feedback shows limit but not usage**
  Flash says "Limit is N posts/replies per 15 minutes" but not how many the user has already used.

- [ ] **Post pinning / announcements**
  No way to pin important threads to the top of a category.

- [ ] **User blocking / ignore**
  No way to mute or ignore another user's content.

- [ ] **Search relevance ranking**
  Search is `ILIKE` with no relevance scoring. Results are sorted by activity date. PostgreSQL full-text search (`tsvector`/`tsrank`) would improve quality significantly.

- [ ] **"Removed content" notification is confusing**
  Moderation notification links to a post that just shows `[removed by moderator]` — no context, reason, or post title surfaced to the user.

---

## Nice to Have

- [ ] **Breadcrumb navigation**
  No breadcrumbs anywhere. Inside a post thread there's no clear path back to the category.

- [ ] **Better notification grouping**
  10 replies in one thread → 10 separate notifications. Most forums group these: "10 new replies in [thread title]."

- [ ] **Post bookmarking / favourites**
  No way to save posts to find later.

- [ ] **Quote / reply-to**
  No way to quote a specific reply when responding. Useful for keeping conversation context in long threads.

- [ ] **@mention autocomplete**
  Users must know the exact username. An autocomplete dropdown while typing `@` would help.

- [ ] **Bulk moderation actions**
  Admin must act on each post/reply/user individually. No multi-select.

- [ ] **Audit log**
  Beyond `removed_by` on posts/replies and `banned_by` on bans, there's no unified action log. Promotions, demotions, and un-bans leave no trace.

- [ ] **Open Graph / meta tags**
  No `<meta property="og:...">` tags. Links shared externally show no preview.

- [ ] **Session timeout**
  No session expiration configured. Users stay logged in forever unless they explicitly log out.

- [ ] **Dark mode**
  Tailwind supports it with `dark:` variants but it's not wired up.

- [ ] **Post drafts / auto-save**
  No draft saving. A long post is lost if the tab closes or the session expires.

- [ ] **Mobile layout review**
  Core layout works on mobile but the compose form and long reply threads could use attention on small screens.

---

## Priority Summary

| Priority | Items |
|---|---|
| **Fix now (bugs)** | N+1 notifications, wrong reply count, missing DB indexes, broken empty state |
| **Fix soon (polish)** | Missing name index, inefficient profile pagination |
| **Must have** | Password reset, content reporting, category admin UI, email notifications |
| **Should have** | Markdown preview, ban reason in flash, rate limit usage, post pinning, user blocking, search ranking, soft-delete restore, notification context |
| **Nice to have** | Breadcrumbs, notification grouping, bookmarks, quote/reply-to, @mention autocomplete, bulk moderation, audit log, OG tags, session timeout, dark mode, drafts, mobile polish |
