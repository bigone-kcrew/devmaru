#!/usr/bin/env bash
# devmaru 설치 부트스트랩: curl -fsSL <repo>/install.sh | sudo bash   (환경변수 DEVMARU_REF=<버전> 또는 DEVMARU_URL=<tarball 주소> 로 지정, DEVMARU_SOURCE=github|gitlab 로 배포처 선택(기본 github), 기본은 이 저장소의 패키지 레지스트리)
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
  REF="${DEVMARU_REF:-1.4.2}"
  # 배포처: github(기본) · gitlab — DEVMARU_SOURCE 로 고른다. DEVMARU_BASE(예전 방식, <기본주소>/<버전>/파일) 나 DEVMARU_URL 을 직접 지정하면 그대로 쓴다.
  if [ -n "${DEVMARU_BASE:-}" ]; then DEFAULT_URL="$DEVMARU_BASE/$REF/devmaru-kit-$REF.tar.gz"
  else
    case "${DEVMARU_SOURCE:-github}" in
      github) DEFAULT_URL="https://github.com/${DEVMARU_GH_REPO:-bigone-kcrew/devmaru}/releases/download/v$REF/devmaru-kit-$REF.tar.gz" ;;
      gitlab) DEFAULT_URL="https://gitlab.aigov.go.kr/api/v4/projects/bigone-kised%2Fdevmaru/packages/generic/devmaru-kit/$REF/devmaru-kit-$REF.tar.gz" ;;
      *) echo "실패: DEVMARU_SOURCE 는 github 또는 gitlab 이어야 합니다" >&2; exit 1 ;;
    esac
  fi
  DEVMARU_URL="${DEVMARU_URL:-$DEFAULT_URL}"
  T="$(mktemp -d)/devmaru-kit.tar.gz"
  command -v curl >/dev/null || { apt-get update -qq && apt-get install -y -qq curl ca-certificates; }
  curl -fsSL "$DEVMARU_URL" -o "$T"; curl -fsSL "$DEVMARU_URL.sha256" -o "$T.sha256"
  ( cd "$(dirname "$T")" && sed "s#  .*#  $(basename "$T")#" "$(basename "$T").sha256" | sha256sum -c - ) || { echo "실패: sha256 불일치" >&2; exit 1; }
fi
rm -rf "$DEST.new"; mkdir -p "$DEST.new"; tar -xzf "$T" -C "$DEST.new" --strip-components=1
[ -z "${DEVMARU_URL:-}" ] || echo "$DEVMARU_URL" > "$DEST.new/SOURCE_URL"
rm -rf "$DEST"; mv "$DEST.new" "$DEST"
exec python3 "$DEST/bin/devmaru-install" "$@"
