-- ============================================================================
-- 어법 공부 — 지문 문장마다 선생님이 표시한 어법 포인트 (Vocab-study 프로젝트에서 실행)
--
--   grammar_sentences  문장 하나 = 한 줄
--     src  문장. 어법 포인트를 [정답/다른 정답/삭제] 로 감싼다 (첫 번째가 원문 그대로)
--     pts  대괄호 순서대로 [{ok:[정답들], bad:[틀린 형태들], note:설명, extra:덧붙임}]
--   화면이 한 문장에서 포인트 1~3개를 골라 틀린 형태로 바꿔 보여 주고, 학생이 찾아 고친다.
--
-- 지문처럼 브라우저(anon)가 표를 직접 읽을 수 없고, 로그인한 학생 키로 아래 함수를 불러야 받는다.
-- 정답은 지문 원문 그대로라 숨길 이유가 없어서, 채점은 화면에서 한다.
-- 데이터(실제 문제)는 공개 저장소에 두지 않는다 — SQL Editor 로 따로 넣는다.
-- 여러 번 실행해도 안전하다. 기존 표·데이터는 건드리지 않는다.
-- ============================================================================

create table if not exists public.grammar_sentences (
  grp        text not null,            -- 지문과 같은 그룹 이름
  pid        text not null,            -- 지문 번호 (passages.pid)
  sen        integer not null,         -- 문장 번호 (❶ = 1)
  src        text not null,
  pts        jsonb not null,
  updated_at timestamptz not null default now(),
  primary key (grp, pid, sen)
);
alter table public.grammar_sentences enable row level security;
revoke all on public.grammar_sentences from anon, authenticated;

-- 어느 시험의 어느 지문에 어법 문장이 몇 개 있는지 — {그룹: [[지문, 문장 수], …]} (지문 순서대로)
create or replace function public.grammar_index(p_key text) returns json
language sql stable security definer set search_path = '' as $$
  select case
    when not exists (select 1 from private.student_keys s where s.student_key = p_key) then null
    else coalesce((select json_object_agg(grp, pids) from (
           select g.grp, json_agg(json_build_array(g.pid, g.n) order by coalesce(p.ord, 999999), g.pid) pids
             from (select grp, pid, count(*) n from public.grammar_sentences group by grp, pid) g
             left join public.passages p on p.grp = g.grp and p.pid = g.pid
            group by g.grp) x), '{}'::json)
  end;
$$;

-- 고른 지문들의 어법 문장 — [{pid, sen, src, pts}] (지문 순서 · 문장 순서)
create or replace function public.grammar_get(p_key text, p_grp text, p_pids text[]) returns json
language sql stable security definer set search_path = '' as $$
  select case
    when not exists (select 1 from private.student_keys s where s.student_key = p_key) then null
    else coalesce((select json_agg(json_build_object('pid', s.pid, 'sen', s.sen, 'src', s.src, 'pts', s.pts)
                                   order by coalesce(p.ord, 999999), s.pid, s.sen)
                     from public.grammar_sentences s
                     left join public.passages p on p.grp = s.grp and p.pid = s.pid
                    where s.grp = p_grp and (p_pids is null or s.pid = any(p_pids))), '[]'::json)
  end;
$$;

revoke all on function public.grammar_index(text) from public;
revoke all on function public.grammar_get(text, text, text[]) from public;
grant execute on function public.grammar_index(text) to anon, authenticated;
grant execute on function public.grammar_get(text, text, text[]) to anon, authenticated;
