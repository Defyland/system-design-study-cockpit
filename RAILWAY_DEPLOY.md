# Railway Deploy

Este guia deixa o deploy pronto sem commitar secrets.

## 1. Antes do login

Rode:

```sh
script/railway-preflight
```

O preflight valida:

- CLI do Railway instalado
- repo Git limpo e com remote
- `railway.json` valido
- `config/master.key` presente localmente
- se o Railway CLI esta autenticado

Se o CLI ainda nao estiver autenticado, faca:

```sh
railway login
```

## 2. Variaveis necessarias

Antes de rodar o deploy, exporte:

```sh
export STUDY_COCKPIT_PASSWORD="replace-with-a-strong-password"
export GITHUB_TOKEN="replace-with-a-token-that-can-read-Defyland/system-design-estudos"
```

`RAILS_MASTER_KEY` nao precisa ser exportada. O script le `config/master.key` localmente e envia para o Railway sem imprimir o valor.

## 3. Deploy

Depois do login:

```sh
script/railway-after-login
```

Por padrao, o script usa:

```sh
PROJECT_NAME=system-design-study-cockpit
SERVICE_NAME=web
POSTGRES_SERVICE_NAME=Postgres
```

Overrides:

```sh
PROJECT_NAME=my-project SERVICE_NAME=app POSTGRES_SERVICE_NAME=Database script/railway-after-login
```

## 4. Validacao

O script tenta gerar um dominio Railway e imprime os proximos comandos.

Depois do deploy, valide:

```sh
railway status
railway logs --service web
railway open
```

No browser, verifique:

```txt
/up
/
```

## Variaveis configuradas no Railway

O script seta no servico Rails:

```sh
RAILS_ENV=production
DATABASE_URL=${{Postgres.DATABASE_URL}} # ajustado por POSTGRES_SERVICE_NAME
RAILS_MASTER_KEY=<from local config/master.key>
STUDY_COCKPIT_USERNAME=study
STUDY_COCKPIT_PASSWORD=<from env>
GITHUB_TOKEN=<from env>
STUDY_SYNC_ON_BOOT=true
STUDY_CONTENT_MODE=github
STUDY_CONTENT_GITHUB_REPO=Defyland/system-design-estudos
STUDY_CONTENT_GITHUB_REF=main
```

## Observacao

`Defyland/system-design-estudos` esta privado. Portanto, `GITHUB_TOKEN` e necessario para o sync em producao.
