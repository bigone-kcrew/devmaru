# mig-common.sh — devmaru-migrate-live 도구들이 같이 읽는 설정·공통 함수. 직접 실행하지 않는다(각 도구가 source).
# 설정: migrate.conf(KEY=값, 셸로 실행하지 않고 허용된 키만 읽는다) · migrate-groups.conf(전송 그룹).
# 위치: 이 디렉터리, 또는 MIG_CONF · MIG_GROUPS 환경변수. 예시는 *.example 을 복사해 고친다.
MIG_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# --help / -h: 각 도구 머리말(사용법)을 보여 주고 끝낸다(source 는 호출한 도구의 인자를 그대로 본다)
case "${1:-}" in -h|--help) sed -n '2,/^set -uo/p' "$0" | grep '^#' | sed 's/^# \{0,1\}//'; exit 0;; esac
say(){ printf '%s\n' "$*"; }; warn(){ printf '경고: %s\n' "$*" >&2; }; fail(){ printf '실패: %s\n' "$*" >&2; exit 1; }

# 기본값(설정 파일이 덮어쓴다)
PFX=devmaru; NEW_HOST=""; NEW_HOSTNAME=""; RUSER=""; SSH_PORT=22
SSH_KEY=/root/.ssh/migrate_ed25519; SSH_KNOWN_HOSTS=/root/.ssh/known_hosts_migrate
REMOTE_RSYNC="sudo -n /usr/bin/rsync"; BWLIMIT=0; LOG_DIR=""; MEMBERS=""; EXTRA_PROC_PATTERNS=""

load_conf(){
  local f=${MIG_CONF:-$MIG_DIR/migrate.conf} k v
  [ -f "$f" ] || fail "설정 파일이 없다: $f (migrate.conf.example 을 복사해 고치세요)"
  while IFS= read -r line || [ -n "$line" ]; do
    line=${line%%#*}; [[ "$line" =~ ^[[:space:]]*$ ]] && continue
    [[ "$line" =~ ^[[:space:]]*([A-Z_]+)=(.*)$ ]] || fail "설정 형식 오류(KEY=값): $line"
    k=${BASH_REMATCH[1]}; v=${BASH_REMATCH[2]}; v=${v%"${v##*[![:space:]]}"}; v=${v#\"}; v=${v%\"}
    case "$k" in
      PFX|NEW_HOST|NEW_HOSTNAME|RUSER|SSH_PORT|SSH_KEY|SSH_KNOWN_HOSTS|REMOTE_RSYNC|BWLIMIT|LOG_DIR|MEMBERS|EXTRA_PROC_PATTERNS) printf -v "$k" '%s' "$v";;
      *) fail "알 수 없는 설정 키: $k";;
    esac
  done < "$f"
  [[ "$PFX" =~ ^[a-z][a-z0-9-]{1,20}$ ]] || fail "PFX 형식 오류: $PFX"
  case "$SSH_PORT$BWLIMIT" in *[!0-9]*) fail "SSH_PORT·BWLIMIT 는 숫자";; esac
  LOG_DIR=${LOG_DIR:-/var/log/$PFX-migrate-live}
  RSH="ssh -p $SSH_PORT -i $SSH_KEY -o IdentitiesOnly=yes -o BatchMode=yes -o UserKnownHostsFile=$SSH_KNOWN_HOSTS -o StrictHostKeyChecking=yes"
}
need_remote(){ [ -n "$NEW_HOST" ] && [ -n "$NEW_HOSTNAME" ] && [ -n "$RUSER" ] || fail "migrate.conf 에 NEW_HOST·NEW_HOSTNAME·RUSER 가 필요하다"; }
remote(){ $RSH "$RUSER@$NEW_HOST" "$1"; }
need_root(){ [ "$(id -u)" = 0 ] || [ "${MIG_TEST:-}" = 1 ] || fail "root 로 실행하세요(sudo bash $0 …)"; }
# 방향 확인: 잘못된 서버로 보내거나, 신 서버에서 거꾸로 보내는 사고를 막는다
guard_direction(){
  need_remote; local rh
  rh=$(remote hostname 2>/dev/null) || fail "신 서버 접속 실패($RUSER@$NEW_HOST) — 키·known_hosts 확인"
  [ "$rh" = "$NEW_HOSTNAME" ] || fail "대상 호스트명이 $NEW_HOSTNAME 이 아니다($rh) — 중단"
  [ "$(hostname)" != "$NEW_HOSTNAME" ] || fail "구 서버에서 실행해야 한다(이 서버가 $NEW_HOSTNAME)"
}
# 확인 문구: 비대화형에서 --yes 없이 쓰면 거부된다
confirm(){ local want=$1 got; printf '계속하려면 «%s» 를 그대로 입력하세요: ' "$want" >&2; read -r got || got=""; [ "$got" = "$want" ] || fail "확인 문구가 다르다 — 중단"; }

# 그룹 파일: 이름 | 종류(live|stop|conf) | 원본(공백 구분) | 옵션(exclude= include= usermap= groupmap=) | 설명
# 원본의 {PFX} 는 접두어로 바뀐다. MIG_ROOT(시험용)가 있으면 로컬 원본 경로 앞에 붙는다.
groups_file(){ local f=${MIG_GROUPS:-$MIG_DIR/migrate-groups.conf}; [ -f "$f" ] || fail "그룹 파일이 없다: $f (migrate-groups.conf.example 을 복사)"; echo "$f"; }
trim(){ local s=$1; s=${s#"${s%%[![:space:]]*}"}; s=${s%"${s##*[![:space:]]}"}; printf '%s' "$s"; }
group_names(){ local f; f=$(groups_file) || exit 1; grep -vE '^[[:space:]]*(#|$)' "$f" | cut -d'|' -f1 | while read -r n; do trim "$n"; echo; done; }
# load_group <이름> → G_TYPE G_SRCS(배열) G_EXC G_INC G_UMAP G_GMAP(배열) G_NOTE
load_group(){
  local f line n o s; f=$(groups_file) || exit 1
  line=$(grep -vE '^[[:space:]]*(#|$)' "$f" | awk -F'|' -v g="$1" '{n=$1; gsub(/^[ \t]+|[ \t]+$/,"",n); if(n==g){print; exit}}')
  [ -n "$line" ] || return 1
  IFS='|' read -r n G_TYPE s o G_NOTE <<< "$line"
  G_TYPE=$(trim "$G_TYPE"); G_NOTE=$(trim "$G_NOTE"); s=${s//\{PFX\}/$PFX}
  case "$G_TYPE" in live|stop|conf) ;; *) fail "그룹 $1 의 종류가 잘못됐다: $G_TYPE (live|stop|conf)";; esac
  read -r -a G_SRCS <<< "$s"; G_EXC=("lost+found" "*.sock" "*.pid"); G_INC=(); G_UMAP=(); G_GMAP=()
  local toks t; read -r -a toks <<< "$o"   # read 는 글로브를 펼치지 않는다(exclude=/*/tmp/* 보호)
  for t in "${toks[@]}"; do case "$t" in
    exclude=*) G_EXC+=("${t#exclude=}");; include=*) G_INC+=("${t#include=}");;
    usermap=*) G_UMAP+=("${t#usermap=}");; groupmap=*) G_GMAP+=("${t#groupmap=}");;
    *) fail "그룹 $1 의 옵션을 모르겠다: $t";; esac; done
  [ ${#G_SRCS[@]} -gt 0 ] || fail "그룹 $1 에 원본이 없다"
}
