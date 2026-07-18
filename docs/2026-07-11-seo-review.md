# SEO Review — Public-Facing HTML

**Date:** 2026-07-11
**Scope:** All anonymous-visitor-facing HTML routes, the root layout, structured data, microformats, sitemap/robots, and the Atom feed. Authenticated-only views (LiveView feeds shown to signed-in users, `/people/settings`, checkin/place/post editors, `/pings`, `/following`) are out of scope.

## How to read this report

Each finding has a **Severity** (Critical / High / Medium / Low) based on likely impact on indexability, click-through, and rich-result eligibility, plus exact file/line citations so they can be fixed directly.

---

## Public route inventory

| Route | Controller/Action | Robots pipeline | `X-Robots-Tag` |
|---|---|---|---|
| `GET /` (anonymous) | `PageController.index` | `robots_noindex` | `noindex, follow` |
| `GET /credits` | `CreditsController.index` | `robots_noindex` | `noindex, follow` |
| `GET /people/:id`, `GET /@:username` | `PersonController.show` | `robots_noindex` | `noindex, follow` |
| `GET /places` | `PlaceController.index` | `robots_noindex` | `noindex, follow` |
| `GET /checkins` | `CheckinController.index` | `robots_noindex` | `noindex, follow` |
| `GET /posts` | `PostController.index` | `robots_noindex` | `noindex, follow` |
| `GET /notes/:id` | `NoteController.show` | `robots_noindex` | `noindex, follow` |
| `GET /places/:id[/:country[/:secondary]/:city]/:slug` | `PlaceController.show` | `robots_index` | `index, follow` |
| `GET /checkins/:id[/:country[/:secondary]/:city]/:slug` | `CheckinController.show` | `robots_index` | `index, follow` |
| `GET /posts/:id[/:year/:month/:day/:slug]` | `PostController.show` | `robots_index` | `index, follow` |
| `GET /.well-known/webfinger`, `/.well-known/nodeinfo`, `/nodeinfo/:version`, `/identicon/:id`, `/feed.atom`, `/sitemap*.xml` | various | *(no pipeline — outside `:browser` entirely)* | none set |

(`lib/revix_web/router.ex:29-163`)

Only individual checkin/place/post **detail** pages are indexable today; the home page, all three index/listing pages, and every person profile are explicitly `noindex`.

---

## Findings

### 1. [Critical] Every page shares one identical `<title>`

`lib/revix_web/components/layouts/root.html.heex:8-10`:

```heex
<.live_title default="Revix" suffix=" · Phoenix Framework">
  {assigns[:page_title]}
</.live_title>
```

`page_title` is never assigned anywhere in the codebase (verified: the only match for `page_title` under `lib/revix_web/` is this read site). Every public page — home, `/places`, `/checkins`, `/posts`, every checkin/place/post detail page, every person profile, `/credits` — renders the exact same title: **"Revix · Phoenix Framework"**.

**Impact:** Title tags are the single strongest on-page ranking and CTR signal. With no per-page title, search engines cannot distinguish a checkin at the Eiffel Tower from a blog post from the homepage in search results, and Google will typically rewrite the `<title>` itself, taking that control away from you entirely. This alone likely suppresses most organic traffic potential for detail pages that are otherwise correctly set to `index, follow`.

**Fix:** Set `assign(:page_title, ...)` in each controller action — e.g. `"#{place.name} · Revix"`, `"Checkin at #{place.name} · Revix"`, `"#{post.name} · Revix"`.

---

### 2. [Critical] No `<meta name="description">` anywhere

Confirmed via repo-wide search: no `<meta name="description">` exists in `root.html.heex` or any controller/template. Only `og:description` is populated, and only on the three detail-page controllers (see Finding 4).

**Impact:** Without a meta description, Google fabricates a snippet by pulling arbitrary text from the page body, which is unpredictable and usually less compelling than a hand-written summary. This directly affects click-through rate from search results even on pages that *are* indexed.

**Fix:** Add a `<meta name="description" content={...}>` slot to the root layout (parallel to the existing `head_meta` mechanism), and populate it per-page — at minimum on the three detail-page controllers, ideally also on `/`, `/places`, `/checkins`, `/posts`, and person profiles.

---

### 3. [Critical] The highest-value pages are marked `noindex`

