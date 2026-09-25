# Cockpit — ambiente de estudo com fontes

Pedido: criar imagens primeiro, encaminhar à tarefa Sol 6 xhigh existente para implementação e receber sua devolutiva para avaliação na tarefa de origem `01a0d609-62f9-7853-8d81-c267308c8c85`.

## Referências visuais

- `01-library-guide.png`: biblioteca, seleção de fontes, retomada e guia com trecho original.
- `02-cards-quiz.png`: resposta em primeira pessoa, progresso de leitura e quiz com explicação.
- `03-map-mobile-review.png`: mapa navegável e revisão explicitamente escolhida no celular.

São propostas, não screenshots de funcionalidades existentes. Textos técnicos nas imagens são exemplos de composição: reutilizar os textos reais do acervo na implementação. Nomes, datas, contagens e fontes ilustrativas não devem virar dados de produção. Não implementar menus inventados pelo gerador (Notificações, Estatísticas, Configurações) por aparecerem na imagem. Navegação canônica: Estudar, Biblioteca, Revisão. Não copiar o nome Ana Costa. Esta especificação prevalece sobre inconsistências das imagens.

## Direção visual

Fundo #F6F5F1, superfícies brancas, texto carvão, verde #225B48 para ações e lavanda discreta para fontes. Bordas finas, leitura confortável, tipografia consistente com o projeto. Desktop: navegação estreita, área central de estudo e painel de fonte quando necessário. Mobile: uma coluna; fontes em painel acessível; ações ao alcance do polegar, sem cobrir conteúdo. Contraste WCAG AA, foco visível, teclado, disclosures acessíveis, estados de carregamento e erro sem perder a posição.

## Seis fluxos a implementar

1. Biblioteca e sessão: filtrar trilha e selecionar fontes existentes; informar seleção, oferecer retomada e nova rodada de até 50. Mostrar contagens reais. Preservar todos os assuntos e o acesso ao conteúdo original. Nenhuma importação externa ou geração paga necessária.
2. Guia com fontes: organizar seções e exercícios existentes em Entenda, Compare e Pratique; abrir exatamente o trecho citado. Não inventar sínteses ou comparações sem suporte. Se o acervo não contém comparação, mostrar as seções pertinentes sem apresentar uma comparação fabricada. Usar títulos claros para leitura original versus pergunta de entrevista.
3. Cards: manter pergunta, raciocínio em primeira pessoa quando existente, resposta, alternativas/condições e armadilhas. Disclosure fechado e aberto. Próximo, swipe, desfazer, salvar para revisão. Avanço é leitura, nunca acerto. Persistir posição e seleção após reload; impedir duplicação por requisição repetida ou tela desatualizada. Sem repetição automática.
4. Quiz: reaproveitar perguntas, respostas canônicas, distractors e explicações existentes do Arcade. Não converter qualquer parágrafo em uma pergunta inventada. Mostrar resposta escolhida, correção, justificativa e fonte; persistir tentativa e progresso; revisão voluntária dos erros. Ausência de perguntas elegíveis exige estado vazio honesto, sem fallback silencioso. Não confundir resultado do quiz com progresso de cards.
5. Mapa: navegação por trilha/documento/seção usando hierarquia ou relações reais disponíveis. Todo nó abre conteúdo de origem e permite iniciar estudo filtrado. Não deduzir relações semânticas arbitrárias: as setas técnicas desenhadas são ilustrativas, não uma ontologia aprovada. Rotular mapa do acervo quando só houver hierarquia. Fornecer alternativa em lista navegável por teclado.
6. Revisão no celular: escolher Guardados, Erros no quiz ou Concluídos; iniciar revisão só por ação explícita. Persistir itens guardados e permitir remover marcação sem apagar estudo. Fluxos vazios explicam como formar a lista. Progresso de leitura e resultado de avaliação separados.

## Limites e integração

Reutilizar Rails, Turbo/Stimulus, catálogo, importadores e avaliação existentes. Evitar novo framework e motor de IA. Não acrescentar chat, podcast, vídeo, geração remota ou assinatura como requisito deste escopo. Funcionalidades de áudio já existentes permanecem disponíveis nos seus fluxos. Preservar IDs, histórico, identidade do aluno, rotas existentes e conteúdos. Coordenar com a implementação do login e os testes de produção já pedidos nesta mesma tarefa; este pacote acrescenta o redesign, não cancela esses objetivos. Não alterar os sete arquivos sujos anteriores no checkout original sem necessidade e coordenação; preferir worktree isolado.

## Aceitação e devolutiva

Antes de alterações, registrar resultados observáveis e principais falhas. Exercitar o produto real com persistência e reload: seleção de fontes limita a rodada; citação abre trecho correto; card avança e desfaz sem perda; quiz registra resposta real e explica erro; mapa abre fonte correta; marcação e revisão persistem; nenhuma repetição não solicitada. Demonstrar que testes relevantes detectam defeito original ou quebra deliberada. Cobrir desktop e viewport móvel, teclado, vazio e fonte indisponível. Não apresentar testes unitários como prova do navegador.

Enviar à tarefa de origem via send_message_to_thread um relatório final com: commit/branch e worktree, arquivos, funcionalidades entregues versus pendentes, comandos e resultados, screenshots reais de cada um dos seis fluxos, comparação visual com estas pranchas e limites de produção. Solicitar avaliação final da tarefa de origem. Não declarar concluído sem testar. O pedido autoriza implementação; preparar evidências antes de pedir eventual autorização de publicação da nova mudança. Não presumir que o deploy anterior dos cards autoriza publicar automaticamente todo o redesign.

## Inspiração consultada

- https://blog.google/innovation-and-ai/models-and-research/google-labs/notebooklm-student-features/ — cards, quizzes, explicações e citações.
- https://blog.google/innovation-and-ai/models-and-research/google-labs/notebooklm-studying-help/ — mapas para explorar fontes.

Usar os mecanismos de estudo como referência, sem copiar marca ou prometer paridade integral com NotebookLM.
