-- ============================================================================
-- 지문 넣기 / 고치기 — Supabase SQL Editor 에서 실행 (프로젝트 uxzsleryzpjaoqciyqvs)
--
-- · grp 는 단어장 그룹 이름과 글자 하나까지 같아야 한다.
-- · pid 는 단어 챕터 이름과 같게 쓴다 (예: 1-2510-20). 목록에서 이 순서(ord → pid)로 보인다.
-- · 원문과 해석의 각 문장 앞에 ❶ ❷ ❸ … (또는 ① ② ③ …) 를 붙이고 개수를 맞추면
--   학생이 영어 문장을 누를 때 그 문장의 해석만 펼쳐진다.
--   번호가 없거나 개수가 다르면 [해석 보기] 버튼으로 해석 전체를 보여 준다.
-- · 같은 grp · pid 로 다시 실행하면 덮어쓴다.
-- · $$ … $$ 안에는 작은따옴표(')를 그대로 써도 된다.
-- ============================================================================

-- ⚠ 아래는 형식 예시다. 그대로 실행하면 진짜 1-2510-20 지문을 예시 문장으로 덮어쓴다.
--    /* */ 를 지우기 전에 grp · pid · en · ko 를 실제 내용으로 바꿀 것.
/*
insert into public.passages (grp, pid, ord, en, ko) values
(
  '용산 고1 2026 2학기 기말고사', '1-2510-20', 0,
  $$❶ First sentence of the passage. ❷ Second sentence.$$,
  $$❶ 지문의 첫 문장 해석. ❷ 두 번째 문장 해석.$$
)
on conflict (grp, pid) do update
  set ord = excluded.ord, en = excluded.en, ko = excluded.ko, updated_at = now();
*/

-- 지금 들어 있는 지문 보기
-- select grp, pid, ord, left(en, 40) en, updated_at from public.passages order by grp, ord, pid;

-- 지문 하나 지우기
-- delete from public.passages where grp = '용산 고1 2026 2학기 기말고사' and pid = '1-2510-20';
