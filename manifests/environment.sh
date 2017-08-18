#!/usr/bin/bash

# TLS Bootstrapping に使用させる Token
# 下記のコマンドで作成できる
# head -c 16 /dev/urandom | od -An -t x | tr -d ' '
BOOTSTRAP_TOKEN="41f7e4ba8b7be874fcff18bf5cf41a7c"

# 使っていないネットワークセグメントで
# Service ネットワークセグメント と Pod ネットワークセグメント を定義する

# Service ネットワークセグメント (Service CIDR）
# デプロイ完成までアクセスできない
# デプロイ完成したら、 IP:Port でアクセスできてなる
SERVICE_CIDR="10.254.0.0/16"

# POD ネットワークセグメント (Cluster CIDR）
# デプロイ完成まで、アクセスできない、**デプロイ後**ルーターアクセスできる (flanneld で)
CLUSTER_CIDR="172.30.0.0/16"

# 振り分けるポート範囲 (NodePort Range)
NODE_PORT_RANGE="8400-9000"

# etcd クラスターIPアドレス
ETCD_ENDPOINTS="https://10.64.3.7:2379,https://10.64.3.8:2379,https://10.66.3.86:2379"

# flanneld ネットワーク配置の頭文字
FLANNEL_ETCD_PREFIX="/kubernetes/network"

# kubernetes IP アドレス (振り分ける準備、一般に SERVICE_CIDR の第一番目IPアドレスを振り分ける)
CLUSTER_KUBERNETES_SVC_IP="10.254.0.1"

# クラスター DNS サービス IP ( SERVICE_CIDR から振り分ける)
CLUSTER_DNS_SVC_IP="10.254.0.2"

# Cluster DNS ドメイン
CLUSTER_DNS_DOMAIN="cluster.local."