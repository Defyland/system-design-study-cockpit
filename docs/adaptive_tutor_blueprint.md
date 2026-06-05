# Adaptive Tutor Blueprint

Este documento guarda a estrutura mais impactante do cockpit: um tutor adaptativo de system design. O MVP atual implementa apenas o nucleo pragmatico: prediction, confidence, misconceptions e sessao adaptativa sob demanda.

## Objetivo

Transformar o cockpit em um tutor que escolhe o proximo treino com base no que voce erra, esquece ou responde com baixa confianca.

O foco nao e virar LMS. O foco e acelerar julgamento tecnico:

- quando usar
- por que usar
- quando nao usar
- o que quebra primeiro
- como mitigar
- como responder em entrevista

## Knowledge Components

No futuro, cada chapter, contrast, simulation lab e caso real deve mapear para componentes de conhecimento menores:

- idempotency
- cache freshness
- replica lag
- rollout safety
- rollback trigger
- rate limit fairness
- load shedding
- workflow compensation
- search freshness
- fanout trade-off
- auth boundary
- first metric

O mastery nao deve ser por chapter. Deve ser por decisao tecnica.

## Mastery Score

Cada knowledge component pode calcular score por:

- recall correto
- confidence calibrado
- misconception recente
- tempo desde ultima revisao
- transferencia para caso menor
- transferencia para caso big tech
- decisao correta em simulador

Um acerto com confidence baixo nao deve valer como dominio completo. Um erro repetido em contexto diferente deve reduzir mastery mais do que um erro isolado.

## Item Bank

Cada tema deve ter itens em niveis:

- definicao curta
- quando usar
- quando nao usar
- trade-off
- primeira metrica
- incidente em 15 minutos
- entrevista em 90 segundos
- pequena empresa
- grande escala
- contraste com solucao parecida

O tutor escolhe itens misturados para evitar leitura linear passiva.

## Worked Example Fading

O fluxo ideal:

1. mostrar resposta exemplar completa
2. esconder uma parte da decisao
3. esconder trade-off
4. esconder rollback/metricas
5. pedir resposta inteira

Isso reduz carga cognitiva no inicio e aumenta dificuldade progressivamente.

## Adaptive Session Persistida

Versao futura pode persistir sessoes:

- itens planejados
- itens completados
- tempo gasto
- resposta do usuario
- confidence
- resultado
- proxima revisao sugerida

O MVP atual gera sessao sob demanda para evitar complexidade prematura.

## Drills Cronometrados

Adicionar modos:

- 15 segundos: distincao tecnica
- 60 segundos: trade-off
- 90 segundos: entrevista
- 15 minutos: incidente

O objetivo e treinar resposta sob pressao, nao escrever texto bonito.

## IA Opcional

IA pode entrar depois para:

- avaliar resposta oral/textual
- detectar misconception sem regra fixa
- gerar variações de drills
- simular interviewer

Nao entra no MVP porque primeiro precisamos de sinais bons, dados historicos e fluxo estavel.
