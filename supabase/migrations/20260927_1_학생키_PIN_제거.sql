-- ============================================================================
-- 1단계 — 학생 키에서 PIN 을 없애고, 기록을 다루는 "창구" 함수를 만든다
--
-- 문제
--   progress 표의 student_key 가 "이름_PIN" 이었다. 이 PIN 은 성적 사이트
--   학부모 로그인과 같은 값이고, progress 는 공개 키로 누구나 읽을 수 있었다.
--
-- 이 파일이 하는 일
--   1) 비밀값(private.secrets)으로 섞은 키로 바꾼다:  김민수_4821 → k1_8f3a…
--      같은 이름·PIN 이면 언제나 같은 키가 나오고, 키에서 PIN 을 되돌릴 수 없다.
--   2) 기존 기록의 키를 전부 새 키로 옮긴다 (학생 입장에서는 달라지는 것 없음).
--      예외 명단(students)의 PIN(phone4)도 지운다.
--   3) student_login 이 새 키를 돌려주게 한다.
--   4) 학생 창구(progress_mine · progress_put · progress_del · shared_aliases ·
--      alias_ai_share)와 관리자 창구(admin_*)를 만든다.
--      관리자 창구는 성적 사이트 관리자 비밀번호로 연다 (admin-api 로 확인).
--
-- 이 파일은 옛 화면과도 호환된다. 표를 닫는 것은 2단계 파일이 한다.
--   (옛 화면도 student_login 이 준 키를 그대로 쓰므로 기록이 이어진다)
-- 여러 번 실행해도 안전하다.
-- ============================================================================

-- ---------- 비공개 공간 ----------
-- private 스키마는 API 로 노출되지 않는다. anon 은 들어올 수조차 없다.
create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

create table if not exists private.secrets (
  name  text primary key,
  value text not null
);
insert into private.secrets(name, value)
values ('student_key', encode(extensions.gen_random_bytes(32), 'hex'))
on conflict (name) do nothing;

-- 로그인에 성공한 적이 있는 학생의 키. 창구 함수는 여기 있는 키만 받는다
-- (아무 키나 지어내서 기록을 쌓는 것을 막는다).
create table if not exists private.student_keys (
  student_key text primary key,
  name        text not null,
  last_login  timestamptz not null default now()
);

create table if not exists private.admin_sessions (
  token      text primary key,
  expires_at timestamptz not null
);

-- 되돌리기용 백업 — 옮기기 직전의 원본. 이 안에는 PIN 이 남아 있으므로
-- 새 방식이 안정되면(1~2주 뒤) 지운다:
--   drop table private.progress_backup_20260927, private.students_backup_20260927;
create table if not exists private.progress_backup_20260927 as table public.progress;
create table if not exists private.students_backup_20260927 as table public.students;

-- ---------- 키 만들기 ----------
create or replace function private.hkey(p_raw text) returns text
language sql stable security definer set search_path = '' as $$
  select 'k1_' || left(encode(extensions.hmac(
           p_raw, (select s.value from private.secrets s where s.name = 'student_key'), 'sha256'), 'hex'), 32);
$$;

create or replace function private.touch_student(p_key text, p_name text) returns void
language sql security definer set search_path = '' as $$
  insert into private.student_keys(student_key, name, last_login)
  values (p_key, p_name, now())
  on conflict (student_key) do update set name = excluded.name, last_login = now();
$$;

create or replace function private.admin_assert(p_token text) returns void
language plpgsql stable security definer set search_path = '' as $$
begin
  if p_token is null or not exists (
       select 1 from private.admin_sessions a where a.token = p_token and a.expires_at > now()) then
    raise exception 'admin_auth' using errcode = '28000',
      hint = '관리자 확인이 필요합니다. 관리 화면에 다시 들어가 주세요.';
  end if;
end $$;

-- ---------- 기존 기록 옮기기 ----------
insert into private.student_keys(student_key, name, last_login)
select private.hkey(p.student_key),
       coalesce(max(p.student_name), split_part(p.student_key, '_', 1)),
       coalesce(max(p.updated_at), now())
from public.progress p
where p.student_key !~ '^(__|k1_)'
group by p.student_key
on conflict (student_key) do nothing;

update public.progress
   set student_key = private.hkey(student_key)
 where student_key !~ '^(__|k1_)';

alter table public.students alter column phone4 drop not null;
update public.students
   set student_key = private.hkey(student_key), phone4 = null
 where student_key !~ '^k1_';

