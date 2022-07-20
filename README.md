# Signet 🪧

Signet is a lightweight Ethereum RPC client for Elixir. The goal is to make it easy to interact with Ethereum in Elixir. As an example:

```elixir
{:ok, trx_id} =
  Signet.RPC.execute_trx(
    "0x123...",
    {"transfer(uint)", [50]},
    gas_price: {50, :gwei},
    value: 0
  )
```

The above code will use a signer you set-up (see below) to send a build, sign and transmit a transaction to Infura. Signet handles determining your nonce and estimating the gas cost, and, by default, fails if the transaction were to revert.

Signet has a number of other features, including:

  * Signing and verifying Ethereum signatures (including [EIP-191](https://eips.ethereum.org/EIPS/eip-191))
  * Signing and verifying [EIP-712 typed data](https://eips.ethereum.org/EIPS/eip-712)
  * Signing via [Curvy](https://github.com/libitx/curvy) or [Google KMS](https://cloud.google.com/kms/docs/apis).
    * Note: Curvy signatures should be avoided in production.
  * Filters through active processes

## Installation

Signet can be installed by adding `signet` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:signet, "~> 0.1.0-rc4"}
  ]
end
```

Documentation can be found at <https://hexdocs.pm/signet>.

## Getting Started

### Signers

First, you'll need to set-up a signer, which will be used to sign transactions or other messages. Signers are GenServers, and uou can set-up several signers, and you will specify a name of a signer (or pid) at the point of actually using the signer. Currently there are two supported signers: raw keys or Google KMS.

#### Raw Key

** Note: This uses an experimental Elixir signing library, Curvy, and is considered unsafe for production. **

You can specify a signer key by configuring:

** runtime.exs **

```elixir
config :signet, :signers, %{
  MySigner: {:priv_key, System.get_env("MY_PRIVATE_KEY")}
}
```

Then use `MySigner` when asked for a signer when using Signet.

You can also specify a default signer, which will be used by default so you do not need to specify the signer in your calls:

```elixir
config :signet, :signer, {:priv_key, System.get_env("MY_PRIVATE_KEY")}
```

#### Google KMS

You can set-up Google KMS by configuring:

```elixir
config :signet, :signers, %{
  MySigner: {:cloud_kms, GCPCredentials, "projects/{project}/locations/{location}/keyRings/{keyring}/cryptoKeys/{keyid}", "1"}
}
```

This will use your given key from the URL, version "1", for signing.

`GCPCredentials` should be a `Goth` process set-up with proper credentials to access Google Cloud KMS.

#### Custom Signers

You can also specify custom signers by specifying an mfa that implements the required behavior:

```elixir
config :signet, :signers, %{
  MySigner: {:mfa, Signet.Signer.Curvy, :sign, [<<1::256>>]}
}
```

Feel free to add pull requests with new signing methods.

You can also spawn your own process by adding to your start-up application:

```elixir
children = [
  # ...
  {Signet.Signer, mfa: {...}, chain_id: chain_id, name: MySigner}
]
```

Note: if you do not name your signer, it will be named `Signet.Signer.Default` and will be used to sign all transactions unless otherwise specified.

### Signing

Now that you have a signer, you can sign data, for instance:

```elixir
{:ok, sig} = Signet.Signer.sign("test", MySigner)
```

And then you can recover it via:

```elixir
signer_address = Signet.Recover.recover_eth("test", sig)
```

You can also sign EIP-712 typed data:

```elixir
%Signet.Typed{
  domain: %Signet.Typed.Domain{
    chain_id: 1,
    name: "Ether Mail",
    verifying_contract: Signet.Util.decode_hex!("0xCcCCccccCCCCcCCCCCCcCcCccCcCCCcCcccccccC"),
    version: "1"
  },
  types: %{
    "Mail" => %Signet.Typed.Type{fields: [{"from", "Person"}, {"to", "Person"}, {"contents", :string}]},
    "Person" => %Signet.Typed.Type{fields: [{"name", :string}, {"wallet", :address}]}
  },
  value: %{
    "contents" => "Hello, Bob!",
    "from" => %{
      "name" => "Cow",
      "wallet" => Signet.Util.decode_hex!("0xCD2a3d9F938E13CD947Ec05AbC7FE734Df8DD826")
    },
    "to" => %{
      "name" => "Bob",
      "wallet" => Signet.Util.decode_hex!("0xbBbBBBBbbBBBbbbBbbBbbbbBBbBbbbbBbBbbBBbB")
    }
  }
}
|> Signet.Typed.encode()
|> Signet.Signer.sign()
```

### RPC

Signet includes an RPC library to talk to Ethereum nodes, such as Infura. First, specify an Ethereum node address, e.g.

** config.exs **
```elixir
config :signet, :rpc,
  ethereum_node: "https://goerli.infura.io"
  chain_id: :goerli
```

Then, you can run any Ethereum JSON-RPC command, e.g.:

```elixir
Signet.RPC.send_rpc("net_version", [])
{:ok, "3"}
```

You can build an Ethereum (pre-EIP-1559) transaction, e.g.:

```elixir
transaction = Signet.Transaction.V1.new(1, {100, :gwei}, 100_000, <<1::160>>, {2, :wei}, <<1, 2, 3>>)
```

And you can get the results from calling that transaction, via:

```elixir
{:ok, <<0x0c>>} = Signet.RPC.call_trx(transaction)
```

And if you're happy, you can send the trx:

```elixir
{:ok, trx_id} = Signet.RPC.send_trx(transaction)
```

You can also pass in known Solidity errors, to have them decoded for you, e.g.:

```elixir
> errors = ["Cool(uint256,string)"]
> Signet.Transaction.V1.new(1, {100, :gwei}, 100_000, <<11::160>>, {2, :wei}, <<1, 2, 3>>)
> |> Signet.RPC.call_trx(errors: errors)
{:error, "error 3: execution reverted (Cool(uint256,string)[1, \"cat\"])"}
```

Finally, `execute_trx` is similar to sending transactions with Web3, which will pull a nonce and estimate gas, before submitting the transaction to the Ethereum node:

```elixir
{:ok, trx_id} = Signet.RPC.execute_trx(<<1::160>>, {"baz(uint,address)", [50, <<1::160>> |> :binary.decode_unsigned]}, gas_price: {50, :gwei}, gas_limit: 100_000, value: 0, nonce: 10)
```

Note: due to our ABI encoder, addresses should be passed in as `unsigned`s, not binaries.

### Filtering

The library also has a built-in system to use JSON-RPC filters (i.e. via `eth_newFilter`). In your application.ex (or any other supervisor), start a new filter:

```
children = [
  # ...
                   # Filter name     # Address    # Topics
  {Signet.Filter, [MyTransferFilter, <<1::160>>, [<<2::256>>]]}
]
```

Then, in your code, any process can register to hear events from the filter via:

```elixir
Signet.Filter.listen(MyTransferFilter)
```

Once registered, events will be passed in via Elixir messages `{:event, event}` for decoded events and `{:log, log}` for plain logs. For example:

```elixir
defmodule MyGenServer do
  use GenServer

  # ...
  def init(_) do
    Signet.Filter.listen(MyTransferFilter)
  end

  def handle_info({:event, event, log}, state) do
    IO.inspect(event, label: "New Event")
    {:noreply, state}
  end

  def handle_info({:log, log}, state) do
    IO.inspect(log, label: "New Log")
    {:noreply, state}
  end
end
```

Currently, only ERC-20 transfer events as decoded, e.g. as:

```elixir
{:event, {"Transfer", %{"from" => <<1::160>>, "to" => <<2::160>>, "amount" => 100}}, %Signet.Filter.Log{}}
```

Note: filters may expire if not refreshed every so often. The filter code does not attempt to reach back in time if a filter is expired- that is up to your code.

## Contributing

Create a PR to contribute to Signet. All contributors agree to accept the license specified in this repository for all contributions to this project. See [LICENSE.md](/LICENSE.md).

Feel free to create Feature Requests in the issues.
