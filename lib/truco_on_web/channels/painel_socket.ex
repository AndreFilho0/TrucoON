defmodule TrucoOnWeb.PainelSocket do
  @moduledoc """
  WebSocket do **painel** (`/painel`). Só leitura: não precisa de token,
  porque não expõe nada que permita alterar o jogo nem ver cartas.
  """

  use Phoenix.Socket

  channel "painel:trace", TrucoOnWeb.PainelChannel

  @impl true
  def connect(_params, socket, _connect_info), do: {:ok, socket}

  @impl true
  def id(_socket), do: nil
end

defmodule TrucoOnWeb.PainelChannel do
  @moduledoc """
  Repassa ao navegador os eventos de rastreamento deste peer
  (`TrucoOn.Peer.Trace`). O painel abre um canal destes em **cada** peer e
  junta tudo numa visão só.
  """

  use TrucoOnWeb, :channel

  alias TrucoOn.Peer.{Membership, Multicast, Replica, Trace}

  @inst :main

  @impl true
  def join("painel:trace", _params, socket) do
    Phoenix.PubSub.subscribe(TrucoOn.PubSub, Trace.topic(@inst))
    {:ok, hello(), socket}
  end

  @impl true
  def handle_info({:trace, event}, socket) do
    push(socket, "ev", event)
    {:noreply, socket}
  end

  # Estado inicial: quem é este peer, o grupo, as filas e a réplica.
  defp hello do
    %{me: me, view: view} = Membership.info(@inst)
    mc = Multicast.info(@inst)

    %{
      peer_id: me && me.id,
      region: me && me.region,
      mode: mc.mode,
      ready: mc.ready,
      faults: mc.faults,
      controls: TrucoOnWeb.PainelController.controls?(),
      peers:
        Enum.map(view || [], fn m ->
          %{id: m.id, region: m.region, url: "http://#{m.host}:#{m.http_port}"}
        end),
      queues: if(mc.ready, do: Multicast.queues(@inst)),
      replica: Replica.summary(@inst)
    }
  end
end
