class_name DeterministicRng
extends RefCounted

## Port 1:1 dari `seededRandom()` / `hashSeed()` di
## `backend/supabase/functions/_shared/battle.mjs`. Nilai yang dihasilkan wajib
## identik dengan runtime Deno, karena server menghitung ulang setiap turn dari
## command yang sama. Paritasnya dijaga `tests/test_battle_sim_parity.gd`
## memakai vektor yang digenerasi dari `.mjs` aslinya.

const MASK32 := 0xFFFFFFFF
const FNV_OFFSET_BASIS := 2166136261
const FNV_PRIME := 16777619
const SPLITMIX_GAMMA := 0x6d2b79f5

var _state: int = 0


func _init(seed_text: String = "") -> void:
	_state = hash_seed(seed_text)


## JS `Math.imul`: perkalian 32-bit. Hasil penuh 64-bit meluap di GDScript
## (0xFFFFFFFF^2 melewati batas int), jadi operand dipecah 16-bit dulu.
static func imul32(a: int, b: int) -> int:
	var lhs := a & MASK32
	var rhs := b & MASK32
	var lo := lhs & 0xFFFF
	var hi := (lhs >> 16) & 0xFFFF
	return ((lo * rhs) + (((hi * rhs) & 0xFFFF) << 16)) & MASK32


## FNV-1a 32-bit. Seed produksi selalu ASCII (UUID, angka, titik dua), jadi
## code point dan UTF-16 code unit sama persis di sini.
static func hash_seed(value: String) -> int:
	var hash_value := FNV_OFFSET_BASIS
	for index in value.length():
		hash_value = (hash_value ^ value.unicode_at(index)) & MASK32
		hash_value = imul32(hash_value, FNV_PRIME)
	return hash_value & MASK32


## Satu langkah splitmix32. `_state` boleh dimask tiap langkah: JS membiarkan
## `value` tumbuh sebagai float64 lalu ToUint32 memodulokannya, dan penjumlahan
## modular memberi bit yang sama.
func next_uint32() -> int:
	_state = (_state + SPLITMIX_GAMMA) & MASK32
	var mixed := _state
	mixed = imul32(mixed ^ (mixed >> 15), mixed | 1)
	mixed = (mixed ^ ((mixed + imul32(mixed ^ (mixed >> 7), mixed | 61)) & MASK32)) & MASK32
	return (mixed ^ (mixed >> 14)) & MASK32


func next_float() -> float:
	return float(next_uint32()) / 4294967296.0
