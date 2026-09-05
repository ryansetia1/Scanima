/** Default chapter directory (repo-relative). Candy-specific IDs live only in that tree's JSON. */
export const DEFAULT_CHAPTER_REL = "backend/chapters/the-sugarworks/v1";

export const DESIGN_SCHEMA_VERSION = 2;

export const REVIEW_CONFIRM_PHRASE = "I reviewed all chapter assets and dialogue";

export const BOSS_SEEKER_POSES = Object.freeze([
  "intro_idle",
  "attack_command",
  "special_command",
  "switch_command",
  "concern_hit",
  "last_anima",
  "victory",
  "defeat",
  "profile",
]);

export const DIALOGUE_TRIGGERS = Object.freeze([
  "chapter_intro",
  "boss_intro",
  "first_attack",
  "first_special",
  "first_switch",
  "last_anima",
  "victory",
  "defeat",
  "rematch",
]);

export const VOICE_PROFILE_FIELDS = Object.freeze([
  "core_motive",
  "player_relationship",
  "speech_rhythm",
  "emotional_arc",
  "natural_language",
  "avoid",
]);

export const PAID_ACK_PREFIX = "I accept chapter factory spend up to $";
export const DESIGN_ACK_PREFIX = "I accept chapter factory design spend up to $0.003";
export const PUSH_CONFIRM_PHRASE = "Send chapter push to all opted-in players";

export const VISION_MODEL_DEFAULT = "google/gemini-2.5-flash";

export const IP_BLOCKLIST = Object.freeze([
  /\bpok[eé]mon\b/i,
  /\bpokemon\b/i,
  /\bpok[eé]dex\b/i,
  /\bpikachu\b/i,
  /\bdigimon\b/i,
  /\bagumon\b/i,
  /\bnaruto\b/i,
  /\bdragon\s*ball\b/i,
  /\bgoku\b/i,
  /\bmario\b/i,
  /\bzelda\b/i,
  /\bmickey\s*mouse\b/i,
  /\bdisney\b/i,
  /\bnintendo\b/i,
  /\bgame\s*freak\b/i,
]);

export const SAFE_ID = /^[a-z0-9][a-z0-9_-]{1,47}$/;
export const SAFE_SLUG = /^[a-z0-9][a-z0-9-]{2,47}$/;
export const SAFE_SPECIES_KEY = /^[a-z0-9][a-z0-9_]{1,47}$/;
