# FORJA — Workflow do Codex

## Prompt mínimo padrão

```text
Continue o FORJA no checkpoint <CHECKPOINT>.
Use the matching FORJA repo skill(s).
Confirm origin/main before editing.
Follow the checkpoint plan.
Subagents: 0.
Push/start CI/STOP.
```

O prompt não deve repetir regras permanentes que já estejam em:
- `AGENTS.md`;
- `docs/agents/FORJA_RULES.md`;
- `docs/agents/SKILLS_POLICY.md`;
- skills locais em `.codex/skills/`.

## Tipos de rodada

### Review gate
Use `forja-checkpoint`.
Somente leitura. Sem branch, commit, PR ou produção.

### RED
Use `forja-checkpoint`; adicione `forja-supabase` quando houver banco.
Criar testes/fixtures/contratos que expressem o comportamento esperado.
Não implementar o comportamento.
Commit/push/draft PR/start CI/STOP.

### GREEN
Use `forja-checkpoint`; adicione `forja-supabase` quando houver banco.
Implementação mínima que satisfaz o RED.
Sem ampliar escopo.
Commit/push/start CI/STOP.

### Types sync
Use `forja-supabase`.
Somente quando o único gate restante for generated-types mismatch.
Nunca editar types manualmente.

### Final Security
Use `forja-final-security`.
Read-only no head exato final.
Subagents 0 salvo necessidade real da ferramenta.
Sem correções durante o scan.

### Release
Use `forja-release`.
Só após autorização explícita.
Merge + dry-run + migration esperada + health + Vercel.

## Stop points

- após RED pushado;
- após GREEN pushado;
- após types sync pushado;
- após final Security;
- após release.

Nunca gastar sessão esperando GitHub Actions.

## Formato dos prompts

Prompts novos devem carregar apenas:
- checkpoint;
- SHA/base quando crítico;
- objetivo específico que ainda não está no plano;
- documentos autoritativos específicos;
- arquivos permitidos somente quando houver exceção;
- stop point.

Regras permanentes ficam no GitHub e não devem ser repetidas.
