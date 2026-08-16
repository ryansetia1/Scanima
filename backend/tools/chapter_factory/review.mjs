import { readFile } from "node:fs/promises";
import { join } from "node:path";
import { Image } from "imagescript";
import { BOSS_SEEKER_POSES } from "./constants.mjs";
import { escapeHtml, renderMapPreview } from "./review_html.mjs";

async function imageCard(chapterDir, { title, relPath, subtitle = "", crop = null }) {
  const abs = join(chapterDir, relPath);
  let dims = { width: 0, height: 0 };
  try {
    const bytes = await readFile(abs);
    const decoded = await Image.decode(bytes);
    dims = { width: decoded.width, height: decoded.height };
  } catch {
    // missing during partial builds
  }
  const cropStyle = crop
    ? `style="width:${crop.w}px;height:${crop.h}px;background-image:url('${relPath}');background-position:-${crop.x}px -${crop.y}px;background-size:auto;image-rendering:pixelated;"`
    : "";
  const body = crop
    ? `<div class="crop" ${cropStyle}></div>`
    : `<img src="${relPath}" alt="${escapeHtml(title)}" loading="lazy">`;
  return `<div class="card">
    <div><strong>${escapeHtml(title)}</strong></div>
    ${subtitle ? `<div class="muted">${escapeHtml(subtitle)}</div>` : ""}
    <div class="muted">${dims.width}×${dims.height}px · <code>${escapeHtml(relPath)}</code></div>
    ${body}
  </div>`;
}

function zoneArenaCard({ title, relPath, subtitle = "" }) {
  return `<div class="card arena-card">
    <div><strong>${escapeHtml(title)} — arena crop</strong></div>
    ${subtitle ? `<div class="muted">${escapeHtml(subtitle)}</div>` : ""}
    <div class="muted">Center crop · feet at 88% · protected floor band</div>
    <div class="arena-stage">
      <img src="${relPath}" alt="${escapeHtml(title)} arena crop">
      <div class="arena-floor"></div>
      <div class="arena-foot"></div>
      <div class="arena-anchor arena-player"></div>
      <div class="arena-anchor arena-opponent"></div>
    </div>
  </div>`;
}

