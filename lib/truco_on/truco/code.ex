defmodule TrucoOn.Truco.Code do
  @moduledoc """
  Código de convite da mesa (vai no link e no QR code).

  8 caracteres de um alfabeto de 31 símbolos sem caracteres ambíguos
  (sem 0/O, 1/I/L) ⇒ 31^8 ≈ 8,5 × 10^11 combinações (~39 bits): inviável de
  adivinhar por força bruta. Exibido como `K7QX-29FA`.
  """

  @alphabet ~c"ABCDEFGHJKMNPQRSTUVWXYZ23456789"

  def generate do
    for _ <- 1..8, into: "", do: <<Enum.random(@alphabet)>>
  end

  @doc "Aceita `k7qx-29fa`, `K7QX29FA` etc. e devolve a forma canônica `K7QX29FA`."
  def normalize(code) when is_binary(code) do
    code |> String.upcase() |> String.replace(~r/[^A-Z0-9]/, "")
  end

  def normalize(_), do: ""

  def format(<<a::binary-size(4), b::binary-size(4)>>), do: a <> "-" <> b
  def format(code), do: code
end
