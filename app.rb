require 'sinatra'
require 'sinatra/json'
require 'sinatra/subdomain'
require 'httparty'
require 'date'
require 'sinatra/custom_logger'
require 'sinatra/cross_origin'
require 'sinatra/activerecord'
require 'eth'
require 'logger'

set :logger, Logger.new('ddns_ruby.log')
disable :show_exceptions

configure do
  enable :cross_origin
end

TYPE_A = 0
TYPE_CNAME = 1
TYPE_TXT = 2
TYPE_IPFS = 3

class Record < ActiveRecord::Base
end

BLANK_VALUE = nil
# 修改这个即可， 例如 ddns.so,  test-ddns.com
#SITE_NAME = "ddns.so"
SITE_NAME = "test-ddns.com"


#IPFS_SITE_NAME = "https://ipfsgate.#{SITE_NAME}"
IPFS_SITE_NAME = ""
#ENS_SERVER_URL = 'https://ensgraph.test-pns-link.com/subgraphs/name/graphprotocol/ens'
#PNS_SERVER_URL = 'https://moonbeamgraph.test-pns-link.com/subgraphs/name/graphprotocol/pns'
PNS_SERVER_URL = 'https://pns-graph.ddns.so/subgraphs/name/graphprotocol/pns'
ENS_SERVER_URL = 'https://api.thegraph.com/subgraphs/name/ensdomains/ens'
LENS_SERVER_URL = 'https://lens-graph.ddns.so/subgraphs/name/rtomas/lens-subgraph'

# 我们约定它的 key 都是 string 类型
# 例如 @cache['bitsofcode.eth'] = 'QmfFjVBz5wd66kyd89RWkJJiWEMq1Fde3XGN9MBfx47Btp'
def my_cache
  @cache = {} if @cache == nil
  return @cache
end

# 发起http post请求
def post_request options
  server_url = options[:server_url]
  body_in_hash = options[:body_in_hash]
  logger.info "== before post request to: server_url: #{server_url} body_in_hash: #{body_in_hash}"
  response = HTTParty.post server_url,
    :headers => { 'Content-Type' => 'application/json', 'Accept' => 'application/json'},
    :body => body_in_hash.to_json

  logger.info "== response: #{response}"
  result = response.body
  return result
end

