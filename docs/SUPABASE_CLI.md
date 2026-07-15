# Supabase CLI no FORJA

## Arquitetura

O Supabase CLI fica fixado como dependÃªncia de desenvolvimento e as migrations versionadas sÃ£o a fonte de verdade do esquema. Pull requests validam localmente sem credenciais de produÃ§Ã£o. ApÃ³s merge na `main`, um workflow separado vincula o projeto, executa `db push --dry-run` e sÃ³ entÃ£o aplica migrations aprovadas.

O frontend continua publicado pelo Vercel. O workflow de banco nÃ£o depende de secrets do Vercel e nÃ£o altera `index.html`.

## Scripts histÃ³ricos, baseline e migrations futuras

- Arquivos SQL diretamente em `supabase/` sÃ£o histÃ³ricos e nÃ£o sÃ£o migrations pendentes.
- O baseline remoto `20260715144255_forja_remote_baseline` já foi registrado. A recuperação do arquivo local deve usar `supabase migration fetch --linked`; não execute outro `db pull` para esse baseline.
- Migrations futuras ficam exclusivamente em `supabase/migrations/` e sÃ£o criadas pelo CLI.

NÃ£o copie scripts histÃ³ricos para `supabase/migrations/` e nunca execute `db reset --linked`.

Enquanto `supabase/migrations/20260715144255_forja_remote_baseline.sql` não existir, a recuperação do baseline está pendente e nenhum `db push` deve ser executado. Antes de recuperá-lo, confirme Docker, credenciais de ambiente, projeto vinculado e o histórico remoto registrado.

## Recuperação temporária do baseline remoto

O workflow `Supabase baseline capture` foi convertido para recuperar o baseline já registrado e deve ser executado manualmente pela aba Actions, selecionando a `main`. Ele não possui gatilhos de `push`, pull request ou agendamento.

1. Informe exatamente `yncintjylzmvzcadjfqa` no campo obrigatório `confirm_project_ref`.
2. Aguarde a aprovação do environment `production`, quando essa proteção estiver configurada.
3. O workflow confirma que o histórico remoto contém exclusivamente `20260715144255_forja_remote_baseline` e executa `migration fetch --linked` para recuperar o arquivo local.
4. O `migration fetch` não reaplica, repara ou altera o histórico remoto. O nome recuperado é validado antes de qualquer dry-run.
5. O workflow exige que `migration list` fique alinhado e que `db push --dry-run` não encontre pendências. Nenhum `db push` real é executado.
6. Depois da reconstrução local, lint, advisors e geração de tipos, uma branch exclusiva e um novo pull request draft são publicados.
7. O pull request gerado inclui a migration, `supabase/database.types.ts` e a remoção do próprio workflow temporário.

Se o histórico remoto tiver outra migration, o Project Ref divergir, o Docker estiver indisponível ou o dry-run mostrar pendências, o workflow falha sem tentar reparar o histórico e sem abrir o pull request.

## InstalaÃ§Ã£o

```bash
pnpm install --frozen-lockfile
pnpm run supabase:version
```

## Criar uma migration

```bash
pnpm exec supabase --help
pnpm exec supabase migration --help
pnpm exec supabase migration new nome_da_alteracao
```

Edite apenas o arquivo gerado. Nunca invente o timestamp.

## Testar localmente

Docker precisa estar operacional:

```bash
docker info
pnpm exec supabase start
pnpm exec supabase migration list --local
pnpm exec supabase db lint --local --fail-on error
pnpm exec supabase db advisors --local --type all --fail-on error
pnpm exec supabase stop --no-backup
```

O workflow de pull request executa esse fluxo sem tokens, senhas ou banco remoto.

## Vincular e executar dry-run

Configure `SUPABASE_ACCESS_TOKEN`, `SUPABASE_DB_PASSWORD` e `SUPABASE_PROJECT_REF` somente no ambiente seguro:

```bash
pnpm exec supabase link --project-ref "$SUPABASE_PROJECT_REF"
pnpm exec supabase migration list --linked
pnpm exec supabase db push --linked --dry-run
```

O push real pertence ao workflow de produÃ§Ã£o apÃ³s merge na `main`.

## Gerar tipos

```bash
pnpm run supabase:types
```

O resultado fica em `supabase/database.types.ts` e nÃ£o contÃ©m credenciais.

## Interpretar `migration list`

O comando compara timestamps em `supabase/migrations/` com `supabase_migrations.schema_migrations`. Uma linha somente local indica migration ainda nÃ£o aplicada; uma linha somente remota indica divergÃªncia que deve ser investigada antes de qualquer push.

## Corrigir divergÃªncias sem apagar o banco

1. Pare o deploy e compare esquema, arquivos locais e histÃ³rico remoto.
2. Se o remoto foi alterado manualmente, capture o estado com `db pull`.
3. Use `migration repair` somente apÃ³s confirmar o estado real; ele altera apenas o histÃ³rico.
4. Nunca use reset remoto, apague tabelas para alinhar ambientes ou reaplique scripts histÃ³ricos.

## ConfiguraÃ§Ã£o do GitHub

- Secret `SUPABASE_ACCESS_TOKEN`.
- Secret `SUPABASE_DB_PASSWORD`.
- Variable `SUPABASE_PROJECT_REF` com o ref de produÃ§Ã£o.

Esses valores nÃ£o pertencem ao Git nem ao Vercel para o workflow do banco. Valores usados pelo navegador deixam de ser secretos mesmo quando fornecidos como variÃ¡veis de build; nunca exponha `service_role`, tokens privados ou senhas ao frontend.

## RecuperaÃ§Ã£o de falhas

Se a validaÃ§Ã£o local falhar, corrija a migration e repita os testes. Se o dry-run falhar, o workflow nÃ£o executa o push. Compare `migration list`, confirme o projeto vinculado e investigue a divergÃªncia. Se o push falhar parcialmente, nÃ£o repita cegamente: inspecione histÃ³rico e esquema antes de decidir entre migration corretiva ou `migration repair`.
