defmodule Signet.Test.Client do
  @moduledoc """
  A module for helping tests by providing responses without
  needing to connect to a real Etheruem node.
  """

  defp parse_request(body) do
    %{
      "jsonrpc" => "2.0",
      "method" => method,
      "params" => params,
      "id" => id
    } = body

    {method, params, id}
  end

  def post(_url, body, _headers, _opts) do
    {method, params, id} = parse_request(Jason.decode!(body))

    case apply(__MODULE__, String.to_atom(method), params) do
      {:error, error} ->
        return_body = Jason.encode!(%{"jsonrpc" => "2.0", "error" => error, "id" => id})
        {:ok, %HTTPoison.Response{status_code: 200, body: return_body}}

      {:ok, result} ->
        return_body = Jason.encode!(%{"jsonrpc" => "2.0", "result" => result, "id" => id})
        {:ok, %HTTPoison.Response{status_code: 200, body: return_body}}

      result ->
        return_body = Jason.encode!(%{"jsonrpc" => "2.0", "result" => result, "id" => id})
        {:ok, %HTTPoison.Response{status_code: 200, body: return_body}}
    end
  end

  def net_version() do
    "3"
  end

  def get_balance(_address, _block) do
    "0x0234c8a3397aab58"
  end

  def eth_getTransactionCount(_address, _block) do
    "0x4"
  end

  def eth_getTransactionReceipt(
        "0x0000000000000000000000000000000000000000000000000000000000000001"
      ),
      do: %{}

  def eth_getTransactionReceipt(
        "0x0000000000000000000000000000000000000000000000000000000000000002"
      ),
      do: nil

  def eth_getTransactionReceipt(
        "0xF9E69BE4F1AE524854E14DC820C519D8F2B86E52C60E54448ABF920D22FB6FE2"
      ) do
    %{
      "transactionHash" => "0xf9e69be4f1ae524854e14dc820c519d8f2b86e52c60e54448abf920d22fb6fe2",
      "transactionIndex" => "0x0",
      "blockHash" => "0x4bc3c26b1a599ced9876d9bf9a17c9bd58ec8b71a68e75335de7f2820e9336ca",
      "blockNumber" => "0xa01df4",
      "from" => "0xb03d1100c68e58aa1895f8c1f230c0851ff41851",
      "to" => "0x9d8ec03e9ddb71f04da9db1e38837aaac1782a97",
      "cumulativeGasUsed" => "0x365b2",
      "gasUsed" => "0x365b2",
      "contractAddress" => nil,
      "logs" => [
        %{
          "address" => "0x9d8ec03e9ddb71f04da9db1e38837aaac1782a97",
          "topics" => [
            "0x3ffe5de331422c5ec98e2d9ced07156f640bb51e235ef956e50263d4b28d3ae4",
            "0x0000000000000000000000002326aba712500ae3114b664aeb51dba2c2fb416d",
            "0x0000000000000000000000002326aba712500ae3114b664aeb51dba2c2fb416d"
          ],
          "data" =>
            "0x000000000000000000000000cb372382aa9a9e6f926714f4305afac4566f75380000000000000000000000000000000000000000000000000000000000000000",
          "blockHash" => "0x4bc3c26b1a599ced9876d9bf9a17c9bd58ec8b71a68e75335de7f2820e9336ca",
          "blockNumber" => "0xa01df4",
          "transactionHash" =>
            "0xf9e69be4f1ae524854e14dc820c519d8f2b86e52c60e54448abf920d22fb6fe2",
          "transactionIndex" => "0x0",
          "logIndex" => "0x0",
          "removed" => false
        },
        %{
          "address" => "0xcb372382aa9a9e6f926714f4305afac4566f7538",
          "topics" => [
            "0xe0d20d95fbbe7375f6edead77b5ce5c5b096e7dac85848c45c37a95eaf17fe62",
            "0x0000000000000000000000009d8ec03e9ddb71f04da9db1e38837aaac1782a97",
            "0x00000000000000000000000054f0a87eb5c8c8ba70243de1ac19e735b41b10a2",
            "0x0000000000000000000000000000000000000000000000000000000000000000"
          ],
          "data" => "0x0000000000000000000000000000000000000000000000000000000000000000",
          "blockHash" => "0x4bc3c26b1a599ced9876d9bf9a17c9bd58ec8b71a68e75335de7f2820e9336ca",
          "blockNumber" => "0xa01df4",
          "transactionHash" =>
            "0xf9e69be4f1ae524854e14dc820c519d8f2b86e52c60e54448abf920d22fb6fe2",
          "transactionIndex" => "0x0",
          "logIndex" => "0x1",
          "removed" => false
        },
        %{
          "address" => "0xcb372382aa9a9e6f926714f4305afac4566f7538",
          "topics" => ["0x0000000000000000000000000000000000000000000000000000000000000055"],
          "data" => "0x",
          "blockHash" => "0x4bc3c26b1a599ced9876d9bf9a17c9bd58ec8b71a68e75335de7f2820e9336ca",
          "blockNumber" => "0xa01df4",
          "transactionHash" =>
            "0xf9e69be4f1ae524854e14dc820c519d8f2b86e52c60e54448abf920d22fb6fe2",
          "transactionIndex" => "0x0",
          "logIndex" => "0x2",
          "removed" => false
        }
      ],
      "status" => "0x1",
      "logsBloom" =>
        "0x00800000000000000000000400000000000000000000000000000000000000000000000000000000000000000000002000200040000000000000000200001000000000000000000000000000000000000000000000000000000000000010000000008000020000004000000200000800000000000000000000220000000000000000000000000800000000000400000000000000000000000000000000000000000000040000000000008000008000000000000000000000000000000004000000800000000000004000000000000000000000000000000004080000000020000000000000000080000000000000000000000000000000000000000000000000",
      "type" => "0x0",
      "effectiveGasPrice" => "0x47868c0a",
      "deposit_nonce" => nil
    }
  end

  def eth_getTransactionReceipt(
        "0x85D995EBA9763907FDF35CD2034144DD9D53CE32CBEC21349D4B12823C6860C5"
      ) do
    %{
      "blockHash" => "0xa957d47df264a31badc3ae823e10ac1d444b098d9b73d204c40426e57f47e8c3",
      "blockNumber" => "0xeff35f",
      "contractAddress" => nil,
      "cumulativeGasUsed" => "0xa12515",
      "effectiveGasPrice" => "0x5a9c688d4",
      "from" => "0x6221a9c005f6e47eb398fd867784cacfdcfff4e7",
      "gasUsed" => "0xb4c8",
      "logs" => [
        %{
          "logIndex" => "0x1",
          "blockNumber" => "0x1b4",
          "blockHash" => "0xaa8216c5785ac562ff41e2dcfdf5785ac562ff41e2dcfdf829c5a142f1fccd7d",
          "transactionHash" =>
            "0xaadf829c5a142f1fccd7d8216c5785ac562ff41e2dcfdf5785ac562ff41e2dcf",
          "transactionIndex" => "0x0",
          "address" => "0x16c5785ac562ff41e2dcfdf829c5a142f1fccd7d",
          "data" => "0x0000000000000000000000000000000000000000000000000000000000000000",
          "topics" => [
            "0x59ebeb90bc63057b6515673c3ecf9438e5058bca0f92585014eced636878c9a5"
          ]
        }
      ],
      "logsBloom" =>
        "0x00000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000001",
      "status" => "0x1",
      "to" => "0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2",
      "transactionHash" => "0x85d995eba9763907fdf35cd2034144dd9d53ce32cbec21349d4b12823c6860c5",
      "transactionIndex" => "0x66",
      "type" => "0x2"
    }
  end

  def eth_feeHistory(_block_count, _newest_block, _reward_percentiles \\ []) do
    %{
      "oldestBlock" => "0xfd6a75",
      "reward" => [
        [
          "0x3b9aca00",
          "0x3b9aca00",
          "0x59682f00"
        ],
        [
          "0x3b9aca00",
          "0x3b9aca00",
          "0x77359400"
        ],
        [
          "0x3b9aca00",
          "0x3b9aca00",
          "0x3b9aca00"
        ],
        [
          "0x2e7ddb00",
          "0x3b9aca00",
          "0x77359400"
        ],
        [
          "0x3b9aca00",
          "0x3b9aca00",
          "0x59682f00"
        ]
      ],
      "baseFeePerGas" => [
        "0x4c9d974c3",
        "0x4c38a847a",
        "0x49206d475",
        "0x47ac58b63",
        "0x471e805d8",
        "0x46f5f64a6"
      ],
      "gasUsedRatio" => [
        0.4794155666666667,
        0.3375966,
        0.42049746666666665,
        0.4690773,
        0.49109343333333333
      ]
    }
  end

  def trace_transaction("0x000000000000000000000000000000000000000000000000000000000000000A") do
    [
      %{
        "action" => %{
          "callType" => "call",
          "from" => "0xb03d1100c68e58aa1895f8c1f230c0851ff41851",
          "gas" => "0x5bc0b",
          "input" =>
            "0xce28da440000000000000000000000005af819e8d1bf8c87e3107441fb799e4f1876448e0000000000000000000000005af819e8d1bf8c87e3107441fb799e4f1876448e000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000e0000000000000000000000000000000000000000000000000000000000000001c46fc4208ee27643f7686feef2c622aa192a12a12e023eb3a0a5acdef9c3663e52554479549cdf9d47b467ddf33dd8807535f0d5875968b318ce01e8ca40281490000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000a000000000000000000000000000000000000000000000000000000000000000e0000000000000000000000000000000000000000000000000000000007104f0080000000000000000000000000000000000000000000000000000000000000019630102030460005232620000135760006000f35b6004601cfd00000000000000000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002",
          "to" => "0x9d8ec03e9ddb71f04da9db1e38837aaac1782a97",
          "value" => "0x0"
        },
        "blockHash" => "0x151ccedeab15a443b3c45719ff00404d9b1d431454e6f63c845b22c46c9d25e2",
        "blockNumber" => 10_493_512,
        "error" => "Reverted",
        "result" => %{"gasUsed" => "0x35276", "output" => "0x01020304"},
        "subtraces" => 2,
        "traceAddress" => [],
        "transactionHash" => "0xd2cb84e759a8882f8c3de29b673f6a602e0cae7f37a440b957526ef76eb05303",
        "transactionPosition" => 0,
        "type" => "call"
      },
      %{
        "action" => %{
          "from" => "0x9d8ec03e9ddb71f04da9db1e38837aaac1782a97",
          "gas" => "0x4ad07",
          "init" =>
            "0x60e03461009157601f6101ec38819003918201601f19168301916001600160401b038311848410176100965780849260609460405283398101031261009157610047816100ac565b906100606040610059602084016100ac565b92016100ac565b9060805260a05260c05260405161012b90816100c18239608051816088015260a051816045015260c0518160c60152f35b600080fd5b634e487b7160e01b600052604160045260246000fd5b51906001600160a01b03821682036100915756fe608060405260043610156013575b3660ba57005b6000803560e01c8063238ac9331460775763c34c08e51460325750600d565b34607457806003193601126074576040517f00000000000000000000000000000000000000000000000000000000000000006001600160a01b03168152602090f35b80fd5b5034607457806003193601126074577f00000000000000000000000000000000000000000000000000000000000000006001600160a01b03166080908152602090f35b600036818037808036817f00000000000000000000000000000000000000000000000000000000000000005af4903d918282803e60f357fd5bf3fea264697066735822122032b5603d6937ceb7a252e16379744d8545670ff4978c8d76c985d051dfcfe46c64736f6c634300081700330000000000000000000000009eecb6f3c9b7516094ed78e2e0e76201cbd6aac00000000000000000000000005af819e8d1bf8c87e3107441fb799e4f1876448e0000000000000000000000005af819e8d1bf8c87e3107441fb799e4f1876448e",
          "value" => "0x0"
        },
        "blockHash" => "0x151ccedeab15a443b3c45719ff00404d9b1d431454e6f63c845b22c46c9d25e2",
        "blockNumber" => 10_493_512,
        "result" => %{
          "address" => "0x107eed62216e0f83218858cef6830d1b17ad6bc3",
          "code" =>
            "0x608060405260043610156013575b3660ba57005b6000803560e01c8063238ac9331460775763c34c08e51460325750600d565b34607457806003193601126074576040517f0000000000000000000000005af819e8d1bf8c87e3107441fb799e4f1876448e6001600160a01b03168152602090f35b80fd5b5034607457806003193601126074577f0000000000000000000000005af819e8d1bf8c87e3107441fb799e4f1876448e6001600160a01b03166080908152602090f35b600036818037808036817f0000000000000000000000009eecb6f3c9b7516094ed78e2e0e76201cbd6aac05af4903d918282803e60f357fd5bf3fea264697066735822122032b5603d6937ceb7a252e16379744d8545670ff4978c8d76c985d051dfcfe46c64736f6c63430008170033",
          "gasUsed" => "0xebe8"
        },
        "subtraces" => 0,
        "traceAddress" => [0],
        "transactionHash" => "0xd2cb84e759a8882f8c3de29b673f6a602e0cae7f37a440b957526ef76eb05303",
        "transactionPosition" => 0,
        "type" => "create"
      },
      %{
        "action" => %{
          "callType" => "call",
          "from" => "0x9d8ec03e9ddb71f04da9db1e38837aaac1782a97",
          "gas" => "0x3b933",
          "input" =>
            "0x7fba1a4e0000000000000000000000000000000000000000000000000000000000000080000000000000000000000000000000000000000000000000000000000000001c46fc4208ee27643f7686feef2c622aa192a12a12e023eb3a0a5acdef9c3663e52554479549cdf9d47b467ddf33dd8807535f0d5875968b318ce01e8ca40281490000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000a000000000000000000000000000000000000000000000000000000000000000e0000000000000000000000000000000000000000000000000000000007104f0080000000000000000000000000000000000000000000000000000000000000019630102030460005232620000135760006000f35b6004601cfd00000000000000000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002",
          "to" => "0x107eed62216e0f83218858cef6830d1b17ad6bc3",
          "value" => "0x0"
        },
        "blockHash" => "0x151ccedeab15a443b3c45719ff00404d9b1d431454e6f63c845b22c46c9d25e2",
        "blockNumber" => 10_493_512,
        "error" => "Reverted",
        "result" => %{"gasUsed" => "0x1bfa6", "output" => "0x01020304"},
        "subtraces" => 1,
        "traceAddress" => [1],
        "transactionHash" => "0xd2cb84e759a8882f8c3de29b673f6a602e0cae7f37a440b957526ef76eb05303",
        "transactionPosition" => 0,
        "type" => "call"
      },
      %{
        "action" => %{
          "callType" => "delegatecall",
          "from" => "0x107eed62216e0f83218858cef6830d1b17ad6bc3",
          "gas" => "0x39f63",
          "input" =>
            "0x7fba1a4e0000000000000000000000000000000000000000000000000000000000000080000000000000000000000000000000000000000000000000000000000000001c46fc4208ee27643f7686feef2c622aa192a12a12e023eb3a0a5acdef9c3663e52554479549cdf9d47b467ddf33dd8807535f0d5875968b318ce01e8ca40281490000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000a000000000000000000000000000000000000000000000000000000000000000e0000000000000000000000000000000000000000000000000000000007104f0080000000000000000000000000000000000000000000000000000000000000019630102030460005232620000135760006000f35b6004601cfd00000000000000000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002",
          "to" => "0x9eecb6f3c9b7516094ed78e2e0e76201cbd6aac0",
          "value" => "0x0"
        },
        "blockHash" => "0x151ccedeab15a443b3c45719ff00404d9b1d431454e6f63c845b22c46c9d25e2",
        "blockNumber" => 10_493_512,
        "error" => "Reverted",
        "result" => %{"gasUsed" => "0x1b46a", "output" => "0x01020304"},
        "subtraces" => 4,
        "traceAddress" => [1, 0],
        "transactionHash" => "0xd2cb84e759a8882f8c3de29b673f6a602e0cae7f37a440b957526ef76eb05303",
        "transactionPosition" => 0,
        "type" => "call"
      },
      %{
        "action" => %{
          "callType" => "staticcall",
          "from" => "0x107eed62216e0f83218858cef6830d1b17ad6bc3",
          "gas" => "0x382a8",
          "input" => "0x238ac933",
          "to" => "0x107eed62216e0f83218858cef6830d1b17ad6bc3",
          "value" => "0x0"
        },
        "blockHash" => "0x151ccedeab15a443b3c45719ff00404d9b1d431454e6f63c845b22c46c9d25e2",
        "blockNumber" => 10_493_512,
        "result" => %{
          "gasUsed" => "0xad",
          "output" => "0x0000000000000000000000005af819e8d1bf8c87e3107441fb799e4f1876448e"
        },
        "subtraces" => 0,
        "traceAddress" => [1, 0, 0],
        "transactionHash" => "0xd2cb84e759a8882f8c3de29b673f6a602e0cae7f37a440b957526ef76eb05303",
        "transactionPosition" => 0,
        "type" => "call"
      },
      %{
        "action" => %{
          "callType" => "staticcall",
          "from" => "0x107eed62216e0f83218858cef6830d1b17ad6bc3",
          "gas" => "0x3757f",
          "input" =>
            "0x8cf01bd86886709834af922756b5e263623577d3ce62cd570f7e0c580ffe9456000000000000000000000000000000000000000000000000000000000000001c46fc4208ee27643f7686feef2c622aa192a12a12e023eb3a0a5acdef9c3663e52554479549cdf9d47b467ddf33dd8807535f0d5875968b318ce01e8ca4028149",
          "to" => "0x0000000000000000000000000000000000000001",
          "value" => "0x0"
        },
        "blockHash" => "0x151ccedeab15a443b3c45719ff00404d9b1d431454e6f63c845b22c46c9d25e2",
        "blockNumber" => 10_493_512,
        "result" => %{
          "gasUsed" => "0xbb8",
          "output" => "0x0000000000000000000000005af819e8d1bf8c87e3107441fb799e4f1876448e"
        },
        "subtraces" => 0,
        "traceAddress" => [1, 0, 1],
        "transactionHash" => "0xd2cb84e759a8882f8c3de29b673f6a602e0cae7f37a440b957526ef76eb05303",
        "transactionPosition" => 0,
        "type" => "call"
      },
      %{
        "action" => %{
          "callType" => "call",
          "from" => "0x107eed62216e0f83218858cef6830d1b17ad6bc3",
          "gas" => "0x35d37",
          "input" =>
            "0xd6d38d3f00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000019630102030460005232620000135760006000f35b6004601cfd00000000000000",
          "to" => "0x6385c1d72862d10fd77ceb80c1b896e030fa8cce",
          "value" => "0x0"
        },
        "blockHash" => "0x151ccedeab15a443b3c45719ff00404d9b1d431454e6f63c845b22c46c9d25e2",
        "blockNumber" => 10_493_512,
        "result" => %{
          "gasUsed" => "0xa535",
          "output" => "0x0000000000000000000000000479f1ccc2d1dbfc7f648b16709c225a421882c7"
        },
        "subtraces" => 1,
        "traceAddress" => [1, 0, 2],
        "transactionHash" => "0xd2cb84e759a8882f8c3de29b673f6a602e0cae7f37a440b957526ef76eb05303",
        "transactionPosition" => 0,
        "type" => "call"
      },
      %{
        "action" => %{
          "from" => "0x6385c1d72862d10fd77ceb80c1b896e030fa8cce",
          "gas" => "0x2c11c",
          "init" =>
            "0x608060405238601319018060146000396000f3fe630102030460005232620000135760006000f35b6004601cfd",
          "value" => "0x0"
        },
        "blockHash" => "0x151ccedeab15a443b3c45719ff00404d9b1d431454e6f63c845b22c46c9d25e2",
        "blockNumber" => 10_493_512,
        "result" => %{
          "address" => "0x0479f1ccc2d1dbfc7f648b16709c225a421882c7",
          "code" => "0x630102030460005232620000135760006000f35b6004601cfd",
          "gasUsed" => "0x13b7"
        },
        "subtraces" => 0,
        "traceAddress" => [1, 0, 2, 0],
        "transactionHash" => "0xd2cb84e759a8882f8c3de29b673f6a602e0cae7f37a440b957526ef76eb05303",
        "transactionPosition" => 0,
        "type" => "create"
      },
      %{
        "action" => %{
          "callType" => "call",
          "from" => "0x107eed62216e0f83218858cef6830d1b17ad6bc3",
          "gas" => "0x2a404",
          "input" =>
            "0x7fa56b5f00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000479f1ccc2d1dbfc7f648b16709c225a421882c70000000000000000000000000000000000000000000000000000000000000060000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002",
          "to" => "0x57aeaa002075971027c9cd72a86ed1c3d864d80e",
          "value" => "0x0"
        },
        "blockHash" => "0x151ccedeab15a443b3c45719ff00404d9b1d431454e6f63c845b22c46c9d25e2",
        "blockNumber" => 10_493_512,
        "error" => "Reverted",
        "result" => %{"gasUsed" => "0xc389", "output" => "0x01020304"},
        "subtraces" => 1,
        "traceAddress" => [1, 0, 3],
        "transactionHash" => "0xd2cb84e759a8882f8c3de29b673f6a602e0cae7f37a440b957526ef76eb05303",
        "transactionPosition" => 0,
        "type" => "call"
      },
      %{
        "action" => %{
          "callType" => "call",
          "from" => "0x57aeaa002075971027c9cd72a86ed1c3d864d80e",
          "gas" => "0x1dfac",
          "input" =>
            "0x46af85cf0000000000000000000000000479f1ccc2d1dbfc7f648b16709c225a421882c70000000000000000000000000000000000000000000000000000000000000040000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002",
          "to" => "0x107eed62216e0f83218858cef6830d1b17ad6bc3",
          "value" => "0x0"
        },
        "blockHash" => "0x151ccedeab15a443b3c45719ff00404d9b1d431454e6f63c845b22c46c9d25e2",
        "blockNumber" => 10_493_512,
        "error" => "Reverted",
        "result" => %{"gasUsed" => "0x69e", "output" => "0x01020304"},
        "subtraces" => 1,
        "traceAddress" => [1, 0, 3, 0],
        "transactionHash" => "0xd2cb84e759a8882f8c3de29b673f6a602e0cae7f37a440b957526ef76eb05303",
        "transactionPosition" => 0,
        "type" => "call"
      },
      %{
        "action" => %{
          "callType" => "delegatecall",
          "from" => "0x107eed62216e0f83218858cef6830d1b17ad6bc3",
          "gas" => "0x1d714",
          "input" =>
            "0x46af85cf0000000000000000000000000479f1ccc2d1dbfc7f648b16709c225a421882c70000000000000000000000000000000000000000000000000000000000000040000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002",
          "to" => "0x9eecb6f3c9b7516094ed78e2e0e76201cbd6aac0",
          "value" => "0x0"
        },
        "blockHash" => "0x151ccedeab15a443b3c45719ff00404d9b1d431454e6f63c845b22c46c9d25e2",
        "blockNumber" => 10_493_512,
        "error" => "Reverted",
        "result" => %{"gasUsed" => "0x55c", "output" => "0x01020304"},
        "subtraces" => 1,
        "traceAddress" => [1, 0, 3, 0, 0],
        "transactionHash" => "0xd2cb84e759a8882f8c3de29b673f6a602e0cae7f37a440b957526ef76eb05303",
        "transactionPosition" => 0,
        "type" => "call"
      },
      %{
        "action" => %{
          "callType" => "callcode",
          "from" => "0x107eed62216e0f83218858cef6830d1b17ad6bc3",
          "gas" => "0x1cbe3",
          "input" =>
            "0x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002",
          "to" => "0x0479f1ccc2d1dbfc7f648b16709c225a421882c7",
          "value" => "0x0"
        },
        "blockHash" => "0x151ccedeab15a443b3c45719ff00404d9b1d431454e6f63c845b22c46c9d25e2",
        "blockNumber" => 10_493_512,
        "error" => "Reverted",
        "result" => %{"gasUsed" => "0x22", "output" => "0x01020304"},
        "subtraces" => 0,
        "traceAddress" => [1, 0, 3, 0, 0, 0],
        "transactionHash" => "0xd2cb84e759a8882f8c3de29b673f6a602e0cae7f37a440b957526ef76eb05303",
        "transactionPosition" => 0,
        "type" => "call"
      }
    ]
  end

  def trace_transaction(_trx_id) do
    [
      %{
        "action" => %{
          "callType" => "call",
          "from" => "0x83806d539d4ea1c140489a06660319c9a303f874",
          "gas" => "0x1a1f8",
          "input" => "0x",
          "to" => "0x1c39ba39e4735cb65978d4db400ddd70a72dc750",
          "value" => "0x7a16c911b4d00000"
        },
        "blockHash" => "0x7eb25504e4c202cf3d62fd585d3e238f592c780cca82dacb2ed3cb5b38883add",
        "blockNumber" => 3_068_185,
        "result" => %{
          "gasUsed" => "0x2982",
          "output" => "0x"
        },
        "subtraces" => 2,
        "traceAddress" => ["0x1c39ba39e4735cb65978d4db400ddd70a72dc750"],
        "transactionHash" => "0x17104ac9d3312d8c136b7f44d4b8b47852618065ebfa534bd2d3b5ef218ca1f3",
        "transactionPosition" => 2,
        "type" => "call"
      },
      %{
        "action" => %{
          "callType" => "call",
          "from" => "0x83806d539d4ea1c140489a06660319c9a303f874",
          "gas" => "0x1a1f8",
          "input" => "0x",
          "to" => "0x1c39ba39e4735cb65978d4db400ddd70a72dc750",
          "value" => "0x7a16c911b4d00000"
        },
        "blockHash" => "0x7eb25504e4c202cf3d62fd585d3e238f592c780cca82dacb2ed3cb5b38883add",
        "blockNumber" => 3_068_186,
        "result" => %{
          "gasUsed" => "0x2982",
          "output" => "0x"
        },
        "subtraces" => 2,
        "traceAddress" => ["0x1c39ba39e4735cb65978d4db400ddd70a72dc750"],
        "transactionHash" => "0x17104ac9d3312d8c136b7f44d4b8b47852618065ebfa534bd2d3b5ef218ca1f3",
        "transactionPosition" => 2,
        "type" => "call"
      }
    ]
  end

  # TODO: Add other outputs
  def trace_call(_trx = %{"to" => _}, ["trace"], _block) do
    [
      %{
        "action" => %{
          "callType" => "call",
          "from" => "0x83806d539d4ea1c140489a06660319c9a303f874",
          "gas" => "0x1a1f8",
          "input" => "0x",
          "to" => "0x1c39ba39e4735cb65978d4db400ddd70a72dc750",
          "value" => "0x7a16c911b4d00000"
        },
        "blockHash" => "0x7eb25504e4c202cf3d62fd585d3e238f592c780cca82dacb2ed3cb5b38883add",
        "blockNumber" => 3_068_185,
        "result" => %{
          "gasUsed" => "0x2982",
          "output" => "0x"
        },
        "subtraces" => 2,
        "traceAddress" => ["0x1c39ba39e4735cb65978d4db400ddd70a72dc750"],
        "transactionHash" => "0x17104ac9d3312d8c136b7f44d4b8b47852618065ebfa534bd2d3b5ef218ca1f3",
        "transactionPosition" => 2,
        "type" => "call"
      },
      %{
        "action" => %{
          "callType" => "call",
          "from" => "0x83806d539d4ea1c140489a06660319c9a303f874",
          "gas" => "0x1a1f8",
          "input" => "0x",
          "to" => "0x1c39ba39e4735cb65978d4db400ddd70a72dc750",
          "value" => "0x7a16c911b4d00000"
        },
        "blockHash" => "0x7eb25504e4c202cf3d62fd585d3e238f592c780cca82dacb2ed3cb5b38883add",
        "blockNumber" => 3_068_186,
        "result" => %{
          "gasUsed" => "0x2982",
          "output" => "0x"
        },
        "subtraces" => 2,
        "traceAddress" => ["0x1c39ba39e4735cb65978d4db400ddd70a72dc750"],
        "transactionHash" => "0x17104ac9d3312d8c136b7f44d4b8b47852618065ebfa534bd2d3b5ef218ca1f3",
        "transactionPosition" => 2,
        "type" => "call"
      }
    ]
  end

  def eth_gasPrice() do
    # 1 gwei
    "0x3b9aca00"
  end

  def eth_maxPriorityFeePerGas() do
    "0x3b9aca01"
  end

  def eth_sendRawTransaction(trx_enc = "0x02" <> _rest) do
    {:ok, trx} =
      trx_enc
      |> Signet.Util.decode_hex!()
      |> Signet.Transaction.V2.decode()

    %Signet.Transaction.V2{
      nonce: nonce,
      max_priority_fee_per_gas: max_priority_fee_per_gas,
      max_fee_per_gas: max_fee_per_gas,
      gas_limit: gas_limit,
      destination: destination,
      amount: _amount,
      data: _data
    } = trx

    Signet.Util.encode_hex(
      <<nonce::integer-size(8), max_priority_fee_per_gas::integer-size(64),
        max_fee_per_gas::integer-size(64), gas_limit::integer-size(24), destination::binary>>
    )
  end

  def eth_sendRawTransaction(trx_enc) do
    {:ok, trx} =
      trx_enc
      |> Signet.Util.decode_hex!()
      |> Signet.Transaction.V1.decode()

    %Signet.Transaction.V1{
      nonce: nonce,
      gas_price: gas_price,
      gas_limit: gas_limit,
      to: to,
      value: _value,
      data: _data,
      v: _v,
      r: _r,
      s: _s
    } = trx

    Signet.Util.encode_hex(
      <<nonce::integer-size(8), gas_price::integer-size(64), gas_limit::integer-size(24),
        to::binary>>
    )
  end

  # Call that fails with simple encoded error
  def eth_call(_trx = %{"to" => "0x000000000000000000000000000000000000000A"}, _block) do
    {:error,
     %{
       "code" => 3,
       "data" => "0x3d738b2e",
       "message" => "execution reverted"
     }}
  end

  # Call that fails with complex encoded error
  def eth_call(_trx = %{"to" => "0x000000000000000000000000000000000000000B"}, _block) do
    {:error,
     %{
       "code" => 3,
       "data" => Signet.Util.encode_hex(ABI.encode("Cool(uint256,string)", [1, "cat"])),
       "message" => "execution reverted"
     }}
  end

  # Call that fails with a blank data
  def eth_call(_trx = %{"to" => "0x000000000000000000000000000000000000000C"}, _block) do
    {:error,
     %{
       "code" => 3,
       "data" => "0x",
       "message" => "execution reverted"
     }}
  end

  # Call that works v1
  def eth_call(
        _trx = %{"to" => "0x0000000000000000000000000000000000000001", "gasPrice" => _},
        _block
      ) do
    "0x0c"
  end

  # Call that works v2
  def eth_call(
        _trx = %{
          "to" => "0x0000000000000000000000000000000000000001",
          "maxPriorityFeePerGas" => _,
          "maxFeePerGas" => _
        },
        _block
      ) do
    "0x0d"
  end

  # Call to Adaptor- don't care about response
  def eth_call(trx = %{"to" => "0x00000000000000000000000000000000000000CC"}, _block) do
    case trx["data"] do
      "0x8035F0CE" ->
        # String.slice(Signet.Util.encode_hex(Signet.Hash.keccak("push()")), 0, 10) ->
        "0x"

      "0x8D4D94A6" <> _ ->
        # String.slice(Signet.Util.encode_hex(Signet.Hash.keccak("withdraw(uint256,address,uint256,bytes32,bytes[])")), 0, 10)
        "0x"

      _ ->
        "0x0c"
    end
  end

  # Call els
  def eth_call(_trx = %{"to" => _}, _block) do
    "0xcc"
  end

  # V1
  def eth_estimateGas(_trx = %{"gasPrice" => _}, _block) do
    "0x0d"
  end

  # V2
  def eth_estimateGas(_trx = %{"maxPriorityFeePerGas" => _, "maxFeePerGas" => _}, _block) do
    "0xdd"
  end

  def eth_newFilter(%{}) do
    "0xf11735"
  end

  def eth_getFilterChanges("0xf11735") do
    [
      %{
        address: "0xb5a5f22694352c15b00323844ad545abb2b11028",
        blockHash: "0x99e8663c7b6d8bba3c7627a17d774238eae3e793dee30008debb2699666657de",
        blockNumber: "0x5d12ab",
        data: "0x00000000000000000000000000000000000000000000000000000004a817c800",
        logIndex: "0x0",
        removed: false,
        topics: [
          "0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef",
          "0x000000000000000000000000b2b7c1795f19fbc28fda77a95e59edbb8b3709c8",
          "0x0000000000000000000000007795126b3ae468f44c901287de98594198ce38ea"
        ],
        transactionHash: "0xa74c2432c9cf7dbb875a385a2411fd8f13ca9ec12216864b1a1ead3c99de99cd",
        transactionIndex: "0x3"
      }
    ]
  end
end
