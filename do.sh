#!/bin/bash
if [[ "$1" = "debug" ]]; then
    set -x
fi

OSAREPO="https://git.openstack.org/openstack/openstack-ansible"
OSKVER="queens"
OSABRANCH="stable/${OSKVER}"
ARCHURI="https://cloud-images.ubuntu.com/xenial/current"
ARCHIMAGE="xenial-server-cloudimg-amd64-disk1.img"
IMAGE="xenserv.img"
SSH_OPTIONS=(-o StrictHostKeyChecking=no -o GlobalKnownHostsFile=/dev/null -o UserKnownHostsFile=/dev/null -o LogLevel=error)
PUBKEY=$(<${HOME}/.ssh/id_rsa.pub)
MYDIR=$(dirname $(readlink -f "$0"))
DOMAINS=('jumpstart' 'infra1' 'storage1' 'log1' 'compute1' 'compute2')
declare -A IMGSIZ=( ['jumpstart']='16G' ['infra1']='48G' ['storage1']='16G' ['log1']='16G' ['compute1']='16G' ['compute2']='16G' )
declare -A MEMSIZ=( ['jumpstart']='4194304' ['infra1']='16777216' ['storage1']='8388608' ['log1']='8388608' ['compute1']='8388608' ['compute2']='8388608' )
declare -A VCPUS=( ['jumpstart']='2' ['infra1']='4' ['storage1']='2' ['log1']='2' ['compute1']='2' ['compute2']='2' )
ULIMIT=4096 # 4096 should be ok...
DELAY=10
OUCPATCH="openstack_user_config.yaml.diff"
MAOH="maoh.patch"
CLUSTER_GATEWAY="172.29.236.1/22"

function mkseed () {
    local seed="seed-${1}"
    cat <<- EOF > ${seed}
	#cloud-config
	hostname: $1
	password: ubuntu
	chpasswd: { expire: False }
	ssh_pwauth: True
	ssh_authorized_keys:
	    - ${PUBKEY}
	EOF
    cloud-localds "${seed}.iso" ${seed}
    echo -e "\n### $1: cloudinit: ${seed}.iso\n"
}

function mkimage () {
    wget -nc -q -O ${IMAGE} "${ARCHURI}/${ARCHIMAGE}"
    qemu-img convert -O qcow2 ${IMAGE}  "${1}.qcow2"
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
    local net=${2:-'default'}
    local mac=$(virsh domiflist $1 | grep $net | grep -o -E $ETHERP)

    arp -e | grep $mac | grep -o -P $IPP
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
    sleep $DELAY
    virsh reboot $1 --mode=agent
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
    virsh net-define bus.xml
    virsh net-start bus
    sudo modprobe 8021q
    sudo vconfig add bus 10
    sudo ifconfig bus.10 ${CLUSTER_GATEWAY}
}

