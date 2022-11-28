ENV['APP_ENV'] = 'test'

require './app'
require 'test/unit'
require 'rack/test'

class AppTest < Test::Unit::TestCase
  include Rack::Test::Methods

  def app
    Sinatra::Application
  end

  #def test_should_get_name_vitalik_eth
  test "should get /name/vitalik.eth" do
    header "HOST", "api.ddns.so"
    response = get '/name/vitalik.eth'

    body = JSON.parse(response.body)
    assert_equal "ok", body['result']
    assert_equal "vitalik.eth", body['data']['name']
    assert_equal "0xee6c4522aab0003e8d14cd40a6af439055fd2577951148c14b6cea9a53475835", body['data']['nameHash']
  end

  test "should get /name/jiangplus.dot" do
    header "HOST", "api.ddns.so"
    response = get '/name/jiangplus.dot'

    body = JSON.parse(response.body)
    assert_equal "ok", body['result']
    assert_equal "jiangplus.dot", body['data']['name']
    assert_equal "0xce30c63c310f041da7553c3236129facb6f6e0cbf20617ac1bc5fee6ecd007d5", body['data']['nameHash']
  end

  test "should get /name/jouni.lens" do
    header "HOST", "api.ddns.so"
    response = get '/name/jouni.lens'

    body = JSON.parse(response.body)
    assert_equal "ok", body['result']
    assert_equal "jouni.lens", body['data']['handle']
  end

  test "should get /name/phone.bit" do
    header "HOST", "api.ddns.so"
    response = get '/name/phone.bit'

    body = JSON.parse(response.body)
    assert_equal "ok", body['result']
    assert_equal "phone.bit", body['data']['name']
    assert_equal "0x36aa229e20134008dd688e59b955d6674c81016f6bda65375a8ef7712bc3f802", body['data']['nameHash']
  end

  test "should get /name/brantly.eth?subdomains=yes" do
    header "HOST", "api.ddns.so"
    response = get '/name/brantly.eth?subdomains=yes'

    body = JSON.parse(response.body)
    assert_equal "ok", body['result']
    assert_equal "brantly.eth", body['data']['name']
    assert_equal 20, body['data']['per']
    assert last_response.body.include?('brantly.eth')
  end

  test "should get /name/zzzzzzzzzzzzzzzzzzzzz.dot?subdomains=yes" do
    header "HOST", "api.ddns.so"
    response = get '/name/zzzzzzzzzzzzzzzzzzzzz.dot?subdomains=yes'

    body = JSON.parse(response.body)
    assert_equal "ok", body['result']
    assert_equal "zzzzzzzzzzzzzzzzzzzzz.dot", body['data']['name']
    assert_equal 20, body['data']['per']
    assert last_response.body.include?('zzzzzzzzzzzzzzzzzzzzz.dot')
  end

  test "should get /name/0x.bit?subdomains=yes&page=3" do
    header "HOST", "api.ddns.so"
    response = get '/name/0x.bit?subdomains=yes&page=3'

    body = JSON.parse(response.body)
    assert_equal "ok", body['result']
    assert_equal "0x.bit", body['data']['name']
    assert_equal 20, body['data']['per']
    assert last_response.body.include?('0x.bit')
  end

  test "should get /reverse/ens/0x0b23E3588c906C3F723C58Ef4d6baEe7840A977c" do
    header "HOST", "api.ddns.so"
    response = get '/reverse/ens/0x0b23E3588c906C3F723C58Ef4d6baEe7840A977c'

    body = JSON.parse(response.body)
    assert_equal "ok", body['result']
    assert_equal "0x0b23E3588c906C3F723C58Ef4d6baEe7840A977c", body['address']
    assert_equal "daydayup666.eth", body['data']
  end

  test "should get /reverse/bit/0x9176acd39a3a9ae99dcb3922757f8af4f94cdf3c" do
    header "HOST", "api.ddns.so"
    response = get '/reverse/bit/0x9176acd39a3a9ae99dcb3922757f8af4f94cdf3c'

    body = JSON.parse(response.body)
    assert_equal "ok", body['result']
    assert_equal "0x9176acd39a3a9ae99dcb3922757f8af4f94cdf3c", body['address']
    assert_equal "justing.bit", body['data']
  end

  test "should get /reverse/pns/0x0b23E3588c906C3F723C58Ef4d6baEe7840A977c" do
    header "HOST", "api.ddns.so"
    response = get '/reverse/pns/0x0b23E3588c906C3F723C58Ef4d6baEe7840A977c'

    body = JSON.parse(response.body)
    assert_equal "ok", body['result']
    assert_equal "0x0b23E3588c906C3F723C58Ef4d6baEe7840A977c", body['address']
    assert_equal "zzzzzzzzzzzzzzzzzzzzz.dot", body['data']
  end

  test "should get /get_all_domain_names/0x0b23E3588c906C3F723C58Ef4d6baEe7840A977c" do
    header "HOST", "api.ddns.so"
    response = get '/get_all_domain_names/0x0b23E3588c906C3F723C58Ef4d6baEe7840A977c'

    body = JSON.parse(response.body)
    assert_equal "ok", body['result']
    assert_equal "0x0b23E3588c906C3F723C58Ef4d6baEe7840A977c", body['address']
    assert last_response.body.include?('zzzzzzzzzzzzzzzzzzzzz.dot')
    assert last_response.body.include?('daydayup666.eth')
  end

  test "should get /get_all_domain_names/0x4f34124bc7d275a801016f699b539d89605769cc" do
    header "HOST", "api.ddns.so"
    response = get '/get_all_domain_names/0x4f34124bc7d275a801016f699b539d89605769cc'

    body = JSON.parse(response.body)
    assert_equal "ok", body['result']
    assert_equal "0x4f34124bc7d275a801016f699b539d89605769cc", body['address']
    assert last_response.body.include?('0x.bit')
  end

end
