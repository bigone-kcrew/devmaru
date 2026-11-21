---
version: alpha
name: @@BRAND@@
description: @@BRAND@@ 포털·가이드·OPS 의 시각 언어(shadcn/ui neutral 기반, 한글 Pretendard, 접근성 예외 4건). 정본은 shared.css 이며 이 파일은 거기서 생성된다.
colors:
  bg: "oklch(1 0 0)"
  card: "oklch(1 0 0)"
  text: "oklch(0.145 0 0)"
  text-2: "oklch(0.371 0 0)"
  muted: "oklch(0.54 0 0)"
  soft: "oklch(0.97 0 0)"
  line: "oklch(0.922 0 0)"
  line-strong: "oklch(0.87 0 0)"
  control-line: "oklch(0.6 0 0)"
  primary: "oklch(0.205 0 0)"
  primary-fg: "oklch(0.985 0 0)"
  secondary: "oklch(0.97 0 0)"
  secondary-fg: "oklch(0.205 0 0)"
  accent: "oklch(0.488 0.243 264.376)"
  accent-contrast: "oklch(0.985 0 0)"
  ring: "oklch(0.488 0.243 264.376)"
  ok: "#0d6d60"
  hold: "#865809"
  danger: "#b42318"
  bg-dark: "oklch(0.145 0 0)"
  card-dark: "oklch(0.205 0 0)"
  text-dark: "oklch(0.985 0 0)"
  text-2-dark: "oklch(0.87 0 0)"
  muted-dark: "oklch(0.708 0 0)"
  soft-dark: "oklch(0.269 0 0)"
  line-dark: "oklch(1 0 0 / 10%)"
  line-strong-dark: "oklch(1 0 0 / 20%)"
  control-line-dark: "oklch(1 0 0 / 40%)"
  primary-dark: "oklch(0.922 0 0)"
  primary-fg-dark: "oklch(0.205 0 0)"
  secondary-dark: "oklch(0.269 0 0)"
  secondary-fg-dark: "oklch(0.985 0 0)"
  accent-dark: "oklch(0.707 0.165 254.624)"
  accent-contrast-dark: "oklch(0.145 0 0)"
  ring-dark: "oklch(0.707 0.165 254.624)"
  ok-dark: "#4fd8c0"
  hold-dark: "#f5b13d"
  danger-dark: "#ff9d94"
typography:
  h1:
    fontFamily: Pretendard
    fontSize: 3rem
    fontWeight: 600
    lineHeight: 1.1
    letterSpacing: -0.05em
  h2:
    fontFamily: Pretendard
    fontSize: 1.875rem
    fontWeight: 600
    lineHeight: 2.25rem
    letterSpacing: -0.025em
  h3:
    fontFamily: Pretendard
    fontSize: 1.5rem
    fontWeight: 600
    lineHeight: 2rem
    letterSpacing: -0.025em
  card-title:
    fontFamily: Pretendard
    fontSize: 1rem
    fontWeight: 500
    lineHeight: 1.5rem
  body:
    fontFamily: Pretendard
    fontSize: 0.875rem
    fontWeight: 400
    lineHeight: 1.25rem
  body-lg:
    fontFamily: Pretendard
    fontSize: 1rem
    fontWeight: 400
    lineHeight: 1.5rem
  label:
    fontFamily: Pretendard
    fontSize: 0.875rem
    fontWeight: 500
    lineHeight: 1
  caption:
    fontFamily: Pretendard
    fontSize: 0.75rem
    fontWeight: 500
    lineHeight: 1rem
  code:
    fontFamily: ui-monospace
    fontSize: 0.875rem
    fontWeight: 400
    lineHeight: 1.5
rounded:
  sm: 8px
  md: 12px
  lg: 18px
  xl: 24px
  full: 9999px
