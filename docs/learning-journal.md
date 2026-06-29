# Learning Journal

Este journal documenta a história do repositório até o commit `01eb8ec`, que é o
`HEAD` gravado no momento desta edição.

## Como este journal usa evidências

- Base primária:
  `git log`, `README.md`, `docs/decisions.md`, controllers, services de content
  import/adaptive session/simulation e os testes de modelo, service e system.

- Quando o texto fala de “camada adaptativa”:
  ele se apoia em serviços reais e modelos persistidos, não em marketing de IA.

## O que o histórico não prova

- O histórico não prova multiusuário em grande escala.
- Não prova tutor perfeito nem avaliação pedagógica universal.
- Não prova que toda inteligência do cockpit já está estabilizada; ele registra
  um núcleo adaptativo pragmático.

## 1. Objetivo do projeto

Este repositório existe para ensinar como colocar uma camada Rails interativa por
cima de um repositório de estudo sem sequestrar a autoria do conteúdo. O que ele
quer tornar explícito é:

- conteúdo e cockpit são sistemas diferentes;
- importação é boundary de produto;
- checkpoint, review schedule, misconception e simulation attempt são entidades
  úteis, não ornamento;
- side tracks e sync GitHub/local são parte do desenho.

Ao terminar este journal, o leitor deve conseguir:

- seguir a passagem de conteúdo bruto para experiência de estudo;
- explicar onde a camada adaptativa entra e onde ela não entra;
- apontar quais testes protegem o grafo curricular, os lembretes e os
  simuladores;
- reconstruir as principais viradas do cockpit até side tracks.

## 2. Como ler o repositório primeiro, em ordem de aprendizado

1. Leia `README.md`.
2. Leia `app/controllers/dashboard_controller.rb`,
   `app/controllers/chapters_controller.rb`,
   `app/controllers/side_tracks_controller.rb`.
3. Leia `app/services/content/importer.rb`,
   `app/services/content/filesystem_source.rb`,
   `app/services/content/github_source.rb`.
4. Leia `app/services/review_scheduler.rb`,
   `app/services/misconception_tracker.rb`,
   `app/services/adaptive_session_builder.rb`.
5. Leia `app/services/simulation_catalog.rb` e
   `app/services/simulation_engine.rb`.
6. Feche com:
   `test/models/curriculum_graph_test.rb`,
   `test/models/reminder_test.rb`,
   `test/services/content_importer_test.rb`,
   `test/services/adaptive_session_builder_test.rb`,
   `test/system/study_flow_test.rb`.

## 3. História cronológica da implementação

### Fase 1: MVP e deploy (`16ac032` a `f444053`, 2026-06-04 a 2026-06-05)

- O cockpit começou como MVP e rapidamente ganhou configuração de Railway e
  preparo de deploy.
- Isso indica que o produto nasceu para ser usado, não só demonstrado localmente.

### Fase 2: núcleo adaptativo e registry de conteúdo (`864d59a` a `9c9c2f6`, 2026-06-05 a 2026-06-07)

- Entram adaptive study cockpit, cache best effort, simulator hardening,
  curriculum graph e novos kinds de catálogo.
- O produto deixa de ser apenas reader e vira sistema de prática.

### Fase 3: consolidação de tentativa, lembrete e sync (`646e0d6` a `9611524`, 2026-06-07)

- A sequência deste dia inteiro gira em torno de tornar a camada adaptativa mais
  coerente: simulation attempts server-side, reminders por sinal de risco,
  deduplicação, assessment centralizado, contract explícito de tentativa,
  progress routed, unicidade de reminder source e review schedule.

### Fase 4: alinhamento operacional e side tracks (`6c34da5` a `01eb8ec`, 2026-06-10 a 2026-06-11)

- O repo alinha Ruby 3.4.9 ao conteúdo, adiciona deploy gated, registra decisões
  e finalmente trata side tracks como cidadãos de primeira classe.

## Features importantes como unidades completas

### Importação de conteúdo por filesystem e GitHub

- Problema que resolve:
  o cockpit precisa ler um repositório vivo sem virar cópia manual de markdown.

- Commits principais:
  `16ac032`, `66a621a`, `9c9c2f6`, `01eb8ec`.

- Arquivos principais:
  `app/services/content/importer.rb`,
  `app/services/content/filesystem_source.rb`,
  `app/services/content/github_source.rb`.

### Camada adaptativa, misconception e reminders

- Problema que resolve:
  não basta mostrar conteúdo; o produto precisa reagir ao desempenho.

- Commits principais:
  `864d59a`, `8603ad5`, `dfe67ed`, `38fa51a`, `dbc96f3`, `d4b725f`.

- Arquivos principais:
  `app/services/adaptive_session_builder.rb`,
  `app/services/misconception_tracker.rb`,
  `app/services/review_scheduler.rb`,
  models de `Reminder`, `ReviewSchedule`, `MisconceptionEvent`.

