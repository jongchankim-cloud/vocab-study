-- ============================================================================
-- 입장 확인을 score-system 명단에 맡긴다
--
--   score-system 은 students 테이블을 anon 에 열어두지 않고
--   parent-login Edge Function 으로만 "이름 + PIN" 을 검증한다.
--   그래서 명단을 복사하지 않고, 그 함수를 그대로 호출한다.
--
--   · 명단을 옮겨 적을 필요가 없다 (항상 최신)
--   · score-system 의 데이터는 읽지도 쓰지도 않는다 (로그인 확인만)
--   · 새 키가 필요 없다 (이미 공개된 anon 키만 사용, 브라우저에는 안 내려감)
--
--   PIN = 학부모 연락처 뒷 4자리
--   public.students 는 이제 "추가로 입장을 허용할 학생" 목록으로만 쓴다
--   (score-system 명단에 없는 학생 예: 김채현)
-- ============================================================================

-- 쓰지 않게 된 명단 복사 함수 제거 (anon 권한이 없어 401 이 난다)
drop function if exists public.roster_sync_from_score_system(boolean);

create or replace function public.student_login(p_name text, p_phone text)
returns table(ok boolean, student_key text, name text, reason text)
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_key  text := public.make_student_key(p_name, p_phone);
  v_rec  public.students%rowtype;
  v_url  text;
  v_akey text;
  v_resp extensions.http_response;
begin
  if btrim(coalesce(p_name,'')) = '' or btrim(coalesce(p_phone,'')) !~ '^\d{4}$' then
    return query select false, null::text, null::text, 'bad_input'::text;
    return;
  end if;

  -- 1) 선생님이 직접 등록한 학생이면 통과
  select * into v_rec from public.students s where s.student_key = v_key;
  if found then
    return query select true, v_rec.student_key, v_rec.name, 'ok_manual'::text;
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
    -- score-system 이 응답하지 않으면 수업이 끊기지 않도록 판단을 앱에 넘긴다
    return query select false, null::text, null::text, 'upstream_error'::text;
    return;
  end;

  if v_resp.status = 200 then
    return query select true, v_key, btrim(p_name), 'ok'::text;
  elsif v_resp.status in (400, 401, 403, 404) then
    return query select false, null::text, null::text, 'not_listed'::text;
  else
    return query select false, null::text, null::text, 'upstream_error'::text;
  end if;
end $$;

grant execute on function public.student_login(text,text) to anon, authenticated;
