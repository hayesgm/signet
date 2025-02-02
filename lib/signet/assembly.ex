defmodule Signet.Assembly do
  @moduledoc ~S"""
  A for-fun assembler of EVM assembly code from a simple
  lisp-like language used to construct Quark scripts.

  This is really for fun and testing, so mostly feel free
  to ignore.

  ## Usage

  You can build EVM assembly, via:

  ```elixir
  Signet.Assembly.build([
    {:log1, 0, 0, 55}
  ])
  ```

  That results in the EVM compiled script `0x603760006000a1`.

  If you view that here https://ethervm.io/decompile you see
  that it decompiles to:

  ```c
  log(memory[0x00:0x00], [0x37]);
  ```

  via the assembly:

  ```asm
  0000    60  PUSH1 0x37
  0002    60  PUSH1 0x00
  0004    60  PUSH1 0x00
  0006    A1  LOG1
  ```

  Overall, scripts can get more complex, e.g. we use a script
  to revert if `tx.origin` is zero (e.g. during an `eth_estimateGas`).

  ```elixir
  Signet.Assembly.build([
    {:mstore, 0, 0x01020304},
    {:if, :origin, {:revert, 28, 4}, {:return, 0, 0}}
  ])
  ```

  There's no real goal for this assembler. Just a fun experiment and
  useful in testing.
  """

  use Signet.Hex

  @type opcode :: {atom(), integer(), integer()}

  @opcodes %{
    stop: {<<0x00>>, 0, 0},
    add: {<<0x01>>, 2, 1},
    mul: {<<0x02>>, 2, 1},
    sub: {<<0x03>>, 2, 1},
    div: {<<0x04>>, 2, 1},
    sdiv: {<<0x05>>, 2, 1},
    mod: {<<0x06>>, 2, 1},
    smod: {<<0x07>>, 2, 1},
    addmod: {<<0x08>>, 3, 1},
    mulmod: {<<0x09>>, 3, 1},
    exp: {<<0x0A>>, 2, 1},
    signextend: {<<0x0B>>, 2, 1},
    lt: {<<0x10>>, 2, 1},
    gt: {<<0x11>>, 2, 1},
    slt: {<<0x12>>, 2, 1},
    sgt: {<<0x13>>, 2, 1},
    eq: {<<0x14>>, 2, 1},
    iszero: {<<0x15>>, 1, 1},
    and: {<<0x16>>, 2, 1},
    or: {<<0x17>>, 2, 1},
    xor: {<<0x18>>, 2, 1},
    not: {<<0x19>>, 1, 1},
    byte: {<<0x1A>>, 2, 1},
    shl: {<<0x1B>>, 2, 1},
    shr: {<<0x1C>>, 2, 1},
    sar: {<<0x1D>>, 2, 1},
    sha3: {<<0x20>>, 2, 1},
    address: {<<0x30>>, 0, 1},
    balance: {<<0x31>>, 1, 1},
    origin: {<<0x32>>, 0, 1},
    caller: {<<0x33>>, 0, 1},
    callvalue: {<<0x34>>, 0, 1},
    calldataload: {<<0x35>>, 1, 1},
    calldatasize: {<<0x36>>, 0, 1},
    calldatacopy: {<<0x37>>, 3, 0},
    codesize: {<<0x38>>, 0, 1},
    codecopy: {<<0x39>>, 3, 0},
    gasprice: {<<0x3A>>, 0, 1},
    extcodesize: {<<0x3B>>, 1, 1},
    extcodecopy: {<<0x3C>>, 4, 0},
    returndatasize: {<<0x3D>>, 0, 1},
    returndatacopy: {<<0x3E>>, 3, 0},
    extcodehash: {<<0x3F>>, 1, 1},
    blockhash: {<<0x40>>, 1, 1},
    coinbase: {<<0x41>>, 0, 1},
    timestamp: {<<0x42>>, 0, 1},
    number: {<<0x43>>, 0, 1},
    prevrandao: {<<0x44>>, 0, 1},
    gaslimit: {<<0x45>>, 0, 1},
    chainid: {<<0x46>>, 0, 1},
    selfbalance: {<<0x47>>, 0, 1},
    basefee: {<<0x48>>, 0, 1},
    pop: {<<0x50>>, 1, 0},
    mload: {<<0x51>>, 1, 1},
    mstore: {<<0x52>>, 2, 0},
    mstore8: {<<0x53>>, 2, 0},
    sload: {<<0x54>>, 1, 1},
    sstore: {<<0x55>>, 2, 0},
    jump: {<<0x56>>, 1, 0},
    jumpi: {<<0x57>>, 2, 0},
    pc: {<<0x58>>, 0, 1},
    msize: {<<0x59>>, 0, 1},
    gas: {<<0x5A>>, 0, 1},
    jumpdest: {<<0x5B>>, 0, 0},
    tload: {<<0x5C>>, 1, 1},
    tstore: {<<0x5D>>, 2, 0},
    mcopy: {<<0x5E>>, 3, 0},
    # push 0x5f-7f
    # dup 0x80-8f
    # swap 0x90-9f
    log0: {<<0xA0>>, 2, 0},
    log1: {<<0xA1>>, 3, 0},
    log2: {<<0xA2>>, 4, 0},
    log3: {<<0xA3>>, 5, 0},
    log4: {<<0xA4>>, 6, 0},
    create: {<<0xF0>>, 3, 1},
    call: {<<0xF1>>, 7, 1},
    callcode: {<<0xF2>>, 7, 1},
    return: {<<0xF3>>, 2, 0},
    delegatecall: {<<0xF4>>, 6, 1},
    create2: {<<0xF5>>, 4, 1},
    staticcall: {<<0xFA>>, 6, 1},
    revert: {<<0xFD>>, 2, 0},
    # invalid: {<<0xFE>>, 0, 0},
    selfdestruct: {<<0xFF>>, 1, 0}
  }

  @opcodes_with_operand_count fn x ->
    @opcodes
    |> Enum.filter(fn {_opcode, {_, ins, _outs}} -> ins == x end)
    |> Enum.map(fn {opcode, _} -> opcode end)
  end

  @opcodes_by_code @opcodes
                   |> Enum.map(fn {opcode, {code, _, _}} -> {code, opcode} end)
                   |> Enum.into(%{})

  @opcodes_codes Enum.map(@opcodes, fn {_, {code, _, _}} -> code end)

  @no_operands @opcodes_with_operand_count.(0)
  @one_operand @opcodes_with_operand_count.(1)
  @two_operands @opcodes_with_operand_count.(2)
  @three_operands @opcodes_with_operand_count.(3)
  @four_operands @opcodes_with_operand_count.(4)
  @five_operands @opcodes_with_operand_count.(5)
  @six_operands @opcodes_with_operand_count.(6)
  @seven_operands @opcodes_with_operand_count.(7)

  @opcode_keys Map.keys(@opcodes)
  # not sure how to otherwise figure this out
  @jump_sz 3

  defmodule InvalidAssembly do
    defexception message: "invalid assembly"
  end

  defmodule InvalidCode do
    defexception message: "invalid code"
  end

  defmodule InvalidOpcode do
    defexception message: "invalid opcode"
  end

  def compile({opcode, a}) when opcode in @one_operand do
    List.flatten([compile(a), opcode])
  end

  def compile({opcode, a, b}) when opcode in @two_operands do
    List.flatten([compile(b), compile(a), opcode])
  end

  def compile({opcode, a, b, c}) when opcode in @three_operands do
    List.flatten([compile(c), compile(b), compile(a), opcode])
  end

  def compile({opcode, a, b, c, d}) when opcode in @four_operands do
    List.flatten([compile(d), compile(c), compile(b), compile(a), opcode])
  end

  def compile({opcode, a, b, c, d, e}) when opcode in @five_operands do
    List.flatten([compile(e), compile(d), compile(c), compile(b), compile(a), opcode])
  end

  def compile({opcode, a, b, c, d, e, f}) when opcode in @six_operands do
    List.flatten([compile(f), compile(e), compile(d), compile(c), compile(b), compile(a), opcode])
  end

  def compile({opcode, a, b, c, d, e, f, g}) when opcode in @seven_operands do
    List.flatten([
      compile(g),
      compile(f),
      compile(e),
      compile(d),
      compile(c),
      compile(b),
      compile(a),
      opcode
    ])
  end

  def compile({:if, cond, non_zero, zero}) do
    i = :erlang.unique_integer()

    List.flatten([
      compile(cond),
      {:jump_ptr, i},
      :jumpi,
      compile(zero),
      {:jump_dest, i},
      compile(non_zero)
    ])
  end

  def compile(b) when is_binary(b) do
    if byte_size(b) <= 32 do
      [{:push, byte_size(b), b}]
    else
      raise InvalidAssembly, message: "binary value larger than 32-bytes `#{compile(b)}`"
    end
  end

  def compile(x) when is_integer(x) do
    if false && x == 0 do
      compile(<<>>)
    else
      compile(:binary.encode_unsigned(x))
    end
  end

  def compile(opcode) when opcode in @no_operands, do: opcode

  def compile(:self_code_sz), do: :self_code_sz

  def compile(els) when not is_list(els),
    do: raise(InvalidAssembly, message: "invalid or unknown assembly: #{inspect(els)}")

  @doc """
  Compiles operations into assembly, which can then be compiled.

  ## Examples

      iex> use Signet.Hex
      ...> [
      ...>   {:mstore, 0, ~h[0x11223344]},
      ...>   {:revert, 4, 28}
      ...> ]
      ...> |> Signet.Assembly.compile()
      [{:push, 4, ~h[0x11223344]}, {:push, 1, <<0>>}, :mstore, {:push, 1, <<28>>}, {:push, 1, <<0x04>>}, :revert]
  """
  def compile(operations) when is_list(operations) do
    Enum.flat_map(operations, &compile/1)
  end

  def assemble_opcode({:push, n, v}) when byte_size(v) == n, do: <<0x5F + n>> <> v
  def assemble_opcode({:dup, n}), do: <<0x7F + n>>
  def assemble_opcode({:swap, n}), do: <<0x8F + n>>
  def assemble_opcode({:invalid, data}), do: <<0xFE>> <> data

  def assemble_opcode(opcode) do
    {bin, _, _} = Map.fetch!(@opcodes, opcode)
    bin
  end

  def disassemble_opcode(op = <<x::integer-size(8)>> <> rest) when x >= 0x5F and x < 0x80 do
    n = x - 0x5F

    if byte_size(rest) < n do
      raise InvalidCode, message: "unsufficient data for push#{n}: `#{to_hex(op)}`"
    else
      <<v::binary-size(n), rest::binary>> = rest
      {{:push, n, v}, rest}
    end
  end

  def disassemble_opcode(<<x::integer-size(8)>> <> rest) when x >= 0x80 and x <= 0x8F do
    {{:dup, x - 0x7F}, rest}
  end

  def disassemble_opcode(<<x::integer-size(8)>> <> rest) when x >= 0x90 and x <= 0x9F do
    {{:swap, x - 0x8F}, rest}
  end

  def disassemble_opcode(<<0xFE>> <> rest) do
    {{:invalid, rest}, <<>>}
  end

  def disassemble_opcode(<<x::binary-size(1), rest::binary>>) when x in @opcodes_codes do
    {Map.fetch!(@opcodes_by_code, x), rest}
  end

  def opcode_size({:push, n, _v}), do: n + 1
  def opcode_size({:jump_ptr, _}), do: opcode_size({:push, @jump_sz, <<0, 0, 0>>})
  def opcode_size(:self_code_sz), do: opcode_size({:push, @jump_sz, <<0, 0, 0>>})
  def opcode_size({:jump_dest, _}), do: opcode_size(:jumpdest)
  def opcode_size({:dup, _}), do: 1
  def opcode_size({:swap, _}), do: 1
  def opcode_size({:invalid, data}), do: 1 + byte_size(data)
  def opcode_size(opcode) when opcode in @opcode_keys, do: 1

  def transform_jumps(opcodes) do
    {end_pc, jump_map} =
      Enum.reduce(opcodes, {0, %{}}, fn opcode, {pc, acc_jump_map} ->
        next_jump_map =
          case opcode do
            {:jump_dest, i} ->
              Map.put(acc_jump_map, i, pc)

            _ ->
              acc_jump_map
          end

        {pc + opcode_size(opcode), next_jump_map}
      end)

    Enum.map(opcodes, fn opcode ->
      case opcode do
        {:jump_ptr, i} ->
          case Map.fetch(jump_map, i) do
            {:ok, pc} ->
              {:push, @jump_sz, pad_to(:binary.encode_unsigned(pc), @jump_sz)}

            _ ->
              raise InvalidOpcode, message: "could not find jump dest: `#{i}`"
          end

        {:jump_dest, _} ->
          :jumpdest

        :self_code_sz ->
          {:push, @jump_sz, pad_to(:binary.encode_unsigned(end_pc), @jump_sz)}

        _ ->
          opcode
      end
    end)
  end

  @doc """
  Assmbles opcodes into raw evm bytecode

  ## Examples

      iex> [{:push, 0, ""}, {:push, 4, <<0x11, 0x22, 0x33, 0x44>>}, :mstore, {:push, 1, <<4>>}, {:push, 1, <<28>>}, :revert]
      ...> |> Signet.Assembly.assemble()
      <<95, 99, 17, 34, 51, 68, 82, 96, 4, 96, 28, 253>>

      iex> [
      ...>   {:push, 2, <<0x01, 0x02>>},
      ...>   {:push, 1, <<0>>},
      ...>   :mstore,
      ...>   :callvalue,
      ...>   {:push, 1, <<0>>},
      ...>   :sub,
      ...>   {:jump_ptr, 0},
      ...>   :jumpi,
      ...>   {:push, 1, <<2>>},
      ...>   {:push, 1, <<30>>},
      ...>   :revert,
      ...>   {:jump_dest, 0},
      ...>   {:push, 1, <<2>>},
      ...>   {:push, 1, <<31>>},
      ...>   :revert
      ...> ]
      ...> |> Signet.Assembly.assemble()
      ...> |> Signet.Hex.to_hex()
      "0x6101026000523460000362000014576002601efd5b6002601ffd"

      iex> [
      ...>   {:dup, 2},
      ...>   {:swap, 3},
      ...>   {:invalid, ~h[0x010203]}
      ...> ]
      ...> |> Signet.Assembly.assemble()
      ...> |> Signet.Hex.to_hex()
      "0x8192fe010203"
  """
  def assemble(opcodes) when is_list(opcodes) do
    # We're now going to do multiple passes
    # First, we assign pcs to all jump_dests
    # Then we transform jump pts to jump_dests
    # Finally, we'll encode the instructions.
    opcodes
    |> transform_jumps()
    |> Enum.map(&assemble_opcode/1)
    |> Enum.join()
  end

  @doc """
  Disassembles opcodes from raw evm bytecode to opcodes.

  ## Examples

      iex> Signet.Assembly.disassemble(~h[0x6101026000523460000362000014576002601efd5b6002601ffd])
      [
        {:push, 2, <<0x01, 0x02>>},
        {:push, 1, <<0>>},
        :mstore,
        :callvalue,
        {:push, 1, <<0>>},
        :sub,
        {:push, 3, <<0, 0, 20>>},
        :jumpi,
        {:push, 1, <<2>>},
        {:push, 1, <<30>>},
        :revert,
        :jumpdest,
        {:push, 1, <<2>>},
        {:push, 1, <<31>>},
        :revert
      ]
      
      iex> Signet.Assembly.disassemble(~h[0x8192fe010203])
      [
        {:dup, 2},
        {:swap, 3},
        {:invalid, ~h[0x010203]}
      ]
  """
  def disassemble(bytes) when is_binary(bytes) do
    disassemble_(bytes, [])
  end

  defp disassemble_(bytes, acc) do
    if bytes == <<>> do
      Enum.reverse(acc)
    else
      {opcode, rest} = disassemble_opcode(bytes)
      disassemble_(rest, [opcode | acc])
    end
  end

  @doc """
  Compiles and assembles assembly operations.

  ## Examples

      iex> use Signet.Hex
      ...> [
      ...>   {:mstore, 0, ~h[0x11223344]},
      ...>   {:revert, 28, 4}
      ...> ]
      ...> |> Signet.Assembly.build()
      ...> |> to_hex()
      "0x63112233446000526004601cfd"
  """
  def build(operations) do
    operations
    |> compile()
    |> assemble()
  end

  defp pad_to(x, target_sz) do
    pad_sz = target_sz - byte_size(x)

    if pad_sz >= 0 do
      <<0::pad_sz*8, x::binary>>
    else
      raise "jump too large"
    end
  end

  @doc """
  Returns a simple EVM program that returns the input code
  as the output of an Ethereum "initCode" constructor.

  ## Examples

      iex> use Signet.Hex
      ...> Signet.Assembly.constructor(~h[0xaabbcc])
      ...> |> to_hex()
      "0x60036200000e60003960036000f3aabbcc"
  """
  def constructor(code),
    do:
      build([
        {:codecopy, 0x00, :self_code_sz, byte_size(code)},
        {:return, 0x00, byte_size(code)}
      ]) <> code

  @doc """
  Returns a textual representation of the given operation.

  ## Examples

      iex> Signet.Assembly.show_opcode(:add)
      "ADD"

      iex> Signet.Assembly.show_opcode({:push, 5, <<1,2,3,4,5>>})
      "PUSH5 0x0102030405"
  """
  def show_opcode(op) do
    case op do
      :stop ->
        "STOP"

      :add ->
        "ADD"

      :sub ->
        "SUB"

      :mul ->
        "MUL"

      :div ->
        "DIV"

      :sdiv ->
        "SDIV"

      :mod ->
        "MOD"

      :smod ->
        "SMOD"

      :addmod ->
        "ADDMOD"

      :mulmod ->
        "MULMOD"

      :exp ->
        "EXP"

      :signextend ->
        "SIGNEXTEND"

      :lt ->
        "LT"

      :gt ->
        "GT"

      :slt ->
        "SLT"

      :sgt ->
        "SGT"

      :eq ->
        "EQ"

      :iszero ->
        "ISZERO"

      :and ->
        "AND"

      :or ->
        "OR"

      :xor ->
        "XOR"

      :not ->
        "NOT"

      :byte ->
        "BYTE"

      :shl ->
        "SHL"

      :shr ->
        "SHR"

      :sar ->
        "SAR"

      :sha3 ->
        "SHA3"

      :callvalue ->
        "CALLVALUE"

      :calldataload ->
        "CALLDATALOAD"

      :calldatasize ->
        "CALLDATASIZE"

      :calldatacopy ->
        "CALLDATACOPY"

      :codesize ->
        "CODESIZE"

      :codecopy ->
        "CODECOPY"

      :pop ->
        "POP"

      :mload ->
        "MLOAD"

      :mstore ->
        "MSTORE"

      :mstore8 ->
        "MSTORE8"

      :jump ->
        "JUMP"

      :jumpi ->
        "JUMPI"

      :pc ->
        "PC"

      :msize ->
        "MSIZE"

      :gas ->
        "GAS"

      :jumpdest ->
        "JUMPDEST"

      :tload ->
        "TLOAD"

      :tstore ->
        "TSTORE"

      :mcopy ->
        "MCOPY"

      {:push, n, v} ->
        "PUSH#{n} #{to_hex(v)}"

      {:dup, n} ->
        "DUP#{n}"

      {:swap, n} ->
        "SWAP#{n}"

      :return ->
        "RETURN"

      :revert ->
        "REVERT"

      {:invalid, _} ->
        "INVALID"

      :staticcall ->
        "STATICCALL"

      :returndatasize ->
        "RETURNDATASIZE"

      :returndatacopy ->
        "RETURNDATACOPY"

      :address ->
        "ADDRESS"

      :balance ->
        "BALANCE"

      :origin ->
        "ORIGIN"

      :caller ->
        "CALLER"

      :gasprice ->
        "GASPRICE"

      :extcodesize ->
        "EXTCODESIZE"

      :extcodecopy ->
        "EXTCODECOPY"

      :extcodehash ->
        "EXTCODEHASH"

      :blockhash ->
        "BLOCKHASH"

      :coinbase ->
        "COINBASE"

      :timestamp ->
        "TIMESTAMP"

      :number ->
        "NUMBER"

      :prevrandao ->
        "PREVRANDAO"

      :gaslimit ->
        "GASLIMIT"

      :chainid ->
        "CHAINID"

      :selfbalance ->
        "SELFBALANCE"

      :basefee ->
        "BASEFEE"

      :blobhash ->
        "BLOBHASH"

      :blobbasefee ->
        "BLOBBASEFEE"

      :sload ->
        "SLOAD"

      :sstore ->
        "SSTORE"

      :log ->
        "LOG"

      :create ->
        "CREATE"

      :call ->
        "CALL"

      :callcode ->
        "CALLCODE"

      :delegatecall ->
        "DELEGATECALL"

      :create2 ->
        "CREATE2"

      :selfdestruct ->
        "SELFDESTRUCT"
    end
  end
end
