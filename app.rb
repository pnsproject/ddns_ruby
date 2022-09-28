require 'sinatra'
require 'sinatra/json'
require 'sinatra/subdomain'
require 'httparty'
require 'date'

# 修改这个即可， 例如 ddns.so,  test-ddns.com
#SITE_NAME = "test-ddns.com"
SITE_NAME = "ddns.so"

IPFS_SITE_NAME = "https://ipfsgate.#{SITE_NAME}"

# 发起http post请求
def post_request options

  server_url = options[:server_url]
  body_in_hash = options[:body_in_hash]

  response = HTTParty.post server_url,
    :headers => { 'Content-Type' => 'application/json', 'Accept' => 'application/json'},
    :body => body_in_hash.to_json

  puts "== response: #{response}"

  result = response.body
  return result
end

# 根据 domain的名字，例如 vitalik.eth 获得对应的ipfs cid
def get_ipfs_cid subdomain
  subdomain_type = subdomain.split('.').last

  result = ''
  case subdomain_type
  when 'eth'
    temp_result1 = post_request server_url: 'https://ensgraph.test-pns-link.com/subgraphs/name/graphprotocol/ens',
      body_in_hash: {
        "query": "query MyQuery {\n  domains(where: {name: \"#{subdomain}\"}) {\n    id\n    labelName\n    name\n    resolver {\n      id\n    }\n  }\n}",
        "variables": nil,
        "operationName": "MyQuery",
        "extensions":{"headers": nil}
      }

    resolver_id = JSON.parse(temp_result1)['data']['domains'][0]['resolver']['id']

    temp_result2 = post_request server_url: 'https://ensgraph.test-pns-link.com/subgraphs/name/graphprotocol/ens',
      body_in_hash: {
        "query": "query MyQuery {\n  resolver(\n    id: \"#{resolver_id}\"\n  ) {\n    contentHash\n  }\n}\n",
        "variables": nil,
        "operationName":"MyQuery"
      }

    content_hash = JSON.parse(temp_result2)['data']['resolver']['contentHash']

    command = "node get_ipfs_cid.js #{content_hash}"

    result = `#{command}`
    puts result

  when 'dot'
    raise 'not implemented'
  else
    raise 'only support .eth, .dot domain'
  end

  return result
end

subdomain [:www, nil] do
  get '/' do
    json result: "Hi there~, subdomain is: #{subdomain}"
  end
end

subdomain do
  get '/' do
    puts "=== subdomain is: #{subdomain}"
    # 先获得content
    #
    cid = get_ipfs_cid subdomain rescue ''
    # 然后在本地  ipfs gate 访问html content
    #response = HTTParty.get "http://localhost:8080/ipfs/#{content}"
    #response.body

    if cid == ''
      halt 404, 'page not found( seems not set content hash ) '
    end

    target_url = "#{IPFS_SITE_NAME}/ipfs/#{cid}"
    puts "== content is: #{cid}, redirecting..#{target_url}"
    redirect to(target_url)
  end
end

