const contentHash = require('content-hash')

function main(){
  const myArgs = process.argv.slice(2);
  let content_hash_bytes_string = myArgs[0]
  let result_type = myArgs[1] || 'v0'
  content_hash_bytes_string = content_hash_bytes_string.replace('0x','')
  let v0_result = contentHash.decode(content_hash_bytes_string)
  let v1_result = contentHash.helpers.cidV0ToV1Base32(v0_result)
  let result = result_type == 'v0' ? v0_result : v1_result
  console.info(result)
}

/*
 *
 * 把一个 0x 开头的字符串转换成ipfs可以理解的cid
 *
 * 使用方式：
 * node get_ipfs_cid.js '0xe30101701220d26f29c6d794c4957392c052bacd274b5d32790640c3ffec9fed0c32d8deccf9'
 * node get_ipfs_cid.js '0xe30101701220d26f29c6d794c4957392c052bacd274b5d32790640c3ffec9fed0c32d8deccf9' v1
 *
 */
main()
