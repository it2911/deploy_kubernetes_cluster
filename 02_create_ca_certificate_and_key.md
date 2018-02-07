<!-- toc -->

tags: TLS, CA

# CA 証明書とキーファイルの作成

`kubernetes` の各コンポーネントは `TLS` 証明書で通信内容を暗号化することが必要だ。今回 `CloudFlare` の PKI ツール [cfssl](https://github.com/cloudflare/cfssl) で Certificate Authority (CA) 証明書とキーファイルを作成する。CA は自己署名証明書、CA証明書を利用してその他サービスの TLS 証明書を作成する。

## `CFSSL` をインストールする

``` bash
$ wget https://pkg.cfssl.org/R1.2/cfssl_linux-amd64
$ chmod +x cfssl_linux-amd64
$ sudo mv cfssl_linux-amd64 $HOME/bin/cfssl

$ wget https://pkg.cfssl.org/R1.2/cfssljson_linux-amd64
$ chmod +x cfssljson_linux-amd64
$ sudo mv cfssljson_linux-amd64 $HOME/bin/cfssljson

$ wget https://pkg.cfssl.org/R1.2/cfssl-certinfo_linux-amd64
$ chmod +x cfssl-certinfo_linux-amd64
$ sudo mv cfssl-certinfo_linux-amd64 $HOME/bin/cfssl-certinfo

$ export PATH=$HOME/bin:$PATH
$ mkdir ssl
$ cd ssl
$
```

## CA (Certificate Authority) を作成する

CA の配置ファイルを作成する：

``` bash
$ cat ca-config.json
{
  "signing": {
    "default": {
      "expiry": "8760h"
    },
    "profiles": {
      "kubernetes": {
        "usages": [
            "signing",
            "key encipherment",
            "server auth",
            "client auth"
        ],
        "expiry": "8760h"
      }
    }
  }
}
```

+ `ca-config.json`：いつく profiles を設定できる，証明書の有効期限、使用場所などパラメータを指定する；且つ、今後別の証明書をサインする時にも profile の値を関連する；
+ `signing`：作成した証明書がそのた証明書にサインできることの設定項目；作成した ca.pem 証明書の中 `CA=TRUE`；
+ `server auth`：client は CA を利用して server から提供証明書に検証できる；
+ `client auth`：server は CA を利用して client から提供証明書に検証できる；

CA 証明書サインファイルの作成：

``` bash
$ cat ca-csr.json
{
  "CN": "kubernetes",
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

+ "CN"：`Common Name`，kube-apiserver は証明書の当該項目の値でリクエストのユーザー名 (User Name) として設定する；ブラウザは当該の項目の値でウェブサイトの不法アクセスするかをチェックする；
+ "O"：`Organization`，kube-apiserver は証明書の当該項目の値でリクエストの所属グループ (Group) として設定する；

CA 証明書とキーファイルを作成する：

``` bash
$ cfssl gencert -initca ca-csr.json | cfssljson -bare ca
$ ls ca*
ca-config.json  ca.csr  ca-csr.json  ca-key.pem  ca.pem
$
```

## 証明書の配布

作成した CA 証明書、キーファイルと設定ファイルを、**すべてノード**の `/etc/kubernetes/ssl` フォルダにコピーする

``` bash
$ sudo mkdir -p /etc/kubernetes/ssl
$ sudo cp ca* /etc/kubernetes/ssl
$
```

## 証明書の有効性検証

kubernetes 証明書の有効性の検証を例として挙げる：

### `openssl` コマンドを利用する

``` bash
$ openssl x509  -noout -text -in  kubernetes.pem
...
    Signature Algorithm: sha256WithRSAEncryption
        Issuer: C=CN, ST=BeiJing, L=BeiJing, O=k8s, OU=System, CN=Kubernetes
        Validity
            Not Before: Apr  5 05:36:00 2017 GMT
            Not After : Apr  5 05:36:00 2018 GMT
        Subject: C=CN, ST=BeiJing, L=BeiJing, O=k8s, OU=System, CN=kubernetes
...
        X509v3 extensions:
            X509v3 Key Usage: critical
                Digital Signature, Key Encipherment
            X509v3 Extended Key Usage:
                TLS Web Server Authentication, TLS Web Client Authentication
            X509v3 Basic Constraints: critical
                CA:FALSE
            X509v3 Subject Key Identifier:
                DD:52:04:43:10:13:A9:29:24:17:3A:0E:D7:14:DB:36:F8:6C:E0:E0
            X509v3 Authority Key Identifier:
                keyid:44:04:3B:60:BD:69:78:14:68:AF:A0:41:13:F6:17:07:13:63:58:CD

            X509v3 Subject Alternative Name:
                DNS:kubernetes, DNS:kubernetes.default, DNS:kubernetes.default.svc, DNS:kubernetes.default.svc.cluster, DNS:kubernetes.default.svc.cluster.local, IP Address:127.0.0.1, IP Address:10.64.3.7, IP Address:10.254.0.1
...
```

+ `Issuer` 項目の内容と `ca-csr.json` の内容が一致かどうかを確認する；
+ `Subject` 項目の内容と `kubernetes-csr.json` の内容が一致かどうかを確認する；
+ `X509v3 Subject Alternative Name` 項目の内容と `kubernetes-csr.json` の内容が一致かどうかを確認する；
+ `X509v3 Key Usage、Extended Key Usage` 項目の内容と `ca-config.json` の `kubernetes` profile の内容が一致かどうかを確認する；

### `cfssl-certinfo` コマンドを利用する

``` bash
$ cfssl-certinfo -cert kubernetes.pem
...
{
  "subject": {
    "common_name": "kubernetes",
    "country": "CN",
    "organization": "k8s",
    "organizational_unit": "System",
    "locality": "BeiJing",
    "province": "BeiJing",
    "names": [
      "JP",
      "Tokyo",
      "Tokyo",
      "k8s",
      "System",
      "kubernetes"
    ]
  },
  "issuer": {
    "common_name": "Kubernetes",
    "country": "JP",
    "organization": "k8s",
    "organizational_unit": "System",
    "locality": "Tokyo",
    "province": "Tokyo",
    "names": [
      "CN",
      "BeiJing",
      "BeiJing",
      "k8s",
      "System",
      "Kubernetes"
    ]
  },
  "serial_number": "174360492872423263473151971632292895707129022309",
  "sans": [
    "kubernetes",
    "kubernetes.default",
    "kubernetes.default.svc",
    "kubernetes.default.svc.cluster",
    "kubernetes.default.svc.cluster.local",
    "127.0.0.1",
    "10.64.3.7",
    "10.64.3.8",
    "10.66.3.86",
    "10.254.0.1"
  ],
  "not_before": "2017-04-05T05:36:00Z",
  "not_after": "2018-04-05T05:36:00Z",
  "sigalg": "SHA256WithRSA",
...
```

参考資料

+ [Generate self-signed certificates](https://coreos.com/os/docs/latest/generate-self-signed-certificates.html)
+ [Setting up a Certificate Authority and Creating TLS Certificates](https://github.com/kelseyhightower/kubernetes-the-hard-way/blob/master/docs/02-certificate-authority.md)
+ [Client Certificates V/s Server Certificates](https://blogs.msdn.microsoft.com/kaushal/2012/02/17/client-certificates-vs-server-certificates/)
