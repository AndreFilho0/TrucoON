# Checkpoint 2 (19/11): o jogo replicado e por que a ordem importa

**Disciplinas:** Sistemas Operacionais e Sistemas Distribuídos (INF0344), UFG, 2026/2
**Grupo:** <nomes e matrículas>
**Código deste checkpoint:** tag `parte-2` (Parte 2 do enunciado)

Cada tópico segue a mesma estrutura:

- **Teoria:** o conceito como é visto em aula (SO e SD);
- **Na implementação:** como o conceito aparece no código, com os arquivos;
- **No jogo:** qual papel ele tem no truco online.

---

## 1. Onde paramos

No checkpoint 1, os processos trocam mensagens por UDP sem perder nenhuma e com as
mensagens de cada remetente em ordem (FIFO). Mas mensagens de remetentes diferentes
ainda chegam em ordens diferentes em cada processo. Agora as mensagens viram jogadas
de truco, e o efeito disso aparece no jogo.

## 2. A aplicação

- Truco mineiro para partidas privadas (1x1 ou 2x2): criar mesa, convidar por link ou
  QR code, escolher cadeira, jogar. Mobile-first, roda no navegador.
- Regras (baralho de 27 cartas, manilhas fixas, truco/seis/nove/doze, mão de 11, mão
  de ferro, partida até 12 tentos) escritas como **funções puras**:
  `lib/truco_on/truco/` (`deck.ex`, `evaluator.ex`, `rules.ex`, `game.ex`).
- Frontend em `app/` (Expo + React Native Web), servido por cada peer.
- Diagrama: `docs/diagramas/2-arquitetura.png`.

## 3. Replicação por máquina de estados

**Teoria.**
- Replicar um serviço em vários processos para ficar perto dos usuários e tolerar
  falhas.
- Máquina de estados replicada: se todas as réplicas começam no mesmo estado e
  aplicam os **mesmos comandos na mesma ordem**, terminam no mesmo estado.

**Na implementação.**
- Cada mensagem multicast é um comando: `{:create, ...}`, `{:join, ...}`,
  `{:seat, ...}`, `{:start, ...}`, `{:act, ...}`, `{:leave, ...}`, `{:rematch, ...}`.
- `lib/truco_on/truco/rooms.ex`: `Rooms.apply/2` aplica um comando à base de mesas.
- `lib/truco_on/peer/replica.ex`: recebe os comandos na ordem entregue pelo multicast
  e aplica.
- Ponto central: o servidor **não aplica** a jogada do próprio jogador na hora. Ele
  manda para o grupo, espera a entrega pelo multicast como todo mundo, e só então
  responde. Diagrama: `docs/diagramas/2-fluxo-comando.png`.

**No jogo.**
- Cada servidor de jogo (uma "região") tem uma cópia completa de todas as mesas.
  Amigos ligados a servidores diferentes jogam na mesma mesa.

## 4. Determinismo

**Teoria.**
- A replicação por máquina de estados só funciona se aplicar um comando der sempre o
  mesmo resultado. Relógio local, números aleatórios e timers quebram isso.

**Na implementação.**
- Embaralhamento com gerador pseudoaleatório de estado explícito
  (`:rand.seed_s/2`), com a semente enviada no comando `:create` (`truco/deck.ex`).
- Sem timers nem relógio: o servidor de jogo original do melivra tinha timeout de
  abandono e limite de requisições pelo relógio local. Aqui tudo que muda o estado é
  comando.
- Código da mesa sorteado por quem cria e enviado no comando. Se colidir, todas as
  réplicas rejeitam igual (`:code_taken`).

**No jogo.**
- Todas as réplicas distribuem **as mesmas cartas** para os mesmos jogadores.

## 5. Condição de corrida: por que a ordem é crítica

**Teoria.**
- SO: condição de corrida, quando o resultado depende da ordem em que processos
  concorrentes acessam um dado compartilhado; seção crítica.
- SD: o mesmo problema entre réplicas. Comandos concorrentes chegam em ordens
  diferentes e cada réplica decide de um jeito.

**Na implementação.**
- `Rooms.apply/2` é determinística, então a única fonte de diferença é a ordem.
- Medição com `S.seat_race(rooms: 8)` (`lib/truco_on/control/scenario.ex`), 4 peers:
  **8 de 8 mesas divergentes**, tanto em `none` quanto em `fifo`.
- Teste automático: `test/truco_on/integration/divergence_test.exs`.

**No jogo.** Três situações em que as réplicas divergem:
1. **Disputa de cadeira:** Bia e Caio pedem a cadeira 0 ao mesmo tempo, por servidores
   diferentes. Cada réplica dá a cadeira para quem chegou primeiro nela. Diagrama:
   `docs/diagramas/2-divergencia.png`.
2. **Truco × carta:** Ana joga a carta que fecha a mão enquanto Duda pede truco. Numa
   réplica a mão vale 3; na outra, vale 1. O placar diverge.
