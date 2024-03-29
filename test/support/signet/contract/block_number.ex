defmodule Signet.Contract.BlockNumber do
  @moduledoc ~S"""
  This module was auto-generated by Signet. Any changes may be lost.

  See `mix help signet.gen` for more information.
  """
  use Signet.Hex

  def contract_name do
    "BlockNumber"
  end

  def query_selector() do
    %{
      __struct__: ABI.FunctionSelector,
      function: "query",
      function_type: :function,
      returns: [%{name: "blockNumber", type: {:uint, 256}}],
      state_mutability: :view,
      types: []
    }
  end

  def encode_query() do
    ABI.encode(query_selector(), [])
  end

  def prepare_query(contract, opts \\ []) do
    Signet.RPC.prepare_trx(contract, encode_query(), opts)
  end

  def build_trx_query(contract) do
    %Signet.Transaction.V2{destination: contract, data: encode_query()}
  end

  def call_query(contract, opts \\ []) do
    Signet.RPC.call_trx(build_trx_query(contract), opts)
  end

  def estimate_gas_query(contract, opts \\ []) do
    Signet.RPC.estimate_gas(build_trx_query(contract), opts)
  end

  def execute_query(contract, opts \\ []) do
    Signet.RPC.execute_trx(contract, encode_query(), opts)
  end

  def decode_query_call(<<44, 70, 178, 5>> <> calldata) do
    ABI.decode(query_selector(), calldata)
  end

  def query_cool_selector() do
    %{
      __struct__: ABI.FunctionSelector,
      function: "queryCool",
      function_type: :function,
      returns: [
        %{
          name: "cool",
          type:
            {:tuple,
             [
               %{name: "x", type: :string},
               %{name: "ys", type: {:array, {:uint, 256}}},
               %{name: "fun", type: {:tuple, [%{name: "cat", type: :string}]}}
             ]}
        }
      ],
      state_mutability: :pure,
      types: []
    }
  end

  def encode_query_cool() do
    ABI.encode(query_cool_selector(), [])
  end

  def prepare_query_cool(contract, opts \\ []) do
    Signet.RPC.prepare_trx(contract, encode_query_cool(), opts)
  end

  def build_trx_query_cool(contract) do
    %Signet.Transaction.V2{destination: contract, data: encode_query_cool()}
  end

  def call_query_cool(contract, opts \\ []) do
    Signet.RPC.call_trx(build_trx_query_cool(contract), opts)
  end

  def estimate_gas_query_cool(contract, opts \\ []) do
    Signet.RPC.estimate_gas(build_trx_query_cool(contract), opts)
  end

  def execute_query_cool(contract, opts \\ []) do
    Signet.RPC.execute_trx(contract, encode_query_cool(), opts)
  end

  def decode_query_cool_call(<<107, 188, 156, 20>> <> calldata) do
    ABI.decode(query_cool_selector(), calldata)
  end

  def query_three_selector() do
    %{
      __struct__: ABI.FunctionSelector,
      function: "queryThree",
      function_type: :function,
      returns: [%{name: "", type: {:uint, 256}}],
      state_mutability: :view,
      types: []
    }
  end

  def encode_query_three() do
    ABI.encode(query_three_selector(), [])
  end

  def prepare_query_three(contract, opts \\ []) do
    Signet.RPC.prepare_trx(contract, encode_query_three(), opts)
  end

  def build_trx_query_three(contract) do
    %Signet.Transaction.V2{destination: contract, data: encode_query_three()}
  end

  def call_query_three(contract, opts \\ []) do
    Signet.RPC.call_trx(build_trx_query_three(contract), opts)
  end

  def estimate_gas_query_three(contract, opts \\ []) do
    Signet.RPC.estimate_gas(build_trx_query_three(contract), opts)
  end

  def execute_query_three(contract, opts \\ []) do
    Signet.RPC.execute_trx(contract, encode_query_three(), opts)
  end

  def decode_query_three_call(<<219, 127, 37, 93>> <> calldata) do
    ABI.decode(query_three_selector(), calldata)
  end

  def query_two_selector() do
    %{
      __struct__: ABI.FunctionSelector,
      function: "queryTwo",
      function_type: :function,
      returns: [%{name: "x", type: {:uint, 256}}, %{name: "y", type: {:uint, 256}}],
      state_mutability: :view,
      types: []
    }
  end

  def encode_query_two() do
    ABI.encode(query_two_selector(), [])
  end

  def prepare_query_two(contract, opts \\ []) do
    Signet.RPC.prepare_trx(contract, encode_query_two(), opts)
  end

  def build_trx_query_two(contract) do
    %Signet.Transaction.V2{destination: contract, data: encode_query_two()}
  end

  def call_query_two(contract, opts \\ []) do
    Signet.RPC.call_trx(build_trx_query_two(contract), opts)
  end

  def estimate_gas_query_two(contract, opts \\ []) do
    Signet.RPC.estimate_gas(build_trx_query_two(contract), opts)
  end

  def execute_query_two(contract, opts \\ []) do
    Signet.RPC.execute_trx(contract, encode_query_two(), opts)
  end

  def decode_query_two_call(<<53, 0, 122, 122>> <> calldata) do
    ABI.decode(query_two_selector(), calldata)
  end

  def decode_call(calldata = <<44, 70, 178, 5>> <> _) do
    {:ok, "query", decode_query_call(calldata)}
  end

  def decode_call(calldata = <<107, 188, 156, 20>> <> _) do
    {:ok, "queryCool", decode_query_cool_call(calldata)}
  end

  def decode_call(calldata = <<219, 127, 37, 93>> <> _) do
    {:ok, "queryThree", decode_query_three_call(calldata)}
  end

  def decode_call(calldata = <<53, 0, 122, 122>> <> _) do
    {:ok, "queryTwo", decode_query_two_call(calldata)}
  end

  def decode_call(_) do
    :not_found
  end

  def decode_event(_) do
    :not_found
  end

  def decode_error(_) do
    :not_found
  end

  def bytecode() do
    hex!(
      "0x608060405234801561001057600080fd5b506102c4806100206000396000f3fe608060405234801561001057600080fd5b506004361061004c5760003560e01c80632c46b2051461005157806335007a7a146100645780636bbc9c1414610077578063db7f255d14610051575b600080fd5b6040514381526020015b60405180910390f35b604080514380825260208201520161005b565b61007f61008c565b60405161005b91906101e9565b61009461016f565b60408051600380825260808201909252600091602082016060803683370190505090506001816000815181106100cc576100cc610278565b6020026020010181815250506002816002815181106100ed576100ed610278565b60200260200101818152505060038160038151811061010e5761010e610278565b6020908102919091018101919091526040805160a0810182526002606080830191825261686960f01b608084015290825281840194909452815193840182526004928401928352636d656f7760e01b84830152918352810191909152919050565b6040518060600160405280606081526020016060815260200161019e6040518060200160405280606081525090565b905290565b6000815180845260005b818110156101c9576020818501810151868301820152016101ad565b506000602082860101526020601f19601f83011685010191505092915050565b60006020808352835160608285015261020560808501826101a3565b82860151601f1986830381016040880152815180845291850193506000929091908501905b8084101561024a578451825293850193600193909301929085019061022a565b5060408801518782038301606089015251858252935061026c858201856101a3565b98975050505050505050565b634e487b7160e01b600052603260045260246000fdfea2646970667358221220efea369fadd714627de611c12bdbd7180cc281b1920e802d93697400910caf7964736f6c63430008170033"
    )
  end

  def deployed_bytecode() do
    hex!(
      "0x608060405234801561001057600080fd5b506004361061004c5760003560e01c80632c46b2051461005157806335007a7a146100645780636bbc9c1414610077578063db7f255d14610051575b600080fd5b6040514381526020015b60405180910390f35b604080514380825260208201520161005b565b61007f61008c565b60405161005b91906101e9565b61009461016f565b60408051600380825260808201909252600091602082016060803683370190505090506001816000815181106100cc576100cc610278565b6020026020010181815250506002816002815181106100ed576100ed610278565b60200260200101818152505060038160038151811061010e5761010e610278565b6020908102919091018101919091526040805160a0810182526002606080830191825261686960f01b608084015290825281840194909452815193840182526004928401928352636d656f7760e01b84830152918352810191909152919050565b6040518060600160405280606081526020016060815260200161019e6040518060200160405280606081525090565b905290565b6000815180845260005b818110156101c9576020818501810151868301820152016101ad565b506000602082860101526020601f19601f83011685010191505092915050565b60006020808352835160608285015261020560808501826101a3565b82860151601f1986830381016040880152815180845291850193506000929091908501905b8084101561024a578451825293850193600193909301929085019061022a565b5060408801518782038301606089015251858252935061026c858201856101a3565b98975050505050505050565b634e487b7160e01b600052603260045260246000fdfea2646970667358221220efea369fadd714627de611c12bdbd7180cc281b1920e802d93697400910caf7964736f6c63430008170033"
    )
  end
end
