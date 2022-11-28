# DDNS ruby server

ruby 3.0.4

## 数据库

host: dever.c6cr27fjdpyd.ap-northeast-3.rds.amazonaws.com
password: VNa9eKgDjvOmlNni98Ai
username: postgres

## 依赖的第三方应用.

pns graph  : 用于查询pns
graph网址： https://cloud.hasura.io/public/graphiql?endpoint=https%3A%2F%2F%2Fpns-graph.ddns.so%2Fsubgraphs%2Fname%2Fgraphprotocol%2Fpns

ens graph: 用于查询ens
graph网址： https://api.thegraph.com/subgraphs/name/ensdomains/ens/graphql?query=query+MyQuery+%7B%0A++domains%28where%3A+%7BlabelName%3A+%22daydayup%22%7D%29+%7B%0A++++labelhash%0A++++labelName%0A++++id%0A++++name%0A++++subdomainCount%0A++++subdomains%28first%3A+20%29+%7B%0A++++++id%0A++++%7D%0A++%7D%0A%7D%0A

bit: 用于查询bit域名
查询官方网址： https://github.com/dotbitHQ/das-account-indexer/blob/main/API.md#get-account-records-info

lens:  用于查询lens 域名
graph网址:  https://lens-graph.ddns.so/subgraphs/name/rtomas/lens-subgraph

## 安装和运行

bundle install

## 开发模式启动

方式一： ./restart_very_quickly
方式二：
（1）bundle exec ruby app.rb 这个是用来处理各种API查询的
（2）bundle exec ruby get_domain_ip.rb 这个是用来处理针对传统的DNS的查询(例如A记录, CNAME等)

## 运行单元测试

单个测试文件:

```
$ bundle exec ruby test/app_test.rb
```

运行所有测试文件:

```
$ bundle exec ruby test/*
```
