-- ============================================================================
-- 비상용 — 2026-09-27 보안 작업을 되돌린다
--
-- [A] 표 잠금(2단계)만 되돌리기 — 대부분은 이것으로 충분하다
--     학생 기록 저장이 갑자기 안 되거나, 옛 화면을 다시 올려야 할 때.
--     학생 키는 새 키(k1_…) 그대로 두므로 기록은 끊기지 않는다.
--     (옛 화면도 student_login 이 주는 키를 그대로 쓴다)
--
-- [B] 학생 키까지 이름_PIN 으로 되돌리기 — 정말 필요할 때만
--     PIN 이 다시 공개 표에 드러난다. [A] 로 해결되지 않을 때만 쓴다.
--     [B] 를 쓰면 반드시 [A] 도 함께 실행하고, 옛 index.html 을 다시 올려야 한다.
--
-- SQL Editor 에 필요한 부분만 붙여넣고 실행하세요.
-- ============================================================================

-- ---------------- [A] 표 잠금 되돌리기 ----------------
grant all on public.progress, public.students, public.app_config to anon, authenticated;
grant usage, select, update on sequence public.progress_id_seq to anon, authenticated;
drop policy if exists "anon can read"   on public.progress;
drop policy if exists "anon can insert" on public.progress;
drop policy if exists "anon can update" on public.progress;
drop policy if exists "anon can delete" on public.progress;
create policy "anon can read"   on public.progress for select using (true);
create policy "anon can insert" on public.progress for insert with check (true);
create policy "anon can update" on public.progress for update using (true) with check (true);
create policy "anon can delete" on public.progress for delete using (true);
grant execute on function public.roster_list(), public.roster_add(text, text, text),
                          public.roster_remove(text) to anon, authenticated;
-- (students · app_config 는 원래도 정책이 없어 잠겨 있었다 — 권한만 원래대로)


-- ---------------- [B] 학생 키를 이름_PIN 으로 되돌리기 ----------------
-- 필요할 때만 아래 /* */ 를 지우고 실행한다.
/*
-- 1) 기록의 키를 백업에 있던 원래 키로 되돌린다 (그 뒤에 새로 생긴 기록도 함께 옮겨진다)
update public.progress p
   set student_key = o.old_key
  from (select distinct student_key as old_key
          from private.progress_backup_20260927
         where student_key !~ '^(__|k1_)') o
 where p.student_key = private.hkey(o.old_key);

-- 2) 예외 명단을 백업으로 되돌린다
delete from public.students;
insert into public.students select * from private.students_backup_20260927;

-- 3) student_login 을 예전 것으로 — supabase/migrations/20260823_login_via_score_system.sql 을 다시 실행
*/
