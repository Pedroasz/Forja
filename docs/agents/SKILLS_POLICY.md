# FORJA — Política de Skills

O objetivo é reduzir prompts e reutilizar procedimentos sem copiar instruções gigantes em cada turno.

## Skills locais do repositório

O FORJA mantém skills em `.codex/skills/`:

- `forja-checkpoint` — início/continuação de checkpoints, RED/GREEN e stop points.
- `forja-supabase` — migrations, RLS, RPCs, types e concorrência.
- `forja-final-security` — revisão final read-only no head exato.
- `forja-release` — merge/deploy remoto somente após autorização explícita.
- `forja-design` — arquitetura visual, UX, frontend, calendário/social/desafios e revisão anti-"cara de IA".

Use a combinação mínima necessária.

Exemplos:
- A.2E Formula Review Gate: `forja-checkpoint` apenas.
- A.2E RED/GREEN de banco: `forja-checkpoint` + `forja-supabase`.
- Security final: `forja-final-security`.
- Release: `forja-release`.
- Design/UI: `forja-design` + `brainstorming` quando houver criação visual/UX nova.

## Skills gerais disponíveis

Quando instaladas/disponíveis no ambiente Codex, preferir as skills oficiais/especializadas em vez de reescrever o procedimento no prompt.

Prioridade FORJA:
- brainstorming — antes de nova funcionalidade/arquitetura quando requisitos ainda precisam ser explorados;
- writing-plans — para specs multi-etapas antes de implementação;
- test-driven-development — feature/bugfix;
- systematic-debugging — bugs e falhas inesperadas;
- using-git-worktrees — isolamento de feature quando necessário;
- verification-before-completion — antes de afirmar conclusão;
- requesting-code-review / receiving-code-review — revisões;
- finishing-a-development-branch — integração final quando aplicável;
- Supabase skill — tarefas Supabase;
- Supabase Postgres best practices — schema/query/performance.

## Regra de portabilidade

As skills locais via Git viajam com o repositório.

Skills externas/instaladas no `$CODEX_HOME` não viajam automaticamente entre PCs/contas. Se ausentes:
- não inventar que estão instaladas;
- seguir as skills locais + documentos do repo;
- opcionalmente instalar a skill externa por mecanismo oficial quando o usuário pedir.

Não copiar o corpo integral de skills oficiais de terceiros para o FORJA. Referenciar a capacidade e manter no repo apenas a lógica específica do projeto evita versões congeladas/desatualizadas.

## Prompt futuro

O prompt pode ser reduzido para algo como:

```text
Continue FORJA <checkpoint>.
Use the matching FORJA repo skill(s).
Confirm origin/main.
Follow the checkpoint plan.
Subagents: 0.
Push/start CI/STOP.
```

Os detalhes permanentes vivem no GitHub.
