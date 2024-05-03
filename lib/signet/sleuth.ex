defmodule Signet.Sleuth do
  @moduledoc ~S"""
  Sleuth allows you to run a contract call as a single
  `eth_call` call.

  Note: Signet.Contract.Sleuth generated from `mix signet.gen --prefix signet/contract ./priv/Sleuth.json`
  """
  use Signet.Hex

  @sleuth_address ~h[0xFd946Bf25C47A1Bff567B28bA78a961bf78FF9d2]

  def query(bytecode, query, selector, opts \\ []),
    do: query_internal(bytecode, query, selector, false, opts)

  def query_annotated(bytecode, query, selector, opts \\ []),
    do: query_internal(bytecode, query, selector, true, opts)

  def query_by(mod, fun) when is_atom(mod) and is_atom(fun), do: query_by(mod, fun, [])
  def query_by(mod, opts) when is_atom(mod) and is_list(opts), do: query_by(mod, :query, opts)
  def query_by(mod), do: query_by(mod, :query, [])

  def query_by(mod, fun, opts) when is_atom(mod) and is_atom(fun) and is_list(opts) do
    bytecode = try_apply(mod, :bytecode, [])
    query_val = try_apply(mod, String.to_atom("encode_" <> to_string(fun)), [])
    selector = try_apply(mod, String.to_atom(to_string(fun) <> "_selector"), [])

    query_internal(bytecode, query_val, selector, false, opts)
  end

  defp query_internal(bytecode, query, selector, annotated, opts)
       when is_binary(bytecode) and is_list(opts) do
    {sleuth_address, opts} = Keyword.pop(opts, :sleuth_address, @sleuth_address)
    {decode_binaries, rpc_opts} = Keyword.pop(opts, :decode_binaries, true)

    with {:ok, query_res_bytes} <-
           Signet.Contract.Sleuth.call_query(sleuth_address, bytecode, query, rpc_opts),
         {:ok, query_res} <- try_decode_bytes(query_res_bytes),
         {:ok, res} <- try_decode(query_res, selector) do
      {:ok, unwrap_outer_tuple(encode_map(res, selector.returns, annotated, decode_binaries))}
    end
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

  defp encode_map(res, types, annotated, decode_binaries) do
    Enum.map(Enum.zip(res, Enum.with_index(types)), fn {res, {type, i}} ->
      encode_item(res, type, i, annotated, decode_binaries)
    end)
    |> Enum.into(%{})
  end

  defp encode_item(res, type, i, annotated, decode_binaries) do
    var_name =
      if is_nil(type.name) or type.name == "" do
        "var#{i}"
      else
        type.name
      end

    res_enc = encode_value(res, type.type, annotated, decode_binaries)

    {var_name, res_enc}
  end

  defp encode_value(res, type, annotated, decode_binaries) do
    encode_array = fn sub_type ->
      Enum.map(res, fn r -> encode_value(r, sub_type, annotated, decode_binaries) end)
    end

    case type do
      {:tuple, sub_types} ->
        encode_map(Tuple.to_list(res), sub_types, annotated, decode_binaries)

      {:array, sub_type} ->
        encode_array.(sub_type)

      {:array, sub_type, _} ->
        encode_array.(sub_type)

      _ ->
        res_enc =
          case {type, decode_binaries} do
            {:address, false} ->
              to_hex(res)

            {:bytes, false} ->
              to_hex(res)

            _ ->
              res
          end

        if annotated do
          {type, res_enc}
        else
          res_enc
        end
    end
  end

  defp unwrap_outer_tuple(xs = %{"var0" => x}) when map_size(xs) == 1, do: x
  defp unwrap_outer_tuple(els), do: els

  defp try_apply(mod, fun, args) do
    try do
      apply(mod, fun, args)
    rescue
      _ ->
        raise "Sleuth module #{mod} does not define required \"#{fun}/#{Enum.count(args)}\" function"
    end
  end
end
