<!-- toc -->

tags: etcd

# 高可用性の etcd クラスター環境の構築

kuberntes システムは etcd を利用して、設定値を保存する、このドキュメントは三つノードで構成した高可用性の etcd クラスター環境の構築ステップを紹介する。
既にあるノードを利用して、`etcd-host0`、`etcd-host1`、`etcd-host2`の名前を付ける：

+ etcd-host0：10.64.3.7
+ etcd-host1：10.64.3.8
+ etcd-host2：10.66.3.86

## 利用変数

利用変数の設定について、下記の内容を参考してください：

``` bash
$ export NODE_NAME=etcd-host0 # 当該ノードの名前(何でもいいです、その他ノードの名前と区別してください)
$ export NODE_IP=10.64.3.7 # 当該のノードの IP アドレス
$ export NODE_IPS="10.64.3.7 10.64.3.8 10.66.3.86" # etcd クラスターのすべて機器の IP アドレス
$ # etcd クラスター通信用のIPとポートを設定する
$ export ETCD_NODES=etcd-host0=https://10.64.3.7:2380,etcd-host1=https://10.64.3.8:2380,etcd-host2=https://10.66.3.86:2380
$ # その他のグローバル環境変数をインポートする：ETCD_ENDPOINTS、FLANNEL_ETCD_PREFIX、CLUSTER_CIDR
$ source /root/local/bin/environment.sh
$
```

## 二進法ファイルをダウンロードする

`https://github.com/coreos/etcd/releases` のページで最新版 `etcd` の二進法ファイルをダウンロードする：

``` bash
$ wget https://github.com/coreos/etcd/releases/download/v3.1.6/etcd-v3.1.6-linux-amd64.tar.gz
$ tar -xvf etcd-v3.1.6-linux-amd64.tar.gz
$ sudo mv etcd-v3.1.6-linux-amd64/etcd* /root/local/bin
$
```

## TLS の証明書とキーファイルを作成する

安全通信を守れるため、etcd クラスターのノードの間の通信が TLS で暗号化することが必要だ。

etcd 証明書サイン用ファイルを作成する：

``` bash
$ cat > etcd-csr.json <<EOF
{
  "CN": "etcd",
  "hosts": [
    "127.0.0.1",
    "${NODE_IP}"
  ],
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "CN",
      "ST": "BeiJing",
      "L": "BeiJing",
      "O": "k8s",
      "OU": "System"
    }
  ]
}
EOF
```

+ hosts 項目は証明書を使える etcd ノード IP アドレスを指定する；

etcd の証明書とキーファイルを作成する：

``` bash
$ cfssl gencert -ca=/etc/kubernetes/ssl/ca.pem \
  -ca-key=/etc/kubernetes/ssl/ca-key.pem \
  -config=/etc/kubernetes/ssl/ca-config.json \
  -profile=kubernetes etcd-csr.json | cfssljson -bare etcd
$ ls etcd*
etcd.csr  etcd-csr.json  etcd-key.pem etcd.pem
$ sudo mkdir -p /etc/etcd/ssl
$ sudo mv etcd*.pem /etc/etcd/ssl
$ rm etcd.csr  etcd-csr.json
```

## etcd の systemd unit ファイルを作成する

``` bash
$ sudo mkdir -p /var/lib/etcd  # 予めフォルダを作成する
$ cat > etcd.service <<EOF
[Unit]
Description=Etcd Server
After=network.target
After=network-online.target
Wants=network-online.target
Documentation=https://github.com/coreos

[Service]
Type=notify
WorkingDirectory=/var/lib/etcd/
ExecStart=/root/local/bin/etcd \\
  --name=${NODE_NAME} \\
  --cert-file=/etc/etcd/ssl/etcd.pem \\
  --key-file=/etc/etcd/ssl/etcd-key.pem \\
  --peer-cert-file=/etc/etcd/ssl/etcd.pem \\
  --peer-key-file=/etc/etcd/ssl/etcd-key.pem \\
  --trusted-ca-file=/etc/kubernetes/ssl/ca.pem \\
  --peer-trusted-ca-file=/etc/kubernetes/ssl/ca.pem \\
  --initial-advertise-peer-urls=https://${NODE_IP}:2380 \\
  --listen-peer-urls=https://${NODE_IP}:2380 \\
  --listen-client-urls=https://${NODE_IP}:2379,http://127.0.0.1:2379 \\
  --advertise-client-urls=https://${NODE_IP}:2379 \\
  --initial-cluster-token=etcd-cluster-0 \\
  --initial-cluster=${ETCD_NODES} \\
  --initial-cluster-state=new \\
  --data-dir=/var/lib/etcd
Restart=on-failure
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF
```

+ `etcd` のデータフォルダは `/var/lib/etcd` を指定する、`etcd`を起動する前、当該のフォルダを予め作成するが必要だ；
+ 通信安全性のため、etcdのキーファイル(cert-fileとkey-file)、Peers 通信証明書と CA 証明書(peer-cert-file、peer-key-file、peer-trusted-ca-file)、クライアントのCA証明書（trusted-ca-file）の指定が必要だ；
+ `--initial-cluster-state` の値は `new` の時、`--name` のパラメータは必ず `--initial-cluster` リストに入れる；

unit ファイルはこのリンクで参考してください：[etcd.service](https://github.com/opsnull/follow-me-install-kubernetes-cluster/blob/master/systemd/etcd.service)

## etcd サービスを起動する

``` bash
$ sudo mv etcd.service /etc/systemd/system/
$ sudo systemctl daemon-reload
$ sudo systemctl enable etcd
$ sudo systemctl start etcd
$ systemctl status etcd
$
```

最初のノードで etcd を実行する時、その他のノードの etcd がクラスター環境に加入しているので、しばらく待つ状態になる。

すべての etcd ノードで上記の手順で実行してください。

## サービス検証

etcd クラスター環境をデプロイしたら、いずれ etcd ノードで、下記のコマンドを実行する：

``` bash
$ for ip in ${NODE_IPS}; do
  ETCDCTL_API=3 /root/local/bin/etcdctl \
  --endpoints=https://${ip}:2379  \
  --cacert=/etc/kubernetes/ssl/ca.pem \
  --cert=/etc/etcd/ssl/etcd.pem \
  --key=/etc/etcd/ssl/etcd-key.pem \
  endpoint health; done
```

期待結果：

``` text
2017-04-10 14:50:50.011317 I | warning: ignoring ServerName for user-provided CA for backwards compatibility is deprecated
https://10.64.3.7:2379 is healthy: successfully committed proposal: took = 1.687897ms
2017-04-10 14:50:50.061577 I | warning: ignoring ServerName for user-provided CA for backwards compatibility is deprecated
https://10.64.3.8:2379 is healthy: successfully committed proposal: took = 1.246915ms
2017-04-10 14:50:50.104718 I | warning: ignoring ServerName for user-provided CA for backwards compatibility is deprecated
https://10.66.3.86:2379 is healthy: successfully committed proposal: took = 1.509229ms
```

各ノード etcd の出力はすべて healthy の場合、クラスターが立ち上げることが成功だ（warning 情報を無視してください）。

