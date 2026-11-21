#!/usr/bin/env bash
# 서비스 기동: 이미지 빌드 → compose up → 대기. 선택한 모듈만, modules.list 순서대로.
set -uo pipefail
O=/opt/$PFX; E=$O/config/env; bad=0
has(){ case " $DEVMARU_MODULES " in *" $1 "*) return 0;; esac; return 1; }
pass(){ echo "성공: $*"; }; fail(){ echo "실패: $*"; bad=1; }
wait_ctr(){ # <컨테이너> <초>
  local c=$1 t=$2 i st
  for ((i=0;i<t;i+=3)); do
    st=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$c" 2>/dev/null || echo none)
    case $st in healthy|running) return 0;; esac; sleep 3
  done; echo "  > $c 상태: $st"; return 1; }
echo "== 서비스 기동"
echo "  > postgres 이미지 빌드(pgvector · pg_bigm 컴파일, 몇 분 걸림)"
docker build -q -t "$PFX-postgres:18-pgvector087-bigm" "$O/images/postgres" >/dev/null && pass "이미지 $PFX-postgres:18-pgvector087-bigm" || { fail "postgres 이미지 빌드 실패"; echo "결과: 실패"; exit 1; }
while IFS='|' read -r name kind dir ctr secs req deps desc; do
  case "$name" in ''|\#*) continue;; esac
  [ "$kind" = compose ] || continue
  has "$name" || continue
  ctr=${ctr//@@PFX@@/$PFX}
  echo "  > $name 기동($desc)"
  if ( cd "$O/compose/$dir" && docker compose up -d --build 2>&1 | tail -3 ); then :; fi
  if wait_ctr "$ctr" "$secs"; then pass "$name ($ctr)"; else fail "$name 이 $secs 초 안에 올라오지 않음 — docker logs $ctr"; [ "$req" = 1 ] && { echo "결과: 실패"; exit 1; }; fi
  if [ "$name" = postgres ]; then
    # n8n 용 DB·역할(없을 때만)
    if has n8n; then
      . <(grep -E '^N8N_DB_(USER|PASSWORD|NAME)=' "$E/postgres.env")
      for i in 1 2 3 4 5 6; do docker exec postgres pg_isready -U postgres >/dev/null 2>&1 && break; sleep 3; done
      docker exec postgres psql -U postgres -tAc "select 1 from pg_roles where rolname='$N8N_DB_USER'" | grep -q 1 || docker exec postgres psql -U postgres -c "create role $N8N_DB_USER login password '$N8N_DB_PASSWORD'" >/dev/null
      docker exec postgres psql -U postgres -tAc "select 1 from pg_database where datname='$N8N_DB_NAME'" | grep -q 1 || docker exec postgres psql -U postgres -c "create database $N8N_DB_NAME owner $N8N_DB_USER" >/dev/null
      pass "n8n 용 DB·역할"
    fi
    docker exec postgres psql -U postgres -tAc "select string_agg(extname,',') from pg_extension" >/dev/null
    docker exec postgres psql -U postgres -d postgres -c "create extension if not exists vector" -c "create extension if not exists pg_bigm" >/dev/null 2>&1 && pass "확장 vector · pg_bigm" || fail "확장 생성 실패(vector · pg_bigm)"
  fi
done < "$KIT/config/modules.list"
[ "$bad" = 0 ] && echo "결과: 통과" || { echo "결과: 실패"; exit 1; }
