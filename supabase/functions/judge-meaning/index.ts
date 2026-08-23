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
function buildPrompt(w: string, pos: string, meaning: string, alt: string, answer: string) {
  return `너는 영어 단어 시험의 채점 보조다. 학생이 쓴 우리말 뜻이 표준 답안과 같은 뜻인지 판단해라.

영어 단어: ${w}${pos ? ` (${pos})` : ""}
표준 답안: ${meaning}${alt ? `\n추가로 인정된 답안: ${alt}` : ""}
학생 답안: ${answer}

판정 기준
- correct : 표준 답안 중 하나와 뜻이 실질적으로 같다.
            사전이 달라 표현만 다른 경우(예: "나중에" / "추후에"),
            같은 뜻의 다른 낱말, 어미·조사만 다른 경우, 더 풀어 쓴 설명을 모두 포함한다.
- close   : 뜻이 겹치기는 하지만 범위가 지나치게 넓거나 좁아 애매하다.
            또는 그 단어의 다른 뜻(다의어)일 수는 있으나 표준 답안과는 다르다.
- wrong   : 뜻이 다르다. 특히 혼동하기 쉬운 다른 영어 단어의 뜻을 적은 경우
            (예: subsequently 에 "따라서")는 반드시 wrong 이다.

reason 은 학생에게 그대로 보여 줄 한국어 한 문장으로, 35자 이내. 존댓말.`;
}

const SCHEMA = {
  type: "OBJECT",
  properties: {
    verdict: { type: "STRING", enum: ["correct", "close", "wrong"] },
    reason: { type: "STRING" },
  },
  required: ["verdict", "reason"],
};

async function callGemini(model: string, prompt: string, omitThinkingConfig: boolean) {
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
  const res = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json", "x-goog-api-key": API_KEY },
      body: JSON.stringify(body),
      signal: AbortSignal.timeout(8000),
    },
  );
  return res;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ error: "POST only" }, 405);
  if (!API_KEY) return json({ error: "GEMINI_API_KEY 가 설정되지 않았습니다." }, 500);

  let payload: Record<string, string>;
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
  const answer = str(payload.answer, 80);

  // 단어 채점 이외의 용도로 쓰이지 않도록 최소한의 형태 검사
  if (!word || !meaning || !answer) return json({ error: "word, meaning, answer 필요" }, 400);
  if (!/[가-힣]/.test(answer)) return json({ verdict: "wrong", reason: "한국어 뜻이 아닙니다." });

  const prompt = buildPrompt(word, pos, meaning, alt, answer);

  let lastErr = "";
  for (const model of MODELS) {
    for (const omitThinkingConfig of [false, true]) {
      try {
        const res = await callGemini(model, prompt, omitThinkingConfig);
        if (res.ok) {
          const data = await res.json();
          const text = data?.candidates?.[0]?.content?.parts?.[0]?.text ?? "";
          let out: { verdict?: string; reason?: string } = {};
          try { out = JSON.parse(text); } catch { /* 아래에서 처리 */ }
          if (!["correct", "close", "wrong"].includes(out.verdict ?? "")) {
            lastErr = `응답 형식 오류: ${text.slice(0, 120)}`;
            continue;
          }
          return json({
            verdict: out.verdict,
            reason: String(out.reason ?? "").slice(0, 80),
            model,
          });
        }
        const errText = await res.text();
        lastErr = `${model} ${res.status} ${errText.slice(0, 200)}`;
        // thinkingConfig 를 모르는 모델이면 그 옵션 없이 한 번 더
        if (res.status === 400 && /thinking/i.test(errText) && !omitThinkingConfig) continue;
        break; // 다른 오류면 다음 모델로
      } catch (e) {
        lastErr = `${model} ${e instanceof Error ? e.message : String(e)}`;
        break;
      }
    }
  }
  return json({ error: "판정 실패", detail: lastErr }, 502);
});
