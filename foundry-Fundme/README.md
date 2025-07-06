[⠊] Compiling...
No files changed, compilation skipped
Traces:
  [7821953] DeployFundme::run()
    ├─ [0] VM::envAddress("PICA") [staticcall]
    │   └─ ← [Return] <env var value>
    ├─ [0] VM::startBroadcast()
    │   └─ ← [Return] 
    ├─ [0] VM::readFile("./img/bronze.svg") [staticcall]
    │   └─ ← [Return] <file>
    ├─ [0] VM::readFile("./img/silver.svg") [staticcall]
    │   └─ ← [Return] <file>
    ├─ [0] VM::readFile("./img/gold.svg") [staticcall]
    │   └─ ← [Return] <file>
    ├─ [6352350] → new NftBrabo@0xcdDC9342Fb184BcC28b274B3629Ae1a773bf378A
    │   └─ ← [Return] 7202 bytes of code
    ├─ [959239] → new FundMe@0x2aDbEa927A0f06536439Ed2FD8Ef3Fca51d31756
    │   └─ ← [Return] 4677 bytes of code
    ├─ [22532] NftBrabo::setMinterContract(FundMe: [0x2aDbEa927A0f06536439Ed2FD8Ef3Fca51d31756])
    │   └─ ← [Stop] 
    ├─ [0] VM::stopBroadcast()
    │   └─ ← [Return] 
    ├─ [0] console::log("\n Deployment Complete!") [staticcall]
    │   └─ ← [Stop] 
    ├─ [0] console::log("MoodNft:", NftBrabo: [0xcdDC9342Fb184BcC28b274B3629Ae1a773bf378A]) [staticcall]
    │   └─ ← [Stop] 
    ├─ [0] console::log("FundMe:", FundMe: [0x2aDbEa927A0f06536439Ed2FD8Ef3Fca51d31756]) [staticcall]
    │   └─ ← [Stop] 
    ├─ [0] console::log("\n  IMPORTANT: You need to manually transfer PicaTokens to the FundMe contract!") [staticcall]
    │   └─ ← [Stop] 
    ├─ [0] console::log("    FundMe address:", FundMe: [0x2aDbEa927A0f06536439Ed2FD8Ef3Fca51d31756]) [staticcall]
    │   └─ ← [Stop] 
    ├─ [0] console::log("    Recommended amount: 100,000 PCT or more") [staticcall]
    │   └─ ← [Stop] 
    ├─ [0] console::log("\nTo transfer tokens using MetaMask:") [staticcall]
    │   └─ ← [Stop] 
    ├─ [0] console::log("1. Open MetaMask and select your account with PicaTokens") [staticcall]
    │   └─ ← [Stop] 
    ├─ [0] console::log("2. Click on the PicaToken in your assets") [staticcall]
    │   └─ ← [Stop] 
    ├─ [0] console::log("3. Click 'Send'") [staticcall]
    │   └─ ← [Stop] 
    ├─ [0] console::log("4. Paste the FundMe address:", FundMe: [0x2aDbEa927A0f06536439Ed2FD8Ef3Fca51d31756]) [staticcall]
    │   └─ ← [Stop] 
    ├─ [0] console::log("5. Enter the amount you want to transfer") [staticcall]
    │   └─ ← [Stop] 
    ├─ [0] console::log("6. Confirm the transaction") [staticcall]
    │   └─ ← [Stop] 
    ├─ [0] console::log("\nSave these addresses for future interactions!") [staticcall]
    │   └─ ← [Stop] 
    └─ ← [Return] FundMe: [0x2aDbEa927A0f06536439Ed2FD8Ef3Fca51d31756], NftBrabo: [0xcdDC9342Fb184BcC28b274B3629Ae1a773bf378A]


Script ran successfully.

== Return ==
0: contract FundMe 0x2aDbEa927A0f06536439Ed2FD8Ef3Fca51d31756
1: contract NftBrabo 0xcdDC9342Fb184BcC28b274B3629Ae1a773bf378A
PICA_TOKEN: 0xa7B99dB6E210A5b8acc94D4eD2094886a7037773

