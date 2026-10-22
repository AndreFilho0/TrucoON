# TrucoON — truco online sobre multicast replicado

Trabalho final de **Sistemas Distribuídos (INF0344 — UFG, 2026/2)**, construído a
partir do [MPComm](https://github.com/professorfabio/MPComm) do Prof. Fábio M. Costa,
reescrito em **Elixir/Erlang** (com a autorização do professor).

O MPComm mostra que, sem coordenação, processos que trocam mensagens por
multicast recebem essas mensagens em **ordens diferentes**. O TrucoON dá um
significado a essas mensagens: cada peer guarda uma **réplica das mesas de truco**,
e cada mensagem é uma **jogada**. Se as réplicas aplicam as jogadas em ordens
diferentes, o estado diverge: duas réplicas podem dar a mesma cadeira a jogadores
diferentes, ou uma aceitar um truco que a outra rejeitou.

| Parte | O que pede o enunciado | Onde está | Documento |
|---|---|---|---|
| 1a | Trocar sockets por RPC no cliente-servidor e comparar | `lib/truco_on/control/` | [docs/parte-1a-rpc.md](docs/parte-1a-rpc.md) |
| 1b | Perda de mensagens + ordem FIFO no multicast, com sockets | `lib/truco_on/multicast/reliable.ex`, `peer/multicast.ex` | [docs/parte-1b-perda-fifo.md](docs/parte-1b-perda-fifo.md) |
| 2 | Aplicação em que a ordem é crítica + melhorias no código-base | `lib/truco_on/truco/`, `peer/replica.ex`, `app/` | [docs/parte-2-aplicacao.md](docs/parte-2-aplicacao.md) |
| 3 | Coordenação por ordem total (cap. 5) | `multicast/ordering/lamport.ex` | [docs/parte-3-ordem-total.md](docs/parte-3-ordem-total.md) |
| 4 | Coordenação mais leve (cap. 7) | `multicast/ordering/sequencer.ex` | [docs/parte-4-sequenciador.md](docs/parte-4-sequenciador.md) |

## Resultado em uma tabela

4 peers, 10% de perda e 0–60 ms de atraso por datagrama, 30 mensagens por peer
(`scripts/measure.sh 4 30` com `LOSS=0.1 DELAY_MAX=60`):

| `ORDERING` | Mensagens perdidas | Violações FIFO | Posições fora de ordem | Mesas divergentes (disputa de cadeiras) | Msgs de protocolo / multicast |
|---|---|---|---|---|---|
| `none` (MPComm original) | 50 | 28 | 110 de 110 | 8 de 8 | 4 |
| `fifo` (Parte 1b) | 0 | 0 | 116 de 120 | 8 de 8 | 4 |
| `total` (Parte 3, Lamport) | 0 | 0 | **0** de 120 | **0** de 8 | 20 (= N + N²) |
| `sequencer` (Parte 4) | 0 | 0 | **0** de 120 | **0** de 8 | 4,75 (≤ N + 1) |

## Arquitetura

![Arquitetura do TrucoON](docs/diagramas/2-arquitetura.png)

Todos os diagramas (fonte Mermaid, SVG e PNG para slides) estão em
[docs/arquitetura.md](docs/arquitetura.md).

```
   navegador (Expo Web, mobile-first)          navegador
        │ REST + WebSocket                          │
        ▼                                           ▼
 ┌─────────────── peer 1 ───────────────┐   ┌──── peer 2 ────┐   ┌── peer 3 ──┐
 │ Phoenix (REST sem estado + Channels) │   │      ...       │   │    ...     │
 │ Replica  ── base de mesas + ETS      │   │                │   │            │
 │ Ordenação  none│fifo│total│sequencer │   │                │   │            │
 │ Canal confiável FIFO (seq/ACK/retx)  │   │                │   │            │
 │ UDP (:gen_udp) + injeção de falhas   │◄─►│   UDP          │◄─►│   UDP      │
 └──────────────┬───────────────────────┘   └───────┬────────┘   └─────┬──────┘
                │ socket TCP  ou  RPC (:erpc)        │                  │
                ▼                                    ▼                  ▼
          ┌────────────── nó de controle ──────────────┐
          │ GroupManager — registro e descoberta       │
          │ Verifier — dispara experimentos e compara  │
          └────────────────────────────────────────────┘
```

- **Peers** (`ROLE=peer`) trocam mensagens entre si **só por UDP**. Cada um tem uma
  réplica completa de todas as mesas e um servidor web para os jogadores ligados a ele.
- **Nó de controle** (`ROLE=control`) faz o papel dos servidores do MPComm
  (`GroupMngr.py` e `comparisonServer.py`). Fala com os peers por socket TCP ou por
  RPC, conforme `CONTROL`.
- **Frontend** (`app/`): Expo + React Native Web + NativeWind + Zustand, a base do
  `melivra_mobile`. Cria a mesa, gera o link e o QR code de convite, mostra o lobby,
  a mesa de jogo e um painel com o hash da mesa em cada réplica.

## Instalação

### O que é preciso

| Ferramenta | Versão testada | Para quê |
|---|---|---|
| **Erlang/OTP** | 27.1.1 | runtime dos nós: processos, sockets UDP/TCP e distribuição (`:erpc`) |
| **Elixir** | 1.17.1 (compilado para OTP 27) | backend: protocolos, réplicas, Phoenix |
| **Node.js + npm** | 22.5.1 | só para gerar o frontend (`scripts/build_web.sh`) |

Não é preciso banco de dados nem Docker: o estado fica em memória, replicado entre os
peers. As dependências de cada linguagem (Phoenix 1.7.24 e Bandit no backend; Expo 54,
React Native Web, NativeWind e Zustand no frontend) são baixadas pelo `mix` e pelo
`npm`, com as versões fixadas em `mix.lock` e `app/package-lock.json`.

Desenvolvido e testado em **macOS 26 (Apple Silicon)** com **asdf 0.19**. Os scripts
são em bash, então em Linux funcionam igual; no Windows, use o WSL.

### Instalando com asdf (recomendado)

O [asdf](https://asdf-vm.com) instala exatamente as versões do arquivo
`.tool-versions` da raiz do projeto:

```
elixir 1.17.1-otp-27
erlang 27.1.1
nodejs 22.5.1
```

**1. Instale o asdf**

```bash
# macOS
brew install asdf

# Linux: baixe o binário em https://github.com/asdf-vm/asdf/releases
# e coloque-o no PATH (ex.: ~/.local/bin/asdf)
```

Adicione os *shims* do asdf ao PATH, no `~/.zshrc` ou `~/.bashrc`, e abra um terminal novo:

```bash
export PATH="${ASDF_DATA_DIR:-$HOME/.asdf}/shims:$PATH"
```

**2. Instale as dependências para compilar o Erlang**

O asdf compila o Erlang a partir do código-fonte (leva de 5 a 15 minutos).

```bash
# macOS
brew install autoconf openssl@3
export KERL_CONFIGURE_OPTIONS="--without-javac --without-wx --without-odbc --with-ssl=$(brew --prefix openssl@3)"

# Ubuntu / Debian
sudo apt install build-essential autoconf m4 libncurses-dev libssl-dev
export KERL_CONFIGURE_OPTIONS="--without-javac --without-wx --without-odbc"
```

(`--without-wx` pula a interface gráfica do Erlang, que o projeto não usa.)

**3. Instale Erlang, Elixir e Node**

Na pasta do projeto:

```bash
asdf plugin add erlang
asdf plugin add elixir
asdf plugin add nodejs
asdf install            # lê o .tool-versions; o Erlang vem antes do Elixir
```

**4. Confira**

```bash
erl -noshell -eval 'io:format("~s~n", [erlang:system_info(otp_release)]), halt().'   # 27
elixir --version        # Elixir 1.17.1 (compiled with Erlang/OTP 27)
node --version          # v22.5.1
```

Agora siga para [Preparando o projeto](#preparando-o-projeto-primeira-vez).

### Sem asdf

Também funciona com `brew install elixir node` (macOS) ou `sudo apt install elixir
erlang nodejs npm` (Linux), mas essas versões costumam ser diferentes das testadas.
O projeto aceita Elixir 1.14 ou mais novo (`mix.exs`); se algo falhar, use o asdf com
as versões acima.

### Preparando o projeto (primeira vez)

Vale para qualquer forma de instalação (com ou sem asdf). Depois de clonar o
repositório, na pasta do projeto:

```bash
# 1. Backend: ferramentas do Elixir e dependências (Phoenix, Bandit, ...)
mix local.hex --force
mix local.rebar --force
mix deps.get

# 2. Frontend: dependências do app/ (npm) e export para priv/static
cd app && npm install && cd ..
scripts/build_web.sh
```

> **Não pule estes passos.** As pastas `deps/`, `app/node_modules/` e `priv/static/`
> não vão para o git, então um clone novo não tem nenhuma delas:
>
> - sem o `mix deps.get`, o `scripts/up.sh` falha ao compilar;
> - sem o `scripts/build_web.sh`, os peers sobem, mas `http://localhost:4001` mostra só
>   *"TrucoON peer no ar. Frontend não exportado (rode scripts/build_web.sh)."*

Repita o `mix deps.get` quando o `mix.lock` mudar, o `npm install` quando o
`app/package-lock.json` mudar, e o `scripts/build_web.sh` sempre que mudar algo em `app/`.

## Como rodar

Com tudo instalado e o projeto preparado (seção anterior):

```bash
ORDERING=total scripts/up.sh 3        # controle + 3 peers em segundo plano
# abra http://localhost:4001, :4002 ou :4003 (um servidor de jogo em cada)

scripts/console.sh                    # IEx no nó de controle
scripts/down.sh                       # para tudo
```

Os peers levam uns 10 segundos para se registrar e formar o grupo; na tela inicial a
bolinha fica verde quando o grupo está pronto. Se algo não subir, veja os logs em
`tmp/run/*.log`.

### Jogando pelo celular (mesma rede Wi-Fi)

```bash
ipconfig getifaddr en0                               # IP do computador (Linux: hostname -I)
PEER_HOST=192.168.0.10 ORDERING=total scripts/up.sh 3
```

Abra `http://192.168.0.10:4001` no computador **pelo IP**, não por `localhost`, para
que o link e o QR code do convite funcionem no celular. Use o mesmo `PEER_HOST` no
`scripts/run.sh` e no `scripts/console.sh`. No macOS, permita conexões de entrada para
o `beam.smp` se o firewall perguntar.

Variáveis do `scripts/up.sh`:

| Variável | Valores | Efeito |
|---|---|---|
| `ORDERING` | `none`, `fifo`, `total`, `sequencer` | política de ordenação do multicast |
| `CONTROL` | `rpc`, `socket` | transporte das interações cliente-servidor |
| `LOSS` | `0.0`–`1.0` | probabilidade de descartar cada datagrama UDP |
| `DELAY_MIN`, `DELAY_MAX` | ms | atraso aleatório por datagrama (gera reordenação) |
| `REMOTE_DELAY` | ms | só o último peer fica "em outra região" com esse atraso |

No console do nó de controle (`scripts/console.sh`), ou de fora com `scripts/run.sh '<expressão>'`:

```elixir
V.bench(50)                          # experimento do MPComm: compara a ordem de entrega
V.replicas()                         # compara as réplicas das mesas de truco
V.message_cost()                     # mensagens por multicast
V.transport_benchmark(300)           # socket TCP × RPC (Parte 1a)
V.faults(0.1, 0, 80)                 # muda perda/atraso em todos os peers em tempo real
S.seat_race(rooms: 10)               # cenário: 4 jogadores disputando cadeiras
S.games(rooms: 3, duration_ms: 20_000) # cenário: partidas inteiras com bots
```

Para rodar em várias máquinas (como o MPComm sugere: peers em regiões diferentes da
nuvem), suba em cada VM com `PEER_HOST=<IP público>`, `CONTROL_HOST`/`CONTROL_NODE`
apontando para a VM de controle e libere as portas UDP (6789+), TCP (5678–5680, 5690+)
e, no modo RPC, a 4369 (epmd) e as portas da distribuição Erlang.

### Frontend em modo desenvolvimento

```bash
cd app && npm install && npm run web   # Expo em http://localhost:8081, usa o peer :4001
EXPO_PUBLIC_SERVER=http://192.168.0.10:4001 npm run web   # outro peer / celular na rede
```

## Testes

```bash
mix test        # 56 testes, ~35 s
```

- **Unitários**: regras do truco (portadas do melivra), sala/lobby, canal confiável
  e políticas de ordenação. Os testes de protocolo usam uma rede simulada em memória
  que perde, duplica e reordena mensagens.
- **Integração** (`test/truco_on/integration/`): GroupManager, Verifier e 3–4 peers
  reais na mesma VM, trocando datagramas UDP com 15% de perda. Verificam cada parte:
  controle por socket e por RPC, ausência de perda e violação FIFO, ordem idêntica com
  Lamport e sequenciador, o custo exato de mensagens (20 por multicast com N = 4 no
  Lamport), réplicas iguais com ordem total e **divergentes** sem ela.

## Estrutura

```
lib/truco_on/
  control/          client.ex (socket × RPC), socket_server.ex, group_manager.ex,
                    verifier.ex, compare.ex, scenario.ex
  multicast/        reliable.ex (Parte 1b), ordering.ex (none/fifo),
                    ordering/lamport.ex (Parte 3), ordering/sequencer.ex (Parte 4)
  peer/             multicast.ex (UDP + camadas), replica.ex, membership.ex,
                    experiment.ex, control.ex, bot.ex
  truco/            deck, evaluator, rules (portados do melivra), game.ex (pura),
                    rooms.ex (base replicada), code.ex (código de convite)
lib/truco_on_web/   REST, WebSocket (RoomChannel), CORS, identidade de convidado
app/                frontend Expo (base do melivra_mobile)
scripts/            up, down, console, run, measure, build_web
test/               unitários + integração com peers reais
```