# 用来从graphql获取某个ens域名的数据
def get_data_of_ens_domain_name name, page
  response = post_request server_url: ENS_SERVER_URL,
  body_in_hash: {
    "query": %Q{query MyQuery {\n  domains(where: {name: \"#{name}\"}) {\n    id\n    labelName\n    name\n    labelhash\n    subdomains(first: 20, skip: #{(page * 20)}) {\n      id\n      name\n      subdomains {\n        name\n        labelhash\n        labelName\n      }\n    }\n    subdomainCount\n    owner {\n      id\n    }\n    parent {\n      id\n    }\n    resolvedAddress {\n      id\n      domains {\n        labelName\n        labelhash\n        name\n      }\n    }\n    ttl\n\t\tresolver {\n\t\t  id\n      contentHash\n      texts\n      address\n      coinTypes\n\t\t}\n  }\n}\n},
    "variables": nil,
    "operationName": "MyQuery"
  }
  logger.info "== response: #{response}"
  body = JSON.parse(response)
  data_of_ens_domain_name = body['data']['domains'][0]
  logger.info "===domains #{data_of_ens_domain_name}"
  return data_of_ens_domain_name
end

# 根据 domain的名字，例如 vitalik.eth 获得对应的ipfs cid
def get_domain_ipfs_cid_from_domain_name subdomain
  logger.info "==== in get_domain_ipfs_cid_from_domain_name subdomain #{subdomain}"
  subdomain_type = subdomain.split('.').last
  logger.info "=== subdomain_type #{subdomain_type}"
  result = ''
  case subdomain_type
  when 'eth'
    temp_result = get_data_of_ens_domain_name subdomain
    content_hash = temp_result['resolver']['contentHash'] rescue BLANK_VALUE
    logger.info "=== content_hash: #{content_hash}"
    command = "node get_ipfs_cid.js #{content_hash}"
    logger.info "== command: #{command}"
    result = `#{command}`
  when 'dot'
    temp_result = get_the_data_of_an_pns_domain_name_from_graphql subdomain
    temp_result_domain = JSON.parse(temp_result)['data']['domains'][0]
    temp_result_sets_to_get_records = JSON.parse(temp_result)['data']['sets']
    result_hash = get_records_for_dot_domain temp_result_sets_to_get_records
    result = result_hash['ipfs']['value']
    #raise 'not implemented'
  else
    raise 'only support .eth, .dot domain'
  end
  logger.info "======   result: #{result}"
  result = result.strip
  my_cache[subdomain] = result
  return result
end

# 根据ETH地址进行ENS的反向解析
def reverse_by_ens_name address
  command = "node reverse_name.js #{address}"
  temp_result = `#{command}`
  result = temp_result.sub("\n", "")
  return result
end

def reverse_by_pns_name address
  temp_result = post_request server_url: PNS_SERVER_URL,
    body_in_hash: {
      "query": "query MyQuery {\n  setNames(\n    first: 1\n    where: {account: \"#{address}\"}\n    orderBy: blockNumber\n    orderDirection: desc\n  ) {\n    account {\n      id\n    }\n    tokenId {\n      id\n      name\n    }\n  }\n}",
      "operationName": "MyQuery",
      "variables": nil
    }
  logger.info temp_result
  result = JSON.parse(temp_result)['data']['setNames'][0]['tokenId']['name'] rescue BLANK_VALUE
  logger.info "temp_result is #{temp_result} result reverse_pns_name is #{result}"
  return result
end

def reverse_by_bit_name address
  command = %Q{curl -X POST https://indexer-v1.did.id/v1/reverse/record -d'{"type":"blockchain","key_info":{"coin_type":"60","chain_id":"1","key":"#{address}"}}'}
  logger.info "===in reverse_by_bit_name command #{command}"
  temp_result = `#{command}`
  logger.info "=== temp_result #{temp_result}"
  result = JSON.parse(temp_result)['data']['account'] rescue BLANK_VALUE
  return result
end

# 获得ens域名的注册时间和到期时间
def get_registration_time_and_expiration_time_of_ens_domain_name domains_labelhash
  response_registration = post_request server_url: ENS_SERVER_URL,
  body_in_hash: {
    "query": "query MyQuery {\n  registration(\n    id: \"#{domains_labelhash}\"\n  ) {\n    id\n    expiryDate\n    labelName\n    registrationDate\n    cost\n  }\n}",
    "variables": nil,
    "operationName": "MyQuery"
  }
  logger.info "== response_registration: #{response_registration}"
  body_registration = JSON.parse(response_registration)
  registration = body_registration['data']['registration']
  logger.info "==registration #{registration}"
  return registration
end

# 用来从graphql获得某个pns域名的数据
def get_the_data_of_an_pns_domain_name_from_graphql name, page
  result = post_request server_url: PNS_SERVER_URL,
    body_in_hash: {
      "operationName": "MyQuery",
      "query": "query MyQuery {\n  domains(where: {name: \"#{name}\"}) {\n    labelhash\n    labelName\n    id\n    name\n    subdomains(first: 20) {\n      name\n      owner {\n        id\n      }\n    }\n    subdomainCount\n    owner {\n      id\n    }\n    parent {\n      id\n    }\n  }\n  sets(where: {domain_: {name: \"#{name}\"}}) {\n    id\n    keyHash\n    value\n  }\n  registrations(where: {labelName: \"#{name.sub(".dot", '')}\"}) {\n    expiryDate\n    events {\n      id\n      triggeredDate\n    }\n  }\n}\n",
      "variables": nil
    }
  return result
end

def get_records_for_dot_domain temp_result_sets_to_get_records
  temp_hash = {
    "dot" => '70476024645083539914866120258902002044389822943217047784978736702069848167247',
    "eth" => '77201932000687051421874801696342701541816747065578039511607412978553675800564',
    "btc" => '105640063387051144792550451261497903460441457163918809975891088748950929433065',
    "ipfs" => '109444936916467285377972213791356162468265265799777646334604004948560489512394',
    "email" => '50101170924916254227885891120695131387383646459470231890507002477095918146885',
    "notice" => '31727182724036554852371956750201584211517824919105130426252222689897810866214',
    "twitter_com" => '11710898932869919534375710263824782355793106641910621555855312720536896315685',
    "github" => '102576668688838416847107385580607409742813859881781246507337882384803237069874',
    "twitter_url" => '23368862207911262087635895660209245090921614897479706708279561601163163997039',
    "avatar" => '98593787308120460448886304499976840768878166060614499815391824681489593998420',
    "cname" => '69611991539268867131500085835156593536513732089793432642972060827780580969128'
  }
  records_of_pns_domain = {}
  temp_hash.map { |key, value|
    dot_value = []
    temp_result_sets_to_get_records.each { |e| dot_value << e if e['keyHash'] == value }
    records_of_pns_domain.store(key, (dot_value.last || ''))
  }
  logger.info "=== records_of_pns_domain: #{records_of_pns_domain}"
  return records_of_pns_domain
end

# 获得ens域名的最终结果
def get_final_result_of_ens_domain data_of_ens_domain_name, registration_data_of_ens_domain_name
  domains_resolved_address = domains['resolvedAddress']['domains'] rescue BLANK_VALUE
  result = {
    name: data_of_ens_domain_name['name'],
    nameHash: data_of_ens_domain_name['id'],
    labelName: data_of_ens_domain_name['labelName'],
    labelHash: data_of_ens_domain_name['labelhash'],
    owner: data_of_ens_domain_name['owner']['id'],
    parent: data_of_ens_domain_name['parent']['id'],
    subdomainCount: data_of_ens_domain_name['subdomainCount'],
    ttl: data_of_ens_domain_name['ttl'],
    cost: registration_data_of_ens_domain_name['cost'],
    expiryDate: Time.at(registration_data_of_ens_domain_name['expiryDate'].to_i),
    registrationDate: Time.at(registration_data_of_ens_domain_name['registrationDate'].to_i),
    # 列出了 该eth地址 注册的其他 ens域名, 暂时隐藏
    #resolvedAddress: {
    #  id: (data_of_ens_domain_name['resolvedAddress']['id'] rescue ''),
    #  data_of_ens_domain_name: data_of_ens_domain_name_resolved_address,
    #},
    records: {
      contentHash: (data_of_ens_domain_name['resolver']['contentHash'] rescue BLANK_VALUE),
      eth: data_of_ens_domain_name['owner']['id'],
      dot: BLANK_VALUE,
      btc: BLANK_VALUE,
      text: (domains['resolver']['texts'] rescue BLANK_VALUE),
      pubkey: BLANK_VALUE
    }
  } rescue BLANK_VALUE
  return result
end

# 获取pns域名的最终结果
def get_pns_json_result temp_result_domain, records_of_pns_domain, registration_data_of_pns_domain, owner_address
  result = {
    name: temp_result_domain['name'],
    nameHash: temp_result_domain['id'],
    labelName: temp_result_domain['labelName'],
    labelHash: temp_result_domain['labelhash'],
    owner: (owner_address rescue BLANK_VALUE),
    parent: temp_result_domain['parent']['id'],
    expiryDate: (Time.at(registration_data_of_pns_domain['expiryDate'].to_i) rescue BLANK_VALUE),
    registrationDate: (Time.at(registration_data_of_pns_domain['events'][0]['triggeredDate'].to_i) rescue BLANK_VALUE),
    subdomainCount: temp_result_domain['subdomainCount'],
    records: {
      dot: (records_of_pns_domain['dot']['value'] rescue BLANK_VALUE),
      eth: (records_of_pns_domain['eth']['value'] rescue BLANK_VALUE),
      btc: (records_of_pns_domain['btc']['value'] rescue BLANK_VALUE),
      ipfs: (records_of_pns_domain['ipfs']['value'] rescue BLANK_VALUE),
      email: (records_of_pns_domain['email']['value'] rescue BLANK_VALUE),
      notice: (records_of_pns_domain['notice']['value'] rescue BLANK_VALUE),
      twitter: (records_of_pns_domain['twitter_com']['value'] rescue BLANK_VALUE),
      github: (records_of_pns_domain['github']['value'] rescue BLANK_VALUE),
      url: (records_of_pns_domain['twitter_url']['value'] rescue BLANK_VALUE),
      avatar: (records_of_pns_domain['avatar']['value'] rescue BLANK_VALUE),
      cname: (records_of_pns_domain['cname']['value'] rescue BLANK_VALUE)
    }
  } rescue BLANK_VALUE
end

def get_ens_domain_names_from_address address
  temp_result = post_request server_url: ENS_SERVER_URL,
    body_in_hash: {
      "operationName": "MyQuery",
      "query": "query MyQuery {\n account(id: \"#{address.downcase}\") {\n id\n domains {\n name\n labelhash\n }\n }\n}\n",
      "variables": nil
    }
  logger.info "===temp_result in ens#{temp_result}"
  result = JSON.parse(temp_result)['data']['account']['domains'].map{ |e| e["name"] } rescue []
  logger.info "===result in ens#{result}"
  return result
end

def get_pns_domain_names_from_address address
  temp_result = post_request server_url: PNS_SERVER_URL,
    body_in_hash: {
      "operationName": "MyQuery",
      "query": "query MyQuery {\n  domains(where: {owner: \"#{address.downcase}\"}) {\n    name\n    labelhash\n    labelName\n    id\n    createdAt\n  }\n}\n",
      "variables": nil
    }
  logger.info "===temp_result in pns#{temp_result}"
  result = JSON.parse(temp_result)['data']['domains'].map{ |e| e["name"] } rescue []
  logger.info "===result in pns#{result}"
  return result
end

def get_bit_domain_names_from_address address
  command = %Q{curl -X POST https://indexer-v1.did.id/v1/account/list -d'{"type":"blockchain","key_info":{"coin_type":"60","chain_id":"1","key":"#{address}"}}'}
  temp_result = `#{command}`
  logger.info "=== in get_bit_domain_names_from_address command #{command} temp_result #{temp_result}"
  result = JSON.parse(temp_result)['data']['account_list'].map{ |e| e["account"] } rescue []
  logger.info "===result in bit#{result}"
  return result
end

def get_data_of_lens_domain_name name
  response = post_request server_url: LENS_SERVER_URL,
  body_in_hash: {
    "query": "query MyQuery {\n profiles(first: 10, where: {handle:\"#{name}\"}) {\n   handle\n   id\n   imageURI\n   lastUpdated\n   profileId\n   totalComments\n   totalFollowings\n   totalFollowers\n   totalMirrors\n   totalPosts\n   owner {\n   id\n }\n }\n }",
    "variables": nil,
    "operationName": "MyQuery"
  }
  logger.info "== response: #{response}"
  body = JSON.parse(response)
  data_of_lens_domain_name = body['data']['profiles'][0]
  logger.info "===domains #{data_of_lens_domain_name}"
  return data_of_lens_domain_name
end

def get_result_from_graphql_when_ens_domain name, subdomains, page
  temp_data_of_ens_domain_name = get_data_of_ens_domain_name name, page
  logger.info "==temp_data_of_ens_domain_name #{temp_data_of_ens_domain_name} subdomains #{subdomains}"
  temp_registration_data_of_ens_domain = get_registration_time_and_expiration_time_of_ens_domain_name temp_data_of_ens_domain_name['labelhash'] rescue BLANK_VALUE
  result = get_final_result_of_ens_domain temp_data_of_ens_domain_name, temp_registration_data_of_ens_domain
  result['subdomains'] = temp_data_of_ens_domain_name['subdomains'] if subdomains == 'yes'
  logger.info "=== after add subdomains result : #{result}"
  return result
end

def get_result_when_lens_domain name, subdomains
  temp_data_of_lens_domain_name = get_data_of_lens_domain_name name

  result = {
    handle: name,
    id: temp_data_of_lens_domain_name['id'],
    imageURI: temp_data_of_lens_domain_name['imageURI'],
    lastUpdated: "#{Time.at(temp_data_of_lens_domain_name['lastUpdated'].to_i).to_s}",
    profileId: temp_data_of_lens_domain_name['profileId'],
    totalComments: temp_data_of_lens_domain_name['totalComments'],
    totalFollowings: temp_data_of_lens_domain_name['totalFollowings'],
    totalFollowers: temp_data_of_lens_domain_name['totalFollowers'],
    totalMirrors: temp_data_of_lens_domain_name['totalMirrors'],
    totalPosts: temp_data_of_lens_domain_name['totalPosts'],
    owner: temp_data_of_lens_domain_name['owner']['id'],
  }
  return result
end

def get_result_from_graphql_when_pns_domain name, subdomains, page
  temp_result = get_the_data_of_an_pns_domain_name_from_graphql name, page
  data_of_an_pns_domain_name = JSON.parse(temp_result)['data']['domains'][0]
  owner_address = data_of_an_pns_domain_name['owner']['id'] rescue BLANK_VALUE
  temp_result_sets_to_get_records = JSON.parse(temp_result)['data']['sets']
  registration_data_of_pns_domain = JSON.parse(temp_result)['data']['registrations'][0]
  records_of_pns_domain = get_records_for_dot_domain temp_result_sets_to_get_records
  result = get_pns_json_result data_of_an_pns_domain_name, records_of_pns_domain, registration_data_of_pns_domain, owner_address
  logger.info "=== subdomains #{subdomains} before add subdomains result : #{result}"
  if data_of_an_pns_domain_name != nil
    data_of_an_pns_domain_name['subdomains'].each do |subdomain|
      subdomain['owner'] = subdomain['owner']['id']
    end
  end
  result['subdomains'] = data_of_an_pns_domain_name['subdomains'] if subdomains == 'yes'
  logger.info "=== after add subdomains result : #{result}"
  return result
end

def get_result_when_bit_domain name, subdomains, page
  command = %Q{curl -X POST https://indexer-v1.did.id/v1/sub/account/list -d'{"account":"#{name}","page":#{page},"size":20}'}
  temp_result = `#{command}`
  temp_subdomains_data = JSON.parse(temp_result)
  logger.info "=== command #{command} return data #{temp_subdomains_data}"

  command_to_get_records = %Q{curl -X POST https://indexer-v1.did.id/v1/account/records -d'{"account":"#{name}"}'}
  return_records_data = `#{command_to_get_records}`
  logger.info "=== command_to_get_records #{command_to_get_records} return_records_data #{return_records_data}"
  temp_records = JSON.parse(return_records_data)['data']['records']
  logger.info "=== temp_records #{temp_records}"

  command_to_get_account_info = %Q{curl -X POST https://indexer-v1.did.id/v1/account/info -d'{"account":"#{name}"}'}
  return_account_info_data = `#{command_to_get_account_info}`
  logger.info "=== command_to_get_account_info #{command_to_get_account_info} return_account_info_data #{return_account_info_data}"
  temp_account_data = JSON.parse(return_account_info_data)
  logger.info "=== temp_account_data #{temp_account_data}"
  owner = temp_account_data['data']['account_info']['owner_key']
  created_at = temp_account_data['data']['account_info']['create_at_unix']
  expired_at = temp_account_data['data']['account_info']['expired_at_unix']
  temp_name_hash= temp_account_data['data']['out_point']['tx_hash']
  logger.info "== owner #{owner} created_at #{created_at} expired_at #{expired_at} temp_name_hash #{temp_name_hash}"

  subdomain_count = temp_subdomains_data['data']['sub_account_total']
  temp_subdomains = temp_subdomains_data['data']['sub_account_list']
  logger.info "=== temp_subdomains #{temp_subdomains.inspect} temp_name_hash #{temp_name_hash}"

  show_subdomains = BLANK_VALUE
  if temp_subdomains.present?
    show_subdomains = temp_subdomains.map {|e|
      {
        name: e['account'],
        owner: e['owner_key']
      }
    }
    puts "==== in subdomains "
  end

  records = BLANK_VALUE
  if temp_records.present?
    records = temp_records.map { |e|
      logger.info "==== e #{e}"
      {
        name: "#{e['key'].to_s.split(".").last}",
        value: e['value']
      }
    }
  end
  logger.info "== records #{records}"

  result = {
    name: name,
    nameHash: temp_name_hash,
    labelName: name.split('.').first,
    labelHash: BLANK_VALUE,
    owner: owner,
    parent: BLANK_VALUE,
    subdomainCount: subdomain_count,
    ttl: BLANK_VALUE,
    cost: BLANK_VALUE,
    expiryDate: "#{Time.at(expired_at.to_i).to_s}",
    registrationDate: "#{Time.at(created_at.to_i).to_s}",
    records: records,
  } rescue BLANK_VALUE
  result['subdomains'] = show_subdomains if subdomains == 'yes'
  return result
end

# example:
# nft_id: 0xcc942b3e781ca36eba0d59bb1afc88cc1ff0d1b7dc54c5aba3c112f4387b6e23
# return:
# {
#  "data": {
#    "domains": [
#      {
#        "id": "0xcc942b3e781ca36eba0d59bb1afc88cc1ff0d1b7dc54c5aba3c112f4387b6e23",
#        "name": "ttt112.dot"
#      }
#    ]
#  }
# }
def get_domain_name_by_nft_id nft_id
  temp_result = post_request server_url: PNS_SERVER_URL,
    body_in_hash: {
      "query":"query MyQuery {\n  domains(\n    where: {id: \"#{nft_id}\"}\n  ) {\n    id\n    name\n    labelhash\n    labelName\n  }\n}\n",
      "variables": nil,
      "operationName":"MyQuery"
    }

  result = JSON.parse(temp_result)['data']['domains'][0]['name'] rescue nil
  return result
end

# 确定显示逻辑。
def display_the_logic_of_the_page cid, subdomain
  logger.info "=== subdomain: #{subdomain} cid: #{cid}"

  # step1. 如果有cid, 就展示内容
  if cid != '' && cid != nil
    #url = "#{IPFS_SITE_NAME}/ipfs/#{cid}"
    logger.info "== cid: #{cid}"
    logger.info "== request.referer: #{request.referrer}, inspect: #{request.referrer == nil}"

    url = ''

    # referrer: 基本就是 nil 或者
    #
    # e.g. https://bitsofcode.eth.ddns.so/
    if request.referrer != nil
      # TODO 这里不用了
      # 传入的应该是 vitalik.eth.ddns.so/css/a.css   所以 fullpath = css/a.css
      #url = request.referrer + request.fullpath.gsub('/ipfs', '')
      url = request.referrer + request.fullpath.gsub('/ipfs', '')
    else
      url = "https://cloudflare-ipfs.com/" + "ipfs/" + cid
    end

    logger.info "=== url is: #{url}"
    response = HTTParty.get url

    status 200

    # 这里特别重要
    my_headers = {'content-type' => response.headers['content-type']}
    headers my_headers
    logger.info "== -- body: #{response.body}"
    body response.body
    # 这个return也是必须的
    return

  # step2.如果域名有cname, 就展示
  elsif (record_cname = Record.where('domain_name = ? and record_type = ?', subdomain, TYPE_CNAME).first) && record_cname.present?
    url = "https://#{record_cname.content}"
    logger.info "=== url #{url} record_cname is #{record_cname.inspect}"

  # step3.如果域名有A记录, 就展示
  elsif (record_a = Record.where('domain_name = ? and record_type = ?', subdomain, TYPE_A).first) && record_a.present?
    url = "https://#{record_a.content}"
    logger.info "=== url #{url} record_a is #{record_a.inspect}"

  # step4.如果域名有ipfs, 就展示
  elsif (record_ipfs = Record.where('domain_name = ? and record_type = ?', subdomain, TYPE_IPFS).first) && record_ipfs.present?
    url = record_ipfs.content
    logger.info "=== record_ipfs is #{record_ipfs.inspect} url #{url}"

  # step5.如果都没有，就展示web3profile页面
  else
    url = "https://#{subdomain.sub("eth", "dot")}.site/"
  end
  redirect to(url)
end

def display_css_js_files cid
  logger.info "== in display_css_js_files: cid: #{cid}"
  logger.info "== request.referer: #{request.referrer}, inspect: #{request.referrer == nil}"

  url = "https://cloudflare-ipfs.com/" + "ipfs/" + cid + request.fullpath

  logger.info "=== url is: #{url}"
  response = HTTParty.get url

  status 200

  # 这里特别重要
  my_headers = {'content-type' => response.headers['content-type']}
  headers my_headers
  logger.info "== -- body: #{response.body[1..100]}"
  body response.body
end

# 本方法 本来应该直接调用 dig @localhost -p 2346
# 但是由于， type 会存在 ipfs 类型，不被 2346 app所支持
# 所以需要在这里先进行对于 'ipfs'的查询
# CNAME: 也需要放在这里处理，因为格式不同（2346 app需要它是个array)
#
# 如果type是ipfs/cname  就从数据库取数据
# 否则，就走2346端口
def get_domain_ip name, type
  type_name = ''
  if type == 'ipfs'
    type_name = TYPE_IPFS
  elsif type == 'cname'
    type_name = TYPE_CNAME
  end

  if type_name.present?
    record_local = Record.where('domain_name = ? and record_type = ?', name, type_name).first
  end

  result = ''
  if record_local.present? || ( type == 'ipfs' && record_local.blank? )
    result = record_local.content rescue ''
  else
    command = "dig @localhost -p 2346 #{name} #{type}"
    logger.info "=== command #{command}"
    result = `#{command}`
    logger.info "=== result #{result}"
    temp_result = result.gsub /^$\n/, ''
    temp_array = temp_result.split('\n')
    temp_domain_data = temp_array.map { |a|
      a.split("\n").reject { |e|
        e =~ /;/
      }
    }
    temp_result = temp_domain_data.to_s.split('\\t').last.sub('"]]', '')
    if type == 'txt'
      result = temp_result.gsub('\\"', '')
    elsif type == 'cname'
      temp_time = temp_result[-32, 32]
      result = temp_result.split(temp_time)
    else
      type = 'a'
      result = temp_result
    end
  end

  data = {
    domain_name: name,
    value: result,
    type: type
  }

  return data
end

# 用于解决浏览器的报错问题
get '/favicon.ico' do
  send_file 'favicon.ico'
end


# 对于 api.ddns.so 的配置
subdomain :api do
  get "/name/:name" do
    name = params[:name]
    subdomains = params[:subdomains]
    page = params[:page].to_i
    logger.info "===before= page #{page}"
    page = 1 if page == 0
    logger.info "===after= page #{page}"
    subdomain_type = name.split('.').last
    case subdomain_type
    when 'eth'
      data = get_result_from_graphql_when_ens_domain name, subdomains, page
      json({
        result: 'ok',
        data: data
      })

    when 'dot'
      data = get_result_from_graphql_when_pns_domain name, subdomains, page
      json({
        result: 'ok',
        data: data
      })

    when 'bit'
      data = get_result_when_bit_domain name, subdomains, page
      json({
        result: 'ok',
        data: data
      })

    when 'lens'
      data = get_result_when_lens_domain name, subdomains
      json({
        result: 'ok',
        data: data
      })
    else
      'only support .eth, .dot .bit domain'
    end

  end

  # type参数：可用的是  ens/pns
  # 使用例子：  /reverse/ens/0xa1b2c3d4
  # 使用例子：  /reverse/pns/0xa1b2c3d4
  # 根据某个地址，找到它的所有的注册的域名
  get '/reverse/:type/:address' do
    address = params[:address]
    if address == nil || address == ''
      halt 404, 'page not found(address is missing) '
    end
    result = nil
    if params[:type] == 'ens'
      result = reverse_by_ens_name address rescue BLANK_VALUE
    elsif params[:type] == 'pns'
      result = reverse_by_pns_name address rescue BLANK_VALUE
    else
      result = reverse_by_bit_name address rescue BLANK_VALUE
    end
    logger.info "result : #{result}"

    json({
      result: 'ok',
      address: address,
      data: result
    })

  end

  # 根据某个地址获得该地址的所有 域名（ens + pns)
  # 参数：
  # address: 地址
  # type: 地址的类型，目前仅支持 eth, pns
  get '/get_all_domain_names/:address' do
    address = params[:address]
    if address == nil || address == ''
      halt 404, 'page not found(address is missing) '
    end
    data_ens = get_ens_domain_names_from_address address
    data_pns = get_pns_domain_names_from_address address
    data_bit = get_bit_domain_names_from_address address
    data = data_ens + data_pns + data_bit
    logger.info "data_ens#{data_ens} data_pns#{data_pns} data_bit #{data_bit}data : #{data}"

    json({
      result: 'ok',
      address: address,
      data: data
    })
  end

  # 根据 nft_id  获得某个域名的信息
  get '/query_by_nft_id/:type/:nft_id' do
    result = nil
    domain_name = nil
    case params[:type]
    when 'pns'
      result = {
        result: 'ok',
        data: get_domain_name_by_nft_id(params[:nft_id])
      }
    else
      result = {
        result: 'not support',
        data: nil
      }
    end
    json(result)
  end

  get '/domain/:name' do
    data = get_domain_ip params[:name], params[:type]

    json({
      result: 'ok',
      data: data
    })
  end

end


# 用来访问 www.ddns.so , ddns.so
subdomain [:www, nil] do
  get '/' do
    json result: "Hi there~, subdomain is: #{subdomain}"
  end
end

# 用来访问 vitalik.eth.ddns.so
# 处理 ens, pns
subdomain do
  get '/*' do

    cid = get_domain_ipfs_cid_from_domain_name subdomain rescue ''
    if request.fullpath == '/'
      display_the_logic_of_the_page cid, subdomain
    else
      display_css_js_files cid
    end
  end

  get '/ipfs/*' do
    logger.info "== request.referer: #{request.referrer}, inspect: #{request.referrer == nil}"

    url = ''
    if request.referrer != nil
      url = request.referrer + request.fullpath.gsub('/ipfs', '')
    else
      url = "https://cloudflare-ipfs.com/" + request.fullpath
    end

    logger.info "=== url is: #{url}"
    response = HTTParty.get url

    status 200

    # 这里特别重要
    my_headers = {'content-type' => response.headers['content-type']}
    headers my_headers

    body response.body
  end
end

