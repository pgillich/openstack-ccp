#!/bin/bash

sudo mkdir -p /etc/systemd/system/docker.service.d
echo "[Service]
Environment='HTTP_PROXY=${HTTP_PROXY}' 'HTTPS_PROXY=${HTTPS_PROXY}' 'NO_PROXY=${NO_PROXY}'
" |  sudo tee /etc/systemd/system/docker.service.d/http-proxy.conf >/dev/null
sudo systemctl daemon-reload
sudo systemctl restart docker
# systemctl show --property=Environment docker

docker build --build-arg "http_proxy=${http_proxy}" --build-arg "https_proxy=${https_proxy}" --build-arg "no_proxy=${no_proxy}" /home/ubuntu/git/openstack-ccp/ --tag osh-jumpstart
