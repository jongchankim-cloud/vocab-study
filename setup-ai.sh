#!/usr/bin/env bash
#
# AI 채점 켜기 — Gemini API 키를 Supabase 에 등록하고 Edge Function 을 배포합니다.
#
#   ./setup-ai.sh <GEMINI_API_KEY> [PROJECT_REF]
#
# 키는 이 컴퓨터의 Supabase 프로젝트 환경변수로만 올라갑니다.
# 저장소나 index.html 에는 절대 기록하지 않습니다.
#
set -euo pipefail

KEY="${1:-}"
REF="${2:-uxzsleryzpjaoqciyqvs}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -z "$KEY" ]; then
  cat <<'USAGE'
사용법: ./setup-ai.sh <GEMINI_API_KEY> [PROJECT_REF]

  GEMINI_API_KEY  https://aistudio.google.com/apikey 에서 발급한 키
                  ("AIzaSy" 로 시작하는 39자입니다)
  PROJECT_REF     Supabase 프로젝트 ref (기본값: uxzsleryzpjaoqciyqvs)
USAGE
  exit 1
fi

# 키 모양 확인 — 구글은 AIza(기존)와 AQ.(신형 인증 키) 두 가지를 발급합니다
case "$KEY" in
  AIza*) echo "▸ 기존 형식 API 키(AIza…)" ;;
  AQ.*)  echo "▸ 신형 인증 키(AQ.…) — Bearer 방식으로 호출합니다" ;;
  ya29.*)
    echo "✗ 이건 OAuth 액세스 토큰(ya29.…)이라 몇 시간 뒤 만료됩니다."
    echo "  https://aistudio.google.com/apikey 에서 API 키를 발급해 주세요."
    exit 1 ;;
  *)
    echo "⚠  보통은 'AIza…' 또는 'AQ.…' 로 시작합니다. 계속할까요? [y/N] "
    read -r yn
    [ "$yn" = "y" ] || [ "$yn" = "Y" ] || exit 1 ;;
esac

if ! command -v supabase >/dev/null 2>&1; then
  echo "✗ Supabase CLI 가 없습니다."
  echo "  설치: npm i -g supabase   (또는  brew install supabase/tap/supabase )"
  exit 1
fi

echo "▸ 프로젝트 연결 ($REF)"
supabase link --project-ref "$REF" >/dev/null

echo "▸ API 키 등록 (GEMINI_API_KEY)"
supabase secrets set "GEMINI_API_KEY=$KEY" >/dev/null   # 키는 화면에 찍지 않습니다

echo "▸ 함수 배포 (judge-meaning)"
supabase functions deploy judge-meaning

URL="https://$REF.supabase.co/functions/v1/judge-meaning"

# 배포한 함수가 실제로 Gemini 를 부를 수 있는지 바로 확인합니다
echo "▸ 자체 점검 중…"
ANON="$(grep -o 'const SUPABASE_ANON = "[^"]*"' "$HERE/index.html" | head -1 | cut -d'"' -f2)"
CHECK="$(curl -sS -m 30 -H "Authorization: Bearer $ANON" "$URL?selftest=1" || true)"
case "$CHECK" in
  *'"ok":true'*)
    echo "  ✓ Gemini 호출 성공"
    echo "    $CHECK" ;;
  "")
    echo "  ⚠ 함수에서 응답이 없습니다. 잠시 후 아래 주소로 다시 확인해 보세요."
    echo "    curl -H \"Authorization: Bearer \$ANON\" \"$URL?selftest=1\"" ;;
  *)
    echo "  ✗ 호출에 실패했습니다. 아래 내용을 확인하세요."
    echo "    $CHECK"
    echo "    (401 ACCESS_TOKEN_TYPE_UNSUPPORTED 이면 그 키로는 Gemini API 를 쓸 수 없습니다."
    echo "     AI Studio 에서 키를 다시 발급하거나 다른 프로젝트의 키를 써 보세요.)" ;;
esac

# index.html 의 AI_JUDGE_URL 을 채워 넣습니다 (주소는 비밀이 아닙니다)
if grep -q '^const AI_JUDGE_URL = ' "$HERE/index.html"; then
  tmp="$(mktemp)"
  sed "s|^const AI_JUDGE_URL = \".*\";|const AI_JUDGE_URL = \"$URL\";|" "$HERE/index.html" > "$tmp"
  mv "$tmp" "$HERE/index.html"
  echo "▸ index.html 의 AI_JUDGE_URL 을 설정했습니다."
fi

cat <<DONE

완료했습니다.
  함수 주소 : $URL
  다음 할 일 : index.html 을 평소처럼 배포(업로드)하면 AI 채점이 켜집니다.

끄고 싶으면 index.html 의 AI_JUDGE_URL 을 "" 로 되돌리면 됩니다.
키를 바꾸려면 이 스크립트를 새 키로 다시 실행하세요.
DONE
