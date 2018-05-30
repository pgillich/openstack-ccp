#!/bin/bash
WDIR="/opt/openstack-helm"
TDIR="tools/deployment/multinode"
DELAY=10
TASKS=(
    '010-setup-client'
    '020-ingress'
    '030-ceph'
    '040-ceph-ns-activate'
    '050-mariadb'
    '060-rabbitmq'
    '070-memcached'
    '080-keystone'
    '090-ceph-radosgateway'
    '100-glance'
    '110-cinder'
    '120-openvswitch'
    '130-libvirt'
    '140-compute-kit'
    '150-heat'
    '160-barbican')

cd ${WDIR}
for task in "${TASKS[@]}" ; do
    bash "${TDIR}/${task}.sh"
    sleep $DELAY
done
