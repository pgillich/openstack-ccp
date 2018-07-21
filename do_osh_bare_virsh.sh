#!/bin/bash
###
# do_ulimit ?
# net.ipv4.ip_forward ?
#
# arp -e --> arp -en
# mem swap tiltás (k8s)
###

if [[ "$1" = "debug" ]]; then
    set -x
fi

#MYDIR=$(dirname $(readlink -f "$0"))
MYDIR=/home/peter/work/k8s/openstack/openstack-ccp/my
POOL=$MYDIR
ARCHURI="https://cloud-images.ubuntu.com/xenial/current"
ARCHIMAGE="xenial-server-cloudimg-amd64-disk1.img"
IMAGE="xenserv.img"
SSH_OPTIONS=(-o StrictHostKeyChecking=no -o GlobalKnownHostsFile=/dev/null -o UserKnownHostsFile=/dev/null -o LogLevel=error)
PUBKEY=$(<${HOME}/.ssh/id_rsa.pub)
DOMAINS=('k8s-m' 'k8s-w1' 'k8s-w2' 'k8s-w3')
declare -A IMGSIZ=( ['k8s-m']='32G' ['k8s-w0']='32G' ['k8s-w1']='32G' ['k8s-w2']='32G' ['k8s-w3']='32G' )
declare -A MEMSIZ=( ['k8s-m']='3145728' ['k8s-w0']='3145728' ['k8s-w1']='3145728' ['k8s-w2']='3145728' ['k8s-w3']='3145728' )
declare -A VCPUS=( ['k8s-m']='2' ['k8s-w0']='2' ['k8s-w1']='2' ['k8s-w2']='2' ['k8s-w3']='2' )
ULIMIT=4096 # 4096 should be ok...
DELAY=10
#JUMPSTART_USER=ubuntu
JUMPSTART_USER=peter
declare -A IP4DOMAINS=( ['jumpstart']='172.16.0.1' ['k8s-m']='172.16.1.1' ['k8s-w0']='172.16.2.1' ['k8s-w1']='172.16.3.1' ['k8s-w2']='172.16.4.1' ['k8s-w3']='172.16.6.1' )

function mkseed () {
    local seed="seed-${1}"
    cat <<- EOC > ${seed}
	#cloud-config
	hostname: $1
	password: ubuntu
	chpasswd: { expire: False }
	ssh_pwauth: True
	ssh_authorized_keys:
	    - ${PUBKEY}
	EOC
    cloud-localds "${POOL}/${seed}.iso" ${seed}
    echo -e "\n### $1: cloudinit: ${seed}.iso\n"
}

function mkimage () {
    wget -nc -q -O "${POOL}/${IMAGE}" "${ARCHURI}/${ARCHIMAGE}"
    qemu-img convert -O qcow2 "${POOL}/${IMAGE}"  "${POOL}/${1}.qcow2"
    qemu-img resize "${POOL}/${1}.qcow2" ${IMGSIZ[${1}]}
    qemu-img info "${POOL}/${1}.qcow2"
}

function ip4domain () {
    if [ ! -z "${IP4DOMAINS[${1}]}" ]; then
        echo "${IP4DOMAINS[${1}]}"
    else
        local ETHERP="([0-9a-f]{2}:){5}([0-9a-f]{2})"
        local IPP="^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}"
        local net=${2:-'default'}
        local mac=$(virsh domiflist $1 | grep $net | grep -o -E $ETHERP)

        local ipaddr=$(arp -en | grep $mac | grep -o -P $IPP)
        IP4DOMAINS[${1}]=$ipaddr
        echo $ipaddr
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
    sleep $DELAY
    virsh reboot $1 --mode=agent
    sleep $DELAY
    wait4ssh $1
}

function mknet () {
    cat <<- EOC > "bus.xml"
	<network>
	  <name>bus</name>
	  <forward mode='nat'>
	    <nat>
	      <port start='1024' end='65535'/>
	    </nat>
	  </forward>
	  <bridge name='bus' stp='on' delay='0'/>
	  <ip address='172.16.0.1' netmask='255.255.0.0'>
	    <dhcp>
	      <range start='172.16.0.2' end='172.16.255.254'/>
	      <host name='k8s-m' ip="${IP4DOMAINS[k8s-m]}"/>
	      <host name='k8s-w0' ip="${IP4DOMAINS[k8s-w0]}"/>
	      <host name='k8s-w1' ip="${IP4DOMAINS[k8s-w1]}"/>
	      <host name='k8s-w2' ip="${IP4DOMAINS[k8s-w2]}"/>
	      <host name='k8s-w3' ip="${IP4DOMAINS[k8s-w3]}"/>
	    </dhcp>
	  </ip>
	</network>
	EOC
    virsh net-define bus.xml
    virsh net-start bus
}

