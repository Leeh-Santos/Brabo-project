forge script script/DeployFundMe.s.sol --rpc-url $BASEMAIN --private-key $KEY --broadcast --verify --etherscan-api-key $ETHERSCANTOKEN --verifier-url $SCANURL -vvvv

forge inspect src/FundMe.sol:FundMe abi > fundmepoha 

== Return == -- OLD
0: contract FundMe 0x97583D6A71dBc2d7352a6193C9179E1117Cc1aBe
1: contract NftBrabo 0x90684085D126d0C39cEB74DB2Ccadf3100ef29DA


                                                                           

== Return ==
0: contract FundMe 0x8D9f0f0CA6CeD2177d4E95AEA3130b484F9aFC0f
1: contract NftBrabo 0x38F3BCe6Ebf6B27d2af76b3a69858C2e4913B8c3