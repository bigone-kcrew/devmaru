#!/usr/bin/env bash
# mig-accounts.sh — 회원 리눅스 계정(UID/GID/추가 그룹 · /etc/subuid·subgid 범위)과 비밀번호 해시 이관. root 로 실행.
#   (구 서버) sudo bash mig-accounts.sh export [--users alice,bob]   → /root/<접두어>-migrate-accounts/{manifest.tsv,hashes.txt} (700·600)
#   (전송)    sudo bash mig-rsync.sh accounts --apply                   (migrate-groups.conf 의 accounts 그룹)
#   (신 서버) sudo bash mig-accounts.sh import [--apply]               기본은 계획. --apply: 없는 계정을 같은 번호로 만들고 해시를 넣은 뒤 지문으로 검증
#   (양쪽)    sudo bash mig-accounts.sh cleanup                         해시 파일 삭제(shred)
# 대상: --users 또는 migrate.conf 의 MEMBERS. 해시는 화면에 출력하지 않고 sha256 지문 12자만 보여 준다.
# 이미 있는 계정의 UID/GID 나 subuid 범위가 다르면 바꾸지 않고 «불일치» 로 멈춘다(파일 소유권·루트리스 도커가 어긋난다 — 사람이 판단).
set -uo pipefail
. "$(cd "$(dirname "$0")" && pwd)/mig-common.sh"
fp(){ printf '%s' "$1" | sha256sum | cut -c1-12; }
sub(){ awk -F: -v u="$1" '$1==u{print $2":"$3; exit}' "${MIG_ROOT:-}/etc/$2" 2>/dev/null; }   # subuid|subgid → 시작:개수
run(){
load_conf; DIR=${MIG_ACC_DIR:-/root/$PFX-migrate-accounts}
CMD=${1:-}; shift || true; APPLY=0; USERS=$MEMBERS
while [ $# -gt 0 ]; do case "$1" in --apply) APPLY=1;; --users) USERS=${2:-}; USERS=${USERS//,/ }; shift;; *) fail "알 수 없는 옵션: $1";; esac; shift; done
case "$CMD" in export|import|cleanup) ;; *) fail "사용법: $0 export [--users a,b] | import [--apply] | cleanup";; esac
need_root; umask 077
case "$CMD" in
export)
  [ -n "$USERS" ] || fail "대상 회원이 없다 — --users a,b 또는 migrate.conf MEMBERS"
  [ "$(hostname)" != "$NEW_HOSTNAME" ] || fail "export 는 구 서버에서 한다"
  mkdir -p "$DIR" && chmod 700 "$DIR"; : > "$DIR/manifest.tsv"; : > "$DIR/hashes.txt"; chmod 600 "$DIR"/*
  say "== export → $DIR (해시는 출력하지 않는다)"
  for u in $USERS; do
    pw=$(getent passwd "$u") || fail "계정 없음: $u"; IFS=: read -r _ _ uid gid _ home shell <<< "$pw"
    pg=$(getent group "$gid" | cut -d: -f1); supp=$(id -nG "$u" | tr ' ' '\n' | grep -vx "$pg" | paste -sd, -)
    h=$(getent shadow "$u" | cut -d: -f2); [ -n "$h" ] || fail "shadow 항목을 읽지 못했다: $u"
    su=$(sub "$u" subuid); sg=$(sub "$u" subgid)
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$u" "$uid" "$gid" "$pg" "${supp:--}" "$home" "$shell" "$(fp "$h")" "${su:--}" "${sg:--}" >> "$DIR/manifest.tsv"
    printf '%s:%s\n' "$u" "$h" >> "$DIR/hashes.txt"
    case "$h" in '!'*|'*'*) st="잠김";; \$*) st="해시 \$$(printf '%s' "$h" | cut -d'$' -f2)\$";; *) st="형식 확인 필요";; esac
    say "  $u uid=$uid gid=$gid($pg) 추가그룹=${supp:-없음} subuid=${su:-없음} · $st · 지문 $(fp "$h")"
  done
  say "다음: sudo bash mig-rsync.sh accounts --apply → 신 서버에서 import";;
import)
  [ "$(hostname)" = "$NEW_HOSTNAME" ] || [ "${MIG_TEST:-}" = 1 ] || fail "import 는 신 서버($NEW_HOSTNAME)에서 한다"
  [ -s "$DIR/manifest.tsv" ] && [ -s "$DIR/hashes.txt" ] || fail "$DIR 에 manifest.tsv·hashes.txt 가 없다 — export·전송 먼저"
  say "== import $([ $APPLY = 1 ] && echo 적용 || echo '계획(쓰지 않음)')"; bad=0
  while IFS=$'\t' read -r u uid gid pg supp home shell efp su sg; do
    [ "$supp" = - ] && supp=""; h=$(grep -m1 "^$u:" "$DIR/hashes.txt" | cut -d: -f2-)
    [ -n "$h" ] && [ "$(fp "$h")" = "$efp" ] || { say "  해시 없음·전송 중 변경: $u"; bad=1; continue; }
    if cur=$(getent passwd "$u"); then IFS=: read -r _ _ cuid cgid _ <<< "$cur"
      [ "$cuid" = "$uid" ] && [ "$cgid" = "$gid" ] || { say "  UID/GID 불일치: $u (구 $uid/$gid · 신 $cuid/$cgid) — 손대지 않음"; bad=1; continue; }
      act="계정 있음"
    else
      o=$(getent passwd "$uid" | cut -d: -f1); [ -z "$o" ] || { say "  uid $uid 를 신 서버의 다른 계정($o)이 쓴다: $u — 손대지 않음"; bad=1; continue; }
      act="계정 생성 예정(uid=$uid gid=$gid 추가그룹=${supp:-없음})"; fi
    for k in subuid subgid; do want=$([ $k = subuid ] && echo "$su" || echo "$sg"); [ "$want" = - ] && continue; now=$(sub "$u" $k)
      [ -z "$now" ] || [ "$now" = "$want" ] || { say "  $k 불일치: $u (구 $want · 신 $now) — 루트리스 도커 파일 소유가 어긋난다. 손대지 않음"; bad=1; continue 2; }; done
    if [ $APPLY = 0 ]; then say "  $u: $act · 해시 $(case "$h" in '!'*|'*'*) echo '잠김(설정 안 함)';; *) echo "설정 예정(지문 $efp)";; esac)"; continue; fi
    if ! getent passwd "$u" >/dev/null; then
      getent group "$gid" >/dev/null || groupadd -g "$gid" "$pg" || { say "  groupadd 실패: $pg"; bad=1; continue; }
      useradd -M -u "$uid" -g "$gid" -d "$home" -s "$shell" ${supp:+-G "$supp"} "$u" || { say "  useradd 실패: $u"; bad=1; continue; }
    fi
    [ "$su" = - ] || [ -n "$(sub "$u" subuid)" ] || usermod --add-subuids "${su%%:*}-$(( ${su%%:*} + ${su##*:} - 1 ))" "$u" || { say "  subuid 설정 실패: $u"; bad=1; }
    [ "$sg" = - ] || [ -n "$(sub "$u" subgid)" ] || usermod --add-subgids "${sg%%:*}-$(( ${sg%%:*} + ${sg##*:} - 1 ))" "$u" || { say "  subgid 설정 실패: $u"; bad=1; }
    case "$h" in '!'*|'*'*) say "  $u: $act · 구 서버도 잠김 — 해시 설정 안 함"; continue;; esac
    printf '%s:%s\n' "$u" "$h" | chpasswd -e || { say "  chpasswd 실패: $u"; bad=1; continue; }
    [ "$(fp "$(getent shadow "$u" | cut -d: -f2)")" = "$efp" ] && say "  OK $u: 지문 일치($efp)" || { say "  지문 불일치: $u"; bad=1; }
  done < "$DIR/manifest.tsv"
  [ $bad = 0 ] || fail "일부 항목 문제 — 위 줄 확인"
  say "완료.$([ $APPLY = 1 ] && echo " 끝나면 양쪽에서: sudo bash $0 cleanup" || echo " 적용: $0 import --apply")";;
cleanup)
  [ -d "$DIR" ] || { say "없음: $DIR"; return 0; }
  for f in hashes.txt manifest.tsv; do [ -f "$DIR/$f" ] && { shred -u "$DIR/$f" 2>/dev/null || rm -f "$DIR/$f"; }; done
  rmdir "$DIR" 2>/dev/null && say "삭제함: $DIR" || say "남은 파일이 있어 폴더는 유지: $DIR";;
esac
}
run "$@"; exit $?
