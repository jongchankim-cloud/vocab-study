-- ============================================================================
-- 지문 공부 화면이 쓰는 함수 두 개를 맞춘다 — Vocab-study 프로젝트에서 실행
--
--   passage_index(p_key)              어느 그룹에 어떤 지문이 있는지
--   passage_get(p_key, p_grp, p_pid)  지문 하나 — 원문 · 해석 · 단어(words)
--
-- 표와 데이터는 건드리지 않는다. 여러 번 실행해도 안전하다.
-- ============================================================================

alter table public.passages add column if not exists words jsonb;

create or replace function public.passage_index(p_key text) returns json
language sql stable security definer set search_path = '' as $$
  select case
    when not exists (select 1 from private.student_keys s where s.student_key = p_key) then null
    else coalesce((select json_object_agg(grp, pids) from (
           select grp, json_agg(pid order by ord, pid) pids
             from public.passages group by grp) x), '{}'::json)
  end;
$$;

create or replace function public.passage_get(p_key text, p_grp text, p_pid text) returns json
language sql stable security definer set search_path = '' as $$
  select case
    when not exists (select 1 from private.student_keys s where s.student_key = p_key) then null
    else (select json_build_object('pid', p.pid, 'en', p.en, 'ko', p.ko, 'words', p.words)
            from public.passages p where p.grp = p_grp and p.pid = p_pid)
  end;
$$;

revoke all on function public.passage_index(text) from public;
revoke all on function public.passage_get(text, text, text) from public;
grant execute on function public.passage_index(text) to anon, authenticated;
grant execute on function public.passage_get(text, text, text) to anon, authenticated;

-- 확인: 지문 31 · 단어 788 · 함수 2 가 나오면 성공
select
  (select count(*) from public.passages where grp = '용산 고1 2026 2학기 기말고사') as "지문",
  (select sum(jsonb_array_length(words)) from public.passages where grp = '용산 고1 2026 2학기 기말고사') as "단어",
  (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname in ('passage_index', 'passage_get')) as "함수";
