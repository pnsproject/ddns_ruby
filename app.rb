require 'sinatra'
require 'sinatra/json'
require 'sinatra/subdomain'

subdomain [:www, nil] do
  get '/' do
    json result: 'Hi there~, fine thank you, and you? '
  end
end
