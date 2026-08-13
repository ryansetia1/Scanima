// Harga per panggilan, dipakai eval untuk melaporkan biaya dan dipakai produksi
// untuk mengisi generations.cost_usd_estimate — yang menjadi dasar spend cap
// harian. Kalau eval dan produksi punya angka berbeda, cap-nya menjaga batas
// yang salah, jadi tabelnya satu.

// Estimasi, bukan angka resmi: Replicate tidak mencantumkan harga per token untuk
// wrapper Gemini, jadi ini hitungan dari harga Google gemini-2.5-flash
// ($0.30/1M input, $2.50/1M output) dengan ~4,3k token input (system prompt +
// skema + satu gambar 1024px) dan ~700 token output.
export const BIAYA_VISION_USD = 0.003;

/**
 * GPT Image 2 ditagih per token, jadi tidak ada harga tetap. Dua run medium
 * nyata memberi $0.068 dan $0.072 termasuk prompt + foto, jadi $0.07 lebih jujur
 * daripada mengutip biaya output $0.053 saja. nano-banana-pro punya harga tetap
 * dan hanya untuk rollback/A-B. nano-banana-2-lite tercantum $0.034 per output
 * image pada snapshot Replicate 13 Agustus 2026.
 */
export function biayaGambarUsd(model, quality = "medium") {
  if (model === "google/nano-banana-2-lite") return 0.034;
  if (model !== "openai/gpt-image-2") return 0.134;
  if (quality === "high") return 0.23;
  if (quality === "low") return 0.02;
  return 0.07;
}
