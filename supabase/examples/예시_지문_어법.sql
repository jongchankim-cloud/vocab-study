-- ============================================================================
-- 예시 데이터 — 화면 틀을 보여 주기 위한 것 (실제 시험 지문이 아니다)
-- 실제 본문을 받으면 이 형식으로 넣는다.
--
-- 어법: q 에서 틀린 부분을 [ ] 로 감싼다 → 학생 화면에 밑줄로 보인다.
--       a 는 정답 목록. 여러 개면 array['go', 'should go'] 처럼.
-- ============================================================================

insert into public.passages(grp, pid, ord, en, ko) values
('용산 고1 2026 2학기 기말고사', '1-2509-20', 1,
'Many teachers overlook the first few minutes of class. Students arrive, find their seats, and wait for something to happen. Yet these opening minutes can set the tone for the rest of the lesson.

A brief routine at the start of class, such as a short review question on the board, gives students a clear task. It also makes the transition from the hallway to learning much smoother. In summary, a well-planned beginning is one of the most effective habits a teacher can establish.',
'많은 교사들이 수업의 처음 몇 분을 간과한다. 학생들은 도착해서 자리를 찾고, 무언가 일어나기를 기다린다. 그러나 이 도입부 몇 분은 수업의 나머지 부분의 분위기를 조성할 수 있다.

칠판에 적힌 짧은 복습 질문과 같은, 수업 시작 때의 간단한 정례 활동은 학생들에게 분명한 과제를 준다. 그것은 또한 복도에서 학습으로의 전환을 훨씬 더 순조롭게 만든다. 요약하자면, 잘 계획된 시작은 교사가 정착시킬 수 있는 가장 효과적인 습관 중 하나이다.'),
('용산 고1 2026 2학기 기말고사', '1-2509-21', 2,
'Every atom in your body has a long history. The carbon you exhale today may once have been part of a tree, a dinosaur, or a distant star. Atoms are not destroyed; they cycle through the universe on a grand scale.

In this sense, we are only temporary caretakers of the matter that makes us up. When we are gone, our atoms will continue their journey, becoming part of something new.',
'당신 몸의 모든 원자는 긴 역사를 가지고 있다. 오늘 당신이 내쉬는 탄소는 한때 나무, 공룡, 또는 먼 별의 일부였을지도 모른다. 원자는 파괴되지 않으며, 거대한 규모로 우주를 순환한다.

이런 의미에서 우리는 우리를 구성하는 물질의 임시 관리인일 뿐이다. 우리가 사라지면 우리의 원자는 여정을 계속하여 새로운 무언가의 일부가 될 것이다.')
on conflict (grp, pid) do update set ord = excluded.ord, en = excluded.en, ko = excluded.ko, updated_at = now();

delete from public.grammar_items where grp = '용산 고1 2026 2학기 기말고사' and pid in ('1-2509-20', '1-2509-21');
insert into public.grammar_items(grp, pid, ord, q, a, note) values
('용산 고1 2026 2학기 기말고사', '1-2509-20', 1, 'Many teachers [overlooks] the first few minutes of class.', array['overlook'], '주어 Many teachers 가 복수 → overlook'),
('용산 고1 2026 2학기 기말고사', '1-2509-20', 2, 'Students arrive, find their seats, and [waiting] for something to happen.', array['wait'], 'arrive, find 와 병렬 → 동사원형 wait'),
('용산 고1 2026 2학기 기말고사', '1-2509-20', 3, 'It also makes the transition from the hallway to learning much [smoothly].', array['smoother'], 'make + 목적어 + 형용사(목적격 보어) → smoother'),
('용산 고1 2026 2학기 기말고사', '1-2509-20', 4, 'A well-planned beginning is one of the most effective [habit] a teacher can establish.', array['habits'], 'one of the + 복수명사'),
('용산 고1 2026 2학기 기말고사', '1-2509-21', 1, 'The carbon you exhale today may once [be] part of a tree.', array['have been'], '과거에 대한 추측 → may have p.p.'),
('용산 고1 2026 2학기 기말고사', '1-2509-21', 2, 'We are only temporary caretakers of the matter [what] makes us up.', array['that', 'which'], '선행사 the matter 가 있음 → that / which');
