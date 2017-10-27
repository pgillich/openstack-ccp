#!/bin/bash
DOMAINS=('infra1' 'storage1' 'log1' 'compute1' 'compute2' 'jumpstart')
for domain in ${DOMAINS[@]} ; do
    virsh shutdown $domain
    sleep 5
    virsh undefine $domain
done

