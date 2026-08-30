/**
 * judge-meaning — 주관식 답안 의미 판정 (Gemini Flash)
 *
 * 브라우저에서 규칙 기반으로 채점해 본 뒤, "비슷함/오답"으로 나온 것만 이 함수로 넘어온다.
 * 정답으로 이미 판정된 답은 여기까지 오지 않으므로 호출 건수가 적다.
 *
 * 배포:
 *   supabase secrets set GEMINI_API_KEY=...
 *   supabase functions deploy judge-meaning
 *
 * 선택 환경변수:
 *   GEMINI_MODEL    사용할 모델 (기본: gemini-2.5-flash)
 *   ALLOWED_ORIGIN  CORS 허용 도메인 (기본: * )
 */

const API_KEY = Deno.env.get("GEMINI_API_KEY") ?? "";
const ALLOWED_ORIGIN = Deno.env.get("ALLOWED_ORIGIN") ?? "*";

/* 지정 모델이 없으면 순서대로 시도한다 (모델 이름이 바뀌어도 죽지 않도록).

   2026-08 측정 기록 — 처음 보는 단어 16개(파생명사 함정 8 + 진짜 두 품사 8)로 잰 정확도:
     gemini-2.5-flash       13/16   608ms   ← 가장 정확해서 맨 앞에 둔다
     gemini-3.5-flash       12/16   830ms
     gemini-3.7-flash       11/16  2617ms   (느리고 응답이 잘림)
     gemini-3.1-flash-lite  10/16   526ms   (싸고 빠르지만 가장 부정확)
   gemini-2.5-flash-lite 와 gemini-2.0-flash-lite 는 구글이 내려서 404 다.
   체인 앞에 두면 채점할 때마다 헛호출을 두 번 하고 시작하므로 뺐다. */
const MODELS = [
  Deno.env.get("GEMINI_MODEL"),
  "gemini-2.5-flash",
  "gemini-3.1-flash-lite",
  "gemini-3.5-flash",
].filter(Boolean) as string[];

const CORS = {
  "Access-Control-Allow-Origin": ALLOWED_ORIGIN,
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });

