---
name: forja-release
description: Use only when the user explicitly authorizes releasing an already-reviewed FORJA checkpoint to main/remote production.
---

# FORJA Release

Do not invoke this workflow from implementation approval alone.
The user must separately authorize release of the exact checkpoint.

Before mutation:
- confirm PR, base and exact head;
- confirm final CI green on that head;
- confirm final Security result;
- confirm no head movement.

Then:
1. update obsolete PR metadata only if needed;
2. squash merge using the approved repository method;
3. capture new `main` SHA;
4. run Supabase migration dry-run;
5. require that only the authorized migration(s) are pending;
6. if history diverges, STOP;
7. apply only the authorized migration through the normal migration workflow;
8. verify migration history exactly once;
9. verify Supabase health/advisors;
10. verify Vercel production corresponds to the merged main SHA.

Never:
- run arbitrary/manual SQL;
- access or mutate production user data;
- alter implementation during release;
- touch unrelated PRs/modules;
- silently work around failed deploys.

Return exact merge SHA, migration result, health/advisors, deployment ID/SHA, and final DEPLOYED or STOPPED status.
