# @@PFX@@-access-lib.sh — 접근 정책을 ACL 로 옮기는 함수 모음(source 용). @@PFX@@-user-add · @@PFX@@-access 가 쓴다.
#   WORKSPACE_OTHERS=none|read  다른 회원이 내 workspace 를 읽을 수 있나(쓰기는 항상 불가)
#   SHARED_DEFAULT=rw|ro        공유 프로젝트에서 회원 전원의 기본 권한(ro 면 쓰기는 만든 사람·관리자만)
# 정책 값은 /etc/@@PFX@@/site.env 에 있고, 실제 권한은 폴더 ACL 이다. 새 프로젝트는 상위 폴더의 default 그룹 권한을 따른다.
ACC_SITE=/etc/@@PFX@@/site.env

acc_load() {
  local k v
  WORKSPACE_OTHERS=none; SHARED_DEFAULT=rw; ADMIN_USER=@@ADMIN_USER@@
  if [[ -r $ACC_SITE ]]; then
    while IFS='=' read -r k v; do v=${v//\'/}; v=${v//\"/}; printf -v "$k" '%s' "$v"
    done < <(grep -E '^(WORKSPACE_OTHERS|SHARED_DEFAULT|ADMIN_USER)=' "$ACC_SITE")
  fi
  case $WORKSPACE_OTHERS in none|read) ;; *) WORKSPACE_OTHERS=none;; esac
  case $SHARED_DEFAULT in rw|ro) ;; *) SHARED_DEFAULT=rw;; esac
  ACC_USERS=${USER_ROOT_BASE:-/srv/@@PFX@@/users}; ACC_SHARED=${SHARED_PATH:-/srv/@@PFX@@/shared}; ACC_GROUP=@@PFX@@
  ACC_ADMIN_UID=$(id -u "$ADMIN_USER" 2>/dev/null || true)
}

# 계획 모드(ACC_PLAN=1)에서는 명령을 실행하지 않고 보여 준다
acc_run() { if [[ ${ACC_PLAN:-0} = 1 ]]; then echo "  [계획] $*"; else "$@"; fi; }
acc_X() { echo "${1%x}X"; }          # rwx → rwX, r-x → r-X, --- → ---

acc_members() {   # 계정이 있는 회원 ID 목록
  local d u
  for d in "$ACC_USERS"/*/; do u=${d%/}; u=${u##*/}; id "$u" >/dev/null 2>&1 && echo "$u"; done
}

# 컨테이너 안(회원 계정)에서 다른 회원 이름→uid 를 알 수 있게 공유 폴더에 읽기 전용 목록을 둔다
acc_members_map() {
  local m="$ACC_SHARED/.access" u
  [[ ${ACC_PLAN:-0} = 1 ]] && { echo "  [계획] $m/members.map 갱신"; return 0; }
  install -d -o root -g root -m 0755 "$m"
  { for u in $(acc_members); do echo "$u $(id -u "$u")"; done; [[ -n ${ACC_ADMIN_UID:-} ]] && echo "@admin $ACC_ADMIN_UID"; true; } > "$m/members.map.new" && chmod 0644 "$m/members.map.new" && mv -f "$m/members.map.new" "$m/members.map"
}

# 프로젝트 폴더(작업공간·공유 최상위 아래 한 단계)에 그룹 권한을 적용. kind=personal|shared (관리자 쓰기 ACL 은 shared 에만)
acc_projects() {  # <상위폴더> <그룹권한> <default 그룹권한> <kind>
  local dir=$1 g=$2 dg=$3 kind=$4 c adm=""
  [[ $kind = shared && -n ${ACC_ADMIN_UID:-} ]] && adm=",u:$ACC_ADMIN_UID:rwx,d:u:$ACC_ADMIN_UID:rwx"
  [[ -d $dir ]] || return 0
  while IFS= read -r c; do
    if [[ $kind = shared && -e $c/.@@PFX@@-access ]]; then echo "  건너뜀(프로젝트별 정책): ${c##*/}"; continue; fi
    acc_run setfacl -m "g::$g,d:g::$dg$adm,m::rwx,d:m::rwx" "$c"
  done < <(find "$dir" -mindepth 1 -maxdepth 1 -type d)
}

# 전체 재귀(--full): .private 와 프로젝트별 정책 파일은 건드리지 않는다. 무거우므로 낮은 우선순위로 실행
acc_tree() {  # <폴더> <그룹권한> <default 그룹권한> <kind>
  local dir=$1 g=$2 dg=$3 kind=$4 gx admd="" admf=""
  gx=$(acc_X "$g")
  [[ $kind = shared && -n ${ACC_ADMIN_UID:-} ]] && { admd=",u:$ACC_ADMIN_UID:rwx,d:u:$ACC_ADMIN_UID:rwx"; admf=",u:$ACC_ADMIN_UID:rwX"; }
  [[ -d $dir ]] || return 0
  acc_run ionice -c3 nice -n 19 find "$dir" \( -name .private -o -name ".@@PFX@@-access" \) -prune -o -type d -exec setfacl -m "g::$g,d:g::$dg$admd" {} +
  acc_run ionice -c3 nice -n 19 find "$dir" \( -name .private -o -name ".@@PFX@@-access" \) -prune -o -type f -exec setfacl -m "g::$gx$admf" {} +
}

