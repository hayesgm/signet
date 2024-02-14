## v1.0.0-alpha6

- Adjust return value of RPC call [BREAKING]

## v1.0.0-alpha5

- Add `trace_call` Support (1.0.0-alpha5)

## v1.0.0-alpha4

- This patch accepts `chain_id` as an input option to `prepare_trx` instead of using the default chain_id for the signer. This is as we move to a better version of multi-chain world.

## v1.0.0-alpha3

- Bump ABI dep

## v1.0.0-alpha2

- Bump ABI dep

## v1.0.0-alpha1

- Support EIP-1559 transactions

## v0.1.10

- Add simple auto-publish mechanism

## v0.1.9

- Add EIP-155 signature helpers
- Logo and readme improvements

## v0.1.8

- Support non-EIP-155 signature recovery

## v0.1.7

- Move support libs to conditional compilation
- Add estimate gas price support

## v0.1.6

- Make CloudKMS truly optional

## v0.1.5

- Add build-in Solidity error decoding, fix warnings, bump to 0.1.5

## 0.1.4

- Memoize versus preload address for signers

## 0.1.3

- Add RPC option for timeout, increase default to 30s

## 0.1.2

- Include a built-in Erc20 contract implementation
- Allow 0 to specify not including an EIP-155 signature
- Add a simple contract address translation function

## 0.1.1

- Add Ethereum Keypair Generation

## 0.1.0

- Initial version
