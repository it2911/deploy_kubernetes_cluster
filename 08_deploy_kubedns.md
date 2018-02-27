<!-- toc -->

tags: kubedns

# kubedns pluginデプロイ

デプロイ用ファイルの所属フォルダ：`kubernetes/cluster/addons/dns`

デプロイ用ファイル：

``` bash
$ ls *.yaml *.base
kubedns-cm.yaml  kubedns-sa.yaml  kubedns-controller.yaml.base  kubedns-svc.yaml.base
```

すでに作成 yaml ファイルは：[dns](./manifests/kubedns)を参考してください

## システム定義した RoleBinding

予め定義した RoleBinding `system:kube-dns` は kube-system の `kube-dns` ServiceAccount と `system:kube-dns` Role と紐づけて、当該 Role は kube-apiserver DNS の関連 API へアクセス権限を振り分けた

``` bash
$ kubectl get clusterrolebindings system:kube-dns -o yaml
apiVersion: rbac.authorization.k8s.io/v1beta1
kind: ClusterRoleBinding
metadata:
  annotations:
    rbac.authorization.kubernetes.io/autoupdate: "true"
  creationTimestamp: 2017-04-06T17:40:47Z
  labels:
    kubernetes.io/bootstrapping: rbac-defaults
  name: system:kube-dns
  resourceVersion: "56"
  selfLink: /apis/rbac.authorization.k8s.io/v1beta1/clusterrolebindingssystem%3Akube-dns
  uid: 2b55cdbe-1af0-11e7-af35-8cdcd4b3be48
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: system:kube-dns
subjects:
- kind: ServiceAccount
  name: kube-dns
  namespace: kube-system
```

`kubedns-controller.yaml` で Pods を定義する時、`kubedns-sa.yaml` ファイルで定義した `kube-dns` ServiceAccount を利用して、ですから kube-apiserver DNS の関連 API へアクセス権限を振り分けた

## kube-dns ServiceAccount の修正

修正しない

## 配置 `kube-dns` の設定

``` bash
$ diff kubedns-svc.yaml.base kubedns-svc.yaml
30c30
<   clusterIP: __PILLAR__DNS__SERVER__
---
>   clusterIP: 10.254.0.2
```

+ こちらの spec.clusterIP を[クラスター変数]./manifests/environment.sh)の `CLUSTER_DNS_SVC_IP` 値を設定して、この IP アドレスは kubelet の `—cluster-dns` パラメター値が一致してください

## `kube-dns` Deployment の修正

``` bash
$ diff kubedns-controller.yaml.base kubedns-controller.yaml
88c88
<         - --domain=__PILLAR__DNS__DOMAIN__.
---
>         - --domain=cluster.local.
92c92
<         __PILLAR__FEDERATIONS__DOMAIN__MAP__
---
>         #__PILLAR__FEDERATIONS__DOMAIN__MAP__
129c129
<         - --server=/__PILLAR__DNS__DOMAIN__/127.0.0.1#10053
---
>         - --server=/cluster.local./127.0.0.1#10053
148c148
<         image: gcr.io/google_containers/k8s-dns-sidecar-amd64:1.14.1
---
>         image: xuejipeng/k8s-dns-sidecar-amd64:v1.14.1
161,162c161,162
<         - --probe=kubedns,127.0.0.1:10053,kubernetes.default.svc.__PILLAR__DNS__DOMAIN__,5,A
<         - --probe=dnsmasq,127.0.0.1:53,kubernetes.default.svc.__PILLAR__DNS__DOMAIN__,5,A
---
>         - --probe=kubedns,127.0.0.1:10053,kubernetes.default.svc.cluster.local.,5,A
>         - --probe=dnsmasq,127.0.0.1:53,kubernetes.default.svc.cluster.local.,5,A
```

+ `--domain` は [クラスター変数ドキュメント](01-environment.md) の `CLUSTER_DNS_DOMAIN` 値；
+ システムですでにある RoleBinding の `kube-dns` ServiceAccount，当該のアカウントが kube-apiserver DNS に関する API へアクセス権限を振り分けた。

## kubedns-sa.yaml
kubednsのservice account設定ファイルでnamespaceの設定を漏れたので、追加する
``` bash
$ diff kubedns-sa.yaml.old kubedns-sa.yaml
4a5
>   namespace: kube-system
```

## Yamlファイルのデプロイ

``` bash
$ pwd
/root/kubernetes-git/cluster/addons/dns
$ ls *.yaml
kubedns-cm.yaml  kubedns-controller.yaml  kubedns-sa.yaml  kubedns-svc.yaml
$ kubectl create -f .
$
```

## kubedns 機能が再チェック

検証用Deploymentをデプロイする

``` bash
$ cat  my-nginx.yaml
apiVersion: extensions/v1beta1
kind: Deployment
metadata:
  name: my-nginx
spec:
  replicas: 2
  template:
    metadata:
      labels:
        run: my-nginx
    spec:
      containers:
      - name: my-nginx
        image: nginx:1.7.9
        ports:
        - containerPort: 80
$ kubectl create -f my-nginx.yaml
$
```

Deploymentのserviceも作成する、`my-nginx` のserviceを含めて確認する

``` bash
$ kubectl expose deploy my-nginx
$ kubectl get services --all-namespaces |grep my-nginx
default       my-nginx               10.254.86.48     <none>        80/TCP          1d
```

別の Pod を立ち上げてみて、`/etc/resolv.conf` で `kubelet` 設定した `--cluster-dns` と `--cluster-domain` を含めている。`my-nginx` サービスを上記の Cluster IP `10.254.86.48` に解析できるかどうかを検証する

``` bash
$ cat pod-nginx.yaml
apiVersion: v1
kind: Pod
metadata:
  name: nginx
spec:
  containers:
  - name: nginx
    image: nginx:1.7.9
    ports:
    - containerPort: 80
$ kubectl create -f pod-nginx.yaml
$ kubectl exec  nginx -i -t -- /bin/bash
root@nginx:/# cat /etc/resolv.conf
nameserver 10.254.0.2
search default.svc.cluster.local svc.cluster.local cluster.local tjwq01.ksyun.com
options ndots:5

root@nginx:/# ping my-nginx
PING my-nginx.default.svc.cluster.local (10.254.86.48): 48 data bytes
^C--- my-nginx.default.svc.cluster.local ping statistics ---
2 packets transmitted, 0 packets received, 100% packet loss

root@nginx:/# ping kubernetes
PING kubernetes.default.svc.cluster.local (10.254.0.1): 48 data bytes
^C--- kubernetes.default.svc.cluster.local ping statistics ---
1 packets transmitted, 0 packets received, 100% packet loss

root@nginx:/# ping kube-dns.kube-system.svc.cluster.local
PING kube-dns.kube-system.svc.cluster.local (10.254.0.2): 48 data bytes
^C--- kube-dns.kube-system.svc.cluster.local ping statistics ---
1 packets transmitted, 0 packets received, 100% packet loss
```