== Logs ==
  
 Deployment Complete!
  MoodNft: 0xcdDC9342Fb184BcC28b274B3629Ae1a773bf378A
  FundMe: 0x2aDbEa927A0f06536439Ed2FD8Ef3Fca51d31756
  
  IMPORTANT: You need to manually transfer PicaTokens to the FundMe contract!
      FundMe address: 0x2aDbEa927A0f06536439Ed2FD8Ef3Fca51d31756
      Recommended amount: 100,000 PCT or more
  
To transfer tokens using MetaMask:
  1. Open MetaMask and select your account with PicaTokens
  2. Click on the PicaToken in your assets
  3. Click 'Send'
  4. Paste the FundMe address: 0x2aDbEa927A0f06536439Ed2FD8Ef3Fca51d31756
  5. Enter the amount you want to transfer
  6. Confirm the transaction
  
Save these addresses for future interactions!

## Setting up 1 EVM.
==========================
Simulated On-chain Traces:

  [6352350] → new NftBrabo@0xcdDC9342Fb184BcC28b274B3629Ae1a773bf378A
    └─ ← [Return] 7202 bytes of code

  [959239] → new FundMe@0x2aDbEa927A0f06536439Ed2FD8Ef3Fca51d31756
    └─ ← [Return] 4677 bytes of code

  [22532] NftBrabo::setMinterContract(FundMe: [0x2aDbEa927A0f06536439Ed2FD8Ef3Fca51d31756])
    └─ ← [Stop] 


==========================

Chain 11155111

Estimated gas price: 0.000500588 gwei

Estimated total gas used for script: 10110135

Estimated amount required: 0.00000506101225938 ETH

==========================

##### sepolia
✅  [Success] Hash: 0x4576dc3ea7f6627d22057f08651312cdb663dbf8ab3be738c97a10116f9dc842
Contract Address: 0xcdDC9342Fb184BcC28b274B3629Ae1a773bf378A
Block: 8560730
Paid: 0.000003325507947188 ETH (6643814 gas * 0.000500542 gwei)


##### sepolia
✅  [Success] Hash: 0x79cdb819aeff612b3ce352e7a3de7b3b4310f2d6470260d42a693cc40d3593a6
Contract Address: 0x2aDbEa927A0f06536439Ed2FD8Ef3Fca51d31756
Block: 8560733
Paid: 0.00000054384907665 ETH (1086503 gas * 0.00050055 gwei)


##### sepolia
✅  [Success] Hash: 0x6e08a18a4e0ebefa535aee1de50397f65be2f17dce8fb19722a7583ea1e0e319
Block: 8560738
Paid: 0.00000002200596038 ETH (43964 gas * 0.000500545 gwei)

✅ Sequence #1 on sepolia | Total Paid: 0.000003891362984218 ETH (7774281 gas * avg 0.000500545 gwei)
                                                                                                                                                                  

==========================

ONCHAIN EXECUTION COMPLETE & SUCCESSFUL.




    




170119971



a poupança com um seguro mais barato pode ser superior ao custo do agravamento do spread

contratos onde não houve bonificação ao manter os seguros no banco,

Se este último caso é o seu e quer fazer uma transferência do seguro de vida, o melhor é ponderar as duas situações, que seguro proposto lhe trará mais vantagens e, se for pela poupança, fazer as contas para perceber em qual das situações vai ficar a pagar menos pelo bolo todo, no geral.


--****SO VALE A PENA SE FOR MAIS BARATO A PARTIR DE AGORA 27.30

, spread tao foda assim??  mudar de seguro tanka com aumento do spread? 
 12 anos  --- +40 reduz metade 
IF WE SELL IN 12 YEARS FUCK IT not woth it


YOU HAVE TO BE REALLY FUCKING OLD TO BE FUCKED UP



2500 - 4 anos, so para trocar

se for metade - 4 anos 720

PROJECAO 12 ANOS

4800 + 1440 + 1164 = 7404 banco comecando 27 subindo gradual = 3.7402 + 2500 = 6200

se alarme 2500 e se 

27(324) 30(360) 40(480) 50(600) 50(600) 50(600) 50(600) 50(600) 50(600) 50(600) 50(600) 60(720) - 40Y 60(720)

15 15 20 25 25 25 25 25 25 25 25 30 30

DIFERENCIA TEM QUE SER MUITO BOA 2500 E TROCA DE SEGURA

SO SE FOR METADE



if (half(4x720)){
  dale;
}