/** 학생 답안이 표준 답안과 같은 뜻인지 묻는 프롬프트 */
function buildPrompt(w: string, pos: string, meaning: string, alt: string, answer: string, exclude: string, formMismatch: boolean, posLocked: boolean) {
  return `너는 영어 단어 시험의 채점자다. 학생이 쓴 우리말 뜻이 정답인지 판단해라.
(교재의 뜻과 글자까지 같은 답은 이미 정답 처리되어 여기 오지 않는다. 너는 교재에 없는
표현을 판단한다.)

영어 단어: ${w}${pos ? `\n지정된 품사: ${pos}${posLocked ? " — 이 품사의 뜻만 정답으로 인정한다" : ""}` : ""}
교재의 뜻: ${meaning}${alt ? `\n추가로 인정된 답안: ${alt}` : ""}${exclude ? `\n인정하지 않는 뜻: ${exclude}` : ""}
학생 답안: ${answer}${formMismatch ? "\n\n※ 학생 답안의 품사·형태가 교재의 뜻과 다르다. 규칙 2로 판단해라 — 그 단어가 사전에서 답안의 품사로 그 뜻을 가지면 correct, 아니면 pos 다." : ""}

채점 규칙 — 번호 순서대로 적용하고, 앞 규칙에서 판정이 나면 뒤는 보지 않는다.

[규칙 1 — 제외·지정]
"인정하지 않는 뜻" 과 같은 뜻이면 wrong. 문제가 그 뜻은 빼라고 지정한 것이다.
"지정된 품사" 가 있으면 그 품사의 뜻만 정답 후보다. 다른 품사면 사전에 있어도 pos.

[규칙 2 — 품사는 엄격하게]
· 답에 조사가 붙으면 pos. 뜻이 "농구" 인데 "농구의", "농구와" 라고 쓰면 pos.
· 품사가 지정되지 않았다면, 교재의 품사가 아니어도 **그 단어가 사전에서 실제로
  가지는 품사의 뜻**이면 정답 후보다. 어느 방향이든 같다.
  예: address — "주소", "연설하다", "다루다", "말을 걸다" 모두 correct.
  예: orbit — 교재의 뜻이 "궤도를 돌다"(동사) 여도, 사전에 명사 "궤도" 가 있으므로
      "궤도" 는 correct. (acquire 의 "획득" 과 다르다 — "획득" 은 acquire 의
      사전 뜻이 아니지만, "궤도" 는 orbit 의 사전 뜻이다. 기준은 형태가 아니라
      사전에 실려 있는가다.)
· 그 단어가 사전에서 가지지 않는 품사·형태는 pos. 의미가 통해도 안 된다.
  예: acquire 는 동사뿐 → 명사형 "획득" 은 pos
  예: atom 은 명사뿐 → "원자이다" 는 pos
  예: in summary 는 부사구 → 명사 "요약" 은 pos
  예: less than 은 "~ 미만의" 라는 관형 표현 → 서술형 "~보다 작다" 는 pos
  예: momentary 는 형용사 "순간적인" 뿐 → 부사형 "순간적으로" 는 pos
      (그건 momentarily 의 뜻이다. 관형형과 부사형은 다른 품사다)
· 표제어가 두 낱말 이상인 구(句)면, 그 구 전체의 품사만 본다.
  구를 이루는 낱낱의 단어가 가진 품사는 근거가 되지 않는다.
  구는 대개 품사가 하나뿐이므로 "사전에 다른 품사가 있다" 는 구제가 없다.
  교재의 뜻에 "~에", "~와" 같은 자리표시가 있으면 그 뜻은 구다.
  예: in addition to 는 전치사구 "~에 더하여" → 동사 "더하다" 는 pos.
      (addition·add 가 명사·동사인 것은 근거가 되지 않는다.)
  예: combined with 는 부사구 "~와 결합되어" → "결합되다" 는 pos.
  예: through the night 는 부사구 "밤새도록" → "밤새다" 는 pos.
품사 문제는 correct 아니면 pos 다. close 를 쓰지 마라.

[규칙 3 — 같은 뜻의 다른 표현은 인정]
교재의 뜻과 표현이 달라도 같은 의미면 correct. 사전마다 다른 번역, 유의어,
더 풀어 쓴 설명을 모두 포함한다.
예: run(달리다) — "뛰다", "뜀박질하다", "내달리다", "질주하다", "냅다 뛰다" 모두 correct.

[규칙 4 — 사전·통용 뜻은 인정]
교재에 없어도 사전에 실려 있거나 일반적으로 통용되는 그 단어의 뜻이면 correct.
지엽적인 뜻이라도 인정한다.
예: offer(제의[제안]하다) — "할인", "(금전적) 제의", "제의한 액수", "제의", "제안",
    "(하느님께) 바치다", "내놓다" 모두 correct.

[규칙 5 — 다른 단어의 뜻은 오답]
그 단어의 뜻이 아니면 wrong. 특히 혼동하기 쉬운 다른 영어 단어의 뜻을 적은 경우
(예: subsequently 에 "따라서" — consequently 의 뜻)는 반드시 wrong.

close 는 뜻이 겹치지만 범위가 지나치게 넓거나 좁아 확신이 서지 않을 때만 쓴다.
확신이 없으면 correct 를 주지 마라.

reason 은 학생에게 그대로 보여 줄 한국어 한 문장, 35자 이내, 존댓말.
correct 면 근거를(예: "동사로도 쓰여요"), pos 면 어떤 형태로 써야 하는지 적어라.`;
}



