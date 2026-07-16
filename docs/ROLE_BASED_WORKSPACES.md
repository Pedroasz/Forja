# Workspaces por papel no FORJA

## Objetivo

A V4.2A adapta a navegação ao papel real do usuário e centraliza as decisões de autorização do frontend. A interface nunca concede papéis: ela deriva workspaces e capacidades do usuário autenticado, do contexto devolvido pelo Supabase e das atribuições profissionais vigentes. RLS, ACLs e RPCs continuam sendo a autoridade para acesso aos dados.

## Valores reais do domínio

Os valores abaixo vêm do schema versionado e das RPCs atuais:

- tipo principal da conta: `individual`, `trainer`, `nutritionist`;
- modos combináveis: `individual`, `student`, `trainer`, `nutritionist`;
- papéis de plataforma: `platform_admin`, `support`;
- papéis de organização: `owner`, `admin`, `trainer`, `nutritionist`, `student`;
- tipos profissionais: `trainer`, `nutritionist`;
- status de organização: `active`, `suspended`, `archived`;
- status de membership: `pending`, `active`, `suspended`, `revoked`;
- status de relacionamento: `pending`, `active`, `rejected`, `revoked`;
- status de assignment: `active`, `superseded`, `revoked`.

Valores ausentes ou fora dessas listas não concedem workspace nem capacidade.

## Resolução de workspaces

O `WorkspaceService` calcula as opções disponíveis após cada login ou refresh de sessão:

- `trainer`: exige tipo principal `trainer` e modo `trainer`;
- `nutritionist`: exige tipo principal `nutritionist` e modo `nutritionist`;
- `student`: exige modo `student`, membership ativa como `student` ou relacionamento profissional ativo como aluno/paciente;
- `manager`: exige membership ativa como `owner` ou `admin` em organização também ativa;
- `admin`: exige o papel de plataforma `platform_admin`;
- `individual`: exige o modo pessoal ou o uso pessoal habilitado na conta.

O papel `support` não é promovido a administrador. Um modo isolado também não cria identidade profissional. A opção selecionada fica em uma chave de `localStorage` associada ao ID do usuário e é revalidada contra o contexto atual. Uma seleção removida ou inválida é descartada; quando nenhum workspace confiável puder ser derivado, a interface usa um fallback pessoal seguro, sem conceder operações profissionais.

O tipo principal é escalar no modelo atual. Uma mesma conta pode atuar como profissional e também como aluno/paciente, mas não pode operar simultaneamente como treinador e nutricionista sem uma futura evolução do modelo comercial.

## Navegação

Cada workspace mantém cinco destinos na navegação principal:

| Workspace | Entrada | Destinos |
| --- | --- | --- |
| Treinador | Alunos | Alunos, Treinos, Evolução, Feedbacks, Perfil |
| Nutricionista | Pacientes | Pacientes, Consultas, Dietas, Evolução, Perfil |
| Aluno/paciente | Meu treino | Meu treino, Minha dieta, Minha evolução, Feedbacks, Perfil |
| Individual | Início | Início, Dieta, Treino, Evolução, Perfil |
| Administrador/gestor | Dashboard | Dashboard e ferramentas existentes autorizadas |

Treinador e nutricionista não passam pelo dashboard genérico. `Feedbacks` e `Consultas` são apenas estados visuais nesta fase; não criam tabelas, prontuários, registros ou RPCs fictícios. As áreas profissionais reutilizam a tela de conexões com subrotas que isolam os painéis de cada domínio.

O aplicativo permanece oculto durante a resolução de perfil, conta comercial, modos, contexto de acesso, conexões e assignments. A navegação só é revelada depois que o workspace ativo foi validado, evitando o flash de conteúdo de outro papel.

## PermissionService

O `PermissionService` expõe capacidades centrais, incluindo:

- visualizar o dashboard;
- gerenciar alunos ou pacientes;
- criar templates de treino ou nutrição;
- editar prescrições pessoais de treino ou nutrição;
- registrar execução de treino ou adesão nutricional;
- visualizar feedback profissional;
- trocar de workspace.

