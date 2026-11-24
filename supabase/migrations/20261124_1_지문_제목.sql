-- ============================================================================
-- 지문 제목 — Vocab-study 프로젝트(uxzsleryzpjaoqciyqvs) SQL Editor 에서 실행
--
--   passages.title  지문 제목 (없으면 화면에 제목 줄이 나오지 않는다)
--   passage_get     원문 · 해석 · 단어에 더해 title 도 돌려준다
--
-- 지문 88개의 제목도 함께 넣는다 (1-2211-20·22·23·24 는 선생님 원고, 나머지는 Claude 초안).
-- 제목이 비어 있는 지문에만 넣으므로 여러 번 실행해도 안전하고, 나중에 고친 제목을 덮어쓰지 않는다.
-- ============================================================================

alter table public.passages add column if not exists title text;

create or replace function public.passage_get(p_key text, p_grp text, p_pid text) returns json
language sql stable security definer set search_path = '' as $$
  select case
    when not exists (select 1 from private.student_keys s where s.student_key = p_key) then null
    else (select json_build_object('pid', p.pid, 'title', p.title, 'en', p.en, 'ko', p.ko, 'words', p.words)
            from public.passages p where p.grp = p_grp and p.pid = p_pid)
  end;
$$;

revoke all on function public.passage_get(text, text, text) from public;
grant execute on function public.passage_get(text, text, text) to anon, authenticated;

