defmodule TrucoOn.Integration.GroupTest do
  @moduledoc """
  Peers reais trocando datagramas UDP, com perda e atraso artificiais.
  Cada teste reproduz um ponto do trabalho.
  """
  use TrucoOn.GroupCase, async: false

  alias TrucoOn.Control.Verifier

  @moduletag timeout: 120_000

  describe "Parte 1a — controle por socket TCP e por RPC" do
    for transport <- [:socket, :rpc] do
      test "grupo forma e experimento roda com CONTROL=#{transport}" do
        start_group(3, ordering: :none, transport: unquote(transport))
        report = Verifier.bench(5, quiet: true)
        assert report.logs_received == 3
        assert Enum.all?(report.per_peer, fn {_id, p} -> p.missing == 0 end)
      end
    end
  end
end
