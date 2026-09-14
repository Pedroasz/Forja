---
name: forja-checkpoint
description: Use when starting or continuing any FORJA implementation checkpoint, including RED, GREEN, types-sync, or documentation-only product checkpoints.
---

# FORJA Checkpoint

Read in order:
1. `AGENTS.md`
2. `docs/agents/FORJA_RULES.md`
3. `docs/agents/PROJECT_STATE.md`
4. `docs/agents/CODEX_WORKFLOW.md`
5. only the ADR/spec/plan for the active checkpoint

Then:
- fetch/confirm `origin/main`;
- inspect related open/draft PRs and current worktree;
- identify the exact checkpoint and allowed files;
- do not broaden scope.

For behavior changes:
- RED first;
- push RED and start CI;
- STOP;
- after explicit continuation, implement minimum GREEN;
- push and start CI;
- STOP.

Do not wait for GitHub Actions inside the Codex session.

Never merge, deploy, access production data, or apply remote migrations through this skill.

Return:
- checkpoint;
- branch/head SHA;
- PR;
- changed files;
- local validation;
- workflow run IDs;
- next gate.