-- 제목 넣기 (비어 있는 것만)
update public.passages p set title = v.title
  from (values
  ($g$용산 고1 2026 2학기 기말고사$g$, $p$1-2510-20$p$, $t$Stay in Touch to Keep Relationships Alive$t$),
  ($g$용산 고1 2026 2학기 기말고사$g$, $p$1-2510-21$p$, $t$The Urban Green Space Paradox$t$),
  ($g$용산 고1 2026 2학기 기말고사$g$, $p$1-2510-22$p$, $t$Understand the Ocean Before We Change It$t$),
  ($g$용산 고1 2026 2학기 기말고사$g$, $p$1-2510-23$p$, $t$Rome: A Melting Pot from the Start$t$),
  ($g$용산 고1 2026 2학기 기말고사$g$, $p$1-2510-24$p$, $t$A Universe Finely Tuned for Life$t$),
  ($g$용산 고1 2026 2학기 기말고사$g$, $p$1-2510-29$p$, $t$Be Humble About Changing Our Diets$t$),
  ($g$용산 고1 2026 2학기 기말고사$g$, $p$1-2510-30$p$, $t$Gen Z Banks on Its Values$t$),
  ($g$용산 고1 2026 2학기 기말고사$g$, $p$1-2510-31$p$, $t$The Myth of Iron-Rich Spinach$t$),
  ($g$용산 고1 2026 2학기 기말고사$g$, $p$1-2510-32$p$, $t$Animals' Number Sense Blurs with Bigger Numbers$t$),
  ($g$용산 고1 2026 2학기 기말고사$g$, $p$1-2510-33$p$, $t$How Thinking Shapes Our Emotions$t$),
  ($g$용산 고1 2026 2학기 기말고사$g$, $p$1-2510-34$p$, $t$Letting Each Animal Flourish in Its Own Way$t$),
  ($g$용산 고1 2026 2학기 기말고사$g$, $p$1-2510-35$p$, $t$Posting Memories Helps Us Keep Them$t$),
  ($g$용산 고1 2026 2학기 기말고사$g$, $p$1-2510-36$p$, $t$Eating Is a Multisensory Experience$t$),
  ($g$용산 고1 2026 2학기 기말고사$g$, $p$1-2510-37$p$, $t$How Children Come to Understand Opposites$t$),
  ($g$용산 고1 2026 2학기 기말고사$g$, $p$1-2510-38$p$, $t$Human Social Life Is Shaped by Nurture$t$),
  ($g$용산 고1 2026 2학기 기말고사$g$, $p$1-2510-39$p$, $t$Fashion: A Tool to Make Us Consume More$t$),
  ($g$용산 고1 2026 2학기 기말고사$g$, $p$1-2510-40$p$, $t$Illusory Progress Motivates Us$t$),
  ($g$용산 고1 2026 2학기 기말고사$g$, $p$1-2510-42$p$, $t$Can AI Limit Our Creativity?$t$),
  ($g$용산 고1 2026 2학기 기말고사$g$, $p$1-2410-36$p$, $t$Social Pressure That Feels Like Our Own Will$t$),
  ($g$용산 고1 2026 2학기 기말고사$g$, $p$1-2410-39$p$, $t$Life as a High-Dimensional System$t$),
  ($g$용산 고1 2026 2학기 기말고사$g$, $p$1-2311-20$p$, $t$Take Charge of Your Own Growth$t$),
  ($g$용산 고1 2026 2학기 기말고사$g$, $p$1-2311-22$p$, $t$The Details That Matter in Fiction$t$),
  ($g$용산 고1 2026 2학기 기말고사$g$, $p$1-2311-23$p$, $t$Oral Health Affects the Whole Body$t$),
  ($g$용산 고1 2026 2학기 기말고사$g$, $p$1-2311-24$p$, $t$Why We Get Bored So Easily$t$),
  ($g$용산 고1 2026 2학기 기말고사$g$, $p$1-2311-38$p$, $t$Losing Crop Diversity Puts Us at Risk$t$),
  ($g$용산 고1 2026 2학기 기말고사$g$, $p$1-2211-20$p$, $t$Give Readers a Reason to Return$t$),
  ($g$용산 고1 2026 2학기 기말고사$g$, $p$1-2211-22$p$, $t$How Frightening News Discourages Action$t$),
  ($g$용산 고1 2026 2학기 기말고사$g$, $p$1-2211-23$p$, $t$Melting Ice and Longer Days$t$),
  ($g$용산 고1 2026 2학기 기말고사$g$, $p$1-2211-24$p$, $t$Stay Open to Other Viewpoints$t$),
  ($g$용산 고1 2026 2학기 기말고사$g$, $p$1-2211-32$p$, $t$Innovation Lets Us Work for Each Other$t$),
  ($g$용산 고1 2026 2학기 기말고사$g$, $p$1-2211-38$p$, $t$Language Is Just One Part of the Mind$t$),
  ($g$용산 고1 2026 2학기 기말고사$g$, $p$교과서 3-1$p$, $t$Tigers in Korean Culture$t$),
  ($g$용산 고1 2026 2학기 기말고사$g$, $p$교과서 3-2$p$, $t$Tigers in Korean Folktales$t$),
  ($g$용산 고1 2026 2학기 기말고사$g$, $p$교과서 3-3$p$, $t$The Tiger as a Symbol of Korea$t$),
  ($g$용산 고1 2026 2학기 기말고사$g$, $p$교과서 4-1$p$, $t$Nature's Solutions to Environmental Problems$t$),
  ($g$용산 고1 2026 2학기 기말고사$g$, $p$교과서 4-2$p$, $t$Mealworms That Help Break Down Plastic$t$),
  ($g$용산 고1 2026 2학기 기말고사$g$, $p$교과서 4-3$p$, $t$Cleaning Polluted Soil with Willow Trees$t$),
  ($g$용산 고1 2026 2학기 기말고사$g$, $p$교과서 4-4$p$, $t$A Second Life for Used Coffee Grounds$t$),
  ($g$용산 고2 2026 2학기 기말고사$g$, $p$2-2510-33$p$, $t$Glass Windows as Tools of Royal Power$t$),
  ($g$용산 고2 2026 2학기 기말고사$g$, $p$2-2510-34$p$, $t$The Spiral of Silence$t$),
  ($g$용산 고2 2026 2학기 기말고사$g$, $p$2-2510-35$p$, $t$Units of Measure Are Arbitrary Choices$t$),
  ($g$용산 고2 2026 2학기 기말고사$g$, $p$2-2510-36$p$, $t$How Sea Creatures Handle Salt$t$),
  ($g$용산 고2 2026 2학기 기말고사$g$, $p$2-2510-37$p$, $t$Moths and Butterflies: More Alike Than Different$t$),
  ($g$용산 고2 2026 2학기 기말고사$g$, $p$2-2510-38$p$, $t$Active and Inactive Wildlife Management$t$),
  ($g$용산 고2 2026 2학기 기말고사$g$, $p$2-2510-39$p$, $t$From Built-In Waste to Products as a Service$t$),
  ($g$용산 고2 2026 2학기 기말고사$g$, $p$2-2510-40$p$, $t$Nature Won't Fit Our Fixed View of Time$t$),
  ($g$용산 고2 2026 2학기 기말고사$g$, $p$2-2410-20$p$, $t$What It Means to Be Mathematically Literate$t$),
  ($g$용산 고2 2026 2학기 기말고사$g$, $p$2-2410-21$p$, $t$No Pill for Instant Virtue$t$),
  ($g$용산 고2 2026 2학기 기말고사$g$, $p$2-2410-22$p$, $t$Measurement Depends on Theory$t$),
  ($g$용산 고2 2026 2학기 기말고사$g$, $p$2-2410-23$p$, $t$Pain Keeps Us in Balance$t$),
  ($g$용산 고2 2026 2학기 기말고사$g$, $p$2-2410-24$p$, $t$The Endless Itch to Upgrade$t$),
  ($g$용산 고2 2026 2학기 기말고사$g$, $p$2-2410-29$p$, $t$Finding Out What Animals Want$t$),
  ($g$용산 고2 2026 2학기 기말고사$g$, $p$2-2410-30$p$, $t$Why Birds Breed in Seasons$t$),
  ($g$용산 고2 2026 2학기 기말고사$g$, $p$2-2410-31$p$, $t$Knowing Your Resources Boosts Creativity$t$),
  ($g$용산 고2 2026 2학기 기말고사$g$, $p$2-2410-32$p$, $t$Every Translation Is a Crowd Translation$t$),
  ($g$용산 고2 2026 2학기 기말고사$g$, $p$2-2410-33$p$, $t$Reading as a Family of Activities$t$),
  ($g$용산 고2 2026 2학기 기말고사$g$, $p$2-2410-34$p$, $t$Weber's Law: Noticing Differences$t$),
  ($g$용산 고2 2026 2학기 기말고사$g$, $p$2-2410-35$p$, $t$The Tragedy of the Commons$t$),
  ($g$보성여고 2학년 2학기 기말고사$g$, $p$3-5$p$, $t$See Yourself as You Truly Are$t$),
  ($g$보성여고 2학년 2학기 기말고사$g$, $p$3-6$p$, $t$Great Things Take Time$t$),
  ($g$보성여고 2학년 2학기 기말고사$g$, $p$3-7$p$, $t$Agriculture and Its Challenges$t$),
  ($g$보성여고 2학년 2학기 기말고사$g$, $p$3-8$p$, $t$Focus on Actions, Not Personality$t$),
  ($g$보성여고 2학년 2학기 기말고사$g$, $p$4-5$p$, $t$From a Brick on the Pedal to Personalized Medicine$t$),
  ($g$보성여고 2학년 2학기 기말고사$g$, $p$4-6$p$, $t$Art That Challenges Us Can Change Us$t$),
  ($g$보성여고 2학년 2학기 기말고사$g$, $p$4-7$p$, $t$Fungi Protect Forest Diversity$t$),
  ($g$보성여고 2학년 2학기 기말고사$g$, $p$4-8$p$, $t$How North America Lost Its Food Culture$t$),
  ($g$보성여고 2학년 2학기 기말고사$g$, $p$5-5$p$, $t$The Baby Bottle: An Overlooked Time-Saver$t$),
  ($g$보성여고 2학년 2학기 기말고사$g$, $p$5-6$p$, $t$Public Clocks and Economic Progress$t$),
  ($g$보성여고 2학년 2학기 기말고사$g$, $p$5-7$p$, $t$Positive Fantasies Drain Our Energy$t$),
  ($g$보성여고 2학년 2학기 기말고사$g$, $p$5-8$p$, $t$AI Makes Emotional Intelligence More Valuable$t$),
  ($g$보성여고 2학년 2학기 기말고사$g$, $p$6-5$p$, $t$Diversity Makes Science More Objective$t$),
  ($g$보성여고 2학년 2학기 기말고사$g$, $p$6-6$p$, $t$What Empathy Means in Business$t$),
  ($g$보성여고 2학년 2학기 기말고사$g$, $p$6-7$p$, $t$How Shills Made Shopping Carts Popular$t$),
  ($g$보성여고 2학년 2학기 기말고사$g$, $p$6-8$p$, $t$The Upside of Cooking Less$t$),
  ($g$보성여고 2학년 2학기 기말고사$g$, $p$7-5$p$, $t$Make Deadlines Feel Close$t$),
  ($g$보성여고 2학년 2학기 기말고사$g$, $p$7-6$p$, $t$The Pressure to Always Be Reachable$t$),
  ($g$보성여고 2학년 2학기 기말고사$g$, $p$7-7$p$, $t$Should Care Robots Deceive Us?$t$),
  ($g$보성여고 2학년 2학기 기말고사$g$, $p$7-8$p$, $t$Vote with Your Wallet$t$),
  ($g$보성여고 2학년 2학기 기말고사$g$, $p$11-7$p$, $t$Lectins: Plants' Hidden Weapon$t$),
  ($g$보성여고 2학년 2학기 기말고사$g$, $p$11-8$p$, $t$Rethinking Sell-By Dates$t$),
  ($g$보성여고 2학년 2학기 기말고사$g$, $p$12-7$p$, $t$Technology Reshapes Privacy$t$),
  ($g$보성여고 2학년 2학기 기말고사$g$, $p$12-8$p$, $t$Why Caffeine Affects People Differently$t$),
  ($g$보성여고 2학년 2학기 기말고사$g$, $p$13-7$p$, $t$Reactance: Wanting What We Can't Have$t$),
  ($g$보성여고 2학년 2학기 기말고사$g$, $p$13-8$p$, $t$The Sunk Cost Fallacy$t$),
  ($g$보성여고 2학년 2학기 기말고사$g$, $p$14-7$p$, $t$Financial Markets Separate Earning from Spending$t$),
  ($g$보성여고 2학년 2학기 기말고사$g$, $p$14-8$p$, $t$Not Everything That Counts Can Be Counted$t$),
  ($g$보성여고 2학년 2학기 기말고사$g$, $p$15-7$p$, $t$Moral Character Can Still Be Taught$t$),
  ($g$보성여고 2학년 2학기 기말고사$g$, $p$15-8$p$, $t$Weak Rulers, Strong Democracy$t$)
  ) as v(grp, pid, title)
 where p.grp = v.grp and p.pid = v.pid and p.title is null;

-- REST(PostgREST)가 새 열을 바로 보도록
notify pgrst, 'reload schema';

-- 확인: 지문 88 · 제목 열 1 · 제목 있는 지문 88 이 나오면 성공
select
  (select count(*) from public.passages) as "지문",
  (select count(*) from information_schema.columns
    where table_schema = 'public' and table_name = 'passages' and column_name = 'title') as "제목 열",
  (select count(*) from public.passages where title is not null) as "제목 있는 지문";
