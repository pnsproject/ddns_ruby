require 'sinatra'
require 'sinatra/json'
require 'sinatra/subdomain'
require 'httparty'
require 'date'
require 'sinatra/custom_logger'
require 'sinatra/cross_origin'

require 'eth'
require 'logger'
require 'active_record'

set :logger, Logger.new('ddns_ruby.log')
disable :show_exceptions

configure do
  enable :cross_origin
end

password = 'eadd2f80c59511f3f73388d9d898277224fd623c689f232097a886500ad1118022ba7a01683c1df2053c09e964e09e3bb539ad815031dd464cd17c143859a24c'
host = '172.17.0.3'
ActiveRecord::Base.establish_connection(adapter: 'postgresql', pool: "#{ENV["DATABASE_POOL"] || 64}", timeout: 5000, encoding: 'utf-8', host: "#{host}", user: 'postgres', username: 'postgres', password: "#{password}", port: 5432, database: 'ddns_rails')

KYPE_CNAME = 1
KYPE_A = 0
KYPE_IPFS = 3

class Record < ActiveRecord::Base
end


BLANK_VALUE = nil
# 修改这个即可， 例如 ddns.so,  test-ddns.com
SITE_NAME = "ddns.so"

#IPFS_SITE_NAME = "https://ipfsgate.#{SITE_NAME}"
IPFS_SITE_NAME = ""
#ENS_SERVER_URL = 'https://ensgraph.test-pns-link.com/subgraphs/name/graphprotocol/ens'
PNS_SERVER_URL = 'https://moonbeamgraph.test-pns-link.com/subgraphs/name/graphprotocol/pns'
ENS_SERVER_URL = 'https://api.thegraph.com/subgraphs/name/ensdomains/ens'

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

