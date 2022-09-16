require 'sinatra'
require 'sinatra/json'

get '/' do
  json result: 'Hi there~, fine thank you, and you? '
end
