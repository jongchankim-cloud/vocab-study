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
 *   GEMINI_MODEL    사용할 모델 (기본: gemini-2.5-flash-lite)
 *   ALLOWED_ORIGIN  CORS 허용 도메인 (기본: * )
 */

const API_KEY = Deno.env.get("GEMINI_API_KEY") ?? "";
const ALLOWED_ORIGIN = Deno.env.get("ALLOWED_ORIGIN") ?? "*";

// 지정 모델이 없으면 순서대로 시도한다 (모델 이름이 바뀌어도 죽지 않도록)
const MODELS = [
  Deno.env.get("GEMINI_MODEL"),
  "gemini-2.5-flash-lite",
  "gemini-2.0-flash-lite",
  "gemini-2.5-flash",
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
function buildPrompt(w: string, pos: string, meaning: string, alt: string, answer: string, exclude: string, formMismatch: boolean) {
  return `너는 영어 단어 시험의 채점자다. 학생이 쓴 우리말 뜻이 정답인지 판단해라.
학원 시험이므로 관대함보다 정확함이 중요하다. 확신이 없으면 correct 를 주지 마라.

영어 단어: ${w}${pos ? ` (${pos})` : ""}
교재의 뜻: ${meaning}${alt ? `\n추가로 인정된 답안: ${alt}` : ""}${exclude ? `\n인정하지 않는 뜻: ${exclude}` : ""}
학생 답안: ${answer}${formMismatch ? "\n\n※ 학생 답안의 품사·형태가 교재의 뜻과 다르다. 2단계를 특히 엄격하게 판단해라." : ""}

아래 순서대로 판단해라. 앞 단계에서 판정이 나면 뒤 단계는 보지 않는다.

[1단계 — 제외된 뜻]
"인정하지 않는 뜻" 과 같은 뜻이면, 사전에 있는 뜻이어도 wrong.
문제에서 그 뜻은 빼고 답하라고 지정한 것이다.

[2단계 — 품사·형태]
학생 답안이 나타내는 품사가, 그 영어 단어가 사전에서 실제로 가지는 품사인지 본다.
· 사전에 그 품사로 그 뜻이 실려 있다 → 3단계로.
  (예: demand 는 교재에 "요구"(명사) 만 있어도 사전에 동사 "요구하다" 가 있다 → 통과)
· 사전에 없는 품사·형태다 → 뜻이 아무리 비슷해도 pos. 의미가 통한다는 이유로
  correct 를 주면 안 된다.
  예: acquire 는 동사뿐 → 명사형 "획득" 은 pos
  예: in summary 는 부사구 → 명사 "요약" 은 pos
  예: atom 은 명사뿐 → "원자이다" 는 pos
  예: less than 은 "~ 미만의" 라는 관형 표현 → 서술형 "~보다 작다" 는 pos
품사 문제는 correct 아니면 pos 다. close 를 쓰지 마라.

[3단계 — 뜻]
· correct : 교재의 뜻(또는 추가 인정 답안)과 실질적으로 같다.
            같은 뜻의 다른 낱말(예: "나중에"/"추후에"), 같은 품사 안에서의 활용형,
            더 풀어 쓴 설명을 포함한다.
            또는 교재에 없어도 **사전에 실려 있는 그 단어의 다른 뜻**이다.
            지엽적인 뜻이라도 사전에 있으면 인정한다.
            (예: address 에 "연설하다" — 교재에 "다루다" 만 있어도 correct)
· close   : 뜻이 겹치기는 하지만 범위가 지나치게 넓거나 좁아 애매하다.
· wrong   : 그 단어의 뜻이 아니다. 혼동하기 쉬운 다른 영어 단어의 뜻
            (예: subsequently 에 "따라서")은 반드시 wrong.

reason 은 학생에게 그대로 보여 줄 한국어 한 문장, 35자 이내, 존댓말.
correct 면 근거를(예: "동사로도 쓰여요"), pos 면 어떤 형태로 써야 하는지 적어라.`;
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
    const r = await judge(buildPrompt("subsequently", "부", "그 뒤에, 나중에", "", "추후에", "", false));
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

  // 단어 채점 이외의 용도로 쓰이지 않도록 최소한의 형태 검사
  if (!word || !meaning || !answer) return json({ error: "word, meaning, answer 필요" }, 400);
  if (!/[가-힣]/.test(answer)) return json({ verdict: "wrong", reason: "한국어 뜻이 아닙니다." });

  const r = await judge(buildPrompt(word, pos, meaning, alt, answer, exclude, formMismatch));
  if ("ok" in r) return json(r.ok);
  return json({ error: "판정 실패", detail: r.err }, 502);
});
