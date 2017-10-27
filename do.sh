#!/bin/bash
ARCHURI="https://cloud-images.ubuntu.com/xenial/current"
ARCHIMAGE="xenial-server-cloudimg-amd64-disk1.img"
IMAGE="xenserv.img"
SSH_OPTIONS=(-o StrictHostKeyChecking=no -o GlobalKnownHostsFile=/dev/null -o UserKnownHostsFile=/dev/null -o LogLevel=error)
PUBKEY=$(<${HOME}/.ssh/id_rsa.pub)
MYDIR=$(dirname $(readlink -f "$0"))
DOMAINS=('infra1' 'storage1' 'log1' 'compute1' 'compute2' 'jumpstart')
declare -A IMGSIZ=( ['jumpstart']='4G' ['infra1']='4G' ['storage1']='4G' ['log1']='4G' ['compute1']='4G' ['compute2']='4G' )
DELAY=10
OUCPATCH="openstack_user_config.yaml.diff"

function mkseed () {
	local seed="seed-${1}"
    cat <<- EOF > $seed
	#cloud-config
	hostname: $1
	password: ubuntu
	chpasswd: { expire: False }
	ssh_pwauth: True
	ssh_authorized_keys:
	    - ${PUBKEY}
	EOF
    cloud-localds "${seed}.img" $seed
    echo -e "\n### $1: cloudinit: ${seed}.img\n"
}

function mkimage () {
    wget -nc -q -O $IMAGE "${ARCHURI}/${ARCHIMAGE}"
    qemu-img convert -O qcow2 $IMAGE  "${1}.qcow2"
    qemu-img resize "${1}.qcow2" ${IMGSIZ[${1}]}
    qemu-img info "${1}.qcow2"
}

function mkstorage () {
    local size=${1:-'16G'}
    qemu-img create -f qcow2 storage.qcow2 $size
    qemu-img info storage.qcow2
}

function ip4domain () {
    local ETHERP="([0-9a-f]{2}:){5}([0-9a-f]{2})"
    local IPP="^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}"
    local MACS=$(virsh domiflist $1 |grep -o -E $ETHERP)
    for mac in $MACS ; do
        arp -e |grep $mac |grep -o -P $IPP
    done
}

function pingssh () {
    local ipaddr=$(ip4domain $1)
    (echo >/dev/tcp/${ipaddr}/22) &>/dev/null && return 0 || return 1
}

function wait4ssh () {
    until pingssh $1; do
        echo "### Waiting ${DELAY} seconds more for ssh..."
        sleep $DELAY
    done
}

function do_reboot () {
    virsh reboot $1
    sleep $DELAY
    wait4ssh $1
}

function mknet () {
    cat <<- EOF > "bus.xml"
	<network>
	  <name>bus</name>
	  <bridge name='bus' stp='on' delay='0'/>
	</network>
	EOF
    if virsh net-list --all|cut -d ' ' -f 2|egrep -q -wo 'bus'; then
        virsh net-destroy bus
        virsh net-undefine bus
    fi
    virsh net-define bus.xml
    virsh net-start bus
}

function mkdomain () {
    cat <<- EOF > "${1}.xml"
	<domain type="kvm">
	    <name>$1</name>
	    <memory>1048576</memory>
	    <os>
	        <type>hvm</type>
	        <boot dev="hd" />
	    </os>
	    <features>
	        <acpi />
	    </features>
	    <vcpu>1</vcpu>
	    <devices>
	        <disk type="file" device="disk">
	            <driver type="qcow2" cache="none" />
	            <source file="${MYDIR}/${1}.qcow2" />
	            <target dev="vda" bus="virtio" />
	        </disk>
	        <disk type="file" device="cdrom">
	            <source file="${MYDIR}/seed-${1}.img" />
	            <target dev="vdb" bus="virtio" />
	            <readonly/>
	        </disk>
	EOF
    if [[ "$1" = "storage1" ]]; then
        cat <<- EOF >> "${1}.xml"
	        <disk type="file" device="disk">
	            <driver type="qcow2" cache="none" />
	            <source file="${MYDIR}/storage.qcow2" />
	            <target dev="vdc" bus="virtio" />
	        </disk>
	EOF
    fi
    cat <<- EOF >> "${1}.xml"
	        <interface type="network">
	            <source network="default" />
	            <model type="virtio" />
	       </interface>
	        <interface type="network">
	            <source network="bus" />
	            <model type="e1000" />
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
	    </devices>
	</domain>
	EOF
    virsh define ${1}.xml
    virsh start ${1}
    wait4ssh ${1}
    echo -e "\n### Domain $1 is up\n"
}

