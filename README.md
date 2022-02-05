# Consul Partition Demo

* Test Consul Version 1.11.2+ent

## Pre-requisites

* Install Terraform 1.0 or higher

* Ensure you have a AWS

* Install helm 3

* Install Kubectl

* Install aswcli v2 https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-install.html 

* Clone this repo


## Usage
### 1. Terraform

Initialise your environment
```hcl
terraform init 
```

Run a Terraform plan
```hcl
terraform plan 
```

Apply the Terraform environment
```hcl
terraform apply
```

If the run is successful you will see a single output of an IP address we will use in the next step.

### 2. EC2 Consul Server

SSH Connection example
```bash
# if '13.208.106.44' ip is Consul Server IP
ssh -i ./.ssh/sample_rsa ec2-user@13.208.106.44
```

Download Consul to `/usr/bin`
> <https://releases.hashicorp.com/consul/1.11.2+ent/>  
```bash
cd /tmp
wget https://releases.hashicorp.com/consul/1.11.2+ent/consul_1.11.2+ent_linux_amd64.zip
unzip consul_1.11.2+ent_linux_amd64.zip
mv ./consul /usr/bin/
```

Create Dir
- /root/consul : consul root
- /root/consul/config : consul config dir
- /root/consul/cert : consul tls dir
```bash
mkdir -p  mkdir /root/consul/{config,cert}
```

Create License
> 30 day trial : <https://www.hashicorp.com/products/consul/trial>  
`/root/consul/consul.hclic`

Create Config : `/root/consul/config/config.hcl`
```hcl
datacenter = "dc1"
data_dir = "/var/lib/consul"
client_addr = "0.0.0.0"
bind_addr = "{{ GetInterfaceIP \"eth0\" }}"
log_level = "DEBUG"
server = true
bootstrap_expect = 1
disable_update_check = true
encrypt = "QFn2KWHsvu94MEh+bAymbyt4CntDLlreidgE3uzmL1w="
leave_on_terminate = true
license_path = "/root/consul/consul.hclic"
ui_config {
  enabled = true
}
ports {
  server = 8300
  https = 8501
  grpc = 8502
}
connect {
  enabled = true
}
auto_encrypt {
  allow_tls = true
}
key_file = "/root/consul/cert/dc1-server-consul-0-key.pem"
cert_file = "/root/consul/cert/dc1-server-consul-0.pem"
ca_file = "/root/consul/cert/consul-agent-ca.pem"
```

Create TLS
```bash
cd /root/consul/cert
consul tls ca create -common-name server.dc1.consul
consul tls cert create -server -additional-ipaddress $(hostname -i)
consul tls cert create -client -additional-ipaddress $(hostname -i)
```

Copy client cert to Host from EC2 : e.g. `./app/cert`
- dc1-client-consul-0.pem
- dc1-client-consul-0-key.pem

Create Start Script : e.g. `/root/consul/start.sh`
```bash
$ cat <<EOF> /root/consul/start.sh
/usr/bin/consul agent -config-dir=/root/consul/config
EOF
$ chmod +x /root/consul/start.sh
```

Run Consul Server
```bash
$ cd /root/consul
$ ./start.sh
```

Create Admin Partition (Other window)
```bash
consul partition create -name eks1
consul partition create -name eks2
```

### 3. Consul Client for Partition on EKS