#subdomain :api do
  get "/name/:name" do
    children = params['children']
    subdomain_type = params[:name].split('.').last
    case subdomain_type
    when 'eth'
      response = post_request server_url: 'https://ensgraph.test-pns-link.com/subgraphs/name/graphprotocol/ens',
      body_in_hash: {
        "query": "query MyQuery {\n  domains(where: {name: \"#{params[:name]}\"}) {\n    id\n    name\n    labelName\n    labelhash\n    resolver {\n      id\n      texts\n      contentHash\n      coinTypes\n      address\n    }\n    owner {\n      id\n    }\n    parent {\n      id\n    }\n    subdomainCount\n    subdomains {\n      id\n      labelName\n      labelhash\n      name\n    }\n    resolvedAddress {\n      id\n      domains {\n        labelName\n        labelhash\n        name\n      }\n    }\n    ttl\n  }\n}",
        "variables": nil,
        "operationName": "MyQuery",
      }
      puts "== response: #{response}"
      body = JSON.parse(response)
      domains = body['data']['domains'][0]
      if domains['resolvedAddress'] == nil
        domains_resolved_address = nil
      else
        domains_resolved_address = domains['resolvedAddress']['domains']
      end
      puts "==domains"
      puts domains.inspect

      response_registration = post_request server_url: 'https://ensgraph.test-pns-link.com/subgraphs/name/graphprotocol/ens',
      body_in_hash: {
        "query": "query MyQuery {\n  registration(\n    id: \"#{domains['labelhash']}\"\n  ) {\n    id\n    expiryDate\n    labelName\n    registrationDate\n    cost\n  }\n}",
        "variables": nil,
        "operationName": "MyQuery",
      }

        puts "== response_registration: #{response_registration}"
        body_registration = JSON.parse(response_registration)
        puts body_registration['data'].inspect
        registration = body_registration['data']['registration']
        puts "==registration"
        puts registration.inspect
      json({
        code: 1,
        message: 'success',
        result: {
          name: domains['name'],
          nameHash: "",
          labelName: domains['labelName'],
          labelhash: domains['labelhash'],
          owner: domains['owner']['id'],
          parent: domains['parent']['id'],
          subdomains: {
            id: (domains['subdomains']['id'] rescue ''),
            labelName: (domains['subdomains']['labelName'] rescue ''),
            labelhash: (domains['subdomains']['labelhash'] rescue ''),
            name: (domains['subdomains']['name'] rescue ''),
          },
          subdomainCount: domains['subdomainCount'],
          resolvedAddress: {
            id: (domains['resolvedAddress']['id'] rescue ''),
            domains: domains_resolved_address,
          },
          ttl: domains['ttl'],
          cost: registration['cost'],
          expiryDate: Time.at(registration['expiryDate'].to_i),
          registrationDate: Time.at(registration['registrationDate'].to_i),
          records: {
            contenthash: (domains['resolver']['contentHash'] rescue ''),
            eth: domains['owner']['id'],
            dot: '',
            btc: '',
            text: (domains['resolver']['texts'] rescue ''),
            pubkey: ''
          }
        }
      })

    when 'dot'
      puts "=== params[:name].split('.') #{params[:name].sub('.dot', '')}"
      temp_result = post_request server_url: 'https://moonbeamgraph.test-pns-link.com/subgraphs/name/graphprotocol/pns',
      body_in_hash: {
        "operationName": "MyQuery",
        "query": "query MyQuery {\n  domains(where: {name: \"#{params[:name]}\"}) {\n    labelhash\n    labelName\n    id\n    name\n    subdomains {\n      name\n      owner {\n        id\n      }\n    }\n    subdomainCount\n    owner {\n      id\n    }\n    parent {\n      id\n    }\n  }\n  sets(where: {domain_: {name: \"#{params[:name]}\"}}) {\n    id\n    keyHash\n    value\n  }\n  registrations(where: {labelName: \"#{params[:name].sub(".dot", '')}\"}) {\n    expiryDate\n    events {\n      id\n      triggeredDate\n    }\n  }\n}\n",
        "variables": nil
      }

      result_domain = JSON.parse(temp_result)['data']['domains'][0]
      result_sets = JSON.parse(temp_result)['data']['sets']
      result_registrations = JSON.parse(temp_result)['data']['registrations']
      temp_hash = {
        "DOT" => '70476024645083539914866120258902002044389822943217047784978736702069848167247',
        "ETH" => '77201932000687051421874801696342701541816747065578039511607412978553675800564',
        "BTC" => '105640063387051144792550451261497903460441457163918809975891088748950929433065',
        "IPFS" => '109444936916467285377972213791356162468265265799777646334604004948560489512394',
        "EMAIL" => '50101170924916254227885891120695131387383646459470231890507002477095918146885',
        "NOTICE" => '31727182724036554852371956750201584211517824919105130426252222689897810866214',
        "TWITTER_COM" => '11710898932869919534375710263824782355793106641910621555855312720536896315685',
        "GITHUB" => '102576668688838416847107385580607409742813859881781246507337882384803237069874',
        "TWITTER_URL" => '23368862207911262087635895660209245090921614897479706708279561601163163997039',
        "AVATAR" => '98593787308120460448886304499976840768878166060614499815391824681489593998420',
        "C_NAME" => '69611991539268867131500085835156593536513732089793432642972060827780580969128'
      }
      result_hash = {}
      temp_hash.map { |key, value|
        dot_value = []
        result_sets.each { |e|
          if e['keyHash'] == value
            dot_value << e
            puts dot_value
            puts key
            puts value
            puts e['keyHash']
          end
          if dot_value.last == nil
            hash = result_hash.store(key, '')
          else
            hash = result_hash.store(key, dot_value.last)
          end
        }
      }
      puts "=== temp_hash : #{temp_hash}"
      puts "=== result_hash: #{result_hash}"
      # 取到了所有的 key hash 对应的value
      result = {
        name: result_domain['name'],
        namehash: '',
        labelName: result_domain['labelName'],
        labelhash: result_domain['labelhash'],
        owner: result_domain['owner']['id'],
        parent: result_domain['parent']['id'],
        expiryDate: (Time.at(result_registrations[0]['expiryDate'].to_i) rescue ''),
        registrationDate: (Time.at(result_registrations[0]['events'].first['triggeredDate'].to_i) rescue ''),
        subdomainCount: result_domain['subdomainCount'],
        records: {
          DOT: (result_hash['DOT']['value'] rescue ''),
          ETH: (result_hash['ETH']['value'] rescue ''),
          BTC: (result_hash['BTC']['value'] rescue ''),
          IPFS: (result_hash['IPFS']['value'] rescue ''),
          Email: (result_hash['EMAIL']['value'] rescue ''),
          Notice: (result_hash['NOTICE']['value'] rescue ''),
          twitter: (result_hash['TWITTER_COM']['value'] rescue ''),
          github: (result_hash['GITHUB']['value'] rescue ''),
          Url: (result_hash['TWITTER_URL']['value'] rescue ''),
          Avatar: (result_hash['AVATAR']['value'] rescue ''),
          CNAME: (result_hash['C_NAME']['value'] rescue '')
        }
      }
      puts "===query_type: #{params[:name]}"
      puts "===result : #{result}"
      if params['subdomains'] == 'yes'
        result['subdomains'] = result_domain['subdomains']
      end
      puts "===result : #{result}"

      json({
        code: 1,
        message: 'success',
        result: result
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

    subdomain_type = address.match(/0x/) ? 'eth' : 'dot'
    case subdomain_type
    when 'eth' then
      temp_result = post_request server_url: 'https://ensgraph.test-pns-link.com/subgraphs/name/graphprotocol/ens',
        body_in_hash: {
          "operationName": "MyQuery",
          "query": "query MyQuery {\n account(id: \"#{address.downcase}\") {\n id\n domains {\n name\n labelhash\n }\n }\n}\n",
          "variables": nil
        }

      result = JSON.parse(temp_result)['data']['account']['domains'].map{ |e| e["name"] } # rescue []
    when 'dot' then
      result = []
    else
      result = []
    end

    json({
      code: 1,
      message: 'success',
      address: address,
      result: result
    })

  end

#end

get '/' do
  json result: 'hihi, you are visiting @ subdomain'
end

