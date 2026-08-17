// Lawan Duel bikinan sistem, plus taksiran keseimbangan yang memutuskan kapan
// lawan pemain sungguhan masih layak dipakai.
//
// Kenapa ada: matchmaking Duel hanya menyaring stage dan total base stat ±15%,
// sementara yang benar-benar menentukan hasil adalah Level, bentuk distribusi
// stat, dan elemen. Terukur pada roster production, duel ber-label `even`
// berkisar 8,5% sampai 100% peluang menang. Bot sistem menutup itu dengan
// mencerminkan Level dan bentuk stat pemain, memakai elemen netral dua arah,
// lalu mencari total stat yang membuat duelnya terukur imbang.
//
// Seluruh angka di file ini berasal dari sweep simulasi terhadap resolver di
// battle.mjs; jangan mengubahnya tanpa menjalankan ulang skenario duel bot di
// `npm run selftest`.

import {
  careCombatMultiplier,
  computeDamage,
  duelWinRate,
  formFromLevel,
  LEVEL_CAP,
  normalizeBaseStats,
  seededRandom,
  toBattleStats,
} from "./battle.mjs";
import { REWARD_TIERS } from "./catalog.mjs";
import {
  defenseElements,
  dualDefenderMultiplier,
  ELEMENT_ROSTER,
  MATCHUP_NEUTRAL,
  normalizeElement,
  singleMatchup,
} from "./elements.mjs";

// Kekuatan bot dicari sampai duelnya terukur imbang, bukan dipatok satu band
// untuk semua Anima. Band tetap 0,96..1,00 sudah dicoba lebih dulu dan gagal
// karena satu angka harus melayani dua ujung roster sekaligus: batas atasnya
// ditentukan Anima paling rapuh (ber-Special 15, yang jatuh dari 57% ke 29%
// begitu rasio menyentuh 1,02), dan angka aman untuk Anima itu ternyata
// walkover bagi enam Anima production lainnya — mereka menang 89%..100%.
//
// Rasio bukan tuas yang linear. Terukur pada langkah 0,005, peluang menang
// runtuh di sekitar titik cermin: klasik 100% pada 0,990 lalu 70% pada 0,995
// lalu 38% pada 1,020. Pencarian per-Anima ada justru karena tebing itu — satu
// konstanta tidak bisa mendarat di sisi yang benar untuk semua bentuk stat.
export const BOT_TARGET_WIN_RATE = 0.65;
export const BOT_RATIO_MIN = 0.9;
export const BOT_RATIO_MAX = 1.25;
// Tujuh langkah bisection menyisakan resolusi 0,0027 pada band di atas, lebih
// halus daripada tebing tersempit yang terukur, dan `normalizeBaseStats`
// membulatkan stat ke integer sehingga langkah yang lebih halus lagi memberi
// blok stat yang sama.
export const BOT_RATIO_STEPS = 7;

// Batas penerimaan lawan sungguhan, dalam satuan taksiran turn-to-kill.
// Dikalibrasi terhadap win rate terukur pada sembilan pasangan production:
// yang adil (42%..71%) jatuh di 0,56..0,89, walkover (98%..100%) di 0,39..0,50,
// dan yang mustahil (7%..8%) di 1,22..1,34. Pemisahannya bersih di kedua sisi.
export const REAL_BALANCE_MIN = 0.53;
export const REAL_BALANCE_MAX = 1.0;

// Tiga tier hanya menentukan wajah dan nama; kekuatannya selalu dari Level
// pemain. Batasnya sengaja memakai formFromLevel() supaya tidak ada ambang baru.
export const SYSTEM_DUEL_BOTS = Object.freeze({
  hatchling: Object.freeze({
    anima_id: "system-duel-fledgling",
    name: "Echo Fledgling",
    strike_name: "Trial Jab",
    surge_name: "Mirror Pulse",
  }),
  adult: Object.freeze({
    anima_id: "system-duel-warden",
    name: "Echo Warden",
    strike_name: "Trial Strike",
    surge_name: "Mirror Surge",
  }),
  evolved: Object.freeze({
    anima_id: "system-duel-paragon",
    name: "Echo Paragon",
    strike_name: "Trial Cleave",
    surge_name: "Mirror Cascade",
  }),
});

