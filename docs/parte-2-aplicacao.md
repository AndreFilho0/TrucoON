# Parte 2 — Aplicação: mesas de truco replicadas

## A aplicação

**TrucoON** é um truco mineiro online para partidas privadas, 1 contra 1 ou 2 contra 2.
Uma pessoa cria a mesa, compartilha o **link** ou o **QR code** com os amigos, cada um
escolhe uma cadeira e o anfitrião começa a partida. É mobile-first e roda no navegador.

As regras vêm do truco do projeto melivra (baralho de 27 cartas, manilhas fixas,
truco/seis/nove/doze, mão de 11, mão de ferro, partida até 12 tentos), reescritas como
**funções puras**.

## Significado das mensagens e dos processos

- **Processos (peers)**: cada peer é um servidor que guarda uma **réplica completa da
  base de mesas**. Jogadores se conectam ao peer mais próximo (sua "região") por
  WebSocket. Amigos em regiões diferentes jogam na mesma mesa por peers diferentes.
- **Mensagens**: cada mensagem multicast é um **comando** sobre a base replicada:

```
{:create, código, jogador, modo, semente}   criar mesa
{:join,   código, jogador}                  entrar no lobby
{:seat,   código, jogador, cadeira}         sentar
{:start,  código, jogador}                  começar (só o anfitrião)
{:act,    código, jogador, ação}            jogar carta, pedir truco, aceitar, fugir...
{:leave,  código, jogador}                  sair / desistir
{:rematch, código, jogador}                 revanche
```

![Arquitetura do TrucoON](diagramas/2-arquitetura.png)

## Por que a ordem é crítica

Toda réplica aplica os comandos com `Rooms.apply/2`, que é **determinística**: mesmo
estado + mesmo comando ⇒ mesmo resultado (inclusive os erros). Por isso o estado das
réplicas só depende da **ordem** dos comandos (replicação por máquina de estados). Com
ordens diferentes, as réplicas divergem. Exemplos:

1. **Disputa de cadeira**: Bia (peer 1) e Caio (peer 3) pedem a cadeira 0 ao mesmo
   tempo. A réplica que aplica Bia primeiro dá a cadeira a Bia e rejeita Caio; a que
   aplica Caio primeiro faz o contrário. Agora Bia está no time A num peer e no time B
   no outro.
2. **Truco × carta**: Ana joga a carta que fecha a mão enquanto Duda pede truco. Numa
   réplica o truco entra primeiro: a mão passa a valer 3 e a carta de Ana é rejeitada
   (truco pendente). Na outra, a carta fecha a mão valendo 1 e o truco cai na mão
   seguinte. O placar diverge.
3. **Resposta ao truco no 2v2**: os dois parceiros respondem ao mesmo tempo, um
   "aceito" e outro "fujo". Cada réplica aplica primeiro uma resposta diferente.

![Disputa de cadeira sem ordem total](diagramas/2-divergencia.png)

Medição sem coordenação (`S.seat_race(rooms: 8)`, 4 peers): **8 de 8 mesas
divergentes**, tanto em `none` quanto em `fifo`. O teste
`test/truco_on/integration/divergence_test.exs` comprova isso automaticamente.

## Arquitetura de um peer

```
navegador ─WebSocket─► RoomChannel ── submit(cmd) ──┐
                         ▲                          ▼
                PubSub local (só este nó)   Multicast (UDP, camadas)
                         │                          │ entrega na ordem da política
                     Replica ◄──────────────────────┘
                     ├── Rooms.apply/2   (puro, determinístico)
                     └── ETS             (leitura concorrente das visões)
```

![Caminho de uma jogada](diagramas/2-fluxo-comando.png)

![Árvore de supervisão de um peer](diagramas/2-supervisao.png)

Ponto central: o peer **não aplica** o comando do próprio jogador na hora. Ele envia
o comando ao grupo e **espera a entrega pelo multicast**, como todas as outras
réplicas, e só então responde ao jogador. Assim toda alteração passa pela mesma ordem
em todas as réplicas.

### Determinismo

