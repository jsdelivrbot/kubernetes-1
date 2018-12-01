#!/bin/sh
# Require: Cluster information

INSTALL_PREFIX="/root/kubernetes/kubernetes-init"
INSTALL_SRC="$INSTALL_PREFIX/src"
INSTALL_CERT="$INSTALL_PREFIX/cert"
mkdir -p $INSTALL_SRC
mkdir -p $INSTALL_CERT

SUBNET="10.244.0.0/16"

LB_DOMAIN="etcd-lb.iwinv.kr"
LB_IP="115.68.167.124"

MM_IP=`ifconfig | grep "eth1" -A1 | grep inet | awk '{print $2}'`
MASTER_IP1="115.68.167.121"
MASTER_IP2="115.68.167.122"
MASTER_IP3="115.68.167.123"

function config {
cat << EOF > /etc/hosts
127.0.0.1   localhost localhost.localdomain localhost4 localhost4.localdomain4
::1         localhost localhost.localdomain localhost6 localhost6.localdomain6

115.68.167.124 etcd-lb.iwinv.kr
115.68.167.100 console.k8s

115.68.167.121 Master1.k8s
115.68.167.122 Master2.k8s
115.68.167.123 Master3.k8s

192.168.0.3 Worker1.k8s
192.168.0.26 Worker2.k8s
192.168.0.6 Worker3.k8s
192.168.0.10 Worker4.k8s
192.168.0.5 Worker5.k8s
192.168.0.18 Worker6.k8s
EOF

cat << EOF > $INSTALL_SRC/etcd.service
[Unit]
Description=etcd
Documentation=https://github.com/coreos

[Service]
ExecStart=/usr/bin/etcd \
  --name $MM_IP \
  --cert-file=/etc/etcd/kubernetes.pem \
  --key-file=/etc/etcd/kubernetes-key.pem \
  --peer-cert-file=/etc/etcd/kubernetes.pem \
  --peer-key-file=/etc/etcd/kubernetes-key.pem \
  --trusted-ca-file=/etc/etcd/ca.pem \
  --peer-trusted-ca-file=/etc/etcd/ca.pem \
  --peer-client-cert-auth \
  --client-cert-auth \
  --initial-advertise-peer-urls https://$MM_IP:2380 \
  --listen-peer-urls https://$MM_IP:2380 \
  --listen-client-urls https://$MM_IP:2379,http://127.0.0.1:2379 \
  --advertise-client-urls https://$MM_IP:2379 \
  --initial-cluster-token etcd-cluster-0 \
  --initial-cluster $MASTER_IP1=https://$MASTER_IP1:2380,$MASTER_IP2=https://$MASTER_IP2:2380,$MASTER_IP3=https://$MASTER_IP3:2380
  --initial-cluster-state new \
  --data-dir=/var/lib/etcd
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

cat << EOF > $INSTALL_SRC/haproxy.cfg
# haproxy.cfg
#---------------------------------------------------------------------
# Example configuration for a possible web application.  See the
# full configuration options online.
#
#   http://haproxy.1wt.eu/download/1.4/doc/configuration.txt
#
#---------------------------------------------------------------------

#---------------------------------------------------------------------
# Global settings
#---------------------------------------------------------------------
global
    # to have these messages end up in /var/log/haproxy.log you will
    # need to:
    #
    # 1) configure syslog to accept network log events.  This is done
    #    by adding the '-r' option to the SYSLOGD_OPTIONS in
    #    /etc/sysconfig/syslog
    #
    # 2) configure local2 events to go to the /var/log/haproxy.log
    #   file. A line like the following can be added to
    #   /etc/sysconfig/syslog
    #
    #    local2.*                       /var/log/haproxy.log
    #
    log         127.0.0.1 local2

    chroot      /var/lib/haproxy
    pidfile     /var/run/haproxy.pid
    maxconn     4000
    user        haproxy
    group       haproxy
    daemon

    # turn on stats unix socket
    stats socket /var/lib/haproxy/stats

#---------------------------------------------------------------------
# common defaults that all the 'listen' and 'backend' sections will
# use if not designated in their block
#---------------------------------------------------------------------
defaults
    mode                    http
    log                     global
    option                  httplog
    option                  dontlognull
    option http-server-close
    option forwardfor       except 127.0.0.0/8
    option                  redispatch
    retries                 3
    timeout http-request    10s
    timeout queue           1m
    timeout connect         10s
    timeout client          1m
    timeout server          1m
    timeout http-keep-alive 10s
    timeout check           10s
    maxconn                 3000

#---------------------------------------------------------------------
# main frontend which proxys to the backends
#---------------------------------------------------------------------
#frontend  main *:5000
#    acl url_static       path_beg       -i /static /images /javascript /stylesheets
#    acl url_static       path_end       -i .jpg .gif .png .css .js
#
#    use_backend static          if url_static
#    default_backend             app

#---------------------------------------------------------------------
# static backend for serving up images, stylesheets and such
#---------------------------------------------------------------------
#backend static
#    balance     roundrobin
#    server      static 127.0.0.1:4331 check

#---------------------------------------------------------------------
# round robin balancing between the various backends
#---------------------------------------------------------------------
#backend app
#    balance     roundrobin
#    server  app1 127.0.0.1:5001 check
#    server  app2 127.0.0.1:5002 check
#    server  app3 127.0.0.1:5003 check
#    server  app4 127.0.0.1:5004 check

frontend kubernetes
bind $LB_DOMAIN:6443
option tcplog
mode tcp
default_backend kubernetes-master-nodes

backend kubernetes-master-nodes
mode tcp
balance roundrobin
option tcp-check
server master1.k8s $MASTER_IP1:6443 check fall 3 rise 2
server master2.k8s $MASTER_IP2:6443 check fall 3 rise 2
server master3.k8s $MASTER_IP3:6443 check fall 3 rise 2

#frontend haproxy_nodes
#    bind *:80
#    mode http
#    default_backend http_nodes
#
#backend http_nodes
#mode http
#balance roundrobin
#option forwardfor
#http-request set-header X-Forwarded-Port %[dst_port]
#http-request add-header X-Forwarded-Proto https if { ssl_fc }
#option httpchk HEAD / HTTP/1.1\r\nHost:localhost

#server master1 $MASTER_IP1:30000 check fall 10 rise 4
#server master2 $MASTER_IP2:30000 check fall 10 rise 4
#server master3 $MASTER_IP3:30000 check fall 10 rise 4
EOF

cat << EOF > $INSTALL_SRC/install_config.yaml
apiVersion: kubeadm.k8s.io/v1alpha3
kind: ClusterConfiguration
kubernetesVersion: stable
apiServerCertSANs:
- $LB_DOMAIN
controlPlaneEndpoint: "$LB_DOMAIN:6443"
etcd:
  external:
    endpoints:
    - https://$MASTER_IP1:2379
    - https://$MASTER_IP2:2379
    - https://$MASTER_IP3:2379
    caFile: /etc/etcd/ca.pem
    certFile: /etc/etcd/kubernetes.pem
    keyFile: /etc/etcd/kubernetes-key.pem
networking:
  podSubnet: $SUBNET
apiServerExtraArgs:
  apiserver-count: "3"
EOF
}

