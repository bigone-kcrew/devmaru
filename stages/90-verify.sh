#!/usr/bin/env bash
set -uo pipefail
echo "== 최종 점검"
# 접근 정책을 모든 모듈(파일 서비스·SMB)에 맞춘다(멱등). 정책은 site.env 의 WORKSPACE_OTHERS · SHARED_DEFAULT
"/usr/local/sbin/$PFX-access" apply --all >/dev/null 2>&1 || echo "경고: 접근 정책 적용 실패 — sudo $PFX-access apply --all"
"/usr/local/sbin/$PFX-doctor"