/**
 * Elemen yang netral dua arah terhadap pemain: bot tidak unggul saat menyerang,
 * dan pemain tidak unggul saat menyerang bot lewat Attack maupun Special.
 *
 * Elemen adalah tuas terbesar di Duel, lebih besar daripada selisih stat 35%.
 * Terukur pada stat identik: bot ber-elemen unggul membuat peluang menang 0%,
 * bot ber-elemen lemah membuatnya 100%, sementara netral memberi 77%. Karena
 * pengali itu tidak masuk perhitungan tier, satu-satunya pilihan jujur adalah
 * netral.
 */
export function neutralBotElements(primary, secondary = "") {
  const attacks = defenseElements(primary, secondary);
  return ELEMENT_ROSTER.filter((candidate) => {
    if (dualDefenderMultiplier(candidate, primary, secondary) !== MATCHUP_NEUTRAL) return false;
    return attacks.every((attack) => singleMatchup(attack, candidate) === MATCHUP_NEUTRAL);
  });
}

/**
 * Rakit lawan sistem dari snapshot pemain. Deterministik terhadap `seed`, jadi
 * resume dan replay memakai lawan yang sama tanpa perlu menyimpan resepnya.
 *
 * Bentuk stat bot adalah cermin persis milik pemain, dan itu keputusan terukur,
 * bukan jalan termudah. Mencampurnya ke arah distribusi rata sudah diuji dan
 * ditolak: sebaran win rate antar-roster melompat dari 23 poin menjadi 71 poin
 * pada campuran 70/30 dan 88 poin pada 50/50, karena bot berbentuk rata
 * mengalahkan Anima yang serangannya lemah jauh lebih cepat daripada Anima itu
 * bisa membalas. Cermin membuat panjang pertarungan mengikuti gaya pemain
 * sendiri, sehingga tidak ada bentuk stat yang dihukum.
 */
export function systemDuelBot(player, seed) {
  const level = clampLevel(player?.level);
  const identity = SYSTEM_DUEL_BOTS[formFromLevel(level)] ?? SYSTEM_DUEL_BOTS.hatchling;
  const base = normalizeBaseStats(player?.base_stats);
  const total = STAT_KEYS.reduce((sum, key) => sum + base[key], 0);

  const random = seededRandom(`${seed}:duel_bot`);
  const primary = normalizeElement(player?.element);
  const secondary = player?.secondary_element
    ? normalizeElement(player.secondary_element, "")
    : "";
  const neutral = neutralBotElements(primary, secondary);
  // Elemen pemain sendiri selalu netral terhadap dirinya, jadi daftar ini tidak
  // pernah kosong; fallback-nya cuma jaring pengaman. Elemen netral dua arah
  // tidak mengubah kesulitan, jadi ia tetap boleh diundi seed sementara
  // kekuatannya diukur.
  const element = neutral[Math.floor(random() * neutral.length)] ?? primary;

  const draft = (ratio) => ({
    anima_id: identity.anima_id,
    name: identity.name,
    species_key: identity.anima_id,
    color_bucket: "system",
    stage: 1,
    level,
    element,
    base_stats: normalizeBaseStats(base, Math.round(total * ratio)),
    // Lawan sistem menanggung potongan lapar/kotor yang sama dengan pemain, jadi
    // createFighter() mengalikan kedua sisi dengan angka yang identik dan
    // cerminnya tetap persis pada kondisi care apa pun.
    //
    // Gerbang Hunger dulu dibuang supaya pemain tanpa Bits dan tanpa makanan
    // tidak kehabisan jalan, tetapi terukur jalan keluarnya cuma bergeser:
    // melawan lawan yang tidak ikut terpotong, Anima lapar menang 0%..22% dan
    // lapar+kotor 0%..2%. Menyesuaikan total base stat bot dengan pengali care
    // juga sudah diuji dan gagal — suku HP tetap +20 di toBattleStats() dan
    // lantai 10 per stat di normalizeBaseStats() dua-duanya tidak menyusut,
    // sehingga bot justru berakhir lebih tebal daripada pemain dan Anima
    // ber-Special rendah tetap 0% pada setiap lantai yang dicoba. Menyamakan
    // care membatalkan kedua distorsi itu sekaligus, tanpa aritmetika baru.
    hunger: readNeed(player?.hunger ?? player?.care?.hunger),
    hygiene: readNeed(player?.hygiene ?? player?.care?.hygiene),
    body_height_cm: clampHeight(player?.body_height_cm),
    strike_name: identity.strike_name,
    surge_name: identity.surge_name,
    evolution_version: 0,
    strike_effect_id: "",
    surge_effect_id: "",
    system_asset: "placeholder",
    manifest: {},
  });

  return draft(balancedRatio(player, draft));
}

