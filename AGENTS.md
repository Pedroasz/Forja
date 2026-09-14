# AGENTS.md — FORJA

Este arquivo é o ponto de entrada obrigatório para qualquer agente/Codex trabalhando no FORJA.

## 1. Ordem de leitura

Antes de qualquer alteração:

1. Leia `docs/agents/FORJA_RULES.md`.
2. Leia `docs/agents/PROJECT_STATE.md`.
3. Leia `docs/agents/SKILLS_POLICY.md`.
4. Leia `docs/agents/CODEX_WORKFLOW.md`.
5. Use a combinação mínima de skills locais em `.codex/skills/` que corresponda à tarefa.
6. Leia somente os ADRs/specs/planos citados pelo checkpoint atual.
7. Confirme `origin/main`, branch, PRs relacionados e worktree antes de editar.

Não releia documentos não relacionados ao escopo apenas por precaução.

## 2. Fonte de verdade

- GitHub/`origin/main` é a fonte oficial do código aprovado.
- `supabase/migrations/` é a fonte oficial do schema.
- ADRs/specs/planos em `docs/` são a fonte oficial das decisões.
- Supabase/Vercel representam o estado publicado.
- Google Drive é backup/cópia validada; não substitui Git como fonte de verdade.

## 3. Regra de execução

- Uma tarefa = um checkpoint/escopo claro.
- TDD: RED → GREEN → CI → final Security → release.
- Draft PR por padrão.
- Subagents = 0 por padrão.
- Codex para após push + início da CI; não espera Actions.
- Nenhum merge, migration remota, SQL manual, produção ou deploy sem autorização separada.
- Nunca acessar dados reais para validar feature.
- Não ampliar escopo para “limpeza” ou refatoração não solicitada.

## 4. Supabase

- Toda mudança de schema usa migration forward-only.
- Nunca editar migration já aplicada.
- RLS/GRANTs/RPCs seguem `docs/agents/FORJA_RULES.md`.
- Para trabalho Supabase, usar a skill local `forja-supabase` além da skill `forja-checkpoint`.
- `service_role` nunca no frontend.
- `database.types.ts` é gerado localmente e nunca escrito à mão.
- `db push` real só após merge, dry-run e autorização de release.
- Nunca `db reset --linked`.

## 5. Frontend e módulos protegidos

- `index.html` continua monolítico; não fazer refatoração ampla oportunista.
- DIETA e PR #10 ficam fora do escopo até autorização explícita.
- Preservar funcionalidades existentes.
- Mudanças visuais grandes somente em checkpoint autorizado.

## 6. Google Drive

A pasta oficial do FORJA no Drive é backup/cópia validada.

- Nunca sobrescrever automaticamente backups históricos.
- Nunca enviar segredos, caches ou temporários.
- Sincronizar Drive somente quando a tarefa pedir ou quando um release/checkpoint exigir cópia validada.
- Confirmar qualquer escrita por releitura/metadados.
- Nunca excluir arquivos sem solicitação explícita.

## 7. Novo eixo de produto

O roadmap agora inclui **Comunidade + Calendário + Competições**.

Antes de implementar, ler:
`docs/product/SOCIAL_CALENDAR_COMPETITIONS.md`

Esse eixo não deve interromper checkpoints A.2E–A.2I sem uma decisão explícita de repriorização.

Para qualquer trabalho visual/UX, usar a skill local `forja-design` e ler `docs/design/DESIGN_REFERENCES.md`.

## 8. Final obrigatório

Ao terminar, reporte:
- checkpoint;
- SHA/branch/PR;
- arquivos alterados;
- testes/CI;
- ações remotas;
- próximo gate.

Nunca declarar sucesso sem evidência verificável.
