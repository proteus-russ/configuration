---
name: pf-users-schema
description: >-
  Proteus Framework users/auth database schema — Principal, Role,
  PrincipalGroup, Credentials. Use when querying ANY PF-backed database
  (reviewr, engage, …) — local via psql/postgres MCP or remote via pssh —
  about users, principals, roles, groups, usernames, credentials, SSO
  accounts, or admin membership. Key trap: there is no `principal` table.
  Also triggers on `role_fk`, `principalgroup_principal`, "who is principal
  N", or joining people to submissions/events by user id.
---

# Proteus Framework users schema (Principal / Role / Credentials)

Applies to every PF-backed database (reviewr, engage, …), local or remote.
ORM source: `proteusframework/users/src/main/java/net/proteusframework/users/model/`.

## The trap: there is no `principal` table

`Principal extends Role` with **SINGLE_TABLE inheritance** — principals are
rows in **`public.role`** with discriminator `type = 'principal'`
(plain roles have `type = 'role'`). A principal's id IS its role id
(`role_id_seq`).

```sql
-- look up a principal
select id, programmaticname, status from role where type = 'principal' and id = 3650;
```

Useful `role` columns: `id`, `type`, `programmaticname`, `enabled`,
`status` (principal status: active/…), `contact_id` (FK → `contact`,
holds the human name/emails), `name_id`/`description_id` (localized keys,
resolve via `gettext(...)`).

## Usernames live on `credentials`, keyed by `role_fk`

`Credentials` is its own SINGLE_TABLE hierarchy (table
**`public.credentials`**, discriminator `type`: `password`, `saml`,
openauth subtypes…). The link to the principal is the join column
**`role_fk`** (from `Principal.getCredentials()` `@JoinColumn(name = "role_fk")`).

⚠️ `credentials.userid` is NOT the principal id (it's a varchar used by
SSO/external credential subtypes). Join on `role_fk`:

```sql
select c.role_fk as principal_id, c.username, c.type
from credentials c
where c.role_fk in (3650) and c.type = 'password';
```

SSO accounts (e.g. reviewr staff/admin, who are SAML+MFA) have a `saml`
credential row with a null `username` — identify them via `ssoid`/`nameid`
or the linked `contact`.

## Group membership

`PrincipalGroup` (table **`principalgroup`**) ↔ Principal membership is the
explicit entity table **`principalgroup_principal`**
(`principal_id`, `principalgroup_id`).

```sql
select principalgroup_id from principalgroup_principal where principal_id = 3650;
```

Well-known reviewr groups: 1 = Proteus Admin, 150 = Reviewr Administrators,
60090 = Reviewr API Administrators. Well-known roles: 1 = Proteus Admin,
2953 = I2RD Admin, 3050 = Reviewr Admin.

## Other relations

- `role_role` — role hierarchy (`Role.getChildren()` ManyToMany).
- `role_acegipermission` — permissions per role.
- `principal_authenticationdomain` style join tables come from the ManyToMany
  mappings on `Principal` (auth domains).
- `credentials_passwordhistory` — password history (`elt` column holds hashes).
- Localized names: resolve via `gettext(...)` (PF convention), e.g.
  `select id, gettext(name) from principalgroup`.
