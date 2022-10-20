const Web3 = require('web3');
const web3 = new Web3('https://mainnet.infura.io/v3/6d5b3edb39ed4ac39731a6f107540942');

var namehash = require('@ensdomains/eth-ens-namehash')

async function reverse(address) {
  var lookup=address.toLowerCase().substr(2) + '.addr.reverse'
  var ResolverContract=await web3.eth.ens.resolver(lookup);
  var nh=namehash.hash(lookup);
  var name=await ResolverContract.methods.name(nh).call()
  return name;
}

async function main(){

  let name = await reverse('0x0b23E3588c906C3F723C58Ef4d6baEe7840A977c');
  console.info("== name is: ", name)
}

main()
