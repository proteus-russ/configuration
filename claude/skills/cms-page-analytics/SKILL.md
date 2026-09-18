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

Two halves: **CMS object model** (page built from `PageElement`s) + **request analytics** (every request recorded in `requeststatistic`, traced back to page elements).

## Orientation

**Object model.** `Layout` = ordered list of `Box`es (HEADER, MAIN, ASIDE, FOOTER, …). `PageTemplate` references one `Layout`. `Page` references one `PageTemplate`, inherits template content per box, overrides where wanted. Content units = `ContentElement`s (text, menus, MIWT/Kotlin UIs, scripted beans — dozens of subtypes, `disc_type` discriminator on single `contentelement` table). Page/template -> "these content elements in this box" wiring = `BeanBoxList`. `PageElementPath` maps site URL path to `Page` or `ContentElement` polymorphically.

**Request analytics.** `requeststatistic` = one row per HTTP request to origin server. Row records resolved `page`, handling `contentelement` (when applicable), URL `pagepath`, principal, timing, HTTP status, user agent, `partial` flag (AJAX/in-page). `page` + `contentelement` = plain id refs into CMS model -> join `requeststatistic` → `page` / `contentelement` to turn traffic into "which UI did users engage."

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

`requeststatistic` links to **Page and ContentElement only — never Box**. Boxes/Layout = structural context via beanboxlist joins, not recorded per request.

## Two rules that bite

1. **All Postgres columns lowercase.** hbm.xml uses camelCase (`requestTime`, `contentElement`, `userPrincipal`) but real columns are `requesttime`, `contentelement`, `userprincipal`. SQL lowercase or fail.
2. **Always bound analytics queries by `requesttime`.** Table huge (tens of millions rows in prod, growing, archived periodically) — unbounded scan expensive; old rows may be archived out. Every analytic query carries `requesttime` filter.

## PII/PHI gate — confirm before pulling production data

`requeststatistic` rows describe real user activity (`userprincipal`, user
agent, exact `pagepath`); joins into the CMS model can surface more. **Before
running any query that reads production data — or whose results include
personal data — you MUST stop and ask the user to explicitly confirm it
contains no PII or PHI that is meant to be scrubbed before leaving production.**
Get that confirmation **every time**; never assume.

Applies to every product. **Engage** is the sharp example: use its **sanitized
snapshots**; Engage production data is off-limits — do **not** pull it, ever;
this must not be overridden. Engage flags PHI-protected records via the
`phisafeguards` column in `app.company` — exactly the kind of data that must
not leave production unscrubbed.

## Where to go next

| You want to… | Go to |
| --- | --- |
| Run analytics query (top pages, top UIs, errors, timing, by user) | `references/query-cookbook.md` |
| `requeststatistic` columns, how rows written, join caveats | `references/requeststatistic.md` |
| CMS object model / table+column mapping / class hierarchy | `references/page-element-model.md` |

Analytics question -> adapt cookbook query (already lowercase, `requesttime`-bounded, joins to readable labels). Run via `postgres` MCP. Headline "which UI" field = `contentelement.componentidentifier` (exact bean/Kotlin class); `contentelement.name` = human label; `partial = true` isolates in-page interactions from full page loads.
