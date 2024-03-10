if Code.ensure_loaded?(GoogleApi.CloudKMS.V1.Api.Projects) do
  defmodule Signet.Signer.CloudKMS do
    @moduledoc """
    Signer to sign messages from a Google Cloud KMS key.
    """
    import Signet.Hash, only: [keccak: 1]

    alias GoogleApi.CloudKMS.V1.Api.Projects, as: CloudKMSApi

    @doc ~S"""
    Get the Ethereum address associated with the given KMS key version.

    ## Examples

        iex> {:ok, address} = Signet.Signer.CloudKMS.get_address("token", "project", "location", "keychain", "key", "version")
        iex> Signet.Hex.to_hex(address)
        "0xdda641b2a76a4a7c3617815bb13281dd207b74d5"
    """
    @spec get_address(term(), String.t(), String.t(), String.t(), String.t(), String.t()) ::
            {:ok, binary()} | {:error, String.t()}
    def get_address(cred, project, location, keychain, key, version) do
      with {:ok, %GoogleApi.CloudKMS.V1.Model.PublicKey{algorithm: algorithm, pem: pem}} <-
             CloudKMSApi.cloudkms_projects_locations_key_rings_crypto_keys_crypto_key_versions_get_public_key(
               client(cred),
               project,
               location,
               keychain,
               key,
               version
             ) do
        case algorithm do
          "EC_SIGN_SECP256K1_SHA256" ->
            [certs] = :public_key.pem_decode(pem)
            {{:ECPoint, public_key}, _} = :public_key.pem_entry_decode(certs)
            {:ok, Signet.Util.get_eth_address(public_key)}

          _ ->
            {:error, "Invalid algorithm: #{algorithm}"}
        end
      end
    end

    @doc ~S"""
    Signs a message with the given KMS key version, after digesting the message with keccak.

    ## Examples

        iex> use Signet.Hex
        iex> {:ok, sig} = Signet.Signer.CloudKMS.sign("test", "token", "project", "location", "keychain", "key", "version")
        iex> {:ok, recid} = Signet.Recover.find_recid("test", sig, ~h[0xDDA641B2A76A4A7C3617815BB13281DD207B74D5])
        iex> Signet.Recover.recover_eth("test", %{sig|recid: recid}) |> Hex.to_address()
        "0xDDa641B2A76a4A7c3617815bb13281DD207b74d5"
    """
    @spec sign(String.t(), term(), String.t(), String.t(), String.t(), String.t(), String.t()) ::
            {:ok, Curvy.Signature.t()} | {:error, String.t()}
    def sign(message, cred, project, location, keychain, key, version) when is_binary(message) do
      message_hash_enc =
        message
        |> keccak()
        |> Base.encode64()

      with {:ok, response} <-
             CloudKMSApi.cloudkms_projects_locations_key_rings_crypto_keys_crypto_key_versions_asymmetric_sign(
               client(cred),
               project,
               location,
               keychain,
               key,
               version,
               body: %{
                 digest: %{
                   sha256: message_hash_enc
                 }
               }
             ),
           {:ok, decoded_sig} <- Base.decode64(response.signature) do
        {:ok, Curvy.Signature.parse(decoded_sig)}
      end
    end

    defp client(token) when is_binary(token), do: GoogleApi.CloudKMS.V1.Connection.new(token)

    defp client(cred) do
      %{token: token, type: "Bearer"} = Goth.fetch!(cred)
      GoogleApi.CloudKMS.V1.Connection.new(token)
    end
  end
end