### Simulações como treino operacional

- Problema que resolve:
  system design estudado sem prática guiada vira lembrança fraca.

- Commits principais:
  `0446018`, `646e0d6`, `1e3a3f3`, `3ed0f6e`, `edb12f6`, `04ee399`.

- Arquivos principais:
  `app/services/simulation_catalog.rb`,
  `app/services/simulation_engine.rb`,
  `test/services/simulation_engine_test.rb`.

## 4. Decisão por decisão

- Conteúdo fora do cockpit:
  escolhido para preservar a source of truth no repo de estudo.

- Sync local e GitHub:
  escolhido para servir tanto desenvolvimento quanto produção.

- Adaptive core pragmático:
  escolhido para ajudar a prática sem prometer tutor mágico.

- Side tracks declaradas:
  escolhidas para não tratar trilhas paralelas como exceção ad hoc.

## 5. Prós e contras das escolhas principais

- Import separado:
  pró: preserva boundary.
  contra: aumenta custo de sync e parsing.

- Camada adaptativa persistida:
  pró: feedback e repetição mais úteis.
  contra: mais modelos e estados de consistência.

- Simulações server-side:
  pró: reduz confiança em input do cliente.
  contra: aumenta complexidade de backend.

## 6. Erros, correções e endurecimentos

- O histórico mostra várias correções de deduplicação e unicidade em lembretes e
  schedules, o que é típico de produto que amadurece de “funciona” para
  “permanece coerente”.
- Side track só virou entidade de primeira classe depois do núcleo principal
  estar mais estável.

## 7. Como os testes foram usados

- Fortemente em modelos e services.
- O produto depende menos de controller tests tradicionais e mais de grafo,
  lembrete, importação e simulação como unidades testáveis.

## 8. Timeline dos commits atômicos

| Commit | Pergunta que o commit responde | Mudança principal |
| --- | --- | --- |
| `16ac032` | Como nasce o cockpit? | MVP |
| `dd60c96` | Como preparar o deploy? | Railway config |
| `f444053` | Como publicar com segurança? | deploy workflow |
| `864d59a` | Como tornar o estudo adaptativo? | adaptive cockpit |
| `d5e1a45` | Como lidar com cache? | best-effort cache |
| `0446018` | Como endurecer simulações? | simulator hardening |
| `66a621a` | Como navegar o estudo? | curriculum graph |
| `9c9c2f6` | Como ampliar tipos de conteúdo? | new catalog kinds |
| `646e0d6` | Onde avaliar simulação? | attempts server-side |
| `8603ad5` | Como lembrar o que foi arriscado? | simulation reminders |
| `dfe67ed` | Como evitar duplicação? | reminder dedupe |
| `1e3a3f3` | Onde fica a avaliação? | centralized assessment |
| `3ed0f6e` | O contrato de tentativa é explícito? | explicit contract |
| `edb12f6` | Quem avalia a simulação? | backend engine |
| `04ee399` | O input é seguro? | whitelisted inputs |
| `06070e0` | Como atualizar progresso? | routed updates |
| `38fa51a` | Como deduplicar lembretes de checkpoint? | checkpoint reminder dedupe |
| `dbc96f3` | Reminder source é único? | uniqueness |
| `d4b725f` | Review schedule é único? | uniqueness |
| `9611524` | Como ampliar o conteúdo? | expanded study catalogs |
| `6c34da5` | Toolchain está alinhada? | Ruby 3.4.9 |
| `45aace6` | Deploy deve ser gated? | gated Railway deploy |
| `9fae246` | Como registrar decisões? | decisions journal |
| `01eb8ec` | Como tratar side tracks? | side track learning flow |

## 9. Perguntas de recuperação

- Onde o cockpit decide se lê do filesystem ou do GitHub?
- O que transforma conteúdo bruto em sessão adaptativa?
- Qual a diferença entre reminder, review schedule e simulation attempt?

## 10. Comandos de terminal que um specialist usaria aqui

```bash
git log --oneline --reverse
bin/rails study:sync_content
bin/rails test test/services/content_importer_test.rb
bin/rails test test/services/adaptive_session_builder_test.rb
bin/rails test test/services/simulation_engine_test.rb
bin/rails test
bin/rubocop
bin/brakeman --quiet --no-pager --exit-on-warn --exit-on-error
bin/bundler-audit
```

## 11. Como adicionar a próxima feature sem quebrar a aula

Se a próxima feature for um novo tipo de exercício:

1. declare como ele entra no import;
2. decida o modelo persistido mínimo;
3. explicite o contract de avaliação;
4. prove geração de reminder ou progress update, se existir;
5. só então exponha a UI.

## 12. Limites de produção deixados de propósito

- não tenta ser LMS completo;
- não prova multiusuário robusto;
- mantém o foco em learnability e feedback loop dentro do escopo do estudo.