#用来从graphql获取某个ens域名的数据
def get_data_of_ens_domain_name name
  response = post_request server_url: ENS_SERVER_URL,
  body_in_hash: {
    "query":"query MyQuery {\n  domains(where: {name: \"#{name}\"}) {\n    id\n    labelName\n    name\n    labelhash\n    subdomains {\n      id\n      name\n      subdomains {\n        name\n        labelhash\n        labelName\n      }\n    }\n    subdomainCount\n    owner {\n      id\n    }\n    parent {\n      id\n    }\n    resolvedAddress {\n      id\n      domains {\n        labelName\n        labelhash\n        name\n      }\n    }\n    ttl\n\t\tresolver {\n\t\t  id\n      contentHash\n      texts\n      address\n      coinTypes\n\t\t}\n  }\n}\n",
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
  logger.info "==== in get_domain_ipfs_cid_from_domain_name"
  subdomain_type = subdomain.split('.').last
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
    temp_result = get_temp_result_for_pns_domain subdomain
    temp_result_domain = JSON.parse(temp_result)['data']['domains'][0]
    temp_result_sets_to_get_records = JSON.parse(temp_result)['data']['sets']
    result_registration = JSON.parse(temp_result)['data']['registrations'][0]
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


#获得ens域名的注册时间和到期时间
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

#用来从graphql获得某个pns域名的数据
def get_the_data_of_an_pns_domain_name_from_graphql name
  result = post_request server_url: PNS_SERVER_URL,
    body_in_hash: {
      "operationName": "MyQuery",
      "query": "query MyQuery {\n  domains(where: {name: \"#{name}\"}) {\n    labelhash\n    labelName\n    id\n    name\n    subdomains {\n      name\n      owner {\n        id\n      }\n    }\n    subdomainCount\n    owner {\n      id\n    }\n    parent {\n      id\n    }\n  }\n  sets(where: {domain_: {name: \"#{name}\"}}) {\n    id\n    keyHash\n    value\n  }\n  registrations(where: {labelName: \"#{name.sub(".dot", '')}\"}) {\n    expiryDate\n    events {\n      id\n      triggeredDate\n    }\n  }\n}\n",
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

#获得ens域名的最终结果
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

#获取pns域名的最终结果
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
  result = JSON.parse(temp_result)['data']['account']['domains'].map{ |e| e["name"] } rescue BLANK_VALUE
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
  result = JSON.parse(temp_result)['data']['domains'].map{ |e| e["name"] } rescue BLANK_VALUE
  logger.info "===result in pns#{result}"
  return result
end

def get_result_from_graphql_when_ens_domain name, is_show_subdomains
  temp_data_of_ens_domain_name = get_data_of_ens_domain_name name
  logger.info "==temp_data_of_ens_domain_name #{temp_data_of_ens_domain_name} is_show_subdomains #{is_show_subdomains}"
  temp_registration_data_of_ens_domain = get_registration_time_and_expiration_time_of_ens_domain_name temp_data_of_ens_domain_name['labelhash'] rescue BLANK_VALUE
  result = get_final_result_of_ens_domain temp_data_of_ens_domain_name, temp_registration_data_of_ens_domain
  result['subdomains'] = temp_data_of_ens_domain_name['subdomains'] if is_show_subdomains == 'yes'
  logger.info "=== after add subdomains result : #{result}"
  return result
end

def get_result_from_graphql_when_pns_domain name, is_show_subdomains
  temp_result = get_the_data_of_an_pns_domain_name_from_graphql name
  data_of_an_pns_domain_name = JSON.parse(temp_result)['data']['domains'][0]
  owner_address = data_of_an_pns_domain_name['owner']['id'] rescue BLANK_VALUE
  temp_result_sets_to_get_records = JSON.parse(temp_result)['data']['sets']
  registration_data_of_pns_domain = JSON.parse(temp_result)['data']['registrations'][0]
  records_of_pns_domain = get_records_for_dot_domain temp_result_sets_to_get_records
  result = get_pns_json_result data_of_an_pns_domain_name, records_of_pns_domain, registration_data_of_pns_domain, owner_address
  logger.info "=== is_show_subdomains #{is_show_subdomains} before add subdomains result : #{result}"
  if data_of_an_pns_domain_name != nil
    data_of_an_pns_domain_name['subdomains'].each do |subdomain|
      subdomain['owner'] = subdomain['owner']['id']
    end
  end
  result['subdomains'] = data_of_an_pns_domain_name['subdomains'] if is_show_subdomains == 'yes'
  logger.info "=== after add subdomains result : #{result}"
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
  elsif (record_cname = Record.where('domain_name = ? and record_type = ?', subdomain, KYPE_CNAME).first) && record_cname.present?
    url = "https://#{record_cname.content}"
    logger.info "=== url #{url} record_cname is #{record_cname.inspect}"

  # step3.如果域名有A记录, 就展示
  elsif (record_a = Record.where('domain_name = ? and record_type = ?', subdomain, KYPE_A).first) && record_a.present?
    url = "https://#{record_a.content}"
    logger.info "=== url #{url} record_a is #{record_a.inspect}"

  # step4.如果域名有ipfs, 就展示
  elsif (record_ipfs = Record.where('domain_name = ? and record_type = ?', subdomain, KYPE_IPFS).first) && record_ipfs.present?
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

# 用于解决浏览器的报错问题
get '/favicon.ico' do
  send_file 'favicon.ico'
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

# 对于 api.ddns.so 的配置
subdomain :api do
  get "/name/:name" do
    name = params[:name]
    is_show_subdomains = params[:is_show_subdomains]
    subdomain_type = name.split('.').last
    case subdomain_type
    when 'eth'
      data = get_result_from_graphql_when_ens_domain name, is_show_subdomains
      json({
        result: 'ok',
        data: data
      })

    when 'dot'
      data = get_result_from_graphql_when_pns_domain name, is_show_subdomains
      json({
        result: 'ok',
        data: data
      })
    else
      'only support .eth, .dot domain'
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
    else
      result = reverse_by_pns_name address rescue BLANK_VALUE
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
    if params[:type] == 'eth'
      data = get_ens_domain_names_from_address address
    else
      data = get_pns_domain_names_from_address address
    end
    logger.info "data : #{data}"

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

end



