# Analytics query cookbook

Ready-to-run PostgreSQL for `requeststatistic`. Run via `postgres` MCP. Every query lowercase + bounded by `requesttime` — keep it that way (tens of millions rows, archived periodically; unbounded scans slow, old rows gone). Adjust interval/`LIMIT` to taste. `LEFT JOIN` to `page`/`contentelement` (no enforced FK — see `requeststatistic.md`).

Filter notes:
- `status = 200` = successful views; drop to include redirects/errors.
- `partial = false` ≈ full page loads; `partial = true` ≈ in-page (AJAX/MIWT) interactions.
- `userprincipal IS NULL` = anonymous.

## Top pages by views (readable path)

```sql
SELECT pep.path AS page_path, count(*) AS views
FROM requeststatistic r
LEFT JOIN page p              ON p.page_id = r.page
LEFT JOIN pageelementpath pep ON pep.pageelementpath_id = p.pageelementpath_id
WHERE r.requesttime > now() - interval '30 days'
  AND r.partial = false
  AND r.status = 200
GROUP BY pep.path
ORDER BY views DESC
LIMIT 30;
```

`pagepath` (on stat row) = alternative grouping key, works when no page resolved — static assets, redirects, 404s.

## Top components / UIs interacted with

Headline "which part of page" query. `componentidentifier` = exact bean/Kotlin class; `name` = human label.

```sql
SELECT ce.name                AS component,
       ce.componentidentifier AS component_id,
       ce.disc_type           AS bean_type,
       count(*)               AS hits
FROM requeststatistic r
JOIN contentelement ce ON ce.contentelement_id = r.contentelement
WHERE r.requesttime > now() - interval '30 days'
  AND r.partial = true            -- in-page interactions, not passive page loads
GROUP BY ce.name, ce.componentidentifier, ce.disc_type
ORDER BY hits DESC
LIMIT 30;
```

## Engagement by MIWT / Kotlin UI class

Specific UI impl (e.g. Kotlin component): group by `componentidentifier`, pattern-match class.

```sql
SELECT ce.componentidentifier, count(*) AS hits
FROM requeststatistic r
JOIN contentelement ce ON ce.contentelement_id = r.contentelement
WHERE r.requesttime > now() - interval '30 days'
  AND ce.componentidentifier LIKE '%co.proteus.reviewr.kotlin.ui%'
GROUP BY ce.componentidentifier
ORDER BY hits DESC;
```

## Traffic over time (daily)

```sql
SELECT date_trunc('day', r.requesttime) AS day, count(*) AS requests
FROM requeststatistic r
WHERE r.requesttime > now() - interval '30 days'
GROUP BY day
ORDER BY day;
```

## Error rate by page

```sql
SELECT pep.path AS page_path,
       count(*)                                  AS total,
       count(*) FILTER (WHERE r.status >= 400)   AS errors,
       round(100.0 * count(*) FILTER (WHERE r.status >= 400) / count(*), 2) AS error_pct
FROM requeststatistic r
LEFT JOIN page p              ON p.page_id = r.page
LEFT JOIN pageelementpath pep ON pep.pageelementpath_id = p.pageelementpath_id
WHERE r.requesttime > now() - interval '7 days'
GROUP BY pep.path
HAVING count(*) FILTER (WHERE r.status >= 400) > 0
ORDER BY errors DESC
LIMIT 30;
```

## Slowest pages (by service time)

```sql
SELECT pep.path AS page_path,
       count(*)            AS samples,
       round(avg(r.servicetime)) AS avg_ms,
       max(r.servicetime)        AS max_ms,
       percentile_cont(0.95) WITHIN GROUP (ORDER BY r.servicetime) AS p95_ms
FROM requeststatistic r
LEFT JOIN page p              ON p.page_id = r.page
LEFT JOIN pageelementpath pep ON pep.pageelementpath_id = p.pageelementpath_id
WHERE r.requesttime > now() - interval '7 days'
  AND r.servicetime IS NOT NULL
GROUP BY pep.path
HAVING count(*) > 50
ORDER BY p95_ms DESC
LIMIT 30;
```

## Authenticated vs anonymous

```sql
SELECT CASE WHEN r.userprincipal IS NULL THEN 'anonymous' ELSE 'authenticated' END AS who,
       count(*) AS requests,
       count(DISTINCT r.sessionid) AS sessions
FROM requeststatistic r
WHERE r.requesttime > now() - interval '7 days'
GROUP BY who;
```

## Traffic by hostname

`requeststatistic.hostname` = readable host string (`CmsHostname.name`, e.g. `my.reviewr.com`) — group directly. One site can answer to many hostnames (vanity domains, internal VPC names, IPs) -> finer-grained than "by site".

```sql
SELECT r.hostname, count(*) AS requests, count(DISTINCT r.sessionid) AS sessions
FROM requeststatistic r
WHERE r.requesttime > now() - interval '7 days'
GROUP BY r.hostname
ORDER BY requests DESC;
```

Roll up by site: join `site`, resolve primary domain string: `requeststatistic.site` → `site.site_id`, then `site.domain` → `authenticationdomain.id` (readable string `authenticationdomain.domainname`). `site.domain` = `AuthenticationDomain` id, **not** hostname.

```sql
SELECT ad.domainname AS site_domain, count(*) AS requests
FROM requeststatistic r
JOIN site s                 ON s.site_id = r.site
JOIN authenticationdomain ad ON ad.id = s.domain
WHERE r.requesttime > now() - interval '7 days'
GROUP BY ad.domainname
ORDER BY requests DESC;
```

## Activity for one user

```sql
SELECT r.requesttime, r.pagepath, r.requestmethod, r.status, r.partial
FROM requeststatistic r
WHERE r.userprincipal = :principal_id
  AND r.requesttime > now() - interval '30 days'
ORDER BY r.requesttime DESC
LIMIT 200;
```

## Top user agents (browser mix)

```sql
SELECT r.useragent, count(*) AS requests
FROM requeststatistic r
WHERE r.requesttime > now() - interval '7 days'
  AND r.partial = false
GROUP BY r.useragent
ORDER BY requests DESC
LIMIT 20;
```
