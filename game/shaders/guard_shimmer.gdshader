shader_type canvas_item;

// Guard "Harden": satu pita kilau menyapu badan Anima plus tepi silhouette yang
// menyala. Waktu tetap dimiliki Tween di AnimaPresenter — shader ini hanya
// memetakan progress 0..1 menjadi satu sapuan utuh, jadi tidak ada TIME dan
// tidak ada state yang bisa tertinggal menyala setelah tween dilepas.
//
// UV di sini adalah koordinat atlas, bukan 0..1 per pose. Itu aman karena
// AnimaLoader menolak manifest yang keempat region-nya tidak berukuran sama:
// jarak pita jadi identik di semua pose, dan sisa offset per pose hanya
// menggeser fase — tidak terlihat pada kilau.

uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform vec4 shimmer_tint : source_color = vec4(0.66, 0.90, 1.0, 1.0);
uniform float band_frequency : hint_range(4.0, 80.0) = 34.0;
uniform float band_travel : hint_range(0.0, 24.0) = 11.0;

void fragment() {
	// COLOR sudah berisi texture * modulate, jadi Dormant/tint care tetap ikut.
	// Piksel transparan digating lewat perkalian, bukan early return: Godot
	// menolak 'return' di dalam processor function.
	float body = step(0.004, COLOR.a);

	// Naik lalu turun sekali: satu pemanggilan sama dengan satu kilau utuh,
	// tanpa perlu tween kedua untuk memadamkannya.
	float envelope = sin(progress * PI);

	// Pita diagonal, fase bergerak mengikuti progress supaya kilaunya menyapu
	// dan bukan berdenyut di tempat.
	float wave = sin((UV.y + UV.x * 0.45) * band_frequency - progress * band_travel);
	float band = smoothstep(0.55, 1.0, wave);

	// Piksel bertepi lembut hasil keying dipakai sebagai rim: badan terlihat
	// mengeras, bukan hanya menjadi terang rata.
	float rim = 1.0 - smoothstep(0.35, 1.0, COLOR.a);

	float glow = clamp(envelope * (band * 0.55 + rim * 0.70 + 0.18), 0.0, 1.0) * body;
	COLOR.rgb = mix(COLOR.rgb, COLOR.rgb + shimmer_tint.rgb, glow);
}
