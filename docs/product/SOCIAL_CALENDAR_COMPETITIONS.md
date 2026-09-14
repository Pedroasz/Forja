# FORJA — Comunidade, Calendário e Competições

## Objetivo

Transformar o FORJA em uma plataforma de performance com:
- comunidade;
- calendário unificado;
- desafios;
- rankings;
- competição saudável;
- eventos.

## Social v1

- perfil público limitado;
- seguir/deixar de seguir;
- feed de atividades opt-in;
- reactions;
- comentários;
- compartilhar conquistas, treinos concluídos, participação em desafios e marcos;
- bloquear/silenciar/denunciar.

Nunca publicar no feed:
- conteúdo clínico;
- anamnese;
- medicamentos;
- condições;
- dados fisiológicos privados;
- anexos de consulta;
- raw BIA;
- notas internas profissionais.

## Calendário

Calendário único com:
- treino planejado;
- treino concluído;
- consulta/agendamento;
- desafio;
- prova/evento;
- lembrete;
- janela de meta.

O calendário referencia o módulo de origem; não duplica sua autoridade.

## Competições e desafios

Tipos v1:
- consistência;
- treinos concluídos;
- volume esportivo elegível;
- distância;
- duração;
- participação em calendário;
- desafio pessoal;
- grupo fechado;
- desafio público.

Não competir por:
- menor peso;
- menor ingestão;
- maior déficit calórico;
- menor percentual de gordura;
- métricas clínicas.

## Contrato do desafio

Todo desafio tem:
- ID/version;
- criador;
- visibilidade;
- início/fim/timezone;
- critério/unidade;
- elegibilidade;
- fontes de eventos aceitos;
- pontuação;
- desempate;
- política de edição;
- estado;
- auditoria.

Regra publicada não muda silenciosamente após entrada de participantes.

## Ranking

- determinístico;
- reproduzível;
- baseado em eventos aceitos;
- recalculável a partir de ledger;
- sem score arbitrário oculto.

Guardar eventos/ledger, não apenas total agregado.

## Fair play

Planejar:
- limites plausíveis;
- duplicidade;
- timezone;
- edição retroativa;
- atividade deletada;
- origem da atividade;
- janela de competição;
- replay/idempotência;
- desempate;
- auditoria.

## Integração com profissionais

Treinador/nutricionista pode, quando autorizado:
- criar evento/consulta;
- criar desafio de grupo;
- acompanhar participação agregada compatível com escopo.

Social nunca amplia acesso a conteúdo privado.

## Roadmap sugerido

Depois de estabilizar a fundação atual:

### S.1 — Product/architecture spec
social graph, privacy matrix, calendar projection, challenge scoring.

### S.2 — Social graph
profiles/follows/blocks.

### S.3 — Activity ledger + feed
event model + publication controls.

### S.4 — Unified calendar
projections + eventos do usuário.

### S.5 — Challenges
definition, enrollment, scoring, leaderboard.

### S.6 — Frontend/social UX
feed/calendar/challenge screens.

### S.7 — Notifications
reminders/event-driven notifications.

Cada slice segue RED → GREEN → CI → Security → release.
