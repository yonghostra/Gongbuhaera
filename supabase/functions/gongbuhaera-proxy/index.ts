// 공부해라 — ElevenLabs · HeyGen 프록시 (Supabase Edge Function)
// 앱 바이너리에 API 키를 넣지 않기 위한 서버 중계.
// 인증: 앱이 보내는 x-app-secret 헤더 (Supabase JWT 미사용 → verify_jwt=false)
// 필요한 Secrets (Supabase 대시보드 → Edge Functions → Secrets):
//   ELEVENLABS_API_KEY, HEYGEN_API_KEY, APP_SECRET
import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const API = "https://api.elevenlabs.io/v1";
const KEY = Deno.env.get("ELEVENLABS_API_KEY") ?? "";
const APP_SECRET = Deno.env.get("APP_SECRET") ?? "";
const HEYGEN_KEY = Deno.env.get("HEYGEN_API_KEY") ?? "";
const HG_UPLOAD = "https://upload.heygen.com/v1";
const HG_API = "https://api.heygen.com";

// 한국어가 자연스러운 다국어 모델
const TTS_MODEL = "eleven_multilingual_v2";
// 남용 방지: 멘트 한 줄 최대 길이, 녹음 파일 최대 크기
const MAX_TEXT = 200;
const MAX_UPLOAD_BYTES = 10 * 1024 * 1024;
const MAX_AUDIO_BYTES = 2 * 1024 * 1024; // 멘트 한 줄 mp3 는 100KB 안팎
// 아바타 영상: 정사각형, 앱 화면의 아바타 프레임 배경색과 같은 배경
const AVATAR_DIMENSION = { width: 720, height: 720 };
const AVATAR_BACKGROUND = "#1D1A18";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, content-type, x-app-secret",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
}

const VOICE_ID = /^[A-Za-z0-9]{10,40}$/;
const HEYGEN_ID = /^[A-Za-z0-9_-]{6,100}$/;

// HeyGen 오류 응답 모양이 엔드포인트마다 달라 한 줄로 정리
// deno-lint-ignore no-explicit-any
function heygenError(j: any, status: number): string {
  return j?.error?.message ?? j?.message ??
    (typeof j?.error === "string" ? j.error : null) ?? `heygen ${status}`;
}

async function readJson(r: Response) {
  try {
    return await r.json();
  } catch {
    return null;
  }
}

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

    // ───────── HeyGen: 말하는 아바타 ─────────
    if (path.startsWith("/heygen/")) {
      if (!HEYGEN_KEY) return json({ error: "heygen not configured" }, 500);

      // 부모 사진 → 사진 아바타(talking photo) 등록. 앱 → 이미지 바이트 그대로
      if (path.startsWith("/heygen/photo")) {
        const bytes = new Uint8Array(await req.arrayBuffer());
        if (bytes.length === 0) return json({ error: "image missing" }, 400);
        if (bytes.length > MAX_UPLOAD_BYTES) return json({ error: "image too large" }, 413);
        const r = await fetch(`${HG_UPLOAD}/talking_photo`, {
          method: "POST",
          headers: { "X-Api-Key": HEYGEN_KEY, "Content-Type": req.headers.get("content-type") ?? "image/jpeg" },
          body: bytes,
        });
        const j = await readJson(r);
        const id = j?.data?.talking_photo_id;
        if (!r.ok || !id) return json({ error: heygenError(j, r.status) }, r.ok ? 502 : r.status);
        return json({ talking_photo_id: id });
      }

      // 영상 생성 요청. ?talking_photo_id=..  본문: 멘트 mp3 (없으면 ?silence=초 → 대기 영상)
      if (path.startsWith("/heygen/video")) {
        const q = new URL(req.url).searchParams;
        const talkingPhotoId = q.get("talking_photo_id") ?? "";
        if (!HEYGEN_ID.test(talkingPhotoId)) return json({ error: "bad talking_photo_id" }, 400);

        let voice: Record<string, string>;
        const silence = q.get("silence");
        if (silence) {
          const sec = Math.min(20, Math.max(1, Number(silence) || 6));
          voice = { type: "silence", duration: String(sec) };
        } else {
          const audio = new Uint8Array(await req.arrayBuffer());
          if (audio.length === 0) return json({ error: "audio missing" }, 400);
          if (audio.length > MAX_AUDIO_BYTES) return json({ error: "audio too large" }, 413);
          const up = await fetch(`${HG_UPLOAD}/asset`, {
            method: "POST",
            headers: { "X-Api-Key": HEYGEN_KEY, "Content-Type": "audio/mpeg" },
            body: audio,
          });
          const uj = await readJson(up);
          const assetId = uj?.data?.id;
          if (!up.ok || !assetId) return json({ error: heygenError(uj, up.status) }, up.ok ? 502 : up.status);
          voice = { type: "audio", audio_asset_id: assetId };
        }

        const r = await fetch(`${HG_API}/v2/video/generate`, {
          method: "POST",
          headers: { "X-Api-Key": HEYGEN_KEY, "Content-Type": "application/json" },
          body: JSON.stringify({
            video_inputs: [{
              character: { type: "talking_photo", talking_photo_id: talkingPhotoId },
              voice,
              background: { type: "color", value: AVATAR_BACKGROUND },
            }],
            dimension: AVATAR_DIMENSION,
          }),
        });
        const j = await readJson(r);
        const videoId = j?.data?.video_id;
        if (!r.ok || !videoId) return json({ error: heygenError(j, r.status) }, r.ok ? 502 : r.status);
        return json({ video_id: videoId });
      }

      // 영상 상태 확인. ?video_id=..
      if (path.startsWith("/heygen/status")) {
        const videoId = new URL(req.url).searchParams.get("video_id") ?? "";
        if (!HEYGEN_ID.test(videoId)) return json({ error: "bad video_id" }, 400);
        const r = await fetch(`${HG_API}/v1/video_status.get?video_id=${encodeURIComponent(videoId)}`, {
          headers: { "X-Api-Key": HEYGEN_KEY },
        });
        const j = await readJson(r);
        if (!r.ok || !j?.data) return json({ error: heygenError(j, r.status) }, r.ok ? 502 : r.status);
        const err = j.data.error;
        return json({
          status: j.data.status,
          video_url: j.data.video_url ?? null,
          error: err ? (err.message ?? err.detail ?? JSON.stringify(err)) : null,
        });
      }
    }

    if (path === "/" || path.startsWith("/health")) {
      return json({ ok: true, service: "gongbuhaera-proxy", heygen: !!HEYGEN_KEY });
    }
    return json({ error: "not found", path }, 404);
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});
