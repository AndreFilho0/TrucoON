# Parte 1b — Tratamento de perda e ordem FIFO no multicast (com sockets UDP)

## Problema

O `peerCommunicatorUDP.py` envia cada mensagem com `sendto` para cada peer e entrega
o que chegar, na ordem em que chegar. Com UDP:

- datagramas podem **se perder**;
- podem chegar **fora de ordem** (rotas e atrasos diferentes);
- podem chegar **duplicados**.

O próprio README do MPComm diz que "a versão atual não usa um protocolo confiável".

## Solução: um canal confiável e FIFO por par de processos

`lib/truco_on/multicast/reliable.ex` é uma estrutura de dados pura, sem rede,
testável isoladamente. Para cada par (remetente → destinatário):

**No remetente**
- cada mensagem para aquele destino recebe um número de sequência `seq` (1, 2, 3, …);
- a mensagem fica guardada em `unacked` até chegar o ACK;
- a cada 25 ms, o que estiver há mais de 150 ms sem ACK é **retransmitido** (RTO).

**No destinatário**
- guarda `expected`, o próximo número esperado daquele remetente;
- mensagem com `seq < expected` ou já no buffer é **duplicada**: é descartada, mas o
  ACK é reenviado (o ACK anterior pode ter se perdido);
- mensagem adiantada vai para a **fila de espera** (*hold-back queue*);
- quando chega `expected`, entrega essa e todas as seguintes que estiverem contíguas
  no buffer. Isso é a **ordem FIFO por remetente**;
- responde com **ACK cumulativo** `expected - 1` ("recebi tudo até aqui"), então um
  ACK perdido é coberto pelo próximo.

```
remetente                                       destinatário (expected = 1)
  d(1) ───────────────────────────────X  perdido
  d(2) ──────────────────────────────►  buffer {2}           ack(0) ◄──
  d(3) ──────────────────────────────►  buffer {2,3}         ack(0) ◄──
  ... 150 ms sem ack de 1 ...
  d(1) (retransmissão) ──────────────►  entrega 1,2,3        ack(3) ◄──
```

![Perda, fila de espera, retransmissão e ACK cumulativo](diagramas/1b-perda-retransmissao.png)

![Camadas do multicast dentro de um peer](diagramas/1b-camadas-peer.png)

### Formato dos datagramas (`peer/multicast.ex`)

```
{:d, origem, seq, mensagem}   dado do canal confiável
{:a, origem, cum}             ACK cumulativo
{:r, origem, mensagem}        UDP cru (modo ORDERING=none, sem tratamento)
```

Os datagramas continuam sendo enviados com `:gen_udp.send/3`: **sockets UDP**, como
pede o enunciado.

### Injeção de falhas

Para reproduzir o comportamento entre regiões numa máquina só, cada datagrama pode
ser descartado com probabilidade `LOSS` e atrasado entre `DELAY_MIN` e `DELAY_MAX` ms
(`transmit/3` em `peer/multicast.ex`). Atrasos aleatórios por datagrama geram
**reordenação**, como na Internet. Dá para mudar em tempo real com `V.faults/3`.

## O que FIFO garante e o que não garante

FIFO garante que as mensagens **de um mesmo remetente** chegam na ordem em que ele
enviou. Mensagens de remetentes **diferentes** ainda podem chegar em ordens diferentes
em cada peer. A medição deixa isso visível:

| `ORDERING` | Perdidas | Duplicadas | Violações FIFO | Posições fora de ordem |
|---|---|---|---|---|
| `none` | 50 | 0 | 28 | 110 de 110 |
| `fifo` | **0** | **0** | **0** | 116 de 120 |

(4 peers × 30 mensagens, 10% de perda, 0–60 ms de atraso.)

Com `fifo`, cada peer recebe as 120 mensagens, sem repetição e com as de cada
remetente em ordem, mas a sequência global continua diferente entre os peers. Isso
motiva as Partes 3 e 4.

Custo: 108 retransmissões e ~9,3 datagramas UDP por multicast (4 dados + 4 ACKs +
retransmissões), contra 4 no modo cru.

## Métricas do Verifier (melhorias no `comparisonServer.py`)

O original compara só as posições `0..N_MSGS-2` e só os peers `0..N-2`: o laço
`range(1, N-1)` deixa o último peer de fora. `TrucoOn.Control.Compare.bench/3` compara
todas as posições e todos os peers, e mede também, por peer:

- mensagens perdidas (esperadas − recebidas);
- duplicatas;
- violações de FIFO (uma mensagem de `p` entregue depois de outra posterior de `p`).

## Como demonstrar

```bash
ORDERING=none LOSS=0.1 DELAY_MAX=60 scripts/up.sh 4
scripts/run.sh 'V.bench(30)'      # perdas e violações de FIFO
scripts/down.sh

ORDERING=fifo LOSS=0.1 DELAY_MAX=60 scripts/up.sh 4
scripts/run.sh 'V.bench(30)'      # zero perdas, zero violações; ainda fora de ordem entre peers
```

Testes:
- `test/truco_on/multicast/protocols_test.exs` — rede simulada com 30% de perda nos
  dois sentidos e reordenação: tudo é entregue, uma vez, em ordem;
- `test/truco_on/integration/group_test.exs`, bloco "Parte 1b" — peers reais com 15%
  de perda.
