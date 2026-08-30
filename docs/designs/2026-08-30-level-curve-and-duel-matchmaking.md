# Rebalance kurva Level dan matchmaking Duel

Status: **rencana, belum diimplementasikan.** Ditulis 30 Agustus 2026.

## Konteks

Pemain melaporkan Duel: Anima **Lv 13 HP 292** melawan bot **Lv 4 HP 240**, dan
rasanya bukan pertandingan timpang seperti yang dijanjikan angka Level-nya.
Ekspektasinya ala Pokémon — Lv 13 vs Lv 4 harusnya walkover.

Investigasi memastikan **angka itu bukan bug**; ketiganya adalah keluaran
formula yang berjalan benar. Yang rusak adalah kontrak antara angka Level yang
ditampilkan dan kekuatan yang ia wakili.

### Tiga penyebab yang saling menumpuk

**1. Level nyaris tidak berarti** — `_shared/battle.mjs:104`

```js
let mult = 1 + 0.02 * (lv - 1);
```

Linear, tidak compounding. Lv 4 → ×1,06, Lv 13 → ×1,24. Sembilan level
grinding = **+17% stat**. Seluruh Lv 1→40 hanya ×1,00→×1,78 (×2,13 dengan bonus
form legacy).

Bandingkan dengan sumber stat yang lain: Vision memberi base stat **10–95 per
stat** (`prompts/v41/vision_schema.json:74-86`), total 200–350. Di `toBattleStats`
(`battle.mjs:167`) satu poin `base.hp` bernilai `4 × g` HP, sedangkan satu level
bernilai `base.hp × 0,08` HP. Pada base 55 itu **4,96 HP per poin base vs 4,4 HP
per level** — satu poin base stat ≈ 1,13 level.

Konsekuensinya terukur: rentang HP dari roll Vision saja (69→491 pada Lv 13)
**lebih lebar daripada seluruh grind 40 level** (240→488 pada base 55). Anima
Lv 1 bertubuh tebal mengalahkan Anima Lv 40 bertubuh rapuh pada HP.

**2. HP 292 dan 240 keduanya konsisten dan unik.** `max_hp = trunc(base.hp × 4 × g) + 20`:

| | Level | g | base.hp | hasil |
|---|---|---|---|---|
| Pemain | 13 | 1,24 | **55** | trunc(272,80) + 20 = **292** |
| Bot | 4 | 1,06 | **52** | trunc(220,48) + 20 = **240** |

Tidak ada nilai `base.hp` lain di 10–95 yang menghasilkan angka itu pada level
masing-masing. Sembilan level hanya menyumbang +39 HP; selisih 3 poin base.hp
memakan +13 HP dari itu. Suku flat `+20` mengencerkan rasionya lebih jauh lagi
(272/220 = 1,236 menjadi 292/240 = 1,217).

**3. Matchmaking Duel sengaja buta Level — dan malah menyamakan stat.**
`battle_anima/index.ts:583-592`:

```ts
const close = candidate.row.stage === player.stage &&
  Math.abs(baseStatTotal(candidate.row.base_stats) - playerTotal) <= playerTotal * 0.15;
const baseStats = close
  ? normalizeStats(candidate.row.base_stats)
  : normalizeStats(candidate.row.base_stats, playerTotal);   // ← dinaikkan ke anggaran pemain
```

Tidak ada satu pun predikat Level di seluruh jalur: tidak di query
`gallery_entries` (`index.ts:236-245`), tidak di `pickFairCandidate`, tidak di
`start_battle`. Lawan lolos semata-mata kalau simulasi 64 duel jatuh di win rate
**40–80%** (`isWinnableDuel`, `duel_bot.mjs:307-310`).

Jadi lawan Lv 4 itu **base stat-nya dinaikkan ke anggaran Lv 13 milik pemain**,
lalu diloloskan justru *karena* duelnya ketat.

**Verifikasi:** matchup persis itu, disimulasikan dengan resolver production —
win rate pemain **40,6%**, tier `tough`, median 5 turn. Pemain bukan sekadar
"kurang unggul"; secara statistik dia **underdog**, sambil membaca "Lv 13 vs
Lv 4" di HUD.

Perlu dicatat: lawan sistem (Echo) **tidak** punya masalah ini —
`systemDuelBot()` mencerminkan Level pemain persis (`duel_bot.mjs:150`). Yang
bisa memunculkan selisih Level besar hanya lawan Atlas sungguhan.

### Keputusan arah

Dikonfirmasi operator, 30 Agustus 2026:

1. **Kurva Level tajam ala Pokémon** — `g = 1 + 0,09 × (lv−1)`, Lv 40 = ×4,51.
2. **Band Level lebar di matchmaking** — ±30% Level, minimum ±3, gate win-rate tetap jalan sesudahnya.
3. **Rescale dipertahankan tapi jujur** — kalibrasi pindah ke sumbu yang terlihat.

### Konsekuensi yang ditemukan saat memvalidasi arah itu

**Kurva tajam merusak pacing, karena `100/(100+DEF)` tidak skala-invarian.**
Kalau ATK/DEF/HP semuanya naik ×g:

```
turns = g·hp₀ · (100 + g·def₀) / (g·atk₀ · (P/50) · 100)
      = hp₀ · (100 + g·def₀) / (atk₀ · (P/50) · 100)     ← tumbuh linear terhadap g
```

Terukur (mirror duel, base 55 rata, 3 surge + strike):

| | k = 0,02 (sekarang) | k = 0,09 tanpa perbaikan | k = 0,09 + perbaikan |
|---|---|---|---|
| Lv 1 | 4,4 turn | 4,4 turn | 4,4 turn |
| Lv 13 | 4,6 turn | 5,9 turn | 4,0 turn |
| Lv 40 | 5,4 turn | **10,2 turn** | 3,9 turn |

10,2 turn dasar plus guard-stall (guard ×0,5 **dan** isi ulang PP — satu duel
terukur molor 4→7 turn karena ini) mendekati `BATTLE_MAX_TURNS = 30`, dan
menabrak pagar pacing eksplisit di `selftest.mjs:2082-2084` yang menuntut
6–10 turn. Perbaikannya wajib ikut, bukan opsional.

---

## Perubahan

### 1. Kurva Level — `_shared/battle.mjs`

Konstanta baru di samping konstanta lain (baris 41–56), lalu `growthMultiplier`
(baris 99–112) memakainya:

```js
export const GROWTH_PER_LEVEL = 0.09;   // ponytail: satu tuas. Turunkan ke 0.05 kalau playtest bilang terlalu tajam.
...
let mult = 1 + GROWTH_PER_LEVEL * (lv - 1);
```

Cabang legacy `+0.15`/`+0.20` dan cabang `formMultiplier(stage)` tidak disentuh —
keduanya sudah ter-gate `usesEvolutionCombat` dan tidak ikut membesar.

### 2. Mitigasi skala-invarian — `_shared/battle.mjs`

Basis mitigasi ikut naik bersama growth defender. Ini persis cara Pokémon
menjaga pacing (suku `2·Level/5 + 2` di pembilangnya).

- Export `mitigationBase(level, opts) => 100 * growthMultiplier(level, opts)`.
- `createFighter` (baris 454–496) menyimpan `mitigation_base` di dict fighter,
  dihitung dari argumen yang sama dengan `toBattleStats`.
- `computeDamage` (baris 200–221) menerima `mitigationBase = 100`:
  ```js
  const base = Math.max(1, Number(mitigationBase) || 100);
  const mitigation = base / (base + Math.max(0, Number(defense) || 0));
  ```
- `resolveCombatAttack` (baris 557–637), `bestDuelAction` preview (baris 267–282),
  dan `chooseBotAction`/`scoreActionValue` meneruskan `target.mitigation_base`.

**Default 100 itu yang menjaga kompatibilitas mundur.** `createFighter` hanya
jalan sekali di `startBattle`; `resolveTurn` tidak pernah menurunkan ulang stat.
Jadi session yang sedang berjalan (TTL 30 menit) tidak punya field itu, jatuh ke
100, dan menyelesaikan diri dengan matematika lama. **Tidak perlu menaikkan
`RULES_VERSION`.**

### 3. Band Level + kalibrasi yang jujur — `battle_anima/index.ts`

Di `pickFairCandidate` (baris 576–601), ganti blok `close`/rescale:

```ts
const band = Math.max(3, Math.round(playerLevel * 0.30));
const shortlist = candidates
  .filter((c) => Math.abs(levelFromExp(c.row.care_score) - playerLevel) <= band)
  .map((c) => { /* refit level, lihat bawah */ })
  .filter((c) => isPlausibleRealOpponent(playerSnapshot, c.fighter));
```

**Kalibrasi pindah dari base stat ke Level.** Sekarang Level adalah tuas
kekuatan, jadi menyetelnya di situ membuat angka yang tampil = angka yang
dilawan. Base stat lawan tetap utuh (itu identitas Anima-nya, hasil roll Vision
pemiliknya); yang disetel adalah Level efektifnya:

```ts
const gNeeded = growthMultiplier(playerLevel, {...}) * (playerTotal / candidateTotal);
const refitLevel = clampInt(Math.round(1 + (gNeeded - 1) / GROWTH_PER_LEVEL), 1, LEVEL_CAP);
```

Lalu `refitLevel` dipakai untuk **stat maupun tampilan** — `candidateFighter` dan
`gallerySnapshot` memakai angka yang sama. Tidak ada lagi "Lv 4 dengan HP 240":
HUD menampilkan Level yang benar-benar menghasilkan stat itu.

Rentang refit dibatasi band yang sama supaya kalibrasi tidak diam-diam
membatalkan filter Level. Kandidat yang refit-nya keluar band dibuang.

Gate `isWinnableDuel` (40–80%) tetap sebagai keputusan akhir, tidak disentuh.
`DUEL_GATE_CANDIDATES = 3` tetap.

**Catatan pool:** query `gallery_entries` (`index.ts:236-245`) punya `limit(200)`
tanpa `order by`. Selama pool masih < 200 baris ini tidak berpengaruh, tapi band
Level akan menyempitkan pool lebih jauh — fallback `systemDuelBot` (yang Level-nya
sudah dicerminkan persis) akan lebih sering dipakai, dan itu memang hasil yang
diinginkan.

### 4. Mirror client — `game/scripts/sim/battle_sim.gd`

Parity test membandingkan dict **persis dua arah** (`test_battle_sim_parity.gd:222-280`
— kunci tambahan *dan* kunci hilang sama-sama gagal), jadi ketiga hal ini wajib
ikut:

- `growth_multiplier` baris 89 → `1.0 + GROWTH_PER_LEVEL * float(lv - 1)`
- `compute_damage` baris 227–248 → parameter `mitigation_base`
- `create_fighter` → field `mitigation_base` di dict

Konstanta `GROWTH_PER_LEVEL` juga masuk pemindai konstanta GDScript di
`selftest.mjs:5876-5905` (yang sudah mencocokkan 21 konstanta client terhadap
`_shared`) — tambahkan ke daftarnya supaya divergensi ketahuan gratis.

`game/scripts/care_rules.gd:356` (`growth_multiplier_for_row`) adalah salinan
ketiga; ikut diperbarui.

### 5. Lawan sistem, Team Battle, dan Expedition

Ini yang paling gampang terlupa dan paling mahal kalau terlupa.

- **`_shared/duel_bot.mjs`** — `estimateFighter` (baris 314–337) menambahkan
  `mitigation_base`; `strikeDamage`/`surgeDamage` (339–359) meneruskannya.
  `BOT_RATIO_MIN/MAX = 0,9/1,25` dan `REAL_BALANCE_MIN/MAX = 0,53/1,0` adalah
  hasil sweep terhadap kurva lama — **wajib diukur ulang**, bukan diasumsikan.
  `systemDuelBot` mencerminkan Level pemain persis, jadi bisection-nya tetap
  bekerja; yang bergeser adalah band-nya.

- **Lawan chapter Expedition semuanya `"level": 12`** — 70 dari 70 di
  `backend/chapters/`. Pada kurva lama itu ×1,22, jadi ia melayani rentang
  pemain yang lebar. Pada k = 0,09 itu ×1,99: pemain Lv 4 (×1,27) tidak punya
  peluang, pemain Lv 30 (×3,61) menang tanpa perlawanan. The Sugarworks perlu
  **v8 dengan ramp Level per zona**; v1–v7 tetap immutable untuk run lama sesuai
  aturan chapter yang berlaku.

- **Template Team Battle** `scrap-scavengers` (Lv 2), `starter-sentinels` (Lv 4),
  `vault-wardens` (Lv 7) — pada kurva baru ketiganya menjadi latihan sasaran
  untuk pemain Lv 13+. `teamCombatPower` menghitung tier dari ratio, jadi
  ketiganya akan runtuh ke `favorable`. Perlu migrasi yang menaikkan Level
  template, atau menskalakannya relatif terhadap roster pemain.

### 6. Regenerasi dan pengukuran ulang

Golden vector **adalah kunci jawaban**, jadi ini bukan langkah opsional:

```bash
node backend/tools/emit_sim_vectors.mjs
godot --headless --path game --script res://tests/test_battle_sim_parity.gd
```

Angka yang dipatok dan wajib diukur ulang (bukan ditebak):