`lib/revix_web/router.ex:37-42,116-134` pipe the home page, `/places`, `/checkins`, `/posts`, and person profiles (`/@username`, `/people/:id`) through `:robots_noindex` (`lib/revix_web/plugs/robots_header.ex:13`, `robots_value(_, false) → "noindex, follow"`). Only the three detail-page scopes (`router.ex:136-151`) get `:robots_index`.

**Impact:** This is very likely inverted from intent. Index/listing pages and profile pages are normally the pages you *most* want discoverable — they're what a search engine uses to find and crawl into the detail pages, and profile pages are frequently what people search for by name/username. As configured, Google can follow links *from* these pages (`follow` is set) but will never show them in search results, and — more importantly — a `noindex` header on `/places`, `/checkins`, and `/posts` doesn't stop crawling, but it does signal these are low-value pages, which can reduce crawl budget allocated to discovering the detail pages linked from them.

**Fix:** Confirm with product/marketing whether this was deliberate (e.g., to avoid thin/duplicate content on paginated listings). If not deliberate, switch `/`, `/places`, `/checkins`, `/posts`, and person profiles to `:robots_index`. If the listings paginate, keep listings `noindex,follow` intentionally but make sure that's a documented decision, not a default.

---

### 4. [High] Canonical, Open Graph, and JSON-LD are implemented but scoped to only 3 of ~9 public routes

`CheckinController.show` (`lib/revix_web/controllers/checkin_controller.ex:80-89`), `PlaceController.show` (`lib/revix_web/controllers/place_controller.ex:52-61`), and `PostController.show` (`lib/revix_web/controllers/post_controller.ex:83-92`) each assign `:json_ld`, `:head_links` (canonical + AP `alternate`), and `:head_meta` (Open Graph), which the root layout renders (`root.html.heex:36-47`). No other public route sets any of these — home, `/places`, `/checkins`, `/posts`, `/@username`, `/credits` get zero canonical tag, zero OG tags, zero JSON-LD.

**Impact:** Social share previews (Slack, iMessage, Facebook, LinkedIn) for the homepage or a profile link will show nothing but a bare URL. Listing pages have no canonical tag, which is a minor risk if they ever gain query-string variants (filters/pagination) in the future without a matching canonical update.

**Fix:** Add at least a self-referential canonical link and basic `og:title`/`og:description`/`og:url` to every public template, and consider a `ProfilePage`/`Person` JSON-LD block for `/@username`.

---

### 5. [High] Avatar `<img>` elements have no `alt` attribute at all

Confirmed via grep across all `*_html/*.heex` templates and `layouts.ex`: every avatar image (navbar, activity feed, checkin/post author + companion lists, place show page lists) omits `alt` entirely. Only entry-attachment photos have one, via `alt={entry_image.image.alt || ""}` (`checkin_html/show.html.heex:94`, `post_html/show.html.heex:106`).

**Impact:** A raw `<img>` with no `alt` attribute (as opposed to an intentional `alt=""`) is a WCAG 1.1.1 failure and is flagged by Lighthouse/axe accessibility audits, which factor into Google's page-quality signals. It's also a missed opportunity for image search — none of these images are describable by search engines.

**Fix:** Add `alt={person.display_name || "avatar"}` (or `alt=""` if decorative) to every avatar `<img>`.

---

### 6. [High] `robots.txt` is the unmodified Phoenix placeholder

`priv/static/robots.txt`:

```
# See https://www.robotstxt.org/robotstxt.html for documentation on how to use the robots.txt file
#
# To ban all spiders from the entire site uncomment the next two lines:
# User-agent: *
# Disallow: /
```

This is scaffolding left over from `phx.new`. It has no `Sitemap:` directive, despite a working dynamically-generated sitemap existing at `/sitemap.xml` (`lib/revix_web/controllers/sitemap_controller.ex`, `router.ex:159`).

**Impact:** Missing `Sitemap:` directive means search engines rely solely on discovering `/sitemap.xml` through Search Console submission or crawl luck rather than the standard robots.txt pointer.

**Fix:**
```
User-agent: *
Allow: /

Sitemap: https://<production-host>/sitemap.xml
```

---

### 7. [Medium] Two listing pages render zero `<h1>`

