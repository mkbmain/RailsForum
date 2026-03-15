# Homepage Redesign — Forest Community

**Date:** 2026-03-15
**Scope:** Post index page (`posts#index`) + navigation bar
**Framework:** Rails + Tailwind CSS v4 + Hotwire

---

## Goal

Redesign the forum homepage to feel warm, inviting, and community-focused. The current design is minimal but lacks personality. The new design uses an earthy teal/green palette, a two-column layout with a sticky category sidebar, and a spacious single-column post feed with rich post previews.

---

## Color & Typography

| Element | Tailwind class / value |
|---|---|
| Page background | `bg-stone-50` |
| Surface (cards) | `bg-white border border-stone-200` |
| Primary color | `teal-700` |
| Primary light | `teal-100` |
| Accent / hover | `teal-600` |
| Text primary | `text-stone-900` |
| Text secondary | `text-stone-500` |
| Category badges | `bg-teal-100 text-teal-800 text-xs font-medium px-2 py-0.5 rounded-full` |
| Nav background | `bg-teal-700` |

Font: system font stack (no change). Post titles use `font-semibold`, body text `text-base`.

---

## Navigation Bar

- `bg-teal-700` full-width bar with white text
- Left: "Forum" logo/brand link
- Right (logged in): "New Post" button + user avatar (circle 32px) + display name + Logout button
- Right (logged out): Login + Sign Up links
- "New Post" button — `bg-white text-teal-700 font-semibold rounded-lg px-4 py-1.5 hover:bg-teal-50` — only shown when `logged_in?`
- Flash messages rendered below the nav, full width, then constrained to the same max-width container as the two-column layout

---

## Page Layout

Two-column layout on `lg:` screens, stacks to single column on mobile.

```
[ Sidebar 256px ] [ Feed (max-w-2xl, flex-1) ]
```

### Sidebar

- Sticky (`sticky top-4`)
- Heading: "Categories" in `text-xs font-semibold uppercase tracking-wide text-stone-400`
- "All Posts" link + one link per category
- Active state: `bg-teal-50 text-teal-700 font-semibold rounded-lg` — "All Posts" is active when `params[:category].blank?`; a category link is active when `params[:category].to_i == category.id`
- Inactive state: `text-stone-600 hover:bg-stone-100 rounded-lg`

### Feed

- Each post rendered as a white card: `bg-white border border-stone-200 rounded-xl shadow-sm p-5`
- Hover state: `hover:border-teal-300 hover:shadow-md transition-all`
- Cards separated by `space-y-4`

---

## Post Card Anatomy

```
[ Category badge ]  [ Timestamp (right-aligned) ]
[ Post title (link) ]
[ Body preview — 2 lines, clipped ]
─────────────────────────────────────────────
[ Avatar ] [ Author name ]        [ 💬 N replies ]
```

- **Category badge:** `bg-teal-100 text-teal-800` pill
- **Timestamp:** `text-xs text-stone-400`, right-aligned
- **Title:** `text-lg font-semibold text-stone-900 hover:text-teal-700`
- **Body preview:** `text-sm text-stone-500 line-clamp-2 mt-1` — use `truncate(strip_tags(post.body), length: 200)` to avoid rendering raw HTML/Markdown and limit DOM size
- **Author avatar:** 24px circle; if `avatar_url` present render `<img>`; fallback is a `div` with `bg-teal-100 text-teal-700 font-semibold` showing first letter of `post.user.name`
- **Author name:** `text-sm font-medium text-stone-700`
- **Reply count:** `text-sm text-stone-400` with chat bubble icon (Unicode or inline SVG)

---

## Empty State

When `@posts` is empty, show a styled card in the feed column:

```
bg-white border border-stone-200 rounded-xl p-8 text-center
  text-stone-400 text-sm — "No posts yet. Be the first to start a conversation!"
  (if logged_in?) → "New Post" button in teal
```

## Pagination

Simple prev/next at bottom of feed (intentional label change from "Previous/Next" to "Older/Newer" for chronological framing):
- `← Older` and `Newer →` links
- Styled: `text-teal-700 hover:underline font-medium`

---

## Files Changed

| File | Change |
|---|---|
| `app/views/layouts/application.html.erb` | Update nav bar; update flash message container to use full-width layout |
| `app/views/posts/index.html.erb` | Full redesign; remove existing in-page "New Post" button |
| `app/controllers/posts_controller.rb` | Add `replies` to `includes` to avoid N+1 queries |

No new partials required (keep it simple). No JS changes needed.

---

## Out of Scope

- Post detail page (`posts#show`) — future iteration
- Login/signup pages — future iteration
- Dark mode
- Animations beyond CSS transitions
