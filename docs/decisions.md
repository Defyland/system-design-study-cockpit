# Decisions

Registro curto das decisoes tecnicas. Entrada nova no topo.

## 2026-06-29 - Documentar a arquitetura do cockpit e tirar o template Kamal do caminho de segredo real

- **Arquitetura e case study explicitos** em `docs/architecture.md` e
  `docs/engineering-case-study.md`. O cockpit ja tinha README forte e testes,
  mas ainda faltava uma leitura curta de boundary para avaliacao tecnica. A
  documentacao agora separa importacao de conteudo, camada adaptativa,
  simulacoes e surfaces web, com referencias diretas a services, models e
  testes.
- **Template Kamal movido para `.kamal/secrets.sample`** e `.kamal/secrets`
  passou a ser ignorado pelo Git. O arquivo rastreado nao tinha credencial bruta,
  mas o caminho colidia com a semantica de segredo local e piorava a prontidao
  para publicacao. A amostra preserva onboarding sem manter um arquivo de
  runtime secreto dentro da superficie publicada.

## 2026-06-29 - Publicar o cockpit sob MIT para reaproveitamento didatico

- **Licenca explicita** em `LICENSE.txt` e no `README.md`. O cockpit ja e
  publico, ensina adaptive drills, simulacoes e sincronizacao com
  `system-design-estudos`, mas sem licenca explicita o contrato de reuse ficava
  ambiguo.
- **Tradeoff aceito:** forks podem reutilizar a UX e os services sem contribuir
  de volta. Aqui isso e aceitavel porque o objetivo principal do repo e servir
  como asset de estudo e portfolio, nao como produto fechado.

## 2026-06-10 - Bump de Ruby e deploy gated

- **Ruby 3.3.6 -> 3.4.9**, alinhado ao repo de conteudo `system-design-estudos`.
  Atualizado em `.ruby-version`, `.tool-versions` e no `ARG RUBY_VERSION` do
  `Dockerfile` (que o Railway usa para buildar) para nao haver mismatch no deploy.
  O CI ja le `.ruby-version` via `ruby/setup-ruby`, entao pega 3.4.9 sozinho.
  Verificado em 3.4.9: `bundle install` (124 gems, extensoes nativas),
  `zeitwerk:check` e a suite (`bin/rails test`) verde.
- **Deploy gated no CI** (`.github/workflows/ci.yml`, job `deploy`). Sobe para o
  Railway com `railway up --ci` somente apos `scan_ruby`, `scan_js`, `lint`,
  `test` e `system-test` passarem, e apenas em push para `main`. Escolhido em vez
  de depender so do auto-deploy do dashboard para que nenhum deploy saia sem os
  checks passarem. Requer o secret `RAILWAY_TOKEN` (token de projeto); servico
  default `web`, sobrescrevivel pela variable `RAILWAY_SERVICE`.
