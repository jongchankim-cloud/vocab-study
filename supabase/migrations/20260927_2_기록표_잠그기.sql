-- ============================================================================
-- 2단계 — 표를 잠근다
--
-- 먼저 할 것
--   1) 20260927_1_학생키_PIN_제거.sql 적용
--   2) 새 index.html · admin.html 이 main 에 반영되고, 학생들이 새 버전으로
--      바뀐 뒤 (화면 아래 버전이 2026-09-27-1 이상)
--
-- 이 파일을 적용하면
--   · 브라우저(anon)는 progress · students · app_config 표를 직접 읽거나 쓸 수 없다.
--     학생·관리 화면은 1단계에서 만든 창구 함수로만 드나든다.
--   · 예전 명단 함수(roster_list · roster_add · roster_remove)를 막는다.
--     예외 명단은 관리자 통행증이 있어야 다룰 수 있다 (admin_roster_*).
--
-- 문제가 생기면 20260927_9_비상_되돌리기.sql 의 [A] 를 실행한다.
-- ============================================================================

drop policy if exists "anon can read"   on public.progress;
drop policy if exists "anon can insert" on public.progress;
drop policy if exists "anon can update" on public.progress;
drop policy if exists "anon can delete" on public.progress;

-- RLS 는 켜 둔 채 정책이 없으면 전부 거부된다. 권한도 함께 뺀다(이중 잠금).
revoke all on public.progress, public.students, public.app_config from anon, authenticated;
revoke all on sequence public.progress_id_seq from anon, authenticated;

revoke execute on function public.roster_list()                  from public, anon, authenticated;
revoke execute on function public.roster_add(text, text, text)   from public, anon, authenticated;
revoke execute on function public.roster_remove(text)            from public, anon, authenticated;

-- ---------- 확인 ----------
-- "anon 이 읽을 수 있나" 가 전부 false 이면 성공이다.
select c.relname as "표",
       has_table_privilege('anon', c.oid, 'SELECT') as "anon 이 읽을 수 있나",
       (select count(*) from pg_policies p where p.schemaname = 'public' and p.tablename = c.relname) as "정책 수"
from pg_class c join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public' and c.relname in ('progress', 'students', 'app_config')
order by 1;