> Consul helm 0.36.0 Add support for services across Admin Partitions to communicate using mesh gateways. [GH-807] Documentation for the installation can be found [here](https://github.com/hashicorp/consul-k8s/blob/main/docs/admin-partitions-with-acls.md).

Move to `eks_setup` dir

Helm repo add & update
```bash
helm repo add hashicorp https://helm.releases.hashicorp.com && \
helm repo update
```

Kubernetes context to file
```bash
kubectl config view -o json | jq -r '.contexts[].name'  > ./KCONFIG.txt
```

Add License
```bash
kubectl --context $(grep gs-cluster-0 KCONFIG.txt) create secret generic license --from-file='key=./consul.hclic'
kubectl --context $(grep gs-cluster-1 KCONFIG.txt) create secret generic license --from-file='key=./consul.hclic'
```

Add Gossip key
```bash
kubectl --context $(grep gs-cluster-0 KCONFIG.txt) create secret generic consul-gossip-encryption-key --from-literal=key="QFn2KWHsvu94MEh+bAymbyt4CntDLlreidgE3uzmL1w="
kubectl --context $(grep gs-cluster-1 KCONFIG.txt) create secret generic consul-gossip-encryption-key --from-literal=key="QFn2KWHsvu94MEh+bAymbyt4CntDLlreidgE3uzmL1w="
```

Add TLS Cert
```bash
kubectl --context $(grep gs-cluster-0 KCONFIG.txt) create secret generic consul-ca-cert --from-file='tls.crt=./cert/consul-agent-ca.pem'
kubectl --context $(grep gs-cluster-0 KCONFIG.txt) create secret generic consul-ca-key --from-file='tls.key=./cert/consul-agent-ca-key.pem'
kubectl --context $(grep gs-cluster-1 KCONFIG.txt) create secret generic consul-ca-cert --from-file='tls.crt=./cert/consul-agent-ca.pem'
kubectl --context $(grep gs-cluster-1 KCONFIG.txt) create secret generic consul-ca-key --from-file='tls.key=./cert/consul-agent-ca-key.pem'

# If delete
kubectl --context $(grep gs-cluster-0 KCONFIG.txt) delete secret consul-ca-cert
kubectl --context $(grep gs-cluster-0 KCONFIG.txt) delete secret consul-ca-key
kubectl --context $(grep gs-cluster-1 KCONFIG.txt) delete secret consul-ca-cert
kubectl --context $(grep gs-cluster-1 KCONFIG.txt) delete secret consul-ca-key
```

Install Consul `gs-cluster-0`
```bash
kubectl config use-context $(grep gs-cluster-0 KCONFIG.txt)
helm install consul -f ./helm/values.yaml --set global.adminPartitions.name=eks1 hashicorp/consul --version v0.40.0 --debug
kubectl config use-context $(grep gs-cluster-1 KCONFIG.txt)
helm install consul -f ./helm/values.yaml --set global.adminPartitions.name=eks2 hashicorp/consul --version v0.40.0 --debug
```

### 4. Initial Deploy on EKS1
Move to `eks_setup` dir

if '13.208.106.44' ip is Consul Server IP

Deploy counting & dashboard
```bash
kubectl --context $(grep gs-cluster-0 KCONFIG.txt) apply -f ./eks1/counting.yaml
```
```
serviceaccount/counting created
service/counting created
deployment.apps/counting created
```

```bash
kubectl --context $(grep gs-cluster-0 KCONFIG.txt) apply -f ./eks1/dashiboard.yaml
```
```
serviceaccount/dashboard created
service/dashboard created
deployment.apps/dashboard created
```

Set Ingress upstream
```
curl -k --request PUT --data @consul_config/ingress_eks1.json https://13.208.106.44:8501/v1/config
```

Get Ingress External-ip
```bash
kubectl --context $(grep gs-cluster-0 KCONFIG.txt) get svc
```
```
NAME                        TYPE           CLUSTER-IP       EXTERNAL-IP                                                                    PORT(S)          AGE
...
consul-ingress-gateway      LoadBalancer   172.20.51.129    a61f250f7b7a7460f85bb5e4538f9e04-2130143272.ap-northeast-3.elb.amazonaws.com   5000:31387/TCP   123m
...
```

Call <http://a61f250f7b7a7460f85bb5e4538f9e04-2130143272.ap-northeast-3.elb.amazonaws.com:5000>

It has to Nomal
Find message `Connected`

### 5. Configuration Proxy

Set proxy_defaults
```bash
curl -k --request PUT --data @consul_config/proxy_defaults.json https://13.208.106.44:8501/v1/config
```

Set Gateways Per Service
```bash
curl -k --request PUT --data @consul_config/service_defaults_counting.json https://13.208.106.44:8501/v1/config
curl -k --request PUT --data @consul_config/service_defaults_dashboard.json https://13.208.106.44:8501/v1/config
```

### 6. Initial Deploy on EKS2

```bash
kubectl --context $(grep gs-cluster-1 KCONFIG.txt) apply -f ./eks2/counting_static.yaml
kubectl --context $(grep gs-cluster-1 KCONFIG.txt) apply -f ./eks2/dashiboard.yaml
```
```
serviceaccount/dashboard created
service/dashboard created
deployment.apps/dashboard created
```

Set Ingress upstream
```
curl -k --request PUT --data @consul_config/ingress_eks2.json https://13.208.106.44:8501/v1/config
```

Get Ingress External-ip
```bash
kubectl --context $(grep gs-cluster-1 KCONFIG.txt) get svc
```
```
NAME                        TYPE           CLUSTER-IP       EXTERNAL-IP                                                                    PORT(S)          AGE
...
consul-ingress-gateway      LoadBalancer   172.20.73.105    ad3fd4b8e4fa74cd0aa0967eb02c80a5-518943195.ap-northeast-3.elb.amazonaws.com    5000:31968/TCP   118m
...
```

Call <http://ad3fd4b8e4fa74cd0aa0967eb02c80a5-518943195.ap-northeast-3.elb.amazonaws.com:5000>

Find mockup date `999`

### 7. Cross request between Partitions

Set export service
```
curl -k --request PUT --data @consul_config/export_service.json https://13.208.106.44:8501/v1/config
```

Deploy dashboard : 
- default : `'consul.hashicorp.com/connect-service-upstreams': '<service-name>:<port>'`
- partition : `'consul.hashicorp.com/connect-service-upstreams': '<service-name>.<namespace>.<partition-name>:<port>'`

Fix `dashboard` upstream targeting eks2 : `eks2/dashboard.yaml`
```yaml
...
spec:
  replicas: 1
  selector:
    matchLabels:
      app: dashboard
  template:
    metadata:
      annotations:
        'consul.hashicorp.com/connect-inject': 'true'
        'consul.hashicorp.com/connect-service-upstreams': 'counting.deafult.eks1:9001'
...
```

### Caution

Uninstall Consul of EKS before doing `terraform destroy`.
Check if the LoadBalancer type service is deleted.

```bash
kubectl config use-context $(grep gs-cluster-0 KCONFIG.txt)
helm uninstall consul
kubectl config use-context $(grep gs-cluster-1 KCONFIG.txt)
helm uninstall consul
```