export async function buildReviewPage({ manifest, chapterDir, ctx }) {
  const castRows = manifest.opponents.flatMap((opponent) =>
    opponent.roster.map((member) => ({
      opponent: opponent.id,
      ...member,
    })),
  );
  const uniqueCast = [...new Map(castRows.map((row) => [row.anima_id, row])).values()];
  const maps = manifest.qa?.map_previews ?? [];

  const animaCards = await Promise.all(uniqueCast.map((member) => imageCard(chapterDir, {
    title: member.name,
    relPath: ctx.storageToLocalRel(member.sheet_path),
    subtitle: `${member.anima_id} · ${member.element}${member.secondary_element ? ` / ${member.secondary_element}` : ""}`,
  })));

  const zoneCards = await Promise.all(manifest.zones.flatMap((zone, index) => {
    const relPath = ctx.storageToLocalRel(zone.background_path);
    const title = `Zone ${index + 1}`;
    return [
      imageCard(chapterDir, { title, relPath, subtitle: zone.title_key }),
      zoneArenaCard({ title, relPath, subtitle: zone.title_key }),
    ];
  }));

  const bossPath = ctx.storageToLocalRel(manifest.boss_seeker.sheet_path);
  const bossFull = await imageCard(chapterDir, {
    title: "Boss Seeker — full sheet",
    relPath: bossPath,
    subtitle: manifest.boss_seeker.display_name,
  });
  const bossPoses = manifest.boss_seeker.manifest?.poses ?? {};
  const bossPoseCards = await Promise.all(BOSS_SEEKER_POSES.map(async (pose) => {
    const region = bossPoses[pose]?.region;
    if (!Array.isArray(region)) {
      return `<div class="card"><strong>${escapeHtml(pose)}</strong><div class="muted">region missing</div></div>`;
    }
    const [x, y, w, h] = region;
    return imageCard(chapterDir, {
      title: pose,
      relPath: bossPath,
      subtitle: "Boss Seeker pose",
      crop: { x, y, w, h },
    });
  }));

  const trophyCard = await imageCard(chapterDir, {
    title: manifest.trophy.display_name,
    relPath: ctx.storageToLocalRel(manifest.trophy.art_path),
    subtitle: manifest.trophy.slug,
  });

  const assetEntries = manifest.assets?.entries ?? [];

  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>Chapter Factory Review — ${escapeHtml(manifest.summary.title)}</title>
  <style>
    :root { color-scheme: dark; font-family: "Segoe UI", sans-serif; background:#0b1020; color:#eef3ff; }
    body { margin: 24px; line-height: 1.45; }
    h1,h2,h3 { font-family: Georgia, serif; color:#ffd978; }
    section { margin: 28px 0; padding: 20px; border: 1px solid #2a3558; border-radius: 12px; background:#121a31; }
    table { width:100%; border-collapse: collapse; font-size: 14px; }
    th, td { border-bottom: 1px solid #2a3558; padding: 8px 10px; text-align:left; vertical-align: top; }
    th { color:#9fd6ff; }
    code, pre { background:#060912; padding: 2px 6px; border-radius: 6px; }
    pre { overflow:auto; padding: 12px; }
    .grid { display:grid; grid-template-columns: repeat(auto-fit, minmax(240px, 1fr)); gap: 16px; }
    .card { background:#0d1428; border:1px solid #314068; border-radius: 10px; padding: 12px; }
    .card img { width:100%; image-rendering: pixelated; border-radius: 8px; background:#000; }
    .crop { border-radius: 8px; background-color:#000; background-repeat:no-repeat; max-width:100%; }
    .arena-stage { position:relative; width:100%; aspect-ratio:4 / 5; overflow:hidden; border-radius:8px; background:#000; }
    .arena-stage img { position:absolute; inset:0; width:100%; height:100%; object-fit:cover; object-position:center; border-radius:0; }
    .arena-floor { position:absolute; left:0; right:0; bottom:0; height:35%; background:rgba(255,217,120,0.12); border-top:1px dashed rgba(255,217,120,0.55); pointer-events:none; }
    .arena-foot { position:absolute; left:0; right:0; top:88%; border-top:2px solid #ffd978; pointer-events:none; }
    .arena-anchor { position:absolute; top:88%; width:10px; height:10px; margin:-5px 0 0 -5px; border-radius:50%; background:#9fd6ff; pointer-events:none; }
    .arena-player { left:27%; }
    .arena-opponent { left:73%; }
    .muted { color:#9fb0d0; font-size: 13px; }
    .hash { font-family: ui-monospace, monospace; font-size: 12px; word-break: break-all; }
  </style>
</head>
<body>
  <h1>${escapeHtml(manifest.summary.title)}</h1>
  <p class="muted">Chapter Factory review · sequence ${escapeHtml(String(manifest.sequence ?? manifest.factory?.sequence ?? 1))} · manifest hash <span class="hash">${escapeHtml(manifest.manifest_hash ?? "")}</span></p>
  <p class="muted">Buka file ini setelah <code>build</code> / <code>generate --paid --apply</code>. Semua PNG di bawah memuat preview lokal — bukan daftar hash saja.</p>

  <section>
    <h2>Anima Sheets (${animaCards.length})</h2>
    <div class="grid">${animaCards.join("")}</div>
  </section>

  <section>
    <h2>Zone Art (${manifest.zones.length})</h2>
    <p class="muted">Full frame plus tall-phone arena crop. Amber band is the protected floor; gold line is the 88% foot line; dots mark fighter anchors. Advisory only — reject liquid, rails, or chasms under the dots.</p>
    <div class="grid">${zoneCards.join("")}</div>
  </section>

  <section>
    <h2>Boss Seeker</h2>
    <div class="grid">${bossFull}${bossPoseCards.join("")}</div>
  </section>

  <section>
    <h2>Trophy</h2>
    <div class="grid">${trophyCard}</div>
  </section>

  <section>
    <h2>Cast &amp; Stats</h2>
    <table>
      <thead><tr><th>Anima</th><th>Opponent</th><th>Element</th><th>Stats</th><th>Moves</th></tr></thead>
      <tbody>
        ${uniqueCast.map((member) => `<tr>
          <td><strong>${escapeHtml(member.name)}</strong><br><code>${escapeHtml(member.anima_id)}</code></td>
          <td>${escapeHtml(castRows.filter((row) => row.anima_id === member.anima_id).map((row) => row.opponent).join(", "))}</td>
          <td>${escapeHtml(member.element)}${member.secondary_element ? ` / ${escapeHtml(member.secondary_element)}` : ""}${member.special ? " · special" : ""}</td>
          <td>${escapeHtml(JSON.stringify(member.base_stats))}</td>
          <td>${escapeHtml(member.strike_name)} / ${escapeHtml(member.surge_name)}</td>
        </tr>`).join("")}
      </tbody>
    </table>
  </section>

  <section>
    <h2>Asset Hashes</h2>
    <div class="grid">
      ${assetEntries.map((entry) => `<div class="card">
        <div><strong>${escapeHtml(entry.kind)}</strong></div>
        <div class="muted"><code>${escapeHtml(entry.path)}</code></div>
        <div class="hash">${escapeHtml(entry.sha256)}</div>
      </div>`).join("")}
    </div>
  </section>

  <section>
    <h2>Boss Seeker Dialogue</h2>
    <table>
      <thead><tr><th>Trigger</th><th>Line</th></tr></thead>
      <tbody>
        ${Object.entries(manifest.boss_seeker.dialogue).map(([trigger, line]) => `<tr>
          <td><code>${escapeHtml(trigger)}</code></td>
          <td>${escapeHtml(line)}</td>
        </tr>`).join("")}
      </tbody>
    </table>
  </section>

  <section>
    <h2>Map Previews</h2>
    ${maps.map((map, index) => `<div class="card" style="margin-bottom:16px">
      <h3>Zone ${index + 1}</h3>
      ${renderMapPreview(map)}
    </div>`).join("")}
  </section>
</body>
</html>`;
}
