# Implementação do ambiente de estudo

## Resultado observável

- Biblioteca: a trilha e os documentos escolhidos determinam uma rodada com no máximo 50 cards; a seleção e a posição permanecem após recarregar.
- Guia: Entenda, Compare e Pratique exibem apenas seções existentes; a citação abre a mesma seção no documento original.
- Cards: resposta e material auxiliar abrem por decisão do aluno; avançar registra leitura, desfazer restaura posição, requisição repetida não consome o próximo card e guardar é independente do progresso.
- Quiz: somente perguntas autoradas do Arcade com resposta e distractors elegíveis; a escolha persiste, mostra correção e explicação real, e erros só voltam por ação explícita.
- Mapa: trilha, documento e seção refletem a hierarquia real do acervo; cada seção abre a fonte e permite criar uma rodada filtrada.
- Revisão: Guardados, Erros no quiz e Concluídos têm listas e início explícito; remover marcação não altera leitura.

## Falhas importantes a detectar

- Fonte selecionada ignorada, documento removido, seção citada errada ou conteúdo sintetizado sem origem.
- Duplo envio ou formulário antigo avançando outro card; desfazer no limite; repetição automática.
- Quiz sem alternativas elegíveis fazendo fallback, resposta trocada após recarregar, explicação genérica em vez da autorada, ou contagem de quiz como leitura.
- Mapa apontando para seção inexistente; revisão iniciando sem clique, perdendo guardados ou apagando estudo ao desmarcar.
- Mobile cobrindo conteúdo, foco invisível ou controle inacessível pelo teclado.

## Progresso

- Pacote visual recebido e examinado; branch isolada `codex/study-workspace-redesign` criada sobre o login já publicado em `codex/cockpit-cookie-login`.
- Implementados os seis fluxos no Rails/Turbo/Stimulus existente, com duas migrations para fontes, guardados e quiz. A navegação canônica usa Estudar/Biblioteca/Revisão; o mapa indica apenas a hierarquia comprovada do acervo. O quiz admite apenas perguntas autoradas e elegíveis do Arcade.
- Testes inicialmente vermelhos: as rotas novas retornavam 404 e `StudyCardRound` ainda não possuía `source_ids`. Depois da implementação, `bin/rails test` passou com 416 testes e 32.227 asserções; `bin/rails zeitwerk:check` passou. Após os últimos ajustes de navegação e fixture, `bin/rails test test/controllers/study_workspace_test.rb test/system/study_workspace_mobile_test.rb:44` passou com 7 testes e 88 asserções. A execução completa do novo teste de sistema passou em cinco dos seis cenários; o sexto falhou somente porque o teste procurou o botão `+` pelo nome acessível via `click_button`, que não o localizou. O seletor explícito `button[aria-label='Ampliar mapa']` passou na reexecução do cenário.
- Teste funcional real em Chrome: seleção e retorno, guia e citação com Escape/Back e foco restaurado, cards com bookmark/reload/avanço/desfazer, quiz antes/depois e explicação autorada, mapa/lista com zoom e prévia ancorada, revisão escolhida, conclusão e falha de rede real via Chrome DevTools com retentativa idempotente. Há capturas de 12 estados mobile em 390 px e seis fluxos desktop em `tmp/screenshots/study-workspace/`; o teste também verifica falta de overflow em 320 e 430 px com código longo.
- No navegador integrado, o servidor local com acervo importado mostrou 335 documentos, 3.188 cards e 504 perguntas elegíveis; a fonte do primeiro quiz apontou para um documento importado real. A fixture do teste copia o documento original de DSA para preservar o link também no cenário reproduzível.
- Limites: os gestos físicos em aparelho não foram testados (a cobertura de swipe usa a interface e controles no Chrome); teclado virtual e deploy/produção do redesenho não foram verificados. O browser local e a suite não substituem a verificação de produção após publicação.
