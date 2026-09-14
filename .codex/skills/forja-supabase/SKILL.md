---
name: forja-supabase
description: Use for FORJA Supabase/Postgres schema, migration, RLS, RPC, generated-types, authorization, or concurrency work.
---

# FORJA Supabase

First use the FORJA checkpoint rules, then apply these database-specific constraints.

## Migration
- inspect migration history first;
- create exactly one forward-only migration for the authorized slice;
- never edit a migration already applied remotely;
- never invent a replacement baseline;
- no manual remote SQL as a normal implementation path.

## Security
- enable/force RLS where required;
- no broad browser mutation of sensitive tables;
- sensitive public RPCs derive caller from `auth.uid()`;
- caller-supplied author/client IDs are not authority;
- `SECURITY DEFINER` functions use locked `search_path=''`;
- private helpers remain unexposed;
- test cross-user/cross-tenant/role boundaries.

## Concurrency
When relevant, test stale revision, stale lease, replay, takeover, save races, and atomic finalization/destructive outcomes.

## Generated types
- generate `supabase/database.types.ts` from local Supabase only;
- never hand-edit;
- if CI reports only a types mismatch, stop and use the approved types-sync workflow;
- artifact publication is temporary and requires explicit authorization.

## Remote boundary
Implementation rounds are local/CI only.
Remote migration application belongs only to the separate FORJA release skill after explicit release authorization.
