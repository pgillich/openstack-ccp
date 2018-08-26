#!/bin/bash

#MYDIR=$(dirname $(readlink -f "$0"))
MYDIR=/opt/openstack-ccp

SSH_OPTIONS=(-o StrictHostKeyChecking=no -o GlobalKnownHostsFile=/dev/null -o UserKnownHostsFile=/dev/null -o LogLevel=error)
PUBKEY=$(<${HOME}/.ssh/id_rsa.pub)
DOMAINS=('osh-06' 'osh-07' 'osh-08' 'osh-09' 'osh-12' 'osh-13')
ULIMIT=4096 # 4096 should be ok...
DELAY=10
JUMPSTART_USER=ubuntu
JUMPSTART_HOST='osh-06'
declare -A IP4DOMAINS=( ['osh-06']='172.20.0.6' ['osh-07']='172.20.0.7' ['osh-08']='172.20.0.8' ['osh-09']='172.20.0.9' ['osh-12']='172.20.0.12' ['osh-13']='172.20.0.13' )

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

    sshpass -p ubuntu ssh ${SSH_OPTIONS[@]} ubuntu@${addr} <<- EOC
	sudo su -
	cat >>/etc/security/limits.conf <<EOF
	*	soft	nofile	${ULIMIT}
	*	hard	nofile	${ULIMIT}
	root	soft	nofile	${ULIMIT}
	root	hard	nofile	${ULIMIT}
	EOF

	sudo cat >>/etc/pam.d/common-session <<EOF
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

function provision () {
    local domain=$1
    local addr=$(ip4domain $domain 'bus')
    local remote_user=ubuntu
    local -a PROVISION_STEPS=("sudo apt-get -y install --no-install-recommends"`
								`" ntp"`
								`" ntpdate"`
								`" curl"`
								`" git"`
								`" 2>&1 >> apt.log"
                              "mkdir -p /etc/systemd/system/docker.service.d"
							  "echo \"[Service]
Environment='HTTP_PROXY=\${HTTP_PROXY}' 'HTTPS_PROXY=\${HTTPS_PROXY}' 'NO_PROXY=\${NO_PROXY}'
\" |  sudo tee /etc/systemd/system/docker.service.d/http-proxy.conf >/dev/null")

    if [[ "$domain" == "JUMPSTART_HOST" ]]; then
        #scp ${SSH_OPTIONS[@]} prov_master.sh ubuntu@${addr}:prov_master.sh
        # remote $domain "bash prov_master.sh"

        remote $domain "source "`
							`"<(curl -s https://raw.githubusercontent.com/kubernetes/helm/master/scripts/get)"`
							`" --version v2.8.2"

    else
        do_ulimit $domain
        do_reboot $domain
        for step in "${PROVISION_STEPS[@]}" ; do remote $domain "$step" ; done
        ssh ${SSH_OPTIONS[@]} ubuntu@${addr} <<- EOC
		sudo su -
		echo "net.ipv4.ip_forward = 1" >>/etc/sysctl.conf
		EOC
        do_reboot $domain
    fi
    
    echo -e "\n### Domain $1 ($addr) is provisioned\n"
}

