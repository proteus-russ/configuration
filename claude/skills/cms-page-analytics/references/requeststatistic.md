# requeststatistic — schema, recording pipeline, joins

One row per HTTP request to CMS origin server. Raw material for all "how are people using the site" questions.

- **Entity:** `com.i2rd.cms.controller.RequestStatistic`
  (`proteusframework/cms/src/main/java/com/i2rd/cms/controller/RequestStatistic.java`)
- **Mapping:** `com/i2rd/cms/controller/RequestStatistic.hbm.xml` (same module)
- **Table:** `requeststatistic`, PK `requeststatistic_id` (sequence `requeststatistic_id_sequence`)

## Columns (verified lowercase names)

| Column | Type | Meaning |
| --- | --- | --- |
| `requeststatistic_id` | bigint | PK |
| `site` | bigint | → `site.site_id` (site/microsite served) |
| `page` | bigint | → `page.page_id` of resolved Page (null when none resolved) |
| `contentelement` | bigint | → `contentelement.contentelement_id`; last/handling content element in path (null on plain page loads) |
| `userprincipal` | bigint | authenticated principal id; **null = anonymous** |
| `hostname` | varchar | request hostname string — `CmsHostname.name` (table `hostname`, e.g. `my.reviewr.com`). Readable host; one site can have many hostnames |
| `pagepath` | varchar | resolved path, **relative, no leading slash** (e.g. `s2/showcase/Momentum-Awards-2022`) |
| `pathinfo` | varchar | wildcard remainder after page's path prefix |
| `query` | varchar | query string |
| `requesttime` | timestamp | when request occurred — **always filter on this** |
| `processtime` | int | processing time (ms) |
| `rendertime` | int | rendering time (ms) |
| `servicetime` | int | total service time (ms) — rank "slowest" by this |
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

## How rows recorded

Recording **asynchronous** — fresh requests lag couple seconds.

1. `RenderContext._gatherStats()`
   (`proteusframework/cms/src/main/java/net/proteusframework/cms/controller/RenderContext.java`)
   populates `RequestStatistic` at request teardown — sets `site`, `page` (when resolved PageElement is `Page`), `contentelement` (last `ContentElement` in path), `pagepath`, timing, user, locale, etc.
2. HTTP status/error captured on the fly by `CmsHttpResponseWrapper` (same package) as response written.
3. Stat handed to `Publisher.publish(stat)`, queued, drained by `RequestStatisticConsumer`
   (`com/i2rd/cms/controller/RequestStatisticConsumer.java`) — batch-saves (~1000 at a time, ~2s delay) via `StatisticsDAO.save(...)` (`com/i2rd/cms/dao/StatisticsDAO.java`).

## Join caveats

`page`, `contentelement`, `site`, `userprincipal` mapped `foreign-key="none"` + `not-found="ignore"` — **no enforced FK**. Page/content element can be deleted while old stat rows still reference it. So:

- **Always `LEFT JOIN`** from `requeststatistic` to `page`/`contentelement`, never inner — inner silently drops traffic to deleted elements.
- `page`/`contentelement` null (unresolved, static assets, redirects) -> group by `pagepath`.

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

In-app code: use `StatisticsDAO.getRequestStatistics(limit, site, page, hostname, user, remoteIP, sessionId, statusCode, dstart, dend)` — not hand-rolled HQL. Returns fully-loaded `RequestStatistic` entities with `getPage()` / `getContentElement()` populated.
