class_name ElementRules
extends RefCounted

## Port matchup dari `backend/supabase/functions/_shared/elements.mjs`.
## `ElementCatalog` memakai ulang ROSTER dan ALIASES di sini untuk ikon dan
## label; arahnya sengaja begitu, karena presentasi boleh bergantung pada aturan
## tetapi aturan tidak boleh menyeret autoload. `ElementCatalog` menyentuh
## `LocaleManager`, dan nama autoload belum terdaftar saat skrip `--script`
## dikompilasi, sehingga test headless akan gagal memuat seluruh simulasi.
##
## `normalize()` juga sengaja tidak memanggil `ElementCatalog.normalize()`: yang
## itu mengembalikan "stone" ketika fallback kosong, sedangkan
## `normalizeElement()` di server mengembalikan string kosong. Bedanya
## menentukan apakah sebuah Anima dianggap punya elemen sekunder, dan itu
## langsung mengubah damage.

const ROSTER: PackedStringArray = [
	"metal", "wood", "stone", "ceramic", "glass", "plastic", "cloth", "paper",
	"plant", "food", "fauna", "flow", "spark", "flame", "frost", "air",
	"toxin", "sound",
]

const ALIASES := {
	"tech": "spark",
	"electric": "spark",
	"electricity": "spark",
	"water": "flow",
	"earth": "stone",
	"nature": "plant",
	"fire": "flame",
	"ice": "frost",
	"wind": "air",
	"poison": "toxin",
	"organic": "food",
	"animal": "fauna",
	"beast": "fauna",
	"fabric": "cloth",
	"textile": "cloth",
}

const STRENGTHS := {
	"metal": ["plant", "wood"],
	"wood": ["spark", "sound"],
	"stone": ["metal", "ceramic"],
	"ceramic": ["toxin", "flame"],
	"glass": ["toxin", "air"],
	"plastic": ["flow", "glass"],
	"cloth": ["stone", "sound"],
	"paper": ["food", "stone"],
	"plant": ["flow", "air"],
	"food": ["fauna", "frost"],
	"fauna": ["plant", "cloth"],
	"flow": ["spark", "paper"],
	"spark": ["cloth", "metal"],
	"flame": ["wood", "frost"],
	"frost": ["fauna", "plastic"],
	"air": ["flame", "paper"],
	"toxin": ["food", "plastic"],
	"sound": ["glass", "ceramic"],
}

const MATCHUP_STRONG := 1.5
const MATCHUP_WEAK := 0.67
const MATCHUP_NEUTRAL := 1.0


static func normalize(element: Variant, fallback: String = "stone") -> String:
	var value := str(element if element != null else "").strip_edges().to_lower()
	if value in ROSTER:
		return value
	var aliased := str(ALIASES.get(value, ""))
	if not aliased.is_empty() and aliased in ROSTER:
		return aliased
	return fallback


static func single_matchup(attacker: Variant, defender: Variant) -> float:
	var atk := normalize(attacker, "")
	var def := normalize(defender, "")
	if atk.is_empty() or def.is_empty():
		return MATCHUP_NEUTRAL
	if atk in STRENGTHS and def in STRENGTHS[atk]:
		return MATCHUP_STRONG
	if def in STRENGTHS and atk in STRENGTHS[def]:
		return MATCHUP_WEAK
	return MATCHUP_NEUTRAL


static func defense_elements(primary: Variant, secondary: Variant = null) -> Array:
	var elements: Array = []
	var primary_norm := normalize(primary, "")
	if not primary_norm.is_empty():
		elements.append(primary_norm)
	var secondary_norm := normalize(secondary, "")
	if not secondary_norm.is_empty() and secondary_norm != primary_norm:
		elements.append(secondary_norm)
	return elements


## Weakness dan resistance saling membatalkan, dan multiplier tidak menumpuk.
static func dual_defender_multiplier(
	attacker: Variant, primary: Variant, secondary: Variant = null
) -> float:
	var defenses := defense_elements(primary, secondary)
	if defenses.size() <= 1:
		return single_matchup(attacker, defenses[0] if defenses.size() == 1 else "")

	var has_strong := false
	var has_weak := false
	for defense in defenses:
		var value := single_matchup(attacker, defense)
		if value > MATCHUP_NEUTRAL:
			has_strong = true
		elif value < MATCHUP_NEUTRAL:
			has_weak = true
	if has_strong and has_weak:
		return MATCHUP_NEUTRAL
	if has_strong:
		return MATCHUP_STRONG
	if has_weak:
		return MATCHUP_WEAK
	return MATCHUP_NEUTRAL
