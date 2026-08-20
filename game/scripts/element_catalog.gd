class_name ElementCatalog
extends RefCounted

## Lapisan presentasi elemen: label dan teks bantuan. Elemen tidak punya ikon —
## delapan belas roster berarti delapan belas aset yang harus dijaga konsisten,
## sementara namanya sudah cukup di setiap layar yang menampilkannya.
##
## Normalisasi dimiliki `ElementRules`, dan file ini sengaja tidak punya
## salinannya sendiri. Salinan lama menerima `String`, sehingga pemanggil harus
## menulis `str(row.get("secondary_element"))` — dan `str(null)` PostgREST
## menghasilkan `"<null>"`, bukan string kosong. String itu lalu jatuh ke
## fallback dan setiap Anima tanpa elemen kedua tampil sebagai `· Stone`.
##
## `typing_version` juga tidak lagi dibaca di sini: keberadaan
## `secondary_element` adalah satu-satunya syarat yang dipakai server saat
## menghitung damage (`defenseElements()`), dan constraint
## `animas_secondary_v1_null` sudah menjamin row typing_version 1 selalu null.
## Membacanya kembali berarti label bisa berbeda dari matchup yang benar-benar
## dipakai, dan payload yang tidak memproyeksikan kolom itu — roster Team,
## `atlas_forms` — kehilangan elemen keduanya tanpa sebab yang terlihat.


static func compact_label(row: Dictionary) -> String:
	var primary := ElementRules.normalize(row.get("element"))
	var secondary := ElementRules.normalize(row.get("secondary_element"), "")
	if secondary.is_empty() or secondary == primary:
		return LocaleManager.element_name(primary)
	return TranslationServer.translate("ELEMENT_PAIR") % [
		LocaleManager.element_name(primary),
		LocaleManager.element_name(secondary),
	]


static func help_text(code: String) -> String:
	var key := "ELEMENT_%s_HELP" % ElementRules.normalize(code, "unknown").to_upper()
	var translated := TranslationServer.translate(key)
	return translated if translated != key else TranslationServer.translate("DETAILS_ELEMENT_HELP")
