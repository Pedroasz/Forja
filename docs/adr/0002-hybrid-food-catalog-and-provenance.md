# ADR 0002 — Catálogo híbrido de alimentos e proveniência

Data: 2026-07-21
Status: proposto, aguardando aprovações explícitas da especificação V4.2B.1

## Contexto

O FORJA usa um array local chamado `TACO` para busca e cálculo de quatro macros. O diário persiste ocorrências autossuficientes e offline-first. Planos profissionais persistem JSON e assignments imutáveis; itens aceitam texto livre e `foodId` normalmente nulo.

O produto precisa evoluir para alimentos genéricos, produtos de marca e itens privados com fontes rastreáveis, sem fazer históricos dependerem de um catálogo mutável. TACO, TBCA, Open Food Facts e USDA têm modelos, atualizações e termos diferentes.

## Decisão

Adotar a alternativa C, híbrida e incremental:

1. criar identidade canônica interna por UUID;
2. representar cada registro externo separadamente, com fonte, release/revisão, hash e lote;
3. modelar nutrientes, medidas e aliases como relações extensíveis;
4. usar o catálogo como referência para busca, edição e proveniência;
5. manter snapshots autossuficientes no diário e em assignments;
6. aceitar texto livre e referências nulas durante a transição;
7. separar catálogo público, alimentos privados e operações de importação por RLS/GRANTs/RPCs;
8. promover dados externos apenas por pipeline validado, idempotente e auditável;
9. adiar receitas, compartilhamento de alimentos privados e modelo detalhado de embalagens até haver caso de uso aprovado.
10. selecionar um perfil nutricional corrente completo por alimento, sem misturar valores de fontes diferentes implicitamente.

## Alternativas rejeitadas

### A — mover diretamente o array para uma tabela

Rejeitada porque preserva nome como identidade, não resolve proveniência e cria dependência de rede para um fluxo hoje offline-first.

### B — modelo genérico completo imediatamente

Rejeitada porque amplia schema, autorização e importação antes de validar fontes e consumidores, elevando o risco sem ganho imediato.

## Consequências positivas

- históricos não mudam quando fonte ou alimento muda;
- licenças e atribuições podem ser avaliadas por fonte e release;
- novos nutrientes entram como dados;
- TACO/TBCA/OFF/USDA não perdem a identidade nativa;
- privado permanece isolado;
- importações podem ser repetidas, auditadas e revertidas por lote.

## Consequências negativas

- haverá um período com adaptador entre array local e catálogo remoto;
- referências e snapshots duplicam parte dos dados de propósito;
- busca, RLS e importação exigem testes além de uma tabela simples;
- deduplicação canônica requer governança humana e não pode ser inferida só por nome/barcode.

## Guardrails

- Sem importação TBCA antes de autorização comercial escrita.
- Sem bulk merge de Open Food Facts antes de decisão ODbL documentada.
- Sem converter `missing`, `NA`, `ND` ou `trace` em zero.
- Sem hard-delete de alimento referenciado.
- Sem acesso `anon` na fundação, salvo nova aprovação.
- Sem consulta ao vivo obrigatória para renderizar diário ou assignment.
- Sem alteração retroativa de snapshot.

## Compatibilidade

- Schema 1 dos planos continua aceito.
- `foodId` permanece opcional.
- Nome, quantidade, unidade e macros legados continuam presentes na transição.
- Registros customizados históricos permanecem ocorrências; não viram entidades automaticamente.

## Evidências

- [Auditoria do sistema atual](../audits/v4.2b1-current-food-system-audit.md)
- [Especificação detalhada](../superpowers/specs/2026-07-21-v4.2b1-hybrid-food-catalog-design.md)
- [Plano da fundação B.2](../superpowers/plans/2026-07-21-v4.2b2-food-catalog-foundation.md)

## Revisão da decisão

Reavaliar após o piloto de uma fonte e antes de integrar produtos de marca, compartilhamento organizacional ou receitas. Mudança de estratégia de snapshot ou mescla ODbL exige novo ADR.