-- ---------- 로그인 — 새 키를 돌려준다 ----------
create or replace function public.student_login(p_name text, p_phone text)
returns table(ok boolean, student_key text, name text, reason text)
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_key  text;
  v_rec  public.students%rowtype;
  v_url  text;
  v_akey text;
  v_resp extensions.http_response;
begin
  if btrim(coalesce(p_name,'')) = '' or btrim(coalesce(p_phone,'')) !~ '^\d{4}$' then
    return query select false, null::text, null::text, 'bad_input'::text;
    return;
  end if;
  v_key := private.hkey(public.make_student_key(p_name, p_phone));

  -- 1) 선생님이 직접 등록한 학생이면 통과
  select * into v_rec from public.students s where s.student_key = v_key;
  if found then
    perform private.touch_student(v_key, v_rec.name);
    return query select true, v_key, v_rec.name, 'ok_manual'::text;
    return;
  end if;

  -- 2) score-system 에 물어본다
  select value into v_url  from public.app_config where key = 'score_system_url';
  select value into v_akey from public.app_config where key = 'score_system_key';
  if v_url is null or v_akey is null then
    return query select false, null::text, null::text, 'upstream_error'::text;
    return;
  end if;

  begin
    perform extensions.http_set_curlopt('CURLOPT_TIMEOUT', '6');
    select * into v_resp from extensions.http((
      'POST',
      v_url || '/functions/v1/parent-login',
      array[ extensions.http_header('Authorization', 'Bearer ' || v_akey) ],
      'application/json',
      json_build_object('name', btrim(p_name), 'pin', btrim(p_phone))::text
    )::extensions.http_request);
  exception when others then
    -- 성적 사이트가 응답하지 않으면 판단을 앱에 넘긴다.
    -- 이때는 키를 주지 않는다 — 확인 안 된 이름·PIN 으로 기록을 열면
    -- 키가 맞는지 틀리는지로 PIN 을 알아낼 수 있게 된다.
    return query select false, null::text, null::text, 'upstream_error'::text;
    return;
  end;

  if v_resp.status = 200 then
    perform private.touch_student(v_key, btrim(p_name));
    return query select true, v_key, btrim(p_name), 'ok'::text;
  elsif v_resp.status in (400, 401, 403, 404) then
    return query select false, null::text, null::text, 'not_listed'::text;
  else
    return query select false, null::text, null::text, 'upstream_error'::text;
  end if;
end $$;

-- ---------- 학생 창구 ----------
-- 목록은 json 한 덩어리로 돌려준다 (API 의 1,000행 제한에 걸리지 않게).
create or replace function public.progress_mine(p_key text) returns json
language sql stable security definer set search_path = '' as $$
  select coalesce(json_agg(json_build_object('kind', p.kind, 'word_id', p.word_id)), '[]'::json)
  from public.progress p
  where p.student_key = p_key
    and exists (select 1 from private.student_keys s where s.student_key = p_key);
$$;

create or replace function public.shared_aliases() returns json
language sql stable security definer set search_path = '' as $$
  select coalesce(json_agg(p.word_id), '[]'::json)
  from public.progress p
  where p.student_key in ('__ALIAS__', '__ALIAS_AI__') and p.kind = 'alias';
$$;

create or replace function public.progress_put(p_key text, p_kind text, p_word_id text,
                                               p_word text, p_grp text, p_day text)
returns boolean language plpgsql security definer set search_path = '' as $$
declare v_name text;
begin
  select s.name into v_name from private.student_keys s where s.student_key = p_key;
  if not found then return false; end if;
  if coalesce(p_kind,'') !~ '^[a-z][a-z_]{0,19}$'
     or coalesce(p_word_id,'') = '' or length(p_word_id) > 500 then
    return false;
  end if;
  insert into public.progress(student_key, student_name, kind, word_id, word, grp, day, updated_at)
  values (p_key, v_name, p_kind, p_word_id, left(p_word, 300), left(p_grp, 200), left(p_day, 200), now())
  on conflict (student_key, kind, word_id) do update
    set student_name = excluded.student_name, word = excluded.word,
        grp = excluded.grp, day = excluded.day, updated_at = now();
  return true;
end $$;

create or replace function public.progress_del(p_key text, p_kind text, p_word_id text)
returns boolean language plpgsql security definer set search_path = '' as $$
begin
  if not exists (select 1 from private.student_keys s where s.student_key = p_key) then
    return false;
  end if;
  delete from public.progress p
   where p.student_key = p_key and p.kind = p_kind and p.word_id = p_word_id;
  return true;
