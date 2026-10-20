defmodule TrucoOnWeb.ApiController do
  @moduledoc """
  REST **sem estado**: qualquer peer responde, a identidade vem no token e
  os dados vêm da réplica local (ETS).
  """

  use TrucoOnWeb, :controller

  alias TrucoOn.Peer.{Membership, Multicast, Replica}
  alias TrucoOn.Truco.Code
  alias TrucoOnWeb.Auth

  @inst :main

  def session(conn, params) do
    case Auth.new_player(params["name"]) do
      {:ok, player, token} -> json(conn, %{player: player, token: token})
      {:error, reason} -> error(conn, 422, reason)
    end
  end

  def info(conn, _params) do
    %{me: me, view: view} = Membership.info(@inst)
    mc = Multicast.info(@inst)

    json(conn, %{
      peer_id: me && me.id,
      region: me && me.region,
      ordering: mc.mode,
      group_ready: mc.ready,
      peers:
        Enum.map(view || [], fn m ->
          %{id: m.id, region: m.region, url: "http://#{m.host}:#{m.http_port}"}
        end)
    })
  end

  def debug(conn, _params) do
    digest = Replica.digest(@inst)

    json(conn, %{
      multicast: Multicast.info(@inst) |> Map.update!(:faults, & &1),
      stats: Multicast.stats(@inst),
      replica: Map.take(digest, [:applied, :chain, :state_hash]),
      rooms: digest.rooms
    })
  end

  def create_room(conn, params) do
    with {:ok, player} <- Auth.from_conn(conn),
         mode when mode in ["1v1", "2v2"] <- params["mode"] || {:error, :invalid_mode},
         {:ok, code} <- create(player, mode, 3) do
      json(conn, %{code: code, display: Code.format(code)})
    else
      {:error, :missing} -> error(conn, 401, :unauthorized)
      {:error, :invalid} -> error(conn, 401, :unauthorized)
      {:error, :expired} -> error(conn, 401, :unauthorized)
      {:error, reason} -> error(conn, 422, reason)
      _ -> error(conn, 422, :invalid_mode)
    end
  end

  defp create(_player, _mode, 0), do: {:error, :code_taken}

  defp create(player, mode, tries) do
    code = Code.generate()

    case Replica.submit(@inst, {:create, code, player, mode, :rand.uniform(1_000_000_000)}) do
      {:ok, code} -> {:ok, code}
      {:error, :code_taken} -> create(player, mode, tries - 1)
      other -> other
    end
  end

  def show_room(conn, %{"code" => code}) do
    case Replica.preview(@inst, Code.normalize(code)) do
      nil -> error(conn, 404, :room_not_found)
      room -> json(conn, room)
    end
  end

  defp error(conn, status, reason) do
    conn |> put_status(status) |> json(%{error: to_string(reason)})
  end
end
