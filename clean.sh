#!/bin/bash
DOMAINS=('infra1' 'storage1' 'log1' 'compute1' 'compute2' 'jumpstart')
MYDIR=$(dirname $(readlink -f "$0"))
for domain in ${DOMAINS[@]} ; do
    virsh shutdown $domain
    sleep 5
    virsh undefine $domain
    rm -rf ${domain}.xml
    rm -rf ${domain}.qcow2
    rm -rf "seed-${domain}"
    rm -rf "seed-${domain}.iso"
done

rm -rf storage.qcow2

sudo ifconfig  bus.10 down
sudo vconfig rem bus.10
virsh net-destroy bus
virsh net-undefine bus
rm -rf bus.xml
