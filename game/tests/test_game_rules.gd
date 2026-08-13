extends SceneTree

## Kontrak care murni, tanpa scene dan tanpa jaringan:
##
##   /Applications/Godot.app/Contents/MacOS/Godot --headless --path game \
##     --script res://tests/test_game_rules.gd

const BATTLE_EVENT := preload("res://scripts/battle_event.gd")

var _checks := 0
var _failures: PackedStringArray = []


func _initialize() -> void:
	print("1. normalisasi kebutuhan")
	var normalized := CareRules.normalized_care({"hunger": 120, "energy": -2, "hygiene": 50})
	_check_eq(normalized["hunger"], 100.0, "Hunger dijepit ke 100")
	_check_eq(normalized["energy"], 0.0, "Energy dijepit ke 0")
	_check_eq(normalized["hygiene"], 50.0, "Hygiene dipertahankan")
	_check_eq(normalized["bond"], 0.0, "Bond yang hilang memakai default")

	print("2. decay berjalan sejak sync terakhir, cap 48 jam")
	var full := {"hunger": 100.0, "energy": 100.0, "hygiene": 100.0, "bond": 50.0}
	var after_2h := CareRules.apply_decay(full, 0.0, 2.0 * 3600.0)
	_check_eq(after_2h["hunger"], 80.0, "dua jam harus memotong Hunger 20")
	var after_8h := CareRules.apply_decay(full, 0.0, 8.0 * 3600.0)
	_check_eq(after_8h["hunger"], 20.0, "delapan jam harus memotong Hunger 80")
	var after_18h := CareRules.apply_decay(full, 0.0, 18.0 * 3600.0)
	_check_eq(after_18h["hunger"], 0.0, "Hunger habis dalam 10 jam")
	_check_eq(after_18h["energy"], 0.0, "Energy habis sebelum 18 jam bangun")
	_check(is_equal_approx(after_18h["hygiene"], 24.4), "Hygiene turun 4.2 per jam")
	var after_56h := CareRules.apply_decay(full, 0.0, 56.0 * 3600.0)
	var after_week := CareRules.apply_decay(full, 0.0, 168.0 * 3600.0)
	_check_eq(after_56h, after_week, "48 jam efektif harus menjadi cap")
	for need in CareRules.DEFAULT_CARE:
		_check(after_week[need] >= 0.0 and after_week[need] <= 100.0, "%s tetap 0–100" % need)

	print("3. EXP menentukan Level, Bond tidak luntur")
	var hunger_only := CareRules.apply_decay(
		{"hunger": 0.0, "energy": 100.0, "hygiene": 100.0, "bond": 50.0},
		0.0,
		18.0 * 3600.0
	)
	_check_eq(hunger_only["bond"], 0.0, "Bond tidak dipakai dan selalu 0")
	_check_eq(CareRules.BATTLE_ENERGY_COST, 20.0, "Battle memotong 20 Energy")
	_check_eq(CareRules.level_from_exp(0), 1, "0 EXP adalah Lv 1")
	_check_eq(CareRules.level_from_exp(4), 1, "4 EXP masih Lv 1")
	_check_eq(CareRules.level_from_exp(5), 2, "5 EXP adalah Lv 2")
	_check_eq(CareRules.level_from_exp(75), 16, "75 EXP adalah Lv 16")
	_check_eq(CareRules.level_from_exp(175), 36, "175 EXP adalah Lv 36")
	_check_eq(CareRules.level_from_exp(999), 40, "Level di-cap 40")
	_check_eq(CareRules.form_key(1), "hatchling", "Lv 1 Hatchling")
	_check_eq(CareRules.form_key(16), "adult", "Lv 16 Adult")
	_check_eq(CareRules.form_key(36), "evolved", "Lv 36 Evolved")
	_check_eq(CareRules.growth_multiplier(1), 1.0, "Lv 1 tidak mengubah stat")
	_check(is_equal_approx(CareRules.growth_multiplier(16), 1.45), "Lv 16 lompat +0.15")
	_check(is_equal_approx(CareRules.growth_multiplier(36), 2.05), "Lv 36 lompat kedua")
	_check_eq(CareRules.grown_stat(50, 75), 72, "stat tumbuh terpotong ke bawah")
	_check_eq(CareRules.leveled_up(4, 5), 2, "5 EXP menyeberang ke Lv 2")
	_check_eq(CareRules.leveled_up(4, 4), 0, "EXP sama bukan naik level")
	_check_eq(CareRules.leveled_up(74, 75), 16, "75 EXP menyeberang ke Adult")
	_check_eq(CareRules.leveled_up(195, 200), 0, "EXP di atas cap bukan naik level")

	print("4. tidur pulih linear dari nilai awal")
	var tired := {"hunger": 100.0, "energy": 0.0, "hygiene": 100.0, "bond": 0.0}
	var half_sleep := CareRules.apply_decay(tired, 0.0, 3.0 * 3600.0, 1.0, 0.0)
	# sleep_started_at=1 menghindari sentinel nol; selisihnya praktis tiga jam.
	_check(absf(half_sleep["energy"] - 50.0) < 0.1, "tidur tiga jam memulihkan setengah")
	var full_sleep := CareRules.apply_decay(tired, 0.0, 6.0 * 3600.0, 1.0, 0.0)
	_check(absf(full_sleep["energy"] - 100.0) < 0.1, "tidur enam jam mengisi penuh")

	print("5. EXP, Dormant, dan gerbang aksi")
	_check_eq(CareRules.score_for_action("feed", {"hunger": 39}), 3, "Feed lapar memberi score")
	_check_eq(CareRules.score_for_action("feed", {"hunger": 40}), 0, "Feed Hunger 40 tidak memberi score")
	_check_eq(CareRules.score_for_action("clean", {"hygiene": 49}), 3, "Clean kotor memberi score")
	_check_eq(CareRules.score_for_action("clean", {"hygiene": 50}), 0, "Clean Hygiene 50 tidak memberi score")
	_check_eq(CareRules.score_for_action("play", {}, 4), 1, "Play kelima memberi score")
	_check_eq(CareRules.score_for_action("play", {}, 5), 0, "Play keenam tidak memberi score")
	_check_eq(
		CareRules.play_exp_remaining({
			"play_score_on": "2026-08-14",
			"play_score_today": 2,
			"care_synced_at": "2026-08-14T12:00:00Z",
		}),
		3,
		"sisa Play EXP memakai tanggal UTC server"
	)
	_check_eq(
		CareRules.play_exp_remaining({
			"play_score_on": "2026-08-13",
			"play_score_today": 5,
			"care_synced_at": "2026-08-14T00:10:00Z",
		}),
		5,
		"jatah Play EXP pulih di hari UTC baru"
	)
	_check(
		CareRules.enters_dormant({"hunger": 0, "hygiene": 0}, 48.0),
		"dua kebutuhan nol pada cap masuk Dormant"
	)
	_check(
		not CareRules.enters_dormant({"hunger": 0, "hygiene": 0}, 47.9),
		"sebelum cap belum Dormant"
	)
	_check(
		not CareRules.can_recover_from_dormant({"hunger": 70, "hygiene": 35}),
		"satu kebutuhan saja belum memulihkan Dormant"
	)
	_check(
		CareRules.can_recover_from_dormant({"hunger": 70, "hygiene": 70}),
		"dua kebutuhan di atas 50 memulihkan Dormant"
	)

	print("6. kontrak event Battle client")
	var attack: Dictionary = BATTLE_EVENT.normalized({
		"type": "attack",
		"actor": "player",
		"target": "bot",
		"action": "strike",
		"damage": 24,
		"target_hp": 81,
	})
	_check_eq(attack.get("damage"), 24, "event attack server yang sah diterima")
	_check(
		BATTLE_EVENT.normalized({
			"type": "attack", "actor": "player", "target": "owner_id", "damage": 2,
		}).is_empty(),
		"target event yang tidak dikenal ditolak"
	)
	_check(
		BATTLE_EVENT.normalized({"type": "reward", "bits": 999}).is_empty(),
		"client tidak menerima event reward buatan sebagai combat event"
	)

	_finish()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)


func _check_eq(actual: Variant, expected: Variant, message: String) -> void:
	_check(actual == expected, "%s: dapat %s, mau %s" % [message, str(actual), str(expected)])


func _finish() -> void:
	if _failures.is_empty():
		print("test_game_rules: OK (%d check)" % _checks)
		quit(0)
		return
	printerr("test_game_rules: GAGAL %d dari %d check" % [_failures.size(), _checks])
	for failure in _failures:
		printerr("  - %s" % failure)
	quit(1)
