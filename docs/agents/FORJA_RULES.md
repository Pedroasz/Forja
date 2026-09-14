# FORJA — Regras Canônicas do Projeto

Este documento concentra as regras permanentes do FORJA para reduzir prompts longos e evitar repetir contexto a cada tarefa.

## 1. Fontes de verdade

Ordem de autoridade:
1. `origin/main` no GitHub = fonte de verdade do código e do estado aprovado.
2. `supabase/migrations/` = fonte de verdade do schema.
3. ADRs, especificações e planos em `docs/` = decisões arquiteturais.
4. Supabase remoto/Vercel = estado de produção, nunca fonte para reconstruir código.
5. Google Drive = backup/cópia validada, não fonte primária.

Nunca escolher versão “mais nova” pelo nome. Compare SHA, Git e conteúdo.

## 2. Escopo

Antes de editar:
- identificar checkpoint;
- confirmar `origin/main`;
- revisar somente documentos autoritativos do checkpoint;
- listar arquivos permitidos;
- preservar módulos fora do escopo.

Não tocar em DIETA, catálogo de alimentos/PR #10, frontend, produção ou checkpoint futuro sem autorização específica.

## 3. TDD e checkpoints

Para mudanças de comportamento:
1. RED focado;
2. branch + draft PR;
3. GitHub Actions valida o RED;
4. GREEN mínimo;
5. GitHub Actions valida;
6. sincronizar tipos gerados quando necessário;
7. CI final verde;
8. uma única revisão final de segurança no head exato;
9. release exige autorização separada.

Não substituir teste real de banco por asserção estática para esconder falha.

## 4. Git e PRs

- Basear cada checkpoint no `origin/main` atual.
- Uma branch por checkpoint.
- Draft PR por padrão.
- Squash merge.
- Conventional Commits em inglês.
- Um commit = uma mudança lógica.
- Sem metadata de IA, Co-authored-by ou refs de issue/PR sem pedido explícito.
- Nunca force push.
- Nunca mergear ou marcar ready sem autorização.
- Nunca afirmar deploy/merge sem verificar remotamente.

## 5. Codex e economia de tokens

Padrão:
- GPT-5.6 Thinking.
- Medium para tarefas mecânicas/revisões restritas.
- High para migration, RLS, auth, concorrência e segurança.
- Subagents = 0 por padrão.
- Usar subagentes apenas quando indispensáveis.

Codex implementa. GitHub Actions testa. Usuário testa UX. ChatGPT revisa/orquestra. Security roda uma vez no head final.

Codex deve parar após push + início da CI. Não esperar Actions dentro da sessão.

## 6. Supabase

- Toda mudança de schema começa com uma migration forward-only.
- Nunca editar migration já aplicada em produção.
- RLS habilitada/forçada quando aplicável.
- Browser não recebe escrita direta em conteúdo clínico/sensível.
- RPCs sensíveis derivam o ator de `auth.uid()`.
- `SECURITY DEFINER` usa `search_path=''`.
- `service_role` nunca vai para frontend.
- Nenhum SQL manual remoto como fluxo normal.
- `db push` real somente após merge + dry-run + autorização de release.
- Nunca `db reset --linked`.
- Nunca acessar dados reais para testar feature.

## 7. database.types.ts

O arquivo deve ser gerado do Supabase local, não escrito à mão.

Se CI detectar mismatch:
- não enfraquecer o gate;
- artifact temporário só com autorização explícita;
- secret scan antes da publicação;
- retenção curta;
- sincronizar byte-for-byte;
- remover plumbing temporário;
- rodar CI final novamente.

## 8. Segurança

Antes de release:
- CI completa verde;
- actor/RLS/cross-tenant quando aplicável;
- concorrência quando aplicável;
- generated types exatos;
- uma revisão final Security no head exato.

Reportar Critical/High/Medium por exceção. LOW só quando útil.
Não corrigir warning apenas para “zerar linter” sem problema real.

## 9. Produção

Release é uma autorização separada da implementação.

Fluxo:
1. confirmar head e CI;
2. atualizar metadata do PR;
3. squash merge;
4. capturar SHA de main;
5. Supabase dry-run;
6. confirmar apenas migration esperada;
7. aplicar uma vez;
8. verificar histórico/health/advisors;
9. verificar Vercel production no SHA exato.

Se houver divergência, parar.

## 10. Frontend

O frontend atual é monolítico em `index.html`.
Não fazer refatoração ampla oportunista.

Direção visual:
- FORJA Performance Dark;
- premium esportivo/técnico;
- hierarquia forte;
- evitar template genérico, excesso de gradiente, gamer visual e cartões aninhados.

Integração visual grande só acontece no checkpoint explicitamente autorizado.

## 11. Consultas profissionais — guardrails

- Adultos vinculados, v1.
- Autor profissional é dono do registro.
- Finalizado = imutável.
- Correção = addendum/nova versão.
- Organização/admin não recebe conteúdo clínico.
- Consentimento e compartilhamento são explícitos e auditados.
- Histórico comum usa allowlist exata.
- Sem inferir referência fisiológica a partir de identidade de gênero.
- Campo fisiológico é privado e usado apenas quando a fórmula exigir.
- BIA manual é observação externa, não fórmula FORJA.
- Autosave server-side; sem localStorage/IndexedDB para conteúdo de consulta.
- Lease de edição: 1 editor; takeover explícito; conflito nunca sobrescreve silenciosamente.
- Attachments privados; publicação seletiva.
- Sem diagnóstico automático.

## 12. Novo eixo de produto — Comunidade, calendário e competição

O FORJA passa a ter um quarto eixo de produto além de treino, nutrição e acompanhamento profissional:

**Comunidade + Calendário + Competições.**

Princípios:
- social opt-in;
- privacidade por padrão;
- conteúdo clínico nunca entra no feed;
- competição usa métricas esportivas/consistência, não dados de saúde sensíveis;
- calendário coordena treino, consultas, eventos e desafios;
- rankings transparentes, determinísticos e auditáveis;
- evitar incentivos a comportamentos extremos;
- desafios têm critérios, período, elegibilidade e desempate versionados.

Detalhes: `docs/product/SOCIAL_CALENDAR_COMPETITIONS.md`.

## 13. Resposta final do agente

Retornar:
- checkpoint;
- SHA/branch/PR;
- arquivos alterados;
- validações;
- estado da CI;
- ações remotas realizadas ou “nenhuma”;
- próximo gate.

Nunca afirmar sucesso baseado apenas em intenção.
