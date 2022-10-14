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

puts "===Record.all.size #{Record.all.size}"

BLANK_VALUE = nil
# 修改这个即可， 例如 ddns.so,  test-ddns.com
SITE_NAME = "ddns.so"

#IPFS_SITE_NAME = "https://ipfsgate.#{SITE_NAME}"
IPFS_SITE_NAME = ""
#ENS_SERVER_URL = 'https://ensgraph.test-pns-link.com/subgraphs/name/graphprotocol/ens'
PNS_SERVER_URL = 'https://moonbeamgraph.test-pns-link.com/subgraphs/name/graphprotocol/pns'
ENS_SERVER_URL = 'https://api.thegraph.com/subgraphs/name/ensdomains/ens'

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

# 根据 domain的名字，例如 vitalik.eth 获得对应的ipfs cid
def get_domain_ipfs_cid_form_domain_name subdomain
  logger.info "==== in get_domain_ipfs_cid_form_domain_name"
  subdomain_type = subdomain.split('.').last
  result = ''
  case subdomain_type
  when 'eth'
    temp_result = post_request server_url: ENS_SERVER_URL,
      body_in_hash: {
        "query":"query MyQuery {\n  domains(where: {name:  \"#{subdomain}\"}) {\n    resolver { \n      contentHash\n    }\n   \n  }\n}",
        "variables": nil,
        "operationName": "MyQuery"
      }

    content_hash = JSON.parse(temp_result)['data']['domains'][0]['resolver']['contentHash']
    logger.info "=== content_hash is #{content_hash}"
    command = "node get_ipfs_cid.js #{content_hash}"
    result = `#{command}`
    logger.info result
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

  return result
end

def get_result_for_ens name
  response = post_request server_url: ENS_SERVER_URL,
  body_in_hash: {
    "query":"query MyQuery {\n  domains(where: {name: \"#{name}\"}) {\n    id\n    labelName\n    name\n    labelhash\n    subdomains {\n      id\n      name\n      subdomains {\n        name\n        labelhash\n        labelName\n      }\n    }\n    subdomainCount\n    owner {\n      id\n    }\n    parent {\n      id\n    }\n    resolvedAddress {\n      id\n      domains {\n        labelName\n        labelhash\n        name\n      }\n    }\n    ttl\n\t\tresolver {\n\t\t  id\n      contentHash\n      texts\n      address\n      coinTypes\n\t\t}\n  }\n}\n",
    "variables": nil,
    "operationName": "MyQuery"
  }
  logger.info "== response: #{response}"
  body = JSON.parse(response)
  domains = body['data']['domains'][0]
  logger.info "===domains #{domains}"
  return domains
end

def get_ens_domain_registration domains_labelhash
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

def get_temp_result_for_pns_domain name
  temp_result = post_request server_url: PNS_SERVER_URL,
    body_in_hash: {
      "operationName": "MyQuery",
      "query": "query MyQuery {\n  domains(where: {name: \"#{name}\"}) {\n    labelhash\n    labelName\n    id\n    name\n    subdomains {\n      name\n      owner {\n        id\n      }\n    }\n    subdomainCount\n    owner {\n      id\n    }\n    parent {\n      id\n    }\n  }\n  sets(where: {domain_: {name: \"#{name}\"}}) {\n    id\n    keyHash\n    value\n  }\n  registrations(where: {labelName: \"#{name.sub(".dot", '')}\"}) {\n    expiryDate\n    events {\n      id\n      triggeredDate\n    }\n  }\n}\n",
      "variables": nil
    }
  return temp_result
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
  result_hash = {}
  temp_hash.map { |key, value|
    dot_value = []
    temp_result_sets_to_get_records.each { |e| dot_value << e if e['keyHash'] == value }
    result_hash.store(key, (dot_value.last || ''))
  }
  logger.info "=== result_hash: #{result_hash}"
  return result_hash
end

def get_ens_json_result domains, registration
  domains_resolved_address = domains['resolvedAddress']['domains'] rescue BLANK_VALUE
  result = {
    name: domains['name'],
    nameHash: domains['id'],
    labelName: domains['labelName'],
    labelHash: domains['labelhash'],
    owner: eth_check_summed_address(domains['owner']['id']),
    parent: domains['parent']['id'],
    subdomainCount: domains['subdomainCount'],
    ttl: domains['ttl'],
    cost: registration['cost'],
    expiryDate: Time.at(registration['expiryDate'].to_i),
    registrationDate: Time.at(registration['registrationDate'].to_i),
    # 列出了 该eth地址 注册的其他 ens域名, 暂时隐藏
    #resolvedAddress: {
    #  id: (domains['resolvedAddress']['id'] rescue ''),
    #  domains: domains_resolved_address,
    #},
    records: {
      contentHash: (domains['resolver']['contentHash'] rescue BLANK_VALUE),
      eth: eth_check_summed_address(domains['owner']['id']),
      dot: BLANK_VALUE,
      btc: BLANK_VALUE,
      text: (domains['resolver']['texts'] rescue BLANK_VALUE),
      pubkey: BLANK_VALUE
    }
  } rescue BLANK_VALUE
  return result
end

