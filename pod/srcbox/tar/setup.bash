#!/usr/bin/env bash
set -euo pipefail

# untar from dist
cd ..
tar -xf /mnt/dist/pwrusr.tar
cd srcbox

# initial upgrade
dnf -y upgrade
dnf -y install dnf-plugins-core

# copy yum repository files
cp fs/etc/yum.repos.d/* /etc/yum.repos.d
chmod 640 /etc/yum.repos.d/*.repo

# copy sudoers config; box has sudo
cp fs/etc/sudoers.d/box /etc/sudoers.d 
chmod 440 /etc/sudoers.d/box

# copy pam configuration; creates default XDG and UENV env vars
cp fs/etc/security/pam_env.conf /etc/security
chmod 644 /etc/security/pam_env.conf

# create opt dir for srcbox
mkdir -p /opt/srcbox

# copy container entrypoints to srcbox opt
cp -R fs/opt/srcbox/* /opt/srcbox
chmod 755 /opt/srcbox/entry/*.sh

# enable the copr repositories listed in the `repositories` file
mapfile -t REPOSITORIES < repositories
dnf -y copr enable $REPOSITORIES

# upgrade to finalize repositories
dnf -y upgrade

# install the packages listed in the `packages` file
mapfile -t PACKAGES < packages
dnf -y install $PACKAGES
dnf clean all

# the shadow file must be group readable for ssh to work with the box user
chmod 640 /etc/shadow

# create the box user
useradd -m -k /dev/null -s /usr/bin/nu box
usermod -aG box
echo "box:box" | chpasswd

# finalize ownership and permission
chown -R box:box /home/box
chmod -R go-rwx /home/box 
chown -R root:root /root
chmod -R go-rwx /root 




