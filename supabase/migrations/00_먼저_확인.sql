-- ============================================================================
-- 입장 확인을 성적 사이트에 맡기기 전에, 연결이 되는지부터 확인한다.
--
-- Supabase → Vocab-study 프로젝트 → SQL Editor 에 붙여넣고 실행.
-- 아래 20260823_login_via_score_system.sql 을 적용하기 전에 이것부터 한다.
--
-- 있지도 않은 이름으로 물어보므로 실제 학생 자료는 건드리지 않는다.
-- (성적 사이트의 parent-login 은 조회만 하고, 저장도 문자 발송도 하지 않는다)
-- ============================================================================

select
  r.status                       as "응답코드",
  left(r.content, 300)           as "응답내용",
  case
    when r.status = 401 and r.content like '%invalid_credentials%'
      then '정상 — 이대로 적용해도 됩니다'
    when r.status = 401
      then '키가 잘못됐습니다. app_config 의 score_system_key 를 성적 사이트 anon 키로 고치세요'
    when r.status = 404
      then '주소가 잘못됐습니다. app_config 의 score_system_url 을 확인하세요'
    else '예상 밖입니다 — 이 결과를 그대로 알려 주세요'
  end                            as "판정"
from public.app_config u
cross join public.app_config k
cross join lateral (
  select * from extensions.http((
    'POST',
    u.value || '/functions/v1/parent-login',
    array[ extensions.http_header('Authorization', 'Bearer ' || k.value) ],
    'application/json',
    json_build_object('name', '존재하지않는이름ZZZ테스트', 'pin', '0000')::text
  )::extensions.http_request)
) r
where u.key = 'score_system_url'
  and k.key = 'score_system_key';

-- "정상 — 이대로 적용해도 됩니다" 가 나오면 다음 파일을 실행하세요:
--   supabase/migrations/20260823_login_via_score_system.sql
--
-- 그 밖의 결과가 나오면 적용하지 마세요. 그대로 두면 지금처럼 동작합니다.