spacing:
  s1: 4px
  s2: 8px
  s3: 12px
  s4: 16px
  s6: 24px
  s8: 32px
  s12: 48px
  s16: 64px
  page-max: 1120px
  tap-min: 44px
components:
  button:
    backgroundColor: "{colors.primary}"
    textColor: "{colors.primary-fg}"
    rounded: "{rounded.full}"
    height: 40px
    padding: 0 20px
  button-outline:
    backgroundColor: "{colors.bg}"
    textColor: "{colors.text}"
    rounded: "{rounded.full}"
    height: 40px
  card:
    backgroundColor: "{colors.card}"
    textColor: "{colors.text}"
    rounded: "{rounded.xl}"
    padding: 24px
  input:
    backgroundColor: "{colors.soft}"
    textColor: "{colors.text}"
    rounded: "{rounded.lg}"
    height: 40px
  badge:
    backgroundColor: "{colors.primary}"
    textColor: "{colors.primary-fg}"
    rounded: "{rounded.full}"
---

## Overview

@@BRAND@@ 의 화면(포털·Guide·Skills·Tools·OPS)은 **차분하고 읽기 쉬운 업무 도구**의 인상을 준다. 바탕은 흰색/아주 어두운 회색 중립이고, 강조는 한 가지 색(인디고 계열 accent)과 검정/흰 primary 만 쓴다. 장식(그라데이션·보라/분홍·막대 장식)을 넣지 않는다. 색은 **상태**(정상·주의·위험)에만 쓰고, 상태는 색만으로 구분하지 않고 **기호와 글자를 함께** 쓴다(✓ ! × —). 한국어 본문 중심이며 공문서·관리 화면처럼 밀도 있는 정보를 읽는 사용자를 위한 화면이다. 외부 브랜드나 정부 서비스를 닮게 만들지 않는다.

## Colors

색 토큰은 라이트가 기본이고 `-dark` 접미사가 다크 값이다(`prefers-color-scheme` 와 `data-theme` 로 전환). 이름은 역할이다 — 값을 하드코딩하지 말고 토큰(CSS 변수 `--bg`, `--text` …)을 쓴다.

- **primary / primary-fg**: 주 버튼·배지. 라이트에서는 거의 검정, 다크에서는 거의 흰색.
- **bg / card / soft**: 페이지 바탕 / 카드 면 / 회색 면(입력·코드·선택 배경).
- **text / text-2 / muted**: 본문 / 보조 / 설명·캡션. `muted` 는 회색 면(`soft`) 위에서도 4.5:1 이상이 되도록 정한 값이다.
- **line / line-strong / control-line**: 일반 구분선 / 강한 구분선 / **컨트롤 경계**(입력·버튼 테두리, 비텍스트 대비 3:1 기준). 컨트롤 경계에 `line` 을 쓰지 않는다.
- **accent / ring**: 링크·선택·포커스. 포커스는 반투명 링이 아니라 **2px 실선 윤곽 + 링**.
- **ok / hold / danger**: 정상 / 주의 / 위험(글자색 기준 흰 바탕에서 4.5:1 이상). 배경 틴트는 상태색 10%.

접근성 기준: 본문·설명 글자 4.5:1 이상, 컨트롤 경계와 그래픽 3:1 이상. shadcn 기본값에서 이 기준에 못 미치던 4곳(컨트롤 경계, 포커스, 상태 글자색, muted)은 `shared.css` 에 예외로 고쳐 두었다.

## Typography

글꼴은 **Pretendard** (한글·라틴 공용)이고, 시스템 글꼴로 대체될 수 있다. 코드는 고정폭(ui-monospace 계열)이며 크기는 0.875rem 로 고정한다. 크기 단위는 `rem` 만 쓰고 `em` 은 쓰지 않는다(중첩 시 크기가 누적되는 것을 막기 위해). 굵기는 세 가지 — 본문 400, 라벨·버튼·카드 제목 500, 제목 600.

