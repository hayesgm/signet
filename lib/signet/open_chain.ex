defmodule Signet.OpenChain do
  @moduledoc ~S"""
  API Client for [OpenChain.xyz](https://openchain.xyz] API.
  """

  use Signet.Hex

  defmodule Signatures do
    defstruct [:events, :functions]

    @type t :: %__MODULE__{
            events: [{binary(), String.t()}],
            functions: [{binary(), String.t()}]
          }

    @doc ~S"""
    Deserializes an open chain signature.

    ## Examples

        iex> %{
        ...>   "event" => %{
        ...>     "0x08c379a0" => []
        ...>   },
        ...>   "function" => %{
        ...>     "0x08c379a0" => [
        ...>       %{
        ...>         "name" => "Error(string)",
        ...>         "filtered" => false
        ...>       }
        ...>     ]
        ...>   }
        ...> }
        ...> |> Signet.OpenChain.Signatures.deserialize()
        %Signet.OpenChain.Signatures{
          events: [],
          functions: [
            {<<8, 195, 121, 160>>, "Error(string)"}
          ]
        }
    """
    def deserialize(%{"event" => event_list, "function" => function_list}) do
      %__MODULE__{
        events: decode_entries(event_list),
        functions: decode_entries(function_list)
      }
    end

    defp decode_entries(entries) when is_map(entries) do
      entries
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Enum.map(fn
        {k, vs} ->
          vs
          |> Enum.filter(fn v -> not v["filtered"] end)
          |> Enum.map(fn v -> {from_hex!(k), v["name"]} end)
      end)
      |> List.flatten()
    end
  end

  defmodule API do
    def http_client(), do: Application.get_env(:signet, :open_chain_client, Finch)

    @base_url Application.compile_env(:signet, :open_chain_base_url, "https://api.openchain.xyz")
    @finch_name Application.compile_env(:signet, :finch_name, SignetFinch)

    @spec get(String.t(), Keyword.t()) :: {:ok, term()} | {:error, String.t()}
    def get(url, opts) do
      headers = Keyword.get(opts, :headers, [])
      timeout = Keyword.get(opts, :timeout, 30_000)

      request = Finch.build(:get, url, headers)

      case http_client().request(request, @finch_name, receive_timeout: timeout) do
        {:ok, %Finch.Response{status: code, body: resp_body}} when code in 200..299 ->
          case Jason.decode(resp_body) do
            {:ok, resp} ->
              case resp do
                %{"ok" => true, "result" => result} ->
                  {:ok, result}

                %{"ok" => false, "error" => error} ->
                  {:error, error}
              end

            {:error, json_error} ->
              {:error, Jason.DecodeError.message(json_error)}
          end

        {:error, %Finch.Error{reason: reason}} ->
          {:error, "error: #{inspect(reason)}"}
      end
    end

    @doc ~S"""
    Runs a lookup query from OpenChain, returning matching signtures.

    ## Examples

        iex> Signet.OpenChain.API.lookup([<<8, 195, 121, 160>>], [])
        {:ok,
          %Signet.OpenChain.Signatures{
            events: [],
            functions: [{<<8, 195, 121, 160>>, "Error(string)"}]
          }
        }
    """
    @spec lookup([binary()], [binary()], Keyword.t()) ::
            {:ok, Signatures.t()} | {:error, String.t()}
    def lookup(event_signatures, function_signatures, opts \\ []) do
      {filter, opts} = Keyword.pop(opts, :filter, true)

      events =
        event_signatures
        |> Enum.map(&Signet.Hex.to_hex/1)
        |> Enum.join(",")

      functions =
        function_signatures
        |> Enum.map(&Signet.Hex.to_hex/1)
        |> Enum.join(",")

      with {:ok, resp} <-
             get(
               "#{@base_url}/signature-database/v1/lookup?#{URI.encode_query(event: events, function: functions, filter: filter)}",
               opts
             ) do
        {:ok, Signatures.deserialize(resp)}
      end
    end
  end

  @doc ~S"""
  Tries to lookup given signature of given type.

  ## Examples

      iex> Signet.OpenChain.lookup(<<8, 195, 121, 160>>, :function)
      {:ok, "Error(string)"}
  """
  def lookup(signature, type, opts \\ []) do
    {raise_on_multiple, opts} = Keyword.pop(opts, :raise_on_multiple, false)

    found_signatures_result =
      case type do
        :function ->
          with {:ok, signatures} <- API.lookup([], [signature], opts) do
            {:ok, signatures.functions}
          end

        :event ->
          with {:ok, signatures} <- API.lookup([signature], [], opts) do
            {:ok, signatures.events}
          end
      end

    with {:ok, found_signatures} <- found_signatures_result do
      case Enum.count(found_signatures) do
        0 ->
          {:error, "Signature not found"}

        x when x == 1 or not raise_on_multiple ->
          {^signature, abi} = List.first(found_signatures)

          {:ok, abi}

        _ ->
          {:error, "Multiple matching signatures: #{Enum.join(found_signatures, ",")}"}
      end
    end
  end

  @doc ~S"""
  Looks up and tries to decode a given error message from its ABI-encoded form.

  ## Examples

      iex> Signet.OpenChain.lookup_error(~h[0x08c379a00000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000001b43616c6c6572206e6f74206174746573746572206d616e616765720000000000])
      {:ok, ["Caller not attester manager"]}
  """
  def lookup_error(_, opts \\ [])

  def lookup_error(<<signature::binary-size(4), data::binary>>, opts) do
    with {:ok, signature} <- lookup(signature, :function, opts),
         function_selector <- ABI.FunctionSelector.decode(signature),
         result <- ABI.decode(function_selector, data) do
      {:ok, result}
    end
  end

  def lookup_error(_, _opts), do: {:error, "Error must include 4-byte signature"}

  @doc """
    Looks up an error and decodes its values, returning both.

      ## Examples

          iex> Signet.OpenChain.lookup_error_and_values(~h[0x08c379a00000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000001b43616c6c6572206e6f74206174746573746572206d616e616765720000000000])
          {:ok, "Error(string)", ["Caller not attester manager"]}
  """
  def lookup_error_and_values(_, opts \\ [])

  def lookup_error_and_values(<<signature::binary-size(4), data::binary>>, opts) do
    with {:ok, signature} <- lookup(signature, :function, opts),
         function_selector <- ABI.FunctionSelector.decode(signature),
         result <- ABI.decode(function_selector, data) do
      {:ok, signature, result}
    end
  end

  def lookup_error_and_values(_, _opts), do: {:error, "Error must include 4-byte signature"}
end