end $$;

-- AI 가 인정한 답을 모든 학생에게 공유한다 (로그인한 학생만 쓸 수 있다)
create or replace function public.alias_ai_share(p_key text, p_word_id text,
                                                 p_word text, p_grp text, p_day text)
returns boolean language plpgsql security definer set search_path = '' as $$
begin
  if not exists (select 1 from private.student_keys s where s.student_key = p_key) then
    return false;
  end if;
  if coalesce(p_word_id,'') = '' or length(p_word_id) > 500 then return false; end if;
  insert into public.progress(student_key, student_name, kind, word_id, word, grp, day, updated_at)
  values ('__ALIAS_AI__', '(AI 인정 답안)', 'alias', p_word_id, left(p_word, 300),
          left(p_grp, 200), left(p_day, 200), now())
  on conflict (student_key, kind, word_id) do update set updated_at = now();
  return true;
end $$;

-- ---------- 관리자 창구 ----------
-- 성적 사이트 관리자 비밀번호가 맞는지 admin-api 에 읽기 요청 한 번으로 확인하고,
-- 맞으면 12시간짜리 통행증(token)을 준다. 비밀번호는 저장하지 않는다.
-- 반환: 통행증 문자열 / 비밀번호가 틀리면 null / 성적 사이트가 응답 없으면 오류
create or replace function public.admin_login(p_pw text) returns text
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_url   text;
  v_akey  text;
  v_resp  extensions.http_response;
  v_token text;
begin
  if coalesce(p_pw, '') = '' then return null; end if;
  select value into v_url  from public.app_config where key = 'score_system_url';
  select value into v_akey from public.app_config where key = 'score_system_key';
  begin
    perform extensions.http_set_curlopt('CURLOPT_TIMEOUT', '8');
    select * into v_resp from extensions.http((
      'POST',
      v_url || '/functions/v1/admin-api',
      array[ extensions.http_header('Authorization', 'Bearer ' || v_akey) ],
      'application/json',
      json_build_object('password', p_pw, 'path', 'classes?select=id&limit=1', 'method', 'GET')::text
    )::extensions.http_request);
  exception when others then
    raise exception 'upstream_error' using hint = '성적 사이트가 응답하지 않습니다.';
  end;
  if v_resp.status = 200 then
    delete from private.admin_sessions where expires_at < now();
    v_token := encode(extensions.gen_random_bytes(24), 'hex');
    insert into private.admin_sessions(token, expires_at) values (v_token, now() + interval '12 hours');
    return v_token;
  elsif v_resp.status = 401 then
    return null;
  end if;
  raise exception 'upstream_error' using hint = '성적 사이트 응답 ' || v_resp.status;
end $$;

create or replace function public.admin_logout(p_token text) returns void
language sql security definer set search_path = '' as $$
  delete from private.admin_sessions where token = p_token;
$$;

create or replace function public.admin_progress_all(p_token text) returns json
language plpgsql stable security definer set search_path = '' as $$
declare v json;
begin
  perform private.admin_assert(p_token);
  select coalesce(json_agg(json_build_object(
           'student_key', p.student_key, 'student_name', p.student_name, 'kind', p.kind,
           'word_id', p.word_id, 'word', p.word, 'grp', p.grp, 'day', p.day,
           'updated_at', p.updated_at) order by p.updated_at desc nulls last), '[]'::json)
    into v
    from public.progress p;
  return v;
end $$;

-- AI 인정 답안 하나를 완전히 지운다 — 공유본과 모든 학생의 개인 기록(alias_ai)까지
create or replace function public.admin_delete_ai_alias(p_token text, p_word_id text) returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform private.admin_assert(p_token);
  delete from public.progress p
   where (p.student_key = '__ALIAS_AI__' and p.kind = 'alias' and p.word_id = p_word_id)
      or (p.kind = 'alias_ai' and p.word_id = p_word_id);
end $$;

-- AI 인정 답안 전체 비우기 (채점 규칙을 바꾼 뒤)
create or replace function public.admin_purge_ai_aliases(p_token text) returns integer
language plpgsql security definer set search_path = '' as $$
declare v_n integer;
begin
  perform private.admin_assert(p_token);
  delete from public.progress p
   where (p.student_key = '__ALIAS_AI__' and p.kind = 'alias') or p.kind = 'alias_ai';
  get diagnostics v_n = row_count;
  return v_n;