function remote() {
    local ipaddr=$(ip4domain $1)
    local step=$2

    echo "### $1: Doing ${step} on ${ipaddr}"
    until ssh ${SSH_OPTIONS[@]} ubuntu@${ipaddr} ${step}; do
        echo "### ssh to $ipaddr failed, retrying in $DLEAY seconds..."
        sleep $DELAY
    done
}

function provision () {
    local domain=$1
    local addr=$(ip4domain $1)
    local jumposa="/opt/openstack-ansible"
    local jumpdepcfg="/etc/openstack_deploy"
    local osauc="${jumpdepcfg}/openstack_user_config.yml"
    local -a PROVISION_STEPS
    local -a UPGRADE_STEPS=("sudo apt-get update 2>&1 >> apt.log"
                            "sudo apt-get -y dist-upgrade 2>&1 >> apt.log")
    case $domain in
        jumpstart)
            PROVISION_STEPS=("sudo apt-get -y install"`
                                `" build-essential"`
                                `" ntp"`
                                `" ntpdate"`
                                `" python-dev"`
                                `" 2>&1 >> apt.log")
            ;;
         *)
            PROVISION_STEPS=("sudo apt-get -y install"`
                                `" bridge-utils"`
                                `" debootstrap"`
                                `" ifenslave"`
                                `" ifenslave-2.6"`
                                `" lsof"`
                                `" lvm2"`
                                `" ntp"`
                                `" ntpdate"`
                                `" tcpdump"`
                                `" vlan"`
                                `" python"`
                                `" 2>&1 >> apt.log")
            ;;
    esac
    for step in "${UPGRADE_STEPS[@]}"   ; do remote $domain "$step" ; done
    do_reboot $domain
    for step in "${PROVISION_STEPS[@]}" ; do remote $domain "$step" ; done
    case $domain in
        jumpstart)
            do_reboot $domain
            scp ${SSH_OPTIONS[@]} "$OUCPATCH" "ubuntu@${addr}:${OUCPATCH}"
            ssh ${SSH_OPTIONS[@]} ubuntu@${addr} <<- EOC
		sudo su -
		apt-get install git
		git clone https://git.openstack.org/openstack/openstack-ansible $jumposa
		cat >>"${jumposa}/ansible-role-requirements.yml" <<EOF
		- name: os_monasca
		  scm: git
		  src: https://git.openstack.org/openstack/openstack-ansible-os_monasca
		  version: master
		EOF
		cp -r "${jumposa}/etc/openstack_deploy/." "${jumpdepcfg}/"
		cp "${jumpdepcfg}/openstack_user_config.yml.test.example" $osauc
		patch $osauc "/home/ubuntu/${OUCPATCH}"
		bash ${jumposa}/scripts/bootstrap-ansible.sh 2>&1 >> /home/ubuntu/ansible.log
		EOC
            ;;
        storage1)
            scp ${SSH_OPTIONS[@]} "interfaces.${domain}" "ubuntu@${addr}:interfaces.${domain}"
            ssh ${SSH_OPTIONS[@]} ubuntu@${addr} <<- EOC
		sudo su -
		echo 'bonding' >> /etc/modules
		echo '8021q' >> /etc/modules
		cat "/home/ubuntu/interfaces.${domain}" >/etc/network/interfaces.d/60-osa-interfaces.cfg
		pvcreate --metadatasize 2048 /dev/vdc
		vgcreate cinder-volumes /dev/vdc
		EOC
            do_reboot $domain
            ;;
        *)
            scp ${SSH_OPTIONS[@]} "interfaces.${domain}" "ubuntu@${addr}:interfaces.${domain}"
            ssh ${SSH_OPTIONS[@]} ubuntu@${addr} <<- EOC
		sudo su -
		echo 'bonding' >> /etc/modules
		echo '8021q' >> /etc/modules
		cat "/home/ubuntu/interfaces.${domain}" >/etc/network/interfaces.d/60-osa-interfaces.cfg
		EOC
            do_reboot $domain
            ;;
    esac
    echo -e "\n### Domain $1 ($addr) is provisioned\n"
}

function add_to_ssh_config() {
    local domain=$1
    local ipaddr=$(ip4domain $1)
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

mknet
mkstorage
for domain in ${DOMAINS[@]} ; do
    mkseed $domain
    mkimage $domain
    mkdomain $domain
    provision $domain
    add_to_ssh_config $domain
done

#virsh shutdown guest1 --mode acpi


