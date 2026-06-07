# requeststatistic — schema, recording pipeline, joins

One row per HTTP request to the CMS origin server. This is the raw material for all "how are people
using the site" questions.

- **Entity:** `com.i2rd.cms.controller.RequestStatistic`
  (`proteusframework/cms/src/main/java/com/i2rd/cms/controller/RequestStatistic.java`)
- **Mapping:** `com/i2rd/cms/controller/RequestStatistic.hbm.xml` (same module)
- **Table:** `requeststatistic`, PK `requeststatistic_id` (sequence `requeststatistic_id_sequence`)

## Columns (verified lowercase names)

| Column | Type | Meaning |
| --- | --- | --- |
| `requeststatistic_id` | bigint | PK |
| `site` | bigint | → `site.site_id` (which site/microsite served the request) |
| `page` | bigint | → `page.page_id` of the resolved Page (null when no page resolved) |
| `contentelement` | bigint | → `contentelement.contentelement_id`; the last/handling content element in the path (null on plain page loads) |
| `userprincipal` | bigint | authenticated principal id; **null = anonymous** |
| `hostname` | varchar | the request's hostname string — a `CmsHostname.name` value (table `hostname`, e.g. `my.reviewr.com`). Use this for a readable host; one site can have many hostnames |
| `pagepath` | varchar | resolved path string, **relative, no leading slash** (e.g. `s2/showcase/Momentum-Awards-2022`) |
| `pathinfo` | varchar | wildcard remainder after the page's path prefix |
| `query` | varchar | query string |
| `requesttime` | timestamp | when the request occurred — **always filter on this** |
| `processtime` | int | processing time (ms) |
| `rendertime` | int | rendering time (ms) |
| `servicetime` | int | total service time (ms) — the one to rank "slowest" by |
| `status` | int | HTTP status code |
| `errorphrase` | varchar | error message when status ≠ 200 |
| `referer` | varchar | HTTP Referer header |
| `requestmethod` | varchar | GET / POST / … |
| `contenttype` | varchar | response content type |
| `useragent` | varchar | browser UA string |
| `userlocale` | varchar | user locale |
| `useripaddress` | varchar | client IP |
| `sessionid` | varchar | HTTP session id |
| `requestid` | varchar | unique per-request UUID |
| `partial` | boolean | **true = AJAX/in-page (MIWT) interaction**; false = full page request |

## How rows are recorded

Recording is **asynchronous**, so freshly-issued requests lag a couple of seconds before they appear.

1. `RenderContext._gatherStats()`
   (`proteusframework/cms/src/main/java/net/proteusframework/cms/controller/RenderContext.java`)
   populates a `RequestStatistic` at request teardown — sets `site`, `page` (when the resolved
   PageElement is a `Page`), `contentelement` (the last `ContentElement` in the path), `pagepath`,
   timing, user, locale, etc.
2. HTTP status/error are captured on the fly by `CmsHttpResponseWrapper` (same package) as the response
   is written.
3. The stat is handed to `Publisher.publish(stat)`, queued, and drained by `RequestStatisticConsumer`
   (`com/i2rd/cms/controller/RequestStatisticConsumer.java`) which batch-saves (~1000 at a time, ~2s
   delay) via `StatisticsDAO.save(...)` (`com/i2rd/cms/dao/StatisticsDAO.java`).

## Join caveats

The `page`, `contentelement`, `site`, `userprincipal` columns are mapped with `foreign-key="none"` and
`not-found="ignore"` — there is **no enforced FK**. A page or content element can be deleted while old
stat rows still reference its id. Therefore:

- **Always `LEFT JOIN`** from `requeststatistic` to `page`/`contentelement`, never inner, or you'll
  silently drop traffic to since-deleted elements.
- For requests where `page`/`contentelement` is null (unresolved, static assets, redirects), fall back
  to grouping by `pagepath`.

```sql
-- Resolve a window of requests to readable page + component labels.
SELECT r.requesttime, r.pagepath, r.status, r.partial,
       pep.path                AS page_path,
       ce.name                 AS component_name,
       ce.componentidentifier  AS component_id
FROM requeststatistic r
LEFT JOIN page p              ON p.page_id = r.page
LEFT JOIN pageelementpath pep ON pep.pageelementpath_id = p.pageelementpath_id
LEFT JOIN contentelement ce   ON ce.contentelement_id = r.contentelement
WHERE r.requesttime > now() - interval '1 day'
ORDER BY r.requesttime DESC
LIMIT 100;
```

## JVM-side query API

Code that needs these stats in-app should use `StatisticsDAO.getRequestStatistics(limit, site, page,
hostname, user, remoteIP, sessionId, statusCode, dstart, dend)` rather than hand-rolling HQL — it
returns fully-loaded `RequestStatistic` entities with `getPage()` / `getContentElement()` populated.
