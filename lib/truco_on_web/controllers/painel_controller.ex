defmodule TrucoOnWeb.PainelController do
  @moduledoc """
  Página do painel (`/painel`) e os comandos de demonstração.

  Os comandos (mudar atraso/perda da rede e disparar a disputa de cadeira)
  alteram o comportamento do peer, então só ficam ligados com
  `PAINEL_CONTROLE=1` (o `scripts/up.sh` liga por padrão, para a demo
  local). Num servidor público, o painel continua só de leitura.
  """

  use TrucoOnWeb, :controller

  alias TrucoOn.Peer.{Multicast, Replica}
  alias TrucoOn.Truco.Code

  @inst :main

  def controls?, do: Application.get_env(:truco_on, :painel_controle, false)

  def index(conn, _params) do
    path = Application.app_dir(:truco_on, "priv/painel/index.html")
    conn |> put_resp_content_type("text/html") |> send_file(200, path)
  end

  @doc "Muda perda e atraso artificiais DESTE peer (o painel chama em todos)."
  def faults(conn, params) do
    with :ok <- allowed() do
      faults =
        %{}
        |> put_num(:loss, params["loss"], &to_float/1)
        |> put_num(:delay_min, params["delay_min"], &to_int/1)
        |> put_num(:delay_max, params["delay_max"], &to_int/1)

      :ok = Multicast.set_faults(@inst, faults)
      json(conn, %{faults: Multicast.info(@inst).faults})
    else
      {:error, status, reason} -> error(conn, status, reason)
    end
  end

  @doc """
  Prepara a disputa: cria uma mesa 2x2 com um anfitrião e faz os
  `racers` jogadores entrarem. Tudo por este peer, um comando depois do
  outro (sem concorrência ainda).
  """
  def race_setup(conn, params) do
    with :ok <- allowed() do
      racers = params |> Map.get("racers", 3) |> to_int() |> min(4) |> max(2)
      code = Code.generate()
      host = %{id: "painel-anfitriao", name: "Anfitrião"}

      with {:ok, _} <- Replica.submit(@inst, {:create, code, host, "2v2", 1}),
           players = for(i <- 1..racers, do: %{id: "painel-P#{i}", name: "P#{i}"}),
           :ok <- join_all(code, players) do
        json(conn, %{code: code, players: players})
      else
        {:error, reason} -> error(conn, 422, reason)
      end
    else
      {:error, status, reason} -> error(conn, status, reason)
    end
  end

  @doc "Um jogador pede uma cadeira por ESTE peer. Responde sem esperar."
  def race_seat(conn, %{"code" => code, "player_id" => pid} = params) do
    with :ok <- allowed() do
      seat = params |> Map.get("seat", 0) |> to_int()
      Task.start(fn -> Replica.submit(@inst, {:seat, code, pid, seat}) end)
      json(conn, %{ok: true})
    else
      {:error, status, reason} -> error(conn, status, reason)
    end
  end

  defp join_all(code, players) do
    Enum.reduce_while(players, :ok, fn p, :ok ->
      case Replica.submit(@inst, {:join, code, p}) do
        {:ok, _} -> {:cont, :ok}
        err -> {:halt, err}
      end
    end)
  end

  defp allowed, do: if(controls?(), do: :ok, else: {:error, 403, :painel_controle_desligado})

  defp put_num(map, _key, nil, _conv), do: map
  defp put_num(map, key, value, conv), do: Map.put(map, key, conv.(value))

  defp to_int(v) when is_integer(v), do: v
  defp to_int(v) when is_float(v), do: round(v)
  defp to_int(v) when is_binary(v), do: v |> Float.parse() |> elem(0) |> round()

  defp to_float(v) when is_number(v), do: v / 1
  defp to_float(v) when is_binary(v), do: v |> Float.parse() |> elem(0)

  defp error(conn, status, reason),
    do: conn |> put_status(status) |> json(%{error: to_string(reason)})
end