허용 크기: xs 0.75rem · sm 0.875rem · base 1rem · md 1.125rem · lg 1.25rem · xl 1.5rem · 2xl 1.875rem. 이 밖의 크기를 만들지 않는다. h1 은 화면 폭에 따라 1.875rem~3rem 으로 변한다(YAML 의 h1 은 최대값).

## Layout

간격은 4px 기준 척도(4·8·12·16·24·32·48·64)만 쓴다. 본문 최대 폭은 1120px, 터치 대상 최소 높이는 44px. 카드 안쪽 여백은 24px(촘촘한 카드 16px). 고정 헤더 높이는 `--head-h` 하나로 관리한다. 모바일(약 390px)에서 가로로 넘치는 요소가 없어야 하며, 표와 코드는 자기 가로 스크롤 영역 안에서만 스크롤한다.

## Elevation & Depth

깊이는 **옅은 그림자 2단**과 1px 경계로 만든다. 카드 = `shadow-1`(1px 경계 포함), 호버·떠 있는 요소 = `shadow-2`, 가장 가벼운 구분 = `shadow-xs`. 다크 모드는 그림자를 더 진하게 쓰고 경계는 흰색 알파(oklch(1 0 0 / 10%))로 대체한다. 선택 상태는 테두리를 굵게 하지 않고 2px 링으로 표시한다.

## Shapes

모서리는 작은 요소 8px, 중간 12px, 입력·행 18px, 카드 24px, **버튼·배지·칩은 알약(full)**. 장식용 각진/둥근 혼합을 만들지 않는다.

## Components

- **Button**: 높이 40px, 알약, 기본(primary) / outline / ghost. 글자 0.875rem 굵기 500. 아이콘만 있는 버튼에도 접근 가능한 이름을 단다.
- **Card**: 흰 면 + 1px `line` + `shadow-1`, 반경 24px. 제목은 16px/500, 설명은 `muted`.
- **Input / Select**: 높이 40px, 회색 면(`soft` 55%), 경계는 `control-line`. 포커스는 `ring` 실선 윤곽 + 3px 링.
- **Badge / Tag**: 알약, 글자 0.75rem/500. 상태 태그는 상태색 10% 배경 + 기호.
- **Tabs / Toggle / Accordion / Alert / Table / Breadcrumb / Sidebar**: `shared.css` 의 `.sc-*` 클래스와 기존 클래스 매핑을 쓴다(새 모양을 만들지 않는다).
- 모션: 요소 360ms·데이터 그래픽 800ms, 이동 12px 이내, 되튐(overshoot) 없음. `prefers-reduced-motion` 에서는 재생하지 않는다.

## Do's and Don'ts

- Do: 색 변수(`var(--text)` 등)를 쓴다 / 상태에 기호+글자를 함께 쓴다 / 라이트·다크 둘 다 확인한다 / 키보드 포커스가 보이게 한다 / 한국어 문장은 어절 단위로 줄바꿈된다(`word-break: keep-all` 계열) 는 것을 전제로 폭을 잡는다.
- Don't: 16진수 색을 직접 쓰지 않는다 / 그라데이션·보라·분홍 장식을 쓰지 않는다 / 왼쪽 강조 막대로 카드를 꾸미지 않는다 / `em` 크기를 쓰지 않는다 / 색만으로 상태를 구분하지 않는다 / 특정 기업·정부 서비스의 외관을 모방하지 않는다.
- Don't: 외부 CDN·폰트 호스트를 새로 추가하지 않는다(폰트는 Pretendard 한 곳).

## 사용 방법 (에이전트용)

화면·스타일 작업을 시작하기 전에 이 파일을 읽는다. 값이 필요하면 이 파일이 아니라 `shared.css` 의 토큰을 가져다 쓴다(이 파일은 요약본이며 정본은 `shared.css`). 이 파일의 값과 `shared.css` 가 다르면 `shared.css` 가 맞다.
