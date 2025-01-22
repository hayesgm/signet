
# Signet Development Doc

## Generating Signet contracts

* `i_console.ex`
  * `mix signet.gen --prefix signet/contract ./sol/out/IConsole.sol/IConsole.json`
* `sleuth.ex`
  * Clone [sleuth](https://github.com/compound-finance/sleuth) and 
  * `mix signet.gen --prefix signet/contract ../sleuth/out/Sleuth.sol/Sleuth.json`
* `test/support/{block_number,ierc20,rock}.ex`
  * `mix signet.gen --prefix signet/contract --out ./test/support/ ./test/abi/*.json`