Handlers de mutação consultam o serviço mesmo quando o respectivo botão está oculto. Ocultar componentes é somente uma decisão de apresentação e não substitui RLS ou os guards das RPCs.

## Prescrição versus registro

Treino e nutrição são domínios independentes.

Um treino é tratado como profissional somente quando existem, simultaneamente, assignment ativo e vigente, relacionamento ativo, tipo `trainer`, scope de gerenciamento de treino e, quando aplicável, organização e membership profissional ativas. A autorização é armazenada separadamente da data de vigência para que uma atribuição futura passe a ficar protegida na data correta mesmo offline. Nesse caso, a estrutura prescrita fica somente leitura, mas o usuário ainda pode iniciar o treino e registrar carga, repetições, conclusão e observações.

Uma dieta é tratada como profissional somente quando existem assignment ativo e vigente, relacionamento ativo, tipo `nutritionist`, scope de gerenciamento nutricional e, quando aplicável, organização e membership profissional ativas. Refeições, alimentos, quantidades e a exclusão da prescrição profissional ficam somente leitura. Diário, consumo, hidratação, adesão e observações pessoais continuam separados.

Um treinador nunca bloqueia a dieta e um nutricionista nunca bloqueia o treino. Um vínculo sem assignment vigente também não bloqueia o editor pessoal.

## Offline e armazenamento local

Workspaces, caches de assignments e dados pessoais usam chaves associadas ao usuário autenticado. O modo offline sem sessão usa um namespace próprio. Para preservar dados de versões anteriores sem criar vazamento entre contas, as chaves globais antigas são copiadas uma única vez pelo primeiro dono verificável: uma sessão persistida no bootstrap, um login explícito ou a escolha explícita do modo offline. Um marcador válido impede reivindicação posterior por outra conta; marcador corrompido falha fechado e não copia nenhum dado.

Assignments são evidência de autorização, não apenas cache. Para uma sessão autenticada, somente uma resposta RPC bem-sucedida torna a ausência de assignment confiável; reset, cache, offline ou erro de rede mantêm a edição estrutural bloqueada. Usuário offline sem sessão continua podendo usar seu espaço local independente. A fila de sincronização segue o mesmo namespace do usuário para não reenviar dados de outra sessão.

O comando **Apagar dados locais deste espaço** remove somente os dados e registros locais do dono atual, incluindo caches, rascunho de onboarding e snapshot de dieta. Ele nunca apaga dados remotos do Supabase nem namespaces de outro usuário. Se os dados globais legados pertencerem ao dono atual, são removidos e o marcador é mantido como tombstone para impedir uma nova reivindicação cruzada.

## Supabase, RLS e ACLs

A V4.2A não cria tabelas. A migration aditiva de hardening:

- restaura revogações de tabela e função que não foram preservadas no baseline capturado;
- mantém leitura autenticada e execução apenas das RPCs públicas necessárias;
- impede novos grants amplos por default privilege;
- restringe a leitura profissional de assignments de treino e nutrição a relacionamento ativo, tipo correto, scope correspondente, organização ativa e membership compatível;
- exige membership e organização ativas nas atribuições organizacionais de treino e nutrição, inclusive quando o template é pessoal;
- exige organização e membership profissionais ativas no entitlement de acompanhamento e na leitura/eligibilidade de prescrições organizacionais;
- inclui o status real da organização no contexto de acesso, impedindo workspace gestor para organizações suspensas ou arquivadas.

O aluno continua podendo ler o próprio histórico. Escritas de templates e assignments permanecem mediadas por RPCs `SECURITY DEFINER` com `search_path` vazio, validação de identidade, relacionamento, scope, ownership e organização.

## Limitações e próximos passos

- `Feedbacks` e `Consultas` ainda não possuem fluxo de dados.
- O modelo comercial ainda possui um único `primary_account_type`.
- Não há prontuário clínico, chat, upload de exames, cobrança ou automação por IA nesta fase.
- A V4.2B pode evoluir feedbacks e comunicação reutilizando as capacidades e rotas centralizadas, sem duplicar autorização no DOM.
