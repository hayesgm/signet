defmodule Signet.VmTestHelpers do
  def word(x, sz \\ nil)

  def word(x, nil) when is_integer(x) and x >= 0 do
    {:ok, res} = Signet.VM.uint_to_word(x)
    res
  end

  def word(x, sz) when is_integer(x) and x >= 0 do
    <<_::binary-size(32 - sz), res::binary-size(sz)>> = word(x)
    res
  end

  def word(x, nil) when is_integer(x) and x < 0 do
    {:ok, res} = Signet.VM.sint_to_word(x)
    res
  end

  def word("0x" <> x, nil) do
    {:ok, res} = Signet.VM.pad_to_word(Signet.Hex.from_hex!(x))
    res
  end

  def word(x, nil) when is_binary(x) do
    {:ok, res} = Signet.VM.pad_to_word(x)
    res
  end
end
