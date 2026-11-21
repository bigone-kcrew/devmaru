# 🧾 서드파티 구성요소

> 이 저장소에는 **우리가 만든 코드(MIT)** 만 들어 있습니다.
>
> 아래 구성요소는 **설치할 때 각 업스트림에서 내려받으며**, 저장소와 릴리스 파일에 포함하지 않습니다.
>
> 각 구성요소는 해당 프로젝트의 라이선스를 따릅니다.

> ⚠️ **라이선스 열은 «기록» 기준입니다**
>
> 아래 라이선스는 설치 환경에 남은 출처 기록을 따른 것입니다.
>
> 각 상류 저장소의 `LICENSE` 파일을 직접 대조하는 작업은 아직 끝나지 않았습니다(«확인» 열).

---

## 🧩 스킬 · 플러그인 (커밋·해시 고정)

| 구성요소 | 고정 | 라이선스(기록) | 확인 |
|---|---|---|---|
| [ponytail](https://github.com/DietrichGebert/ponytail) (스킬) | 커밋 `7801d06` · sha256 | MIT | 대조 필요 |
| [archify](https://github.com/tt-a1i/archify) (스킬) | v3.2.0 · sha256 | MIT | 대조 필요 |
| [effective-html](https://github.com/plannotator/effective-html) (스킬 7종) | 커밋 `975b047` | MIT | 대조 필요 |
| [ui-ux-pro-max](https://github.com/nextlevelbuilder/ui-ux-pro-max-skill) (스킬 7종) | 커밋 `d14efff` | MIT | 대조 필요 |
| [agent-browser](https://github.com/vercel-labs/agent-browser) | v0.41.0 · sha256 | Apache-2.0 | 대조 필요 |
| [superpowers](https://github.com/obra/superpowers) (플러그인) | v7.0.1 · 커밋 `2ce8aa1` | MIT | 대조 필요 |

---

## 🤖 에이전트 · 개발 도구

| 구성요소 | 고정 | 라이선스 | 비고 |
|---|---|---|---|
| [Claude Code](https://github.com/anthropics/claude-code) | 빌드 인자에 버전 고정 | 각 벤더 약관 | 설치 서버가 직접 받음(재배포 아님) |
| [Codex](https://github.com/openai/codex) | 〃 | 〃 | 〃 |
| [Paseo](https://github.com/getpaseo/paseo) | 〃 | 〃 | 〃 |
| [Antigravity](https://github.com/google-antigravity/antigravity-cli) | 〃 · sha256 | 〃 | 〃 |
| [Playwright](https://playwright.dev) · [gh](https://cli.github.com) · [glab](https://gitlab.com/gitlab-org/cli) · Node.js · bun · uv | 〃 | 각 라이선스 | 〃 |

---

## 🗄 서비스 · 인프라

| 구성요소 | 고정 | 라이선스 | 비고 |
|---|---|---|---|
| [PostgreSQL](https://www.postgresql.org) · [pgvector](https://github.com/pgvector/pgvector) · [pg_bigm](https://github.com/pgbigm/pg_bigm) | 이미지 · 소스 태그 | 각 라이선스 | 설치 서버에서 빌드 |
| [n8n](https://github.com/n8n-io/n8n) · [SFTPGo](https://github.com/drakkan/sftpgo) · [Uptime Kuma](https://github.com/louislam/uptime-kuma) · [Ollama](https://ollama.com) | 이미지 태그 | 각 라이선스 | 설치 서버가 직접 받음 |
| [Caddy](https://caddyserver.com) · [Docker](https://www.docker.com) · [Cockpit](https://cockpit-project.org) · [restic](https://restic.net) | 패키지 | 각 라이선스 | 설치 서버가 직접 받음 |

---

## 🗄 SMB over QUIC (선택 모듈 `smb`)

| 구성요소 | 고정 | 라이선스 | 비고 |
|---|---|---|---|
| [Samba](https://www.samba.org) (`samba` · `smbclient` · `tdb-tools` 패키지) | 배포판 패키지(4.23 계열) | GPL-3.0-or-later | 설치 서버가 직접 받음 |
| [lxin/quic](https://github.com/lxin/quic) 커널 모듈 | 커밋 `bf47121` | GPL-2.0-or-later | 설치할 때 받아 DKMS 로 빌드. 이 저장소에는 **호환 패치(`ubuntu-abi38.patch`, 3개 파일)** 만 있고 소스는 없음 |
| [DKMS](https://github.com/dell/dkms) · [certbot](https://certbot.eff.org) | 배포판 패키지 | GPL-2.0-or-later · Apache-2.0 | 설치 서버가 직접 받음(certbot 은 공인 인증서일 때만) |

---

## 📄 문서 변환 · 수집

| 구성요소 | 고정 | 라이선스 | 비고 |
|---|---|---|---|
| [Kordoc](https://github.com/chrisryugj/kordoc) | npm 버전 고정 | MIT(npm 기록) | HWP · HWPX 등 한글 문서 변환 |
| [MarkItDown](https://github.com/microsoft/markitdown) | PyPI 버전 고정 | 각 라이선스 | 문서 → Markdown |
| [Crawl4AI](https://github.com/unclecode/crawl4ai) | Docker 이미지 태그 | 각 라이선스 | 웹 수집 |
| [public-apis-4Kr](https://github.com/yybmion/public-apis-4Kr) | 설치 때 최신 목록 | 각 라이선스 | 공개 API 목록 |

---

## 🔌 선택 외부 서비스

ALIO · K-Startup 은 **별도 외부 서비스**이며 이 킷에 포함되지 않습니다.
관리자가 `<접두어>-mcp-remote enable <이름>` 으로 켜는 **후보**로만 제공합니다.
