#!/bin/bash
NET_DEFAULT_INTERFACE=eno1.2502

cat > /opt/openstack-helm-infra/tools/gate/devel/multinode-inventory.yaml <<EOF
all:
  children:
    primary:
      hosts:
        osh-06:
          ansible_port: 22
          ansible_host: 172.20.1.6
          ansible_user: ubuntu
          ansible_ssh_private_key_file: /etc/openstack-helm/deploy-key.pem
          ansible_ssh_extra_args: -o StrictHostKeyChecking=no
    nodes:
      hosts:
        osh-07:
          ansible_port: 22
          ansible_host: 172.20.1.7
          ansible_user: ubuntu
          ansible_ssh_private_key_file: /etc/openstack-helm/deploy-key.pem
          ansible_ssh_extra_args: -o StrictHostKeyChecking=no
        osh-08:
          ansible_port: 22
          ansible_host: 172.20.1.8
          ansible_user: ubuntu
          ansible_ssh_private_key_file: /etc/openstack-helm/deploy-key.pem
          ansible_ssh_extra_args: -o StrictHostKeyChecking=no
        osh-09:
          ansible_port: 22
          ansible_host: 172.20.1.9
          ansible_user: ubuntu
          ansible_ssh_private_key_file: /etc/openstack-helm/deploy-key.pem
          ansible_ssh_extra_args: -o StrictHostKeyChecking=no
        osh-12:
          ansible_port: 22
          ansible_host: 172.20.1.12
          ansible_user: ubuntu
          ansible_ssh_private_key_file: /etc/openstack-helm/deploy-key.pem
          ansible_ssh_extra_args: -o StrictHostKeyChecking=no
        osh-13:
          ansible_port: 22
          ansible_host: 172.20.1.13
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
+      - 159.107.194.50
+      - 159.107.94.47
       - 8.8.8.8
       - 8.8.4.4
     cluster:
EOF