function mkdomain () {
    cat <<- EOC > "${1}.xml"
	<domain type="kvm">
	    <name>$1</name>
	    <memory>${MEMSIZ[${1}]}</memory>
	    <os>
	        <type>hvm</type>
	        <boot dev="hd"/>
	    </os>
	    <features>
	        <acpi/>
	    </features>
	    <vcpu>${VCPUS[${1}]}</vcpu>
	    <devices>
	        <disk type="file" device="disk">
	            <driver type="qcow2" cache="none"/>
	            <source file="${POOL}/${1}.qcow2"/>
	            <target dev="vda" bus="virtio"/>
	        </disk>
	        <disk type="file" device="cdrom">
	            <source file="${POOL}/seed-${1}.iso"/>
	            <target dev="vdb" bus="virtio"/>
	            <readonly/>
	        </disk>
	            <interface type="network">
	            <source network="bus"/>
	            <model type="e1000"/>
	            <address type='pci' domain='0x0000' bus='0x00' slot='0x04' function='0x0'/>
	        </interface>
	        <console type='pty'>
	            <target type='serial' port='0'/>
	        </console>
	        <input type='mouse' bus='ps2'/>
	        <input type='keyboard' bus='ps2'/>
	        <graphics type='vnc' port='-1' autoport='yes' keymap='en-us'/>
	        <sound model='ich6'>
	        </sound>
	        <video>
	            <model type='vmvga' vram='9216' heads='1'/>
	            <address type='pci' domain='0x0000' bus='0x00' slot='0x02' function='0x0'/>
	        </video>
	        <memballoon model='virtio'>
	            <address type='pci' domain='0x0000' bus='0x00' slot='0x0a' function='0x0'/>
	        </memballoon>
	        <channel type='unix'>
	            <source mode='bind' path="/var/lib/libvirt/qemu/channel/target/${1}.org.qemu.guest_agent.0"/>
	            <target type='virtio' name='org.qemu.guest_agent.0' state='connected'/>
	            <alias name='channel0'/>
	            <address type='virtio-serial' controller='0' bus='0' port='1'/>
	        </channel>
	    </devices>
	</domain>
	EOC
    virsh define ${1}.xml
    virsh start ${1}
    wait4ssh ${1}
    echo -e "\n### Domain $1 is up\n"
}

function remote() {
    local domain=$1
    local ipaddr=$(ip4domain $domain 'bus')
    local step=$2

    case $domain in
        jumpstart)
            local remote_user=$JUMPSTART_USER
            ;;
         *)
            local remote_user=ubuntu
            ;;
    esac

    echo "### $1: Doing ${step} on ${ipaddr}"
    until ssh ${SSH_OPTIONS[@]} ${remote_user}@${ipaddr} ${step}; do
        echo "### ssh to $ipaddr failed, retrying in $DELAY seconds..."
        sleep $DELAY
    done
}

function do_ulimit() {
    local addr=$(ip4domain $1 'bus')

    ssh ${SSH_OPTIONS[@]} ubuntu@${addr} <<- EOC
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

function provision () {
    local domain=$1
    local addr=$(ip4domain $1 'bus')
    local -a PROVISION_STEPS
    local -a UPGRADE_STEPS=("sudo apt-get update 2>&1 >> apt.log"
                            "sudo apt-get -y install qemu-guest-agent"
                            "sudo apt-get -y dist-upgrade 2>&1 >> apt.log")
    case $domain in
        jumpstart)
            PROVISION_STEPS=("sudo apt-get -y install --no-install-recommends"`
                                `" ca-certificates"`
                                `" ntp"`
                                `" ntpdate"`
                                `" uuid-runtime"`
                                `" git"`
                                `" make"`
                                `" jq"`
                                `" nmap"`
                                `" curl"`
                                `" ipcalc"`
                                `" sshpass"`
                                `" patch"`
                                `" python-cmd2"`
                                `" 2>&1 >> apt.log")
            ;;
         *)
            PROVISION_STEPS=("sudo apt-get -y install --no-install-recommends"`
                                `" ntp"`
                                `" ntpdate"`
                                `" curl"`
                                `" git"`
                                `" 2>&1 >> apt.log")
            ;;
    esac
    for step in "${UPGRADE_STEPS[@]}"   ; do remote $domain "$step" ; done
    do_ulimit $domain
    do_reboot $domain
    addr=$(ip4domain $domain 'bus')
    for step in "${PROVISION_STEPS[@]}" ; do remote $domain "$step" ; done
    ssh ${SSH_OPTIONS[@]} ubuntu@${addr} <<- EOC
	sudo su -
	echo "net.ipv4.ip_forward = 1" >>/etc/sysctl.conf
	EOC
    case $domain in
        jumpstart)
            scp ${SSH_OPTIONS[@]} prov_master.sh ubuntu@${addr}:prov_master.sh
            remote $domain "bash prov_master.sh"
            ;;
        k8s-m)
            remote $domain "source "`
                             `"<(curl -s https://raw.githubusercontent.com/kubernetes/helm/master/scripts/get)"`
                             `" --version v2.8.2"
            ;;
        *)
            ;;
    esac
    do_reboot $domain
    addr=$(ip4domain $domain 'bus')
    echo -e "\n### Domain $1 ($addr) is provisioned\n"
}

