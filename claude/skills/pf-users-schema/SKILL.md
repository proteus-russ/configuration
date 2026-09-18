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

Applies to every PF-backed DB (reviewr, engage, …), local or remote.
ORM source: `proteusframework/users/src/main/java/net/proteusframework/users/model/`.

## The trap: no `principal` table

`Principal extends Role`, **SINGLE_TABLE inheritance** — principals = rows in **`public.role`** with discriminator `type = 'principal'` (plain roles `type = 'role'`). Principal id IS role id (`role_id_seq`).

```sql
-- look up a principal
select id, programmaticname, status from role where type = 'principal' and id = 3650;
```

Useful `role` columns: `id`, `type`, `programmaticname`, `enabled`, `status` (principal status: active/…), `contact_id` (FK → `contact`, human name/emails), `name_id`/`description_id` (localized keys, resolve via `gettext(...)`).

## Usernames on `credentials`, keyed by `role_fk`

`Credentials` = own SINGLE_TABLE hierarchy (table **`public.credentials`**, discriminator `type`: `password`, `saml`, openauth subtypes…). Link to principal = join column **`role_fk`** (from `Principal.getCredentials()` `@JoinColumn(name = "role_fk")`).

⚠️ `credentials.userid` NOT principal id (varchar for SSO/external credential subtypes). Join on `role_fk`:

```sql
select c.role_fk as principal_id, c.username, c.type
from credentials c
where c.role_fk in (3650) and c.type = 'password';
```

SSO accounts (e.g. reviewr staff/admin, SAML+MFA) have `saml` credential row with null `username` — identify via `ssoid`/`nameid` or linked `contact`.

## Human name: `contact.name` → `personname`

`role.contact_id` → **`public.contact`**, whose **`name`** column is an id into **`public.personname`**
(`first`, `last`, …). Not `contact.name_id`, and there is no `name` table.

```sql
select r.id as principal_id, pn.first, pn.last
from role r
join contact c on c.id = r.contact_id
join personname pn on pn.id = c.name
where r.type = 'principal' and r.id in (2);
```

## Group membership

`PrincipalGroup` (table **`principalgroup`**) ↔ Principal membership = explicit entity table **`principalgroup_principal`** (`principal_id`, `principalgroup_id`).

```sql
select principalgroup_id from principalgroup_principal where principal_id = 3650;
```

Well-known reviewr groups: 1 = Proteus Admin, 150 = Reviewr Administrators, 60090 = Reviewr API Administrators. Well-known roles: 1 = Proteus Admin, 2953 = I2RD Admin, 3050 = Reviewr Admin.

## Other relations

- `role_role` — role hierarchy (`Role.getChildren()` ManyToMany).
- `role_acegipermission` — permissions per role.
- `principal_authenticationdomain` style join tables — ManyToMany mappings on `Principal` (auth domains).
- `credentials_passwordhistory` — password history (`elt` column holds hashes).
- Localized names: `gettext(...)` (PF convention), e.g. `select id, gettext(name) from principalgroup`.
