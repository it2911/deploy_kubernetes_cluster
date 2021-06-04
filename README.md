# Kubernetesクラスター環境構築学習 

最初に様々な会社のVPSサービスを試したが、OSのセキュリティ設定やネットワークの問題でKubernetesのクラスターをうまく構築出来ませんでした。
諦める直前に、[さくらインターネット](https://www.sakura.ad.jp/)のVPSでKubernetesを無事に作成しました。**さくらインターネットの皆様、ありがとうございます。**

## Kubernetesの構築手順書の説明

ドキュメントがKubernetesの各コンポーネントの間の通信、動作など情報を詳しく記載している。

1. [コンポーネントバージョンとクラスター環境](./01_ready_to_deploy_a_kubernetes_cluster.md)  
2. [CA 証明書とキーファイルの作成](./02_create_ca_certificate_and_key.md)  
3. [高可用性の etcd クラスター環境の構築](./03_deploy_high_available_etcd_cluster.md)  
4. [kubectlのデプロイ](./04_deploy_kubectl_command_tools.md)  
5. [Flannel ネットワークのデプロイ](./05_deploy_flannel_network.md)  
6. [Kubenetes Master Nodeのデプロイ](./06_deploy_kubernetes_master.md)
7. [Kubenetes Slave Nodeのデプロイ](./07_deploy_kubernetes_worker.md)  
8. [DNS プラグインのデプロイ](./08_deploy_kubedns.md)  
9. [Dashboard プラグインのデプロイ](./09_deploy_dashborad.md)  
10. [Heapster プラグインのデプロイ](./10_deploy_heapster.md)
11. [EFK プラグインのデプロイ](./11_deploy_efk.md)
12. Docker Registry プラグインのデプロイ  
13. Harbor プラグインのデプロイ  
14. クラスタークリア  

![dashboard](./images/dashboard.png)

![heapster](./images/heapster.png)

![kibana](./images/kibana.png)

![harbor](./images/harbor.png)

[it2911研究Blog](http://www.it2911.com)
