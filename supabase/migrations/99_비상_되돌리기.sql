-- ============================================================================
-- 비상용 — 입장이 막혔을 때 즉시 되돌린다.
--
-- 학생들이 갑자기 "이름 또는 PIN이 올바르지 않아요" 로 못 들어오면
-- 이 파일을 SQL Editor 에 붙여넣고 실행하세요. 바로 다시 열립니다.
--
-- 이름·PIN 확인을 아예 하지 않는 상태(명단 기능을 넣기 전 상태)로 돌아갑니다.
-- 수업을 먼저 살려 놓고, 원인은 나중에 찾으면 됩니다.
-- ============================================================================

-- 2026-09-27 부터 학생 키는 PIN 이 드러나지 않는 새 키(k1_…)다.
-- 여기서도 같은 새 키를 돌려줘야 기록이 이어지고, PIN 이 다시 표에 남지 않는다.
create or replace function public.student_login(p_name text, p_phone text)
returns table(ok boolean, student_key text, name text, reason text)
language plpgsql security definer set search_path = public as $$
declare v_key text := private.hkey(public.make_student_key(p_name, p_phone));
begin
  if btrim(coalesce(p_name,'')) = '' or btrim(coalesce(p_phone,'')) !~ '^\d{4}$' then
    return query select false, null::text, null::text, 'bad_input'::text;
    return;
  end if;
  perform private.touch_student(v_key, btrim(p_name));
  return query select true, v_key, btrim(p_name), 'ok_open'::text;
end $$;

grant execute on function public.student_login(text,text) to anon, authenticated;