function mw {
yum install -y wget vim-enhanced net-tools yum-utils device-mapper-persistent-data lvm2
yum update -y

systemctl disable iptables
systemctl stop iptables

rpm -e docker-ce-cli docker-ce
yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
yum install docker-ce-18.06.1.ce-3.el7.x86_64 -y

systemctl daemon-reload
systemctl enable docker
systemctl restart docker

cat << EOF > /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-x86_64
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
exclude=kube*
EOF

setenforce 0
sed -i 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config

yum install -y kubelet kubeadm kubectl --disableexcludes=kubernetes

modprobe ip_vs
modprobe ip_vs_rr
modprobe ip_vs_wrr
modprobe ip_vs_sh
modprobe nf_conntrack_ipv4

systemctl enable kubelet && systemctl start kubelet

cat << EOF > /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
EOF

sysctl --system

swapoff -a

}


function lb {
hostname $LB_DOMAIN
echo "hostname=$LB_DOMAIN" >> /etc/sysconfig/network 
setenforce 0
sed -i 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config

systemctl disable iptables
systemctl stop iptables

yum install -y wget vim-enhanced haproxy
yum update -y

wget https://pkg.cfssl.org/R1.2/cfssl_linux-amd64 -O /usr/local/bin/cfssl
wget https://pkg.cfssl.org/R1.2/cfssljson_linux-amd64 -O /usr/local/bin/cfssljson
wget https://storage.googleapis.com/kubernetes-release/release/v1.12.2/bin/linux/amd64/kubectl -O /usr/local/bin/kubectl
chmod 700 /usr/local/bin/cfssl* && chmod 700 /usr/local/bin/kubectl
cat $INSTALL_SRC/haproxy.cfg > /etc/haproxy/haproxy.cfg

systemctl enable haproxy
systemctl restart haproxy

cat << EOF > $INSTALL_CERT/ca-config.json
{
  "signing": {
    "default": {
      "expiry": "8760h"
    },
    "profiles": {
      "kubernetes": {
        "usages": ["signing", "key encipherment", "server auth", "client auth"],
        "expiry": "8760h"
      }
    }
  }
}
EOF

cat << EOF > $INSTALL_CERT/ca-csr.json
{
  "CN": "Kubernetes",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
  {
    "C": "CHROME",
    "L": "IT",
    "O": "Kubernetes",
    "OU": "SEOUL",
    "ST": "SmileServ Co."
  }
 ]
}
EOF

