#!/usr/bin/env bash
# @@PFX@@-mask-lib.sh — 비밀 마스킹(값만 지우고 구조는 남긴다). source 해서 쓰는 라이브러리.
#   mask            표준 입력을 마스킹해 표준 출력으로(파이프용)
#   mask_selftest   가짜 토큰·비밀번호·링크가 모두 지워지는지 자체 시험(0 통과)
#   $HIGH           «강한 비밀 패턴» 정규식(마스킹 뒤 재검사용)
# 쓰는 곳: @@PFX@@-support-bundle · @@PFX@@-mask(명령) · 관리 콘솔/fleet 의 메시지 마스킹. 규칙을 고칠 때는 여기 한 곳만 고친다.
# ── 마스킹: 값만 지우고 구조(키 이름)는 남긴다 ──
HIGH='-----BEGIN [A-Z ]*PRIVATE KEY-----|gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,}|(^|[^A-Za-z0-9])sk-[A-Za-z0-9_-]{24,}|xox[baprs]-[A-Za-z0-9-]{10,}|AIza[0-9A-Za-z_-]{30,}|AKIA[0-9A-Z]{16}|eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{5,}|[0-9a-fA-F]{40,}|(offer|pairing)[=#][A-Za-z0-9_%.~+/=-]{16,}|[a-z]+://[^/[:space:]:@]+:[^/[:space:]@]+@'
mask(){ sed -E \
  -e 's/-----BEGIN [A-Z ]*PRIVATE KEY-----.*/[MASKED:private-key]/' \
  -e 's#([a-z]+://)[^/[:space:]:@]+:[^/[:space:]@]+@#\1[MASKED]@#g' \
  -e 's/gh[pousr]_[A-Za-z0-9]{30,}/[MASKED:token]/g; s/github_pat_[A-Za-z0-9_]{30,}/[MASKED:token]/g' \
  -e 's/(^|[^A-Za-z0-9])sk-[A-Za-z0-9_-]{24,}/\1[MASKED:token]/g; s/xox[baprs]-[A-Za-z0-9-]{10,}/[MASKED:token]/g' \
  -e 's/AIza[0-9A-Za-z_-]{30,}/[MASKED:token]/g; s/AKIA[0-9A-Z]{16}/[MASKED:token]/g' \
  -e 's/eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{5,}/[MASKED:jwt]/g' \
  -e 's/(offer|pairing)([=#])[A-Za-z0-9_%.~+\/=-]{16,}/\1\2[MASKED:link]/g' \
  -e 's/[0-9a-fA-F]{40,}/[MASKED:hex]/g' \
  -e 's/([Bb]earer|[Bb]asic)[[:space:]]+[A-Za-z0-9._~+\/=-]{8,}/\1 [MASKED]/g' \
  -e 's/([A-Za-z0-9_.-]*(PASS|PASSWORD|PASSWD|SECRET|TOKEN|KEY|CREDENTIAL|AUTH)[A-Za-z0-9_.-]*[[:space:]]*[=:][[:space:]]*)("[^"]*"|'"'"'[^'"'"']*'"'"'|[^[:space:],;"]+)/\1[MASKED]/Ig' \
  -e 's/[A-Za-z0-9._%+-]+@([A-Za-z0-9.-]+\.[A-Za-z]{2,})/[MASKED:email]@\1/g'; }

mask_selftest(){ local t r; t=$(mktemp); r=0
  { printf 'gh%s_%s\n' p "$(printf 'a%.0s' $(seq 36))"; printf 'sk-%s\n' "$(printf 'b%.0s' $(seq 30))"
    printf 'AKIA%s\n' "$(printf 'C%.0s' $(seq 16))"; printf 'eyJ%s.%s.%s\n' "$(printf 'd%.0s' $(seq 12))" "$(printf 'e%.0s' $(seq 12))" "$(printf 'f%.0s' $(seq 8))"
    echo 'POSTGRES_PASSWORD=hunter2-fake'; echo 'api_key: "fake-value-123"'; echo 'Authorization: Bearer abcdef1234567890xyz'
    echo 'url=postgres://user:fakepw@db:5432/x'; echo "link=https://app.example/#offer=$(printf 'g%.0s' $(seq 30))"
    echo "sha $(printf 'a1%.0s' $(seq 32))"; } > "$t"
  mask < "$t" > "$t.m"
  grep -qE -e "$HIGH" "$t.m" && { echo "실패: 마스킹 후에도 토큰 패턴이 남음"; r=1; }
  grep -qE 'hunter2-fake|fake-value-123|fakepw|abcdef1234567890xyz' "$t.m" && { echo "실패: 마스킹 후에도 가짜 비밀 값이 남음"; r=1; }
  grep -qE -e "$HIGH" "$t" || { echo "실패: 검사기 자체 시험(원본에서 패턴을 못 찾음)"; r=1; }
  rm -f "$t" "$t.m"; [ "$r" = 0 ] && echo "성공: 마스킹 자체 시험 통과(가짜 토큰·비밀번호·링크 모두 마스킹)"; return $r; }
