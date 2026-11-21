#!/usr/bin/env bash
# AI 에이전트 전용 계정(선택): SSH 키 전용 계정 · 제한된 sudo(읽기성 명령만) · 감사 로그. 키는 설치 뒤 관리자가 등록한다.
set -uo pipefail
case " $DEVMARU_MODULES " in *" agent "*) ;; *) echo "안내: agent 모듈을 선택하지 않아 건너뜀"; echo "결과: 통과"; exit 0;; esac
echo "== AI 에이전트 계정"
"/usr/local/sbin/$PFX-agent-setup" install ${AGENT_EXPIRES:+--expires "$AGENT_EXPIRES"} || { echo "결과: 실패"; exit 1; }
echo "안내: 공개키 등록 sudo $PFX-agent-key add <파일> · 기록 보기 sudo $PFX-agent-audit · 설명 docs/AGENT.md"
echo "결과: 통과"
