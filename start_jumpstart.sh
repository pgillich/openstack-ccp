#!/bin/bash

# For developers:
# docker run -d --rm -p '2222:22' --name osh-jumpstart --hostname osh-jumpstart --env http_proxy=$http_proxy --env https_proxy=$https_proxy --env no_proxy=$no_proxy --env HTTP_PROXY=$http_proxy --env HTTPS_PROXY=$https_proxy --env NO_PROXY=$no_proxy --volume /home/ubuntu/git/openstack-ccp:/opt/openstack-ccp osh-jumpstart

docker run -d --rm -p '2222:22' --name osh-jumpstart osh-jumpstart
