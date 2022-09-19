require 'sinatra'
require 'sinatra/json'
require 'sinatra/subdomain'
require 'httparty'

SITE_FULL_NAME = "test-ddns.com"
IPFS_SITE_NAME = "https://ipfsgate.test-ddns.com"

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

subdomain :api do
  get "/name/:name" do
    server_url = 'https://ensgraph.test-pns-link.com/subgraphs/name/graphprotocol/ens'
    response = HTTParty.post server_url,
      :headers => { 'Content-Type' => 'application/json', 'Accept' => 'application/json'},
      :body => {
        "query": "query MyQuery {\n  domains(where: {name: \"#{params[:name]}\"}) {\n    id\n    labelName\n    name\n    resolver {\n      id\n    }\n    labelhash\n    owner {\n      id\n    }\n    parent {\n      id\n      labelName\n      labelhash\n      name\n    }\n    subdomainCount\n    subdomains {\n      id\n      labelName\n      labelhash\n      name\n    }\n    resolvedAddress {\n      id\n      domains {\n        labelName\n        labelhash\n        name\n      }\n    }\n    ttl\n  }\n}",
        "variables": nil,
        "operationName": "MyQuery",
        "extensions":{"headers": nil}
      }.to_json
    puts "== response: #{response}"
    body = JSON.parse(response.body)
    domains = body['data']['domains'][0]
    puts "==domains"
    puts domains.inspect

    response_registration = HTTParty.post server_url,
      :headers => { 'content-type' => 'application/json', 'accept' => 'application/json'},
      :body => {
        "query": "query MyQuery {\n  registration(\n    id: \"#{domains['labelhash']}\"\n  ) {\n    id\n    expiryDate\n    labelName\n    registrationDate\n    cost\n  }\n}",
        "variables": nil,
        "operationname": "myquery",
        "extensions":{"headers": nil}
      }.to_json

      puts "== response_registration: #{response_registration}"
      body_registration = JSON.parse(response_registration.body)
      puts body_registration['data'].inspect
      registration = body_registration['data']['registration']
      puts "==registration"
      puts registration.inspect
    json({
      code: 1,
      message: 'success',
      result: {
        name: "#{domains['name']}",
        nameHash: "",
        labelName: "#{domains['labelName']}",
        labelhash: "#{domains['labelhash']}",
        owner: {
          id: "#{domains['owner']['id']}"
        },
        parent: {
          id: "#{domains['parent']['id']}",
          labelName: "#{domains['parent']['labelName']}",
          labelhash: "#{domains['parent']['labelhash']}",
          name: "#{domains['parent']['name']}"
        },
        subdomainCount: "#{domains['subdomainCount']}",
        subdomains: {
          id: "#{domains['subdomain']['id'] rescue ''}",
          labelName: "#{domains['subdomain']['labelName'] rescue ''}",
          labelhash: "#{domains['subdomain']['labelhash'] rescue '' }",
          name: "#{domains['subdomain']['name'] rescue '' }",
        },
        resolvedAddress: {
          id: "#{domains['resolvedAddress']['id']}",
          domains: {
            labelName: "#{domains['resolvedAddress']['domains'][0]['labelName'] rescue ''}",
            labelhash: "#{domains['resolvedAddress']['domains'][0]['labelhash'] rescue ''}",
            name: "#{domains['resolvedAddress']['domains'][0]['name'] rescue ''}"
          }
        },
        ttl: "#{domains['ttl'] rescue ''}",
        registration: {
          id: "#{registration['id']}",
          expiryDate: "#{registration['expiryDate']}",
          labelName: "#{registration['labelName']}",
          registrationDate: "#{registration['registrationDate']}",
          cost: "#{registration['cost']}"
        }
      }
    })

  end

  get '/reverse' do
    json({
      name: 'vitalik.eth',
      namehash: '0x..'
    })
  end
end

get '/' do
  json result: 'hihi, you are visiting @ subdomain'
end

