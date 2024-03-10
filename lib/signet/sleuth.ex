defmodule Signet.Sleuth do
  @moduledoc ~S"""
  Sleuth allows you to run a contract call as a single
  `eth_call` call.

  Note: Signet.Contract.Sleuth generated from `mix signet.gen --prefix signet/contract ./priv/Sleuth.json`
  """
  use Signet.Hex

  @sleuth_address ~h[0xc6a613fdac3465d250df7ff3cc21bec86eb8a372]

  # Note: this is the only real function, the rest are helpers
  #       to make calling into Sleuth easier.
  def query(bytecode, query, selector, opts \\ []) when is_binary(bytecode) and is_list(opts) do
    {sleuth_address, rpc_opts} = Keyword.pop(opts, :sleuth_address, @sleuth_address)

    with {:ok, query_res_bytes} <-
           Signet.Contract.Sleuth.call_query(sleuth_address, bytecode, query, rpc_opts),
         {:ok, query_res} <- try_decode_bytes(query_res_bytes),
         {:ok, res} <- try_decode(query_res, selector) do
      {:ok, unwrap_outer_tuple(encode_map(res, selector.returns, ""))}
    end
  end

  # Helpers to allow simple querying when query doesn't take arguments
  def query_by(mod, fun) when is_atom(mod) and is_atom(fun), do: query_by(mod, fun, [])
  def query_by(mod, opts) when is_atom(mod) and is_list(opts), do: query_by(mod, :query, opts)
  def query_by(mod), do: query_by(mod, :query, [])

  def query_by(mod, fun, opts) when is_atom(mod) and is_atom(fun) and is_list(opts) do
    encode_fn = String.to_atom("encode_" <> to_string(fun))
    selector_fn = String.to_atom(to_string(fun) <> "_selector")

    bytecode =
      try do
        apply(mod, :bytecode, [])
      rescue
        _ ->
          raise "Sleuth module #{mod} does not define required \"bytecode/0\" function"
      end

    query_val =
      try do
        apply(mod, encode_fn, [])
      rescue
        _ ->
          raise "Sleuth module #{mod} does not define required \"#{encode_fn}/0\" function"
      end

    selector =
      try do
        apply(mod, selector_fn, [])
      rescue
        _ ->
          raise "Sleuth module #{mod} does not define required \"#{selector_fn}/0\" function"
      end

    query(bytecode, query_val, selector, opts)
  end

  defp try_decode_bytes(bytes) do
    try do
      [decoded] = ABI.decode("(bytes)", bytes)
      {:ok, decoded}
    rescue
      e ->
        {:error, "error decoding bytes: #{inspect(e)}"}
    end
  end

  defp try_decode(query_res, selector) do
    try do
      {:ok, ABI.decode(%ABI.FunctionSelector{types: selector.returns}, query_res)}
    rescue
      e ->
        {:error, "error decoding: #{inspect(e)}"}
    end
  end

  defp encode_map(res, types, prefix) do
    Enum.map(Enum.zip(res, Enum.with_index(types)), fn {res, {type, i}} ->
      encode_item(res, type, i, prefix)
    end)
    |> Enum.into(%{})
  end

  defp encode_item(res, type, i, prefix) do
    var_name =
      if is_nil(type.name) or type.name == "" do
        "var#{i}"
      else
        type.name
      end

    res_enc = encode_value(res, type.type, i, prefix)

    {var_name, res_enc}
  end

  defp encode_value(res, type, i, prefix) do
    sub_prefix = prefix <> "#{i}_"

    encode_array = fn sub_type ->
      Enum.map(Enum.with_index(res), fn {r, j} -> encode_value(r, sub_type, j, sub_prefix) end)
    end

    case type do
      {:bytes, _} ->
        to_hex(res)

      x when x in [:bytes, :address] ->
        to_hex(res)

      {:tuple, sub_types} ->
        encode_map(Tuple.to_list(res), sub_types, sub_prefix)

      {:array, sub_type} ->
        encode_array.(sub_type)

      {:array, sub_type, _} ->
        encode_array.(sub_type)

      _ ->
        res
    end
  end

  defp unwrap_outer_tuple(%{"var0" => x}), do: x
  defp unwrap_outer_tuple(els), do: els
end
