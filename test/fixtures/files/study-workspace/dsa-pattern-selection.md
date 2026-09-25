# Chapter 01 - DSA Operating System and Pattern Selection

## Slice

Como transformar um problema ambiguo em pattern escolhido, complexidade defendida e resposta verbalizavel em vez de chute elegante.

## Study Context

- `Track order`: `01/06` - loop de entrevista antes da lista de problemas
- `Upstream principal`: [Tech Interview Handbook - Algorithms Study Cheatsheet](https://www.techinterviewhandbook.org/algorithms/study-cheatsheet/)
- `Upstream complementar`: [Tech Interview Handbook - Best Practice Questions](https://www.techinterviewhandbook.org/best-practice-questions/), [NeetCode Roadmap](https://neetcode.io/roadmap)
- `Pontes locais`: [Interview Checklist](../../snippets/system-design-interview-checklist.md), [Ruby / Rails Senior Question Bank](../../../../interview/story-bank/03-ruby-rails-senior-question-bank.md)
- `Review card`: [Card 01](../reviews/cards/01-dsa-operating-system-and-pattern-selection.md)

## Why This Matters In Interviews

A maior parte das pessoas nao perde entrevista porque esqueceu um truque raro.

Perde porque:
- comeca codando antes de esclarecer input e constraint
- nao nomeia o gargalo do brute force
- escolhe estrutura de dados tarde demais
- esquece edge case basico
- fala uma resposta "bonita" que cai no primeiro follow-up

## Interview Operating Loop

Use sempre esta ordem:

1. `Clarify`
   - tamanho do input
   - ordenado ou nao
   - duplicados
   - negativos
   - pode mutar input
   - Unicode importa
2. `Brute force`
   - mostre a primeira ideia correta, mesmo que lenta
3. `Bottleneck`
   - nested loop
   - recomputacao
   - lookup repetido
   - ordenar sem necessidade
4. `Pattern`
   - HashMap, window, DFS/BFS, heap, binary search, DP
5. `Complexity`
   - tempo
   - espaco
   - custo de mutar ou ordenar
6. `Edge cases`
   - vazio
   - 1 elemento
   - duplicado
   - sem resposta
   - ciclo ou grafo desconectado
7. `Speak and test`
   - rode `1` caso feliz
   - rode `1` armadilha

## The Real 80/20

Se voce so pudesse dominar o conjunto que mais se repete, eu priorizaria:

- `HashMap / Set`
  - lookup rapido, contagem, deduplicacao
  - exemplos: Two Sum, Valid Anagram, Longest Consecutive Sequence
- `Two pointers`
  - array ordenado, string, left/right squeeze
  - exemplos: Valid Palindrome, 3Sum, Container With Most Water
- `Sliding window`
  - substring, janela valida, frequencia
  - exemplos: Longest Substring Without Repeating, Minimum Window Substring
- `Prefix / suffix`
  - subarray, produto ou soma acumulada
  - exemplos: Product Except Self, Subarray Sum Equals K
- `Binary search`
  - monotonicidade e busca em resposta
  - exemplos: Search Rotated Array, Koko Eating Bananas
- `DFS / BFS`
  - arvore, grafo, grade
  - exemplos: Number of Islands, Clone Graph, Level Order
- `Heap / priority queue`
  - top K, stream, merge K
  - exemplos: Top K Frequent, Kth Largest, Merge K Lists
- `Intervals`
  - overlap, merge, ordering
  - exemplos: Merge Intervals, Meeting Rooms
- `DP basico`
  - estado, transicao, reuse
  - exemplos: Climbing Stairs, Coin Change, Word Break

Trie, Union Find, topological sort e backtracking entram logo depois. Nao ignore, mas nao comece por eles.

## Pattern Selection Heuristics

Quando voce estiver travado, pergunte:

- `preciso saber se algo ja apareceu?`
  - use HashMap ou Set
- `tenho uma janela valida que cresce e encolhe?`
  - use sliding window
- `o input ordenado me permite cortar espaco de busca?`
  - use binary search ou two pointers
- `preciso explorar vizinhos?`
  - use DFS ou BFS
- `quero o top K sem ordenar tudo?`
  - use heap
- `subproblema se repete e a resposta de hoje depende da de ontem?`
  - use DP

## Language Traps That Matter

### Ruby

- `Set` vive na stdlib: `require "set"`
- `queue.shift` em loop grande degrada; prefira array + ponteiro `head`
- ordenacao muta array; duplique se a mutacao for proibida
- se a entrevista pedir heap e voce nao tiver implementacao pronta, diga isso cedo e escolha entre:
  - implementar um binary heap pequeno
  - ou explicar que em producao usaria gem/abstracao pronta

### JavaScript / TypeScript

- use `Map` e `Set` para dicionario dinamico e membership
- `sort()` sem comparator ordena como string
- array como queue precisa de `head pointer`; `shift()` repetido custa caro
- em TypeScript, tipagem simples ja basta na maioria dos problemas:
  - `number[]`
  - `Map<string, number>`
  - `type Pair = [number, number]`

## Follow-ups That Reappear

Quase todo problema serio vira alguma destas perguntas:

- da para reduzir espaco?
- o input esta ordenado?
- posso mutar input?
- como fica com duplicados?
- e se vier em stream?
- e se o grafo tiver ciclo?
- e se for Unicode real e nao ASCII?
- isso escala para distribuido ou so para processo unico?

## Pattern Fire Drill

Antes de abrir o editor, responda em voz alta:

- `membership repetido`: HashMap ou Set
- `janela valida que cresce e encolhe`: sliding window
- `input ordenado com corte monotono`: binary search ou two pointers
- `vizinhos ou componentes conectados`: DFS ou BFS
- `top k sem ordenar tudo`: heap ou bucket
- `estado que reaproveita subproblemas`: DP

Se voce nao conseguir dizer `bottleneck -> pattern -> complexity` em menos de `60` segundos, rode primeiro:

- `bundle exec rake drills:ruby`
- `bundle exec rake drills:typescript`
- `interview/dsa-drills/README.md`

## Interview Compression

- `15 segundos`: fale constraint, brute force, gargalo e pattern antes de codar.
- `15 segundos`: o 80/20 real e HashMap, window, binary search, DFS/BFS, heap, intervals e DP basico.
- `1 minuto`: a pergunta certa nao e "qual problema e este?". E "qual estrutura reduz o gargalo que acabei de nomear?".

## Decision Synthesis

### Use When

- voce esta estudando DSA com ROI de entrevista
- quer parar de resolver problema por intuicao solta
- precisa verbalizar melhor o caminho antes de codar

### Why This Matters

- entrevista mede clareza sob ambiguidade, nao so sintaxe
- pattern selection economiza tempo e erro
- follow-up quase sempre testa se voce entendeu a estrutura, nao o problema original

### Main Trade-offs

- falar demais sem convergir atrasa
- codar cedo demais esconde erro de leitura
- explicar complexity sem edge case ainda deixa buraco

### Warning Signs

- voce abre o editor sem perguntar nada
- diz "acho que e DP" sem nomear estado
- usa `sort()` porque ficou sem ideia
- confunde fila, stack e heap na explicacao

## Production Recall

- `Pergunta`: qual e a ordem de resposta que mais reduz erro em entrevista DSA?
- `Resposta com as suas palavras`: clarificar, mostrar brute force, nomear gargalo, escolher pattern, declarar complexidade, testar edge case e so entao codar.
- `Resposta ruim que parece boa`: eu ja comeco pelo codigo otimizado para ganhar tempo.
- `Troque por isto`: velocidade sem leitura correta cria retrabalho e follow-up ruim.

## Fixacao Relampago

- `Pergunta`: quais patterns realmente formam o 80/20 de entrevistas DSA?
- `Resposta curta`: HashMap/Set, two pointers, sliding window, binary search, DFS/BFS, heap, intervals e DP basico.
- `Armadilha`: trie, segment tree e backtracking raro como ponto de partida.
- `Correcao`: comece pelo que reaparece, depois cubra o resto.
