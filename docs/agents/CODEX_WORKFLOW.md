# FORJA — Workflow do Codex

## Prompt mínimo padrão

```text
Continue o FORJA no checkpoint <CHECKPOINT>.
Leia AGENTS.md e somente os documentos autoritativos citados para este checkpoint.
Confirme origin/main antes de editar.
Respeite arquivos permitidos, TDD, draft PR, CI-first e no-remote-without-release.
Subagents: 0.
Pare após push + início da CI e reporte SHA/PR/run IDs.
```

## Tipos de rodada

### Review gate
Somente leitura. Sem branch, commit, PR ou produção.

### RED
Criar testes/fixtures/contratos que expressem o comportamento esperado.
Não implementar o comportamento.
Commit/push/draft PR/start CI/STOP.

### GREEN
Implementação mínima que satisfaz o RED.
Sem ampliar escopo.
Commit/push/start CI/STOP.

### Types sync
Somente quando o único gate restante for generated-types mismatch.
Nunca editar types manualmente.

### Final Security
Read-only no head exato final.
Subagents 0 salvo necessidade real da ferramenta.
Sem correções durante o scan.

### Release
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
- objetivo;
- documentos autoritativos;
- arquivos permitidos;
- critérios específicos;
- stop point.

Regras permanentes ficam no GitHub e não devem ser repetidas.
