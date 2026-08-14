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
	_check_eq(CareRules.BATTLE_MIN_HUNGER, 40.0, "Battle menolak Hunger di bawah pose Hungry")
	_check(CareRules.is_hungry({"hunger": 39.0}), "Hunger 39 lapar")
	_check(not CareRules.is_hungry({"hunger": 40.0}), "Hunger 40 siap Battle")
	_check(CareRules.need_is_low({"hunger": 39.0}, "hunger"), "Hunger di bawah pose Hungry menandai panel")
	_check(not CareRules.need_is_low({"hunger": 40.0}, "hunger"), "Hunger 40 tidak menandai panel")
	_check(CareRules.need_is_low({"hygiene": 49.0}, "hygiene"), "Hygiene di bawah pose Dirty menandai panel")
	_check(not CareRules.need_is_low({"hygiene": 50.0}, "hygiene"), "Hygiene 50 tidak menandai panel")
	_check(CareRules.need_is_low({"energy": 19.0}, "energy"), "Energy di bawah biaya Battle menandai panel")
	_check(not CareRules.need_is_low({"energy": 20.0}, "energy"), "Energy 20 tidak menandai panel")
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
	var bench_half := CareRules.apply_decay(
		tired, 0.0, 1.5 * 3600.0, 1.0, 0.0, CareRules.BENCH_SLEEP_FULL_HOURS
	)
	_check(absf(bench_half["energy"] - 50.0) < 0.1, "tidur Collection 1.5 jam memulihkan setengah")
	var bench_full := CareRules.apply_decay(
		tired, 0.0, 3.0 * 3600.0, 1.0, 0.0, CareRules.BENCH_SLEEP_FULL_HOURS
	)
	_check(absf(bench_full["energy"] - 100.0) < 0.1, "tidur Collection tiga jam mengisi penuh")

	print("5. EXP, Dormant, dan gerbang aksi")
	_check_eq(CareRules.score_for_action("feed", {"hunger": 39}), 3, "Feed lapar dengan restore default memberi score")
	_check_eq(CareRules.score_for_action("feed", {"hunger": 40}), 0, "Feed Hunger 40 tidak memberi score")
	_check_eq(CareRules.score_for_action("feed", {"hunger": 0}, 0, 10), 0, "Byte Berry dari 0 tidak menyeberang 40")
	_check_eq(CareRules.score_for_action("feed", {"hunger": 0}, 0, 45), 3, "Ember Noodles dari 0 menyeberang 40")
	_check_eq(CareRules.score_for_action("feed", {"hunger": 35}, 0, 10), 3, "restore kecil tetap +3 saat menyeberang 40")
	_check_eq(CareRules.score_for_action("clean", {"hygiene": 49}), 3, "Clean kotor memberi score")
	_check_eq(CareRules.score_for_action("clean", {"hygiene": 50}), 0, "Clean Hygiene 50 tidak memberi score")
	_check_eq(CareRules.score_for_action("play", {}, 4), 1, "Play kelima memberi score")
	_check_eq(CareRules.score_for_action("play", {}, 5), 0, "Play keenam tidak memberi score")
	_check(CareRules.need_is_full({"hunger": 100.0}, "hunger"), "Hunger 100 penuh")
	_check(CareRules.need_is_full({"hunger": 99.5}, "hunger"), "Hunger 99.5 tampil penuh")
	_check(not CareRules.need_is_full({"hunger": 99.4}, "hunger"), "Hunger 99.4 masih bisa Feed")
	_check(CareRules.need_is_full({"hygiene": 99.99}, "hygiene"), "Hygiene 99.99 tampil penuh")
	_check(not CareRules.need_is_full({"hygiene": 80.0}, "hygiene"), "Hygiene 80 masih bisa Clean")
	_check_eq(
		CareRules.play_exp_remaining({
			"play_score_on": "2026-08-14",
			"play_score_today": 2,
			"care_synced_at": "2026-08-14T17:10:00Z",
		}, "2026-08-14"),
		3,
		"sisa Play EXP memakai hari sipil lokal, bukan prefix UTC"
	)
	_check_eq(
		CareRules.play_exp_remaining({
			"play_score_on": "2026-08-13",
			"play_score_today": 5,
			"care_synced_at": "2026-08-14T00:10:00Z",
		}, "2026-08-14"),
		5,
		"jatah Play EXP pulih di hari sipil lokal baru"
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
	_check_eq(
		BATTLE_EVENT.normalized({"type": "item", "actor": "player", "item_id": "vital_patch"}).get("type"),
		"item",
		"event item server yang sah diterima"
	)

	print("5. pose visual mengikuti Sleep, Dormant, lalu kebutuhan")
	_check_eq(CareRules.visual_pose(true, false), "sleep", "tidur mengalahkan kebutuhan")
	_check_eq(
		CareRules.collection_pose({"id": "a", "sleep_started_at": null}, "a"),
		"idle",
		"companion aktif yang bangun memakai pose Idle di Collection"
	)
	_check_eq(
		CareRules.collection_pose(
			{"id": "b", "care": {"hunger": 80.0, "energy": 40.0, "hygiene": 80.0}},
			"a"
		),
		"sleep",
		"Anima yang tidak di-Summon memakai pose Sleep di Collection selama Energy pulih"
	)
	_check_eq(
		CareRules.collection_pose(
			{
				"id": "b",
				"sleep_started_at": "2026-08-14T00:00:00Z",
				"care": {"hunger": 80.0, "energy": 100.0, "hygiene": 80.0},
			},
			"a"
		),
		"idle",
		"Energy penuh di Collection memakai pose Idle, siap Summon"
	)
	_check_eq(
		CareRules.collection_pose(
			{
				"id": "a",
				"sleep_started_at": "2026-08-14T00:00:00Z",
				"care": {"hunger": 80.0, "energy": 40.0, "hygiene": 80.0},
			},
			"a"
		),
		"sleep",
		"companion aktif yang tidur tetap Sleep di Collection selama Energy belum penuh"
	)
	_check_eq(
		CareRules.collection_pose({"id": "b", "dormant_since": "2026-08-14T00:00:00Z"}, "a"),
		"defeated",
		"Dormant mengalahkan pose Sleep di Collection"
	)
	var sleep_start := 1_000_000.0
	var started_iso := Time.get_datetime_string_from_unix_time(int(sleep_start), true)
	var recovering := {
		"id": "b",
		"sleep_started_at": started_iso,
		"sleep_energy_at_start": 10.0,
		"care_synced_at": started_iso,
		"care": {"hunger": 80.0, "energy": 10.0, "hygiene": 80.0},
	}
	_check_eq(
		CareRules.collection_pose(recovering, "a", sleep_start + 30.0 * 60.0),
		"sleep",
		"tidur Collection yang Energy-nya belum penuh tetap Sleep tanpa tap"
	)
	_check_eq(
		CareRules.collection_pose(recovering, "a", sleep_start + 3.0 * 3600.0),
		"idle",
		"Energy penuh dihitung dari timestamp tidur, bukan dari tap sync"
	)
	_check_eq(CareRules.visual_pose(false, true), "defeated", "Dormant mengalahkan kebutuhan")
	_check_eq(
		CareRules.visual_pose(false, false, {"hunger": 20.0, "energy": 80.0, "hygiene": 80.0}),
		"hungry",
		"Hunger rendah memakai Hungry"
	)
	_check_eq(
		CareRules.visual_pose(false, false, {"hunger": 80.0, "energy": 80.0, "hygiene": 20.0}),
		"dirty",
		"Hygiene rendah memakai Dirty"
	)
	_check_eq(
		CareRules.visual_pose(false, false, {"hunger": 80.0, "energy": 80.0, "hygiene": 80.0}),
		"idle",
		"kebutuhan tinggi memakai Idle; Happy hanya event Play/level-up/menang"
	)
	_check_eq(
		CareRules.visual_pose(false, false, {"hunger": 55.0, "energy": 55.0, "hygiene": 55.0}),
		"idle",
		"kebutuhan sedang memakai Idle"
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