| Lokasi | Isi |
|---|---|
| `selftest.mjs:1932-1980` | `toBattleStats` Lv 1/16/36 → 220 / 310 / 430 |
| `selftest.mjs:1964-1966` | `growthMultiplier(16)==1.45`, `(36)==2.05` |
| `selftest.mjs:2061-2084` | damage 33, guarded 16, **band turn 6–10** |
| `selftest.mjs:2136-2151` | HP lapar 176 / kelaparan 132 / kotor 154 |
| `selftest.mjs:6466-6491` | 5 win rate roster production dipatok ±0,12 |
| `selftest.mjs:6513-6548` | 12 `GATE_PAIRS` dipatok ke string tier persis |
| `selftest.mjs:6296-6309` | setiap duel lawan sistem wajib tier `even` |
| `selftest.mjs:10456-10460` | `duelWinRate(adult, hatchling)` di [0,75; 1,0) |
| `test_game_rules.gd:108-111` | `growth_multiplier(16)≈1.45`, `(36)≈2.05`, `grown_stat(50,150)==72` |
| `test_game_rules.gd:401-415` | ekspektasi Adult hardcode `(1+0.02*15) * 1.06` |

Yang **tidak** perlu disentuh: kurva EXP (`expForLevel`/`battleExpYield`) dan
salinan SQL-nya di migrasi `20260816200507`. Kita tidak mengubah kecepatan naik
Level, hanya nilainya.

### 7. Dokumentasi (wajib, satu langkah yang sama)

- `docs/wiki/battle.md` — bagian "Siapa lawanmu di Duel" (baris 233–275)
  sekarang **salah**: ia menjanjikan Level yang sama padahal itu hanya berlaku
  untuk Echo bot, tidak untuk lawan Atlas sungguhan. Tulis band Level, tulis
  bahwa Level lawan disetel agar seimbang, tulis bahwa Level sekarang tuas
  kekuatan utama.
- `docs/wiki/anima.md` — Level sekarang benar-benar menaikkan stat; sebutkan
  besarannya.
- `docs/04-game-systems-economy.md:700-800` — bab balancing kanonis.
- `.cursor/rules/battle-and-expedition.mdc` baris 30 — gate lawan Duel.
- `CLAUDE.md` tabel "Status live" kalau `battle_anima` version naik.
- `docs/14-deploy-log.md` — entri rollout beserta angka terukur sebelum/sesudah.

### 8. Temuan sampingan (tidak dikerjakan, dicatat saja)

`stageMultipliers()` (`battle.mjs:114-125`, tabel guardian/ravager 1,9/1,5) **nol
pemanggil di seluruh repo**, dan parameter `branch` di `toBattleStats` diterima
tapi tidak pernah diteruskan ke `growthMultiplier`. Evolution branch tidak
berpengaruh apa pun pada stat hari ini. Kandidat penghapusan terpisah.

---

## Verifikasi

Berurutan, berhenti di kegagalan pertama:

```bash
# 1. Formula + kalibrasi + kontrak GDScript (gratis)
npm run selftest

# 2. Regenerasi kunci jawaban, lalu parity client vs server
node backend/tools/emit_sim_vectors.mjs
godot --headless --path game --script res://tests/test_battle_sim_parity.gd

# 3. Aturan game + kurva Level di client
godot --headless --path game --script res://tests/test_game_rules.gd

# 4. Tidak ada regresi di jalur lain
godot --headless --path game --script res://tests/test_scan_ui.gd
godot --headless --path game --script res://tests/test_expedition_route_map.gd

# 5. Pagar kuota/akses kalau ada migrasi template Team Battle
supabase db query --file backend/tests/quota_rules.sql --linked
```

**Pemeriksaan feel yang harus ditulis sebagai skenario baru di `selftest.mjs`** —
inilah yang gagal kalau logikanya rusak, dan inilah keluhan aslinya:

1. `duelWinRate(Lv13, Lv4)` dengan base stat setara **≥ 0,95**. Sekarang 0,406.
   Terukur pada kurva baru: pemain membunuh dalam ~1,4 turn sementara lawan
   butuh ~8,3 turn.
2. Mirror duel pada Lv 1, Lv 20, dan Lv 40 semuanya jatuh di **4–8 turn**. Ini
   yang menjaga perbaikan mitigasi tetap terpasang; tanpanya Lv 40 = 10,2 turn.
3. `pickFairCandidate` tidak pernah mengembalikan kandidat yang Level-nya di luar
   `max(3, round(0,30 × playerLevel))`.

Sesudah backend lulus, smoke tanpa kredensial (nol biaya, 401 = fungsi boot):

```bash
curl -sS -X POST https://kgcaisvmmpxswevjvgft.supabase.co/functions/v1/battle_anima -d '{}'
```

Lalu Duel sungguhan di device: konfirmasi HUD menampilkan Level yang cocok
dengan HP-nya, dan lawan yang muncul ada di dalam band.
