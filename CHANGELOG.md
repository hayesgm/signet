## v1.0.0-charlie7

- [Improve ABI Event Decoding](https://github.com/hayesgm/signet/pull/56)

## v1.0.0-charlie6

- [Partial EIP-712 Domains](https://github.com/hayesgm/signet/pull/55)

## v1.0.0-charlie5

- [Fix Call Params](https://github.com/hayesgm/signet/pull/52)
- [Add Sleuth Annotations](https://github.com/hayesgm/signet/pull/54)

## v1.0.0-charlie4

- Bump ABI dependency
- [Filter Improvements](https://github.com/hayesgm/signet/pull/51)
- [Fix ABI-only Encoding](https://github.com/hayesgm/signet/pull/50)

## v1.0.0-charlie3

- Make sure Sleuth handles bytes decoding and improve responses

## v1.0.0-charlie2

- Escape macro expands

## v1.0.0-charlie1

- Add Sleuth support
- Fix nilable values in rpc send

## v1.0.0-beta9

-  Add contract codegen code

## v1.0.0-beta8

- Add Signet.Hex to replace Signet.Util's hex libraries

## v1.0.0-beta7

- Improve error handling of RPC calls

## v1.0.0-beta6

- Add `eth_getCode` support

## v1.0.0-beta5

- Add `trace_callMany` support

## v1.0.0-beta4

- Allow custom `id` for RPC calls

## v1.0.0-beta3

- Allow wide EIP-155 signatures

## v1.0.0-beta2

- Support sepolia

## v1.0.0-beta1

- Fix ABI integration

## v1.0.0-alpha10

- Allow nil rewards from `eth_feeHistory`

## v1.0.0-alpha9

- Improve error logging for RPC decoding errors

## v1.0.0-alpha8

- Add Fee History and MaxFeePerGas Endpoints [1.0.0-alpha8] (#34)
  - Add Fee History Endpoint
  - Try to simplify logic even more, don't apply buffer when values are set directly

## v1.0.0-alpha7

- Improve Trace Support [1.0.0-alpha7]

- This patch improves trace support to handle more cases, such as contract creation and reverts. The trace code isn't heavily documented, so we're mostly going off of some real-life examples.

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
