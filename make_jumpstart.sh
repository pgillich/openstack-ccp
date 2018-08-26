#!/bin/bash

docker build --build-arg "http_proxy=${http_proxy}" --build-arg "https_proxy=${https_proxy}" --build-arg "no_proxy=${no_proxy}" /home/ubuntu/git/openstack-ccp/ --hostname osh-jumpstart --tag osh-jumpstart
