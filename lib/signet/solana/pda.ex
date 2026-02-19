defmodule Signet.Solana.PDA do
  @moduledoc """
  Program Derived Addresses (PDAs) for Solana.

  A PDA is an address derived from seeds and a program ID that is guaranteed
  to NOT be on the Ed25519 curve (no private key can sign for it). Only the
  owning program can "sign" for a PDA via cross-program invocation.

  ## Examples

      iex> {:ok, {address, bump}} = Signet.Solana.PDA.find_program_address(["hello"], <<0::256>>)
      iex> byte_size(address)
      32
      iex> bump >= 0 and bump <= 255
      true
  """

  import Bitwise

  # Ed25519 field prime: 2^255 - 19
  @p (1 <<< 255) - 19

  # Ed25519 curve constant d = -121665/121666 mod p
  @d 37_095_705_934_669_439_343_138_083_508_754_565_189_542_113_879_843_219_016_388_785_533_085_940_283_555

  # (p - 1) / 2 for Euler's criterion
  @euler_exp div(@p - 1, 2)

  @pda_marker "ProgramDerivedAddress"

  @doc """
  Find a program-derived address from seeds and a program ID.

  Tries bump seeds from 255 down to 0, returning the first off-curve result.

  ## Examples

      iex> {:ok, {_address, bump}} = Signet.Solana.PDA.find_program_address(["hello"], <<0::256>>)
      iex> bump >= 0 and bump <= 255
      true
  """
  @spec find_program_address([binary()], <<_::256>>) ::
          {:ok, {<<_::256>>, non_neg_integer()}} | {:error, :no_valid_pda}
  def find_program_address(seeds, <<program_id::binary-32>>) do
    result =
      Enum.reduce_while(255..0//-1, nil, fn bump, _acc ->
        case create_program_address(seeds ++ [<<bump>>], program_id) do
          {:ok, address} -> {:halt, {address, bump}}
          {:error, :on_curve} -> {:cont, nil}
        end
      end)

    case result do
      nil -> {:error, :no_valid_pda}
      found -> {:ok, found}
    end
  end

  @doc """
  Like `find_program_address/2`, but raises on failure.

  ## Examples

      iex> {_address, bump} = Signet.Solana.PDA.find_program_address!(["hello"], <<0::256>>)
      iex> bump >= 0 and bump <= 255
      true
  """
  @spec find_program_address!([binary()], <<_::256>>) :: {<<_::256>>, non_neg_integer()}
  def find_program_address!(seeds, program_id) do
    case find_program_address(seeds, program_id) do
      {:ok, result} -> result
      {:error, :no_valid_pda} -> raise "could not find PDA (all 256 bumps produced on-curve addresses)"
    end
  end

  @doc """
  Create a program address from seeds (including bump) and program ID.

  Returns `{:ok, address}` if the result is off-curve, or `{:error, :on_curve}`
  if the candidate is on the Ed25519 curve.

  This is the single-attempt version where the caller provides the bump seed
  as part of the seeds list.

  ## Examples

      iex> {address, bump} = Signet.Solana.PDA.find_program_address!(["test"], <<0::256>>)
      iex> {:ok, ^address} = Signet.Solana.PDA.create_program_address(["test", <<bump>>], <<0::256>>)
      iex> byte_size(address)
      32
  """
  @spec create_program_address([binary()], <<_::256>>) :: {:ok, <<_::256>>} | {:error, :on_curve}
  def create_program_address(seeds, <<program_id::binary-32>>) do
    hash_input = Enum.reduce(seeds, <<>>, fn seed, acc -> acc <> seed end)
    hash_input = hash_input <> program_id <> @pda_marker

    <<candidate::binary-32>> = :crypto.hash(:sha256, hash_input)

    if on_curve?(candidate) do
      {:error, :on_curve}
    else
      {:ok, candidate}
    end
  end

  @doc """
  Check if 32 bytes represent a valid Ed25519 public key (on the curve).

  Uses Ed25519 compressed point decompression: interprets the bytes as a
  y-coordinate and checks if the corresponding x² is a quadratic residue
  mod p. Uses `:crypto.mod_pow/3` for efficient modular exponentiation.

  ## Examples

      iex> valid_pub = Base.decode16!("D75A980182B10AB7D54BFED3C964073A0EE172F3DAA62325AF021A68F707511A")
      iex> Signet.Solana.PDA.on_curve?(valid_pub)
      true

      iex> Signet.Solana.PDA.on_curve?(<<0::256>>)
      true
  """
  @spec on_curve?(<<_::256>>) :: boolean()
  def on_curve?(<<bytes::binary-32>>) do
    # Decode y-coordinate: little-endian, clear the sign bit (bit 255)
    <<y_raw::little-unsigned-256>> = bytes
    y = y_raw &&& ((1 <<< 255) - 1)

    cond do
      # y must be a valid field element
      y >= @p ->
        false

      # y = 0: u = p-1, v = 1, x² = p-1 which is NOT a QR (so off-curve)
      # Actually let's just compute it uniformly
      true ->
        y2 = mod_pow(y, 2)
        u = rem(y2 - 1 + @p, @p)
        v = rem(@d * y2 + 1, @p)
        v_inv = mod_pow(v, @p - 2)
        x2 = rem(u * v_inv, @p)

        if x2 == 0 do
          true
        else
          # Euler's criterion: x2^((p-1)/2) ≡ 1 mod p means QR (on curve)
          mod_pow(x2, @euler_exp) == 1
        end
    end
  end

  defp mod_pow(base, exp) do
    :crypto.mod_pow(base, exp, @p) |> :binary.decode_unsigned()
  end
end
