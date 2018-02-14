<!-- toc -->

tags: master, kube-apiserver, kube-scheduler, kube-controller-manager

# masterノードのデプロイ

kubernetes master ノードで使うコンポーネントリスト：

+ kube-apiserver
+ kube-scheduler
+ kube-controller-manager

今回、上記の３つコンポーネントを同じノードにデプロイ予定：

+ `kube-scheduler`、`kube-controller-manager` と `kube-apiserver` の間互いにAPIを叩いてる。
+ HAクラスターを構築する時、ただ同時に `kube-scheduler`、`kube-controller-manager` １つMasterノードで動ける、複数Masterで動ける時、leaderサーバーを選挙することが必要。

当該のドキュメントでkubernetes master ノードをデプロイする手順を紹介するが、**master HAを構築していない**。

master サーバー と node サーバー の Pods は docker ネットワークで通信するため、master サーバーで Flannel のインストールが必要。

## 利用変数

今回利用する変数が下記になる：

``` bash
$ export MASTER_IP=10.64.3.7  # 利用するMasterサーバーのIPアドレスを置き換える
$ # 必要なグローバル変数：SERVICE_CIDR、CLUSTER_CIDR、NODE_PORT_RANGE、ETCD_ENDPOINTS、BOOTSTRAP_TOKEN
$ source $HOME/bin/environment.sh
$
```

## 最新版Kubernetes実行ファイルダウンロード

下記が２つダウンロード方式がある(2を勧める)：

