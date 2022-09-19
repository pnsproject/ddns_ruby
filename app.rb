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

# FIXME
subdomain :api do
  get '/name' do
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

