# Dark Mode — Design Spec

**Date:** 2026-03-22
**Status:** Approved

---

## Overview

Add dark mode to the forum's main user-facing UI using Tailwind CSS `dark:` variants. Dark mode defaults to the OS system preference (`prefers-color-scheme: dark`) but can be overridden by the user via a sun/moon toggle in the navbar. The preference is persisted in `localStorage`. Admin panel views are out of scope.

---

## 1. Tailwind Configuration

The app uses **Tailwind CSS v4** via the `tailwindcss-rails` gem. There is no `tailwind.config.js` — configuration is done through CSS directives in `app/assets/tailwind/application.css`.

Dark mode is enabled by adding an `@variant` directive after the existing `@import`:

```css
@import "tailwindcss";
@variant dark (&:where(.dark, .dark *));
```

This tells Tailwind to generate `dark:` variant classes that activate when any ancestor element has the `dark` class — which we place on `<html>`.

No `config/tailwind.config.js` file is created.

---

## 2. Flash Prevention (No Theme Flash on Load)

A small synchronous `<script>` block is placed at the very top of `<head>` in `application.html.erb`, **before** the `stylesheet_link_tag` lines. If the app enforces a Content Security Policy that disallows inline scripts, add `nonce: content_security_policy_nonce` to the script tag. The current app has `<%= csp_meta_tag %>` in `<head>` but does not appear to enforce a strict nonce-based CSP for inline scripts; confirm before deploying. It reads the stored preference from `localStorage` and immediately applies or removes the `dark` class on `<html>` before the browser renders anything.

```html
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <script>
    (function() {
      var theme = localStorage.getItem('theme');
      if (theme === 'dark' || (!theme && window.matchMedia('(prefers-color-scheme: dark)').matches)) {
        document.documentElement.classList.add('dark');
      } else {
        document.documentElement.classList.remove('dark');
      }
    })();
  </script>
  <%= stylesheet_link_tag "application", "data-turbo-track": "reload" %>
  <%= stylesheet_link_tag "tailwind", "data-turbo-track": "reload" %>
  ...
```

The script handles all three states:
- `localStorage === 'dark'` → add `dark` class
- `localStorage === 'light'` → remove `dark` class
- No stored value → follow `prefers-color-scheme`

---

## 3. Stimulus Dark Mode Controller

A new Stimulus controller at `app/javascript/controllers/dark_mode_controller.js`. It is attached to `<body>` in `application.html.erb` (not `<html>` — Stimulus is designed to scope controllers within `document.body`). The controller calls `document.documentElement.classList` directly to manipulate the `dark` class on `<html>`.

**Responsibilities:**
- `connect()`: sets up a `matchMedia` listener so live OS preference changes apply when no `localStorage` override is set. Stores the listener reference for cleanup.
- `disconnect()`: removes the `matchMedia` listener to prevent leaks.
- `toggle()`: flips the `dark` class on `document.documentElement`, saves `'dark'` or `'light'` to `localStorage`.

The controller does **not** need to read localStorage on connect — the inline `<script>` already handles initial state before Stimulus loads.

`eagerLoadControllersFrom` in `controllers/index.js` auto-discovers controllers by filename, so no manual registration is needed.

---

## 4. Toggle Button

A sun/moon button is added to the navbar in `application.html.erb`, visible to all users (logged in or not). It sits in the right-side nav group, before the login/signup links.

```html
<button data-action="click->dark-mode#toggle" class="text-teal-100 hover:text-white" aria-label="Toggle dark mode">
  <%# Moon icon — shown in light mode %>
  <svg class="w-5 h-5 dark:hidden" ...>...</svg>
  <%# Sun icon — shown in dark mode %>
  <svg class="w-5 h-5 hidden dark:block" ...>...</svg>
</button>
```

Icon swapping is done entirely via Tailwind `dark:` variants — no JS needed to swap icons.

---

## 5. Color Palette

The app uses three color scales: `stone-*`, `gray-*`, and `blue-*`. The mapping for dark mode:

**Stone / Gray (backgrounds, text, borders):**

| Light class | Dark counterpart |
|---|---|
| `bg-stone-50` (`<body>` page bg) | `dark:bg-stone-900` |
| `bg-white` (cards, forms) | `dark:bg-stone-800` |
| `bg-gray-50` (reply cards) | `dark:bg-stone-800` |
| `bg-stone-100` / `bg-gray-100` | `dark:bg-stone-700` |
| `border-stone-200` / `border-gray-200` | `dark:border-stone-700` |
| `border-stone-100` / `border-gray-100` | `dark:border-stone-700` |
| `border-gray-300` (form inputs) | `dark:border-stone-600` |
| `text-stone-900` / `text-gray-900` | `dark:text-stone-100` |
| `text-stone-800` / `text-gray-800` (prose body) | `dark:text-stone-200` |
| `text-stone-700` / `text-gray-700` | `dark:text-stone-300` |
| `text-stone-600` / `text-gray-600` | `dark:text-stone-400` |
| `text-stone-500` / `text-gray-500` | `dark:text-stone-400` |
| `text-stone-400` / `text-gray-400` | `dark:text-stone-500` |
| `hover:bg-stone-100` / `hover:bg-stone-50` (sidebar links) | `dark:hover:bg-stone-700` |

**Teal (navbar, badges, active states):**

