# SourceTrait Infrastructure: Git Server

An implementation of Git's official chapter for [Git on the Server](https://git-scm.com/book/en/v2/Git-on-the-Server-Setting-Up-the-Server)
using docker.

Git+SSH is locked down and users are limited to git-shell.

Basic administration is available via git-shell-commands; Manipulate repositories, users, and their
roles.

System user accounts and groups are used for permissions. SELinux provides
granular role constraints. 

Running on Rocky Linux (community RHEL).
