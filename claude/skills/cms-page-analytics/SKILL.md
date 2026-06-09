---
name: cms-page-analytics
description: >-
  Proteus Framework CMS page model and request analytics. Use for any question about how users
  interact with Proteus Framework sites — traffic, page views, request volume, error rates,
  response timing, authenticated vs anonymous usage, top pages or components — or anything
  involving the `requeststatistic` table. Also use for CMS structure: how `Page`, `PageElement`,
  `PageTemplate`, `Layout`, `Box`, `ContentElement`, `BeanBoxList`, and `PageElementPath` work
  and map to database tables. Trigger even when no table or class is named, e.g. "most popular
  pages last month" or "show me 500s by page". Framework-wide knowledge, not project-specific.
---

# CMS page model + request analytics

Two halves, equal weight: the **CMS object model** (how a page is built out of `PageElement`s) and the
**request analytics** (how every user request is recorded in `requeststatistic` and traced back to
those page elements).

## Orientation

**Object model.** A `Layout` is an ordered list of `Box`es (HEADER, MAIN, ASIDE, FOOTER, …). A
`PageTemplate` references one `Layout`. A `Page` references one `PageTemplate` and inherits the
template's content per box, overriding it where it wants. The content units are `ContentElement`s
(text, menus, MIWT/Kotlin UIs, scripted beans — dozens of subtypes, distinguished by the `disc_type`
discriminator column on a single `contentelement` table). The wiring from a page/template to "these
content elements live in this box" is the `BeanBoxList`. A `PageElementPath` maps a site URL path to a
`Page` or `ContentElement` polymorphically.

**Request analytics.** `requeststatistic` holds one row per HTTP request to the origin server. Each row
records the resolved `page`, the `contentelement` that handled it (when applicable), the URL
`pagepath`, the principal, timing, HTTP status, user agent, and whether it was a `partial`
(AJAX/in-page) request. The `page` and `contentelement` columns are plain id references back into the
CMS model, so you join `requeststatistic` → `page` / `contentelement` to turn raw traffic into
"which UI did users engage."

## Object-model spine + request links (text ER)

```
                 layout_box (order_id)        pagetemplate_beanboxlist / page_beanboxlist (order_id)
  Layout  ───────────────────────────►  Box        ▲                          ▲
    ▲  layout_id                         box_id     │ beanboxlist.box_id       │
    │                                               │                          │
PageTemplate ──pagetemplate──◄ Page          BeanBoxList ──beanboxlist_elements(order_id)──► ContentElement
    │ pagetemplate_id              │              (one box → ordered content elements)            │ disc_type
    │                              │ pageelementpath_id                                           │ pageelementpath_id
    └──────────────► PageElementPath (path, pageelement_class, pageelement_id) ◄──────────────────┘

requeststatistic.page            ──► page.page_id
requeststatistic.contentelement  ──► contentelement.contentelement_id
requeststatistic.site            ──► site.site_id
requeststatistic.userprincipal   ──► principal id
```

Note: `requeststatistic` links to **Page and ContentElement only — never Box**. Boxes/Layout are
structural context you reach through the beanboxlist joins, not something recorded per request.

## Two rules that will bite you

1. **All Postgres columns are lowercase.** Proteus hbm.xml mappings use camelCase (`requestTime`,
   `contentElement`, `userPrincipal`) but the real columns are `requesttime`, `contentelement`,
   `userprincipal`. Write SQL in lowercase or it fails.
2. **Always bound analytics queries by `requesttime`.** The table is huge (tens of millions of rows in
   production, growing constantly, archived periodically) — an unbounded scan is expensive, and old
   rows may have been archived out anyway. Every analytic query should carry a `requesttime` filter.

## PII/PHI gate — confirm before pulling production data

`requeststatistic` rows describe real user activity (`userprincipal`, user
agent, the exact `pagepath`), and joins back into the CMS model can surface
more. **Before running any query that reads production data — or whose results
include personal data — you MUST stop and ask the user to explicitly confirm it
contains no PII or PHI that is meant to be scrubbed before leaving production.**
Get that confirmation **every time**; never assume.

This applies to every product. **Engage** is the sharp example: you must use its
**sanitized snapshots** and treat Engage production data as off-limits — do
**not** pull it ever - this must not be overridden. Engage flags PHI-protected
records via the `phisafeguards` column in `app.company`, which is exactly the
kind of data that must not leave production unscrubbed.

## Where to go next

| You want to… | Go to |
| --- | --- |
| Run an analytics query (top pages, top UIs, errors, timing, by user) | `references/query-cookbook.md` |
| Understand `requeststatistic` columns, how rows get written, join caveats | `references/requeststatistic.md` |
| Understand the CMS object model / table+column mapping / class hierarchy | `references/page-element-model.md` |

When asked an analytics question, prefer adapting a cookbook query — they are already lowercase,
`requesttime`-bounded, and join to readable labels. Run them via the `postgres` MCP. The headline field
for "which UI" is `contentelement.componentidentifier` (names the exact bean/Kotlin class) with
`contentelement.name` as the human label; filter `partial = true` to isolate in-page interactions from
full page loads.
