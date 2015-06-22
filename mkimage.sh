#!/bin/bash

function print_usage {
	echo >&2

	echo >&2 "usage: $0 \$image \$version \$justTar"

	echo >&2
	echo >&2 "example: $0 cloudix-dev 0.1 # builds image cloudix-dev version 0.1, not pushing to dockerhub."
	echo >&2 "example: $0 cloudix-dev 0.1 true # builds cloudix-linux-fs.tar.bz2"
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
tarfile="cloudix-linux-fs.tar.bz2"
include="epel-release"

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
	#cp -a /etc/yum/vars "$target"/etc/yum/
fi

# install packages
sudo yum --disablerepo='*' \
		--enablerepo=cloudix-master \
		--enablerepo=cloudix-main \
		--enablerepo=cloudix-updates \
		--installroot="$target" \
		--setopt=tsflags=nodocs \
    --setopt=group_package_types=mandatory -y \
    	groupinstall Base

# install includes
if [ ! -z "$include" ] ; then
	sudo yum --disablerepo='*' \
		--enablerepo=cloudix-master \
		--enablerepo=cloudix-main \
		--enablerepo=cloudix-updates \
		--installroot="$target" \
		--setopt=tsflags=nodocs \
		-y install "$include"
fi

# clean up yum
sudo yum --installroot="$target" -y \
		clean all

# fix for EPEL, we don't have fastest-mirror plugin.
sudo sed -i 's|#baseurl|baseurl|g' ${target}/etc/yum.repos.d/epel.repo
sudo sed -i 's|mirrorlist|#mirrorlist|g' ${target}/etc/yum.repos.d/epel.repo
sudo sed -i 's|#baseurl|baseurl|g' ${target}/etc/yum.repos.d/epel-testing.repo
sudo sed -i 's|mirrorlist|#mirrorlist|g' ${target}/etc/yum.repos.d/epel-testing.repo


# make sure /etc/resolv.conf has something useful in it
sudo bash -c 'cat > "$target"/etc/resolv.conf <<EOF
nameserver 8.8.8.8
nameserver 8.8.4.4
EOF
'

# remove amazon mirrors, they are useless outside of aws network
sudo rm -fv "$target"/etc/yum.repos.d/amzn*

# add custom yum mirrors, AWS dosn't allow access from outside there own network
sudo bash -c "cat > ${target}/etc/yum.repos.d/cloudix-main.repo <<EOF
[cloudix-main]
name=cloudix-main-Base
baseurl=http://rpm.cloudix-linux.com/main/
enabled=1
gpgcheck=0
mirror_expire=300
metadata_expire=300
priority=10
fastestmirror_enabled=0
retries=5
timeout=10
EOF"

sudo bash -c "cat > ${target}/etc/yum.repos.d/cloudix-master.repo <<EOF
[cloudix-master]
name=cloudix-master-Base
baseurl=http://rpm.cloudix-linux.com/master/
enabled=1
gpgcheck=0
mirror_expire=300
metadata_expire=300
priority=1
fastestmirror_enabled=0
retries=5
timeout=10
EOF"

sudo bash -c "cat > ${target}/etc/yum.repos.d/cloudix-updates.repo <<EOF
[cloudix-updates]
name=cloudix-updates-Base
baseurl=http://rpm.cloudix-linux.com/updates/
enabled=1
gpgcheck=0
mirror_expire=300
metadata_expire=300
priority=10
fastestmirror_enabled=0
retries=5
timeout=10
EOF"

sudo bash -c "cat > ${target}/etc/yum.repos.d/cloudix-extra.repo <<EOF
[cloudix-extra]
name=cloudix-extra
baseurl=http://rpm.cloudix-linux.com/extra/
enabled=0
gpgcheck=0
mirror_expire=300
metadata_expire=300
priority=10
fastestmirror_enabled=0
retries=5
timeout=10
EOF"

## Color Bash Prompt
# Read more at https://wiki.archlinux.org/index.php/Color_Bash_Prompt
sudo bash -c "cat > ${target}/root/.bashrc <<EOF
PS1='\[\e[0;32m\]\u\[\e[m\] \[\e[1;34m\]\w\[\e[m\] \[\e[1;32m\]\$\[\e[m\] \[\e[1;37m\]'
EOF"

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
	echo "Creating tar for ${name}:${version}, target cloudix-linux-fs.tar.bz2"
	touch "$tarfile"
	sudo tar --numeric-owner -C "$target" -caf "$tarfile" .
else
	echo "Creating docker image ${name}:${version}"
	sudo tar --numeric-owner -c -C "$target" . | sudo docker import - $name:$version
	sudo docker run -i -t --rm $name:$version echo success
	echo "Done! Run new image with:"
	echo "# sudo docker run -i -t --rm $name:$version /bin/bash"
fi

sudo rm -rf "$target"
