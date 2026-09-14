---
name: forja-final-security
description: Use for the single final read-only security review of an exact FORJA checkpoint head after CI is fully green.
---

# FORJA Final Security

This is read-only.

Inputs required:
- exact base SHA;
- exact final head SHA;
- checkpoint scope;
- evidence that required CI is green.

Review only the checkpoint delta.

Prioritize:
- auth/RLS/privilege boundaries;
- `SECURITY DEFINER` and search_path;
- cross-tenant/cross-professional access;
- caller spoofing;
- concurrency/TOCTOU;
- immutability/finalization;
- provenance and canonical snapshot integrity;
- private/sensitive data leakage;
- input bounds and denial-of-service surfaces;
- SQL injection/dynamic SQL;
- secrets.

Report Critical/High/Medium by exception.
LOW only when materially useful.

Do not change files, commit, push, merge, deploy, or apply remote database changes during this review.

If there are zero reportable C/H/M findings, state that clearly and STOP.