- `place_html/index.html.heex` has no `<.header>` and no raw `<h1>` — goes straight into `<.map />` / `<.labeled_list>`.
- `checkin_html/index.html.heex` — same, no `<h1>` anywhere.
- `post_html/show.html.heex:` the `<h1>` is conditional on `@post.name` being present (`{if @post.name}<h1 class="my-4 leading-10 p-name">{@post.name}</h1>{end}`) — a nameless/draft-titled post renders **zero** `<h1>` elements.

**Impact:** A missing `<h1>` removes a strong on-page relevance signal and is also an accessibility/document-outline defect (screen reader users rely on heading landmarks to navigate).

**Fix:** Add a page-level `<h1>` to both index templates (e.g. "Places" / "Checkins"), and give `post_html/show.html.heex` a fallback heading (e.g. the place name or "Untitled post") when `post.name` is blank.

---

### 8. [Medium] No semantic HTML5 sectioning elements anywhere in public templates

Confirmed via grep: no `<article>`, `<nav>`, `<footer>`, or `<section>` appear in any public template. The only semantic elements in the entire rendered page are the layout's `<header>` (nav bar) and `<main>` wrapper (`lib/revix_web/components/layouts.ex`) — every content area, card, and list is a generic `<div>`/`<ul>`/`<li>`.

**Impact:** Search engines use sectioning elements as a secondary signal for identifying primary content vs. chrome/navigation. `<article>` in particular is a natural fit for checkin/post/place detail pages (which already carry `h-entry`/`h-card` microformat classes) and would strengthen both accessibility and content-extraction accuracy for crawlers and reader-mode tools.

**Fix:** Wrap each detail page's primary content in `<article>`, wrap the nav bar in `<nav>` (nested inside the existing `<header>`), and add a `<footer>` if there's site-wide footer content.

---

### 9. [Medium] Canonical-URL redirects use 302, not 301

`CheckinController.show` (`checkin_controller.ex:75`), `PlaceController.show` (`place_controller.ex:46`), and `PostController.show` (`post_controller.ex:78`) call plain `redirect(conn, to: canonical)` when a bare-ID URL doesn't match the canonical slugged path. Phoenix's `redirect/2` defaults to a 302 (temporary) redirect.

**Impact:** Search engines treat 301 and 302 differently for consolidating ranking signals onto the canonical URL. A 302 is a weaker signal that the redirect is permanent, which can slow down or dilute canonicalization compared to a 301, especially at scale across many bare-ID inbound links.

