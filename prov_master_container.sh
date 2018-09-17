#!/bin/bash
#JUMPSTART_USER=ubuntu
JUMPSTART_USER=peter
REPOS=( 'openstack-helm' 'openstack-helm-infra' )
function net_default_iface {
  sudo ip -4 route list 0/0 | awk '{ print $5; exit }'
}
#NET_DEFAULT_INTERFACE=$(net_default_iface)
NET_DEFAULT_INTERFACE=ens4
# ssh-keygen -q -f /home/ubuntu/.ssh/id_rsa -t rsa -N ''
sudo mkdir -p /etc/openstack-helm
sudo cp ~/.ssh/id_rsa /etc/openstack-helm/deploy-key.pem
sudo chown $JUMPSTART_USER /etc/openstack-helm/deploy-key.pem
sudo chown -R $JUMPSTART_USER: /opt
for repo in "${REPOS[@]}" ; do
    git clone "https://git.openstack.org/openstack/${repo}.git" "/opt/${repo}"
done
cat > /opt/openstack-helm-infra/tools/gate/devel/multinode-inventory.yaml <<EOF
all:
  children:
    primary:
      hosts:
        k8s-m:
          ansible_port: 22
          ansible_host: 172.16.1.1
          ansible_user: ubuntu
          ansible_ssh_private_key_file: /etc/openstack-helm/deploy-key.pem
          ansible_ssh_extra_args: -o StrictHostKeyChecking=no
    nodes:
      hosts:
        k8s-w1:
          ansible_port: 22
          ansible_host: 172.16.3.1
          ansible_user: ubuntu
          ansible_ssh_private_key_file: /etc/openstack-helm/deploy-key.pem
          ansible_ssh_extra_args: -o StrictHostKeyChecking=no
        k8s-w2:
          ansible_port: 22
          ansible_host: 172.16.4.1
          ansible_user: ubuntu
          ansible_ssh_private_key_file: /etc/openstack-helm/deploy-key.pem
          ansible_ssh_extra_args: -o StrictHostKeyChecking=no
        k8s-w3:
          ansible_port: 22
          ansible_host: 172.16.6.1
          ansible_user: ubuntu
          ansible_ssh_private_key_file: /etc/openstack-helm/deploy-key.pem
          ansible_ssh_extra_args: -o StrictHostKeyChecking=no
EOF
cat > /opt/openstack-helm-infra/tools/gate/devel/multinode-vars.yaml <<EOF
kubernetes_network_default_device: $NET_DEFAULT_INTERFACE
EOF
cd /opt && patch -p1 <<EOF
diff -ruN a/openstack-helm-infra/tools/images/kubeadm-aio/assets/opt/playbooks/vars.yaml b/openstack-helm-infra/tools/images/kubeadm-aio/assets/opt/playbooks/vars.yaml
--- a/openstack-helm-infra/tools/images/kubeadm-aio/assets/opt/playbooks/vars.yaml	2018-05-23 17:48:52.440252944 +0200
+++ b/openstack-helm-infra/tools/images/kubeadm-aio/assets/opt/playbooks/vars.yaml	2018-05-23 17:53:40.987339368 +0200
@@ -20,6 +20,7 @@
       gid: null
       home: null
     external_dns_nameservers:
+      - 172.16.0.1
       - 8.8.8.8
       - 8.8.4.4
     cluster:
EOF
