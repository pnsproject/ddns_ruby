require 'rubydns'
require 'pp'
require 'active_record'

#enum :type, { A: 0, CNAME: 1, TXT: 2, IPFS: 3 }
TYPE_A = 0
TYPE_TXT = 2
password = '88888888'
host = 'localhost'
user = 'admin'
ActiveRecord::Base.establish_connection(adapter: 'postgresql', pool: "#{ENV["DATABASE_POOL"] || 64}", timeout: 5000, encoding: 'utf-8', host: "#{host}", user: "#{user}", username: "#{user}", password: "#{password}", port: 5432, database: 'ddns_rails')

class Record < ActiveRecord::Base
end

class Domain < ActiveRecord::Base
end

class MyServer < Async::DNS::Server
  def process(name, resource_class, transaction)
    @resolver ||= Async::DNS::Resolver.new([[:udp, '8.8.8.8', 53], [:tcp, '8.8.8.8', 53]])
    #目前只适用于A C TXT 等传统域名
    if resource_class == 'TXT'
      type_name = TYPE_TXT
    else
      type_name = TYPE_A
    end
    record_local = Record.where('domain_name = ? and record_type = ?', name, type_name).first
    if record_local.present?
      transaction.respond!(record_local.content)
    else
      transaction.passthrough!(@resolver) rescue transaction.fail!(:NXDomain)
    end
  end
end

server = MyServer.new([[:udp, '127.0.0.1', 2346]])
server.run
