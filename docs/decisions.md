# Decisions

Registro curto das decisoes tecnicas. Entrada nova no topo.

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
