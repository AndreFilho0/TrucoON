# Checkpoint 3 (26/11): fazendo todos concordarem com a ordem

**Disciplinas:** Sistemas Operacionais e Sistemas Distribuídos (INF0344), UFG, 2026/2
**Equipe:** ZAP
**Participantes:**
- André de Oliveira Machado Filho (202406913)
- Alan Queiroz Dantas de Oliveira (202109882)
- Stephany Jorge Araújo Resque (202400316)
- Jamilly Vitorya da Silva Barbosa (202103736)

**Código deste checkpoint:** tag `parte-4`

Cada tópico segue a mesma estrutura:

- **Teoria:** o conceito como é visto em aula (SO e SD);
- **Na implementação:** como o conceito aparece no código, com os arquivos;
- **No jogo:** qual papel ele tem no truco online.

---

## 1. Onde paramos

No checkpoint 2, cada servidor tem uma cópia das mesas, e as jogadas concorrentes
chegam em ordens diferentes em cada um: 8 de 8 mesas divergem na disputa de cadeiras.
Precisamos que **todas as cópias apliquem as jogadas na mesma ordem** (ordem total).
Duas soluções: uma distribuída (Lamport) e uma centralizada (sequenciador).

## 2. Tempo em sistemas distribuídos e relógio lógico

**Teoria.** [2, cap. 5], [5]
- SO: numa máquina só existe um relógio, e o kernel ordena os eventos.
- SD: cada máquina tem o seu relógio, e eles se desviam. Não dá para ordenar eventos
  pelo horário.
- Relação "aconteceu antes" (→) e **relógio lógico de Lamport**:
  - antes de enviar: `clock = clock + 1`, e a mensagem leva esse valor;
  - ao receber com carimbo `t`: `clock = max(clock, t) + 1`.
- Se A → B, então `L(A) < L(B)`. Desempatando pelo id do processo, `(ts, id)` define
  uma ordem total igual para todos.

**Na implementação.**
- O relógio é um inteiro no estado do protocolo:
  `lib/truco_on/multicast/ordering/lamport.ex`.
- Nenhum protocolo usa o relógio físico das máquinas; o tempo local só serve para
  medir intervalos (retransmissão, medições).

**No jogo.**
- Cada jogada recebe um carimbo `(ts, servidor)`. É esse carimbo, e não o horário de
  cada servidor, que decide quem sentou primeiro.

## 3. Multicast totalmente ordenado

**Teoria.** [2, cap. 5], [5]
- Premissa: canais confiáveis e FIFO.
1. Enviar `m`: carimba e manda para todos, inclusive para si.
2. Receber `m`: coloca numa fila ordenada por `(ts, origem)` e manda ACK para todos.
3. Entregar a cabeça da fila quando ela tiver ACK de **todos** os N processos.
- **Por que funciona:** suponha que a cabeça `m = (ts, o)` tem ACK de todos e existe
  `m'` com carimbo menor que ainda não chegou. `m'` foi enviada por algum processo `p`,
  que também confirmou `m`:
  - se `p` enviou `m'` **antes** do ACK de `m`, o canal FIFO entrega `m'` antes desse
    ACK, então `m'` já estaria na fila;
  - se `p` enviou `m'` **depois**, o carimbo de `m'` é maior que o do ACK, que é maior
    que `ts`. Contradição.
  
  Logo, nenhuma mensagem menor aparece depois, e todos entregam na mesma ordem.

**Na implementação.**
- Mensagens `{:tm, ts, origem, m}` e ACKs `{:ta, ts, quem, (ts, origem)}`.
- Fila ordenada com `:gb_sets`.
- O ACK pode chegar antes da própria mensagem (canais diferentes), então ACKs de
  mensagens ainda desconhecidas também são guardados.
- A premissa "canal confiável e FIFO" é a camada do checkpoint 1 (`reliable.ex`): uma
  camada apoia a outra.

![Lamport: mensagem e ACKs](../diagramas/3-lamport.png)

**No jogo.**
- Bia e Caio pedindo a mesma cadeira ao mesmo tempo: todos os servidores ordenam os
  dois pedidos igual, dão a cadeira à mesma pessoa e rejeitam a outra.
- O painel ⚙ Réplicas fica verde.

## 4. Custo da ordem total distribuída

**Teoria.** [2, cap. 5]
- Por multicast: N mensagens de dados + N × N ACKs.
- A entrega espera o processo **mais lento**; se um processo cai, ninguém entrega mais
  nada.

**Na implementação.**
- Medido com `V.message_cost()`, N = 4: **20 mensagens** por multicast (4 + 16),
  ~58 datagramas UDP com 10% de perda.

**No jogo.**
- Toda jogada espera a confirmação de todos os servidores. Um servidor lento deixa o
  jogo lento para todos.

## 5. Coordenação centralizada: sequenciador

