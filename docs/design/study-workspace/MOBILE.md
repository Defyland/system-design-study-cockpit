# Mobile: contrato de telas e interação

Complemento obrigatório do README. As três pranchas 04–06 definem 12 estados mobile; substituem a referência mobile parcial da prancha 03. Imagens são exemplos visuais, não conteúdo canônico.

## Layout comum

- Referência 390 × 844 CSS px; verificar também 320 × 568 e 430 × 932. Sem overflow horizontal da página. Código pode rolar dentro de seu bloco.
- Margens 16 px, espaçamento 8/16/24 px, texto de corpo mínimo 16 px, entrelinha 1.5, alvos de toque mínimos 44 × 44 px. Usar a mesma família sans-serif do desktop: o serif da prancha 04 é desvio do gerador, não mudança de identidade.
- Navegação inferior Estudar/Biblioteca/Revisão nas páginas de exploração. Destacar a seção realmente ativa (alguns destaques das imagens estão errados). Na sessão focada de card/quiz, usar Voltar no topo e ações inferiores; não empilhar a navegação global sob essas ações.
- Footer de ações respeita safe-area-inset-bottom e reserva sua altura no conteúdo; nunca esconde última linha ou campo com teclado aberto. Conteúdo longo rola normalmente, sem limitar altura para imitar o desenho.
- Ícones, logo e cores iguais em todas as telas; não copiar logos, slogans ou ícones divergentes gerados. Estado não depende apenas da cor. Foco, labels e leitores de tela precisam funcionar.

## 04 — Biblioteca, configuração, guia e fonte

A. Busca e filtros de trilha, seleção por checkbox e botão Escolher formato. Mostrar quantidade real; com zero selecionados, desabilitar o botão e explicar. Busca sem resultado mantém filtros editáveis. Retomar rodada é ação separada e preserva a seleção da rodada existente.

B. Voltar mantém seleção. Quatro formatos explícitos. Quantidade até 50 aplica-se a cards; quiz usa quantidade de perguntas elegíveis; guia/mapa não mostram quantidade de cards. Cards novos e revisão são modos separados: não oferecer checkbox que silenciosamente misture concluídos e inéditos. O texto 'prioriza' da imagem está incorreto: inéditos EXCLUI concluídos. Ausência de conteúdo elegível mostra estado vazio, nunca outro formato ou assunto automaticamente.

C. Guia em uma coluna, tabs Entenda/Compare/Pratique quando houver conteúdo real pertinente, bloco de código com scroll interno, citação clicável, botão para praticar. Não reescrever conteúdo original para preencher o layout.

D. Citação abre bottom sheet com título da fonte, seção, trecho real e acesso ao documento completo. Altura máxima aproximada de 85dvh, scroll interno. Fechar por botão, Escape e retorno do navegador restaura a posição e o foco de origem. Usar diálogo acessível com contenção de foco e fundo inerte; não exigir gesto de arraste para fechar. Fonte indisponível: mensagem explícita e Voltar, sem citações fabricadas.

## 05 — Card fechado/aberto e quiz antes/depois

A/B. Progresso persistido, bookmark com label Guardar/Guardado, pergunta e disclosure. Abrir resposta não marca feito. Feito avança, Desfazer reverte o último avanço. Swipe apenas na área do card e sem capturar scroll vertical, seleção de texto ou scroll do código; botão sempre disponível. Conteúdo expandido pode ultrapassar a tela. Rodada inicial sem avanço não oferece desfazer ativo.

C. Quiz mostra 'Ruby · Quiz', não 'Inéditos' como gerado. Selecionar radio não envia; Confirmar registra. Sem seleção, botão desabilitado. Não revelar resposta antes do envio. Desabilitar confirmação durante envio para evitar duplicação.

D. Depois da confirmação, mostrar alternativa correta e escolhida com texto/ícone, explicação e fonte reais. Próxima só após resultado salvo. Rever conceito não perde resposta/progresso. Card lido e resposta acertada continuam sendo registros distintos.

## 06 — Mapa, revisão, conclusão e falha

A. Lista hierárquica acessível é modo inicial mobile. Expandir nós sem navegação involuntária; selecionar nó mostra fonte e ação Estudar assunto. Modo Mapa oferece controles explícitos de zoom e enquadrar; alternativa Lista sempre visível, sem depender de pinch. Relações e contagens vêm do acervo; não reproduzir conexões técnicas fictícias das imagens.

B. Escolher Guardados/Erros no quiz/Concluídos, filtrar e selecionar itens. Erros no quiz são perguntas, não 'cards que você errou' como a imagem sugere. Quantidades reais; zero itens mostra orientação específica e não inicia sessão vazia. Revisar só por ação explícita; nenhuma recomendação inicia repetição automaticamente.

C. Conclusão usa total real da rodada (não fixa 50). Novos cards e Revisar concluídos são escolhas separadas. Se não há inéditos, explicar e manter revisão opcional. Nenhum timer ou redirecionamento automático.

D. Falha de salvamento mantém card e posição confirmada; mensagem persistente com Tentar novamente. Retentativa idempotente. Se a resposta do servidor se perdeu após gravação, reconciliar com estado persistido antes de avançar novamente. Nunca mostrar salvo em erro. Carregamento indica Salvando e bloqueia avanço duplicado; falha de rede não apaga texto/seleção.

## Evidências exigidas na devolutiva

Capturas reais dos 12 estados a 390 px e verificações funcionais em 320/430 px. Demonstrar fonte abrindo/fechando sem perder posição; seleção e bookmark persistindo após reload; quiz antes/depois sem vazamento da resposta; lista/mapa com fonte correta; revisão opt-in; conclusão; falha e retentativa sem duplicação. Testar teclado/foco e conteúdo longo. Declarar gestos físicos não testados se usar eventos sintetizados. Enviar resultado à tarefa de origem conforme README.
