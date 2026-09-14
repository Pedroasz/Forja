# FORJA — Estado do Projeto

Atualizar somente após checkpoint ou release confirmado.

## Produção atual

- Main: `2b33fc7e0f5be16b2c9996626c0cfde2f19d8514`
- V4.3A.2D: DEPLOYED
- Última migration de consultas: `20260813174405_consultation_measurements_v43.sql`
- PR #15: merged
- PR #10 (food catalog docs): congelado, draft, não tocar sem autorização.

## Consultas profissionais

Concluídos:
- A.2A — core relacional
- A.2B — autorização/RLS
- A.2C — lifecycle/lease
- A.2D — measurements/repeated readings

Próximo checkpoint autorizado:
- **A.2E — formula registry + synthetic calculation tests**

Estado exato:
- implementação A.2E ainda não iniciada;
- nenhum branch/PR A.2E confirmado;
- primeiro passo é o **Formula Review Gate**;
- o gate decide fontes, algoritmos, versões, coeficientes, população, exclusões, precisão e ordem de recomendação antes do RED.

Depois:
- A.2F — anamnesis/profession sections
- A.2G — publication/ack/auditing
- A.2H — attachments/PDF foundation
- visual checkpoint
- A.2I — minimal frontend integration

## Novo eixo aprovado para planejamento

Adicionar ao roadmap:
- social graph/community;
- activity feed;
- calendar;
- challenges/competitions;
- leaderboards;
- event participation;
- achievements/streaks.

Ainda não implementar. Primeiro especificar arquitetura/produto e sequenciar sem quebrar A.2E–A.2I.