# 회원 한 명: users/<id>(루트)와 workspace 의 접근 ACL 을 정책에 맞춘다
acc_member() {  # <회원> [full=0|1]
  local u=$1 full=${2:-0} root="$ACC_USERS/$1" ws="$ACC_USERS/$1/workspace" top dtop g dg
  [[ -d $root && -d $ws ]] || { echo "  건너뜀: $u (폴더 없음)"; return 0; }
  if [[ $WORKSPACE_OTHERS = read ]]; then top='--x'; dtop='---'; g='r-x'; dg='r-x'; else top='---'; dtop='r-x'; g='---'; dg='---'; fi
  acc_run setfacl -m "u::rwx,u:1000:rwx,u:$u:rwx,g::$top,m::rwx,o::---" -m "d:u::rwx,d:u:1000:rwx,d:u:$u:rwx,d:g::$dtop,d:m::rwx,d:o::---" "$root"
  acc_run setfacl -m "u::rwx,u:1000:rwx,u:$u:rwx,g::$g,m::rwx,o::---" -m "d:u::rwx,d:u:1000:rwx,d:u:$u:rwx,d:g::$dg,d:m::rwx,d:o::---" "$ws"
  # 읽기 허용 시에도 workspace 밖(agent-config·tmp 등)은 닫아 둔다(최상위만)
  [[ $WORKSPACE_OTHERS = read ]] && acc_run find "$root" -mindepth 1 -maxdepth 1 ! -name workspace -exec setfacl -m g::--- {} +
  acc_projects "$ws" "$g" "$dg" personal
  [[ $full = 1 ]] && acc_tree "$ws" "$g" "$dg" personal
  return 0
}

# 공유 공간: /shared 루트(새 항목은 못 만든다: ro) · /shared/workspaces(프로젝트는 만들 수 있다, 남의 것은 못 지움)
acc_shared() {  # [full=0|1]
  local full=${1:-0} sh=$ACC_SHARED ws=$ACC_SHARED/workspaces g dg mode
  if [[ $SHARED_DEFAULT = rw ]]; then g='rwx'; dg='rwx'; mode=3775; else g='rwx'; dg='r-x'; mode=3755; fi
  acc_run install -d -o root -g "$ACC_GROUP" -m "$mode" "$sh"
  acc_run install -d -o root -g "$ACC_GROUP" -m 3775 "$ws"
  acc_run setfacl -m "g::rwx,m::rwx,d:g::$dg,d:m::rwx,d:o::---${ACC_ADMIN_UID:+,u:$ACC_ADMIN_UID:rwx,d:u:$ACC_ADMIN_UID:rwx}" "$ws"
  acc_projects "$ws" "$dg" "$dg" shared
  [[ $full = 1 ]] && acc_tree "$ws" "$dg" "$dg" shared
  return 0
}

# 파일 서비스(SFTPGo): ro 면 /shared 는 목록·내려받기만. 서비스·API 키가 없으면 건너뛴다
acc_sftpgo() {  # <회원>
  local key=/etc/@@PFX@@/secrets/sftpgo-provisioner-api-key api=http://127.0.0.1:8080/api/v2 body code
  [[ -r $key ]] && command -v jq >/dev/null 2>&1 || return 0
  body=$(curl -s -m 10 -H "X-SFTPGO-API-KEY: $(cat "$key")" "$api/users/$1") || return 0
  jq -e .username >/dev/null 2>&1 <<<"$body" || return 0
  if [[ $SHARED_DEFAULT = ro ]]; then body=$(jq -c '.permissions["/shared"]=["list","download"]' <<<"$body")
  else body=$(jq -c 'del(.permissions["/shared"])' <<<"$body"); fi
  if [[ ${ACC_PLAN:-0} = 1 ]]; then echo "  [계획] SFTPGo 사용자 $1 권한 갱신(/shared: $SHARED_DEFAULT)"; return 0; fi
  code=$(curl -s -m 10 -o /dev/null -w '%{http_code}' -X PUT -H "X-SFTPGO-API-KEY: $(cat "$key")" -H 'Content-Type: application/json' -d "$body" "$api/users/$1")
  [[ $code = 200 ]] || echo "  경고: SFTPGo 사용자 $1 권한 갱신 실패(HTTP $code)"
}

# Samba [shared]: ro 면 read only = yes + 관리자만 쓰기. smb 모듈이 없으면 건너뛴다
acc_samba() {
  local c=/srv/@@PFX@@/samba/smb.conf ro=no
  [[ -f $c ]] || return 0
  [[ $SHARED_DEFAULT = ro ]] && ro=yes
  if [[ ${ACC_PLAN:-0} = 1 ]]; then echo "  [계획] Samba [shared] read only = $ro"; return 0; fi
  awk -v ro="$ro" -v adm="$ADMIN_USER" '
    /^\[/ {sec=$0}
    sec=="[shared]" && /^[ \t]*write list[ \t]*=/ {next}
    sec=="[shared]" && /^[ \t]*read only[ \t]*=/ {print "    read only = " ro; if (ro=="yes") print "    write list = " adm; next}
    {print}' "$c" > "$c.new" && install -m "$(stat -c %a "$c")" "$c.new" "$c" && rm -f "$c.new"
  command -v smbcontrol >/dev/null 2>&1 && smbcontrol all reload-config >/dev/null 2>&1 || true
}
