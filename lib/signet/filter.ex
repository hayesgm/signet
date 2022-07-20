defmodule Signet.Filter do
  use GenServer

  require Logger

  alias Signet.RPC

  def start_link([name, endpoint, address, topics]) do
    decoders = %{
      Signet.Util.decode_hex!(
        "0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef"
      ) => fn [from_hex, to_hex], amount ->
        <<0::96, from::binary()>> = Signet.Util.decode_hex!(from_hex)
        <<0::96, to::binary()>> = Signet.Util.decode_hex!(to_hex)

        {"Transfer",
         %{
           from: from,
           to: to,
           amount: :binary.decode_unsigned(Signet.Util.decode_hex!(amount))
         }}
      end
    }

    GenServer.start_link(
      __MODULE__,
      %{
        endpoint: endpoint,
        address: address,
        topics: topics,
        name: name,
        listeners: [],
        decoders: decoders
      },
      name: name
    )
  end

  def init(state = %{endpoint: endpoint, address: address, topics: topics}) do
    {:ok, filter_id} =
      RPC.send_rpc(endpoint, "eth_newFilter", [
        %{
          "address" => Signet.Util.encode_hex(address),
          "topics" => Enum.map(topics, &Signet.Util.encode_hex/1)
        }
      ])

    Process.send_after(self(), :check_filter, 5000)

    {:ok, Map.put(state, :filter_id, filter_id)}
  end

  def listen(filter) do
    GenServer.cast(filter, {:listen, self()})
  end

  def handle_cast({:listen, pid}, state = %{listeners: listeners}) do
    {:noreply, Map.put(state, :listeners, [pid | listeners])}
  end

  def handle_info(
        :check_filter,
        state = %{
          endpoint: endpoint,
          filter_id: filter_id,
          listeners: listeners,
          decoders: decoders,
          name: name
        }
      ) do
    Process.send_after(self(), :check_filter, 3000)

    case RPC.send_rpc(endpoint, "eth_getFilterChanges", [filter_id]) do
      {:ok, logs} ->
        events = Enum.flat_map(logs, fn log -> decode_log(log, decoders) end)

        for listener <- listeners, event <- events do
          send(listener, {:event, event})
        end

        for listener <- listeners, log <- logs do
          send(listener, {:log, log})
        end

      {:error, error} ->
        Logger.error("[Filter #{name}] Error getting filter changes: #{error}")
    end

    {:noreply, state}
  end

  defp decode_log(log, decoders) do
    [topic_0 | topic_rest] = log["topics"]

    case decoders[Signet.Util.decode_hex!(topic_0)] do
      nil ->
        []

      decoder_fn ->
        [decoder_fn.(topic_rest, log["data"])]
    end
  end
end