/* ---- 사전 품사 조회 ----
   "hibernate 가 명사로도 쓰이나" 는 판단이 아니라 사실이다.
   그런데 긴 한국어 채점 프롬프트 안에서 함께 물으면 모델이 자주 틀린다
   (측정: 처음 보는 단어 16개 중 13개만 정답).
   그래서 품사만 영어로 따로, 좁게 묻는다 (같은 모델로 28/28).
   단어의 품사는 변하지 않으므로 한 번 물어보고 기억해 둔다. */
const POS_SCHEMA = {
  type: "OBJECT",
  properties: {
    partsOfSpeech: {
      type: "ARRAY",
      items: { type: "STRING", enum: ["noun", "verb", "adjective", "adverb", "preposition", "conjunction", "other"] },
    },
    nounForm: { type: "STRING" },
  },
  required: ["partsOfSpeech", "nounForm"],
};

function posPrompt(w: string) {
  return `In a standard English dictionary, what parts of speech does the headword "${w}" itself have?
List ONLY parts of speech that "${w}" has as its own headword entry.
Do NOT include parts of speech that belong to derived or related words.
Example: "hibernate" is verb only — the noun is "hibernation", a different headword.
Example: "record" is both noun and verb — the same spelling is both headwords.
If the word is not a noun, put its noun form (a different word) in nounForm; otherwise leave nounForm empty.`;
}

const posCache = new Map<string, { pos: string[]; nounForm: string }>();

async function lookupPos(word: string): Promise<{ pos: string[]; nounForm: string } | null> {
  const key = word.toLowerCase().trim();
  if (posCache.has(key)) return posCache.get(key)!;
  for (const model of MODELS) {
    for (const auth of authOrder()) {
      let res: Response;
      try {
        res = await callRaw(model, posPrompt(word), POS_SCHEMA, auth);
      } catch { continue; }
      if (!res.ok) continue;
      const data = await res.json();
      const text = data?.candidates?.[0]?.content?.parts?.[0]?.text ?? "";
      try {
        const o = JSON.parse(text);
        if (Array.isArray(o.partsOfSpeech) && o.partsOfSpeech.length) {
          const out = { pos: o.partsOfSpeech as string[], nounForm: String(o.nounForm ?? "") };
          posCache.set(key, out);
          return out;
        }
      } catch { /* 다음 조합으로 */ }
    }
  }
  return null;                       // 조회 실패 — 예전처럼 AI 판정에 맡긴다
}

/* 학생이 쓴 품사가 사전에 없으면 그 자리에서 오답이다.
   있으면 뜻까지 맞는지는 아래 judge() 가 마저 본다. */
function posHintKo(pos: string[]): string {
  const t: Record<string, string> = { noun: "명사", verb: "동사", adjective: "형용사",
    adverb: "부사", preposition: "전치사", conjunction: "접속사" };
  return pos.map((p) => t[p] || p).join("·");
}

const SCHEMA = {
  type: "OBJECT",
  properties: {
    verdict: { type: "STRING", enum: ["correct", "close", "wrong", "pos"] },
    reason: { type: "STRING" },
  },
  required: ["verdict", "reason"],
};

/* 인증 방식 — 키 종류에 따라 받는 방식이 다르다.
   AIza… (기존 API 키)  : x-goog-api-key 헤더
   AQ.…  (신형 인증 키)  : Authorization: Bearer
   어느 쪽이 될지 확실치 않으므로 순서대로 시도하고, 통한 방식을 기억해 둔다. */
type Auth = "header" | "bearer" | "query";
let workingAuth: Auth | null = null;

function authOrder(): Auth[] {
  if (workingAuth) return [workingAuth, ...(["header", "bearer", "query"] as Auth[]).filter((a) => a !== workingAuth)];
  return API_KEY.startsWith("AQ.")
    ? ["bearer", "header", "query"]
    : ["header", "query", "bearer"];
}

