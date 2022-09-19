require 'sinatra'
require 'sinatra/json'
require 'sinatra/subdomain'
require 'httparty'

SITE_FULL_NAME = "test-ddns.com"
IPFS_SITE_NAME = "https://ipfsgate.test-ddns.com"

def get_ipfs_content subdomain
  # vitalik.eth
  return 'bafybeigsn4u4nv4uyskxhewakk5m2j2lluzhsbsayp76zh7nbqznrxwm7e'
  # image
  #return 'QmSkFCXoTamt9fJDxdiRU8EEsvBrT3zw8FFL5zvok2VyyB'
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
    content = get_ipfs_content subdomain
    # 然后在本地  ipfs gate 访问html content
    #response = HTTParty.get "http://localhost:8080/ipfs/#{content}"
    #response.body
    target_url = "#{IPFS_SITE_NAME}/ipfs/#{content}"
    puts "== content is: #{content}, redirecting..#{target_url}"
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

