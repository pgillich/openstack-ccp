#!/bin/bash -x

if [[ "$0" == "-bash" ]]; then
	MYDIR=/opt/openstack-ccp
else
	MYDIR=$(dirname $(readlink -f "$0"))
fi

SSH_OPTIONS=(-o StrictHostKeyChecking=no -o GlobalKnownHostsFile=/dev/null -o UserKnownHostsFile=/dev/null -o LogLevel=error)
PUBKEY=$(<${HOME}/.ssh/id_rsa.pub)
DOMAINS=('osh-07' 'osh-08' 'osh-09' 'osh-12' 'osh-13' 'osh-06')
#DOMAINS=('osh-06')
ULIMIT=4096 # 4096 should be ok...
DELAY=10
JUMPSTART_USER=ubuntu
JUMPSTART_HOST='osh-06'
declare -A IP4DOMAINS=( ['osh-06']='172.20.0.6' ['osh-07']='172.20.0.7' ['osh-08']='172.20.0.8' ['osh-09']='172.20.0.9' ['osh-12']='172.20.0.12' ['osh-13']='172.20.0.13' )
REPOS=( 'openstack-helm' 'openstack-helm-infra' )

function ip4domain () {
    if [ ! -z "${IP4DOMAINS[${1}]}" ]; then
        echo "${IP4DOMAINS[${1}]}"
    else
        echo "IP addr to ${1} is not declared" >&2
        exit
    fi
}

function pingssh () {
    local ipaddr=$(ip4domain $1 'bus')
    (echo >/dev/tcp/${ipaddr}/22) &>/dev/null && return 0 || return 1
}

function wait4ssh () {
    until pingssh $1; do
        echo "### Waiting ${DELAY} seconds more for ssh..."
        sleep $DELAY
    done
}

function do_reboot () {
    local remote_user=ubuntu
    local ipaddr=$(ip4domain $domain 'bus')
    sleep $DELAY

	echo "### Reboot ${ipaddr}"
	sshpass -p ubuntu ssh ${SSH_OPTIONS[@]} ${remote_user}@${ipaddr} <<- EOC
	sudo su -
	reboot
EOC

    sleep $DELAY
    wait4ssh $1
}

function remote() {
    local domain=$1
    local ipaddr=$(ip4domain $domain 'bus')
    local step=$2
    local remote_user=ubuntu

    echo "### $1: Doing ${step} on ${ipaddr}"
    until ssh ${SSH_OPTIONS[@]} ${remote_user}@${ipaddr} ${step}; do
        echo "### ssh to $ipaddr failed, retrying in $DELAY seconds..."
        sleep $DELAY
    done
}

function do_ulimit() {
    local addr=$(ip4domain $1 'bus')

	echo "### do_ulimit $1"
    sshpass -p ubuntu ssh ${SSH_OPTIONS[@]} ubuntu@${addr} <<- EOC
	sudo su -
	cat >>/etc/security/limits.conf <<EOF
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

	EOC
}

function provision_master () {
    local domain="$JUMPSTART_HOST"
    local remote_user=ubuntu

    scp ${SSH_OPTIONS[@]} prov_master_container.sh ${remote_user}@${addr}:prov_master_container.sh
    remote $domain "bash prov_master_container.sh"

    remote $domain "source "`
                            `"<(curl -s https://raw.githubusercontent.com/kubernetes/helm/master/scripts/get)"`
                            `" --version v2.8.2"

}


function provision () {
    local domain=$1
    local addr=$(ip4domain $domain 'bus')
    local remote_user=ubuntu
    local -a PROVISION_STEPS=("sudo apt-get -y install --no-install-recommends"`
								`" ntp"`
								`" ntpdate"`
								`" curl"`
                                `" git"`
 								`" rsync"`
								`" 2>&1 >> apt.log"
                              "sudo mkdir -p /etc/systemd/system/docker.service.d"
							  "echo \"[Service]
Environment='HTTP_PROXY=\${HTTP_PROXY}' 'HTTPS_PROXY=\${HTTPS_PROXY}' 'NO_PROXY=\${NO_PROXY}'
\" |  sudo tee /etc/systemd/system/docker.service.d/http-proxy.conf >/dev/null")

    if [[ "$domain" == "$JUMPSTART_HOST" ]]; then
        echo "$domain skipped"
    else
        do_ulimit $domain
        for step in "${PROVISION_STEPS[@]}" ; do remote $domain "$step" ; done
        ssh ${SSH_OPTIONS[@]} ubuntu@${addr} <<- EOC
		sudo su -
		echo "net.ipv4.ip_forward = 1" >>/etc/sysctl.conf
		EOC
        do_reboot $domain
    fi

    echo -e "\n### Domain $1 ($addr) is provisioned\n"
}

function populate_ssh() {
    local addr=$(ip4domain 'jumpstart' 'bus')
    local targetaddr
    local remote_user=ubuntu

 #   for target in ${DOMAINS[@]} ; do
    for target in ${DOMAINS[@]} ; do
            targetaddr=$(ip4domain $target 'bus')
            ssh-copy-id ${SSH_OPTIONS[@]} "${remote_user}@${targetaddr}"
            scp ${SSH_OPTIONS[@]} ${HOME}/.ssh/id_rsa "${remote_user}@${targetaddr}:id_rsa"
            echo "### Setting up deploy key on ${target} ($targetaddr)"
            ssh ${SSH_OPTIONS[@]} ${remote_user}@${targetaddr} <<- EOC
                sudo mkdir -p /etc/openstack-helm
                sudo mv /home/${remote_user}/id_rsa /etc/openstack-helm/deploy-key.pem
                sudo chown ${remote_user} /etc/openstack-helm/deploy-key.pem
EOC
        if [[ "$target" == "$JUMPSTART_HOST" ]]; then
            scp ${SSH_OPTIONS[@]} ${HOME}/.ssh/id_rsa* ${remote_user}@${targetaddr}:.ssh/
            remote $target "chmod 400 /home/${remote_user}/.ssh/id_rsa; chmod 444 /home/${remote_user}/.ssh/id_rsa.pub"
        fi
    done

}

function syncrepos() {
    local targetaddr
    local remote_user=ubuntu

    for target in ${DOMAINS[@]} ; do
        targetaddr=$(ip4domain $target 'bus')
        remote $target "sudo mkdir -p /opt; sudo chown -R ${remote_user}: /opt"
        for repo in "${REPOS[@]}" ; do
            rsync -azv -e "ssh  -o StrictHostKeyChecking=no -o GlobalKnownHostsFile=/dev/null -o UserKnownHostsFile=/dev/null -o LogLevel=error" --progress --delete /opt/${repo}/ $remote_user@${targetaddr}:/opt/${repo}
        done
    done
}

function run_playbooks() {
        export LC_ALL=C
        cd /opt/openstack-helm-infra
        make dev-deploy setup-host multinode
        make dev-deploy k8s multinode
}

function main() {
    #for domain in ${DOMAINS[@]} ; do
    #    provision $domain
    #done
    #populate_ssh
    #syncrepos
    # provision_master
    run_playbooks
    # do_deploy
}


main "$@"

