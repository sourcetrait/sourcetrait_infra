#!/bin/bash
set -euo pipefail

docker compose down
docker compose up --build --force-recreate -d
docker container list --all
ssh-keygen -f "$HOME/.ssh/known_hosts" -R '[localhost]:10022'
ssh -yp 10022 localhost -l git -i "$HOME/.ssh/id_git_gitsrv"