function provision_jumpstart () {
    local domain='jumpstart'
    local addr=$(ip4domain 'jumpstart' 'bus')
    local -a PROVISION_STEPS=("sudo apt-get -y install --no-install-recommends"`
                                `" ca-certificates"`
                                `" ntp"`
                                `" ntpdate"`
                                `" uuid-runtime"`
                                `" git"`
                                `" make"`
                                `" jq"`
                                `" nmap"`
                                `" curl"`
                                `" ipcalc"`
                                `" sshpass"`
                                `" patch"`
                                `" python-cmd2"`
                                `" 2>&1 >> apt.log")
    for step in "${PROVISION_STEPS[@]}" ; do remote $domain "$step" ; done
    scp ${SSH_OPTIONS[@]} prov_master_bare.sh ${JUMPSTART_USER}@${addr}:prov_master_bare.sh
    remote $domain "bash prov_master_bare.sh"
    echo -e "\n### Jumpstart $domain ($addr) is provisioned\n"
}

function add_to_ssh_config() {
    local domain=$1
    local ipaddr=$(ip4domain $1 'bus')
    local oldip=$(grep -w $domain -A 1 ${HOME}/.ssh/config | awk '/Hostname/ {print $2}')
    if [[ -z $oldip ]]
    then
        cat <<- EOC >> "${HOME}/.ssh/config"
	
	Host $domain
	     Hostname $ipaddr
	     user ubuntu
	     StrictHostKeyChecking no
	     UserKnownHostsFile /dev/null
	EOC
    else
        sed -i "s/${oldip}/${ipaddr}/g" "${HOME}/.ssh/config"
    fi
}

function populate_ssh() {
    local addr=$(ip4domain 'jumpstart' 'bus')
    local targetaddr

    for target in ${DOMAINS[@]} ; do
        if [[ "$target" != "jumpstart" ]]; then
            targetaddr=$(ip4domain $target 'bus')
            ssh ${SSH_OPTIONS[@]} ${JUMPSTART_USER}@${addr} sshpass -p 'ubuntu' ssh-copy-id ${SSH_OPTIONS[@]} "ubuntu@${targetaddr}"
            ssh ${SSH_OPTIONS[@]} ${JUMPSTART_USER}@${addr} scp ${SSH_OPTIONS[@]} .ssh/id_rsa "ubuntu@${targetaddr}:id_rsa"
            echo "### Setting up deploy key on ${target} ($targetaddr)"
            ssh ${SSH_OPTIONS[@]} ubuntu@${targetaddr} <<- EOC
		sudo mkdir -p /etc/openstack-helm
		sudo mv /home/ubuntu/id_rsa /etc/openstack-helm/deploy-key.pem
		sudo chown ubuntu /etc/openstack-helm/deploy-key.pem
		EOC
        fi
    done
}

function syncrepos() {
    local addr=$(ip4domain 'jumpstart' 'bus')

    scp ${SSH_OPTIONS[@]} sync.sh ${JUMPSTART_USER}@${addr}:sync.sh
    remote 'jumpstart' "bash sync.sh"
}


function run_playbooks() {
    local addr=$(ip4domain 'jumpstart' 'bus')

    ssh ${SSH_OPTIONS[@]} ${JUMPSTART_USER}@${addr} <<- EOC
	export LC_ALL=C
	cd /opt/openstack-helm-infra
	make dev-deploy setup-host multinode
	make dev-deploy k8s multinode
	EOC
}

function do_deploy() {
    local addr=$(ip4domain 'k8s-m' 'bus')

    scp ${SSH_OPTIONS[@]} deploy.sh ${JUMPSTART_USER}@${addr}:deploy.sh
    remote 'k8s-m' "bash deploy.sh"
}

function main() {
    sudo sysctl vm.swappiness=10
    mknet
    for domain in ${DOMAINS[@]} ; do
        mkseed $domain
        mkimage $domain
        mkdomain $domain
        provision $domain
        add_to_ssh_config $domain
    done
    populate_ssh
    syncrepos
    run_playbooks
    do_deploy
}


# main "$@"

function main_virsh() {
    sudo sysctl vm.swappiness=10
    mknet
    for step in mkseed mkimage mkdomain; do
        echo -e "\n###\n# $step\n###\n"
        for domain in ${DOMAINS[@]} ; do
            $step $domain
        done
    done
}

function main_provision() {
    echo -e "\n### IP addresses:\n# ${!IP4DOMAINS[@]}\n# ${IP4DOMAINS[@]}\n###"

    provision_jumpstart
    for step in provision add_to_ssh_config; do
        for domain in ${DOMAINS[@]} ; do
            echo -e "\n###\n# $step $domain\n###\n"
            $step $domain
        done
    done
    populate_ssh
    syncrepos
}