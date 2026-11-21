#!/usr/bin/env bash
# devmaru 설치 부트스트랩: curl -fsSL <repo>/install.sh | sudo bash   (환경변수 DEVMARU_REF=<버전> 또는 DEVMARU_URL=<tarball 주소> 로 지정, 기본은 이 저장소의 패키지 레지스트리)
# 하는 일: OS 확인 → 릴리스 tarball 받기 → sha256 검증 → /opt/devmaru-kit 에 풀기 → devmaru-install 실행.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "실패: root 로 실행하세요 (sudo bash)" >&2; exit 1; }
. /etc/os-release
[ "${ID:-}" = ubuntu ] && [ "${VERSION_ID:-}" = "26.04" ] || { echo "경고: Ubuntu 26.04 에서만 검증되었습니다(현재 ${PRETTY_NAME:-?})" >&2; [ "${DEVMARU_FORCE:-0}" = 1 ] || { echo "계속하려면 DEVMARU_FORCE=1" >&2; exit 1; }; }
[ "$(uname -m)" = x86_64 ] || { echo "실패: x86_64 만 지원합니다" >&2; exit 1; }
DEST=/opt/devmaru-kit
if [ -n "${DEVMARU_LOCAL:-}" ]; then            # 시험용: 이미 받은 tarball 경로
  T="$DEVMARU_LOCAL"
else
  REF="${DEVMARU_REF:-1.2.2}"
  BASE="${DEVMARU_BASE:-https://gitlab.aigov.go.kr/api/v4/projects/bigone-kised%2Fdevmaru/packages/generic/devmaru-kit}"
  DEVMARU_URL="${DEVMARU_URL:-$BASE/$REF/devmaru-kit-$REF.tar.gz}"
  T="$(mktemp -d)/devmaru-kit.tar.gz"
  command -v curl >/dev/null || { apt-get update -qq && apt-get install -y -qq curl ca-certificates; }
  curl -fsSL "$DEVMARU_URL" -o "$T"; curl -fsSL "$DEVMARU_URL.sha256" -o "$T.sha256"
  ( cd "$(dirname "$T")" && sed "s#  .*#  $(basename "$T")#" "$(basename "$T").sha256" | sha256sum -c - ) || { echo "실패: sha256 불일치" >&2; exit 1; }
fi
rm -rf "$DEST.new"; mkdir -p "$DEST.new"; tar -xzf "$T" -C "$DEST.new" --strip-components=1
[ -z "${DEVMARU_URL:-}" ] || echo "$DEVMARU_URL" > "$DEST.new/SOURCE_URL"
rm -rf "$DEST"; mv "$DEST.new" "$DEST"
exec python3 "$DEST/bin/devmaru-install" "$@"
