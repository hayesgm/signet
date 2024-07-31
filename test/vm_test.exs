defmodule Signet.VmTest do
  use ExUnit.Case, async: true
  doctest Signet.VM
  alias Signet.VM

  use Signet.Hex

  import Signet.VmTestHelpers

  @tests [
    %{
      name: "Simple Add",
      code: [
        {:push, 32, word(0x11)},
        {:push, 32, word(0x22)},
        :add,
        :stop
      ],
      exp_stack: [
        word(0x33)
      ]
    },
    %{
      name: "Add Overflowing",
      code: [
        {:push, 32, word("0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffef")},
        {:push, 32, word(0x22)},
        :add,
        :stop
      ],
      exp_stack: [
        word(0x11)
      ]
    },
    %{
      name: "Simple Sub",
      code: [
        {:push, 32, word(0x11)},
        {:push, 32, word(0x22)},
        :sub,
        :stop
      ],
      exp_stack: [
        word(0x11)
      ]
    },
    %{
      name: "Underflowing Sub",
      code: [
        {:push, 32, word(0x33)},
        {:push, 32, word(0x22)},
        :sub,
        :stop
      ],
      exp_stack: [
        word("0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffef")
      ]
    },
    %{
      name: "Simple Mul",
      code: [
        {:push, 32, word(0x11)},
        {:push, 32, word(0x03)},
        :mul,
        :stop
      ],
      exp_stack: [
        word(0x33)
      ]
    },
    %{
      name: "Simple Div",
      code: [
        {:push, 32, word(0x11)},
        {:push, 32, word(0x33)},
        :div,
        :stop
      ],
      exp_stack: [
        word(0x03)
      ]
    },
    %{
      name: "Simple Div Zero",
      code: [
        {:push, 32, word(0x00)},
        {:push, 32, word(0x33)},
        :div,
        :stop
      ],
      exp_stack: [
        word(0x00)
      ]
    },
    %{
      name: "Simple SDiv",
      code: [
        {:push, 32, word(-0x11)},
        {:push, 32, word(-0x33)},
        :sdiv,
        :stop
      ],
      exp_stack: [
        word(0x03)
      ]
    },
    %{
      name: "Mixed Sign SDiv Denom",
      code: [
        {:push, 32, word(-0x11)},
        {:push, 32, word(0x33)},
        :sdiv,
        :stop
      ],
      exp_stack: [
        word(-0x03)
      ]
    },
    %{
      name: "Mixed Sign SDiv Num",
      code: [
        {:push, 32, word(0x11)},
        {:push, 32, word(-0x33)},
        :sdiv,
        :stop
      ],
      exp_stack: [
        word(-0x03)
      ]
    },
    %{
      name: "Simple Mod",
      code: [
        {:push, 32, word(5)},
        {:push, 32, word(33)},
        :mod,
        :stop
      ],
      exp_stack: [
        word(3)
      ]
    },
    %{
      name: "Simple Mod Zero",
      code: [
        {:push, 32, word(0)},
        {:push, 32, word(33)},
        :mod,
        :stop
      ],
      exp_stack: [
        word(0)
      ]
    },
    %{
      name: "Simple SMod Positives",
      code: [
        {:push, 32, word(5)},
        {:push, 32, word(33)},
        :smod,
        :stop
      ],
      exp_stack: [
        word(3)
      ]
    },
    %{
      name: "Simple SMod Negatives",
      code: [
        {:push, 32, word(-5)},
        {:push, 32, word(-33)},
        :smod,
        :stop
      ],
      exp_stack: [
        word(-3)
      ]
    },
    %{
      name: "Simple SMod Mixed Num",
      code: [
        {:push, 32, word(5)},
        {:push, 32, word(-33)},
        :smod,
        :stop
      ],
      exp_stack: [
        word(-3)
      ]
    },
    %{
      name: "Simple SMod Mixed Denom",
      code: [
        {:push, 32, word(-5)},
        {:push, 32, word(33)},
        :smod,
        :stop
      ],
      exp_stack: [
        word(3)
      ]
    },
    %{
      name: "Simple SMod Zero",
      code: [
        {:push, 32, word(0)},
        {:push, 32, word(33)},
        :smod,
        :stop
      ],
      exp_stack: [
        word(0)
      ]
    },
    %{
      name: "Simple AddMod",
      code: [
        {:push, 32, word(05)},
        {:push, 32, word(01)},
        {:push, 32, word(32)},
        :addmod,
        :stop
      ],
      exp_stack: [
        word(03)
      ]
    },
    %{
      name: "Simple MulMod",
      code: [
        {:push, 32, word(05)},
        {:push, 32, word(03)},
        {:push, 32, word(11)},
        :mulmod,
        :stop
      ],
      exp_stack: [
        word(03)
      ]
    },
    %{
      name: "Simple Exp",
      code: [
        {:push, 32, word(03)},
        {:push, 32, word(05)},
        :exp,
        :stop
      ],
      exp_stack: [
        word(125)
      ]
    },
    %{
      name: "Sign Extend - Byte 0 Negative",
      code: [
        {:push, 32, word(0xFF)},
        {:push, 32, word(0)},
        :signextend,
        :stop
      ],
      exp_stack: [
        word("0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff")
      ]
    },
    %{
      name: "Sign Extend - Byte 0 Positive",
      code: [
        {:push, 32, word(0x7F)},
        {:push, 32, word(0)},
        :signextend,
        :stop
      ],
      exp_stack: [
        word("0x000000000000000000000000000000000000000000000000000000000000007f")
      ]
    },
    %{
      name: "Sign Extend - Byte 1 Unset",
      code: [
        {:push, 32, word(0xFF)},
        {:push, 32, word(1)},
        :signextend,
        :stop
      ],
      exp_stack: [
        word("0x00000000000000000000000000000000000000000000000000000000000000ff")
      ]
    },
    %{
      name: "Sign Extend - Byte 1 Set",
      code: [
        {:push, 32, word(0x8522)},
        {:push, 32, word(1)},
        :signextend,
        :stop
      ],
      exp_stack: [
        word("0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff8522")
      ]
    },
    %{
      name: "Sign Extend - Byte 32",
      code: [
        {:push, 32, word(0x8522)},
        {:push, 32, word(32)},
        :signextend,
        :stop
      ],
      exp_stack: [
        word(0x8522)
      ]
    },
    %{
      name: "Lt Yes",
      code: [
        {:push, 32, word(04)},
        {:push, 32, word(03)},
        :lt,
        :stop
      ],
      exp_stack: [
        word(1)
      ]
    },
    %{
      name: "Lt No",
      code: [
        {:push, 32, word(02)},
        {:push, 32, word(03)},
        :lt,
        :stop
      ],
      exp_stack: [
        word(0)
      ]
    },
    %{
      name: "Gt No",
      code: [
        {:push, 32, word(04)},
        {:push, 32, word(03)},
        :gt,
        :stop
      ],
      exp_stack: [
        word(0)
      ]
    },
    %{
      name: "Gt Yes",
      code: [
        {:push, 32, word(02)},
        {:push, 32, word(03)},
        :gt,
        :stop
      ],
      exp_stack: [
        word(1)
      ]
    },
    %{
      name: "Eq No",
      code: [
        {:push, 32, word(04)},
        {:push, 32, word(03)},
        :eq,
        :stop
      ],
      exp_stack: [
        word(0)
      ]
    },
    %{
      name: "Eq Yes",
      code: [
        {:push, 32, word(03)},
        {:push, 32, word(03)},
        :eq,
        :stop
      ],
      exp_stack: [
        word(1)
      ]
    },
    %{
      name: "IsZero Yes",
      code: [
        {:push, 32, word(0)},
        :iszero,
        :stop
      ],
      exp_stack: [
        word(1)
      ]
    },
    %{
      name: "IsZero No",
      code: [
        {:push, 32, word(55)},
        :iszero,
        :stop
      ],
      exp_stack: [
        word(0)
      ]
    },
    %{
      name: "Binary And",
      code: [
        {:push, 32, word("0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff00ff")},
        {:push, 32, word("0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff11")},
        :and,
        :stop
      ],
      exp_stack: [
        word("0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff0011")
      ]
    },
    %{
      name: "Binary Or",
      code: [
        {:push, 32, word("0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff00ff")},
        {:push, 32, word("0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff11")},
        :or,
        :stop
      ],
      exp_stack: [
        word("0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff")
      ]
    },
    %{
      name: "Binary Xor",
      code: [
        {:push, 32, word("0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff00ff")},
        {:push, 32, word("0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff11")},
        :xor,
        :stop
      ],
      exp_stack: [
        word("0x000000000000000000000000000000000000000000000000000000000000ffee")
      ]
    },
    %{
      name: "Binary Not",
      code: [
        {:push, 32, word("0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff2211")},
        :not,
        :stop
      ],
      exp_stack: [
        word("0x000000000000000000000000000000000000000000000000000000000000ddee")
      ]
    },
    %{
      name: "Byte 31",
      code: [
        {:push, 32, word("0x1100000000000000000000000000000000000000000000000000000000002233")},
        {:push, 32, word(31)},
        :byte,
        :stop
      ],
      exp_stack: [
        word(0x33)
      ]
    },
    %{
      name: "Byte 30",
      code: [
        {:push, 32, word("0x1100000000000000000000000000000000000000000000000000000000002233")},
        {:push, 32, word(30)},
        :byte,
        :stop
      ],
      exp_stack: [
        word(0x22)
      ]
    },
    %{
      name: "Byte 0",
      code: [
        {:push, 32, word("0x1100000000000000000000000000000000000000000000000000000000002233")},
        {:push, 32, word(0)},
        :byte,
        :stop
      ],
      exp_stack: [
        word(0x11)
      ]
    },
    %{
      name: "Byte 99",
      code: [
        {:push, 32, word("0x1100000000000000000000000000000000000000000000000000000000002233")},
        {:push, 32, word(99)},
        :byte,
        :stop
      ],
      exp_stack: [
        word(0x0)
      ]
    },
    %{
      name: "Shl[0]",
      code: [
        {:push, 32, word("0x112233445566778899aabbccddeeff112233445566778899aabbccddeeff1122")},
        {:push, 32, word(0)},
        :shl,
        :stop
      ],
      exp_stack: [
        word("0x112233445566778899aabbccddeeff112233445566778899aabbccddeeff1122")
      ]
    },
    %{
      name: "Shl[1]",
      code: [
        {:push, 32, word("0x112233445566778899aabbccddeeff112233445566778899aabbccddeeff1122")},
        {:push, 32, word(1)},
        :shl,
        :stop
      ],
      exp_stack: [
        word("0x22446688aaccef1133557799bbddfe22446688aaccef1133557799bbddfe2244")
      ]
    },
    %{
      name: "Shl[8]",
      code: [
        {:push, 32, word("0x112233445566778899aabbccddeeff112233445566778899aabbccddeeff1122")},
        {:push, 32, word(8)},
        :shl,
        :stop
      ],
      exp_stack: [
        word("0x2233445566778899aabbccddeeff112233445566778899aabbccddeeff112200")
      ]
    },
    %{
      name: "Shl[255]",
      code: [
        {:push, 32, word("0x112233445566778899aabbccddeeff112233445566778899aabbccddeeff1111")},
        {:push, 32, word(255)},
        :shl,
        :stop
      ],
      exp_stack: [
        word("0x8000000000000000000000000000000000000000000000000000000000000000")
      ]
    },
    %{
      name: "Shr[0]",
      code: [
        {:push, 32, word("0x112233445566778899aabbccddeeff112233445566778899aabbccddeeff1122")},
        {:push, 32, word(0)},
        :shr,
        :stop
      ],
      exp_stack: [
        word("0x112233445566778899aabbccddeeff112233445566778899aabbccddeeff1122")
      ]
    },
    %{
      name: "Shr[1]",
      code: [
        {:push, 32, word("0x112233445566778899aabbccddeeff112233445566778899aabbccddeeff1122")},
        {:push, 32, word(1)},
        :shr,
        :stop
      ],
      exp_stack: [
        word("0x089119a22ab33bc44cd55de66ef77f889119a22ab33bc44cd55de66ef77f8891")
      ]
    },
    %{
      name: "Shr[8]",
      code: [
        {:push, 32, word("0x112233445566778899aabbccddeeff112233445566778899aabbccddeeff1122")},
        {:push, 32, word(8)},
        :shr,
        :stop
      ],
      exp_stack: [
        word("0x00112233445566778899aabbccddeeff112233445566778899aabbccddeeff11")
      ]
    },
    %{
      name: "Shr[255] MSB=0x11",
      code: [
        {:push, 32, word("0x112233445566778899aabbccddeeff112233445566778899aabbccddeeff1122")},
        {:push, 32, word(255)},
        :shr,
        :stop
      ],
      exp_stack: [
        word(0)
      ]
    },
    %{
      name: "Shr[255] MSB=0xF0",
      code: [
        {:push, 32, word("0xf02233445566778899aabbccddeeff112233445566778899aabbccddeeff1122")},
        {:push, 32, word(255)},
        :shr,
        :stop
      ],
      exp_stack: [
        word(1)
      ]
    },
    %{
      name: "Shr[4] MSB=0xF0",
      code: [
        {:push, 32, word("0xf000000000000000000000000000000000000000000000000000000000000000")},
        {:push, 32, word(4)},
        :shr,
        :stop
      ],
      exp_stack: [
        word("0x0f00000000000000000000000000000000000000000000000000000000000000")
      ]
    },
    %{
      name: "Sar[255] MSB=0x11",
      code: [
        {:push, 32, word("0x112233445566778899aabbccddeeff112233445566778899aabbccddeeff1122")},
        {:push, 32, word(255)},
        :sar,
        :stop
      ],
      exp_stack: [
        word(0)
      ]
    },
    %{
      name: "Sar [255] MSB=0xF0",
      code: [
        {:push, 32, word("0xf02233445566778899aabbccddeeff112233445566778899aabbccddeeff1122")},
        {:push, 32, word(128)},
        :sar,
        :stop
      ],
      exp_stack: [
        word("0xfffffffffffffffffffffffffffffffff02233445566778899aabbccddeeff11")
      ]
    },
    %{
      name: "Sar[4] MSB=0xF0",
      code: [
        {:push, 32, word("0xf000000000000000000000000000000000000000000000000000000000000000")},
        {:push, 32, word(4)},
        :sar,
        :stop
      ],
      exp_stack: [
        word("0xff00000000000000000000000000000000000000000000000000000000000000")
      ]
    },
    %{
      name: "Sar[4] MSB=0x30",
      code: [
        {:push, 32, word("0x3000000000000000000000000000000000000000000000000000000000000000")},
        {:push, 32, word(4)},
        :sar,
        :stop
      ],
      exp_stack: [
        word("0x0300000000000000000000000000000000000000000000000000000000000000")
      ]
    },
    %{
      name: "Sar[8] MSB=0xF0",
      code: [
        {:push, 32, word("0xf000000000000000000000000000000000000000000000000000000000000000")},
        {:push, 32, word(8)},
        :sar,
        :stop
      ],
      exp_stack: [
        word("0xfff0000000000000000000000000000000000000000000000000000000000000")
      ]
    },
    %{
      name: "Sar[8] MSB=0x30",
      code: [
        {:push, 32, word("0x3000000000000000000000000000000000000000000000000000000000000000")},
        {:push, 32, word(8)},
        :sar,
        :stop
      ],
      exp_stack: [
        word("0x0030000000000000000000000000000000000000000000000000000000000000")
      ]
    },
    %{
      name: "Sar: EIP-145 1",
      code: [
        {:push, 32, word("0x0000000000000000000000000000000000000000000000000000000000000001")},
        {:push, 4, word(0x00, 4)},
        :sar,
        :stop
      ],
      exp_stack: [
        word("0x0000000000000000000000000000000000000000000000000000000000000001")
      ]
    },
    %{
      name: "Sar: EIP-145 2",
      code: [
        {:push, 32, word("0x0000000000000000000000000000000000000000000000000000000000000001")},
        {:push, 4, word(0x01, 4)},
        :sar,
        :stop
      ],
      exp_stack: [
        word("0x0000000000000000000000000000000000000000000000000000000000000000")
      ]
    },
    %{
      name: "Sar: EIP-145 3",
      code: [
        {:push, 32, word("0x8000000000000000000000000000000000000000000000000000000000000000")},
        {:push, 4, word(0x01, 4)},
        :sar,
        :stop
      ],
      exp_stack: [
        word("0xc000000000000000000000000000000000000000000000000000000000000000")
      ]
    },
    %{
      name: "Sar: EIP-145 4",
      code: [
        {:push, 32, word("0x8000000000000000000000000000000000000000000000000000000000000000")},
        {:push, 4, word(0xFF, 4)},
        :sar,
        :stop
      ],
      exp_stack: [
        word("0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff")
      ]
    },
    %{
      name: "Sar: EIP-145 5",
      code: [
        {:push, 32, word("0x8000000000000000000000000000000000000000000000000000000000000000")},
        {:push, 4, word(0x0100, 4)},
        :sar,
        :stop
      ],
      exp_stack: [
        word("0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff")
      ]
    },
    %{
      name: "Sar: EIP-145 6",
      code: [
        {:push, 32, word("0x8000000000000000000000000000000000000000000000000000000000000000")},
        {:push, 4, word(0x0101, 4)},
        :sar,
        :stop
      ],
      exp_stack: [
        word("0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff")
      ]
    },
    %{
      name: "Sar: EIP-145 7",
      code: [
        {:push, 32, word("0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff")},
        {:push, 4, word(0x00, 4)},
        :sar,
        :stop
      ],
      exp_stack: [
        word("0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff")
      ]
    },
    %{
      name: "Sar: EIP-145 8",
      code: [
        {:push, 32, word("0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff")},
        {:push, 4, word(0x01, 4)},
        :sar,
        :stop
      ],
      exp_stack: [
        word("0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff")
      ]
    },
    %{
      name: "Sar: EIP-145 9",
      code: [
        {:push, 32, word("0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff")},
        {:push, 4, word(0xFF, 4)},
        :sar,
        :stop
      ],
      exp_stack: [
        word("0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff")
      ]
    },
    %{
      name: "Sar: EIP-145 10",
      code: [
        {:push, 32, word("0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff")},
        {:push, 4, word(0x0100, 4)},
        :sar,
        :stop
      ],
      exp_stack: [
        word("0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff")
      ]
    },
    %{
      name: "Sar: EIP-145 11",
      code: [
        {:push, 32, word("0x0000000000000000000000000000000000000000000000000000000000000000")},
        {:push, 4, word(0x01, 4)},
        :sar,
        :stop
      ],
      exp_stack: [
        word("0x0000000000000000000000000000000000000000000000000000000000000000")
      ]
    },
    %{
      name: "Sar: EIP-145 12",
      code: [
        {:push, 32, word("0x4000000000000000000000000000000000000000000000000000000000000000")},
        {:push, 4, word(0xFE, 4)},
        :sar,
        :stop
      ],
      exp_stack: [
        word("0x0000000000000000000000000000000000000000000000000000000000000001")
      ]
    },
    %{
      name: "Sar: EIP-145 13",
      code: [
        {:push, 32, word("0x7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff")},
        {:push, 4, word(0xF8, 4)},
        :sar,
        :stop
      ],
      exp_stack: [
        word("0x000000000000000000000000000000000000000000000000000000000000007f")
      ]
    },
    %{
      name: "Sar: EIP-145 14",
      code: [
        {:push, 32, word("0x7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff")},
        {:push, 4, word(0xFE, 4)},
        :sar,
        :stop
      ],
      exp_stack: [
        word("0x0000000000000000000000000000000000000000000000000000000000000001")
      ]
    },
    %{
      name: "Sar: EIP-145 15",
      code: [
        {:push, 32, word("0x7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff")},
        {:push, 4, word(0xFF, 4)},
        :sar,
        :stop
      ],
      exp_stack: [
        word("0x0000000000000000000000000000000000000000000000000000000000000000")
      ]
    },
    %{
      name: "Sar: EIP-145 16",
      code: [
        {:push, 32, word("0x7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff")},
        {:push, 4, word(0x0100, 4)},
        :sar,
        :stop
      ],
      exp_stack: [
        word("0x0000000000000000000000000000000000000000000000000000000000000000")
      ]
    },
    %{
      name: "Sha3 Value",
      code: [
        {:push, 32, word("0x112233445566778899aabbccddeeff112233445566778899aabbccddeeff1122")},
        {:push, 32, word(100)},
        :mstore,
        {:push, 32, word(10)},
        {:push, 32, word(110)},
        :sha3,
        :stop
      ],
      exp_stack: [
        word("0x045e288bf0d99a3c6d375f2346e49d6ea1965518853fca8dbca586ba44775e46")
      ]
    },
    %{
      name: "Address",
      code: [
        :address
      ],
      exp_error: {:impure, :address}
    },
    %{
      name: "Balance",
      code: [
        :balance
      ],
      exp_error: {:impure, :balance}
    },
    %{
      name: "Origin",
      code: [
        :origin
      ],
      exp_error: {:impure, :origin}
    },
    %{
      name: "Caller",
      code: [
        :caller
      ],
      exp_error: {:impure, :caller}
    },
    %{
      name: "CallValue 0",
      code: [
        :callvalue,
        :stop
      ],
      exp_stack: [
        word(0)
      ]
    },
    %{
      name: "CallValue 55",
      code: [
        :callvalue,
        :stop
      ],
      exp_stack: [
        word(55)
      ],
      with_call_value: 55
    },
    %{
      name: "CallDataLoad - Empty",
      code: [
        {:push, 1, word(100, 1)},
        :calldataload,
        :stop
      ],
      exp_stack: [
        word(0)
      ]
    },
    %{
      name: "CallDataLoad - Set",
      code: [
        {:push, 1, word(5, 1)},
        :calldataload,
        :stop
      ],
      exp_stack: [
        word("0x1122334455000000000000000000000000000000000000000000000000000000")
      ],
      with_call_data: ~h[0xbbccddeeff1122334455]
    },
    %{
      name: "CallDataSize - Empty",
      code: [
        :calldatasize,
        :stop
      ],
      exp_stack: [
        word(0)
      ]
    },
    %{
      name: "CallDataSize - Set",
      code: [
        :calldatasize,
        :stop
      ],
      exp_stack: [
        word(10)
      ],
      with_call_data: ~h[0xbbccddeeff1122334455]
    },
    %{
      name: "CallDataCopy - Empty",
      code: [
        # size
        {:push, 1, word(5, 1)},
        # offset
        {:push, 1, word(1, 1)},
        # dest_offset
        {:push, 1, word(100, 1)},
        :calldatacopy,
        {:push, 32, word(101)},
        :mload,
        :stop
      ],
      exp_stack: [
        word(0)
      ]
    },
    %{
      name: "CallDataCopy - Set",
      code: [
        # size
        {:push, 1, word(5, 1)},
        # offset
        {:push, 1, word(1, 1)},
        # dest_offset
        {:push, 1, word(100, 1)},
        :calldatacopy,
        {:push, 32, word(101)},
        :mload,
        :stop
      ],
      exp_stack: [
        ~h[0xddeeff1100000000000000000000000000000000000000000000000000000000]
      ],
      with_call_data: ~h[0xbbccddeeff1122334455]
    },
    %{
      name: "CodeSize",
      code: [
        :codesize,
        :stop
      ],
      exp_stack: [
        word(2)
      ]
    },
    %{
      name: "CodeCopy - Set",
      code: [
        # size
        {:push, 1, word(5, 1)},
        # offset
        {:push, 1, word(1, 1)},
        # dest_offset
        {:push, 1, word(100, 1)},
        :codecopy,
        {:push, 32, word(101)},
        :mload,
        :stop
      ],
      exp_stack: [
        ~h[0x6001606400000000000000000000000000000000000000000000000000000000]
      ]
    },
    %{
      name: "Pop",
      code: [
        {:push, 32, word(1)},
        :pop,
        :stop
      ],
      exp_stack: []
    },
    %{
      name: "Pop Underflow",
      code: [
        :pop,
        :stop
      ],
      exp_error: :stack_underflow
    },
    %{
      name: "MStore -> MLoad",
      code: [
        {:push, 32, word("0x112233445566778899aabbccddeeff112233445566778899aabbccddeeff1122")},
        {:push, 32, word(100)},
        :mstore,
        {:push, 32, word(110)},
        :mload,
        :stop
      ],
      exp_stack: [
        ~h[0xbbccddeeff112233445566778899aabbccddeeff112200000000000000000000]
      ]
    },
    %{
      name: "MStore -> MStore8 -> MLoad",
      code: [
        {:push, 32, ~h[0x112233445566778899aabbccddeeff112233445566778899aabbccddeeff1122]},
        {:push, 32, word(100)},
        :mstore,
        {:push, 32, ~h[0x112233445566778899aabbccddeeff112233445566778899aabbccddeeff11fe]},
        {:push, 32, word(120)},
        :mstore8,
        {:push, 32, word(110)},
        :mload,
        :stop
      ],
      exp_stack: [
        ~h[0xbbccddeeff1122334455fe778899aabbccddeeff112200000000000000000000]
      ]
    },
    %{
      name: "Direct Jump - First Path",
      code: [
        # pc = 0
        {:push, 1, word(3, 1)},
        # pc = 2
        :jump,
        # pc = 3
        :jumpdest,
        # pc = 4
        {:push, 1, word(2, 1)},
        # pc = 6
        :stop,
        # pc = 7
        :jumpdest,
        # pc = 8
        {:push, 1, word(3, 1)},
        # pc = 9
        :stop
      ],
      exp_stack: [
        word(2)
      ]
    },
    %{
      name: "Direct Jump - Second Path",
      code: [
        # pc = 0
        {:push, 1, word(7, 1)},
        # pc = 2
        :jump,
        # pc = 3
        :jumpdest,
        # pc = 4
        {:push, 1, word(2, 1)},
        # pc = 6
        :stop,
        # pc = 7
        :jumpdest,
        # pc = 8
        {:push, 1, word(3, 1)},
        # pc = 9
        :stop
      ],
      exp_stack: [
        word(3)
      ]
    },
    %{
      name: "Direct Jump - Invalid",
      code: [
        # pc = 0
        {:push, 1, word(1, 1)},
        # pc = 2
        :jump,
        # pc = 3
        :jumpdest,
        # pc = 4
        {:push, 1, word(2, 1)},
        # pc = 6
        :stop,
        # pc = 7
        :jumpdest,
        # pc = 8
        {:push, 1, word(3, 1)},
        # pc = 9
        :stop
      ],
      exp_error: :invalid_jump_dest
    },
    %{
      name: "Indirect Jump - Jumps",
      code: [
        # pc = 0
        {:push, 1, word(111, 1)},
        # pc = 2
        {:push, 1, word(8, 1)},
        # pc = 4
        :jumpi,
        # pc = 5
        {:push, 1, word(2, 1)},
        # pc = 7
        :stop,
        # pc = 8
        :jumpdest,
        # pc = 9
        {:push, 1, word(3, 1)},
        # pc = a
        :stop
      ],
      exp_stack: [
        word(3)
      ]
    },
    %{
      name: "Indirect Jump - Fall through",
      code: [
        # pc = 0
        {:push, 1, word(0, 1)},
        # pc = 2
        {:push, 1, word(8, 1)},
        # pc = 4
        :jumpi,
        # pc = 5
        {:push, 1, word(2, 1)},
        # pc = 7
        :stop,
        # pc = 8
        :jumpdest,
        # pc = 9
        {:push, 1, word(3, 1)},
        # pc = a
        :stop
      ],
      exp_stack: [
        word(2)
      ]
    },
    %{
      name: "Indirect Jump - Invalid Jump Dest",
      code: [
        # pc = 0
        {:push, 1, word(1, 1)},
        # pc = 2
        {:push, 1, word(0, 1)},
        # pc = 4
        :jumpi,
        # pc = 5
        {:push, 1, word(2, 1)},
        # pc = 7
        :stop,
        # pc = 8
        :jumpdest,
        # pc = 9
        {:push, 1, word(3, 1)},
        # pc = a
        :stop
      ],
      exp_error: :invalid_jump_dest
    },
    %{
      name: "PC",
      code: [
        # pc = 0
        {:push, 1, word(1, 1)},
        # pc = 2
        {:push, 1, word(0, 1)},
        # pc = 4
        :pop,
        # pc = 5
        :pop,
        # pc = 6
        :pc,
        :stop
      ],
      exp_stack: [
        word(6)
      ]
    },
    %{
      name: "MSize - 0",
      code: [
        :msize,
        :stop
      ],
      exp_stack: [
        word(0)
      ]
    },
    %{
      name: "MSize - Sized",
      code: [
        {:push, 32, word("0x112233445566778899aabbccddeeff112233445566778899aabbccddeeff1122")},
        {:push, 32, word(100)},
        :mstore,
        {:push, 32, word(110)},
        :mload,
        :pop,
        :msize,
        :stop
      ],
      exp_stack: [
        word(142)
      ]
    },
    %{
      name: "Dup1",
      code: [
        {:push, 32, word(0x100)},
        {:push, 32, word(0x101)},
        {:push, 32, word(0x102)},
        {:push, 32, word(0x103)},
        {:dup, 1},
        :stop
      ],
      exp_stack: [
        word(0x103),
        word(0x103),
        word(0x102),
        word(0x101),
        word(0x100)
      ]
    },
    %{
      name: "Dup2",
      code: [
        {:push, 32, word(0x100)},
        {:push, 32, word(0x101)},
        {:push, 32, word(0x102)},
        {:push, 32, word(0x103)},
        {:dup, 2},
        :stop
      ],
      exp_stack: [
        word(0x102),
        word(0x103),
        word(0x102),
        word(0x101),
        word(0x100)
      ]
    },
    %{
      name: "Dup - Stack Underflow",
      code: [
        {:push, 32, word(0x100)},
        {:push, 32, word(0x101)},
        {:push, 32, word(0x102)},
        {:push, 32, word(0x103)},
        {:dup, 10},
        :stop
      ],
      exp_error: :stack_underflow
    },
    %{
      name: "Swap1",
      code: [
        {:push, 32, word(0x100)},
        {:push, 32, word(0x101)},
        {:push, 32, word(0x102)},
        {:push, 32, word(0x103)},
        {:swap, 1},
        :stop
      ],
      exp_stack: [
        word(0x102),
        word(0x103),
        word(0x101),
        word(0x100)
      ]
    },
    %{
      name: "Swap2",
      code: [
        {:push, 32, word(0x100)},
        {:push, 32, word(0x101)},
        {:push, 32, word(0x102)},
        {:push, 32, word(0x103)},
        {:swap, 2},
        :stop
      ],
      exp_stack: [
        word(0x101),
        word(0x102),
        word(0x103),
        word(0x100)
      ]
    },
    %{
      name: "Swap - Stack Underflow",
      code: [
        {:push, 32, word(0x100)},
        {:push, 32, word(0x101)},
        {:push, 32, word(0x102)},
        {:push, 32, word(0x103)},
        {:swap, 10},
        :stop
      ],
      exp_error: :stack_underflow
    },
    %{
      name: "Return Value",
      code: [
        {:push, 32, word("0x112233445566778899aabbccddeeff112233445566778899aabbccddeeff1122")},
        {:push, 32, word(100)},
        :mstore,
        {:push, 32, word(10)},
        {:push, 32, word(110)},
        :return
      ],
      exp_return: ~h[0xbbccddeeff1122334455]
    },
    %{
      name: "Revert Value",
      code: [
        {:push, 32, word("0x112233445566778899aabbccddeeff112233445566778899aabbccddeeff1122")},
        {:push, 32, word(100)},
        :mstore,
        {:push, 32, word(10)},
        {:push, 32, word(110)},
        :revert
      ],
      exp_revert: ~h[0xbbccddeeff1122334455]
    },
    %{
      name: "Invalid",
      code: [
        {:invalid, word(<<0x11>>)},
        :stop
      ],
      exp_error: :invalid_operation
    }
  ]

  describe "VM Tests" do
    has_only = Enum.any?(@tests, fn t -> t[:only] end)
    here_index = Enum.find_index(@tests, fn t -> t[:here] == true end)

    for {test_info, i} <- Enum.with_index(@tests) do
      is_skip =
        test_info[:skip] == true or (has_only and not (test_info[:only] == true)) or
          (not is_nil(here_index) and i > here_index)

      test_info_escaped = Macro.escape(test_info)

      @tag if(is_skip, do: :skip, else: :ok)
      test test_info[:name] do
        t = unquote(test_info_escaped)

        exec_res =
          VM.exec(t[:code], t[:with_call_data] || <<>>, t[:with_call_value] || 0)

        if t[:exp_error] do
          case exec_res do
            {:error, error} ->
              assert t[:exp_error] == error

            _ ->
              flunk("Expected error #{inspect(t[:exp_error])}, got: #{inspect(exec_res)}")
          end
        else
          assert {:ok, execution_result} = exec_res

          if t[:exp_stack] do
            assert Enum.map(t[:exp_stack], &to_hex/1) ==
                     Enum.map(execution_result.stack, &to_hex/1)
          end

          if t[:exp_return] do
            assert not execution_result.reverted,
                   "Expected success, got revert #{inspect(execution_result)}"

            assert to_hex(t[:exp_return]) == to_hex(execution_result.return_data)
          end

          if t[:exp_revert] do
            assert execution_result.reverted,
                   "Expected revert, got success #{inspect(execution_result)}"

            assert to_hex(t[:exp_revert]) == to_hex(execution_result.return_data)
          end
        end
      end
    end
  end
end