| Light class | Dark counterpart |
|---|---|
| `bg-teal-50` (active sidebar, notifications unread) | `dark:bg-teal-900/40` |
| `bg-teal-100` (category badges, avatars) | `dark:bg-teal-900` |
| `text-teal-700/800` | unchanged — adequate on dark bg |
| Teal-700/600/500 navbar, buttons | unchanged — adequate on dark bg |
| Navbar white pill buttons (`bg-white text-teal-700 hover:bg-teal-50`) | `dark:bg-stone-700 dark:text-white dark:hover:bg-stone-600` |

**Blue (links, submit buttons, form accents):**

`blue-*` classes appear throughout on back-links, inline links, submit buttons, and markdown tab active states. Blue-600 and blue-500 are readable on dark stone backgrounds and require no changes to `text-blue-*` or `bg-blue-*` classes. The exception is focus rings — `focus:ring-blue-500` is nearly invisible against `dark:bg-stone-700` form inputs; these can be left as-is or changed to `dark:focus:ring-blue-400` for better contrast. The active markdown tab border (`border-b-2 border-blue-600`) is handled via the JS constants (see Section 6 note on `markdown_preview_controller.js`).

**Flash messages:**

| Light | Dark |
|---|---|
| `bg-green-50 border-green-200 text-green-800` | `dark:bg-green-900/20 dark:border-green-800 dark:text-green-300` |
| `bg-red-50 border-red-200 text-red-700` | `dark:bg-red-900/20 dark:border-red-800 dark:text-red-400` |

**Shadows:**

The default Tailwind `shadow-sm` and `shadow-lg` use black/transparent colors that are already nearly invisible on light backgrounds and remain acceptable on dark stone backgrounds. No shadow color overrides are needed.

**Other notes:**
- The `prose prose-sm` classes in markdown rendering are not styled by a Tailwind Typography plugin (not installed) — treated as plain HTML. No `dark:prose-invert`. Markdown body text gets `dark:text-stone-200` directly on the wrapper div.
- Form inputs (`<input>`, `<textarea>`, `<select>`) with `bg-white` or no explicit background get `dark:bg-stone-700 dark:text-stone-100` so text remains readable. `<select>` elements require the same treatment — they do not reliably inherit background from parent containers.
- `sessions/new.html.erb`'s card uses only `shadow` (no `border`) for visual separation from the page background. On dark surfaces, shadow alone provides minimal separation — add `dark:border dark:border-stone-700` to that card alongside `dark:bg-stone-800`.
- The `matchMedia` listener in `connect()` should only be registered when `localStorage.getItem('theme')` is falsy. If a manual preference is stored, OS changes should be ignored.

---

## 6. Files Changed

| File | Change |
|---|---|
| `app/assets/tailwind/application.css` | Add `@variant dark` directive |
| `app/views/layouts/application.html.erb` | Add inline `<script>` in `<head>`, `data-controller="dark-mode"` on `<body>`, toggle button in nav, `dark:bg-stone-900` on `<body>` |
| `app/javascript/controllers/dark_mode_controller.js` | Create — toggle action + matchMedia listener + cleanup |
| `app/javascript/controllers/markdown_preview_controller.js` | Update `ACTIVE_TAB` and `INACTIVE_TAB` constants to include dark-mode classes (e.g. `dark:text-blue-400 dark:border-blue-400` on active; `dark:text-stone-400 dark:hover:text-stone-200` on inactive). The controller uses `element.className = CONSTANT` which fully replaces the class attribute, so dark variants must live in the JS constants, not in the HTML. |
| `app/views/posts/index.html.erb` | Add `dark:` variants to cards, sidebar, category badges |
| `app/views/posts/show.html.erb` | Add `dark:` variants to post card, reply form, flag dropdown |
| `app/views/posts/new.html.erb` | Add `dark:` variants to form card, inputs, markdown tabs |
| `app/views/posts/edit.html.erb` | Same as new |
| `app/views/replies/_reply.html.erb` | Add `dark:` variants to reply card, text, flag dropdown |
| `app/views/replies/edit.html.erb` | Add `dark:` variants to form card, inputs |
| `app/views/sessions/new.html.erb` | Add `dark:` variants to card, labels, inputs |
| `app/views/users/new.html.erb` | Add `dark:` variants to card, labels, inputs |
| `app/views/users/show.html.erb` | Add `dark:` variants to profile card, activity items |
| `app/views/users/edit.html.erb` | Add `dark:` variants to form card, labels, inputs |
| `app/views/notifications/index.html.erb` | Add `dark:` variants to notification items, unread highlight |
| `app/views/search/index.html.erb` | Add `dark:` variants to result cards, sidebar |
| `app/views/reactions/_reactions.html.erb` | Add `dark:` variants to reaction buttons |

---

## 7. Out of Scope

- Admin layout/views — the `dark` class on `<html>` is inherited by admin pages. The admin layout uses `bg-stone-100` on `<body>` and `bg-gray-900` on its sidebar. In dark mode, `body` will flip to near-black (from the `@variant dark` inheritance), causing the sidebar to visually merge with the body background and lose structural separation. This is a known visual degradation accepted for this iteration. A future fix would add `class="no-dark"` to the `<html>` tag in `admin.html.erb` and scope the `@variant` selector to exclude it.
- User preference stored server-side (DB column) — `localStorage` is sufficient.
- Mailer template dark mode.
- `@tailwindcss/typography` plugin and `dark:prose-invert` — the plugin is not installed; markdown body text gets a manual `dark:text-stone-200` class instead.
