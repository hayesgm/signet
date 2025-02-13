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
    {decode_binaries, opts} = Keyword.pop(opts, :decode_binaries, true)
    {decode_structs, opts} = Keyword.pop(opts, :decode_structs, false)
    {be_obvious, rpc_opts} = Keyword.pop(opts, :be_obvious, decode_structs)

    with {:ok, query_res_bytes} <-
           Signet.Contract.Sleuth.call_query(sleuth_address, bytecode, query, rpc_opts),
         {:ok, query_res} <- try_decode_bytes(query_res_bytes),
         {:ok, res} <- try_decode(query_res, selector, decode_structs) do
      {:ok,
       postprocess(res, selector.returns,
         annotated: annotated,
         decode_binaries: decode_binaries,
         be_obvious: be_obvious
       )}
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

  defp try_decode(query_res, selector, decode_structs) do
    try do
      {:ok,
       ABI.decode(
         %ABI.FunctionSelector{types: selector.returns},
         query_res,
         decode_structs: decode_structs
       )}
    rescue
      e ->
        {:error, "error decoding: #{inspect(e)}"}
    end
  end

  defp postprocess(results, named_types, opts) when is_list(results) and is_list(named_types) do
    be_obvious = Keyword.get(opts, :be_obvious, false)

    results
    |> Enum.zip(named_types)
    |> Enum.map(fn {it, t} -> {t.name, postprocess(it, t.type, opts)} end)
    |> then(fn
      processed_results when not be_obvious ->
        case processed_results do
          [] -> []
          [{nil, result}] -> result
          [{"", result}] -> result

          [_more | _than_one] = processed_results ->
            processed_results
            |> Enum.with_index()
            |> Enum.map(fn {{name, it}, i} ->
              name =
                if is_nil(name) or name == "" do
                  "var#{i}"
                else
                  name
                end

              {name, it}
            end)
            |> Enum.into(%{})
        end

      processed_results when be_obvious ->
        Enum.map(processed_results, fn {_, v} -> v end)
    end)
  end

  defp postprocess(item, {:tuple, named_types}, opts)
       when is_tuple(item) and is_list(named_types) do
    atomize = Keyword.get(opts, :atomize, false)

    item
    |> Tuple.to_list()
    |> Enum.zip(named_types)
    |> Enum.map(fn {item, %{type: type, name: name}} ->
      name =
        if not is_atom(name) and atomize do
          String.to_atom(Macro.underscore(name))
        else
          name
        end

      {name, postprocess(item, type, opts)}
    end)
    |> Enum.into(%{})
  end

  defp postprocess(item, {:tuple, named_types}, opts)
       when is_map(item) and is_list(named_types) do
    item
    |> Enum.map(fn {k, v} ->
      %{type: type} =
        Enum.find(named_types, fn %{name: name} -> Macro.underscore(name) == to_string(k) end)

      {k, postprocess(v, type, opts)}
    end)
    |> Enum.into(%{})
  end

  defp postprocess(item, {:array, type}, opts) when is_list(item) do
    Enum.map(item, &postprocess(&1, type, opts))
  end

  defp postprocess(item, {:array, type, _}, opts) when is_list(item),
    do: postprocess(item, {:array, type}, opts)

  defp postprocess(item, type, opts) do
    item_encoded =
      if not Keyword.get(opts, :decode_binaries, true) do
        case type do
          :address -> to_hex(item)
          :bytes -> to_hex(item)
          {:bytes, _size} -> to_hex(item)
          _nonbinary_scalar -> item
        end
      else
        item
      end

    if Keyword.get(opts, :annotated, false) do
      {type, item_encoded}
    else
      item_encoded
    end
  end

  defp try_apply(mod, fun, args) do
    try do
      apply(mod, fun, args)
    rescue
      _ ->
        raise "Sleuth module #{mod} does not define required \"#{fun}/#{Enum.count(args)}\" function"
    end
  end
end
