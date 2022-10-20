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
  var myArgs = process.argv.slice(2);
  console.log('myArgs: ', myArgs[0]);

  let name = await reverse(myArgs[0]);
  console.info("== name is: ", name)
}

main()
