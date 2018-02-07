<!-- toc -->

tags: flanneld

# Flannel ネットワークをデプロイする

kubernetes クラスターの各ノードは Pod のネットワークに経由で通信できる、**すべてノード** (Master、Node)で Flannel を利用して Pod のネットワークを構築する。

## 使用変数

利用している変数が下記の内容を参考してください：

``` bash
$ export NODE_IP=10.64.3.7 # 当該ノードの IP アドレス
$ # その他インポートグローバル変数：ETCD_ENDPOINTS、FLANNEL_ETCD_PREFIX、CLUSTER_CIDR
$ source $HOME/bin/environment.sh
$
```

## TLS 証明書とキーファイルを作成する

etcd クラスターは双方向 TLS 認証を行う、flanneld と etcd クラスターの通信用 CA とキーファイルが必要だ。

flanneld 証明書サインを作成する：

``` bash
$ cat > flanneld-csr.json <<EOF
{
  "CN": "flanneld",
  "hosts": [],
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "JP",
      "ST": "Tokyo,
      "L": "Tokyo",
      "O": "k8s",
      "OU": "System"
    }
  ]
}
EOF
```

+ hosts 項目の値が空を設定する；

flanneld 証明書とキーファイルを作成する：

``` bash
$ sudo cfssl gencert -ca=/etc/kubernetes/ssl/ca.pem \
  -ca-key=/etc/kubernetes/ssl/ca-key.pem \
  -config=/etc/kubernetes/ssl/ca-config.json \
  -profile=kubernetes flanneld-csr.json | cfssljson -bare flanneld
$ ls flanneld*
flanneld.csr  flanneld-csr.json  flanneld-key.pem flanneld.pem
$ sudo mkdir -p /etc/flanneld/ssl
$ sudo mv flanneld*.pem /etc/flanneld/ssl
$ rm flanneld.csr  flanneld-csr.json
```

## etcd に Pod クラスターのネットワーク情報を書き込む

注意：当該コマンドの実行はFlannel ネットワークの**初期化する時のみ**に行う、この後、その他ノードで Flannel をデプロイする時、**関連情報の再度書き込む必要がない**。

``` bash
$ sudo $HOME/bin/etcdctl \
  --endpoints=${ETCD_ENDPOINTS} \
  --ca-file=/etc/kubernetes/ssl/ca.pem \
  --cert-file=/etc/flanneld/ssl/flanneld.pem \
  --key-file=/etc/flanneld/ssl/flanneld-key.pem \
  set ${FLANNEL_ETCD_PREFIX}/config '{"Network":"'${CLUSTER_CIDR}'", "SubnetLen": 24, "Backend": {"Type": "vxlan"}}'
```

+ flanneld **(v0.7.1)バージョンは etcd v3 で使えない**，ですから etcd v2 API を使って配置 key とネットワークパラメータを書き込む；
+ 書き込んだ Pod ネットワークの(${CLUSTER_CIDR}，172.30.0.0/16) と kube-controller-manager の `--cluster-cidr` の値と必ずに一致する；

## flanneld のインストールと配置

### flanneld ダウンロード

``` bash
$ mkdir flannel
$ wget https://github.com/coreos/flannel/releases/download/v0.7.1/flannel-v0.7.1-linux-amd64.tar.gz
$ tar -xzvf flannel-v0.7.1-linux-amd64.tar.gz -C flannel
$ sudo cp flannel/{flanneld,mk-docker-opts.sh} /root/local/bin
$
```

### flanneld の systemd unit ファイルを作成する

``` bash
$ cat > flanneld.service << EOF
[Unit]
Description=Flanneld overlay address etcd agent
After=network.target
After=network-online.target
Wants=network-online.target
After=etcd.service
Before=docker.service

[Service]
Type=notify
ExecStart=$HOME/bin/flanneld \\
  -etcd-cafile=/etc/kubernetes/ssl/ca.pem \\
  -etcd-certfile=/etc/flanneld/ssl/flanneld.pem \\
  -etcd-keyfile=/etc/flanneld/ssl/flanneld-key.pem \\
  -etcd-endpoints=${ETCD_ENDPOINTS} \\
  -etcd-prefix=${FLANNEL_ETCD_PREFIX}
ExecStartPost=$HOME/bin/mk-docker-opts.sh -k DOCKER_NETWORK_OPTIONS -d /run/flannel/docker
Restart=on-failure

[Install]
WantedBy=multi-user.target
RequiredBy=docker.service
EOF
```

