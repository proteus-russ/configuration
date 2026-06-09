# CMS PageElement object model ↔ database

How a Proteus Framework CMS page is assembled, and how each class maps to its table. Source paths are
under `/Users/russ/git/fork/proteusframework/cms/src/main/java/`. Postgres columns are **lowercase**;
hbm.xml uses camelCase but that is not what's in the database.

## Contents

- [PageElement (base)](#pageelement-base)
- [Page](#page)
- [PageTemplate](#pagetemplate)
- [Layout](#layout)
- [Box](#box)
- [ContentElement (+ subtypes)](#contentelement)
- [BeanBoxList](#beanboxlist)
- [PageElementPath](#pageelementpath)
- [How template → page content inheritance works](#inheritance)

## PageElement (base) {#pageelement}

Interface `net.proteusframework.cms.PageElement` (`net/proteusframework/cms/PageElement.java`). Common
contract for `Page`, `Box`, and `ContentElement`: id, `name`, `site`, `lastModified`/`lastModUser`,
`primaryPageElementPath`, `cssName`, `trashed`, visibility condition, and a `pathId` discriminator
(`"pg"` Page, `"bx"` Box, `"cb"` ContentElement). Each subtype is backed by its own table; there is no
single `pageelement` table.

## Page {#page}

`net.proteusframework.cms.component.page.Page` (`.../component/page/Page.java`). The whole page.

- **Table** `page`, PK `page_id`.
- Key columns: `pagetemplate` (→ `pagetemplate.pagetemplate_id`), `pageelementpath_id`
  (→ `pageelementpath`, the page's URL), `site_id`, `name`, `persistedtitlekey`, `persistedcssname`,
  `authorization_id`, `authorization_page` (self-ref), `favicon_link_id`, `visibilitycondition_id`,
  `trashed`, `last_modified`, `lastmoduser`.
- Per-box content overrides: join table `page_beanboxlist` (`page_id`, `beanboxlist_id`, `order_id`).
- Other join tables: `page_metainformation`, `page_ndes`, `page_locales`, `page_labels`.

## PageTemplate {#pagetemplate}

`net.proteusframework.cms.component.page.PageTemplate` (`.../component/page/PageTemplate.java`). A
reusable blueprint; many pages share one template.

- **Table** `pagetemplate`, PK `pagetemplate_id`.
- Key columns: `layout_id` (→ `layout`, **not null** — every template has a layout), `site_id`, `name`,
  `cssname`, `last_modified`.
- Default per-box content: join table `pagetemplate_beanboxlist` (`pagetemplate_id`, `beanboxlist_id`,
  `order_id`).
- Other join tables: `pagetemplate_metainformation`, `pagetemplate_ndes`, `pagetemplate_locales`.

## Layout {#layout}

`net.proteusframework.cms.component.page.layout.Layout` (`.../page/layout/Layout.java`). Defines the
set and order of boxes.

- **Table** `layout`, PK `layout_id`. Columns: `name`, `version`, `height100percent`, `modnumber`,
  `site_id`, `last_modified`, `lastmoduser`.
- Ordered boxes: join table `layout_box` (`layout_id`, `box_id`, `order_id`).

## Box {#box}

`net.proteusframework.cms.component.page.layout.Box` (`.../page/layout/Box.java`). A region of the page.

- **Table** `box`, PK `box_id`.
- Key columns: `boxdescriptor` (enum: ENCLOSING, HEADER, COLUMN, SECTION, MAIN, NAVIGATION, ASIDE,
  FOOTER), `boxfloat`, `boxclear`, `boxposition`, `defaultcontentarea`, `name`, `cssname`,
  `styleclass`, `locked`, `wrappingcontainercount`, dimension/offset/margin/padding columns, `site_id`,
  `trashed`.
- **Box hierarchy is self-referential within the table**: `box.parent_id` + `box.order_id` (there is
  **no** separate `box_children` table). A box with children is a structural container; a leaf "bean
  box" holds content elements via a `BeanBoxList`.

## ContentElement {#contentelement}

Interface `net.proteusframework.cms.component.ContentElement` (`.../component/ContentElement.java`),
base impl `AbstractContentElement` (`.../component/AbstractContentElement.java`). The actual content
units. **Single-table inheritance**: one `contentelement` table, subtype chosen by the `disc_type`
discriminator.

- **Table** `contentelement`, PK `contentelement_id`.
- Key columns: `disc_type` (the bean/Kotlin FQCN), `name` (human label), `componentidentifier`
  (`disc_type` + a `/`-suffix identifying the concrete UI — **the field that names the exact UI** in
  analytics), `version`, `cssname`, `styleclass`, `contentwrapperelement`, `delegatepurposelayout_id`,
  `pageelementpath_id`, `site_id`, `visibilitycondition_id`, `trashed`, `last_modified`, `lastmoduser`.
- Join tables: `contentelement_labels`, `contentelement_ndelists`, `contentelement_published`
  (published model data per locale).

Common `disc_type` values:

| disc_type | what it is |
| --- | --- |
| `com.i2rd.cms.bean.ScriptingBean` | scripted/templated content |
| `com.i2rd.cms.bean.TextBean` | rich text |
| `com.i2rd.cms.bean.CompositeBean` | container for other content elements |
| `com.i2rd.cms.component.miwt.MIWTContentElement` | MIWT/Kotlin UI component (the interactive app UIs) |
| `com.i2rd.cms.bean.CollapsibleBean` | collapsible section |
| `com.i2rd.cms.bean.MenuBean` | navigation menu |
| `com.i2rd.freemarker.component.FreeMarkerComponent` | FreeMarker template |
| `com.i2rd.cms.bean.HTMLContentElement` | raw HTML |
| `com.i2rd.cms.bean.TabBean` | tabs |
| `com.i2rd.cms.bean.{LoginBean,LogoutBean}` | auth widgets |

`MIWTContentElement` is where the interactive Kotlin app UIs live; its `componentidentifier` carries the
backing class, e.g. `.../MIWTContentElement:/co.proteus.reviewr.kotlin.ui.submission.NewSubmissionSignupComponent`.

## BeanBoxList {#beanboxlist}

`com.i2rd.cms.page.BeanBoxList` (`com/i2rd/cms/page/BeanBoxList.java`). The junction that says "in this
box, these content elements, in this order." Not a `PageElement`.

- **Table** `beanboxlist`, PK `beanboxlist_id`. Column `box_id` (→ `box`, unique), `lastmodtime`.
- Ordered contents: join table `beanboxlist_elements` (`beanboxlist_id`, `contentelement_id`,
  `order_id`).
- A page or template links to its beanboxlists via `page_beanboxlist` / `pagetemplate_beanboxlist`.

## PageElementPath {#pageelementpath}

`net.proteusframework.cms.PageElementPath` (`net/proteusframework/cms/PageElementPath.java`). Maps a
site URL path to a `Page` or `ContentElement`.

- **Table** `pageelementpath`, PK `pageelementpath_id`.
- Columns: `site_id`, `path` (the URL path, unique per site), `wildcard`, and a **polymorphic ("any")
  reference**: `pageelement_class` (the target FQCN) + `pageelement_id` (the target id). ~99% point at
  `Page`.
- To get a page's URL: `page.pageelementpath_id` → `pageelementpath.path`. A page's `path` is a prefix
  (e.g. `s2/showcase`); the actual requested URL appends wildcard path info (mirrored in
  `requeststatistic.pathinfo`).

## How template → page content inheritance works {#inheritance}

1. A `Page` has one `PageTemplate`; the template has one `Layout`; the layout defines the ordered
   `Box`es.
2. For each box, content can be defined on the **template** (default, via `pagetemplate_beanboxlist`)
   and/or on the **page** (override, via `page_beanboxlist`). Both resolve to a `BeanBoxList` whose
   `beanboxlist_elements` give the ordered `ContentElement`s.
3. Resolution (in `Page.getElements(Box)`): if the page has a non-empty `BeanBoxList` for that box, its
   elements win; otherwise fall back to the template's elements for that box. This is how a shared
   template provides defaults while individual pages override per region.

`requeststatistic` records only the resolved `page` and `contentelement` ids — it does **not** store
which box was involved. To know which box a recorded content element sits in, join
`beanboxlist_elements` → `beanboxlist` → `box`.
