# System Design Study Cockpit

MVP Rails para guiar o estudo do repo `system-design-estudos`.

O cockpit nao substitui os textos. Ele cria uma camada de treino em cima deles:

- dashboard com progresso por chapter
- reader guiado com blocos de leitura
- checkpoints extraidos dos cards de fixacao do Markdown
- drills por chapter
- biblioteca de fundamentos, componentes, sistemas de IA e casos reais
- trilhas paralelas importadas do `curriculum.yml`, como `LLM Foundations`
- simuladores guiados com parametros, metricas e registro de julgamento
- prediction antes do reveal, confidence score e frase de decisao tecnica
- misconception ledger e sessao adaptativa sob demanda
- lembretes estilo post-it a partir de respostas hesitantes ou erradas
- mission e learning records por trilha para guardar estado do aprendiz
- sync local por filesystem e sync de producao via GitHub API

## Stack

- Ruby 3.4.9
- Rails 8.1
- PostgreSQL
- Minitest + system tests
- SimpleCov
- RuboCop Rails Omakase
- Brakeman
- bundler-audit

## Setup local

Este app deve ficar como irmao de `system-design-estudos`:

```txt
backend-challenges/
  system-design-estudos/
  system-design-study-cockpit/
```

Instale dependencias e prepare o banco:

```sh
bundle install
bin/rails db:prepare
```

Sincronize o conteudo local:

```sh
bin/rails study:sync_content
```

Suba o servidor:

```sh
bin/rails server
```

Abra `http://localhost:3000`.

## Sync de conteudo

O importador le:

- `curriculum.yml`
- `chapters/`
- `labs/chapters/`
- `reviews/cards/`
- `capstones/`
- `areas/06-foundations-distribuidas/topics/`
- `areas/07-componentes-de-sistemas/cards/`
- `areas/08-sistemas-ia/topics/`
- `simulation-labs/`
- `real-world-cases/**/README.md`
- `decision-contrasts/`
- side tracks declaradas em `curriculum.yml` com overview, source map, chapters e review cards

### Local

Por padrao, development usa filesystem e le:

```txt
../system-design-estudos
```

Override:

```sh
STUDY_CONTENT_PATH=/path/to/system-design-estudos bin/rails study:sync_content
```

### Producao

Production usa GitHub API por padrao.

Variaveis:

```sh
STUDY_CONTENT_MODE=github
STUDY_CONTENT_GITHUB_REPO=Defyland/system-design-estudos
STUDY_CONTENT_GITHUB_REF=main
GITHUB_TOKEN=...
```

Para sincronizar no boot do container:

```sh
STUDY_SYNC_ON_BOOT=true
```

## Auth

Em production, `STUDY_COCKPIT_PASSWORD` e obrigatoria.

```sh
STUDY_COCKPIT_USERNAME=study
STUDY_COCKPIT_PASSWORD=...
```

Em development/test, se `STUDY_COCKPIT_PASSWORD` estiver vazia, o app fica sem Basic Auth.

## Railway

Guia completo: [RAILWAY_DEPLOY.md](RAILWAY_DEPLOY.md).

O repo inclui `railway.json` para:

- build via `Dockerfile`
- `bundle exec rails db:prepare` antes do deploy
- healthcheck em `/up`
- restart em falha

Variaveis minimas do servico Rails:

```sh
RAILS_ENV=production
DATABASE_URL=${{Postgres.DATABASE_URL}}
RAILS_MASTER_KEY=...
STUDY_COCKPIT_PASSWORD=...
GITHUB_TOKEN=...
STUDY_SYNC_ON_BOOT=true
STUDY_CONTENT_MODE=github
STUDY_CONTENT_GITHUB_REPO=Defyland/system-design-estudos
STUDY_CONTENT_GITHUB_REF=main
```

Passos recomendados:

```sh
railway login
railway init --name system-design-study-cockpit
railway add --database postgres
railway up
railway domain
```

O `Dockerfile` tambem usa `bin/docker-entrypoint`, que executa `db:prepare` e, quando habilitado, `study:sync_content`.

## Qualidade

Comandos principais:

```sh
bin/rails test
bin/rails test:system
bin/rubocop
bin/brakeman --quiet --no-pager --exit-on-warn --exit-on-error
bin/bundler-audit
```

Atalho:

```sh
bin/ci
```

## Escopo do MVP

Este MVP e propositalmente pequeno:

- inclui simuladores de load balancer, cache, rate limit vs load shedding, circuit breaker e canary rollout
- inclui o nucleo adaptativo pragmatico, sem persistir sessoes completas
- nao cria projetos executaveis para snippets
- nao edita `system-design-estudos`
- nao usa login multiusuario
- nao tenta ser LMS completo

A regra e simples: estudar em sequencia, responder rapido, simular trade-offs, revelar feedback e gerar lembretes do que precisa voltar.

O desenho mais ambicioso do tutor adaptativo esta preservado em [docs/adaptive_tutor_blueprint.md](docs/adaptive_tutor_blueprint.md).
