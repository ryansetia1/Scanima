import { readFile } from "node:fs/promises";
import { join } from "node:path";

const PROMPT_DIR = new URL("../../prompts/chapter_factory/", import.meta.url).pathname;

async function readPrompt(name) {
  return readFile(join(PROMPT_DIR, name), "utf8");
}

export async function promptForSlot(slot, ctx) {
  const { design, brief } = ctx;
  if (slot.startsWith("anima:")) {
    const cast = ctx.getCastMember(slot.slice("anima:".length));
    const template = await readPrompt("anima_sheet.md");
    return `${template.trim()}

Chapter: ${design.summary.title}
Anima: ${cast.name} (${cast.id})
Species key: ${cast.species_key}
Primary element: ${cast.element}
Secondary element: ${cast.secondary_element}
Strike: ${cast.strike_name}
Special: ${cast.surge_name}
Silhouette brief: original ${cast.color_bucket} monster for ${design.summary.title} — no logos or franchise likeness.`;
  }
  if (slot.startsWith("zone:")) {
    const index = Number(slot.slice("zone:".length));
    const zone = design.zones.find((entry) => entry.index === index);
    if (!zone) throw new Error(`PROMPT_ZONE_MISSING:${index}`);
    const template = await readPrompt("zone_art.md");
    return `${template.trim()}

Chapter: ${design.summary.title}
Zone ${index}: ${zone.title}
Theme: ${brief.theme ?? design.summary.description} — opaque background, readable path lanes.`;
  }
  if (slot === "boss_seeker") {
    const seeker = design.boss_seeker;
    const template = await readPrompt("boss_seeker_sheet.md");
    return `${template.trim()}

Chapter: ${design.summary.title}
Boss Seeker: ${seeker.display_name}
Role: commands the ${design.summary.title} boss encounter — an original silhouette-led mobile-game character whose personality reads through pose.
Background story: ${seeker.background_story}.
Visual direction: ${seeker.visual_direction ?? "original adult all-ages Seeker with a distinctive body, face, one dominant outfit shape, and restrained theme motifs"}.
Poses required: ${ctx.design.boss_seeker.portrait_pose}, intro_idle, attack_command, special_command, switch_command, concern_hit, last_anima, victory, defeat, profile.`;
  }
  if (slot === "trophy") {
    const trophy = design.trophy;
    const template = await readPrompt("trophy.md");
    return `${template.trim()}

Chapter: ${design.summary.title}
Trophy: ${trophy.display_name}
Description: ${trophy.description}
Chassis: ${trophy.metadata?.chassis ?? "chapter_core_v3"}.
Canonical vessel: ${trophy.metadata?.vessel ?? "point_hex_vessel_v1"} — added after generation; do not draw it.
Palette: ${(trophy.metadata?.palette ?? []).join(", ")}.
Silhouette motif: ${trophy.metadata?.silhouette_motif ?? trophy.metadata?.theme ?? brief.theme}.
Inner core: ${trophy.metadata?.core_motif ?? trophy.metadata?.theme ?? brief.theme}.`;
  }
  throw new Error(`PROMPT_SLOT_INVALID:${slot}`);
}