end $$;

-- 선생님의 "전체 인정" / 취소
create or replace function public.admin_global_alias(p_token text, p_on boolean, p_word_id text,
                                                     p_word text, p_grp text, p_day text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  perform private.admin_assert(p_token);
  if p_on then
    insert into public.progress(student_key, student_name, kind, word_id, word, grp, day, updated_at)
    values ('__ALIAS__', '(공통 인정 답안)', 'alias', p_word_id, p_word, p_grp, p_day, now())
    on conflict (student_key, kind, word_id) do update
      set word = excluded.word, grp = excluded.grp, day = excluded.day, updated_at = now();
  else
    delete from public.progress p
     where p.student_key = '__ALIAS__' and p.kind = 'alias' and p.word_id = p_word_id;
  end if;
end $$;

-- 단어 사이트에만 따로 허용한 학생 (예외 명단). PIN 은 저장하지 않는다.
create or replace function public.admin_roster_list(p_token text) returns json
language plpgsql stable security definer set search_path = '' as $$
declare v json;
begin
  perform private.admin_assert(p_token);
  select coalesce(json_agg(json_build_object('student_key', s.student_key, 'name', s.name,
                                             'note', s.note, 'created_at', s.created_at)
                           order by s.name), '[]'::json)
    into v from public.students s;
  return v;
end $$;

create or replace function public.admin_roster_add(p_token text, p_name text, p_phone text, p_note text default null)
returns void language plpgsql security definer set search_path = '' as $$
begin
  perform private.admin_assert(p_token);
  if btrim(coalesce(p_name,'')) = '' or btrim(coalesce(p_phone,'')) !~ '^\d{4}$' then
    raise exception '이름과 뒷 4자리를 정확히 입력해 주세요.';
  end if;
  insert into public.students(student_key, name, phone4, note)
  values (private.hkey(public.make_student_key(p_name, p_phone)), btrim(p_name), null,
          nullif(btrim(coalesce(p_note,'')), ''))
  on conflict (student_key) do update set name = excluded.name, note = excluded.note;
end $$;

create or replace function public.admin_roster_remove(p_token text, p_key text) returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform private.admin_assert(p_token);
  delete from public.students s where s.student_key = p_key;
end $$;

-- ---------- 옛 관리 화면 호환 (2단계에서 막는다) ----------
-- 옛 화면이 부르는 roster_add 도 PIN 대신 새 키를 저장하게 한다.
create or replace function public.roster_add(p_name text, p_phone text, p_note text default null)
returns public.students language plpgsql security definer set search_path = public as $$
declare v_rec public.students%rowtype;
begin
  if btrim(coalesce(p_name,'')) = '' or btrim(coalesce(p_phone,'')) !~ '^\d{4}$' then
    raise exception '이름과 뒷 4자리를 정확히 입력해 주세요.';
  end if;
  insert into public.students(student_key, name, phone4, note)
  values (private.hkey(public.make_student_key(p_name, p_phone)), btrim(p_name), null,
          nullif(btrim(coalesce(p_note,'')), ''))
  on conflict (student_key) do update set name = excluded.name, note = excluded.note
  returning * into v_rec;
  return v_rec;
end $$;

-- 이름_PIN 키를 전제로 한 함수라 이제 쓸모가 없다 (화면에서도 쓰지 않는다)
drop function if exists public.roster_seed_from_progress();

-- ---------- 권한 ----------
revoke all on all tables    in schema private from public, anon, authenticated;
revoke all on all functions in schema private from public, anon, authenticated;
grant execute on function
  public.student_login(text, text),
  public.progress_mine(text), public.shared_aliases(),
  public.progress_put(text, text, text, text, text, text),
  public.progress_del(text, text, text),
  public.alias_ai_share(text, text, text, text, text),
  public.admin_login(text), public.admin_logout(text), public.admin_progress_all(text),
  public.admin_delete_ai_alias(text, text), public.admin_purge_ai_aliases(text),
  public.admin_global_alias(text, boolean, text, text, text, text),
  public.admin_roster_list(text), public.admin_roster_add(text, text, text, text),
  public.admin_roster_remove(text, text)
to anon, authenticated;

-- ---------- 확인 ----------
-- 아래가 둘 다 0 이면 성공이다.
select
  (select count(*) from public.progress where student_key !~ '^(__|k1_)') as "이름_PIN 키가 남은 기록",
  (select count(*) from public.students where phone4 is not null)       as "PIN 이 남은 예외 명단";