/* 스키마를 바꿔 가며 부를 수 있는 최소 호출 — 품사 조회와 채점이 함께 쓴다 */
async function callRaw(model: string, prompt: string, schema: unknown, auth: Auth, omitThinkingConfig = false) {
  const body: Record<string, unknown> = {
    contents: [{ role: "user", parts: [{ text: prompt }] }],
    generationConfig: {
      temperature: 0,
      maxOutputTokens: 120,
      responseMimeType: "application/json",
      responseSchema: schema,
      ...(omitThinkingConfig ? {} : { thinkingConfig: { thinkingBudget: 0 } }),
    },
  };
  let url = `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`;
  const headers: Record<string, string> = { "Content-Type": "application/json" };
  if (auth === "header") headers["x-goog-api-key"] = API_KEY;
  else if (auth === "bearer") headers["Authorization"] = `Bearer ${API_KEY}`;
  else url += `?key=${encodeURIComponent(API_KEY)}`;
  return await fetch(url, { method: "POST", headers, body: JSON.stringify(body), signal: AbortSignal.timeout(8000) });
}

async function callGemini(model: string, prompt: string, auth: Auth, omitThinkingConfig: boolean) {
  const body: Record<string, unknown> = {
    contents: [{ role: "user", parts: [{ text: prompt }] }],
    generationConfig: {
      temperature: 0,
      maxOutputTokens: 120,
      responseMimeType: "application/json",
      responseSchema: SCHEMA,
      ...(omitThinkingConfig ? {} : { thinkingConfig: { thinkingBudget: 0 } }),
    },
  };
  let url = `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`;
  const headers: Record<string, string> = { "Content-Type": "application/json" };
  if (auth === "header") headers["x-goog-api-key"] = API_KEY;
  else if (auth === "bearer") headers["Authorization"] = `Bearer ${API_KEY}`;
  else url += `?key=${encodeURIComponent(API_KEY)}`;

  return await fetch(url, {
    method: "POST",
    headers,
    body: JSON.stringify(body),
    signal: AbortSignal.timeout(8000),
  });
}

type Judged = { verdict: string; reason: string; model: string; auth: Auth };

