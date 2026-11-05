// 공부해라 — ElevenLabs 프록시 (Supabase Edge Function)
// 앱 바이너리에 ElevenLabs 키를 넣지 않기 위한 서버 중계.
// 인증: 앱이 보내는 x-app-secret 헤더 (Supabase JWT 미사용 → verify_jwt=false)
// 필요한 Secrets (Supabase 대시보드 → Edge Functions → Secrets):
//   ELEVENLABS_API_KEY, APP_SECRET
import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const API = "https://api.elevenlabs.io/v1";
const KEY = Deno.env.get("ELEVENLABS_API_KEY") ?? "";
const APP_SECRET = Deno.env.get("APP_SECRET") ?? "";

// 한국어가 자연스러운 다국어 모델
const TTS_MODEL = "eleven_multilingual_v2";
// 남용 방지: 멘트 한 줄 최대 길이, 녹음 파일 최대 크기
const MAX_TEXT = 200;
const MAX_UPLOAD_BYTES = 10 * 1024 * 1024;

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, content-type, x-app-secret",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
}

const VOICE_ID = /^[A-Za-z0-9]{10,40}$/;

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (!KEY) return json({ error: "server not configured" }, 500);
  if (!APP_SECRET || req.headers.get("x-app-secret") !== APP_SECRET) {
    return json({ error: "unauthorized" }, 401);
  }
  const path = new URL(req.url).pathname.replace(/^.*gongbuhaera-proxy/, "") || "/";

  try {
    // 목소리 복제 (Instant Voice Cloning)
    // 앱 → multipart: name, files, remove_background_noise
    if (path.startsWith("/clone")) {
      const form = await req.formData();
      const file = form.get("files");
      if (!(file instanceof File)) return json({ error: "files missing" }, 400);
      if (file.size > MAX_UPLOAD_BYTES) return json({ error: "file too large" }, 413);
      const out = new FormData();
      out.append("name", String(form.get("name") ?? "gongbuhaera"));
      out.append("files", file, file.name || "voice.m4a");
      out.append("remove_background_noise", String(form.get("remove_background_noise") ?? "true"));
      out.append("description", "공부해라 앱 가상 부모 목소리");
      const r = await fetch(`${API}/voices/add`, {
        method: "POST",
        headers: { "xi-api-key": KEY },
        body: out,
      });
      return new Response(await r.text(), {
        status: r.status,
        headers: { ...CORS, "Content-Type": "application/json" },
      });
    }

    // 문장 → 복제 목소리 mp3
    // 앱 → JSON { voice_id, text }
    if (path.startsWith("/tts")) {
      const { voice_id, text } = await req.json();
      if (typeof voice_id !== "string" || !VOICE_ID.test(voice_id)) {
        return json({ error: "bad voice_id" }, 400);
      }
      if (typeof text !== "string" || !text.trim() || text.length > MAX_TEXT) {
        return json({ error: "bad text" }, 400);
      }
      const r = await fetch(
        `${API}/text-to-speech/${voice_id}?output_format=mp3_44100_128`,
        {
          method: "POST",
          headers: { "xi-api-key": KEY, "Content-Type": "application/json", Accept: "audio/mpeg" },
          body: JSON.stringify({
            text,
            model_id: TTS_MODEL,
            voice_settings: { stability: 0.5, similarity_boost: 0.85, style: 0.2, use_speaker_boost: true },
          }),
        },
      );
      if (!r.ok) {
        return new Response(await r.text(), {
          status: r.status,
          headers: { ...CORS, "Content-Type": "application/json" },
        });
      }
      return new Response(r.body, {
        status: 200,
        headers: { ...CORS, "Content-Type": "audio/mpeg" },
      });
    }

    // 예전 목소리 삭제 — 앱 → JSON { voice_id }
    if (path.startsWith("/delete-voice")) {
      const { voice_id } = await req.json();
      if (typeof voice_id !== "string" || !VOICE_ID.test(voice_id)) {
        return json({ error: "bad voice_id" }, 400);
      }
      const r = await fetch(`${API}/voices/${voice_id}`, {
        method: "DELETE",
        headers: { "xi-api-key": KEY },
      });
      return json({ ok: r.ok }, r.ok ? 200 : r.status);
    }

    if (path === "/" || path.startsWith("/health")) {
      return json({ ok: true, service: "gongbuhaera-proxy" });
    }
    return json({ error: "not found", path }, 404);
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});
