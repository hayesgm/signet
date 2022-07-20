defmodule Signet.Filter do
  use GenServer

  require Logger

  alias Signet.RPC

  @check_delay 3000

  defmodule Log do
    defstruct [
      :address,
      :block_hash,
      :block_number,
      :data,
      :log_index,
      :removed,
      :topics,
      :transaction_hash,
      :transaction_index
    ]

    def deserialize(
          %{
            "address" => address,
            "blockHash" => block_hash,
            "blockNumber" => block_number,
            "data" => data,
            "logIndex" => log_index,
            "removed" => removed,
            "topics" => topics,
            "transactionHash" => transaction_hash,
            "transactionIndex" => transaction_index
          }
        ) do
      %__MODULE__{
        address: Signet.Util.decode_hex!(address),
        block_hash: Signet.Util.decode_hex!(block_hash),
        block_number: Signet.Util.decode_hex!(block_number) |> :binary.decode_unsigned(),
        data: Signet.Util.decode_hex!(data),
        log_index: Signet.Util.decode_hex!(log_index) |> :binary.decode_unsigned(),
        removed: removed,
        topics: Enum.map(topics, &Signet.Util.decode_hex!/1),
        transaction_hash: Signet.Util.decode_hex!(transaction_hash),
        transaction_index: Signet.Util.decode_hex!(transaction_index) |> :binary.decode_unsigned()
      }
    end
  end

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
      {:ok, raw_logs} ->
        {logs, events} =
          raw_logs
          |> Enum.map(&Log.deserialize/1)
          |> parse_events(decoders)

        for listener <- listeners, {event, log} <- events do
          send(listener, {:event, event, log})
        end

        for listener <- listeners, log <- logs do
          send(listener, {:log, log})
        end

      {:error, error} ->
        Logger.error("[Filter #{name}] Error getting filter changes: #{error}")
    end

    {:noreply, state}
  end

  defp parse_events(logs, decoders) do
    events = do_parse_events(logs, decoders, [])
    {logs, Enum.reverse(events)}
  end

  defp do_parse_events([], _, events), do: events

  defp do_parse_events([log | logs], decoders, events) do
    [topic_0 | topic_rest] = log.topics

    case decoders[topic_0] do
      nil ->
        do_parse_events(logs, decoders, events)

      decoder_fn ->
        event = decoder_fn.(topic_rest, log.data)
        do_parse_events(logs, decoders, [{event, log} | events])
    end
  end
end
