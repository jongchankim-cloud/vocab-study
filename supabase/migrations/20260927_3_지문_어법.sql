-- ============================================================================
-- 지문 · 어법 — 공개 저장소에 두지 않고 DB 에만 둔다
--
--   passages      지문 원문 · 해석 · 단어 목록 (그룹 · 지문 번호별)
--   grammar_items 어법 문제. q 의 [대괄호] 부분이 밑줄 칠 곳, a 는 정답(여러 개 가능)
--
-- 두 표 모두 브라우저(anon)가 직접 읽을 수 없다.
-- 로그인에 성공한 학생 키로 창구 함수를 불러야만 받을 수 있고,
-- 어법 정답은 브라우저로 내려가지 않는다 — 서버가 채점해서 맞았는지만 알려 준다
-- (제출한 뒤에 모범답안을 보여 준다).
--
-- 먼저 20260927_1_학생키_PIN_제거.sql 이 적용되어 있어야 한다. 여러 번 실행해도 안전하다.
-- ============================================================================

create table if not exists public.passages (
  grp        text not null,            -- 단어와 같은 그룹 이름 (예: 용산 고1 2026 2학기 중간고사)
  pid        text not null,            -- 지문 번호 = 단어 챕터 이름 (예: 1-2509-20)
  ord        integer not null default 0,
  en         text not null,            -- 원문
  ko         text,                     -- 해석 (없어도 됨)
  words      jsonb,                    -- 지문 단어 [{w, m, note}] (없으면 같은 번호의 단어 챕터를 보여 준다)
  updated_at timestamptz not null default now(),
  primary key (grp, pid)
);
alter table public.passages add column if not exists words jsonb;

create table if not exists public.grammar_items (
  id         bigserial primary key,
  grp        text not null,
  pid        text not null,
  ord        integer not null default 0,
  q          text not null,            -- 문장. 틀린 부분을 [ ] 로 감싼다
  a          text[] not null,          -- 정답들
  note       text,                     -- 해설 (선택)
  updated_at timestamptz not null default now()
);
create index if not exists grammar_items_grp_pid on public.grammar_items(grp, pid, ord);

alter table public.passages      enable row level security;
alter table public.grammar_items enable row level security;
revoke all on public.passages, public.grammar_items from anon, authenticated;
revoke all on sequence public.grammar_items_id_seq from anon, authenticated;

-- 어법 답 비교 — 대소문자 · 앞뒤 공백 · 겹친 공백 · 끝 문장부호 · 둥근 따옴표 차이는 무시
create or replace function private.gnorm(p text) returns text
language sql immutable set search_path = '' as $$
  select regexp_replace(regexp_replace(
           lower(btrim(translate(coalesce(p,''), '’‘“”', '''''""'))),
           '\s+', ' ', 'g'), '[\s.,!?;:]+$', '');
$$;

create or replace function private.is_student(p_key text) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from private.student_keys s where s.student_key = p_key);
$$;

-- 어느 지문에 원문 · 어법이 있는지 (범위 화면에 표시)
create or replace function public.content_index(p_key text) returns json
language sql stable security definer set search_path = '' as $$
  select case when not private.is_student(p_key) then null else json_build_object(
    'passages', coalesce((select json_object_agg(grp, pids) from (
        select grp, json_agg(pid order by ord, pid) pids from public.passages group by grp) x), '{}'::json),
    'grammar',  coalesce((select json_object_agg(grp, cnt) from (
        select grp, json_object_agg(pid, n) cnt from (
          select grp, pid, count(*) n from public.grammar_items group by grp, pid) y group by grp) x), '{}'::json)
  ) end;
$$;

create or replace function public.passage_get(p_key text, p_grp text, p_pid text) returns json
language sql stable security definer set search_path = '' as $$
  select case when not private.is_student(p_key) then null else
    (select json_build_object('pid', p.pid, 'en', p.en, 'ko', p.ko, 'words', p.words)
       from public.passages p where p.grp = p_grp and p.pid = p_pid) end;
$$;

-- 문제만 준다 (정답 없음)
create or replace function public.grammar_questions(p_key text, p_grp text, p_pids text[]) returns json
language sql stable security definer set search_path = '' as $$
  select case when not private.is_student(p_key) then null else
    coalesce((select json_agg(json_build_object('id', g.id, 'pid', g.pid, 'q', g.q) order by g.pid, g.ord, g.id)
                from public.grammar_items g
               where g.grp = p_grp and (p_pids is null or g.pid = any(p_pids))), '[]'::json) end;
$$;

-- 채점 — 선생님이 적어 둔 답과 같을 때만 정답
create or replace function public.grammar_check(p_key text, p_id bigint, p_answer text) returns json
language sql stable security definer set search_path = '' as $$
  select case when not private.is_student(p_key) then null else
    (select json_build_object(
        'ok', exists (select 1 from unnest(g.a) x where private.gnorm(x) = private.gnorm(p_answer))
              and private.gnorm(p_answer) <> '',
        'answers', to_json(g.a), 'note', g.note)
       from public.grammar_items g where g.id = p_id) end;
$$;

revoke all on all functions in schema private from public, anon, authenticated;
grant execute on function public.content_index(text), public.passage_get(text, text, text),
                          public.grammar_questions(text, text, text[]),
                          public.grammar_check(text, bigint, text)
to anon, authenticated;