function mkdomain () {
    cat <<- EOF > "${1}.xml"
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
	            <source file="${MYDIR}/${1}.qcow2"/>
	            <target dev="vda" bus="virtio"/>
	        </disk>
	        <disk type="file" device="cdrom">
	            <source file="${MYDIR}/seed-${1}.iso"/>
	            <target dev="vdb" bus="virtio"/>
	            <readonly/>
	        </disk>
	EOF
    if [[ "$1" = "storage1" ]]; then
        cat <<- EOF >> "${1}.xml"
	        <disk type="file" device="disk">
	            <driver type="qcow2" cache="none"/>
	            <source file="${MYDIR}/storage.qcow2"/>
	            <target dev="vdc" bus="virtio"/>
	        </disk>
	EOF
    fi
    cat <<- EOF >> "${1}.xml"
	        <interface type="network">
	            <source network="default"/>
	            <model type="virtio"/>
	        </interface>
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

function do_ulimit() {
    local addr=$(ip4domain $1)

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

function add_uca () {
    local addr=$(ip4domain $1)
    local aptfile="/etc/apt/sources.list.d/default.list"

    ssh ${SSH_OPTIONS[@]} ubuntu@${addr} <<- EOC
	sudo su -
	cat << EOF > ${aptfile}
	deb http://ubuntu-cloud.archive.canonical.com/ubuntu xenial-updates/${OSKVER} main
	EOF
	EOC
}

function provision () {
    local domain=$1
    local addr=$(ip4domain $1)
    local jumposa="/opt/openstack-ansible"
    local jumpdepcfg="/etc/openstack_deploy"
    local osauc="${jumpdepcfg}/openstack_user_config.yml"
    local osauv="${jumpdepcfg}/user_variables.yml"
    local -a PROVISION_STEPS
    local -a UPGRADE_STEPS=("sudo apt-get update 2>&1 >> apt.log"
                            "sudo apt-get -y install qemu-guest-agent"
                            "sudo apt-get -y dist-upgrade 2>&1 >> apt.log")
    case $domain in
        jumpstart)
            PROVISION_STEPS=("sudo apt-get -y install"`
                                `" build-essential"`
                                `" ntp"`
                                `" ntpdate"`
                                `" python-dev"`
                                `" libssl-dev libffi-dev"`
                                `" python-crypto"`
                                `" python-yaml"`
                                `" vlan"`
                                `" sshpass"`
                                `" 2>&1 >> apt.log")
            ;;
         infra1)
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
                                `" openvswitch-switch"`
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
    #add_uca $domain
    for step in "${UPGRADE_STEPS[@]}"   ; do remote $domain "$step" ; done
    do_ulimit $domain
    do_reboot $domain
    for step in "${PROVISION_STEPS[@]}" ; do remote $domain "$step" ; done
    ssh ${SSH_OPTIONS[@]} ubuntu@${addr} <<- EOC
	sudo su -
	echo "net.ipv4.ip_forward = 1" >>/etc/sysctl.conf
	EOC
    case $domain in
        jumpstart)
	    scp ${SSH_OPTIONS[@]} "interfaces.${domain}" "ubuntu@${addr}:interfaces.${domain}"
	    ssh ${SSH_OPTIONS[@]} ubuntu@${addr} <<- EOC
		sudo su -
		echo '8021q' >> /etc/modules
		cat "/home/ubuntu/interfaces.${domain}" >/etc/network/interfaces.d/60-osa-interfaces.cfg
		EOC
            do_reboot $domain
            scp ${SSH_OPTIONS[@]} "$OUCPATCH" "ubuntu@${addr}:${OUCPATCH}"
            ssh ${SSH_OPTIONS[@]} ubuntu@${addr} <<- EOC
		sudo su -
		apt-get install git
		git clone -b ${OSABRANCH} ${OSAREPO} ${jumposa}
		pushd ${jumposa}
		git checkout "54870ed"
		popd
		cat >>"${jumposa}/ansible-role-requirements.yml" <<EOF
		- name: os_monasca
		  scm: git
		  src: https://git.openstack.org/openstack/openstack-ansible-os_monasca
		  version: "a6f0e9d"
		- name: os_monasca-agent
		  scm: git
		  src: https://git.openstack.org/openstack/openstack-ansible-os_monasca-agent
		  version: "e88aff1"
		- name: os_monasca-ui
		  scm: git
		  src: https://git.openstack.org/openstack/openstack-ansible-os_monasca-ui
		- name: ansible-zookeeper
		  scm: git
		  src: https://github.com/Chillisystems/ansible-zookeeper
		- name: ansible-kafka
		  scm: git
		  src: https://github.com/flaviodsr/ansible-kafka
		- name: ansible-storm
		  scm: git
		  src: https://github.com/flaviodsr/ansible-storm
		- name: ansible-influxdb
		  scm: git
		  src: https://github.com/flaviodsr/ansible-influxdb
		- name: grafana-ansible
		  scm: git
		  src: https://github.com/flaviodsr/grafana-ansible
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

function populate_ssh() {
    local addr=$(ip4domain 'jumpstart')
    local kfiles=('id_rsa' 'id_rsa.pub')
    local targetaddr

    for kfile in ${kfiles[@]} ; do
        ssh ${SSH_OPTIONS[@]} ubuntu@${addr} <<- EOC
	sudo su -
	cp "/root/.ssh/${kfile}" "/home/ubuntu/.ssh/${kfile}"
	chown ubuntu.ubuntu "/home/ubuntu/.ssh/${kfile}"
	EOC
    done
    for target in ${DOMAINS[@]} ; do
        if [[ "$target" != "jumpstart" ]]; then
            targetaddr=$(ip4domain $target)
            ssh ${SSH_OPTIONS[@]} ubuntu@${addr} sshpass -p 'ubuntu' ssh-copy-id ${SSH_OPTIONS[@]} "ubuntu@${targetaddr}"
            ssh ${SSH_OPTIONS[@]} ubuntu@${addr} scp ${SSH_OPTIONS[@]} .ssh/id_rsa.pub "ubuntu@${targetaddr}:id_rsa.pub"
            echo "### Setting up ansible key on ${target} ($targetaddr)"
            ssh ${SSH_OPTIONS[@]} ubuntu@${targetaddr} <<- EOC
		sudo su -
		cat /home/ubuntu/id_rsa.pub >> /root/.ssh/authorized_keys
		chmod 600 /root/.ssh/authorized_keys
		rm -f /home/ubuntu/id_rsa.pub
		EOC
        fi
    done
}

function configure_creds() {
    local addr=$(ip4domain 'jumpstart')
    local secretsfile="/etc/openstack_deploy/user_secrets.yml"

    ssh ${SSH_OPTIONS[@]} ubuntu@${addr} <<- EOC
	sudo su -
	cat >> ${secretsfile}   << EOF
	
	## Monasca options
	grafana_admin_password:
	grafana_galera_password:
	monasca_container_mysql_password:
	monasca_influxdb_admin_password:
	monasca_api_influxdb_password:
	monasca_persister_influxdb_password:
	monasca_service_password:
	
	## Monasca-agent options
	monasca_agent_password:
	EOF
	python /opt/openstack-ansible/scripts/pw-token-gen.py --file ${secretsfile}
	EOC
}

