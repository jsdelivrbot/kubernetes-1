#!/bin/sh
# Require Cluster information
# /etc/hosts host & ip reg

# 1) ssh-agent - LB / Master / Worker nodes
# ssh-keygen
# eval "$(ssh-agent -s)"
# ssh-add ~/.ssh/id_rsa
# scp ~/.ssh/id_rsa.pub {manage_ip}:~/.ssh/authorized_keys
# eval "$(ssh-agent -s)"
# scp ~/.ssh/id_rsa {master_ip}:~/.ssh/

# 2) git clone https://github.com/smileserv/kubernetes

INSTALL_PREFIX="/root/kubernetes/kubernetes-init"
INSTALL_SRC="$INSTALL_PREFIX/src"
INSTALL_CERT="$INSTALL_PREFIX/cert"
mkdir -p $INSTALL_SRC
mkdir -p $INSTALL_CERT

SUBNET="10.244.0.0/16"

LB_DOMAIN="lb11"
LB_IP="115.68.167.111"

export MASTER_IP1="192.168.0.101"
export MASTER_IP2="192.168.0.102"
export MASTER_IP3="192.168.0.103"

function config {
cat << EOF > /etc/systemd/system/kubelet.service.d/20-etcd-service-manager.conf
[Service]
ExecStart=
ExecStart=/usr/bin/kubelet --address=127.0.0.1 --pod-manifest-path=/etc/kubernetes/manifests --allow-privileged=true
Restart=always
EOF

cat << EOF >> ~/.bash_profile
export KUBECONFIG=/etc/kubernetes/admin.conf
#export PATH=$PATH:/usr/local/go/bin
EOF

source ~/.bash_profile
KUBECONFIG=/etc/kubernetes/admin.conf
sysctl net.bridge.bridge-nf-call-iptables=1

systemctl daemon-reload
systemctl restart kubelet

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

function mm {

mkdir -p $INSTALL_CERT/${MASTER_IP1}/ $INSTALL_CERT/${MASTER_IP2}/ $INSTALL_CERT/${MASTER_IP3}/

ETCDMASTER_IPS=(${MASTER_IP1} ${MASTER_IP2} ${MASTER_IP3})
NAMES=("Master1.k8s" "Master2.k8s" "Master3.k8s")

for i in "${!ETCDMASTER_IPS[@]}"; do
MASTER_IP=${ETCDMASTER_IPS[$i]}
NAME=${NAMES[$i]}
cat << EOF > $INSTALL_CERT/${MASTER_IP}/kubeadmcfg.yaml
apiVersion: "kubeadm.k8s.io/v1alpha3"
kind: ClusterConfiguration
etcd:
    local:
        serverCertSANs:
        - "${MASTER_IP}"
        peerCertSANs:
        - "${MASTER_IP}"
        extraArgs:
            initial-cluster: Master1.k8s=https://${ETCDMASTER_IPS[0]}:2380,Master2.k8s=https://${ETCDMASTER_IPS[1]}:2380,Master3.k8s=https://${ETCDMASTER_IPS[2]}:2380
            initial-cluster-state: new
            name: ${NAME}
            listen-peer-urls: https://${MASTER_IP}:2380
            listen-client-urls: https://${MASTER_IP}:2379
            advertise-client-urls: https://${MASTER_IP}:2379
            initial-advertise-peer-urls: https://${MASTER_IP}:2380
networking:
  podSubnet: $SUBNET
EOF
done

kubeadm alpha phase certs etcd-ca

kubeadm alpha phase certs etcd-server --config=$INSTALL_CERT/${MASTER_IP2}/kubeadmcfg.yaml
kubeadm alpha phase certs etcd-peer --config=$INSTALL_CERT/${MASTER_IP2}/kubeadmcfg.yaml
kubeadm alpha phase certs etcd-healthcheck-client --config=$INSTALL_CERT/${MASTER_IP2}/kubeadmcfg.yaml
kubeadm alpha phase certs apiserver-etcd-client --config=$INSTALL_CERT/${MASTER_IP2}/kubeadmcfg.yaml
cp -R /etc/kubernetes/pki $INSTALL_CERT/${MASTER_IP2}/
# cleanup non-reusable certificates
find /etc/kubernetes/pki -not -name ca.crt -not -name ca.key -type f -delete

kubeadm alpha phase certs etcd-server --config=$INSTALL_CERT/${MASTER_IP3}/kubeadmcfg.yaml
kubeadm alpha phase certs etcd-peer --config=$INSTALL_CERT/${MASTER_IP3}/kubeadmcfg.yaml
kubeadm alpha phase certs etcd-healthcheck-client --config=$INSTALL_CERT/${MASTER_IP3}/kubeadmcfg.yaml
kubeadm alpha phase certs apiserver-etcd-client --config=$INSTALL_CERT/${MASTER_IP3}/kubeadmcfg.yaml
cp -R /etc/kubernetes/pki $INSTALL_CERT/${MASTER_IP3}/
# cleanup non-reusable certificates
find /etc/kubernetes/pki -not -name ca.crt -not -name ca.key -type f -delete

kubeadm alpha phase certs etcd-server --config=$INSTALL_CERT/${MASTER_IP1}/kubeadmcfg.yaml
kubeadm alpha phase certs etcd-peer --config=$INSTALL_CERT/${MASTER_IP1}/kubeadmcfg.yaml
kubeadm alpha phase certs etcd-healthcheck-client --config=$INSTALL_CERT/${MASTER_IP1}/kubeadmcfg.yaml
kubeadm alpha phase certs apiserver-etcd-client --config=$INSTALL_CERT/${MASTER_IP1}/kubeadmcfg.yaml
# No need to move the certs because they are for MASTER_IP1

# clean up certs that should not be copied off this host
find $INSTALL_CERT/${MASTER_IP3} -name ca.key -type f -delete
find $INSTALL_CERT/${MASTER_IP2} -name ca.key -type f -delete

mv $INSTALL_CERT/${MASTER_IP1}/kubeadmcfg.yaml $INSTALL_CERT
kubeadm alpha phase etcd local --config=$INSTALL_CERT/kubeadmcfg.yaml

echo
echo "-------------------------------------------------------------------------------------"
echo "kubeadm init --config=$INSTALL_SRC/install_config.yaml"
echo "-------------------------------------------------------------------------------------"
echo "scp /etc/kubernetes/admin.conf root@controller_ip:/root/.kube/config"
echo "-------------------------------------------------------------------------------------"
echo "scp -r $INSTALL_CERT/${MASTER_IP2}/* root@$MASTER_IP2:/etc/kubernetes/"
echo "scp -r $INSTALL_CERT/${MASTER_IP3}/* root@$MASTER_IP3:/etc/kubernetes/"
echo "-------------------------------------------------------------------------------------"
echo "kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/bc79dd1505b0c8681ece4de4c0d86c5cd2643275/Documentation/kube-flannel.yml"
echo "-------------------------------------------------------------------------------------"

#kubectl apply -f https://git.io/weave-kube-1.6
#echo "kubectl apply -f $INSTALL_SRC/weave-kube-1.6"

}

function ms {

mv /etc/kubernetes/kubeadmcfg.yaml $INSTALL_CERT/
kubeadm alpha phase etcd local --config=$INSTALL_CERT/kubeadmcfg.yaml
echo
echo "-------------------------------------------------------------------------------------"
echo "kubeadm init --config=$INSTALL_CERT/kubeadmcfg.yaml"
echo "-------------------------------------------------------------------------------------"
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
echo "usage:$0 mw mm ms dashboard sonobuoy"
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

