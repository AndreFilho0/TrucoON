# Parte 1a — De sockets para RPC nas interações cliente-servidor

## O que muda

No MPComm, três interações são **cliente-servidor** e todas usam socket TCP +
`pickle` montados à mão:

| Interação | Cliente | Servidor | Pedido |
|---|---|---|---|
| Registro do peer | peer | `GroupMngr.py` | `{"op": "register", ...}` |
| Lista de peers | peer, comparisonServer | `GroupMngr.py` | `{"op": "list"}` |
| Sinal de início | comparisonServer | peer | `(peerNumber, nMsgs)` |
| Envio do log | peer | `comparisonServer.py` | lista de mensagens |

No TrucoON essas interações passam por `TrucoOn.Control.Client.request(alvo, pedido)`,
que tem **dois transportes**, escolhidos pela variável `CONTROL`:

- **`socket`** (`client.ex` → `socket_server.ex`): conecta por TCP, envia o pedido
  serializado com `:erlang.term_to_binary/1` (o equivalente do `pickle`) e um prefixo
  de 4 bytes com o tamanho, espera a resposta e fecha a conexão.
- **`rpc`** (`client.ex`): `:erpc.call(nó, Módulo, :handle, [inst, pedido])`. É o RPC
  nativo do Erlang: o chamador escreve uma chamada de função remota e o runtime cuida
  de conexão, serialização, envio, espera e propagação de erros.

No servidor, os dois transportes chegam **na mesma função** `handle/2`
(`GroupManager.handle/2`, `Verifier.handle/2`, `Peer.Control.handle/2`). A comparação
é justa porque só o transporte muda.

```elixir
# mesmo pedido, dois transportes
Client.request(Client.group_manager(), {:register, info}, transport: :socket)
Client.request(Client.group_manager(), {:register, info}, transport: :rpc)
```

## Diagramas

![Visão geral: nó de controle e grupo de peers](diagramas/1a-visao-geral.png)

![O mesmo pedido por socket TCP e por RPC](diagramas/1a-socket-vs-rpc.png)

## Comparação

### Medição

`V.transport_benchmark(300)`: 300 pedidos `:ping` para cada um de 3 peers, na mesma
máquina:

| Transporte | Média | Mediana | p99 |
|---|---|---|---|
| Socket TCP (uma conexão por pedido, como no MPComm) | 143 µs | 133 µs | 203 µs |
| RPC (`:erpc`) | 28 µs | 27 µs | 56 µs |

O RPC sai ~5× mais rápido aqui porque a distribuição Erlang mantém **uma conexão TCP
persistente** entre os nós. O socket abre e fecha uma conexão (handshake de 3 vias)
a cada pedido, como o original. A diferença é de implementação, não do conceito de
RPC: um socket com conexão persistente ficaria parecido, mas aí seria preciso
programar à mão multiplexação, *keepalive* e reconexão.

### Vantagens do RPC

- **Transparência de acesso**: a chamada remota parece uma chamada local
  (`GroupManager.handle(inst, :list)`). Não aparece no código nem conexão, nem
  serialização, nem enquadramento de mensagens.
- **Menos código e menos bugs**: no MPComm, `recv(2048)` pode truncar respostas
  grandes, e um pedido desconhecido deixa o cliente esperando para sempre. Com RPC o
  runtime cuida disso.
- **Erros propagados**: exceção, timeout ou nó fora do ar voltam para o chamador
  como erro (`{:erpc, :noconnection}`, `:timeout`), em vez de um socket pendurado.
- **Conexão persistente e multiplexada** entre nós, o que dá a menor latência medida.

### Desvantagens do RPC

- **Acoplamento de plataforma**: os dois lados precisam ser nós Erlang com o mesmo
  *cookie*. Um cliente em Python ou um navegador não chama `:erpc`. O socket com um
  formato definido funciona com qualquer linguagem.
- **Transparência que engana**: a chamada parece local, mas pode falhar por motivos
  que uma chamada local não tem (rede, nó remoto caído, timeout). O código precisa
  tratar isso igual (ver `Client.rpc/3`).
- **Segurança e implantação**: a distribuição Erlang exige a porta 4369 (epmd) e um
  intervalo de portas abertos. Quem tem o cookie pode executar **qualquer** função no
  nó remoto. O socket expõe só o que `handle/2` aceita.
- **Malha completa**: por padrão um nó conecta em todos os outros que conhece, e
  bibliotecas distribuídas (como o `Phoenix.PubSub`) passam a enviar mensagens entre
  eles sem que o código peça explicitamente. É preciso cuidado para que isso não
  substitua, sem querer, a comunicação que queremos controlar (o multicast UDP).

### Vantagens do socket

- Funciona entre linguagens e sem nenhum runtime em comum.
- Controle total do protocolo (formato, tempo de vida da conexão, o que é aceito).
- Não exige distribuição Erlang. No modo `CONTROL=socket` os peers rodam como nós
  **não distribuídos**.

## Detalhe de segurança: desserialização

`pickle.loads` sobre dados da rede permite **execução arbitrária de código**. No
TrucoON o socket usa `:erlang.binary_to_term(bin, [:safe])`, que recusa termos que
criariam átomos novos ou referências a funções.

Efeito colateral encontrado nos testes: em dev os módulos são carregados sob
demanda, então o átomo `:start_bench` ainda não existia no peer e o pedido era
recusado (`:bad_payload`). A correção foi carregar todos os módulos no boot
(`TrucoOn.Application.start/2`).

## Como demonstrar

```bash
CONTROL=socket scripts/up.sh 3     # peers SEM distribuição Erlang; só TCP
scripts/run.sh 'V.bench(20)'
scripts/down.sh

CONTROL=rpc scripts/up.sh 3        # peers como nós Erlang
scripts/run.sh 'V.bench(20)'
scripts/run.sh 'V.transport_benchmark(300)'
```

Nos logs (`tmp/run/control.log`) dá para ver as portas TCP abertas e os registros.

Testes: `test/truco_on/integration/group_test.exs`, bloco "Parte 1a".
