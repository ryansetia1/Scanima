extends SceneTree

## Kontrak care murni, tanpa scene dan tanpa jaringan:
##
##   /Applications/Godot.app/Contents/MacOS/Godot --headless --path game \
##     --script res://tests/test_game_rules.gd

const BATTLE_EVENT := preload("res://scripts/battle_event.gd")
const BATTLE_SCALE := preload("res://scripts/battle_scale.gd")

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
	_check_eq(after_2h["hunger"], 92.0, "dua jam aktif harus memotong Hunger 8")
	var after_8h := CareRules.apply_decay(full, 0.0, 8.0 * 3600.0)
	_check_eq(after_8h["hunger"], 68.0, "delapan jam aktif harus memotong Hunger 32")
	var after_18h := CareRules.apply_decay(full, 0.0, 18.0 * 3600.0)
	_check_eq(after_18h["hunger"], 28.0, "delapan belas jam aktif memotong Hunger 72")
	var after_25h := CareRules.apply_decay(full, 0.0, 25.0 * 3600.0)
	_check_eq(after_25h["hunger"], 0.0, "Hunger aktif habis dalam 25 jam")
	_check_eq(after_18h["energy"], 0.0, "Energy habis sebelum 18 jam bangun")
	_check(is_equal_approx(after_18h["hygiene"], 24.4), "Hygiene turun 4.2 per jam")
	var after_56h := CareRules.apply_decay(full, 0.0, 56.0 * 3600.0)
	var after_week := CareRules.apply_decay(full, 0.0, 168.0 * 3600.0)
	_check_eq(after_56h, after_week, "48 jam efektif harus menjadi cap")
	for need in CareRules.DEFAULT_CARE:
		_check(after_week[need] >= 0.0 and after_week[need] <= 100.0, "%s tetap 0–100" % need)
	var bench_8h := CareRules.apply_decay(full, 0.0, 8.0 * 3600.0, 0.0, -1.0, -1.0, true)
	_check_eq(bench_8h["hunger"], 92.0, "delapan jam bangku memotong Hunger 8")
	_check(is_equal_approx(bench_8h["hygiene"], 91.6), "Hygiene bangku turun 1.05 per jam")
	var bench_48h := CareRules.apply_decay(full, 0.0, 48.0 * 3600.0, 0.0, -1.0, -1.0, true)
	_check_eq(bench_48h["hunger"], 52.0, "48 jam bangku menahan Hunger di atas 40")
	_check_eq(bench_48h["hygiene"], 50.0, "Hygiene bangku tidak turun di bawah 50")
	var bench_starved := CareRules.apply_decay(
		{"hunger": 10.0, "energy": 100.0, "hygiene": 10.0, "bond": 0.0},
		0.0,
		2.0 * 3600.0,
		0.0,
		-1.0,
		-1.0,
		true
	)
	_check_eq(bench_starved["hunger"], 8.0, "bangku tidak mengangkat Hunger yang sudah di bawah 40")
	_check(is_equal_approx(bench_starved["hygiene"], 7.9), "bangku tidak mengangkat Hygiene yang sudah di bawah 50")
	var bench_at_floor := CareRules.apply_decay(
		{"hunger": 40.0, "energy": 100.0, "hygiene": 50.0, "bond": 0.0},
		0.0,
		8.0 * 3600.0,
		0.0,
		-1.0,
		-1.0,
		true
	)
	_check_eq(bench_at_floor["hunger"], 40.0, "Hunger yang sudah di floor bangku tertahan")
	_check_eq(bench_at_floor["hygiene"], 50.0, "Hygiene yang sudah di floor bangku tertahan")

	print("3. EXP menentukan Level, Bond tidak luntur")
	var hunger_only := CareRules.apply_decay(
		{"hunger": 0.0, "energy": 100.0, "hygiene": 100.0, "bond": 50.0},
		0.0,
		18.0 * 3600.0
	)
	_check_eq(hunger_only["bond"], 0.0, "Bond tidak dipakai dan selalu 0")
	_check_eq(CareRules.BATTLE_ENERGY_COST, 20.0, "Battle memotong 20 Energy")
	_check_eq(CareRules.BATTLE_MIN_HUNGER, 40.0, "pose Hungry menyala di bawah 40")
	_check(CareRules.is_hungry({"hunger": 39.0}), "Hunger 39 lapar")
	_check(not CareRules.is_hungry({"hunger": 40.0}), "Hunger 40 tidak lapar")
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
		not CareRules.enters_dormant({"hunger": 0, "hygiene": 0}, 48.0, true),
		"Anima bangku tidak masuk Dormant baru"
	)
	var bench_row := {
		"id": "bench-1",
		"care": {"hunger": 100.0, "energy": 100.0, "hygiene": 100.0, "bond": 0.0},
		"care_synced_at": "2026-01-01T00:00:00Z",
	}
	var bench_synced := CareRules.timestamp_seconds(bench_row["care_synced_at"])
	var bench_projected := CareRules.projected_care(
		bench_row, "active-1", bench_synced + 48.0 * 3600.0
	)
	_check_eq(bench_projected["hunger"], 52.0, "projected_care bangku memakai decay 1/jam")
	_check_eq(bench_projected["hygiene"], 50.0, "projected_care bangku menghormati floor Hygiene")
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
				"id": "b",
				"sleep_started_at": "2026-08-14T00:00:00Z",
				"care": {"hunger": 20.0, "energy": 100.0, "hygiene": 80.0},
			},
			"a"
		),
		"hungry",
		"Energy penuh tapi lapar memakai pose Hungry di Collection"
	)
	_check_eq(
		CareRules.collection_pose(
			{
				"id": "b",
				"sleep_started_at": "2026-08-14T00:00:00Z",
				"care": {"hunger": 80.0, "energy": 100.0, "hygiene": 20.0},
			},
			"a"
		),
		"dirty",
		"Energy penuh tapi kotor memakai pose Dirty di Collection"
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

	print("7. eligibility Battle lobby vs picker bangku")
	_check_eq(CareRules.battle_unavailable_key({}), "BATTLE_NO_ANIMA", "row kosong menolak Battle")
	var active_sleep := {
		"id": "active",
		"status": "ready",
		"sleep_started_at": "2026-08-14T00:00:00Z",
		"care": {"hunger": 80.0, "energy": 80.0, "hygiene": 80.0, "bond": 0.0},
	}
	_check_eq(
		CareRules.battle_unavailable_key(active_sleep, "active", false),
		"BATTLE_ANIMA_SLEEPING",
		"companion aktif yang tidur menolak lobby"
	)
	_check_eq(
		CareRules.battle_unavailable_key(active_sleep, "active", true),
		"BATTLE_ANIMA_SLEEPING",
		"companion aktif yang tidur tetap redup di picker"
	)
	var bench := {
		"id": "bench",
		"status": "ready",
		"sleep_started_at": "2026-08-14T00:00:00Z",
		"sleep_energy_at_start": 0.0,
		"care_synced_at": "2026-08-14T00:00:00Z",
		"care": {"hunger": 100.0, "energy": 0.0, "hygiene": 100.0, "bond": 0.0},
	}
	var full_energy_at := Time.get_unix_time_from_datetime_string("2026-08-14T03:00:00Z")
	var hungry_at := Time.get_unix_time_from_datetime_string("2026-08-14T07:00:00Z")
	_check_eq(
		CareRules.battle_unavailable_key(bench, "active", true, full_energy_at),
		"",
		"bangku tidur dengan Energy penuh dan Hunger cukup lolos picker"
	)
	_check_eq(
		CareRules.battle_unavailable_key(bench, "active", true, hungry_at),
		"",
		"bangku lapar tetap lolos picker supaya Bits tidak terkunci di belakang makanan"
	)
	_check_eq(
		CareRules.battle_pick_reason_key("BATTLE_ANIMA_LOW_ENERGY"),
		"BATTLE_PICK_LOW_ENERGY",
		"alasan picker memakai label pendek"
	)

	print("12. tas Shop menulis ulang quantity dari respons")
	var bag: Array = [{"item_id": "power_chip", "quantity": 1}]
	_check_eq(Catalog.quantity_of(Catalog.with_quantity(bag, "power_chip", 3), "power_chip"), 3, "beli menambah tumpukan")
	_check_eq(Catalog.quantity_of(Catalog.with_quantity(bag, "power_chip", 0), "power_chip"), 0, "nol menghapus baris")
	_check_eq(Catalog.quantity_of(Catalog.with_quantity([], "vital_patch", 1), "vital_patch"), 1, "item baru masuk tas")

	print("13. canonical-height Battle scale")
	var render := {"render_metrics": {"reference_height_px": 300, "reference_width_px": 220}}
	var design_arena := BATTLE_SCALE.DESIGN_ARENA
	var small_scale := BATTLE_SCALE.fighter_scale(20.0, render, design_arena)
	var doll_scale := BATTLE_SCALE.fighter_scale(50.0, render, design_arena)
	var old_handheld_scale := BATTLE_SCALE.fighter_scale(100.0, render, design_arena)
	var normal_scale := BATTLE_SCALE.fighter_scale(120.0, render, design_arena)
	var giant_scale := BATTLE_SCALE.fighter_scale(2000.0, render, design_arena)
	_check(small_scale < normal_scale, "Anima 20 cm tampil lebih kecil dari Anima 120 cm")
	_check(doll_scale < old_handheld_scale, "floor boneka 50 cm lebih kecil dari companion 100 cm")
	_check(normal_scale < giant_scale, "Anima 2000 cm tetap terasa lebih besar")
	_check(
		300.0 * giant_scale <= BATTLE_SCALE.usable_height(design_arena) * 0.88 + 0.01,
		"tinggi raksasa tidak menutup HUD"
	)
	_check(small_scale >= 0.20, "Anima terkecil tetap terlihat")
	var roomy_arena := Vector2(720.0, 800.0)
	var roomy_pair := BATTLE_SCALE.fighter_pair_scales(
		120.0, render, 120.0, render, roomy_arena
	)
	_check(
		absf(300.0 * roomy_pair.x - roomy_arena.y * BATTLE_SCALE.ARENA_REFERENCE_HEIGHT_RATIO) < 1.0,
		"Anima 120 cm mengisi sekitar 45% kartu desain"
	)
	var arena_size := Vector2(550.0, 680.0)
	var veridian_render := {"render_metrics": {"reference_height_px": 327, "reference_width_px": 274}}
	var fudge_render := {"render_metrics": {"reference_height_px": 235, "reference_width_px": 326}}
	var pair_scales := BATTLE_SCALE.fighter_pair_scales(
		175.0, veridian_render, 135.0, fudge_render, arena_size
	)
	var rendered_veridian_height := 327.0 * pair_scales.x
	var rendered_fudge_height := 235.0 * pair_scales.y
	var expected_height_ratio: float = pow(175.0 / 135.0, BATTLE_SCALE.BODY_HEIGHT_CURVE)
	_check(
		absf(rendered_veridian_height / rendered_fudge_height - expected_height_ratio) < 0.001,
		"rasio tinggi kanonis tetap meski Fudge lebih lebar"
	)
	var seeker_render := {"render_metrics": {"reference_height_px": 282, "reference_width_px": 158}}
	var phone_arena := Vector2(720.0, 800.0)
	var wide_arena := Vector2(1100.0, 800.0)
	var tall_arena := Vector2(720.0, 1600.0)
	var narrow_arena := Vector2(400.0, 1600.0)
	var phone_pair := BATTLE_SCALE.fighter_pair_scales(
		175.0, veridian_render, 135.0, fudge_render, phone_arena
	)
	var wide_pair := BATTLE_SCALE.fighter_pair_scales(
		175.0, veridian_render, 135.0, fudge_render, wide_arena
	)
	var tall_pair := BATTLE_SCALE.fighter_pair_scales(
		175.0, veridian_render, 135.0, fudge_render, tall_arena
	)
	var narrow_pair := BATTLE_SCALE.fighter_pair_scales(
		175.0, veridian_render, 135.0, fudge_render, narrow_arena
	)
	_check(
		is_equal_approx(phone_pair.x, wide_pair.x) and is_equal_approx(phone_pair.y, wide_pair.y),
		"lebar ekstra tidak mengubah skala"
	)
	_check(
		is_equal_approx(phone_pair.x, tall_pair.x) and is_equal_approx(phone_pair.y, tall_pair.y),
		"tinggi ekstra tidak mengubah skala"
	)
	_check(
		is_equal_approx(phone_pair.x, narrow_pair.x) and is_equal_approx(phone_pair.y, narrow_pair.y),
		"lebar layar tidak mengubah skala Anima maupun Seeker"
	)
	var short_arena := Vector2(400.0, 500.0)
	var short_pair := BATTLE_SCALE.fighter_pair_scales(
		175.0, veridian_render, 135.0, fudge_render, short_arena
	)
	_check(
		short_pair.x < phone_pair.x - 0.01,
		"arena yang lebih pendek dari kartu desain mengecilkan semua tubuh bersama"
	)
	var trio := BATTLE_SCALE.shared_scales(
		[175.0, 135.0, 156.0],
		[veridian_render, fudge_render, seeker_render],
		narrow_arena
	)
	_check(trio.size() == 3, "shared_scales menerima Seeker sebagai tubuh ketiga")
	_check(
		absf((327.0 * trio[0]) / (235.0 * trio[1]) - 175.0 / 135.0) < 0.02,
		"di samping Seeker, rasio tinggi Anima mengikuti cm kanonis"
	)
	var rendered_seeker_height := 282.0 * trio[2]
	var rendered_trio_fudge := 235.0 * trio[1]
	var solo_seeker := BATTLE_SCALE.fighter_scale(156.0, seeker_render, phone_arena)
	_check(
		is_equal_approx(trio[2], solo_seeker)
		and rendered_seeker_height / rendered_trio_fudge > pow(
			156.0 / 135.0, BATTLE_SCALE.BODY_HEIGHT_CURVE
		),
		"fit lebar Anima tidak mengerdilkan Seeker di back lane"
	)
	var crowded := BATTLE_SCALE.shared_scales(
		[150.0, 135.0, 156.0],
		[veridian_render, fudge_render, seeker_render],
		phone_arena
	)
	_check(
		absf((327.0 * crowded[0]) / (235.0 * crowded[1]) - 150.0 / 135.0) < 0.02,
		"tubuh lebar mempertahankan rasio tinggi sebelum kamera memuat shot"
	)
	_check(
		is_equal_approx(crowded[2], solo_seeker),
		"shot lebar hanya mengecilkan dua Anima"
	)
	var solo_group := BATTLE_SCALE.shared_scales(
		[156.0], [seeker_render], phone_arena
	)
	_check(
		is_equal_approx(solo_group[0], solo_seeker),
		"Seeker sendirian tidak kena fit lebar"
	)
	var anchors := [20.0, 50.0, 120.0, 300.0, 800.0, 2000.0]
	var rendered: PackedFloat32Array = PackedFloat32Array()
	rendered.resize(anchors.size())
	var arena_h := BATTLE_SCALE.usable_height(design_arena)
	var cap_h := arena_h * 0.88
	for index in anchors.size():
		rendered[index] = 300.0 * BATTLE_SCALE.fighter_scale(anchors[index], render, design_arena)
		_check(rendered[index] <= cap_h + 0.01, "anchor %s cm tetap full-body di bawah cap HUD" % str(anchors[index]))
	for index in range(1, anchors.size()):
		_check(
			rendered[index] + 0.01 >= rendered[index - 1],
			"tinggi %s cm tidak lebih kecil dari %s cm" % [str(anchors[index]), str(anchors[index - 1])]
		)
	_check(rendered[0] < rendered[1], "20 cm lebih kecil dari 50 cm")
	_check(rendered[1] < rendered[2], "50 cm lebih kecil dari 120 cm")
	_check(rendered[2] < rendered[3], "120 cm lebih kecil dari 300 cm")
	_check(rendered[0] >= arena_h * BATTLE_SCALE.ARENA_REFERENCE_HEIGHT_RATIO * 0.42 - 0.01, "tubuh 20 cm tetap di readability floor")
	_check_eq(
		BATTLE_SCALE.anima_display_height_cm(2000.0),
		BATTLE_SCALE.ANIMA_VISUAL_HEIGHT_CAP_CM,
		"20 m Anima tampil sebagai 3 m"
	)
	_check_eq(
		BATTLE_SCALE.anima_display_height_cm(165.0),
		165.0,
		"tinggi di bawah cap tidak diubah"
	)
	var capped_pair := BATTLE_SCALE.fighter_pair_scales(
		2000.0, render, 300.0, render, design_arena
	)
	_check(
		is_equal_approx(capped_pair.x, capped_pair.y),
		"20 m dan 3 m memakai skala Anima yang sama"
	)
	var colossal_pair := BATTLE_SCALE.fighter_pair_scales(
		2000.0, render, 2000.0, render, design_arena
	)
	_check(
		absf(colossal_pair.x - colossal_pair.y) < 0.001
		and 300.0 * colossal_pair.x <= cap_h + 0.01,
		"pasangan 20 m menjaga rasio 1:1 di bawah cap HUD"
	)
	var mixed_pair := BATTLE_SCALE.fighter_pair_scales(
		50.0, render, 2000.0, render, design_arena
	)
	var solo_small := BATTLE_SCALE.fighter_scale(50.0, render, design_arena)
	var solo_capped := BATTLE_SCALE.fighter_scale(
		BATTLE_SCALE.ANIMA_VISUAL_HEIGHT_CAP_CM, render, design_arena
	)
	_check(
		is_equal_approx(mixed_pair.x, solo_small)
		and is_equal_approx(mixed_pair.y, solo_capped),
		"Anima 20 m tidak mengubah rasio dasar pasangan 50 cm sebelum camera zoom"
	)
	var seeker_165 := BATTLE_SCALE.fighter_scale(165.0, seeker_render, phone_arena)
	var giant_trio := BATTLE_SCALE.shared_scales(
		[2000.0, 135.0, 165.0],
		[veridian_render, fudge_render, seeker_render],
		phone_arena
	)
	var normal_trio := BATTLE_SCALE.shared_scales(
		[150.0, 135.0, 165.0],
		[veridian_render, fudge_render, seeker_render],
		phone_arena
	)
	_check(
		is_equal_approx(giant_trio[2], seeker_165)
		and is_equal_approx(normal_trio[2], seeker_165),
		"cap 3 m Anima tidak mengubah skala Boss Seeker"
	)
	_check(
		BATTLE_SCALE.anima_behind_seeker(2000.0, 165.0)
		and BATTLE_SCALE.anima_behind_seeker(150.0, 165.0)
		and not BATTLE_SCALE.anima_behind_seeker(90.0, 165.0),
		"Anima di belakang Seeker hanya jika tampilannya > 60% tinggi Seeker"
	)
	var seeker_px := 282.0 * giant_trio[2]
	_check(
		327.0 * normal_trio[0] < seeker_px - 1.0,
		"Veridian 150 cm lebih pendek dari Seeker 165 cm"
	)
	_check(
		absf((327.0 * giant_trio[0]) / seeker_px - 300.0 / 165.0) < 0.02,
		"Anima 3 m di layar hampir 2× Seeker 165 cm"
	)

	print("14. gallery transport")
	var backend_text := FileAccess.get_file_as_string("res://scripts/backend.gd")
	_check(backend_text.find("func gallery(") >= 0, "Backend exposes gallery edge transport")
	_check(backend_text.find("gallery_thumb_cache_path") >= 0, "gallery thumbs cache bounded per entry id")
	_check(backend_text.find("download_url") >= 0, "signed gallery and battle art use ephemeral URL download")

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