cfssl gencert -initca $INSTALL_CERT/ca-csr.json | cfssljson -bare $INSTALL_CERT/ca

cat << EOF > $INSTALL_CERT/kubernetes-csr.json
{
  "CN": "kubernetes",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
  {
    "C": "CHROME",
    "L": "IT",
    "O": "Kubernetes",
    "OU": "SEOUL",
    "ST": "SmileServ Co."
  }
 ]
}
EOF

cd $INSTALL_CERT
cfssl gencert -ca=$INSTALL_CERT/ca.pem -ca-key=$INSTALL_CERT/ca-key.pem -config=$INSTALL_CERT/ca-config.json -hostname=$MASTER_IP1,$MASTER_IP2,$MASTER_IP3,$LB_DOMAIN,127.0.0.1,kubernetes.default -profile=kubernetes $INSTALL_CERT/kubernetes-csr.json | cfssljson -bare $INSTALL_CERT/kubernetes

echo
echo "----------------------------------------------------------------------------------------------------------------------------------------"
echo "scp $INSTALL_CERT/ca.pem $INSTALL_CERT/kubernetes.pem $INSTALL_CERT/kubernetes-key.pem root@$MASTER_IP1:~"
echo "scp $INSTALL_CERT/ca.pem $INSTALL_CERT/kubernetes.pem $INSTALL_CERT/kubernetes-key.pem root@$MASTER_IP2:~"
echo "scp $INSTALL_CERT/ca.pem $INSTALL_CERT/kubernetes.pem $INSTALL_CERT/kubernetes-key.pem root@$MASTER_IP3:~"
echo "----------------------------------------------------------------------------------------------------------------------------------------"

mkdir /root/.kube
}

