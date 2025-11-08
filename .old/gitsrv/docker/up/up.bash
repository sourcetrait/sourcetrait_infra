#!/bin/bash
# Expects:
#  - $PWD/up
#  - $PWD/up/id_git.pub :: Added to `git` user's authorized SSH keys
#  - $PWD/up/sshd_config_d :: Added to /etc/ssh/sshd_config.d/
set -euo pipefail
umask 077

#SRCDIR="$(realpath $PWD)"

#mv "$SRCDIR/sshd_config_d" /etc/ssh/sshd_config.d/1000-gitserv.conf
#chmod 600 /etc/ssh/sshd_config.d/1000-gitserv.conf

#mkdir -p /srv/git
#chown git:gitusr /srv/git
#chmod 750 /srv/git

#mkdir -p /home/git/.ssh
#chown -R git:git /home/git
#chmod -R go-rwx /home/git

exit 0