- **Embaralhamento**: `Deck.shuffle/2` usa um PRNG com estado explícito
  (`:rand.seed_s/2`) derivado da semente que viaja no comando `:create`. Todas as
  réplicas distribuem as mesmas cartas.
- **Sem timers nem relógio**: o `GameServer` do melivra tinha timers de abandono e
  *rate limit* baseados no relógio local. Em réplicas isso divergiria (cada uma veria
  o timeout num momento diferente). Aqui tudo que muda estado é comando.
- **Código da mesa**: sorteado pelo peer de origem e enviado no comando. Se colidir,
  todas as réplicas rejeitam igual (`:code_taken`) e o peer tenta outro código.

### Estado em memória, ETS, com e sem estado

| Camada | Tipo | Estado |
|---|---|---|
| REST (`/api/session`, `/api/rooms`) | sem estado | identidade vem num token assinado; dados vêm da réplica local |
| WebSocket (`RoomChannel`) | com estado de sessão | um processo por jogador conectado |
| `Replica` (GenServer) | com estado | **único escritor** da base de mesas |
| ETS `truco_rooms_<inst>` | cache local | leitura concorrente das mesas pelos canais, sem passar pela fila do GenServer |

### Identidade e convite

- **Convidado sem conta**: apelido + token `Phoenix.Token` (HMAC). Todos os peers
  compartilham o segredo, então o token vale em qualquer região.
- **Código de convite**: 8 caracteres de um alfabeto de 31 símbolos sem ambiguidade
  (sem 0/O, 1/I/L), ~39 bits. Vai no link `/m/K7QX-29FA` e no QR code.

### Verificação

Cada réplica expõe `digest/1`: número de comandos aplicados, um **hash encadeado** da
sequência de comandos (muda se a ordem mudar) e um hash por mesa. O Verifier
(`V.replicas()`) e o painel **⚙ Réplicas** da interface comparam esses hashes entre os
peers ao vivo.

## Melhorias no código-base do MPComm

| MPComm | TrucoON |
|---|---|
| IPs fixos em `constMP.py` | tudo por variáveis de ambiente (`config/runtime.exs`) |
| IP público via `api.ipify.org` (dependência externa) | `PEER_HOST` configurável |
| `unregister` não implementado (`# to do`) | implementado; peer se desregistra ao sair |
| Registro duplicado se o peer reinicia | registro idempotente por (IP, porta) |
| `recv(2048)` pode truncar mensagens | enquadramento com prefixo de tamanho (`packet: 4`) |
| Pedido desconhecido deixa o cliente esperando | resposta de erro |
| `while handShakeCount < N: pass` (espera ativa, 100% de CPU) | timers (`Process.send_after`) |
| `pickle.loads` em dados da rede (execução remota de código) | `binary_to_term(bin, [:safe])` |
| Comparação ignora o último peer e parte das posições | compara tudo + perdas, duplicatas, FIFO |
| Porta UDP fixa por máquina | porta por peer: vários peers por máquina |
| Processos soltos, sem recuperação | supervisores OTP (`rest_for_one` no peer) |
| Envio e recepção misturados com a lógica | camadas separadas: UDP, canal confiável, ordenação (pura), aplicação |
| Sem testes | testes automatizados, incluindo peers reais com perda |

## Como demonstrar

```bash
scripts/build_web.sh
ORDERING=fifo DELAY_MAX=60 scripts/up.sh 3
```

1. Abra `http://localhost:4001`, crie uma mesa 2x2 e abra o painel ⚙ Réplicas.
2. Abra o link de convite em outras abas anônimas, trocando a porta (`:4002`, `:4003`)
   para que cada jogador fique num peer diferente.
3. Todos tocam em "Sentar" ao mesmo tempo, ou rode `scripts/run.sh 'S.seat_race(rooms: 8)'`.
4. O painel mostra os hashes **diferentes**: as réplicas divergiram.

Roteiro sugerido para o vídeo: criar mesa → QR code → amigos entrando por peers
diferentes → partida → disputa de cadeiras em `fifo` mostrando a divergência (prepara
a Parte 3).