/**
 * Kekuatan bot yang membuat peluang menang pemain paling dekat ke
 * `BOT_TARGET_WIN_RATE`, diukur dengan resolver production yang sama.
 *
 * Bisection sah karena peluang menang turun monoton terhadap rasio: disweep
 * pada tujuh Anima production dari 0,90 sampai 1,58, tidak ada satu pun titik
 * yang naik kembali.
 *
 * `duelWinRate` menetralkan care di kedua sisi, jadi resep bot tidak berubah
 * ketika meter pemain kosong. Itu wajib, bukan kebetulan: bot yang ikut melemah
 * saat pemain lapar akan membuat menelantarkan Anima menjadi cara mendapat
 * duel gampang dengan bayaran yang sama, sebab tier juga care-neutral.
 *
 * ponytail: 7 x 64 duel = 6 ms untuk Anima ringan dan 32 ms untuk Anima paling
 * tebal di roster (HP 404, pertarungannya menyentuh BATTLE_MAX_TURNS), sekali
 * per startBattle dan tidak pernah pada resume atau commit turn. Plafonnya
 * Anima ber-HP maksimum: kalau nanti terukur di atas ~80 ms, turunkan `runs`
 * pencarian ke 32 — terukur cuma menggeser taksiran 1..3 poin, dan tier akhir
 * tetap dihitung ulang pada 64 duel.
 */
function balancedRatio(player, draft) {
  let weak = BOT_RATIO_MIN;
  let strong = BOT_RATIO_MAX;
  let best = null;
  for (let step = 0; step < BOT_RATIO_STEPS; step += 1) {
    const ratio = (weak + strong) / 2;
    const win = duelWinRate(player, draft(ratio));
    const candidate = { ratio, win, miss: Math.abs(win - BOT_TARGET_WIN_RATE) };
    if (best === null || preferBot(candidate, best)) best = candidate;
    if (win > BOT_TARGET_WIN_RATE) weak = ratio;
    else strong = ratio;
  }
  return best.ratio;
}

/**
 * Kandidat mana yang lebih baik. Terdekat ke target, KECUALI satu sisi membuat
 * pemain lebih sering kalah daripada menang — sisi itu selalu kalah.
 *
 * Pagar ini ada karena pada bentuk stat hiper-spesialis duel cermin bukan lereng
 * melainkan tangga: bentuk `95/95/95/10/10` terukur 98% pada rasio 1,007 lalu
 * langsung ~30% sesudahnya, tanpa satu pun titik di antaranya. Itu sifat
 * mencerminkan bentuk ekstrem, bukan kegagalan pencarian — dan tanpa pagar ini
 * jarak ke target bisa memilih sisi 30%, yang berarti lawan sistem berubah dari
 * jalan keluar menjadi dinding. Duel yang mudah cuma dibayar 6 Bits; duel yang
 * tidak bisa dimenangkan tidak dibayar sama sekali.
 */
function preferBot(candidate, best) {
  const winnable = candidate.win >= REWARD_TIERS.even.minWinRate;
  if (winnable !== best.win >= REWARD_TIERS.even.minWinRate) return winnable;
  return candidate.miss < best.miss;
}

