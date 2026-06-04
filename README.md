# System Design Study Cockpit

MVP Rails para guiar o estudo do repo `system-design-estudos`.

O cockpit nao substitui os textos. Ele cria uma camada de treino em cima deles:

- dashboard com progresso por chapter
- reader guiado com blocos de leitura
- checkpoints extraidos dos cards de fixacao do Markdown
- drills por chapter
- lembretes estilo post-it a partir de respostas hesitantes ou erradas
- sync local por filesystem e sync de producao via GitHub API

## Stack

- Ruby 3.3.6
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

Variaveis minimas:

```sh
DATABASE_URL=...
RAILS_MASTER_KEY=...
SECRET_KEY_BASE=...
STUDY_COCKPIT_PASSWORD=...
GITHUB_TOKEN=...
STUDY_SYNC_ON_BOOT=true
```

O `Dockerfile` usa `bin/docker-entrypoint`, que executa `db:prepare` e, quando habilitado, `study:sync_content`.

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

- nao cria projetos executaveis para snippets
- nao edita `system-design-estudos`
- nao usa login multiusuario
- nao tenta ser LMS completo

A regra e simples: estudar em sequencia, responder rapido, revelar feedback e gerar lembretes do que precisa voltar.
