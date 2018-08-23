# ARG before FROM is introduced at Docker 17.0.5
#ARG UBUNTU_VESION=16.04
#FROM ubuntu:${UBUNTU_VESION}
FROM ubuntu:16.04

# Idea from
# https://github.com/rastasheep/ubuntu-sshd/blob/master/16.04/Dockerfile
# https://github.com/phusion/baseimage-docker

ARG JUMPSTART_USER=ubuntu

RUN apt-get update\
 && apt-get install -y --no-install-recommends openssh-server sudo python python-apt ca-certificates ntp ntpdate uuid-runtime git make jq nmap curl ipcalc sshpass patch python-cmd2 nano\
 && apt-get clean

RUN mkdir /var/run/sshd\
 && sed -i 's|^PermitRootLogin .*|PermitRootLogin yes|' /etc/ssh/sshd_config\
 && sed -i 's|session\s*required\s*pam_loginuid.so|session optional pam_loginuid.so|g' /etc/pam.d/sshd

RUN echo 'root:root' | chpasswd\
 && useradd -m ${JUMPSTART_USER}\
 && usermod -a -G sudo ${JUMPSTART_USER}\
 && echo ${JUMPSTART_USER}':'${JUMPSTART_USER} | chpasswd

RUN mkdir -p /home/${JUMPSTART_USER}/.ssh/\
 && ssh-keygen -q -f /home/${JUMPSTART_USER}/.ssh/id_rsa -t rsa -N ''\
 && chown -R ${JUMPSTART_USER}':'${JUMPSTART_USER} /home/${JUMPSTART_USER}/.ssh/

RUN mkdir -p /etc/openstack-helm\
 && cp /home/${JUMPSTART_USER}/.ssh/id_rsa /etc/openstack-helm/deploy-key.pem\
 && chown $JUMPSTART_USER /etc/openstack-helm/deploy-key.pem\
 && chown -R $JUMPSTART_USER: /opt\
 && git clone "https://github.com/pgillich/openstack-ccp.git" "/opt/openstack-ccp"\
 && git clone "https://git.openstack.org/openstack/openstack-helm.git" "/opt/openstack-helm"\
 && git clone "https://git.openstack.org/openstack/openstack-helm-infra.git" "/opt/openstack-helm-infra"

CMD ["/usr/sbin/sshd", "-D"]
#ENTRYPOINT service ssh restart && bash