/** 모델 × 인증방식 × thinking 옵션을 필요한 만큼만 시도한다 */
async function judge(prompt: string): Promise<{ ok: Judged } | { err: string }> {
  const deadModels = new Set<string>();
  const deadAuths = new Set<Auth>();
  let lastErr = "설정 오류";

  for (const model of MODELS) {
    if (deadModels.has(model)) continue;
    for (const auth of authOrder()) {
      if (deadAuths.has(auth) || deadModels.has(model)) continue;
      for (const omitThinkingConfig of [false, true]) {
        let res: Response;
        try {
          res = await callGemini(model, prompt, auth, omitThinkingConfig);
        } catch (e) {
          lastErr = `${model}/${auth} ${e instanceof Error ? e.message : String(e)}`;
          deadModels.add(model);
          break;
        }
        if (res.ok) {
          const data = await res.json();
          const text = data?.candidates?.[0]?.content?.parts?.[0]?.text ?? "";
          let out: { verdict?: string; reason?: string } = {};
          try { out = JSON.parse(text); } catch { /* 아래에서 처리 */ }
          if (!["correct", "close", "wrong", "pos"].includes(out.verdict ?? "")) {
            lastErr = `${model} 응답 형식 오류: ${text.slice(0, 120)}`;
            continue;                       // thinking 옵션을 바꿔 한 번 더
          }
          workingAuth = auth;               // 통한 인증 방식을 기억
          return { ok: {
            verdict: out.verdict!,
            reason: String(out.reason ?? "").slice(0, 80),
            model, auth,
          } };
        }
        const errText = await res.text();
        lastErr = `${model}/${auth} ${res.status} ${errText.slice(0, 200)}`;
        if (res.status === 401 || res.status === 403) { deadAuths.add(auth); break; }
        if (res.status === 404) { deadModels.add(model); break; }
        if (res.status === 400 && /thinking/i.test(errText) && !omitThinkingConfig) continue;
        deadModels.add(model);
        break;
      }
    }
  }
  return { err: lastErr };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (!API_KEY) return json({ error: "GEMINI_API_KEY 가 설정되지 않았습니다." }, 500);

  // 배포 직후 키가 살아 있는지 확인하는 자체 점검
  //   curl -H "Authorization: Bearer <anon key>" ".../judge-meaning?selftest=1"
  if (req.method === "GET" && new URL(req.url).searchParams.has("selftest")) {
    const r = await judge(buildPrompt("subsequently", "부", "그 뒤에, 나중에", "", "추후에", "", false, false));
    if ("ok" in r) {
      return json({
        ok: true,
        message: "AI 채점이 정상 동작합니다.",
        keyType: API_KEY.startsWith("AQ.") ? "AQ (신형 인증 키)" : "AIza (기존 API 키)",
        model: r.ok.model,
        auth: r.ok.auth,
        sample: { answer: "추후에", verdict: r.ok.verdict, reason: r.ok.reason },
      });
    }
    return json({ ok: false, message: "Gemini 호출에 실패했습니다.", detail: r.err }, 502);
  }

  if (req.method !== "POST") return json({ error: "POST only" }, 405);

  let payload: Record<string, unknown>;
  try {
    payload = await req.json();
  } catch {
    return json({ error: "잘못된 요청" }, 400);
  }

  const str = (v: unknown, max: number) => String(v ?? "").trim().slice(0, max);
  const word = str(payload.word, 60);
  const pos = str(payload.pos, 10);
  const meaning = str(payload.meaning, 300);
  const alt = str(payload.alt, 300);
  const exclude = str(payload.exclude, 200);
  const answer = str(payload.answer, 80);
  const formMismatch = payload.form_mismatch === true || payload.form_mismatch === "true";
  const posLocked = payload.pos_locked === true || payload.pos_locked === "true";
  // 학생이 쓴 답의 품사를 영어 사전 기준으로 옮긴 것 (브라우저가 보낸다)
  const answerPosEn = Array.isArray(payload.answer_pos_en)
    ? (payload.answer_pos_en as unknown[]).map((x) => String(x)).slice(0, 6)
    : [];

  // 단어 채점 이외의 용도로 쓰이지 않도록 최소한의 형태 검사
  if (!word || !meaning || !answer) return json({ error: "word, meaning, answer 필요" }, 400);
  if (!/[가-힣]/.test(answer)) return json({ verdict: "wrong", reason: "한국어 뜻이 아닙니다." });

  /* 품사가 어긋난 답은 먼저 사전에 물어본다.
     그 영어 단어가 학생이 쓴 품사로 쓰이지 않으면 그 자리에서 오답이다
     (hibernate 에 "동면" — 명사는 hibernation 이라 hibernate 의 뜻이 아니다).
     사전에 그 품사가 있으면 뜻까지 맞는지는 아래 judge() 가 마저 본다. */
  if (formMismatch && !posLocked && answerPosEn.length && /^[A-Za-z][A-Za-z'’-]*$/.test(word)) {
    const dict = await lookupPos(word);
    if (dict && !dict.pos.some((p) => answerPosEn.includes(p))) {
      const reason = dict.nounForm && answerPosEn.includes("noun")
        ? `그 뜻은 ${dict.nounForm} 의 뜻이에요. ${posHintKo(dict.pos)}로 써 주세요.`
        : `${word} 는 ${posHintKo(dict.pos)}로만 쓰여요.`;
      return json({ verdict: "pos", reason: reason.slice(0, 80), via: "dictionary", dictPos: dict.pos });
    }
  }

  const r = await judge(buildPrompt(word, pos, meaning, alt, answer, exclude, formMismatch, posLocked));
  if ("ok" in r) return json(r.ok);
  return json({ error: "판정 실패", detail: r.err }, 502);
});
