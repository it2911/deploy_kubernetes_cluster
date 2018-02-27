<!-- toc -->

tags: node, flanneld, docker, kubeconfig, kubelet, kube-proxy

# Node クラスターのデプロイ

kubernetes Node サーバーが下記のコンポーネントを含めてる：

+ flanneld
+ docker
+ kubelet
+ kube-proxy

## 利用変数

今回利用する変数が下記になる：

``` bash
$ # MASTER IP
$ export MASTER_IP=10.64.3.7
$ export KUBE_APISERVER="https://${MASTER_IP}:6443"
$ # デプロイ IP アドレス
$ export NODE_IP=10.64.3.7
$ # ETCD_ENDPOINTS、FLANNEL_ETCD_PREFIX、CLUSTER_CIDR、CLUSTER_DNS_SVC_IP、CLUSTER_DNS_DOMAIN、SERVICE_CIDR 変数を導入する
$ source /root/local/bin/environment.sh
$
```

## flanneld のインストールと配置

[Flannel ネットワークのデプロイ](./05_deploy_flannel_network.md)を参考してください。

## docker のインストールと配置

dockerのインストールが[Docker社のインストールドキュメント](https://docs.docker.com/install/)を参考することを勧める

dockerをインストールしたら、docker.serviceの修正が必要です。dockerのネットワーク情報をflannelから取得しているので、flannelのネット環境変数を設定してください。

  ``` bash
  $ diff /usr/lib/systemd/system/docker.service.old /usr/lib/systemd/system/docker.service
  7a8
  > EnvironmentFile=-/run/flannel/docker
  12c13
  < ExecStart=/usr/bin/dockerd
  ---
  > ExecStart=/usr/bin/dockerd --log-level=error $DOCKER_NETWORK_OPTIONS
  ```

docker バージョンが 1.13 から、**iptables FORWARD chainのデフォルトポリシーがDROPを設定したので**、その他のNodeのPod IPに ping を実行したら、通信できなくなった。その場合、手動でポリシーを `ACCEPT` に設定してください。

  ``` bash
  $ sudo iptables -P FORWARD ACCEPT
  ```
  サーバーが再起動するなら、**iptables FORWARD chainのデフォルト設定ポリシーがDROPに戻ること**を防止するため、下記のコマンドを/etc/rc.localファイルに書き込む。
  
  ``` bash
  sleep 60 && /sbin/iptables -P FORWARD ACCEPT
  ```

### dockerd起動する

``` bash
$ sudo iptables -F && sudo iptables -X && sudo iptables -F -t nat && sudo iptables -X -t nat
$ sudo systemctl start docker
```

+ firewalld(centos7)/ufw(ubuntu16.04)を必ずクローズしてください。クローズしなければ、iptables 規則が重複に作成する
+ 古い iptables rules と chains 規則をクリアすることが勧める

### docker サービスの確認

``` bash
$ docker version
```

## kubelet のインストールと配置

kubelet 起動時、 kube-apiserver に TLS bootstrapping を請求するため、お先に bootstrap token ファイル中の kubelet-bootstrap ユーザーに system:node-bootstrapper ロールを振り分ける、この後 kubelet が認証Request(certificatesigningrequests)の権限を持たせる：

``` bash
$ kubectl create clusterrolebinding kubelet-bootstrap --clusterrole=system:node-bootstrapper --user=kubelet-bootstrap
$
```

+ `--user=kubelet-bootstrap` は `/etc/kubernetes/token.csv` ファイルで指定したユーザー名、紐付ける同時に `/etc/kubernetes/bootstrap.kubeconfig`ファイルに書き込む；

### 最新版 kubelet と kube-proxy 実行ファイルダウンロード

``` bash
$ wget https://dl.k8s.io/v1.6.2/kubernetes-server-linux-amd64.tar.gz
$ tar -xzvf kubernetes-server-linux-amd64.tar.gz
$ cd kubernetes
$ tar -xzvf  kubernetes-src.tar.gz
$ sudo cp -r ./server/bin/{kube-proxy,kubelet} $HOME/bin/
$
```

## kubelet bootstrapping kubeconfig ファイルの作成

``` bash
$ # クラスターパラメタの設定
$ kubectl config set-cluster kubernetes \
  --certificate-authority=/etc/kubernetes/ssl/ca.pem \
  --embed-certs=true \
  --server=${KUBE_APISERVER} \
  --kubeconfig=bootstrap.kubeconfig
$ # Client認証設定
$ kubectl config set-credentials kubelet-bootstrap \
  --token=${BOOTSTRAP_TOKEN} \
  --kubeconfig=bootstrap.kubeconfig
$ # Context設定
$ kubectl config set-context default \
  --cluster=kubernetes \
  --user=kubelet-bootstrap \
  --kubeconfig=bootstrap.kubeconfig
$ # default context設定
$ kubectl config use-context default --kubeconfig=bootstrap.kubeconfig
$ mv bootstrap.kubeconfig /etc/kubernetes/
```

+ `--embed-certs` が `true` を設定する時、时表示将 `certificate-authority` 証明書を `bootstrap.kubeconfig` ファイルに書き込む
+ kubelet 認証用パラメターに**証明書とキーを設定する必要がない**、紐付ける時 `kube-apiserver` が自動的に払い出す；

### kubelet の systemd unit ファイルを作成

``` bash
$ sudo mkdir /var/lib/kubelet # 必须先创建工作目录
$ cat > kubelet.service <<EOF
[Unit]
Description=Kubernetes Kubelet
Documentation=https://github.com/GoogleCloudPlatform/kubernetes
After=docker.service
Requires=docker.service

[Service]
WorkingDirectory=/var/lib/kubelet
ExecStart=$HOME/bin/kubelet \\
  --address=${NODE_IP} \\
  --hostname-override=${NODE_IP} \\
  --pod-infra-container-image=registry.access.redhat.com/rhel7/pod-infrastructure:latest \\
  --experimental-bootstrap-kubeconfig=/etc/kubernetes/bootstrap.kubeconfig \\
  --kubeconfig=/etc/kubernetes/kubelet.kubeconfig \\
  --require-kubeconfig \\
  --cert-dir=/etc/kubernetes/ssl \\
  --cluster-dns=${CLUSTER_DNS_SVC_IP} \\
  --cluster-domain=${CLUSTER_DNS_DOMAIN} \\
  --hairpin-mode promiscuous-bridge \\
  --allow-privileged=true \\
  --serialize-image-pulls=false \\
  --logtostderr=true \\
  --v=2
ExecStartPost=/sbin/iptables -A INPUT -s 10.0.0.0/8 -p tcp --dport 4194 -j ACCEPT
ExecStartPost=/sbin/iptables -A INPUT -s 172.16.0.0/12 -p tcp --dport 4194 -j ACCEPT
ExecStartPost=/sbin/iptables -A INPUT -s 192.168.0.0/16 -p tcp --dport 4194 -j ACCEPT
ExecStartPost=/sbin/iptables -A INPUT -p tcp --dport 4194 -j DROP
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
```

+ `--address` は `127.0.0.1`を設定することができない，`127.0.0.1`を設定したら、Pods が kubelet の API へ叩けなくなる。原因は Pods が `127.0.0.1` を叩く時、kubelet へじゃなく、Podsの自身へ叩いた
+ `--hostname-override` 項目を設定したら、 `kube-proxy` の `--hostname-override` 項目の設定も必要だ、設定しなければ Node を見つからない可能性がある；
+ `--experimental-bootstrap-kubeconfig` に bootstrap kubeconfig ファイルを設定する，kubelet は当該ファイルのユーザー名とtokenを使って、kube-apiserver に TLS Bootstrapping Requestを送る
+ 管理者は CSR 認証Requestを承認したら，kubelet が自動的に `--cert-dir` フォルダで証明書とキー(`kubelet-client.crt` と `kubelet-client.key`)を作成して、`--kubeconfig` ファイルに書き込む(`--kubeconfig` で指定したファイルを自動的に作成する) 
+ `--kubeconfig` の設定ファイルに `kube-apiserver` を設定することを勧める。`—api-servers`を指定しなければ 、 必ず`--require-kubeconfig` 項目を指定してください。`--require-kubeconfig` 項目を追加したら、設定ファイルから kue-apiserver 情報を取得する。両方とも設定しなければ、 kubelet が起動した後、kube-apiserver を見つからない。(ログで API Server を見つからないエラーが表示する），`kubectl get nodes` を実行しても、Node 情報を返しない 
+ `--cluster-dns` は kubedns の Service IPを指定する(予め準備して，kubedns を作成する時、当該 IP アドレスを指定することが可能)，`--cluster-domain` はドメインの拡張子を指定する。この２つフラグが同時に設定する時のみ、有効化になる。
+ kubelet cAdvisor はデフォルトに**全てノード**の 4194 portのrequestを受ける。外に飛べる機器に対して危ないため、`ExecStartPost` 項目で iptables 規則を設定して、同じネットワークの機器のみ 4194 portをアクセスできる。

full unit が [kubelet.service](./systemd/kubelet.service)を参考してください。

### kubeletの起動

``` bash
$ sudo cp kubelet.service /etc/systemd/system/kubelet.service
$ sudo systemctl daemon-reload
$ sudo systemctl enable kubelet
$ sudo systemctl start kubelet
$ systemctl status kubelet
$
```

### kubelet の TLS 証明書認証を承認する

kubelet が初めて起動する時、kube-apiserver へ証明書認証Requestを送る、kubernetes システム管理者に承認されたら、Node をクラスターに加入する。

承認されていない CSR requestを確認する：

``` bash
$ kubectl get csr
NAME        AGE       REQUESTOR           CONDITION
csr-2b308   4m        kubelet-bootstrap   Pending
$ kubectl get nodes
No resources found.
```

CSR の請求を受けて、承認する：

``` bash
$ kubectl certificate approve csr-2b308
certificatesigningrequest "csr-2b308" approved
$ kubectl get nodes
NAME        STATUS    AGE       VERSION
10.64.3.7   Ready     49m       v1.6.2
```

kubelet kubeconfig ファイル、証明書とキーが自動的に作成した：

``` bash
$ ls -l /etc/kubernetes/kubelet.kubeconfig
-rw------- 1 root root 2284 Apr  7 02:07 /etc/kubernetes/kubelet.kubeconfig
$ ls -l /etc/kubernetes/ssl/kubelet*
-rw-r--r-- 1 root root 1046 Apr  7 02:07 /etc/kubernetes/ssl/kubelet-client.crt
-rw------- 1 root root  227 Apr  7 02:04 /etc/kubernetes/ssl/kubelet-client.key
-rw-r--r-- 1 root root 1103 Apr  7 02:07 /etc/kubernetes/ssl/kubelet.crt
-rw------- 1 root root 1675 Apr  7 02:07 /etc/kubernetes/ssl/kubelet.key
```

## kube-proxy設定

### kube-proxy 証明書の作成

kube-proxy 証明書サインの作成：

``` bash
$ cat kube-proxy-csr.json
{
  "CN": "system:kube-proxy",
  "hosts": [],
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
```

+ CN は当該証明書の User に `system:kube-proxy`を指定する
+ `kube-apiserver` で予め定義した RoleBinding `system:node-proxier` は User `system:kube-proxy` と Role `system:node-proxier` 紐付ける。当該 Role は `kube-apiserver` のProxy の関連 API を叩く権限を振り分ける
+ hosts 項目に空リストを設定する；

kube-proxy のClient証明書とキーの作成：

``` bash
$ cfssl gencert -ca=/etc/kubernetes/ssl/ca.pem \
  -ca-key=/etc/kubernetes/ssl/ca-key.pem \
  -config=/etc/kubernetes/ssl/ca-config.json \
  -profile=kubernetes  kube-proxy-csr.json | cfssljson -bare kube-proxy
$ ls kube-proxy*
kube-proxy.csr  kube-proxy-csr.json  kube-proxy-key.pem  kube-proxy.pem
$ sudo mv kube-proxy*.pem /etc/kubernetes/ssl/
$ rm kube-proxy.csr  kube-proxy-csr.json
$
```

### kube-proxy kubeconfig ファイルの作成

``` bash
$ # クラスターパラメターの設定
$ kubectl config set-cluster kubernetes \
  --certificate-authority=/etc/kubernetes/ssl/ca.pem \
  --embed-certs=true \
  --server=${KUBE_APISERVER} \
  --kubeconfig=kube-proxy.kubeconfig
$ # Client認証パラメターの設定
$ kubectl config set-credentials kube-proxy \
  --client-certificate=/etc/kubernetes/ssl/kube-proxy.pem \
  --client-key=/etc/kubernetes/ssl/kube-proxy-key.pem \
  --embed-certs=true \
  --kubeconfig=kube-proxy.kubeconfig
$ # Contextのパラメターの設定
$ kubectl config set-context default \
  --cluster=kubernetes \
  --user=kube-proxy \
  --kubeconfig=kube-proxy.kubeconfig
$ # Contextの設定
$ kubectl config use-context default --kubeconfig=kube-proxy.kubeconfig
$ mv kube-proxy.kubeconfig /etc/kubernetes/
```

+ クラスターパラメターの設定とClient認証パラメターの `--embed-certs` に `true` を設定して、当該の設定で、`certificate-authority`、`client-certificate` と `client-key` の証明書内容を作成した `kube-proxy.kubeconfig` ファイルに書き込む
+ `kube-proxy.pem` 証明書の CN が `system:kube-proxy`，`kube-apiserver` である RoleBinding `cluster-admin` はUser `system:kube-proxy` と Role `system:node-proxier` 紐付ける。当該 Role は `kube-apiserver` の Proxy の関連 API を叩く権限を振り分ける

### kube-proxy の systemd unit ファイルの作成

``` bash
$ sudo mkdir -p /var/lib/kube-proxy # 必ずお先にデータを保存するフォルダを用意する
$ cat > kube-proxy.service <<EOF
[Unit]
Description=Kubernetes Kube-Proxy Server
Documentation=https://github.com/GoogleCloudPlatform/kubernetes
After=network.target

[Service]
WorkingDirectory=/var/lib/kube-proxy
ExecStart=$HOME/bin/kube-proxy \\
  --bind-address=${NODE_IP} \\
  --hostname-override=${NODE_IP} \\
  --cluster-cidr=${CLUSTER_CIDR} \\
  --kubeconfig=/etc/kubernetes/kube-proxy.kubeconfig \\
  --logtostderr=true \\
  --v=2
Restart=on-failure
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF
```

+ `--hostname-override` の項目値は必ず kubelet の項目値と同じ、違ったら kube-proxy が起動した後、Nodeを見つからない、iptables 規則を作成しない
+ `--cluster-cidr` 必ず kube-controller-manager の `--cluster-cidr` 項目設定値と同じ；
+ kube-proxy は `--cluster-cidr` によって、クラスターの内部と外部パッケージを判断する。 `--cluster-cidr` または `--masquerade-all` 項目を指定した後、 kube-proxy は Service IP からRequestに SNAT を作成する。
+ `--kubeconfig` で指定ファイルに kube-apiserver のアドレス、ユーザ名、証明書、キーと認証情報を書き込む
+ 予め RoleBinding `cluster-admin` を定義して、User `system:kube-proxy` と Role `system:node-proxier` 紐付ける、当該 Role は `kube-apiserver` の Proxy の関連 API を叩く権限を振り分ける

full unit は [kube-proxy.service](./systemd/kube-proxy.service)を参考してください。

### kube-proxy の起動

``` bash
$ sudo cp kube-proxy.service /etc/systemd/system/
$ sudo systemctl daemon-reload
$ sudo systemctl enable kube-proxy
$ sudo systemctl start kube-proxy
$ systemctl status kube-proxy
$
```

## クラスターの検証

定義ファイル：

``` bash
$ cat nginx-ds.yml
apiVersion: v1
kind: Service
metadata:
  name: nginx-ds
  labels:
    app: nginx-ds
spec:
  type: NodePort
  selector:
    app: nginx-ds
  ports:
  - name: http
    port: 80
    targetPort: 80

---

apiVersion: extensions/v1beta1
kind: DaemonSet
metadata:
  name: nginx-ds
  labels:
    addonmanager.kubernetes.io/mode: Reconcile
spec:
  template:
    metadata:
      labels:
        app: nginx-ds
    spec:
      containers:
      - name: my-nginx
        image: nginx:1.7.9
        ports:
        - containerPort: 80
```

Pod の立ち上げる：

``` bash
$ kubectl create -f nginx-ds.yml
service "nginx-ds" created
daemonset "nginx-ds" created
```

### 各ノードステータスの確認

``` bash
$ kubectl get nodes
NAME        STATUS    AGE       VERSION
10.64.3.7   Ready     8d        v1.6.2
10.64.3.8   Ready     8d        v1.6.2
```

全て Ready を表示する時、正常と思われる。

### 各 Node の Pod IP 互いに通信検証

``` bash
$ kubectl get pods  -o wide|grep nginx-ds
nginx-ds-6ktz8              1/1       Running            0          5m        172.30.25.19   10.64.3.7
nginx-ds-6ktz9              1/1       Running            0          5m        172.30.20.20   10.64.3.8
```

nginx-ds の Pod IP は `172.30.25.19`、`172.30.20.20`、全て Node で この IPアドレス を ping して、通信できるかどうかを確認する。

### サービス IP と Port の通信検証

``` bash
$ kubectl get svc |grep nginx-ds
nginx-ds     10.254.136.178   <nodes>       80:8744/TCP         11m
```

可见：

+ サービスIP：10.254.136.178
+ サービスPort：80
+ NodePort：8744

全て Node で実行する：

``` bash
$ curl 10.254.136.178 # `kubectl get svc |grep nginx-ds` で出力した IPアドレス
$
```

nginx トップページを表示する。

### 检查服务的 NodePort 可达性

全て Node で下記のコマンドを実行する：

``` bash
$ export NODE_IP=10.64.3.7 # 当前 Node 的 IP
$ export NODE_PORT=8744 # `kubectl get svc |grep nginx-ds` 输出中 80 端口映射的 NodePort
$ curl ${NODE_IP}:${NODE_PORT}
$
```

nginx のTOP ページを表示する
