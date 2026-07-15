# AGENTS.md - FORJA

## Google Drive e sincronização do FORJA

- O projeto local e o Git são a fonte de trabalho. A pasta oficial no Google Drive (`1ssfoevDng13hI6Fhu3kt3cpRxbw1z1ou`) mantém cópias validadas e backups.
- `index.html` é o arquivo principal. Arquivos de segurança, como `index.v33-working.html`, `index.before-video-ui.html` e backups datados, nunca devem ser sobrescritos automaticamente.
- Antes de cada tarefa, compare a versão local com a do Drive. Não conclua qual é a mais recente apenas pelo nome: confira conteúdo, tamanho, data de modificação e, quando disponível, o histórico do Git.
- Nunca sobrescreva o `index.html` do Drive antes de validar a versão local. Antes de substituí-lo, preserve a versão remota como `index.backup-AAAA-MM-DD-HHMM.html`.
- Após uma alteração funcional aprovada, sincronize o `index.html` validado. Prefira atualizar o arquivo existente e preservar seu ID; se isso não for seguro, faça backup e substituição controlada.
- Após qualquer envio, releia metadados ou liste a pasta para confirmar nome, ID, tamanho e data. Nunca afirme que houve sincronização sem confirmação do conector.
- Não envie arquivos temporários, caches, logs, segredos ou credenciais. Não registre credenciais neste arquivo e não instale pacotes MCP desconhecidos.
- Nunca exclua arquivos do Drive sem solicitação explícita. Em conflito entre versões, pare, compare e informe as diferenças antes de escrever.
- Em mudanças pequenas, sincronize apenas os trechos necessários do `index.html` quando a ferramenta permitir, preservando IDs e todas as funcionalidades do app.
- Teste antes de sincronizar. A validação mínima inclui sintaxe, erros JavaScript evidentes, IDs usados pelo código e carregamento básico da aplicação.
- No resumo final, informe alterações locais, arquivos enviados ao Drive, testes executados e a verificação feita após o envio.

## Procedimento obrigatório após cada tarefa

1. Ler este `AGENTS.md` integralmente.
2. Inspecionar o estado do Git, quando houver um repositório válido.
3. Criar backup antes de alterações de alto risco.
4. Fazer somente a edição necessária ao escopo.
5. Validar sintaxe, JavaScript, IDs relevantes e carregamento básico.
6. Resumir o que mudou e os testes executados.
7. Atualizar o arquivo principal local validado.
8. Criar backup da versão anterior do Drive.
9. Atualizar o `index.html` existente no Drive, preservando seu ID sempre que possível.
10. Confirmar o envio por releitura de metadados ou conteúdo.
11. Não excluir versões históricas.
12. Informar imediatamente erros ou conflitos; não ocultar falhas de sincronização.

## Uso das ferramentas do Google Drive

- Use primeiro a integração Google Drive já conectada.
- Localize a pasta pela URL ou pelo ID e confirme que o destino é a pasta oficial do FORJA antes de qualquer escrita.
- Use operações do conector para pesquisar, ler, consultar metadados, atualizar e verificar arquivos.
- Solicite aprovação apenas quando a própria ferramenta exigir autorização de escrita.
- Não instale outro servidor MCP quando a integração atual estiver funcional e não use pacotes MCP de origem desconhecida.
