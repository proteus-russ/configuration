# CMS PageElement object model ↔ database

How a Proteus Framework CMS page is assembled; class → table mapping. Source under `/Users/russ/git/fork/proteusframework/cms/src/main/java/`. Postgres columns **lowercase**; hbm.xml camelCase not in DB.

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

Interface `net.proteusframework.cms.PageElement` (`net/proteusframework/cms/PageElement.java`). Common contract for `Page`, `Box`, `ContentElement`: id, `name`, `site`, `lastModified`/`lastModUser`, `primaryPageElementPath`, `cssName`, `trashed`, visibility condition, `pathId` discriminator (`"pg"` Page, `"bx"` Box, `"cb"` ContentElement). Each subtype = own table; **no single `pageelement` table**.

## Page {#page}

`net.proteusframework.cms.component.page.Page` (`.../component/page/Page.java`). Whole page.

- **Table** `page`, PK `page_id`.
- Key columns: `pagetemplate` (→ `pagetemplate.pagetemplate_id`), `pageelementpath_id` (→ `pageelementpath`, page's URL), `site_id`, `name`, `persistedtitlekey`, `persistedcssname`, `authorization_id`, `authorization_page` (self-ref), `favicon_link_id`, `visibilitycondition_id`, `trashed`, `last_modified`, `lastmoduser`.
- Per-box content overrides: join table `page_beanboxlist` (`page_id`, `beanboxlist_id`, `order_id`).
- Other join tables: `page_metainformation`, `page_ndes`, `page_locales`, `page_labels`.

## PageTemplate {#pagetemplate}

`net.proteusframework.cms.component.page.PageTemplate` (`.../component/page/PageTemplate.java`). Reusable blueprint; many pages share one.

- **Table** `pagetemplate`, PK `pagetemplate_id`.
- Key columns: `layout_id` (→ `layout`, **not null** — every template has layout), `site_id`, `name`, `cssname`, `last_modified`.
- Default per-box content: join table `pagetemplate_beanboxlist` (`pagetemplate_id`, `beanboxlist_id`, `order_id`).
- Other join tables: `pagetemplate_metainformation`, `pagetemplate_ndes`, `pagetemplate_locales`.

## Layout {#layout}

`net.proteusframework.cms.component.page.layout.Layout` (`.../page/layout/Layout.java`). Set + order of boxes.

- **Table** `layout`, PK `layout_id`. Columns: `name`, `version`, `height100percent`, `modnumber`, `site_id`, `last_modified`, `lastmoduser`.
- Ordered boxes: join table `layout_box` (`layout_id`, `box_id`, `order_id`).

## Box {#box}

`net.proteusframework.cms.component.page.layout.Box` (`.../page/layout/Box.java`). Region of page.

- **Table** `box`, PK `box_id`.
- Key columns: `boxdescriptor` (enum: ENCLOSING, HEADER, COLUMN, SECTION, MAIN, NAVIGATION, ASIDE, FOOTER), `boxfloat`, `boxclear`, `boxposition`, `defaultcontentarea`, `name`, `cssname`, `styleclass`, `locked`, `wrappingcontainercount`, dimension/offset/margin/padding columns, `site_id`, `trashed`.
- **Box hierarchy self-referential**: `box.parent_id` + `box.order_id` (**no** separate `box_children` table). Box with children = structural container; leaf "bean box" holds content elements via `BeanBoxList`.

## ContentElement {#contentelement}

Interface `net.proteusframework.cms.component.ContentElement` (`.../component/ContentElement.java`), base impl `AbstractContentElement` (`.../component/AbstractContentElement.java`). Actual content units. **Single-table inheritance**: one `contentelement` table, subtype via `disc_type` discriminator.

- **Table** `contentelement`, PK `contentelement_id`.
- Key columns: `disc_type` (bean/Kotlin FQCN), `name` (human label), `componentidentifier` (`disc_type` + `/`-suffix identifying concrete UI — **the field that names the exact UI** in analytics), `version`, `cssname`, `styleclass`, `contentwrapperelement`, `delegatepurposelayout_id`, `pageelementpath_id`, `site_id`, `visibilitycondition_id`, `trashed`, `last_modified`, `lastmoduser`.
- Join tables: `contentelement_labels`, `contentelement_ndelists`, `contentelement_published` (published model data per locale).

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

`MIWTContentElement` = where interactive Kotlin app UIs live; `componentidentifier` carries backing class, e.g. `.../MIWTContentElement:/co.proteus.reviewr.kotlin.ui.submission.NewSubmissionSignupComponent`.

## BeanBoxList {#beanboxlist}

`com.i2rd.cms.page.BeanBoxList` (`com/i2rd/cms/page/BeanBoxList.java`). Junction: "in this box, these content elements, in this order." Not a `PageElement`.

- **Table** `beanboxlist`, PK `beanboxlist_id`. Column `box_id` (→ `box`, unique), `lastmodtime`.
- Ordered contents: join table `beanboxlist_elements` (`beanboxlist_id`, `contentelement_id`, `order_id`).
- Page/template links via `page_beanboxlist` / `pagetemplate_beanboxlist`.

## PageElementPath {#pageelementpath}

`net.proteusframework.cms.PageElementPath` (`net/proteusframework/cms/PageElementPath.java`). Maps site URL path to `Page` or `ContentElement`.

- **Table** `pageelementpath`, PK `pageelementpath_id`.
- Columns: `site_id`, `path` (URL path, unique per site), `wildcard`, **polymorphic ("any") reference**: `pageelement_class` (target FQCN) + `pageelement_id` (target id). ~99% point at `Page`.
- Page's URL: `page.pageelementpath_id` → `pageelementpath.path`. Page's `path` = prefix (e.g. `s2/showcase`); requested URL appends wildcard path info (mirrored in `requeststatistic.pathinfo`).

### CMS URL path format

Request URL can target sub-tree of page, not just whole page. Full format
([VTDEV/CMS URL Path Format](https://proteusco.atlassian.net/wiki/spaces/VTDEV/pages/41091168/CMS+URL+Path+Format)):

```
[/partial][/content-type/${ContentType}][normal path][FdxbQVI${PageElementPath}]
```

- **/partial** — return only what `${PageElementPath}` targets, not whole page. Fetch one portion of page.
- **/content-type/...** — force response content-type (bypasses negotiation); type optionally percent-encoded (e.g. `application%2Fatom%2Bxml`).
- **normal path** — ordinary page path (e.g. `cms/article_demo/ac_box`), the `pageelementpath.path` prefix above.
- **FdxbQVI...** — page element path: prefix `FdxbQVI` (configurable default) + comma-separated element ids using `pathId` discriminators — `pg<id>` Page, `bx<id>` Box, `cb<id>` ContentElement. E.g. `FdxbQVIpg1191,bx728,bx730,cb3012` walks Page 1191 → Box 728 → Box 730 → ContentElement 3012. Ancestors **optional**: list can name just target element; **normal path can be omitted entirely** — `FdxbQVIcb1542` alone targets ContentElement 1542. When present, request params scoped to that sub-tree. Path only optional when targeting ContentElement — e.g. a Box can live on multiple pages with different content per page.

Examples:

- Fetch single content element directly (handy in analytics — given `contentelement_id` from `requeststatistic`, render just that element): `https://my.reviewr.com/partial/FdxbQVIcb1542`
- One content element as Atom feed, full path + forced content-type:
  `http://host/partial/content-type/application%2Fatom%2Bxml/cms/article_demo/ac_box/FdxbQVIpg1191,bx728,bx730,cb3012?FeedType=atom_1_0`

## How template → page content inheritance works {#inheritance}

1. `Page` has one `PageTemplate`; template has one `Layout`; layout defines ordered `Box`es.
2. Per box, content can be on **template** (default, `pagetemplate_beanboxlist`) and/or **page** (override, `page_beanboxlist`). Both resolve to `BeanBoxList` whose `beanboxlist_elements` give ordered `ContentElement`s.
3. Resolution (`Page.getElements(Box)`): page has non-empty `BeanBoxList` for box -> its elements win; else fall back to template's. Shared template = defaults; individual pages override per region.

`requeststatistic` records only resolved `page` + `contentelement` ids — **not** which box. To find box for recorded content element: join `beanboxlist_elements` → `beanboxlist` → `box`.