/**
 * Taksiran rasio turn-to-kill: berapa turn pemain butuh untuk menjatuhkan lawan
 * dibanding sebaliknya. Di bawah 1 berarti pemain lebih cepat.
 *
 * Ini sengaja BUKAN combatPower(). combatPower menjumlahkan stat, sedangkan
 * hasil duel adalah damage dikali daya tahan; dua Anima ber-combatPower identik
 * terukur menang 100% dan 0,3%. Taksiran ini tidak dipakai untuk menghitung
 * hadiah — hanya untuk memutuskan apakah satu lawan sungguhan layak dipakai.
 */
export function estimateDuelBalance(player, bot) {
  const p = estimateFighter(player);
  const b = estimateFighter(bot);
  // Pemain memilih aksi terbaiknya; bot memakai campuran karena chooseBotAction
  // menyebar Attack, Special, dan Guard.
  const playerOutput = Math.max(bestDamage(p, b), 1);
  const botOutput = Math.max(mixedDamage(b, p), 1);
  let playerTurns = b.max_hp / playerOutput;
  const botTurns = p.max_hp / botOutput;
  // Sisi yang lebih cepat efektif mendapat setengah turn lebih dulu setiap
  // pertukaran, dan pada spd sama urutannya undian.
  if (b.spd > p.spd) playerTurns += 0.5;
  else if (p.spd > b.spd) playerTurns -= 0.5;
  return Math.max(0, playerTurns) / Math.max(0.5, botTurns);
}

export function isFairRealOpponent(player, bot) {
  const balance = estimateDuelBalance(player, bot);
  return balance >= REAL_BALANCE_MIN && balance <= REAL_BALANCE_MAX;
}

const STAT_KEYS = Object.freeze(["hp", "atk", "def", "spd", "special"]);

function estimateFighter(snapshot) {
  const stats = toBattleStats(
    snapshot?.base_stats,
    snapshot?.stage,
    snapshot?.evolution_branch,
    snapshot?.level,
    { evolutionVersion: Math.trunc(Number(snapshot?.evolution_version) || 0) },
  );
  const mult = careCombatMultiplier(
    snapshot?.hunger ?? snapshot?.care?.hunger,
    snapshot?.hygiene ?? snapshot?.care?.hygiene,
  );
  return {
    max_hp: Math.max(1, Math.trunc(stats.max_hp * mult)),
    atk: Math.max(1, Math.trunc(stats.atk * mult)),
    def: Math.max(1, Math.trunc(stats.def * mult)),
    spd: Math.max(1, Math.trunc(stats.spd * mult)),
    special: Math.max(1, Math.trunc(stats.special * mult)),
    element: normalizeElement(snapshot?.element),
    secondary_element: snapshot?.secondary_element
      ? normalizeElement(snapshot.secondary_element, "")
      : "",
  };
}

function strikeDamage(actor, target) {
  return computeDamage({
    attack: actor.atk,
    defense: target.def,
    power: 50,
    element: dualDefenderMultiplier(actor.element, target.element, target.secondary_element),
  });
}

function surgeDamage(actor, target) {
  return computeDamage({
    attack: actor.special,
    defense: Math.trunc(target.def * 0.5),
    power: 75,
    element: dualDefenderMultiplier(
      actor.secondary_element || actor.element,
      target.element,
      target.secondary_element,
    ),
  });
}

function bestDamage(actor, target) {
  return Math.max(strikeDamage(actor, target), surgeDamage(actor, target));
}

function mixedDamage(actor, target) {
  return (strikeDamage(actor, target) + surgeDamage(actor, target)) / 2;
}

// Nilai care yang tidak terbaca berarti "tidak ada potongan", sama seperti
// careCombatMultiplier() memperlakukannya.
function readNeed(value) {
  const need = Number(value);
  return Number.isFinite(need) ? Math.min(100, Math.max(0, need)) : 100;
}

function clampLevel(value) {
  const level = Math.trunc(Number(value) || 1);
  return Math.min(LEVEL_CAP, Math.max(1, level));
}

function clampHeight(value) {
  const height = Math.trunc(Number(value) || 120);
  return Math.min(2000, Math.max(20, height));
}
