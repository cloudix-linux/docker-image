#!/bin/bash

# pull repo to enuse we have up2date code
git pull

function print_usage {
	echo >&2

	echo >&2 "usage: $0 \$image \$version \$justTar"

	echo >&2
	echo >&2 "example: $0 sark/naas-linux 0.1 # builds sark/naas-linux image version 0.1."
	echo >&2 "example: $0 sark/naas-linux 0.1 true # builds naas-linux-fs.tar.bz2"
}

if [ -z "$1" ] ; then
	print_usage
	echo "Error, give image name as first argument!"
	exit
fi 

if [ -z "$2" ] ; then
	print_usage
	echo "Error, give image verison as second argument!"
	exit
fi

justTar=
if [ ! -z "$3" ] ; then
	justTar=1
fi

## container image properties
name=$1
version=$2
workspace=$(pwd)/workspace
tarfile="naas-linux-fs.tar.bz2"
include=""

if [ -d $workspace ] ; then
	echo "workspace/ directory exists, will do a clean up now!"
	read -r -p "Are you sure? [y/N] " response
	response=${response,,} # tolower
	if [[ $response =~ ^(yes|y)$ ]] ; then
		"$(pwd)/cleanworkspace.sh"
	else
		echo "Aborted by user input!"
		exit
	fi
fi

mkdir -pv $workspace

# create target in a temp directory
target=$workspace
echo "Target: $target"

set -x # will make the interpreter print each command right before it is executed
set -e # if a command exits with an error and the caller does not check such error, the script aborts immediately

# create working dev
sudo mkdir -m 755 "$target"/dev
sudo mknod -m 600 "$target"/dev/console c 5 1
sudo mknod -m 600 "$target"/dev/initctl p
sudo mknod -m 666 "$target"/dev/full c 1 7
sudo mknod -m 666 "$target"/dev/null c 1 3
sudo mknod -m 666 "$target"/dev/ptmx c 5 2
sudo mknod -m 666 "$target"/dev/random c 1 8
sudo mknod -m 666 "$target"/dev/tty c 5 0
sudo mknod -m 666 "$target"/dev/tty0 c 4 0
sudo mknod -m 666 "$target"/dev/urandom c 1 9
sudo mknod -m 666 "$target"/dev/zero c 1 5

## bootstrap container
# copy custom yum vars
if [ -d /etc/yum/vars ]; then
	mkdir -p -m 755 "$target"/etc/yum
	cp -a /etc/yum/vars "$target"/etc/yum/
fi

# install packages
sudo yum --disablerepo='*' \
		--enablerepo=naas-main \
		--enablerepo=naas-updates \
		--installroot="$target" \
		--setopt=tsflags=nodocs \
    	--setopt=group_package_types=mandatory -y \
    	groupinstall Base

# install includes
if [ ! -z "$include" ] ; then
	sudo yum --disablerepo='*' \
			--enablerepo=naas-main \
			--enablerepo=naas-updates \
			--installroot="$target" \
			--setopt=tsflags=nodocs \
			-y install "$include"
fi

# clean up yum
sudo yum --installroot="$target" -y \
		clean all

## inject configuration
# networking (no need when we build container)
#sudo cat > "$target"/etc/sysconfig/network <<EOF
#NETWORKING=yes
#HOSTNAME=localhost.localdomain
#EOF

# make sure /etc/resolv.conf has something useful in it
sudo bash -c 'cat > "$target"/etc/resolv.conf <<EOF
nameserver 8.8.8.8
nameserver 8.8.4.4
EOF
'

# remove amazon mirrors, they are useless outside of aws network
sudo rm -fv "$target"/etc/yum.repos.d/amzn*

# add custom yum mirrors, AWS dosn't allow access from outside there own network
sudo bash -c "cat > ${target}/etc/yum.repos.d/naas-main.repo <<EOF
[naas-main]
name=naas-main-Base
baseurl=http://rpm.naas.io/main/
enabled=1
gpgcheck=0
mirror_expire=300
metadata_expire=300
priority=10
fastestmirror_enabled=0
retries=5
timeout=10
EOF"

sudo bash -c "cat > ${target}/etc/yum.repos.d/naas-updates.repo <<EOF
[naas-updates]
name=naas-updates-Base
baseurl=http://rpm.naas.io/updates/
enabled=1
gpgcheck=0
mirror_expire=300
metadata_expire=300
priority=10
fastestmirror_enabled=0
retries=5
timeout=10
EOF"

# copy epel mirrors, same configuration as Amazon Linux AMI
if [ -f /etc/yum.repos.d/epel.repo ] ; then
	sudo cp -a /etc/yum.repos.d/epel.repo "$target"/etc/yum.repos.d/epel.repo
fi
if [ -f /etc/yum.repos.d/epel-testing.repo ] ; then
	sudo cp -a /etc/yum.repos.d/epel-testing.repo "$target"/etc/yum.repos.d/epel-testing.repo
fi

# clean up
sudo rm -rf "$target"/usr/{{lib,share}/locale,{lib,lib64}/gconv,bin/localedef,sbin/build-locale-archive}
sudo rm -rf "$target"/usr/share/{man,doc,info,gnome/help}
sudo rm -rf "$target"/usr/share/cracklib
sudo rm -rf "$target"/usr/share/i18n
sudo rm -rf "$target"/sbin/sln
sudo rm -rf "$target"/etc/ld.so.cache
sudo rm -rf "$target"/var/cache/ldconfig/*
sudo rm -fr "$target"/var/lib/yum

if [ "$justTar" ]; then
	echo "Creating tar for ${name}:${version}, target naas-linux-fs.tar.bz2"
	touch "$tarfile"
	sudo tar --numeric-owner -C "$target" -caf "$tarfile" .
else
	echo "Creating docker image ${name}:${version}"
	sudo tar --numeric-owner -c -C "$target" . | sudo docker import - $name:$version
	sudo docker run -i -t --rm $name:$version echo success
fi

sudo rm -rf "$target"