**Fix:** Use `redirect(conn, to: canonical, status: 301)` for these slug-canonicalization redirects (they are permanent by design — the canonical path is deterministic from the resource's current data).

---

### 10. [Medium] No `width`/`height` on any `<img>`, no responsive `srcset`

Confirmed via grep: no `<img>` tag anywhere sets `width`/`height` attributes, despite Waffle already generating bounded-size versions (`Revix.Uploaders.Image`: `:large` 1200×1200, `:medium` 800×800, `:thumb` 300×300; `Revix.Uploaders.Avatar`: `:thumb` 64×64). No template uses `srcset`/`sizes` — a single fixed version URL is always hardcoded (e.g., checkin show uses `:large` for the displayed image even on mobile viewports).

**Impact:** Missing `width`/`height` causes layout shift as images load, which is a direct Core Web Vitals (CLS) regression — a confirmed Google ranking factor. Missing `srcset` means mobile visitors download desktop-sized images, hurting LCP and mobile PageSpeed score, which also factors into mobile search ranking.

**Fix:** Add `width`/`height` attributes matching each version's known max dimensions, and build a `srcset` from the `:thumb`/`:medium`/`:large` variants already produced by the uploader.

---

### 11. [Low] No Twitter Card meta tags

No `twitter:card`, `twitter:title`, `twitter:description`, or `twitter:image` tags exist anywhere. Twitter/X (and several other platforms) fall back to Open Graph tags when Twitter-specific tags are absent, so this is a smaller gap than Finding 4, but `twitter:card=summary_large_image` specifically is needed to get the large-image card layout rather than a small thumbnail.

**Fix:** Once Finding 4 is addressed, add `twitter:card`, `twitter:title`, `twitter:description`, `twitter:image` alongside the existing OG tags.

---

### 12. [Low] No explicit `<link rel="icon">` in `<head>`

`root.html.heex` has no favicon `<link>` tag. `priv/static/favicon.ico` exists and is served by browser default convention at `/favicon.ico`, so this mostly works, but there's no `apple-touch-icon`, no explicit sizes, and the cache-busted hashed favicon variants (`favicon-91f37b6....ico`, `favicon-d3590f4....ico`) present in `priv/static/` are never referenced by an explicit tag.

**Fix:** Add `<link rel="icon" href={~p"/favicon.ico"} />` (using the hashed/fingerprinted path via `~p` for proper cache-busting) and an `apple-touch-icon` for iOS home-screen bookmarks.

---

### 13. [Low] NodeInfo reports `services.outbound: ["rss2.0"]` but the feed served is Atom 1.0

`lib/revix_web/controllers/nodeinfo_controller.ex` — the feed at `/feed.atom` (`feed_atom/index.atom.eex`) is well-formed Atom 1.0, not RSS 2.0. Not an HTML SEO issue, but a factual mismatch in federation metadata that some fediverse directories/crawlers may use to categorize the instance.

**Fix:** Change the NodeInfo `services.outbound` value to `"atom1.0"`.

---

### 14. [Low] Atom feed `<updated>` conflates "published" with "modified"

`lib/revix_web/feed_atom.ex` — `feed_entry_updated/1` uses `published_at_utc` for every activity type's `<updated>` element. Per RFC 4287 §4.2.15, `<updated>` should reflect the most recent modification time. If a checkin/post is edited after publishing, subscribers won't see a change signal, and no Atom `<link rel="enclosure">` is emitted for entry photos, so photo checkins aren't exposed as Atom media enclosures to feed readers.

**Fix:** Use the entry's `updated_at` (or equivalent) for `<updated>` if available, and consider adding `<link rel="enclosure" type="image/jpeg" href="...">` for the primary attached photo.

---

## What's already working well

- **Microformats2** (`h-card`, `h-entry`, `p-name`, `u-uid`, `dt-start`/`dt-published`, `e-content`) are correctly hand-authored on place/checkin/post detail pages (`place_html/show.html.heex`, `checkin_html/show.html.heex`, `post_html/show.html.heex`), giving IndieWeb-compatible parsers real structured data independent of JSON-LD.
- **Schema.org JSON-LD** (`TouristAttraction`, `Event`, `BlogPosting`) is correctly implemented in `lib/revix_web/structured_data.ex` for the three detail-page types, including correctly suppressing JSON-LD for unpublished draft posts (`post_json_ld/1` pattern-matches `published_at_utc: nil` → `nil`, and the root layout's `if assigns[:json_ld]` guard handles it — `lib/revix_web/structured_data.ex:55`).
- **Sitemap** is dynamically generated (`SitemapController`), correctly split into a sitemap index plus per-type sub-sitemaps (places/checkins/posts), each using `<loc>`/`<lastmod>` built from `CanonicalRoutes`.
- **Atom feed** is otherwise well-formed: correct `<id>`, `rel="self"` link (RFC 4287-recommended), CDATA-wrapped HTML content, properly escaped titles via `Phoenix.HTML.html_escape/1`, and stable per-entry `<id>` values.
- **WebFinger** and **NodeInfo** endpoints are standards-compliant for ActivityPub actor discovery.
- **Viewport meta tag** and mobile-first Tailwind utility usage are correctly in place; an iOS zoom-prevention rule (`font-size: 1rem` on inputs) shows real mobile UX attention.
- **Robots control via `X-Robots-Tag` header** is a deliberate, consistently-applied architecture (`RevixWeb.Plugs.RobotsHeader`) — the mechanism itself is sound; only the per-route allow/deny assignment (Finding 3) needs revisiting.
- **Canonical redirect + `<link rel="canonical">` + AP `alternate` link** pattern on detail pages is a solid design; it just needs broader coverage (Finding 4) and a 301 status (Finding 9).

---

## Priority order for remediation

1. Per-page `<title>` (Finding 1) and `<meta name="description">` (Finding 2) — highest ROI, purely additive, no architectural change.
2. Resolve the `noindex` scope question on `/`, `/places`, `/checkins`, `/posts`, profiles (Finding 3) — needs a product decision first.
3. Extend canonical/OG/JSON-LD coverage to all public routes (Finding 4).
4. Avatar `alt` attributes (Finding 5) — small, mechanical fix.
5. `robots.txt` sitemap directive (Finding 6) — one-line fix.
6. Remaining Medium/Low items as capacity allows.
