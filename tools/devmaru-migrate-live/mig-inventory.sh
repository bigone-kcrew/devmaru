#!/usr/bin/env bash
# mig-inventory.sh — 설치 키트가 «복제» 하지 못한 것을 찾는다: 구·신 서버의 파일·유닛 목록을 떠서 비교(읽기 전용, root 권장).
#   sudo bash mig-inventory.sh snapshot > old.inv     (구 서버) / > new.inv (신 서버). 비밀 내용은 담지 않는다(경로·종류만)
#   bash mig-inventory.sh diff old.inv new.inv        항목별로 «구 서버에만 있는 것» · «신 서버에만 있는 것»
# 목록: /usr/local/{bin,sbin,libexec}(종류 l=링크·f=파일 — 링크가 복사본이 되면 여기서 보인다) · /etc/systemd/system(유닛·*.d 드롭인·wants)
#   /etc/caddy(import 스니펫) · /etc/<접두어> · /opt/<접두어>(node_modules 유무 포함) · /var/lib/<접두어>(런타임 디렉터리) · cron · sudoers.d · 도커 네트워크
# snapshot 은 방화벽 규칙(nftables·/etc/<접두어>)이 이 서버에 없는 NIC 이름을 쓰면 경고한다(규칙이 조용히 아무것도 막지 못한다).
set -uo pipefail
. "$(cd "$(dirname "$0")" && pwd)/mig-common.sh"
ls_tree(){ local sec=$1 dir=${MIG_ROOT:-}$2; shift 2; [ -d "$dir" ] && find "$dir" -mindepth 1 "$@" -printf "$sec\t%y %P\n" 2>/dev/null; }
run(){
load_conf; CMD=${1:-}
case "$CMD" in
snapshot)
  for d in /usr/local/bin /usr/local/sbin /usr/local/libexec; do ls_tree "usr-local:${d##*/}" "$d" -maxdepth 2; done
  ls_tree systemd /etc/systemd/system -maxdepth 2
  ls_tree caddy /etc/caddy -maxdepth 3 -not -name '*.bak*'
  ls_tree "etc-$PFX" "/etc/$PFX" -maxdepth 3 -not -name '*.bak*'
  ls_tree "opt-$PFX" "/opt/$PFX" -maxdepth 3 -not -path '*/node_modules/*' -not -name '*.bak*'
  ls_tree "node_modules" "/opt/$PFX" -maxdepth 6 -type d -name node_modules -prune
  ls_tree "var-lib-$PFX" "/var/lib/$PFX" -maxdepth 2
  ls_tree cron.d /etc/cron.d -maxdepth 1; ls_tree crontabs /var/spool/cron/crontabs -maxdepth 1; ls_tree sudoers.d /etc/sudoers.d -maxdepth 1
  command -v docker >/dev/null && docker network ls --format '{{.Name}}' 2>/dev/null | sed 's/^/docker-net\t/'
  nics=$(ls "${MIG_ROOT:-}/sys/class/net" 2>/dev/null)
  for n in $(grep -rhoE 'i(if|of)name[[:space:]]+(\{[^}]*\}|"?[A-Za-z0-9_.-]+"?)' "${MIG_ROOT:-}/etc/nftables.conf" "${MIG_ROOT:-}/etc/nftables.d" "${MIG_ROOT:-}/etc/$PFX" 2>/dev/null \
             | sed -E 's/^i(if|of)name[[:space:]]+//; s/[{}",]/ /g' | tr ' ' '\n' | grep -E '^[A-Za-z][A-Za-z0-9_.-]*$' | sort -u); do
    case "$n" in lo|*'*'*) continue;; esac
    printf '%s\n' "$nics" | grep -qx "$n" || warn "방화벽 규칙의 NIC «$n» 이 이 서버에 없다(있는 NIC: $(echo $nics)) — 규칙을 고친 뒤 자동 해제 시한 시험부터"
  done;;
diff)
  [ -f "${2:-}" ] && [ -f "${3:-}" ] || fail "사용법: $0 diff <구.inv> <신.inv>"
  for sec in $(cut -f1 "$2" "$3" | sort -u); do
    o=$(comm -23 <(awk -F'\t' -v s="$sec" '$1==s{print $2}' "$2" | sort -u) <(awk -F'\t' -v s="$sec" '$1==s{print $2}' "$3" | sort -u))
    n=$(comm -13 <(awk -F'\t' -v s="$sec" '$1==s{print $2}' "$2" | sort -u) <(awk -F'\t' -v s="$sec" '$1==s{print $2}' "$3" | sort -u))
    [ -z "$o$n" ] && continue; say "== $sec"
    [ -z "$o" ] || printf '%s\n' "$o" | sed 's/^/  구에만  /'; [ -z "$n" ] || printf '%s\n' "$n" | sed 's/^/  신에만  /'
  done
  say "(«l 경로» 가 구에만, «f 같은 경로» 가 신에만 있으면 링크가 복사본으로 바뀐 것이다. 구에만 있는 항목은 하나씩 «옮길지·의도적으로 뺐는지» 정한다)";;
*) fail "사용법: $0 snapshot > 파일 | diff <구.inv> <신.inv>";;
esac
}
run "$@"; exit $?
