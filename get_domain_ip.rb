require 'sinatra/activerecord'
require 'rubydns'
require 'pp'

#enum :type, { A: 0, CNAME: 1, TXT: 2, IPFS: 3 }
TYPE_A = 0
TYPE_TXT = 2

class Record < ActiveRecord::Base
end

class MyServer < Async::DNS::Server
  def process(name, resource_class, transaction)
    @resolver ||= Async::DNS::Resolver.new([[:udp, '8.8.8.8', 53], [:tcp, '8.8.8.8', 53]])

    #目前只适用于A C TXT 等传统域名
    type_name = ''
    if resource_class.to_s.include? 'TXT'
      type_name = TYPE_TXT
    elsif resource_class.to_s.include? 'A'
      type_name = TYPE_A
    else
      # todo:目前仅支持a c ipfs TXT记录,所以这个分支永远不会走
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
