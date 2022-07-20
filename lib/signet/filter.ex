defmodule Signet.Filter do
  use GenServer

  require Logger

  alias Signet.RPC

  @check_delay 3000

  def start_link([name, address, topics, events]) do
    decoders =
      for event_abi <- events, into: %{} do
        function_selector = ABI.FunctionSelector.decode(event_abi)

        {ABI.Event.event_topic(function_selector),
         fn event_topics, event_data ->
           ABI.Event.decode_event(event_data, event_topics, function_selector)
         end}
      end

    GenServer.start_link(
      __MODULE__,
      %{
        address: address,
        topics: topics,
        name: name,
        listeners: [],
        decoders: decoders
      },
      name: name
    )
  end

  def init(state = %{address: address, topics: topics}) do
    {:ok, filter_id} =
      RPC.send_rpc("eth_newFilter", [
        %{
          "address" => Signet.Util.encode_hex(address),
          "topics" => Enum.map(topics, &Signet.Util.encode_hex/1)
        }
      ])

    Process.send_after(self(), :check_filter, @check_delay)

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
          filter_id: filter_id,
          listeners: listeners,
          decoders: decoders,
          name: name
        }
      ) do
    Process.send_after(self(), :check_filter, @check_delay)

    case RPC.send_rpc("eth_getFilterChanges", [filter_id]) do
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
    [topic_0 | topic_rest_enc] = log["topics"]

    case decoders[Signet.Util.decode_hex!(topic_0)] do
      nil ->
        []

      decoder_fn ->
        topic_rest = Enum.map(topic_rest_enc, &Signet.Util.decode_hex!/1)
        [decoder_fn.(topic_rest, Signet.Util.decode_hex!(log["data"]))]
    end
  end
end
