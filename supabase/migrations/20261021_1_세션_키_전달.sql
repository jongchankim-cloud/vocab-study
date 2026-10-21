-- 20261021_1 세션 키 전달
--
-- 목적: 성적 사이트가 PIN 을 확인한 뒤 단어 사이트의 학생 키(기록 저장용)를 받을 수 있게 한다.
-- 이 덕분에 자동 입장(쿠키 세션)에서도 PIN 없이 기록이 저장된다.
--
-- 보안: 키는 공유 비밀값(app_config.session_bridge_secret)을 아는 쪽에만 준다.
--       비밀값은 성적 사이트 함수의 VOCAB_BRIDGE_SECRET 과 같아야 한다.
--       PIN 확인은 성적 사이트(parent-login)가 한다. 이 함수는 확인된 이름·PIN 에만 키를 준다.
--
-- 적용 순서 (선생님이 SQL Editor 에서 실행):
--   1) 아래 [1] 의 비밀값을 긴 무작위 문자열로 바꿔서 실행
--   2) 아래 [2] 의 함수 생성
--   3) 성적 사이트 함수에 같은 값을 supabase secrets 로 설정
--        VOCAB_URL, VOCAB_ANON (단어 사이트 anon 키), VOCAB_BRIDGE_SECRET

-- [1] 비밀값 (한 번만 넣는다). 아래 문자열을 바꿔서 실행할 것
insert into public.app_config (key, value)
values ('session_bridge_secret', '여기에-긴-무작위-문자열을-넣으세요')
on conflict (key) do update set value = excluded.value;

-- [2] 함수
create or replace function public.session_student_key(p_name text, p_phone text, p_bridge text)
returns text
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_secret text;
  v_key    text;
begin
  select value into v_secret from public.app_config where key = 'session_bridge_secret';
  if v_secret is null or p_bridge is null or p_bridge <> v_secret then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  if btrim(coalesce(p_name,'')) = '' or btrim(coalesce(p_phone,'')) !~ '^\d{4}$' then
    return null;
  end if;
  v_key := private.hkey(public.make_student_key(btrim(p_name), btrim(p_phone)));
  perform private.touch_student(v_key, btrim(p_name));
  return v_key;
end $$;

revoke all on function public.session_student_key(text, text, text) from public;
grant execute on function public.session_student_key(text, text, text) to anon, authenticated;