function copytojump() {
    local addr=$(ip4domain 'jumpstart')

    scp ${SSH_OPTIONS[@]} ${1} ubuntu@${addr}:${1}
}

function add_monasca() {
    local addr=$(ip4domain 'jumpstart')
    local jumposa="/opt/openstack-ansible"
    local jumpdepcfg="/etc/openstack_deploy"
    local jroles="/etc/ansible/roles"
    local rppath="${jumposa}/playbooks/defaults/repo_packages"
    local gvpath="${jumposa}/inventory/group_vars"
    local rpomsd="${jroles}/os_monasca/extras/repo_packages"
    local rpom="openstack_monasca.yml"
    local gvom="monasca_all.yml"
    local gvoma="monasca-agent.yml"
    local edm="monasca.yml"
    local cdm="cd_monasca.yml"
    local omi="os-monasca-install.yml"
    local omai="os-monasca-agent-install.yml"
    local uhe="user_haproxy_extras.yml"
    local hop="horizon.patch"
    local soy="${jumposa}/playbooks/setup-openstack.yml"
    local soyp="soy.patch"
    local storm="${jroles}/ansible-storm/defaults/main.yml"
    local stormp="storm.patch"
    local -A transfer=( ['gvom']=$gvom
			['gvoma']=$gvoma
			['edm']=$edm
			['cdm']=$cdm
			['omi']=$omi
			['omai']=$omai
			['uhe']=$uhe
			['hop']=$hop
			['soyp']=$soyp
			['stormp']=$stormp )
    for cfile in "${!transfer[@]}" ; do
	copytojump ${transfer[${cfile}]}
    done

#sudo cp "${uhe}" "${jumpdefcfg}/${uhe}" &&\
    ssh ${SSH_OPTIONS[@]} ubuntu@${addr} <<- EOC
	sudo cp "${rpomsd}/${rpom}" "${rppath}/${rpom}" &&\
	sudo cp "${gvom}" "${gvpath}/${gvom}" &&\
	sudo cp "${gvoma}" "${gvpath}/all/${gvoma}" &&\
	sudo cp "${edm}" "${jumpdepcfg}/env.d/${edm}" &&\
	sudo cp "${cdm}" "${jumpdepcfg}/conf.d/monasca.yml" &&\
	sudo cp "${omi}" "${jumposa}/playbooks/${omi}" &&\
	sudo cp "${omai}" "${jumposa}/playbooks/${omai}" &&\
	cd "${jroles}/os_horizon" &&\
	sudo patch -p1 <"/home/ubuntu/${hop}" ||\
		 { echo "*** horizon patch failed"; exit 1; } &&\
	sudo patch ${soy} "/home/ubuntu/${soyp}" ||\
	         { echo "*** setup-openstack patch failed"; exit 1; } &&\
	sudo patch ${storm} "/home/ubuntu/${stormp}" ||\
	         { echo "*** patching storm role failed"; exit 1; }
	EOC
}

function run_playbooks() {
    local oh="/etc/ansible/roles/os_heat/defaults/main.yml"
    local addr=$(ip4domain 'jumpstart')

    copytojump ${MAOH}
    ssh ${SSH_OPTIONS[@]} ubuntu@${addr} <<- EOC
	export LC_ALL=C
	sudo patch "${oh}" "/home/ubuntu/${MAOH}" ||\
		 { echo -e "\n>>>>> patching failed"; exit 1; } &&\
	cd /opt/openstack-ansible/playbooks &&\
	sudo openstack-ansible setup-infrastructure.yml --syntax-check ||\
		 { echo -e "\n>>>>> setup-infrastructure: syntax error"; exit 1; } &&\
	sudo openstack-ansible setup-hosts.yml ||\
		 { echo -e "\n>>>> setup-hosts failed"; exit 1; } &&\
	sudo openstack-ansible setup-infrastructure.yml ||\
		 { echo -e "\n>>>>> setup-infrastructure failed"; exit 1; } &&\
	sudo ansible galera_container -m shell -a \
		 "mysql -h localhost -e 'show status like \"%wsrep_cluster_%\";'" ||\
		 { echo -e "\n>>>>> setup-galera failed"; exit 1; } &&\
	sudo openstack-ansible setup-openstack.yml ||\
		 { echo -e "\n>>>>> setup-openstack failed"; exit 1; }
	EOC
}

function verify() {
    local cid=$(lxc-ls | grep utility)
}

function main() {
    sudo sysctl vm.swappiness=10
    mknet
    mkstorage '32G'
    for domain in ${DOMAINS[@]} ; do
        mkseed $domain
        mkimage $domain
        mkdomain $domain
        provision $domain
        add_to_ssh_config $domain
    done
    populate_ssh
    configure_creds
    add_monasca
    run_playbooks
}


main "$@"