+ mk-docker-opts.sh スクリプトは flanneld の Pod に振り分けるネットワーク情報を `/run/flannel/docker` ファイルに書き込む、后续 docker 启动时使用这个文件中参数值设置 docker0 网桥；
+ flanneld はシステムのルーターのデフォルトAPIとその他ノードと通信する、幾つネットワークインターフェースが存在する場合、 `--iface` で通信用のネットワークインターフェースを指定する
+ (上の systemd unit ファイルはこの項目を指定していない)，若しくは Vagrant + Virtualbox で実行する時、`--iface=enp0s8`を指定することが必要だ；

 [flanneld.service](https://github.com/it2911/deploy_kubernetes_cluster/blob/master/systemd/flanneld.service)

### flanneld サービス起動

``` bash
$ sudo cp flanneld.service /etc/systemd/system/
$ sudo systemctl daemon-reload
$ sudo systemctl enable flanneld
$ sudo systemctl start flanneld
$ systemctl status flanneld
$
```

### flanneld サービス検証

``` bash
$ journalctl  -u flanneld |grep 'Lease acquired'
$ ifconfig flannel.1
```

### 各ノードに振り分ける flanneld の Pod ネットワークの情報を確認する

``` bash
$ # クラスター Pod ネットワーク(/16)の情報を確認する
$ sudo $HOME/bin/etcdctl \
  --endpoints=${ETCD_ENDPOINTS} \
  --ca-file=/etc/kubernetes/ssl/ca.pem \
  --cert-file=/etc/flanneld/ssl/flanneld.pem \
  --key-file=/etc/flanneld/ssl/flanneld-key.pem \
  get ${FLANNEL_ETCD_PREFIX}/config
{ "Network": "172.30.0.0/16", "SubnetLen": 24, "Backend": { "Type": "vxlan" } }
$ # 振り分ける Pod 子ネットワーク(/24)のリストを確認する
$ sudo $HOME/bin/etcdctl \
  --endpoints=${ETCD_ENDPOINTS} \
  --ca-file=/etc/kubernetes/ssl/ca.pem \
  --cert-file=/etc/flanneld/ssl/flanneld.pem \
  --key-file=/etc/flanneld/ssl/flanneld-key.pem \
  ls ${FLANNEL_ETCD_PREFIX}/subnets
/kubernetes/network/subnets/172.30.19.0-24
$ # ある Pod ネットワークの flanneld の IP とネットワークパラメータを確認する
$ sudo $HOME/bin/etcdctl \
  --endpoints=${ETCD_ENDPOINTS} \
  --ca-file=/etc/kubernetes/ssl/ca.pem \
  --cert-file=/etc/flanneld/ssl/flanneld.pem \
  --key-file=/etc/flanneld/ssl/flanneld-key.pem \
  get ${FLANNEL_ETCD_PREFIX}/subnets/172.30.19.0-24
{"PublicIP":"10.64.3.7","BackendType":"vxlan","BackendData":{"VtepMAC":"d6:51:2e:80:5c:69"}}
```

### 各ノードの Pod のネットワークの通信を確保する

**各ノードでFlannelのデプロイが完成済み**、Pod の子ネットワークリスト(/24)を確認する

``` bash
$ sudo $HOME/bin/etcdctl \
  --endpoints=${ETCD_ENDPOINTS} \
  --ca-file=/etc/kubernetes/ssl/ca.pem \
  --cert-file=/etc/flanneld/ssl/flanneld.pem \
  --key-file=/etc/flanneld/ssl/flanneld-key.pem \
  ls ${FLANNEL_ETCD_PREFIX}/subnets
/kubernetes/network/subnets/172.30.19.0-24
/kubernetes/network/subnets/172.30.20.0-24
/kubernetes/network/subnets/172.30.21.0-24
```

当該各ノードに振り分ける Pod ネットワークは：172.30.19.0-24、172.30.20.0-24、172.30.21.0-24。

各ノードで各IPアドレスにPINGコマンドを実行する、通信できることを確認する：

``` bash
$ ping 172.30.19.1
$ ping 172.30.20.2
$ ping 172.30.21.3
```
