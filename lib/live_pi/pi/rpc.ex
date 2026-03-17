defmodule LivePi.Pi.RPC do
  @moduledoc """
  Helpers for the pi RPC JSONL protocol.
  """

  def encode!(payload) when is_map(payload) do
    Jason.encode!(payload) <> "\n"
  end

  def decode_chunk(buffer, chunk) when is_binary(buffer) and is_binary(chunk) do
    data = buffer <> chunk
    parts = String.split(data, "\n")

    {rest, complete} = List.pop_at(parts, -1)

    messages =
      complete
      |> Enum.map(&String.trim_trailing(&1, "\r"))
      |> Enum.reject(&(&1 == ""))
      |> Enum.map(&decode_line/1)

    {messages, rest || ""}
  end

  defp decode_line(line) do
    case Jason.decode(line) do
      {:ok, message} -> {:ok, message}
      {:error, error} -> {:error, {:invalid_json, line, error}}
    end
  end
end