function mm {
mkdir -p /etc/etcd /var/lib/etcd

mv ~/ca.pem ~/kubernetes.pem ~/kubernetes-key.pem /etc/etcd

#wget https://github.com/coreos/etcd/releases/download/v3.3.10/etcd-v3.3.10-linux-amd64.tar.gz -O $INSTALL_SRC/etcd-v3.3.10-linux-amd64.tar.gz
tar xvzf $INSTALL_SRC/etcd-v3.3.10-linux-amd64.tar.gz -C $INSTALL_SRC
mv $INSTALL_SRC/etcd-v3.3.10-linux-amd64/etcd* /usr/bin/
rm -f $INSTALL_SRC/etcd-v3.3.10-linux-amd64.tar.gz

cat $INSTALL_SRC/etcd.service > /etc/systemd/system/etcd.service
chmod 700 /etc/systemd/system/etcd.service

systemctl daemon-reload
systemctl enable etcd
systemctl restart etcd

cat >> ~/.bash_profile <<EOF
export KUBECONFIG=/etc/kubernetes/admin.conf
#export PATH=$PATH:/usr/local/go/bin
EOF

source ~/.bash_profile
KUBECONFIG=/etc/kubernetes/admin.conf
sysctl net.bridge.bridge-nf-call-iptables=1

systemctl restart kubelet

echo
echo "-------------------------------------------------------------------------------------"
echo "kubeadm init --config=$INSTALL_SRC/install_config.yaml"
echo
echo "scp -r /etc/kubernetes/pki root@$MASTER_IP2:/etc/kubernetes/pki"
echo "scp -r /etc/kubernetes/pki root@$MASTER_IP3:/etc/kubernetes/pki"
echo
echo "scp /etc/kubernetes/admin.conf root@$LB_DOMAIN:/root/.kube/config"
echo "scp /etc/kubernetes/admin.conf root@console.k8s:/root/.kube/config"
echo
echo "-------------------------------------------------------------------------------------"
echo kubectl apply -f \"https://cloud.weave.works/k8s/net?k8s-version=$(kubectl version | base64 | tr -d \'\\n\')\"
echo "kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/bc79dd1505b0c8681ece4de4c0d86c5cd2643275/Documentation/kube-flannel.yml"
echo "-------------------------------------------------------------------------------------"


#kubectl apply -f https://git.io/weave-kube-1.6
#echo "kubectl apply -f $INSTALL_SRC/weave-kube-1.6"

}

function ms {
rm -f /etc/kubernetes/pki/apiserver.*

mkdir -p /etc/etcd /var/lib/etcd

mv ~/ca.pem ~/kubernetes.pem ~/kubernetes-key.pem /etc/etcd

#wget https://github.com/coreos/etcd/releases/download/v3.3.10/etcd-v3.3.10-linux-amd64.tar.gz -O $INSTALL_SRC/etcd-v3.3.10-linux-amd64.tar.gz
tar xvzf $INSTALL_SRC/etcd-v3.3.10-linux-amd64.tar.gz -C $INSTALL_SRC
mv $INSTALL_SRC/etcd-v3.3.10-linux-amd64/etcd* /usr/bin/
rm -f $INSTALL_SRC/etcd-v3.3.10-linux-amd64.tar.gz

cat $INSTALL_SRC/etcd.service > /etc/systemd/system/etcd.service

systemctl daemon-reload
systemctl enable etcd
systemctl restart etcd

cat >> ~/.bash_profile <<EOF
export KUBECONFIG=/etc/kubernetes/admin.conf
#export PATH=$PATH:/usr/local/go/bin
EOF

systemctl restart kubelet
echo
echo "-----------------------------------------------------"
echo "kubeadm init --config=$INSTALL_SRC/install_config.yaml"
echo 'kubectl apply -f "https://cloud.weave.works/k8s/net?k8s-version=$(kubectl version | base64 | tr -d '\n')"'
echo "kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/bc79dd1505b0c8681ece4de4c0d86c5cd2643275/Documentation/kube-flannel.yml"
echo "-------------------------------------------------------------------------------------"


#kubectl apply -f https://git.io/weave-kube-1.6
#echo "kubectl apply -f $INSTALL_SRC/weave-kube-1.6"

}

function sonobuoy {
wget https://dl.google.com/go/go1.11.1.linux-amd64.tar.gz
tar -C /usr/local -xzf go1.11.1.linux-amd64.tar.gz
rm -f go1.11.1.linux-amd64.tar.gz
}


function dashboard {
kubectl create -f https://raw.githubusercontent.com/kubernetes/dashboard/master/src/deploy/recommended/kubernetes-dashboard.yaml
kubectl create -f $INSTALL_SRC/dashboard/dashboard-admin.yaml
}


function usage {
echo
echo "usage:$0 mw lb mm ms dashboard sonobuoy"
echo
exit
}

ARGC="$#"

if [ $ARGC -eq 0 ] || [ $ARGC -gt 1 ];then
usage
exit
fi

case "$1" in
  mw)
mw
exit
  ;;

  lb)
config
lb
exit
  ;;

  mm)
config
mm
exit
  ;;

  ms)
config
ms
exit
  ;;

  sonobuoy)
sonobuoy
exit
  ;;

esac

usage
exit