1. [github release ページ](https://github.com/kubernetes/kubernetes/releases) から tarball をダウンロードして、その後、ダウンロードファイルを解凍する

    ``` shell
    $ wget https://github.com/kubernetes/kubernetes/releases/download/v1.6.2/kubernetes.tar.gz
    $ tar -xzvf kubernetes.tar.gz
    ...
    $ cd kubernetes
    $ ./cluster/get-kube-binaries.sh
    ...
    ```

2. [`CHANGELOG`ページ](https://github.com/kubernetes/kubernetes/blob/master/CHANGELOG.md)から `client` または `server` tarball ファイルをダウンロードして

    `server` の tarball `kubernetes-server-linux-amd64.tar.gz` はすでに `client`(`kubectl`) ファイルを含めてるので、`kubernetes-client-linux-amd64.tar.gz`を再度ダウンロードする必要がなかった

    ``` shell
    $ # wget https://dl.k8s.io/v1.6.2/kubernetes-client-linux-amd64.tar.gz
    $ wget https://dl.k8s.io/v1.6.2/kubernetes-server-linux-amd64.tar.gz
    $ tar -xzvf kubernetes-server-linux-amd64.tar.gz
    ...
    $ cd kubernetes
    $ tar -xzvf  kubernetes-src.tar.gz
    ```

ダウンロードしたファイルを指定するPathにコピーする：

``` bash
$ sudo cp -r server/bin/{kube-apiserver,kube-controller-manager,kube-scheduler,kubectl,kube-proxy,kubelet} $HOME/bin/
$
```

## flanneld のインストールと配置

[Flannel ネットワークのデプロイ](./05_deploy_flannel_network.md)を参考してください。

## kubernetes 証明書の作成

kubernetes 証明書の作成用サインファイルを作成する

``` bash
$ cat > kubernetes-csr.json <<EOF
{
  "CN": "kubernetes",
  "hosts": [
    "127.0.0.1",
    "${MASTER_IP}",
    "${CLUSTER_KUBERNETES_SVC_IP}",
    "kubernetes",
    "kubernetes.default",
    "kubernetes.default.svc",
    "kubernetes.default.svc.cluster",
    "kubernetes.default.svc.cluster.local"
  ],
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "JP",
      "ST": "Tokyo",
      "L": "Tokyo",
      "O": "k8s",
      "OU": "System"
    }
  ]
}
EOF
```

+ もし hosts の設定内容が空文字じゃなければ、当該証明書が使える **IP 若くは ドメイン 一覧** を指定しなければいけない。なので、上記のファイルに master サーバーの IPアドレスを書き込んてる；
+ kube-apiserver で登録名が `kubernetes` の IP アドレス(Service Cluster IP)の追加が必要、一般的には kube-apiserver `--service-cluster-ip-range` で指定するIP Rangeの**一番目IPアドレス**，例) "10.254.0.1"；

  ``` bash
  $ kubectl get svc kubernetes
  NAME         CLUSTER-IP   EXTERNAL-IP   PORT(S)   AGE
  kubernetes   10.254.0.1   <none>        443/TCP   1d
  ```

kubernetes の証明書とキーを出力する

    ``` bash
    $ cfssl gencert -ca=/etc/kubernetes/ssl/ca.pem \
      -ca-key=/etc/kubernetes/ssl/ca-key.pem \
      -config=/etc/kubernetes/ssl/ca-config.json \
      -profile=kubernetes kubernetes-csr.json | cfssljson -bare kubernetes
    $ ls kubernetes*
    kubernetes.csr  kubernetes-csr.json  kubernetes-key.pem  kubernetes.pem
    $ sudo mkdir -p /etc/kubernetes/ssl/
    $ sudo mv kubernetes*.pem /etc/kubernetes/ssl/
    $ rm kubernetes.csr  kubernetes-csr.json
    ```

## kube-apiserverの起動と配置

### kube-apiserver を呼び出すため、Clientで利用する token ファイルを作成する

kubelet **首次启动**时向 kube-apiserver 发送 TLS Bootstrapping 请求，kube-apiserver 验证 kubelet 请求中的 token 是否与它配置的 token.csv 一致，如果一致则自动为 kubelet生成证书和秘钥。

``` bash
$ # 导入的 environment.sh 文件定义了 BOOTSTRAP_TOKEN 变量
$ cat > token.csv <<EOF
${BOOTSTRAP_TOKEN},kubelet-bootstrap,10001,"system:kubelet-bootstrap"
EOF
$ mv token.csv /etc/kubernetes/
$
```

### kube-apiserver の systemd unit ファイルを作成する

``` bash
$ cat  > kube-apiserver.service <<EOF
[Unit]
Description=Kubernetes API Server
Documentation=https://github.com/GoogleCloudPlatform/kubernetes
After=network.target

[Service]
ExecStart=$HOME/bin/kube-apiserver \\
  --admission-control=NamespaceLifecycle,LimitRanger,ServiceAccount,DefaultStorageClass,ResourceQuota \\
  --advertise-address=${MASTER_IP} \\
  --bind-address=${MASTER_IP} \\
  --insecure-bind-address=${MASTER_IP} \\
  --authorization-mode=RBAC \\
  --runtime-config=rbac.authorization.k8s.io/v1alpha1 \\
  --kubelet-https=true \\
  --experimental-bootstrap-token-auth \\
  --token-auth-file=/etc/kubernetes/token.csv \\
  --service-cluster-ip-range=${SERVICE_CIDR} \\
  --service-node-port-range=${NODE_PORT_RANGE} \\
  --tls-cert-file=/etc/kubernetes/ssl/kubernetes.pem \\
  --tls-private-key-file=/etc/kubernetes/ssl/kubernetes-key.pem \\
  --client-ca-file=/etc/kubernetes/ssl/ca.pem \\
  --service-account-key-file=/etc/kubernetes/ssl/ca-key.pem \\
  --etcd-cafile=/etc/kubernetes/ssl/ca.pem \\
  --etcd-certfile=/etc/kubernetes/ssl/kubernetes.pem \\
  --etcd-keyfile=/etc/kubernetes/ssl/kubernetes-key.pem \\
  --etcd-servers=${ETCD_ENDPOINTS} \\
  --enable-swagger-ui=true \\
  --allow-privileged=true \\
  --apiserver-count=3 \\
  --audit-log-maxage=30 \\
  --audit-log-maxbackup=3 \\
  --audit-log-maxsize=100 \\
  --audit-log-path=/var/lib/audit.log \\
  --event-ttl=1h \\
  --v=2
Restart=on-failure
RestartSec=5
Type=notify
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF
```

+ kube-apiserver 1.6 版から etcd v3 API を利用して、保存する(**etcd v3の保存構造が変更した**)
+ `--authorization-mode=RBAC` で権限を振り分けるモードを指定する、承認できないRequestを断る
+ kube-scheduler、kube-controller-manager は**http**プロトコルで kube-apiserver と通信するため、 kube-apiserver 一緒に同じサーバーにデプロイする場合が多い
+ kubelet、kube-proxy、kubectl その他 Node サーバーにデプロイして，**https**で kube-apiserverのAPIを叩く場合、お先に TLS 証明書の認証を行って、認証された場合、RBAC で権限わ振り分ける
+ kube-proxy、kubectl は証明書の中に User、Group を指定して、RBAC で権限を振り分ける
+ kubelet TLS Boostrap を利用した場合、`--kubelet-certificate-authority`、`--kubelet-client-certificate` と `--kubelet-client-key` を指定する禁止、両方とも設定された場合 kube-apiserver は kubelet 証明書を認証する時 "x509: certificate signed by unknown authority" エラーが出力する
+ `--admission-control` 項目が `ServiceAccount` を必ず含める、含めないとPluginのインストールが失敗する
+ `--bind-address` に `127.0.0.1`を設定できない
+ `--service-cluster-ip-range` に Service Cluster IP を設定して、当該IPアドレスRangeはルータで届けない
+ `--service-node-port-range=${NODE_PORT_RANGE}` で NodePort のPort範囲を指定する
+ kubernetes の情報はデフォルトに etcd の `/registry` パスに保存されたが、`--etcd-prefix` 項目で調整できる

full unit [kube-apiserver.service](./systemd/kube-apiserver.service)を参考してください。

### kube-apiserverの起動

``` bash
$ sudo cp kube-apiserver.service /etc/systemd/system/
$ sudo systemctl daemon-reload
$ sudo systemctl enable kube-apiserver
$ sudo systemctl start kube-apiserver
$ sudo systemctl status kube-apiserver
$
```

## kube-controller-manager の配置と起動

### kube-controller-manager systemd unit ファイルの作成

``` bash
$ cat > kube-controller-manager.service <<EOF
[Unit]
Description=Kubernetes Controller Manager
Documentation=https://github.com/GoogleCloudPlatform/kubernetes

[Service]
ExecStart=$HOME/bin/kube-controller-manager \\
  --address=127.0.0.1 \\
  --master=http://${MASTER_IP}:8080 \\
  --allocate-node-cidrs=true \\
  --service-cluster-ip-range=${SERVICE_CIDR} \\
  --cluster-cidr=${CLUSTER_CIDR} \\
  --cluster-name=kubernetes \\
  --cluster-signing-cert-file=/etc/kubernetes/ssl/ca.pem \\
  --cluster-signing-key-file=/etc/kubernetes/ssl/ca-key.pem \\
  --service-account-private-key-file=/etc/kubernetes/ssl/ca-key.pem \\
  --root-ca-file=/etc/kubernetes/ssl/ca.pem \\
  --leader-elect=true \\
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
```

+ `--address` の値が必ず `127.0.0.1` を設定する。原因は kube-apiserver が scheduler と controller-manager と同じサーバーに置いてる、そうじゃなければ、下記のエラーが出力する

    ``` bash
    $ kubectl get componentstatuses
    NAME                 STATUS      MESSAGE                                                                                        ERROR
    controller-manager   Unhealthy   Get http://127.0.0.1:10252/healthz: dial tcp 127.0.0.1:10252: getsockopt: connection refused
    scheduler            Unhealthy   Get http://127.0.0.1:10251/healthz: dial tcp 127.0.0.1:10251: getsockopt: connection refused
    ```

    参考：https://github.com/kubernetes-incubator/bootkube/issues/64

+ `--master=http://{MASTER_IP}:8080`：8080 portで kube-apiserver と通信
+ `--cluster-cidr` Cluster の Pod の CIDR 範囲値を設定して、当該ネットワークは Node 間に必ずルータで通信できる(flanneld)；
+ `--service-cluster-ip-range` Cluster の Service の CIDR 範囲値を設定して、当該ネットワークが必ず Node 間にルータで通信できない、且つkube-apiserver の同じ設定項目と一致することが必要
+ `--cluster-signing-*` 指定する証明書とキーで、TLS BootStrap のため、証明書とキーを作成する
+ `--root-ca-file` kube-apiserver 証明書に対して認証する、**当該の証明書を指定した後、Pod の ServiceAccount の中に CA 証明書ファイルを設定**；
+ `--leader-elect=true` 複数台Masterサーバーで Master クラスターとしてデプロイする時、 leaderとする `kube-controller-manager` Progressが選挙で決める

full unit が [kube-controller-manager.service](./systemd/kube-controller-manager.service)を参考してください。

### kube-controller-manager 起動

``` bash
$ sudo cp kube-controller-manager.service /etc/systemd/system/
$ sudo systemctl daemon-reload
$ sudo systemctl enable kube-controller-manager
$ sudo systemctl start kube-controller-manager
$
```

## kube-scheduler の起動と設定

### kube-scheduler の systemd unit ファイルを作成

``` bash
$ cat > kube-scheduler.service <<EOF
[Unit]
Description=Kubernetes Scheduler
Documentation=https://github.com/GoogleCloudPlatform/kubernetes

[Service]
ExecStart=$HOME/bin/kube-scheduler \\
  --address=127.0.0.1 \\
  --master=http://${MASTER_IP}:8080 \\
  --leader-elect=true \\
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
```

+ `--address` の値が必ず `127.0.0.1` を設定する。原因は kube-apiserver が scheduler と controller-manager と同じサーバーに置いてる
+ `--master=http://{MASTER_IP}:8080`：8080 portで kube-apiserver と通信
+ `--leader-elect=true` 複数台Masterサーバーで Master クラスターとしてデプロイする時、 leaderとする `kube-controller-manager` Progressが選挙で決める

full unit は [kube-scheduler.service](./systemd/kube-scheduler.service)を参考してください。

### kube-scheduler の起動

``` bash
$ sudo cp kube-scheduler.service /etc/systemd/system/
$ sudo systemctl daemon-reload
$ sudo systemctl enable kube-scheduler
$ sudo systemctl start kube-scheduler
$
```

## master サーバーのヘルスチェック

``` bash
$ kubectl get componentstatuses
NAME                 STATUS    MESSAGE              ERROR
controller-manager   Healthy   ok
scheduler            Healthy   ok
etcd-0               Healthy   {"health": "true"}
etcd-1               Healthy   {"health": "true"}
etcd-2               Healthy   {"health": "true"}
```