**Teoria.** [1, cap. 2], [2, cap. 7]
- SO: um coordenador central também resolve concorrência, como um gerenciador de
  locks ou o escalonador decidindo quem roda.
- SD: protocolo baseado em primário (*remote-write*). Um processo decide a ordem e os
  outros seguem. Isso dá **consistência sequencial**.
1. Quem quer enviar manda só para o sequenciador: `{:req, m}` (1 mensagem).
2. O sequenciador atribui o número global `g` e manda `{:ord, g, m}` para todos
   (N mensagens).
3. Cada processo entrega em ordem crescente de `g`, com fila de espera para lacunas.

**Na implementação.**
- `lib/truco_on/multicast/ordering/sequencer.ex`, cerca de 80 linhas, puro.
- O sequenciador é o peer de menor id (`GET /api/info` mostra qual é).
- Como todas as `{:ord, ...}` saem de um único remetente por canal FIFO, todos recebem
  na mesma ordem.

![Sequenciador: N + 1 mensagens](../diagramas/4-sequenciador.png)

**No jogo.**
- Um servidor funciona como o "juiz da mesa": decide a ordem das jogadas, e os outros
  aplicam nessa ordem.

## 6. Lamport × sequenciador

| | Lamport | Sequenciador |
|---|---|---|
| Mensagens por multicast | N + N² | N + 1 |
| N = 4, medido | **20** | **4,75** |
| Datagramas UDP (10% de perda) | ~58 | ~13 |
| Posições fora de ordem | 0 | 0 |
| Mesas divergentes | 0 de 8 | 0 de 8 |
| Quem precisa responder para entregar | todos | só o sequenciador |
| Ponto único de falha | não, mas um processo lento trava todos | **sim** |
| Gargalo | não | sim |

Com 10 servidores: Lamport gasta 110 mensagens por jogada, o sequenciador 11.

![Custo em mensagens por tamanho do grupo](../diagramas/4-custo.png)

## 7. Limitações e extensões

- **Falha do sequenciador:** se ele cai, ninguém ordena. Solução clássica: **eleição**
  (algoritmo do valentão ou em anel) [2, cap. 5] e recuperação do último `g`. Não foi
  implementado.
- **Gargalo:** um sequenciador por mesa, porque mesas diferentes não precisam de ordem
  entre si.
- **Latência assimétrica:** quem está longe do sequenciador paga ida e volta.
- **Servidor que reinicia volta com a cópia vazia:** faltaria transferência de estado.

## 8. Resultado final

4 peers, 10% de perda, 0–60 ms de atraso, 30 mensagens por peer
(`scripts/measure.sh 4 30`):

| `ORDERING` | Perdidas | Violações FIFO | Fora de ordem | Mesas divergentes | Msgs / multicast |
|---|---|---|---|---|---|
| `none` (sem tratamento) | 50 | 28 | 110 de 110 | 8 de 8 | 4 |
| `fifo` (checkpoint 1) | 0 | 0 | 116 de 120 | 8 de 8 | 4 |
| `total` (Lamport) | 0 | 0 | **0** de 120 | **0** de 8 | 20 |
| `sequencer` | 0 | 0 | **0** de 120 | **0** de 8 | 4,75 |

## 9. Demonstração prática

```bash
ORDERING=total LOSS=0.1 DELAY_MAX=60 scripts/up.sh 4
scripts/run.sh 'S.seat_race(rooms: 8)'   # 0 mesas divergentes
scripts/run.sh 'V.message_cost()'        # 20 mensagens por multicast
scripts/down.sh

ORDERING=sequencer LOSS=0.1 DELAY_MAX=60 scripts/up.sh 4
scripts/run.sh 'S.seat_race(rooms: 8)'   # 0 mesas divergentes
scripts/run.sh 'V.message_cost()'        # ~4,75 mensagens por multicast
scripts/down.sh

scripts/measure.sh 4 30                  # tabela com os 4 modos
```

Na interface: repetir a disputa de cadeiras do checkpoint 2 com `ORDERING=total`. O
painel ⚙ Réplicas fica verde.

## 10. Conclusão do trabalho

- Checkpoint 1: processos conversando sem perder mensagens (sockets, RPC, canal
  confiável FIFO).
- Checkpoint 2: com as mensagens virando jogadas, a ordem diferente quebra o jogo.
- Checkpoint 3: ordem total resolve. Lamport resolve sem coordenador, mas com custo
  quadrático; o sequenciador resolve com custo linear, mas cria um ponto único de
  falha.

## Referências

- [1] TANENBAUM, A. S.; BOS, H. *Sistemas Operacionais Modernos*. 4. ed. Pearson, 2016.
- [2] VAN STEEN, M.; TANENBAUM, A. S. *Distributed Systems*. 4. ed. 2023 (distributed-systems.net).
- [5] LAMPORT, L. Time, Clocks, and the Ordering of Events in a Distributed System. *Communications of the ACM*, v. 21, n. 7, p. 558–565, 1978.