3. **Aceito × fujo no 2x2:** os dois parceiros respondem ao truco ao mesmo tempo, com
   respostas diferentes.

## 6. Sincronização dentro do servidor: um único escritor

**Teoria.**
- SO: exclusão mútua (mutex, semáforo) e o problema dos **leitores e escritores**.

**Na implementação.**
- `Replica` é um GenServer: processa uma mensagem por vez da sua caixa de entrada.
  Por ser o **único escritor** da base de mesas, não precisa de lock.
- O estado é publicado numa tabela **ETS** com `read_concurrency: true`. Os processos
  dos jogadores leem dela sem entrar na fila da `Replica`: vários leitores, um escritor.
- As mensagens entre processos Erlang são copiadas, então não há memória
  compartilhada para disputar.

**No jogo.**
- Muitos jogadores olhando a mesa ao mesmo tempo não atrasam quem está jogando.

## 7. Processos, supervisão e tolerância a falhas

**Teoria.**
- SO: hierarquia de processos (pai e filho), término e tratamento de falhas.

**Na implementação.**
- Árvore de supervisão OTP: `lib/truco_on/peer.ex` com estratégia `rest_for_one`. Se o
  multicast cai, os processos que dependem dele são reiniciados junto.
- Cada jogador conectado é um processo (`lib/truco_on_web/channels/room_channel.ex`).
  Se ele cai, morre sozinho e não afeta os outros.
- Diagrama: `docs/diagramas/2-supervisao.png`.

**No jogo.**
- A conexão de um jogador caindo não derruba a mesa nem o servidor.

## 8. Com estado × sem estado

**Teoria.**
- Servidores sem estado escalam e se recuperam fácil; servidores com estado guardam
  sessão e dados.

**Na implementação.**

| Camada | Tipo | Estado |
|---|---|---|
| REST (`/api/session`, `/api/rooms`) | sem estado | identidade num token assinado (HMAC) |
| WebSocket (`RoomChannel`) | com estado de sessão | um processo por jogador |
| `Replica` | com estado | único escritor da base de mesas |
| ETS | cache local | leitura concorrente |

**No jogo.**
- Jogador entra como convidado (apelido + token). O token vale em qualquer servidor,
  porque todos compartilham o segredo.
- Código de convite de 8 caracteres sem símbolos ambíguos (sem 0/O, 1/I/L), no link
  e no QR code (`truco/code.ex`).

## 9. Verificação das réplicas

**Na implementação.**
- Cada réplica expõe um **hash encadeado** da sequência de comandos (muda se a ordem
  mudar) e um hash por mesa.
- `V.replicas()` compara os hashes entre os peers.

**No jogo.**
- O painel **⚙ Réplicas** da interface mostra os hashes ao vivo: verde quando as
  cópias são iguais, vermelho quando divergiram.

## 10. Melhorias no código-base do MPComm

| MPComm | TrucoON |
|---|---|
| IPs fixos em `constMP.py` | variáveis de ambiente |
| `unregister` não implementado | implementado |
| `recv(2048)` pode truncar | prefixo de tamanho (`packet: 4`) |
| Espera ativa (100% de CPU) | timers |
| `pickle.loads` em dados da rede | `binary_to_term(bin, [:safe])` |
| Comparação ignora o último peer | compara tudo + perdas, duplicatas, FIFO |
| Processos soltos | supervisores OTP |
| Sem testes | testes automatizados com peers reais |

Lista completa: `docs/parte-2-aplicacao.md`.

## 11. Demonstração prática

```bash
scripts/build_web.sh
ORDERING=fifo DELAY_MAX=60 scripts/up.sh 3
```

1. Abrir `http://localhost:4001`, criar uma mesa 2x2 e abrir o painel ⚙ Réplicas.
2. Abrir o link de convite em abas anônimas, nas portas `:4002` e `:4003`, para cada
   jogador ficar num servidor diferente.
3. Todos tocam em "Sentar" ao mesmo tempo, ou `scripts/run.sh 'S.seat_race(rooms: 8)'`.
4. O painel fica vermelho: as réplicas divergiram.

## 12. Conclusão e gancho para o checkpoint 3

O jogo funciona enquanto as jogadas não são concorrentes. Quando duas jogadas
acontecem ao mesmo tempo em servidores diferentes, cada cópia decide de um jeito, e o
FIFO não resolve. Falta garantir que **todos os servidores apliquem as jogadas na
mesma ordem**: é o tema do checkpoint 3.

## Referências

- A. S. Tanenbaum e M. van Steen, *Distributed Systems*, cap. 7 (Consistência e
  replicação).
- A. S. Tanenbaum e H. Bos, *Sistemas Operacionais Modernos*, cap. 2 (condições de
  corrida, exclusão mútua, leitores e escritores).
- Documento técnico: `docs/parte-2-aplicacao.md`.
