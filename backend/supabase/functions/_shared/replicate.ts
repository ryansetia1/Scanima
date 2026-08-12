// Satu jalur untuk semua panggilan Replicate dari Edge Function. Vision dan
// image generation memakai file yang sama supaya penanganan error, timeout, dan
// status hanya ada di satu tempat.
//
// Perbedaan pentingnya dengan eval: di sini generation TIDAK ditunggu. Sheet
// butuh 57-63 detik dan Edge Function tidak boleh menahan koneksi selama itu,
// jadi Replicate yang memanggil kita kembali lewat webhook.

const BASE = "https://api.replicate.com/v1";

export function tokenReplicate(): string {
  const t = Deno.env.get("REPLICATE_API_TOKEN");
  if (!t) throw new Error("REPLICATE_API_TOKEN belum dipasang di secrets Edge Function");
  return t;
}

function header(): HeadersInit {
  return { authorization: `Bearer ${tokenReplicate()}`, "content-type": "application/json" };
}

type Prediksi = {
  id: string;
  status: string;
  output?: unknown;
  error?: unknown;
};

async function buat(model: string, body: Record<string, unknown>, prefer?: string): Promise<Prediksi> {
  const headers = new Headers(header());
  if (prefer) headers.set("prefer", prefer);

  const res = await fetch(`${BASE}/models/${model}/predictions`, {
    method: "POST",
    headers,
    body: JSON.stringify(body),
  });
  if (!res.ok) throw new Error(`${model} create ${res.status}: ${(await res.text()).slice(0, 300)}`);
  return await res.json();
}

/**
 * Panggilan yang ditunggu sampai selesai. Hanya untuk Vision: ia selesai dalam
 * hitungan detik pada thinking_budget 0, dan hasilnya dibutuhkan sebelum kita
 * boleh memutuskan mendebit Genesis Core.
 */
export async function jalankanPrediksi(
  model: string,
  input: Record<string, unknown>,
  batasMs = 60_000,
): Promise<unknown> {
  // Prefer: wait membuat Replicate menahan respons sampai prediksi selesai,
  // jadi kasus normal tidak melakukan polling sama sekali. Polling di bawah
  // hanya jaring pengaman kalau ia lambat, dan GET tidak berbiaya.
  let pred = await buat(model, { input }, "wait=50");
  const mulai = Date.now();

  while (!["succeeded", "failed", "canceled"].includes(pred.status)) {
    if (Date.now() - mulai > batasMs) throw new Error(`${model} timeout ${batasMs / 1000}s`);
    await new Promise((r) => setTimeout(r, 700));
    const poll = await fetch(`${BASE}/predictions/${pred.id}`, { headers: header() });
    if (!poll.ok) throw new Error(`${model} poll ${poll.status}`);
    pred = await poll.json();
  }

  if (pred.status !== "succeeded") {
    throw new Error(`${model} ${pred.status}: ${String(pred.error ?? "tanpa pesan").slice(0, 300)}`);
  }
  return pred.output;
}

/**
 * Memicu generation lalu langsung kembali. `webhook_events_filter: ["completed"]`
 * bukan optimasi: tanpa filter, Replicate mengirim event start dan logs juga,
 * dan setiap event membangunkan fungsi yang harus memverifikasi tanda tangan
 * lalu memutuskan mengabaikannya.
 */
export async function mulaiGeneration(
  model: string,
  input: Record<string, unknown>,
  webhook: string,
): Promise<string> {
  const pred = await buat(model, {
    input,
    webhook,
    webhook_events_filter: ["completed"],
  });
  if (!pred.id) throw new Error(`${model} tidak mengembalikan id prediksi`);
  return pred.id;
}

// Rahasia penanda tangan webhook diambil dari Replicate, bukan dari secret
// terpisah yang harus dipasang manual. Satu kredensial lebih sedikit berarti
// satu langkah setup yang tidak bisa terlupakan, dan nilainya tetap sama untuk
// seluruh akun. Di-cache selama instance hidup karena ia tidak berubah.
let cacheRahasia: string | null = null;

export async function rahasiaWebhook(): Promise<string> {
  if (cacheRahasia) return cacheRahasia;

  const res = await fetch(`${BASE}/webhooks/default/secret`, { headers: header() });
  if (!res.ok) throw new Error(`ambil rahasia webhook gagal ${res.status}`);
  const { key } = await res.json();
  if (typeof key !== "string" || !key) throw new Error("rahasia webhook kosong");

  cacheRahasia = key;
  return key;
}
