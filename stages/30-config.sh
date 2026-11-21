#!/usr/bin/env bash
# 설정·비밀: env 파일을 만든다. 이미 있는 파일은 그대로 둔다(재실행해도 비밀이 바뀌지 않는다).
set -euo pipefail
O=/opt/$PFX; S=/srv/$PFX; E=$O/config/env
gen(){ openssl rand -hex 24; }
has(){ case " $DEVMARU_MODULES " in *" $1 "*) return 0;; esac; return 1; }
mk(){ # <경로> ; 내용은 stdin. 이미 있으면 건드리지 않는다
  if [ -s "$1" ]; then echo "안내: 유지 $1"; cat >/dev/null; else cat > "$1"; chmod 0600 "$1"; echo "성공: 생성 $1"; fi; }
echo "== 설정·비밀 생성"
install -d -m 0700 "$E"
mk "$E/postgres.env" <<X
POSTGRES_USER=postgres
POSTGRES_PASSWORD=$(gen)
POSTGRES_DB=postgres
TZ=$TZ
N8N_DB_USER=n8n
N8N_DB_PASSWORD=$(gen)
N8N_DB_NAME=n8n
X
if has n8n; then mk "$E/n8n.env" <<X
DB_TYPE=postgresdb
DB_POSTGRESDB_HOST=postgres
DB_POSTGRESDB_PORT=5432
DB_POSTGRESDB_DATABASE=n8n
DB_POSTGRESDB_USER=n8n
DB_POSTGRESDB_PASSWORD=$(grep '^N8N_DB_PASSWORD=' "$E/postgres.env" | cut -d= -f2-)
N8N_HOST=$N8N_HOST
N8N_PORT=5678
N8N_PROTOCOL=https
N8N_EDITOR_BASE_URL=https://$N8N_HOST/
N8N_ENCRYPTION_KEY=$(gen)
GENERIC_TIMEZONE=$TZ
TZ=$TZ
N8N_RESTRICT_FILE_ACCESS_TO=$S/onboarding
N8N_PROXY_HOPS=1
N8N_WEBHOOK_URL=https://$N8N_HOST/
N8N_UNVERIFIED_PACKAGES_ENABLED=false
N8N_RUNNERS_TASK_TIMEOUT=300
N8N_COMPRESSION_NODE_MAX_DECOMPRESSED_SIZE_BYTES=2147483648
N8N_COMPRESSION_NODE_MAX_ZIP_ENTRIES=5000
X
fi
if has kordoc; then mk "$E/kordoc.env" <<X
KORDOC_API_KEY=$(gen)
KORDOC_MAX_FILE_MB=300
KORDOC_TIMEOUT_MS=600000
KORDOC_CONCURRENCY=2
NODE_ENV=production
PORT=3400
X
fi
if has crawl4ai; then mk "$O/compose/crawl4ai/.env" <<X
CRAWL4AI_API_TOKEN=$(gen)
SECRET_KEY=$(gen)
X
fi
if has files; then mk "$O/compose/sftpgo/.env" <<X
SFTPGO_ADMIN_PASSWORD=$(gen)
X
fi
[ -e "$E/catalog-api.env" ] || { : > "$E/catalog-api.env"; chmod 0600 "$E/catalog-api.env"; echo "성공: 생성 $E/catalog-api.env (빈 파일 — 공공데이터 API 키가 있으면 DATA_GO_KR_API_KEY=… 를 넣는다)"; }
mk "$O/config/platform.env" <<X
POSTGRES_MAJOR=18
POSTGRES_IMAGE=$PFX-postgres:18-pgvector087-bigm
POSTGRES_REQUIRE_PGVECTOR=true
POSTGRES_REQUIRE_PG_BIGM=true
PGVECTOR_VERSION=0.8.6
PG_BIGM_VERSION=1.2
AI_DEV_NETWORK=$PFX-dev-net
AI_SERVICE_NETWORK=$PFX-service-net
AI_USER_ROOT=$S/users
AI_SHARED_ROOT=$S/shared
AI_SERVICE_ROOT=$S/services
X
chmod 0644 "$O/config/platform.env"
mk "$O/config/dev-container.env" <<X
GOLDEN_IMAGE=$PFX-dev:$(cat "$O/images/dev/GOLDEN_VERSION" 2>/dev/null || cat "$KIT/VERSION")
DEV_NETWORK=$PFX-dev-net
AI_GROUP=$PFX
USER_ROOT_BASE=$S/users
SHARED_PATH=$S/shared
TERM_DEFAULT=xterm-256color
SECCOMP_PROFILE=unconfined
APPARMOR_PROFILE=unconfined
UPDATE_EXCLUDE_USERS="$ADMIN_USER"
CATALOG_ENV_FILE=$E/catalog-api.env
DEV_MEMORY_LIMIT=4g
DEV_MEMORY_SWAP=4g
DEV_CPU_LIMIT=2
DEV_TZ=$TZ
DEV_TMP_ON_HDD=0
X
chmod 0644 "$O/config/dev-container.env"
# 서비스 데이터 디렉터리
install -d "$S/nvme/postgres/main"; has n8n && install -d -o 1000 -g 1000 "$S/services/n8n/data"
has files && install -d -o 1000 -g 1000 "$S/services/sftpgo/data"; has uptime-kuma && install -d "$S/services/uptime-kuma/data"
chown 999:999 "$S/nvme/postgres/main" 2>/dev/null || true
echo "결과: 통과"
