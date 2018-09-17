# Preparing

Jumpstart host will be the k8s master.

## Preparing all hosts

```
sudo -i
echo "ubuntu ALL=(ALL) NOPASSWD:ALL" >/etc/sudoers.d/ubuntu
```
Replace last line of /root/.profile to:
```
tty -s && mesg n || true
```

## Get repo on Jumpstart host

```
mkdir git
cd git
git clone https://github.com/pgillich/openstack-ccp.git
cd openstack-ccp
```

## Preparing Jumpstart host

```
./jumpstart_prepare_host.sh
sudo reboot
```

## Make Jumpstart image

```
cd git/openstack-ccp
./jumpstart_make.sh
```

## Start Jumpstart

```
./jumpstart_start.sh
```

## Ssh to Jumpstart

```
ssh -p 2222 localhost
```

## Configure hosts


