-- ============================================================================
-- 지문 공부 — 원문 · 해석을 DB 에만 둔다 (공개 저장소에는 올리지 않는다)
--
--   passages  그룹 · 지문 번호별 원문(en) 과 해석(ko)
--
-- 브라우저(anon)는 표를 직접 읽을 수 없다. 로그인에 성공한 학생 키로
-- 아래 두 창구 함수를 불러야만 받을 수 있다.
--
--   passage_index(p_key)              어느 그룹에 어떤 지문이 있는지 {그룹: [번호...]}
--   passage_get(p_key, p_grp, p_pid)  지문 하나 {pid, en, ko}
--
-- 먼저 20260927_1_학생키_PIN_제거.sql 이 적용되어 있어야 한다. 여러 번 실행해도 안전하다.
-- 지문을 넣는 방법은 supabase/examples/지문_넣기.sql 참고.
-- ============================================================================

create table if not exists public.passages (
  grp        text not null,            -- 단어와 같은 그룹 이름 (예: 용산 고1 2026 2학기 기말고사)
  pid        text not null,            -- 지문 번호 = 단어 챕터 이름 (예: 1-2510-20)
  ord        integer not null default 0,
  en         text not null,            -- 원문
  ko         text,                     -- 해석 (없어도 됨)
  updated_at timestamptz not null default now(),
  primary key (grp, pid)
);

alter table public.passages enable row level security;
revoke all on public.passages from anon, authenticated;

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
    else (select json_build_object('pid', p.pid, 'en', p.en, 'ko', p.ko)
            from public.passages p where p.grp = p_grp and p.pid = p_pid)
  end;
$$;

revoke all on function public.passage_index(text) from public;
revoke all on function public.passage_get(text, text, text) from public;
grant execute on function public.passage_index(text) to anon, authenticated;
grant execute on function public.passage_get(text, text, text) to anon, authenticated;
