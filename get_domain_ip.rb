require 'rubydns'
require 'pp'
require 'active_record'

#enum :type, { A: 0, CNAME: 1, TXT: 2, IPFS: 3 }
TYPE_A = 0
TYPE_CNAME = 1
TYPE_TXT = 2
TYPE_IPFS = 3
password = 'eadd2f80c59511f3f73388d9d898277224fd623c689f232097a886500ad1118022ba7a01683c1df2053c09e964e09e3bb539ad815031dd464cd17c143859a24c'
host = 'localhost'
ActiveRecord::Base.establish_connection(adapter: 'postgresql', pool: "#{ENV["DATABASE_POOL"] || 64}", timeout: 5000, encoding: 'utf-8', host: "#{host}", user: 'postgres', username: 'postgres', password: "#{password}", port: 5432, database: 'ddns_rails')

class Record < ActiveRecord::Base
end

class Domain < ActiveRecord::Base
end

class MyServer < Async::DNS::Server
  def process(name, resource_class, transaction)
    @resolver ||= Async::DNS::Resolver.new([[:udp, '8.8.8.8', 53], [:tcp, '8.8.8.8', 53]])
    puts "== name #{name} resource_class #{resource_class}"
    #目前只适用于A C TXT 等传统域名
    if resource_class == 'TXT'
      record_local = Record.where('domain_name = ? and record_type = ?', name, TYPE_TXT).first
    elsif resource_class == 'CNAME'
      record_local = Record.where('domain_name = ? and record_type = ?', name, TYPE_CNAME).first
    else
      record_local = Record.where('domain_name = ? and record_type = ?', name, TYPE_A).first
    end
    puts "=== record_local #{record_local.inspect}"
    if record_local.present?
      transaction.respond!("#{record_local.content}")
    else
      transaction.passthrough!(@resolver) rescue transaction.fail!(:NXDomain)
    end

  end
end

server = MyServer.new([[:udp, '127.0.0.1', 2346]])
server.run
