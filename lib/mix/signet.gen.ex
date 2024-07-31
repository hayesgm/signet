defmodule Mix.Tasks.Signet.Gen do
  @shortdoc "Generates wrapper modules from Solidity artifacts or ABI files"

  @moduledoc ~S"""
  `signet.gen` generates wrapper modules from Solidity artifacts.

  This module will auto-generate code that can be used to easily call into
  a contract. You can pass in either the ABI output or the full Solidity
  output. If you pass in the Solidity artifacts, you'll get wrappers for
  the bytecode.

  For example, `some_contract.ex`

  ```elixir
  defmodule SomeContract do
    use Signet.Hex

    def contract_name do
      "SomeContract"
    end

    def encode_some_function(val) do
      ABI.encode("some_function(uint256)", [val])
    end

    def execute_some_function(contract, val, opts \\ []) do
      Signet.RPC.execute_trx(contract, encode_some_function(val), opts)
    end

    def bytecode(), do: ~h[0x...]

    def deployed_bytecode(), do: ~h[0x...]
  end
  ```

  These stubs are useful, since you can easily then call:

  ```iex
  {:ok, tx_id} = Contract.SomeContract.execute_some_function(addr, 55, priority_fee: {55, :gwei})
  ```


  🐉🌊🌊🌊🌊🌊🐉   HERE BE DRAGONS    🐉🌊🌊🌊🌊🌊🐉


  # Usage

  `mix signet.gen "out/**/*.json"`

   * `--prefix`: Prefix for the outputed modules
     - E.g. `my_app` -> `MyApp.SomeContract` in `my_app/some_contract.ex`
     - E.g. `my_app/contract` -> `MyApp.Contract.SomeContract` in `my_app/contract/some_contract.ex`
   * `--out`: Out directory, e.g. `lib/my_app/` [default `lib/`]
  """

  use Mix.Task
  use Signet.Hex

  require Logger

  defmodule InvalidFileError do
    defexception message: "invalid file error"
  end

  # The contract name isn't obvious from the output-json file, thus we look either by
  # trying to find it in the metadata settings or AST [below]
  defp get_contract_name_by_metadata(abi) do
    case get_in(abi, ["metadata", "settings", "compilationTarget"]) do
      nil ->
        nil

      contracts ->
        case Enum.into(contracts, []) do
          [{_k, v} | _rest] ->
            v

          _ ->
            nil
        end
    end
  end

  # Search the AST for the module name from the output-json
  defp get_contract_name_by_ast(abi) do
    case abi["ast"] do
      %{"sourceUnit" => _, "absolutePath" => absolute_path} ->
        absolute_path
        |> String.split("/")
        |> List.last()
        |> case do
          nil ->
            nil

          file_name ->
            file_name
            |> String.split(".")
            |> List.first()
        end
    end
  end

  # Solidity functions are allowed to overlap with different arugment types, but this
  # would break any Elixir functions, which are not allowed to do that. Thus, we walk
  # the abi from the output-json and see if there are duplicate functions with the
  # same name. If so, we rename any latter by postpending `_aabbccdd` (the function
  # signture) at the end of the function name. The first one doesn't have the prefix,
  # but we could make this more complex to rename all of them if there are any dupes;
  # it would just require two passes.
  defp rename_dups(abis) do
    {abis, _} =
      Enum.reduce(abis, {[], []}, fn abi, {acc, seen} ->
        fn_sel =
          try do
            ABI.FunctionSelector.parse_specification_item(abi)
          rescue
            e ->
              Logger.warning("Ignoring due to failed parse: #{inspect(abi)}")
              Logger.error(e)

              {acc, seen}
          end

        name = abi["name"]

        if is_nil(name) do
          {[abi | acc], seen}
        else
          lower_name = String.downcase(name)

          <<abi_enc_signature::binary-size(4), _::binary>> =
            Signet.Hash.keccak(ABI.FunctionSelector.encode(fn_sel))

          abi_new =
            if Enum.member?(seen, lower_name) do
              "0x" <> abi_sig = Signet.Hex.encode_hex(abi_enc_signature)

              Map.put(abi, "fn_name", "#{name}_#{abi_sig}")
            else
              abi
            end

          {[abi_new | acc], [lower_name | seen]}
        end
      end)

    Enum.reverse(abis)
  end

  # Function to take the abi from the output-json and output function defs (e.g. encode and execute)
  defp get_encode_calls(full_abi, has_bytecode) do
    {fns, decoders, events, errors} =
      (full_abi["abi"] || [])
      |> rename_dups()
      |> Enum.reduce({[], [], [], []}, fn abi, {acc_fns, acc_decoders, acc_events, acc_errors} ->
        case get_encode_call(abi, has_bytecode) do
          {functions, generic_call_decoder, nil, nil} ->
            {acc_fns ++ functions, [generic_call_decoder | acc_decoders], acc_events, acc_errors}

          {functions, nil, generic_event_fn, nil} ->
            {acc_fns ++ functions, acc_decoders, [generic_event_fn | acc_events], acc_errors}

          {functions, nil, nil, generic_error_fn} ->
            {acc_fns ++ functions, acc_decoders, acc_events, [generic_error_fn | acc_errors]}

          nil ->
            {acc_fns, acc_decoders, acc_events, acc_errors}
        end
      end)

    decoders = [
      quote do
        def decode_call(_), do: :not_found
      end
      | decoders
    ]

    errors = [
      quote do
        def decode_error(_), do: :not_found
      end
      | errors
    ]

    events = [
      quote do
        def decode_event(_, _), do: :not_found
      end
      | events
    ]

    fns ++ Enum.reverse(decoders) ++ Enum.reverse(events) ++ Enum.reverse(errors)
  end

  # Parses the ABI spec and generates the functions (encode and execute) if we can parse
  # the ABI spec. We've recently updated our ABI parsing library that this doesn't fail
  # nearly as often as it used to (e.g. it can handle tuples)
  defp get_encode_call(abi, has_bytecode) do
    fn_selector =
      try do
        ABI.FunctionSelector.parse_specification_item(abi)
      rescue
        _e ->
          Logger.warning("Ignoring due to failed parse: #{inspect(abi)}")
          nil
      end

    case fn_selector do
      fs = %ABI.FunctionSelector{function: name} when not is_nil(name) ->
        encode_function_call(fs, abi["fn_name"] || name, has_bytecode)

      fs = %ABI.FunctionSelector{function_type: function_type} ->
        encode_function_call(fs, to_string(function_type), has_bytecode)

      _ ->
        Logger.warning("Ignoring function due to missing name")
        nil
    end
  end

  # Generate the encode and execute functions. This is ... complex (read: hacky)
  defp encode_function_call(selector, fn_name, has_bytecode) do
    # These are the function names we'll define
    encode_fun_name = String.to_atom("encode_#{Macro.underscore(fn_name)}")
    encode_event_fun_name = String.to_atom("encode_#{Macro.underscore(fn_name)}_event")
    build_trx_fun_name = String.to_atom("build_trx_#{Macro.underscore(fn_name)}")
    call_fun_name = String.to_atom("call_#{Macro.underscore(fn_name)}")
    estimate_gas_fun_name = String.to_atom("estimate_gas_#{Macro.underscore(fn_name)}")
    execute_fun_name = String.to_atom("execute_#{Macro.underscore(fn_name)}")
    prepare_fun_name = String.to_atom("prepare_#{Macro.underscore(fn_name)}")
    selector_fun_name = String.to_atom("#{Macro.underscore(fn_name)}_selector")
    event_selector_fun_name = String.to_atom("#{Macro.underscore(fn_name)}_event_selector")
    decode_event_fun_name = String.to_atom("decode_#{Macro.underscore(fn_name)}_event")
    decode_error_fun_name = String.to_atom("decode_#{Macro.underscore(fn_name)}_error")
    decode_call_fun_name = String.to_atom("decode_#{Macro.underscore(fn_name)}_call")
    exec_vm_fun_name = String.to_atom("exec_vm_#{Macro.underscore(fn_name)}")

    event_selector = selector

    argument_types =
      case selector.function_type do
        x when x in [:fallback, :receive] ->
          [%{type: :bytes, name: "data"}]

        _ ->
          selector.types
      end

    # We are returning 4 values and will do a double unzip here so we can return
    # them from one function but get 4 separates lists. A better version of this
    # code would use a reduction to define 4 lists properly.
    {args, vals} =
      Enum.unzip(
        Enum.with_index(argument_types, fn argument_type, index ->
          name =
            case Map.get(argument_type, :name) do
              x when is_nil(x) or x == "" ->
                "var#{index}"

              els ->
                String.trim_leading(els, "_")
            end

          unless Map.has_key?(argument_type, :name) do
            # There's no name for this argument, we're going to return nils
            # here which will mean this function doesn't get included in
            # the generated code.
            {{nil, nil}, {nil, nil}}
          else
            names =
              case argument_type.type do
                {:tuple, tuple_types} ->
                  Enum.map(tuple_types, fn t -> Map.get(t, :name) end)

                _ ->
                  [nil]
              end

            if not Enum.member?(names, nil) and not Enum.member?(names, "") do
              # For a struct, we're going to make the arguments a map to make it
              # name and named for the caller. But this is harder since we'll need
              # to pass the arguments as a `{tuple}` to the encode function, since
              # they need to be ordered. Thus there's a bunch of insane logic here
              # in how to gen the map, and the calls, and trying to make sure we
              # underscore `_unused` vars to prevent compiler warnings.
              #
              # HERE BE DRAGONS 🐉🌊🌊🌊🌊🌊🐉
              #
              name_var = Macro.var(String.to_atom(Macro.underscore(name)), __MODULE__)

              encode_unused_name_var =
                Macro.var(String.to_atom("_" <> Macro.underscore(name)), __MODULE__)

              encode_els =
                Enum.map(names, fn el ->
                  el_atom = String.to_atom(Macro.underscore(el))
                  el_var = Macro.var(el_atom, __MODULE__)

                  quote do
                    {unquote(el_atom), unquote(el_var)}
                  end
                end)

              execute_els_unused =
                Enum.map(names, fn el ->
                  el_atom = String.to_atom(Macro.underscore(el))
                  el_atom_unused = String.to_atom("_" <> Macro.underscore(el))
                  el_var_unused = Macro.var(el_atom_unused, __MODULE__)

                  quote do
                    {unquote(el_atom), unquote(el_var_unused)}
                  end
                end)

              encode_value_inners =
                Enum.map(names, fn el ->
                  el_atom = String.to_atom(Macro.underscore(el))
                  el_var = Macro.var(el_atom, __MODULE__)

                  quote do
                    unquote(el_var)
                  end
                end)

              encode_argument =
                quote do
                  unquote(encode_unused_name_var) = %{unquote_splicing(encode_els)}
                end

              execute_argument =
                quote do
                  unquote(name_var) = %{unquote_splicing(execute_els_unused)}
                end

              execute_value = name_var

              encode_value =
                quote do
                  {unquote_splicing(encode_value_inners)}
                end

              {{execute_argument, encode_argument}, {execute_value, encode_value}}
            else
              var = Macro.var(String.to_atom(Macro.underscore(name)), __MODULE__)
              {{var, var}, {var, var}}
            end
          end
        end)
      )

    # These are the unzipped list of arguments and values to use with the
    # encode function and execute functions.
    {execute_arguments, encode_arguments} = Enum.unzip(args)
    {execute_values, encode_values} = Enum.unzip(vals)

    abi = ABI.FunctionSelector.encode(selector)

    signature =
      <<abi_enc_signature::binary-size(4), _::binary>> =
      Signet.Hash.keccak(ABI.FunctionSelector.encode(selector))

    abi_enc_signature_list = :erlang.binary_to_list(abi_enc_signature)
    signature_list = :erlang.binary_to_list(signature)
    error_name = selector.function

    no_bytecode_constructor =
      selector.function_type == :constructor and
        not has_bytecode

    # check if we bailed on any argument and bail generally, if so.
    if Enum.member?(execute_arguments, nil) or no_bytecode_constructor do
      Logger.warning("Ignoring function #{selector.function} due to unknown argument")
      nil
    else
      encode_fn =
        case selector.function_type do
          :constructor ->
            quote do
              def unquote(encode_fun_name)(unquote_splicing(encode_arguments)) do
                bytecode() <> ABI.encode(unquote(abi), [{unquote_splicing(encode_values)}])
              end
            end

          x when x in [:fallback, :receive] ->
            quote do
              def unquote(encode_fun_name)(unquote_splicing(encode_arguments)) do
                (unquote_splicing(encode_arguments))
              end
            end

          :event ->
            quote do
              def unquote(encode_event_fun_name)(unquote_splicing(encode_arguments)) do
                ABI.encode(unquote(event_selector_fun_name)(), unquote(encode_values))
              end
            end

          _ ->
            quote do
              def unquote(encode_fun_name)(unquote_splicing(encode_arguments)) do
                ABI.encode(unquote(selector_fun_name)(), unquote(encode_values))
              end
            end
        end

      prepare_fn =
        case selector.function_type do
          :constructor ->
            quote do
              def unquote(prepare_fun_name)(
                    unquote_splicing(execute_arguments),
                    opts \\ []
                  ) do
                Signet.RPC.prepare_trx(
                  <<0::256>>,
                  unquote(encode_fun_name)(unquote_splicing(execute_values)),
                  opts
                )
              end
            end

          _ ->
            quote do
              def unquote(prepare_fun_name)(
                    contract,
                    unquote_splicing(execute_arguments),
                    opts \\ []
                  ) do
                Signet.RPC.prepare_trx(
                  contract,
                  unquote(encode_fun_name)(unquote_splicing(execute_values)),
                  opts
                )
              end
            end
        end

      build_trx_fn =
        quote do
          def unquote(build_trx_fun_name)(contract, unquote_splicing(execute_arguments)) do
            %Signet.Transaction.V2{
              destination: contract,
              data: unquote(encode_fun_name)(unquote_splicing(execute_values))
            }
          end
        end

      call_fn =
        quote do
          def unquote(call_fun_name)(contract, unquote_splicing(execute_arguments), opts \\ []) do
            Signet.RPC.call_trx(
              unquote(build_trx_fun_name)(contract, unquote_splicing(execute_values)),
              opts
            )
          end
        end

      estimate_gas_fn =
        quote do
          def unquote(estimate_gas_fun_name)(
                contract,
                unquote_splicing(execute_arguments),
                opts \\ []
              ) do
            Signet.RPC.estimate_gas(
              unquote(build_trx_fun_name)(contract, unquote_splicing(execute_values)),
              opts
            )
          end
        end

      execute_fn =
        case selector.function_type do
          :constructor ->
            quote do
              def unquote(execute_fun_name)(unquote_splicing(execute_arguments), opts \\ []) do
                Signet.RPC.execute_trx(
                  <<0::256>>,
                  unquote(encode_fun_name)(unquote_splicing(execute_values)),
                  opts
                )
              end
            end

          _ ->
            quote do
              def unquote(execute_fun_name)(
                    contract,
                    unquote_splicing(execute_arguments),
                    opts \\ []
                  ) do
                Signet.RPC.execute_trx(
                  contract,
                  unquote(encode_fun_name)(unquote_splicing(execute_values)),
                  opts
                )
              end
            end
        end

      exec_vm_fn =
        quote do
          def unquote(exec_vm_fun_name)(
                unquote_splicing(execute_arguments),
                callvalue \\ 0
              ) do
            Signet.VM.exec_call(
              deployed_bytecode(),
              unquote(encode_fun_name)(unquote_splicing(execute_values)),
              callvalue
            )
          end
        end

      selector_fn =
        quote do
          def unquote(selector_fun_name)() do
            unquote(Macro.escape(selector))
          end
        end

      event_selector_fn =
        quote do
          def unquote(event_selector_fun_name)() do
            unquote(Macro.escape(event_selector))
          end
        end

      decode_event_fn =
        quote do
          def unquote(decode_event_fun_name)(topics, data) when is_list(topics) do
            ABI.Event.decode_event(data, topics, unquote(event_selector_fun_name)())
          end
        end

      decode_call_fn =
        quote do
          def unquote(decode_call_fun_name)(
                <<unquote_splicing(abi_enc_signature_list)>> <> calldata
              ) do
            ABI.decode(unquote(selector_fun_name)(), calldata)
          end
        end

      decode_error_fn =
        quote do
          def unquote(decode_error_fun_name)(
                <<unquote_splicing(abi_enc_signature_list)>> <> error
              ) do
            ABI.decode(unquote(selector_fun_name)(), error)
          end
        end

      generic_decode_call_fn =
        quote do
          def decode_call(calldata = <<unquote_splicing(abi_enc_signature_list)>> <> _) do
            {:ok, unquote(error_name), unquote(decode_call_fun_name)(calldata)}
          end
        end

      generic_error_fn =
        quote do
          def decode_error(error = <<unquote_splicing(abi_enc_signature_list)>> <> _) do
            {:ok, unquote(error_name), unquote(decode_error_fun_name)(error)}
          end
        end

      generic_event_fn =
        quote do
          def decode_event(topics = [<<unquote_splicing(signature_list)>> | _], data) do
            unquote(decode_event_fun_name)(topics, data)
          end
        end

      case {selector.function_type, selector.state_mutability} do
        {:error, _} ->
          {[selector_fn, encode_fn, decode_error_fn], nil, nil, generic_error_fn}

        {:event, _} ->
          {[event_selector_fn, encode_fn, decode_event_fn], nil, generic_event_fn, nil}

        {x, _} when x in [:constructor, :fallback, :receive] ->
          {[encode_fn, prepare_fn, execute_fn], nil, nil, nil}

        {_, :pure} ->
          {[
             selector_fn,
             encode_fn,
             prepare_fn,
             build_trx_fn,
             call_fn,
             estimate_gas_fn,
             execute_fn,
             decode_call_fn,
             exec_vm_fn
           ], generic_decode_call_fn, nil, nil}

        _ ->
          {[
             selector_fn,
             encode_fn,
             prepare_fn,
             build_trx_fn,
             call_fn,
             estimate_gas_fn,
             execute_fn,
             decode_call_fn
           ], generic_decode_call_fn, nil, nil}
      end
    end
  end

  # Generate the bytecode function
  # Note: I wanted to use ~h[] syntax, but generating that was being weird.
  defp get_bytecode(abi) do
    case abi["bytecode"] do
      %{"object" => bytecode} ->
        [
          quote do
            def bytecode(), do: hex!(unquote(bytecode))
          end
        ]

      _ ->
        []
    end
  end

  # Generate the deployed bytecode function
  defp get_deployed_bytecode(abi) do
    case abi["deployedBytecode"] do
      %{"object" => bytecode} ->
        [
          quote do
            def deployed_bytecode(), do: hex!(unquote(bytecode))
          end
        ]

      _ ->
        []
    end
  end

  # The crux of it. Builds the entire module with function declarations, etc
  # based on the output-json "abi" of a given Solidity contract.
  defp build_module(prefix, out, abi_map) do
    contract_name = get_contract_name_by_metadata(abi_map) || get_contract_name_by_ast(abi_map)
    if is_nil(contract_name), do: raise("did not find contract name")

    prefix_parts =
      prefix
      |> String.split("/")
      |> Enum.filter(fn x -> String.length(x) > 0 end)

    prefix_mod = Enum.map(prefix_parts, &Macro.camelize/1)

    module_name =
      String.to_atom(Enum.join(List.flatten(["Elixir", prefix_mod, contract_name]), "."))

    file_name =
      Path.join(
        List.flatten([
          out,
          prefix_parts,
          "#{Macro.underscore(contract_name)}.ex"
        ])
      )

    bytecode_decl = get_bytecode(abi_map)
    deployed_bytecode_decl = get_deployed_bytecode(abi_map)
    encode_call_decl = get_encode_calls(abi_map, Enum.count(bytecode_decl) > 0)

    contents =
      quote do
        defmodule unquote(module_name) do
          @moduledoc ~S"""
          This module was auto-generated by Signet. Any changes may be lost.

          See `mix help signet.gen` for more information.
          """
          use Signet.Hex

          def contract_name, do: unquote(contract_name)

          unquote_splicing(encode_call_decl)
          unquote_splicing(bytecode_decl)
          unquote_splicing(deployed_bytecode_decl)
        end
      end
      |> Macro.to_string()

    {file_name, contents}
  end

  # Gets the output-json of all included Solidity files to auto-generate.
  defp get_json_out(patterns) do
    patterns
    |> Enum.map(fn pattern -> Path.wildcard(pattern) end)
    |> List.flatten()
    |> Enum.map(fn filename -> {filename, File.read!(filename)} end)
    |> Enum.map(fn {filename, contents} -> {filename, Jason.decode!(contents)} end)
    |> Enum.map(fn {filename, contents} ->
      cond do
        is_map(contents) and Map.has_key?(contents, "abi") ->
          # Normal Soidity output
          contents

        is_list(contents) ->
          # Just an ABI, convert to Solidity
          %{
            "abi" => contents,
            "metadata" => %{
              "settings" => %{
                "compilationTarget" => %{
                  filename => Macro.camelize(Path.basename(filename, ".json"))
                }
              }
            }
          }

        true ->
          raise InvalidFileError, "Invalid Solidity output or ABI in `#{filename}`"
      end
    end)
  end

  @doc false
  def run(args) do
    case OptionParser.parse(args, strict: [prefix: :string, out: :string]) do
      {opts, patterns = [_ | _], []} ->
        prefix = Keyword.get(opts, :prefix, "")
        out = Keyword.get(opts, :out, "lib/")

        patterns
        |> get_json_out()
        |> Enum.map(fn abi_map -> build_module(prefix, out, abi_map) end)
        |> Enum.each(fn {path, contents} ->
          File.mkdir_p!(Path.dirname(path))
          File.write!(path, Code.format_string!(contents) ++ "\n")
          Logger.info("Generated #{path}")
        end)

      _ ->
        raise "usage: mix signet.gen --prefix [prefix] --out [out=lib/] [patterns]"
    end
  end
end
