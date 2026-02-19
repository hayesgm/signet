defmodule Signet.Solana.RPC do
  @moduledoc """
  JSON-RPC client for Solana.

  Provides typed functions for Solana RPC methods with automatic
  Base58 encoding of pubkeys, commitment level options, and response
  deserialization.

  ## Configuration

      config :signet,
        solana_node: "https://api.mainnet-beta.solana.com"

  ## Examples

      {:ok, balance} = Signet.Solana.RPC.get_balance(pubkey)
      {:ok, slot} = Signet.Solana.RPC.get_slot()
      {:ok, %{blockhash: bh}} = Signet.Solana.RPC.get_latest_blockhash()
  """

  require Logger

  import Signet.Util, only: [normalize_finch_result: 1]

  @default_timeout Application.compile_env(:signet, :solana_timeout, 30_000)

  defp solana_node, do: Application.get_env(:signet, :solana_node)
  defp http_client, do: Application.get_env(:signet, :client, Finch)
  defp finch_name, do: Application.get_env(:signet, :finch_name, SignetFinch)

  # ---------------------------------------------------------------------------
  # Core transport
  # ---------------------------------------------------------------------------

  @doc """
  Send a raw JSON-RPC request to the Solana node.

  Options:
  - `:solana_node` - Override the node URL
  - `:timeout` - Request timeout in ms (default: #{@default_timeout})
  - `:id` - JSON-RPC request ID (default: auto-generated)

  ## Examples

      Signet.Solana.RPC.send_rpc("getSlot", [])
      {:ok, 123456789}
  """
  @spec send_rpc(String.t(), list(), keyword()) :: {:ok, term()} | {:error, term()}
  def send_rpc(method, params, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    url = Keyword.get(opts, :solana_node, solana_node())
    id = Keyword.get_lazy(opts, :id, fn -> System.unique_integer([:positive]) end)

    body = %{
      "jsonrpc" => "2.0",
      "method" => method,
      "params" => params,
      "id" => id
    }

    headers = [
      {"Accept", "application/json"},
      {"Content-Type", "application/json"}
    ]

    request = Finch.build(:post, url, headers, Jason.encode!(body))

    finch_result =
      normalize_finch_result(
        http_client().request(request, finch_name(), receive_timeout: timeout)
      )

    with {:ok, %Finch.Response{body: resp_body}} <- finch_result do
      decode_response(resp_body, id, method)
    end
  end

  defp decode_response(response, id, method) do
    with {:ok, decoded} <- Jason.decode(response) do
      case decoded do
        %{"jsonrpc" => "2.0", "result" => result, "id" => ^id} ->
          {:ok, result}

        %{"jsonrpc" => "2.0", "error" => %{"code" => code, "message" => message}, "id" => ^id} ->
          Logger.warning("[Signet][Solana][#{method}] RPC error: #{code} #{message}")
          {:error, %{code: code, message: message}}

        _ ->
          {:error, %{code: -999, message: "invalid JSON-RPC response"}}
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp encode_pubkey(<<pubkey::binary-32>>), do: Signet.Base58.encode(pubkey)

  defp commitment_config(opts) do
    config = %{}
    config = if c = Keyword.get(opts, :commitment), do: Map.put(config, "commitment", to_string(c)), else: config
    config = if s = Keyword.get(opts, :min_context_slot), do: Map.put(config, "minContextSlot", s), else: config
    config
  end

  defp account_config(opts) do
    config = commitment_config(opts)
    config = if e = Keyword.get(opts, :encoding), do: Map.put(config, "encoding", encoding_string(e)), else: Map.put(config, "encoding", "base64")
    config
  end

  defp encoding_string(:base58), do: "base58"
  defp encoding_string(:base64), do: "base64"
  defp encoding_string(:"base64+zstd"), do: "base64+zstd"
  defp encoding_string(:json_parsed), do: "jsonParsed"
  defp encoding_string(s) when is_binary(s), do: s

  defp unwrap_value(%{"context" => _ctx, "value" => value}), do: value
  defp unwrap_value(other), do: other

  defp params_with_config(params, opts) do
    config = commitment_config(opts)
    if config == %{}, do: params, else: params ++ [config]
  end

  # ---------------------------------------------------------------------------
  # Account methods
  # ---------------------------------------------------------------------------

  @doc """
  Get the SOL balance (in lamports) for an account.

  ## Options
  - `:commitment` - `:processed`, `:confirmed`, or `:finalized`
  """
  @spec get_balance(<<_::256>>, keyword()) :: {:ok, non_neg_integer()} | {:error, term()}
  def get_balance(pubkey, opts \\ []) do
    with {:ok, result} <- send_rpc("getBalance", params_with_config([encode_pubkey(pubkey)], opts), opts) do
      {:ok, unwrap_value(result)}
    end
  end

  @doc """
  Get account info for a pubkey. Returns `nil` if the account doesn't exist.

  ## Options
  - `:commitment` - `:processed`, `:confirmed`, or `:finalized`
  - `:encoding` - `:base64` (default), `:base58`, `:"base64+zstd"`, `:json_parsed`
  """
  @spec get_account_info(<<_::256>>, keyword()) :: {:ok, map() | nil} | {:error, term()}
  def get_account_info(pubkey, opts \\ []) do
    config = account_config(opts)

    with {:ok, result} <- send_rpc("getAccountInfo", [encode_pubkey(pubkey), config], opts) do
      {:ok, deserialize_account_info(unwrap_value(result))}
    end
  end

  @doc """
  Get account info for multiple pubkeys (max 100).

  ## Options
  - `:commitment`, `:encoding` - same as `get_account_info/2`
  """
  @spec get_multiple_accounts([<<_::256>>], keyword()) :: {:ok, [map() | nil]} | {:error, term()}
  def get_multiple_accounts(pubkeys, opts \\ []) do
    config = account_config(opts)
    encoded = Enum.map(pubkeys, &encode_pubkey/1)

    with {:ok, result} <- send_rpc("getMultipleAccounts", [encoded, config], opts) do
      {:ok, Enum.map(unwrap_value(result), &deserialize_account_info/1)}
    end
  end

  defp deserialize_account_info(nil), do: nil

  defp deserialize_account_info(info) when is_map(info) do
    %{
      data: info["data"],
      executable: info["executable"],
      lamports: info["lamports"],
      owner: info["owner"],
      rent_epoch: info["rentEpoch"],
      space: info["space"]
    }
  end

  # ---------------------------------------------------------------------------
  # Blockhash / slot methods
  # ---------------------------------------------------------------------------

  @doc """
  Get the latest blockhash and its last valid block height.
  """
  @spec get_latest_blockhash(keyword()) ::
          {:ok, %{blockhash: binary(), last_valid_block_height: non_neg_integer()}}
          | {:error, term()}
  def get_latest_blockhash(opts \\ []) do
    with {:ok, result} <- send_rpc("getLatestBlockhash", params_with_config([], opts), opts) do
      value = unwrap_value(result)

      {:ok,
       %{
         blockhash: Signet.Base58.decode!(value["blockhash"]),
         last_valid_block_height: value["lastValidBlockHeight"]
       }}
    end
  end

  @doc """
  Get the current slot.
  """
  @spec get_slot(keyword()) :: {:ok, non_neg_integer()} | {:error, term()}
  def get_slot(opts \\ []) do
    send_rpc("getSlot", params_with_config([], opts), opts)
  end

  @doc """
  Get the current block height.
  """
  @spec get_block_height(keyword()) :: {:ok, non_neg_integer()} | {:error, term()}
  def get_block_height(opts \\ []) do
    send_rpc("getBlockHeight", params_with_config([], opts), opts)
  end

  # ---------------------------------------------------------------------------
  # Transaction methods
  # ---------------------------------------------------------------------------

  @doc """
  Get a transaction by its signature.

  Returns `nil` if the transaction is not found.

  ## Options
  - `:commitment` - `:confirmed` or `:finalized` (`:processed` is NOT supported)
  - `:encoding` - `:json` (default), `:json_parsed`, `:base64`, `:base58`
  """
  @spec get_transaction(String.t(), keyword()) :: {:ok, map() | nil} | {:error, term()}
  def get_transaction(signature, opts \\ []) do
    config = commitment_config(opts)
    config = Map.put(config, "maxSupportedTransactionVersion", 0)
    config = if e = Keyword.get(opts, :encoding), do: Map.put(config, "encoding", encoding_string(e)), else: config

    send_rpc("getTransaction", [signature, config], opts)
  end

  @doc """
  Get the statuses of transaction signatures (max 256).

  ## Options
  - `:search_transaction_history` - Search beyond recent status cache (default: false)
  """
  @spec get_signature_statuses([String.t()], keyword()) ::
          {:ok, [map() | nil]} | {:error, term()}
  def get_signature_statuses(signatures, opts \\ []) do
    config =
      if Keyword.get(opts, :search_transaction_history, false) do
        %{"searchTransactionHistory" => true}
      else
        %{}
      end

    params = if config == %{}, do: [signatures], else: [signatures, config]

    with {:ok, result} <- send_rpc("getSignatureStatuses", params, opts) do
      statuses =
        unwrap_value(result)
        |> Enum.map(fn
          nil ->
            nil

          s ->
            %{
              slot: s["slot"],
              confirmations: s["confirmations"],
              err: s["err"],
              confirmation_status: parse_commitment(s["confirmationStatus"])
            }
        end)

      {:ok, statuses}
    end
  end

  defp parse_commitment(nil), do: nil
  defp parse_commitment("processed"), do: :processed
  defp parse_commitment("confirmed"), do: :confirmed
  defp parse_commitment("finalized"), do: :finalized

  @doc """
  Get the minimum balance for rent exemption for a given data size.
  """
  @spec get_minimum_balance_for_rent_exemption(non_neg_integer(), keyword()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def get_minimum_balance_for_rent_exemption(data_length, opts \\ []) do
    send_rpc(
      "getMinimumBalanceForRentExemption",
      params_with_config([data_length], opts),
      opts
    )
  end

  # ---------------------------------------------------------------------------
  # Token methods
  # ---------------------------------------------------------------------------

  @doc """
  Get the token balance for an SPL Token account.

  Returns the raw integer amount, decimal precision, and `ui_amount_string`
  (a human-readable formatted string provided by the RPC node, e.g. `"1.5"`
  for 1500000 with 6 decimals).
  """
  @spec get_token_account_balance(<<_::256>>, keyword()) ::
          {:ok, %{amount: non_neg_integer(), decimals: non_neg_integer(), ui_amount_string: String.t()}}
          | {:error, term()}
  def get_token_account_balance(pubkey, opts \\ []) do
    with {:ok, result} <- send_rpc("getTokenAccountBalance", params_with_config([encode_pubkey(pubkey)], opts), opts) do
      value = unwrap_value(result)

      {:ok,
       %{
         amount: String.to_integer(value["amount"]),
         decimals: value["decimals"],
         ui_amount_string: value["uiAmountString"]
       }}
    end
  end

  @doc """
  Get all token accounts owned by a wallet.

  Requires exactly one filter: `:mint` (specific token) or `:program_id`
  (all tokens under a program).

  Uses `jsonParsed` encoding by default for structured token account data.

  ## Examples

      get_token_accounts_by_owner(wallet, mint: usdc_mint)
      get_token_accounts_by_owner(wallet, program_id: Programs.token_program())
  """
  @spec get_token_accounts_by_owner(<<_::256>>, keyword(), keyword()) ::
          {:ok, [%{pubkey: String.t(), account: map()}]} | {:error, term()}
  def get_token_accounts_by_owner(owner, filter, opts \\ []) do
    filter_obj =
      cond do
        mint = Keyword.get(filter, :mint) -> %{"mint" => encode_pubkey(mint)}
        program_id = Keyword.get(filter, :program_id) -> %{"programId" => encode_pubkey(program_id)}
        true -> raise ArgumentError, "get_token_accounts_by_owner requires :mint or :program_id filter"
      end

    config = account_config(Keyword.put_new(opts, :encoding, :json_parsed))

    with {:ok, result} <- send_rpc("getTokenAccountsByOwner", [encode_pubkey(owner), filter_obj, config], opts) do
      accounts =
        unwrap_value(result)
        |> Enum.map(fn item ->
          %{
            pubkey: item["pubkey"],
            account: deserialize_account_info(item["account"])
          }
        end)

      {:ok, accounts}
    end
  end

  # ---------------------------------------------------------------------------
  # Fee methods
  # ---------------------------------------------------------------------------

  @doc """
  Get recent prioritization fees. Pass account addresses to see fees for
  transactions locking those accounts.
  """
  @spec get_recent_prioritization_fees([<<_::256>>], keyword()) ::
          {:ok, [%{slot: non_neg_integer(), prioritization_fee: non_neg_integer()}]}
          | {:error, term()}
  def get_recent_prioritization_fees(addresses \\ [], opts \\ []) do
    encoded = Enum.map(addresses, &encode_pubkey/1)
    params = if encoded == [], do: [], else: [encoded]

    with {:ok, result} <- send_rpc("getRecentPrioritizationFees", params, opts) do
      fees =
        Enum.map(result, fn f ->
          %{slot: f["slot"], prioritization_fee: f["prioritizationFee"]}
        end)

      {:ok, fees}
    end
  end

  # ---------------------------------------------------------------------------
  # Node info methods
  # ---------------------------------------------------------------------------

  @doc """
  Check node health. Returns `:ok` if healthy, `{:error, ...}` if unhealthy.
  """
  @spec get_health(keyword()) :: :ok | {:error, term()}
  def get_health(opts \\ []) do
    case send_rpc("getHealth", [], opts) do
      {:ok, "ok"} -> :ok
      {:ok, _} -> :ok
      error -> error
    end
  end

  @doc """
  Get the node version.
  """
  @spec get_version(keyword()) ::
          {:ok, %{solana_core: String.t(), feature_set: non_neg_integer()}}
          | {:error, term()}
  def get_version(opts \\ []) do
    with {:ok, result} <- send_rpc("getVersion", [], opts) do
      {:ok, %{solana_core: result["solana-core"], feature_set: result["feature-set"]}}
    end
  end

  # ---------------------------------------------------------------------------
  # Write methods
  # ---------------------------------------------------------------------------

  @doc """
  Send a signed transaction to the network.

  Accepts a `Signet.Solana.Transaction` struct or raw serialized bytes.

  ## Options
  - `:encoding` - `:base64` (default) or `:base58`
  - `:skip_preflight` - Skip preflight checks (default: false)
  - `:preflight_commitment` - Commitment for preflight simulation
  - `:max_retries` - Max retries before giving up

  Returns the transaction signature (Base58 string).
  """
  @spec send_transaction(binary() | Signet.Solana.Transaction.t(), keyword()) ::
          {:ok, String.t()} | {:error, term()}
  def send_transaction(transaction, opts \\ [])

  def send_transaction(%Signet.Solana.Transaction{} = trx, opts) do
    send_transaction(Signet.Solana.Transaction.serialize(trx), opts)
  end

  def send_transaction(bytes, opts) when is_binary(bytes) do
    encoding = Keyword.get(opts, :encoding, :base64)

    encoded =
      case encoding do
        :base64 -> Base.encode64(bytes)
        :base58 -> Signet.Base58.encode(bytes)
      end

    config = %{"encoding" => encoding_string(encoding)}
    config = if Keyword.get(opts, :skip_preflight, false), do: Map.put(config, "skipPreflight", true), else: config
    config = if c = Keyword.get(opts, :preflight_commitment), do: Map.put(config, "preflightCommitment", to_string(c)), else: config
    config = if r = Keyword.get(opts, :max_retries), do: Map.put(config, "maxRetries", r), else: config

    send_rpc("sendTransaction", [encoded, config], opts)
  end

  @doc """
  Simulate a transaction without submitting it.

  Returns simulation result including logs, compute units consumed, and errors.
  """
  @spec simulate_transaction(binary() | Signet.Solana.Transaction.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def simulate_transaction(transaction, opts \\ [])

  def simulate_transaction(%Signet.Solana.Transaction{} = trx, opts) do
    simulate_transaction(Signet.Solana.Transaction.serialize(trx), opts)
  end

  def simulate_transaction(bytes, opts) when is_binary(bytes) do
    config = %{"encoding" => "base64"}
    config = if c = Keyword.get(opts, :commitment), do: Map.put(config, "commitment", to_string(c)), else: config
    config = if Keyword.get(opts, :sig_verify, false), do: Map.put(config, "sigVerify", true), else: config
    config = if Keyword.get(opts, :replace_recent_blockhash, false), do: Map.put(config, "replaceRecentBlockhash", true), else: config

    encoded = Base.encode64(bytes)

    with {:ok, result} <- send_rpc("simulateTransaction", [encoded, config], opts) do
      value = unwrap_value(result)
      {:ok, %{err: value["err"], logs: value["logs"], units_consumed: value["unitsConsumed"]}}
    end
  end

  @doc """
  Request an airdrop of SOL (devnet/testnet only).

  Returns the airdrop transaction signature.
  """
  @spec request_airdrop(<<_::256>>, non_neg_integer(), keyword()) ::
          {:ok, String.t()} | {:error, term()}
  def request_airdrop(pubkey, lamports, opts \\ []) do
    send_rpc(
      "requestAirdrop",
      params_with_config([encode_pubkey(pubkey), lamports], opts),
      opts
    )
  end

  # ---------------------------------------------------------------------------
  # High-level helpers
  # ---------------------------------------------------------------------------

  @doc """
  Send a transaction and poll for confirmation.

  ## Options
  - `:commitment` - Confirmation level to wait for (default: `:confirmed`)
  - `:timeout` - Max time to wait in ms (default: 30_000)
  - `:poll_interval` - Poll interval in ms (default: 500)
  - All options from `send_transaction/2`
  """
  @spec send_and_confirm(Signet.Solana.Transaction.t() | binary(), keyword()) ::
          {:ok, String.t()} | {:error, term()}
  def send_and_confirm(transaction, opts \\ []) do
    target_commitment = Keyword.get(opts, :commitment, :confirmed)
    timeout = Keyword.get(opts, :timeout, 30_000)
    poll_interval = Keyword.get(opts, :poll_interval, 500)

    with {:ok, signature} <- send_transaction(transaction, opts) do
      deadline = System.monotonic_time(:millisecond) + timeout

      poll_signature(signature, target_commitment, poll_interval, deadline, opts)
    end
  end

  defp poll_signature(signature, target, interval, deadline, opts) do
    if System.monotonic_time(:millisecond) > deadline do
      {:error, :timeout}
    else
      case get_signature_statuses([signature], opts) do
        {:ok, [nil]} ->
          Process.sleep(interval)
          poll_signature(signature, target, interval, deadline, opts)

        {:ok, [%{err: err}]} when not is_nil(err) ->
          {:error, {:transaction_error, err}}

        {:ok, [%{confirmation_status: status}]} when status == target or status == :finalized ->
          {:ok, signature}

        {:ok, [%{confirmation_status: :confirmed}]} when target == :processed ->
          {:ok, signature}

        {:ok, _} ->
          Process.sleep(interval)
          poll_signature(signature, target, interval, deadline, opts)

        {:error, _} = err ->
          err
      end
    end
  end
end
