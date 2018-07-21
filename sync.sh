#!/bin/bash
REPOS=( 'openstack-helm' 'openstack-helm-infra' )
#TGTS=( 'k8s-m' 'k8s-w0' 'k8s-w1' 'k8s-w2' 'k8s-w3' )
TGTS=( 'k8s-m' 'k8s-w1' 'k8s-w2' 'k8s-w3' )
SSH_OPTIONS=(-o StrictHostKeyChecking=no -o GlobalKnownHostsFile=/dev/null -o UserKnownHostsFile=/dev/null -o LogLevel=error)
for tgt in "${TGTS[@]}" ; do
    ssh ${SSH_OPTIONS[@]} ubuntu@${tgt} "sudo chown -R ubuntu: /opt"
    for repo in "${REPOS[@]}" ; do
        rsync -azv -e "ssh  -o StrictHostKeyChecking=no -o GlobalKnownHostsFile=/dev/null -o UserKnownHostsFile=/dev/null -o LogLevel=error" --progress --delete /opt/${repo}/ ubuntu@${tgt}:/opt/${repo}
    done
done
