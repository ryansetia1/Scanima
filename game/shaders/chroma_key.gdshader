shader_type canvas_item;

// Chroma key di GPU. Ini JALUR CADANGAN, bukan jalur utama.
//
// Jalur utama menghapus hijau di backend dan menyimpan PNG RGBA, karena keying
// adalah pekerjaan sekali per spesies, sementara shader ini mengerjakannya ulang
// setiap frame di HP pemain. Shader ini dipakai hanya di mode BYOK, di mana
// gambar datang langsung dari Replicate tanpa lewat Edge Function.
//
// Yang TIDAK bisa dikerjakan shader ini, dan karena itu mode BYOK tetap
// bergantung pada region grid buta 2x2: mencari bounding box, menyeragamkan
// ukuran frame, dan menolak sheet yang cacat. Ketiganya butuh membaca seluruh
// piksel sekaligus, sesuatu yang fragment shader tidak bisa lakukan.
//
// Ambangnya harus tetap sama dengan backend/supabase/functions/_shared/postprocess.mjs. Kalau berbeda, sprite
// yang sama akan tampil beda antara pemain biasa dan pemain BYOK.

uniform vec3 key_color : source_color = vec3(0.0, 1.0, 0.0);
uniform float hue_tolerance : hint_range(0.0, 0.25) = 0.061; // 22 derajat / 360
uniform float sat_min : hint_range(0.0, 1.0) = 0.85;
uniform float val_min : hint_range(0.0, 1.0) = 0.5;
uniform float softness : hint_range(0.001, 0.1) = 0.03;

vec3 rgb_to_hsv(vec3 c) {
	float max_c = max(c.r, max(c.g, c.b));
	float min_c = min(c.r, min(c.g, c.b));
	float delta = max_c - min_c;

	float hue = 0.0;
	if (delta > 0.00001) {
		if (max_c == c.r) {
			hue = mod((c.g - c.b) / delta, 6.0);
		} else if (max_c == c.g) {
			hue = (c.b - c.r) / delta + 2.0;
		} else {
			hue = (c.r - c.g) / delta + 4.0;
		}
		hue /= 6.0;
		if (hue < 0.0) {
			hue += 1.0;
		}
	}

	float sat = max_c > 0.00001 ? delta / max_c : 0.0;
	return vec3(hue, sat, max_c);
}

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	vec3 hsv = rgb_to_hsv(tex.rgb);
	vec3 key = rgb_to_hsv(key_color);

	// Hue itu lingkaran: tanpa pembungkusan ini, hijau di dekat 0.0 lolos.
	float hue_dist = abs(hsv.x - key.x);
	hue_dist = min(hue_dist, 1.0 - hue_dist);

	// Piksel dipertahankan kalau hue-nya jauh dari kunci, ATAU saturasinya
	// rendah, ATAU gelap. Syarat "atau" inilah yang menyelamatkan tubuh Anima
	// berelemen plant: hijau daun saturasinya jauh di bawah 0.85.
	float keep = smoothstep(hue_tolerance, hue_tolerance + softness, hue_dist);
	keep = max(keep, 1.0 - smoothstep(sat_min - softness, sat_min, hsv.y));
	keep = max(keep, 1.0 - smoothstep(val_min - softness, val_min, hsv.z));

	COLOR = vec4(tex.rgb, tex.a * keep);
}
