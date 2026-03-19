if Code.ensure_loaded?(GoogleApi.CloudKMS.V1.Api.Projects) do
  defmodule Signet.Solana.Signer.CloudKMS do
    @moduledoc """
    Ed25519 signing backend using Google Cloud KMS.

    GCP KMS supports Ed25519 signing (algorithm `EC_SIGN_ED25519`) since
    April 2024. This is the Solana equivalent of `Signet.Signer.CloudKMS`
    for Ethereum.

    Key differences from the Ethereum KMS signer:
    - Uses `data` field (raw bytes) instead of `digest.sha256` (pre-hashed)
    - PEM contains Ed25519 SubjectPublicKeyInfo (RFC 8410), not an EC point
    - Signature is raw 64 bytes, not DER-encoded

    Requires the `google_api_cloud_kms` optional dependency.
    """

    alias GoogleApi.CloudKMS.V1.Api.Projects, as: CloudKMSApi

    # Ed25519 SubjectPublicKeyInfo DER prefix (12 bytes):
    # SEQUENCE { SEQUENCE { OID 1.3.101.112 (id-Ed25519) } BIT STRING ... }
    @ed25519_der_prefix <<0x30, 0x2A, 0x30, 0x05, 0x06, 0x03, 0x2B, 0x65, 0x70, 0x03, 0x21, 0x00>>

    @doc """
    Get the Ed25519 public key (32 bytes) from a KMS key version.
    """
    @spec get_address(term(), String.t(), String.t(), String.t(), String.t(), String.t()) ::
            {:ok, <<_::256>>} | {:error, term()}
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
          "EC_SIGN_ED25519" ->
            extract_ed25519_pubkey(pem)

          _ ->
            {:error, "Expected EC_SIGN_ED25519 algorithm, got: #{algorithm}"}
        end
      end
    end

    @doc """
    Sign message bytes using a KMS Ed25519 key.

    Ed25519 signs raw message bytes (no external hashing). The message is
    sent to KMS via the `data` field (not `digest`).

    Returns `{:ok, signature}` where signature is exactly 64 bytes.
    """
    @spec sign(binary(), term(), String.t(), String.t(), String.t(), String.t(), String.t()) ::
            {:ok, <<_::512>>} | {:error, term()}
    def sign(message, cred, project, location, keychain, key, version)
        when is_binary(message) do
      message_enc = Base.encode64(message)

      with {:ok, response} <-
             CloudKMSApi.cloudkms_projects_locations_key_rings_crypto_keys_crypto_key_versions_asymmetric_sign(
               client(cred),
               project,
               location,
               keychain,
               key,
               version,
               body: %{
                 data: message_enc
               }
             ),
           {:ok, <<signature::binary-64>>} <- Base.decode64(response.signature) do
        {:ok, signature}
      end
    end

    defp extract_ed25519_pubkey(pem) do
      [pem_entry] = :public_key.pem_decode(pem)
      {_type, der_bytes, _} = pem_entry

      case der_bytes do
        <<@ed25519_der_prefix, public_key::binary-32>> ->
          {:ok, public_key}

        _ ->
          {:error, "Unexpected DER format for Ed25519 public key"}
      end
    end

    defp client(token) when is_binary(token), do: GoogleApi.CloudKMS.V1.Connection.new(token)

    defp client(cred) do
      %{token: token, type: "Bearer"} = Goth.fetch!(cred)
      GoogleApi.CloudKMS.V1.Connection.new(token)
    end
  end
end
