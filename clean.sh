#!/bin/bash
DOMAINS=('infra1' 'storage1' 'log1' 'mon1' 'compute1' 'compute2' 'jumpstart' 'k8s-m' 'k8s-w0' 'k8s-w1' 'k8s-w2' 'k8s-w3')
MYDIR=$(dirname $(readlink -f "$0"))
POOL=${MYDIR}
for domain in ${DOMAINS[@]} ; do
    virsh shutdown $domain
    sleep 5
    virsh undefine $domain
    rm -rf ${domain}.xml
    rm -rf "${POOL}/${domain}.qcow2"
    rm -rf "seed-${domain}"
    rm -rf "${POOL}/seed-${domain}.iso"
done

rm -rf "${POOL}/storage.qcow2"

sudo ifconfig  bus.10 down
sudo vconfig rem bus.10
virsh net-destroy bus
virsh net-undefine bus
rm -rf bus.xml