def eth_check_summed_address address
  temp = Eth::Address.new address
  logger.info "== address #{address} is valid? #{temp.valid? }"
  result = ''
  if temp.valid?
    result = temp.checksummed
  else
    result = "#{address}(invalid)"
  end
end

def get_pns_json_result temp_result_domain, result_hash, result_registration
  result = {
    name: temp_result_domain['name'],
    nameHash: temp_result_domain['id'],
    labelName: temp_result_domain['labelName'],
    labelHash: temp_result_domain['labelhash'],
    owner: eth_check_summed_address(temp_result_domain['owner']['id']),
    parent: temp_result_domain['parent']['id'],
    expiryDate: (Time.at(result_registration['expiryDate'].to_i) rescue BLANK_VALUE),
    registrationDate: (Time.at(result_registration['events'][0]['triggeredDate'].to_i) rescue BLANK_VALUE),
    subdomainCount: temp_result_domain['subdomainCount'],
    records: {
      dot: (result_hash['dot']['value'] rescue BLANK_VALUE),
      eth: (eth_check_summed_address(result_hash['eth']['value']) rescue BLANK_VALUE),
      btc: (result_hash['btc']['value'] rescue BLANK_VALUE),
      ipfs: (result_hash['ipfs']['value'] rescue BLANK_VALUE),
      email: (result_hash['email']['value'] rescue BLANK_VALUE),
      notice: (result_hash['notice']['value'] rescue BLANK_VALUE),
      twitter: (result_hash['twitter_com']['value'] rescue BLANK_VALUE),
      github: (result_hash['github']['value'] rescue BLANK_VALUE),
      url: (result_hash['twitter_url']['value'] rescue BLANK_VALUE),
      avatar: (result_hash['avatar']['value'] rescue BLANK_VALUE),
      cName: (result_hash['cname']['value'] rescue BLANK_VALUE)
    }
  } rescue BLANK_VALUE
end

def get_ens_domain_names_form_address address
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

def get_dot_domain_names_form_address address
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

def get_result_form_graphql_when_eth_domain name, is_show_subdomains
  temp_domains = get_result_for_ens name
  logger.info "==temp_domains #{temp_domains} is_show_subdomains #{is_show_subdomains}"
  registration = get_ens_domain_registration temp_domains['labelhash'] rescue BLANK_VALUE
  result = get_ens_json_result(temp_domains, registration)
  result['subdomains'] = temp_domains['subdomains'] if is_show_subdomains == 'yes'
  logger.info "=== after add subdomains result : #{result}"
  return result
end

def get_result_form_graphql_when_dot_domain name, is_show_subdomains
  temp_result = get_temp_result_for_pns_domain name
  temp_result_domain = JSON.parse(temp_result)['data']['domains'][0]
  temp_result_sets_to_get_records = JSON.parse(temp_result)['data']['sets']
  result_registration = JSON.parse(temp_result)['data']['registrations'][0]
  result_hash = get_records_for_dot_domain temp_result_sets_to_get_records
  result = get_pns_json_result temp_result_domain, result_hash, result_registration
  logger.info "=== before add subdomains result : #{result}"
  logger.info "==is_show_subdomains #{is_show_subdomains}"
  if temp_result_domain != nil
    temp_result_domain['subdomains'].each do |subdomain|
      subdomain['owner'] = subdomain['owner']['id']
    end
  end
  result['subdomains'] = temp_result_domain['subdomains'] if is_show_subdomains == 'yes'
  logger.info "=== after add subdomains result : #{result}"
  return result
end

subdomain [:www, nil] do
  get '/' do
    json result: "Hi there~, subdomain is: #{subdomain}"
  end
end

def display_the_logic_of_the_page cid, subdomain
  logger.info "=== subdomain is: #{subdomain} cid #{cid}"
  if cid != '' && cid != nil
    url = "#{IPFS_SITE_NAME}/ipfs/#{cid}"
    logger.info "== cid is: #{cid}, redirecting..#{url}"
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

subdomain do
  get '/' do
    cid = get_domain_ipfs_cid_form_domain_name subdomain rescue ''
    display_the_logic_of_the_page cid, subdomain
  end
end

subdomain :api do
  get "/name/:name" do
    name = params[:name]
    is_show_subdomains = params[:is_show_subdomains]
    subdomain_type = name.split('.').last
    case subdomain_type
    when 'eth'
      result = get_result_form_graphql_when_eth_domain name, is_show_subdomains rescue BLANK_VALUE
      json({
        result: 'ok',
        data: result
      })

    when 'dot'
      result = get_result_form_graphql_when_dot_domain name, is_show_subdomains rescue BLANK_VALUE
      json({
        result: 'ok',
        data: result
      })
    else
      'only support .eth, .dot domain'
    end

  end

  get '/reverse/:address' do

    address = params[:address]

    if address == nil || address == ''
      halt 404, 'page not found(address is missing) '
    end

    if params[:type] == 'eth'
      result = get_ens_domain_names_form_address address
    else
      result = get_dot_domain_names_form_address address
    end
    logger.info "result : #{result}"

    json({
      result: 'ok',
      address: address,
      data: result
    })

  end

end

get '/' do
  json result: 'hihi, you are visiting @ subdomain'
end

