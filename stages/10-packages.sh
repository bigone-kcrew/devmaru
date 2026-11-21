#!/usr/bin/env bash
# 패키지: 기본 도구 · Docker(Ubuntu 패키지) · Caddy(공식 저장소).
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
echo "== 패키지 설치"
apt-get -o DPkg::Lock::Timeout=300 update -qq
apt-get -o DPkg::Lock::Timeout=300 install -y -qq curl ca-certificates gnupg jq zstd rsync git unzip openssl python3 sqlite3 tmux acl iproute2 dnsutils openssh-server debian-keyring debian-archive-keyring apt-transport-https qrencode >/dev/null
echo "성공: 기본 도구"
if ! command -v docker >/dev/null 2>&1; then
  apt-get install -y -qq docker.io docker-compose-v2 docker-buildx >/dev/null 2>&1 || apt-get install -y -qq docker.io docker-compose-v2 >/dev/null
fi
systemctl enable --now docker >/dev/null 2>&1
docker buildx version >/dev/null 2>&1 || apt-get install -y -qq docker-buildx >/dev/null 2>&1 || true   # 이미 Docker 가 깔려 있던 서버에도 buildx(이미지 빌드용)를 보장
docker compose version >/dev/null 2>&1 || apt-get install -y -qq docker-compose-v2 >/dev/null 2>&1 || true
docker compose version >/dev/null 2>&1 || { echo "실패: docker compose 플러그인이 없습니다"; exit 1; }
echo "성공: Docker $(docker --version | cut -d' ' -f3 | tr -d ,) · $(docker compose version --short)"
getent group docker >/dev/null && usermod -aG docker "$ADMIN_USER" && echo "성공: $ADMIN_USER → docker 그룹"
if ! command -v caddy >/dev/null 2>&1; then
  install -d -m 0755 /usr/share/keyrings
  curl -fsSL https://dl.cloudsmith.io/public/caddy/stable/gpg.key | gpg --dearmor --yes -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
  curl -fsSL https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt -o /etc/apt/sources.list.d/caddy-stable.list
  apt-get -o DPkg::Lock::Timeout=300 update -qq; apt-get install -y -qq caddy >/dev/null
fi
echo "성공: Caddy $(caddy version | cut -d' ' -f1)"
echo "결과: 통과"
