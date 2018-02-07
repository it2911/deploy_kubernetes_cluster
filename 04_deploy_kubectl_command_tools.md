<!-- toc -->

tags: kubectl

# kubectl デプロイ

kubectl は `~/.kube/config` 配置ファイルから kube-apiserver アドレス、証明書、ユーザー情報などを取得する、`~/.kube/config` ファイルがない場合、下記のエラーが出力する：

``` bash
$  kubectl get pods
The connection to the server localhost:8080 was refused - did you specify the right host or port?
```

当該のドキュメントは kubernetes クラスターのコマンドツール kubectl のダウンロードと配置ステップについて紹介する。

まず**すべて kubectl コマンドを実行するノード**に kubectl の二進法ファイルと `~/.kube/config` 配置ファイルをコピーする。

## 利用変数

利用変数の定義が下記を参考してください：

``` bash
$ export MASTER_IP=10.64.3.7 # 替换为 kubernetes master 集群任一机器 IP
$ export KUBE_APISERVER="https://${MASTER_IP}:6443"
```

+ 变量 KUBE_APISERVER 指定 kubelet 访问的 kube-apiserver 的地址，后续被写入 `~/.kube/config` 配置文件；

## kubectl ダウンロード

``` bash
$ wget https://dl.k8s.io/v1.6.2/kubernetes-client-linux-amd64.tar.gz
$ tar -xzvf kubernetes-client-linux-amd64.tar.gz
$ sudo cp kubernetes/client/bin/kube* $HOME/bin/
$ chmod a+x $HOME/bin/kube*
$ export PATH=$HOME/bin:$PATH
```

## admin 証明書を作成する

kubectl と kube-apiserver の間の安全通信するため、 TLS 証明書とキーファイルが必要だ。

admin 証明書サインを作成する

``` bash
$ cat admin-csr.json
{
  "CN": "admin",
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
      "O": "system:masters",
      "OU": "System"
    }
  ]
}
```

+ `kube-apiserver` は `RBAC` を利用して、( `kubelet`、`kube-proxy`、`Pod`)クライアントの認定を行う；
+ `kube-apiserver` は `RBAC` に使用させるため `RoleBindings` を予め定義した，例えば `cluster-admin` は Group `system:masters` と Role `cluster-admin` と紐づけて，当該の Role に`kube-apiserver` の**すべて API**を呼び出せる権限を渡した；
+ O は証明書の Group が `system:masters`を設定する。証明書がCAにサインされた、且つ証明書Groupは `system:masters` ので、`kubelet` は当該証明書を使って `kube-apiserver` へアクセスする時、 すべて API へアクセスできる権限を渡した；
+ hosts 項目値は空リスト；

admin 証明書とキーファイルを作成する：

``` bash
$ sudo cfssl gencert -ca=/etc/kubernetes/ssl/ca.pem \
  -ca-key=/etc/kubernetes/ssl/ca-key.pem \
  -config=/etc/kubernetes/ssl/ca-config.json \
  -profile=kubernetes admin-csr.json | cfssljson -bare admin
$ ls admin*
admin.csr  admin-csr.json  admin-key.pem  admin.pem
$ sudo mv admin*.pem /etc/kubernetes/ssl/
$ rm admin.csr admin-csr.json
$
```

## kubectl kubeconfig ファイルを作成する

``` bash
$ # クラスター変数設定
$ kubectl config set-cluster kubernetes \
  --certificate-authority=/etc/kubernetes/ssl/ca.pem \
  --embed-certs=true \
  --server=${KUBE_APISERVER}
$ # クライアント認証変数を設定する
$ kubectl config set-credentials admin \
  --client-certificate=/etc/kubernetes/ssl/admin.pem \
  --embed-certs=true \
  --client-key=/etc/kubernetes/ssl/admin-key.pem
$ # コンテキストの変数を設定する
$ kubectl config set-context kubernetes \
  --cluster=kubernetes \
  --user=admin
$ # デフォルトコンテキストを設定する
$ kubectl config use-context kubernetes
```

+ `admin.pem` 証明書 O 項目値は `system:masters`、 `kube-apiserver` で定義された RoleBinding `cluster-admin` は Group `system:masters` と Role `cluster-admin` と紐づけて、当該の Role に `kube-apiserver` のAPIを呼び出せる権限を渡した；
+ 作成した kubeconfig が `~/.kube/config` ファイルに保存する；

## kubeconfig ファイルの配布

`~/.kube/config` ファイルを `kubelet` コマンドを動けるノードの `~/.kube/` フォルダにコピーする。
