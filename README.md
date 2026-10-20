# TrucoON — truco online sobre multicast replicado

Trabalho final de **Sistemas Distribuídos (INF0344 — UFG, 2026/2)**, construído a
partir do [MPComm](https://github.com/professorfabio/MPComm) do Prof. Fábio M. Costa,
reescrito em **Elixir/Erlang** (com a autorização do professor).

Esta versão (`parte-1b`) completa a **Parte 1**: além do controle por socket ou RPC
(1a), o multicast entre os peers continua em **sockets UDP** mas agora com um **canal
confiável e FIFO** por par de processos (número de sequência, ACK cumulativo,
retransmissão e fila de espera).

| Parte | Enunciado | Estado nesta versão | Documento |
|---|---|---|---|
| 1a | Trocar sockets por RPC no cliente-servidor e comparar | ✅ | [docs/parte-1a-rpc.md](docs/parte-1a-rpc.md) |
| 1b | Perda de mensagens + ordem FIFO no multicast, com sockets | ✅ | [docs/parte-1b-perda-fifo.md](docs/parte-1b-perda-fifo.md) |
| 2 | Aplicação em que a ordem é crítica (truco replicado) | próximas entregas | — |
| 3 | Coordenação por ordem total (Lamport, cap. 5) | próximas entregas | — |
| 4 | Coordenação mais leve (sequenciador, cap. 7) | próximas entregas | — |

## Resultado

4 peers, 10% de perda e 0–60 ms de atraso por datagrama, 30 mensagens por peer:

| `ORDERING` | Mensagens perdidas | Violações FIFO | Posições fora de ordem |
|---|---|---|---|
| `none` (MPComm original) | 50 | 28 | 110 de 110 |
| `fifo` (Parte 1b) | 0 | 0 | 116 de 120 |

FIFO elimina perdas e violações de ordem **por remetente**, mas cada peer ainda vê as
mensagens de remetentes diferentes numa ordem diferente: isso é o que as Partes 3 e 4
resolvem.

## Arquitetura

![Camadas de um peer](docs/diagramas/1b-camadas-peer.png)

Detalhes de implementação, comparação e como demonstrar estão no documento de cada
parte (tabela acima).

## Instalação

### O que é preciso

| Ferramenta | Versão testada | Para quê |
|---|---|---|
| **Erlang/OTP** | 27.1.1 | runtime dos nós: processos, sockets UDP/TCP e distribuição (`:erpc`) |
| **Elixir** | 1.17.1 (compilado para OTP 27) | backend: protocolos, réplicas, Phoenix |
| **Node.js + npm** | 22.5.1 | só a partir da Parte 2 (frontend) |

Não é preciso banco de dados nem Docker: o estado fica em memória, replicado entre os
peers. As dependências do Elixir (Phoenix 1.7.24 e Bandit) são baixadas pelo `mix`, com as
versões fixadas em `mix.lock`.

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

**5. Ferramentas do Elixir e dependências do projeto (só na primeira vez)**

```bash
mix local.hex --force
mix local.rebar --force
mix deps.get
```

### Sem asdf

Também funciona com `brew install elixir node` (macOS) ou `sudo apt install elixir
erlang nodejs npm` (Linux), mas essas versões costumam ser diferentes das testadas.
O projeto aceita Elixir 1.14 ou mais novo (`mix.exs`); se algo falhar, use o asdf com
as versões acima.

## Como rodar

```bash
ORDERING=none LOSS=0.1 DELAY_MAX=60 scripts/up.sh 4   # MPComm original: perde e reordena
scripts/run.sh 'V.bench(30)'
scripts/down.sh

ORDERING=fifo LOSS=0.1 DELAY_MAX=60 scripts/up.sh 4   # canal confiável FIFO
scripts/run.sh 'V.bench(30)'
scripts/down.sh
```

Variáveis: `ORDERING` (`none`, `fifo`), `CONTROL` (`rpc`, `socket`), `LOSS`,
`DELAY_MIN`, `DELAY_MAX`, `REMOTE_DELAY`.

## Testes

```bash
mix test
```
