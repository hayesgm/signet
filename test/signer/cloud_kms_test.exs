defmodule Signet.Signer.CloudKMSTest do
  use ExUnit.Case, async: true
  doctest Signet.Signer.CloudKMS

  setup do
    Tesla.Mock.mock(fn
      %{
        method: :get,
        url:
          "https://cloudkms.googleapis.com/v1/projects/project/locations/location/keyRings/keychain/cryptoKeys/key/cryptoKeyVersions/version/publicKey"
      } ->
        # https://cloud.google.com/kms/docs/reference/rest/v1/projects.locations.keyRings.cryptoKeys.cryptoKeyVersions/getPublicKey
        # projects/treasury-stage/locations/global/keyRings/treasury-request-signer-6a14c34/cryptoKeys/testkeyyy/cryptoKeyVersions/1
        %Tesla.Env{
          status: 200,
          body:
            Jason.encode!(%{
              pem:
                "-----BEGIN PUBLIC KEY-----\nMFYwEAYHKoZIzj0CAQYFK4EEAAoDQgAEI3tE5EGI0XQZMPwFEiYs4cvq3YHiNSDT\n3/ehihlwUqKAYJajnrlRGhSYdqC+bGekcjnQZxyLlw1xXf/pr+yj3g==\n-----END PUBLIC KEY-----\n",
              algorithm: "EC_SIGN_SECP256K1_SHA256",
              pemCrc32c: "1065940272",
              name:
                "projects/treasury-stage/locations/global/keyRings/treasury-request-signer-6a14c34/cryptoKeys/testkeyyy/cryptoKeyVersions/1",
              protectionLevel: "HSM"
            })
        }

      %{
        method: :post,
        url:
          "https://cloudkms.googleapis.com/v1/projects/project/locations/location/keyRings/keychain/cryptoKeys/key/cryptoKeyVersions/version:asymmetricSign"
      } ->
        # https://cloud.google.com/kms/docs/reference/rest/v1/projects.locations.keyRings.cryptoKeys.cryptoKeyVersions/asymmetricSign
        # projects/treasury-stage/locations/global/keyRings/treasury-request-signer-6a14c34/cryptoKeys/testkeyyy/cryptoKeyVersions/1
        # {"digest": {"sha256":"nCL/XyHwuBsRPmP3222pT+3vEbIRm0CIuJZk+5o8tlg="}}
        %Tesla.Env{
          status: 200,
          body:
            Jason.encode!(%{
              signature:
                "MEQCIGSKMaVlv78Uhc8D+6c9qacz7ISU4rXvH/zhgtaWy++9AiAU2LxgbNAmeYt5KgcgkzchwFsaRZtHTHdruwf5mY8IYQ==",
              signatureCrc32c: "3329027021",
              name:
                "projects/treasury-stage/locations/global/keyRings/treasury-request-signer-6a14c34/cryptoKeys/testkeyyy/cryptoKeyVersions/1",
              protectionLevel: "HSM"
            })
        }
    end)

    :ok
  end
end
