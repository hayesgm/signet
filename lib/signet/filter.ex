defmodule Signet.Filter do
  @moduledoc """
  A system to create an Ethereum log filter and have
  parsed events passed back to registered processes.
  """

  use GenServer
  use Signet.Hex

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

    def deserialize(%{
          "address" => address,
          "blockHash" => block_hash,
          "blockNumber" => block_number,
          "data" => data,
          "logIndex" => log_index,
          "removed" => removed,
          "topics" => topics,
          "transactionHash" => transaction_hash,
          "transactionIndex" => transaction_index
        }) do
      %__MODULE__{
        address: Hex.decode_address!(address),
        block_hash: Hex.decode_word!(block_hash),
        block_number: Hex.decode_hex_number!(block_number),
        data: from_hex!(data),
        log_index: Hex.decode_hex_number!(log_index),
        removed: removed,
        topics: Enum.map(topics, &Hex.decode_word!/1),
        transaction_hash: from_hex!(transaction_hash),
        transaction_index: Hex.decode_hex_number!(transaction_index)
      }
    end
  end

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    address = Keyword.get(opts, :address, nil)
    topics = Keyword.get(opts, :topics, [])
    events = Keyword.get(opts, :events, [])
    rpc_opts = Keyword.get(opts, :rpc_opts, [])
    check_delay = Keyword.get(opts, :check_delay, @check_delay)

    decoders =
      for event <- events, into: %{} do
        function_selector =
          case event do
            %ABI.FunctionSelector{
              types: [%{name: "_topic", type: {:uint, 256}, indexed: true} | rest_types]
            } ->
              %{event | types: rest_types}

            %ABI.FunctionSelector{} ->
              event

            event_abi when is_binary(event_abi) ->
              ABI.FunctionSelector.decode(event_abi)
          end

        {ABI.Event.event_signature(function_selector),
         fn event_topics, event_data ->
           ABI.Event.decode_event(event_data, event_topics, function_selector)
         end}
      end

    all_topics = Enum.map(decoders, fn {topic, _} -> topic end) ++ topics

    GenServer.start_link(
      __MODULE__,
      %{
        address: address,
        topics: all_topics,
        name: name,
        listeners: [],
        decoders: decoders,
        check_delay: check_delay,
        rpc_opts: rpc_opts
      },
      name: name
    )
  end

  defp set_filter(state = %{address: nil, topics: topics, rpc_opts: rpc_opts}) do
    {:ok, filter_id} =
      RPC.send_rpc(
        "eth_newFilter",
        [
          %{
            "topics" => Enum.map(topics, &Signet.Hex.encode_hex/1)
          }
        ],
        rpc_opts
      )

    Map.put(state, :filter_id, filter_id)
  end

  defp set_filter(state = %{address: address, topics: topics, rpc_opts: rpc_opts}) do
    {:ok, filter_id} =
      RPC.send_rpc(
        "eth_newFilter",
        [
          %{
            "address" => Signet.Hex.encode_hex(address),
            "topics" => Enum.map(topics, &Signet.Hex.encode_hex/1)
          }
        ],
        rpc_opts
      )

    Map.put(state, :filter_id, filter_id)
  end

  def init(state = %{check_delay: check_delay}) do
    state = set_filter(state)

    Process.send_after(self(), :check_filter, check_delay)

    {:ok, state}
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
          name: name,
          check_delay: check_delay,
          rpc_opts: rpc_opts
        }
      ) do
    Process.send_after(self(), :check_filter, check_delay)

    state =
      case RPC.send_rpc("eth_getFilterChanges", [filter_id], rpc_opts) do
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

          state

        {:error, "error -32000: filter not found"} ->
          Logger.error(
            "[Filter #{name}] Filter expired, restarting... Note: some logs may have been lost."
          )

          set_filter(state)

        {:error, error} ->
          Logger.error("[Filter #{name}] Error getting filter changes: #{error}")

          state
      end

    {:noreply, state}
  end

  defp parse_events(logs, decoders) do
    events = do_parse_events(logs, decoders, [])
    {logs, Enum.reverse(events)}
  end

  defp do_parse_events([], _, events), do: events

  defp do_parse_events([log | rest_logs], decoders, acc_events) do
    [topic_0 | _topic_rest] = log.topics

    case Map.get(decoders, topic_0) do
      nil ->
        do_parse_events(rest_logs, decoders, acc_events)

      decoder_fn ->
        case decoder_fn.(log.topics, log.data) do
          {:ok, event_name, event_params} ->
            do_parse_events(rest_logs, decoders, [{{event_name, event_params}, log} | acc_events])

          {:error, error} ->
            Logger.error("Error decoding log: #{error}")
            do_parse_events(rest_logs, decoders, acc_events)
        end
    end
  end
end
