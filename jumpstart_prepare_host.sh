#!/bin/bash

sudo apt-get install docker.io
sudo groupadd docker
sudo usermod -aG docker $USER

sudo apt-get install make

sudo mkdir -p /etc/systemd/system/docker.service.d
echo "[Service]
Environment='HTTP_PROXY=${HTTP_PROXY}' 'HTTPS_PROXY=${HTTPS_PROXY}' 'NO_PROXY=${NO_PROXY}'
" |  sudo tee /etc/systemd/system/docker.service.d/http-proxy.conf >/dev/null
sudo systemctl daemon-reload
sudo systemctl restart docker
# systemctl show --property=Environment docker

ULIMIT=4096

sudo bash -c "cat >>/etc/security/limits.conf <<EOF
*	soft	nofile	${ULIMIT}
*	hard	nofile	${ULIMIT}
root	soft	nofile	${ULIMIT}
root	hard	nofile	${ULIMIT}
EOF
cat >>/etc/pam.d/common-session <<EOF
session required pam_limits.so
EOF
cat >>/etc/pam.d/common-session-noninteractive <<EOF
session required pam_limits.so
EOF
cat >>/etc/systemd/system.conf <<EOF
DefaultLimitNOFILE=${ULIMIT}
EOF
cat >>/etc/systemd/user.conf <<EOF
DefaultLimitNOFILE=${ULIMIT}
EOF
"

sudo bash -c "cat >>/etc/sysctl.conf <<EOF
net.ipv4.ip_forward = 1
EOF
"
