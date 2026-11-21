#!/usr/bin/env bash
# 파일 서비스(SFTPGo) 연동: 멤버 저장소 등록 도구가 쓰는 API 키와 공용 폴더(Shared)를 만든다.
set -uo pipefail
case " $DEVMARU_MODULES " in *" files "*) ;; *) echo "안내: files 모듈을 선택하지 않아 건너뜀"; echo "결과: 통과"; exit 0;; esac
O=/opt/$PFX; KEYF=/etc/$PFX/secrets/sftpgo-provisioner-api-key; API=http://127.0.0.1:8080/api/v2
echo "== 파일 서비스 연동"
if [ -s "$KEYF" ]; then echo "안내: API 키가 이미 있음 — $KEYF"; echo "결과: 통과"; exit 0; fi
. <(grep '^SFTPGO_ADMIN_PASSWORD=' "$O/compose/sftpgo/.env")
for i in $(seq 1 20); do curl -fs -o /dev/null "http://127.0.0.1:8080/healthz" && break; sleep 3; done
TOK=$(curl -fs -u "admin:$SFTPGO_ADMIN_PASSWORD" "$API/token" | jq -r .access_token 2>/dev/null)
[ -n "$TOK" ] && [ "$TOK" != null ] || { echo "실패: SFTPGo 관리자 로그인 실패(초기 관리자가 만들어지지 않았다면 데이터 폴더를 확인)"; echo "결과: 실패"; exit 1; }
H=(-H "Authorization: Bearer $TOK" -H 'Content-Type: application/json')
curl -fs "${H[@]}" "$API/folders/Shared" >/dev/null 2>&1 || curl -fs "${H[@]}" -X POST "$API/folders" -d '{"name":"Shared","mapped_path":"/srv/shared"}' >/dev/null \
  && echo "성공: 공용 폴더 Shared" || { echo "실패: Shared 폴더 생성 실패"; exit 1; }
# 관리자 계정이 API 키 인증을 쓰도록 허용(기본은 꺼짐)
curl -fs "${H[@]}" "$API/admins/admin" | jq '.filters.allow_api_key_auth=true' | curl -fs "${H[@]}" -X PUT "$API/admins/admin" -d @- >/dev/null \
  && echo "성공: 관리자 API 키 인증 허용" || { echo "실패: 관리자 설정 변경 실패"; echo "결과: 실패"; exit 1; }
KEY=$(curl -fs "${H[@]}" -X POST "$API/apikeys" -d '{"name":"provisioner","scope":1,"admin":"admin"}' | jq -r .key 2>/dev/null)
[ -n "$KEY" ] && [ "$KEY" != null ] || { echo "실패: API 키 생성 실패"; echo "결과: 실패"; exit 1; }
curl -fs -o /dev/null -H "X-SFTPGO-API-KEY: $KEY" "$API/users" || { echo "실패: 만든 API 키로 호출이 되지 않음"; echo "결과: 실패"; exit 1; }
install -d -m 0700 "/etc/$PFX/secrets"; umask 077; printf '%s' "$KEY" > "$KEYF"; chmod 0600 "$KEYF"
echo "성공: 멤버 저장소 등록용 API 키 → $KEYF"
echo "결과: 통과"
