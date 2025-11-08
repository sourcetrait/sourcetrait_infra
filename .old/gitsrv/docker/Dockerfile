FROM rockylinux/rockylinux:10

RUN dnf -y update && dnf -y install openssh-server git sudo && dnf clean all

RUN ssh-keygen -A
COPY --chown=root:root --chmod=600 up/sshd_config_d /etc/ssh/sshd_config.d/1000-gitserv.conf

RUN useradd git --shell /usr/bin/git-shell # system maintenance account
#RUN useradd git # uncomment this and comment above to debug shell logins
RUN groupadd git_admin # can add, remove, promote, and demote users
RUN groupadd git_commit # can commit to git repositories
RUN groupadd gitusr # can access ssh and read from git repositories
RUN usermod -aG git_admin,gitusr git

# git repositories are located in /srv/git
RUN mkdir -p /srv/git && chown git:gitusr /srv/git && chmod 750 /srv/git

# the maintenance account's pubkey is a docker secret (git_ssh_pubkey)
# mounted to their authorized_keys file
RUN mkdir -p /home/git/.ssh
RUN chown -R git:git /home/git && chmod -R go-rwx /home/git

COPY --chown=root:gitusr --chmod=750 up/git-shell-commands /home/git/git-shell-commands
COPY --chown=root:gitusr --chmod=750 up/git-shell-env /home/git/git-shell-env

COPY --chown=root:root --chmod=600 up/sudoers_d /etc/sudoers.d/1000-gitserv

# uncomment to debug logins
#RUN echo 'root:debug' | chpasswd
#RUN sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config

EXPOSE 22
CMD ["/usr/sbin/sshd", "-D"]
