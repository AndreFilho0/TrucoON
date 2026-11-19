# TrucoON — Plano de entregas

O trabalho foi entregue em 3 checkpoints (05/11, 19/11 e 26/11), com o README como
relatório. O grupo decidiu fechar o projeto com a ordem total por **relógios de
Lamport** (Parte 3); a variante com sequenciador foi retirada do código. Equipe ZAP,
4 integrantes.

## Estado

| Parte | Código | Testes | Documento (README da entrega) |
|---|---|---|---|
| 1a — RPC × sockets | `control/` | `group_test.exs` "Parte 1a" | `docs/parte-1a-rpc.md` |
| 1b — perda + FIFO | `multicast/reliable.ex`, `peer/multicast.ex` | `protocols_test.exs`, `group_test.exs` "Parte 1b" | `docs/parte-1b-perda-fifo.md` |
| 2 — aplicação | `truco/`, `peer/replica.ex`, `truco_on_web/`, `app/` | `game_test`, `rooms_test`, `divergence_test` | `docs/parte-2-aplicacao.md` |
| 3 — ordem total | `multicast/ordering/lamport.ex` | `protocols_test.exs`, `group_test.exs` | `docs/parte-3-ordem-total.md` |

## Como entregar

O enunciado diz "entrega via GitHub" e "cada parte entregue separadamente". A leitura
mais provável: **um único repositório** que vai evoluindo, e em cada tarefa do Turing
o grupo envia o link do ponto do repositório correspondente àquela parte, mais o link
do vídeo.

O histórico tem **um commit por marco**, cada um com **tag**:

| Tag | Conteúdo | Entrega no Turing |
|---|---|---|
| `parte-1a` | MPComm em Elixir + controle por socket e por RPC | — (parte da entrega 1) |
| `parte-1b` | + canal confiável FIFO sobre UDP | **Parte 1** (a + b) |
| `parte-2` | + truco replicado, web e frontend | **Parte 2** |
| `parte-3` | + ordem total com Lamport | **Parte 3** |
| `main` | + painel da ordem total, medições, README final | **Checkpoint 3** (final) |

Link de cada entrega: `https://github.com/AndreFilho0/TrucoON/tree/parte-2`
(o professor vê o código e o README exatamente como estavam naquela parte). Uma
*Release* no GitHub para cada tag é um bom lugar para o link do vídeo.

Cada tag compila e passa nos próprios testes, e o modo da parte anterior continua
disponível por `ORDERING`, o que facilita comparar no vídeo.

Pontos para confirmar com o professor:
- se a Parte 1 é uma entrega só (1a + 1b) ou duas;
- se basta o link da tag ou ele quer o repositório em outro formato;
- o repositório precisa ser público, ou o professor precisa ser adicionado como
  colaborador.

## Roteiros de vídeo (sugestão)

- **1a**: subir com `CONTROL=socket` (peers sem distribuição Erlang) e com
  `CONTROL=rpc`; mostrar o mesmo `handle/2` atendendo os dois; `V.transport_benchmark`;
  discutir a tabela de vantagens e desvantagens.
- **1b**: `ORDERING=none` com `LOSS=0.1` mostrando perdas e violações de FIFO;
  `ORDERING=fifo` zerando as duas; mostrar que a ordem entre peers ainda difere.
- **2**: fluxo do jogo no celular (criar mesa, QR, amigos em peers diferentes,
  partida); disputa de cadeiras com `fifo` e o painel de réplicas vermelho.
- **3**: o mesmo cenário com `total`: painel verde, `V.bench` com 0 fora de ordem,
  custo de 20 mensagens por multicast.
- **3 (final)**: `scripts/measure.sh` com a tabela de `none`, `fifo` e `total`;
  painel com a faixa "Ordem total" verde; decisões do projeto.

## Divisão sugerida no grupo

- **A** — rede e protocolos: canal confiável, Lamport, medições.
- **B** — controle e infraestrutura: socket × RPC, GroupManager, Verifier, scripts,
  implantação em VMs de regiões diferentes.
- **C** — aplicação: regras do truco, réplica, web e frontend.

## Possíveis extensões (se sobrar tempo)

- Detectar a queda de um peer e tirá-lo do grupo (hoje o Lamport para de entregar
  até ele voltar, porque espera o ACK de todos).
- Implantação em duas regiões de nuvem, como no experimento original do MPComm.
- Transferência de estado para um peer que reinicia (hoje a réplica volta vazia).
