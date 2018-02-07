<!-- toc -->

tags: kubernetes, environment

# コンポーネントバージョンとクラスター環境

## コンポーネントバージョン

+ Kubernetes 1.6.2
+ Docker  17.04.0-ce
+ Etcd 3.1.6
+ Flanneld 0.7.1 vxlan ネットワーク / Calico
+ TLS 通信認証 (etcd、kubernetes master と node の間の通信認証)
+ RBAC ロールペースアクセス制御
+ kubelet TLS BootStrapping
+ kubedns、dashboard、heapster (influxdb、grafana)、EFK (elasticsearch、fluentd、kibana) プラグイン
+ 私的なコンテナレジストリサービス docker registry / harbor，
+ ceph rgw / CephRBD
+ TLS + HTTP Basic 認証


## クラスター機器

+ 10.64.3.7　/ master, node, etcd
+ 10.64.3.8　/ node, etcd
+ 10.66.3.86　/ node, etcd

> 若有安装 Vagrant 与 Virtualbox，这三台机器可以用本着提供的 Vagrantfile 来建置：
``` bash
$ cd vagrant
$ vagrant up
```

## クラスター環境変数

この後、デプロイステップは下記定義されている環境変数を使うので，**利用者のネットワーク状況**によって修正してください：

``` bash
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
```

+ 環境変数について定義は [environment.sh](https://github.com/it2911/deploy_kubernetes_cluster/blob/master/manifests/environment.sh) を参照してください；

## 各サーバーに環境配置ファイルを配布する

**すべて**機器(マシン) `/root/local/bin` フォルダにグローバル変数設定ファイルを置く：

``` bash
$ cp environment.sh $HOME/bin
```
