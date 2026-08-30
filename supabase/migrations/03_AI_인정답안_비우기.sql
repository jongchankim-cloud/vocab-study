-- ============================================================================
-- 예전 규칙으로 저장된 AI 인정 답안 비우기
--
-- 채점 규칙을 바꿔도, 예전 규칙으로 이미 "정답 인정" 되어 저장된 답은
-- 채점을 우회해서 그대로 정답 처리된다 (예: in addition to ← 더하다).
-- 그래서 규칙을 바꾼 뒤에는 한 번 비워 줘야 한다.
--
-- 관리 화면의 [전체 비우기] 버튼과 같은 동작이다.
-- 선생님이 직접 승인한 답안은 지우지 않는다.
-- ============================================================================

with a as (
  delete from public.progress
   where student_key = '__ALIAS_AI__' and kind = 'alias' returning 1
), b as (
  delete from public.progress where kind = 'alias_ai' returning 1
)
select (select count(*) from a) as "공유본_삭제",
       (select count(*) from b) as "개인기록_삭제";
