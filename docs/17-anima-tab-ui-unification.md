# 17 — Anima Tab UI Unification Plan

**Goal:** Seragamkan design language ketiga tab Anima (Collection · Synthesis · Atlas)
mengikuti gaya **Anima Collection** sebagai design authority, tanpa mengubah konten/logika
fungsional masing-masing tab.

---

## 1. Diagnosis Inkonsistensi

### 1.1 Perbedaan yang terlihat dari screenshot

| Dimensi | Collection ✅ (authority) | Synthesis ❌ | Atlas ❌ |
|---------|--------------------------|-------------|---------|
| **Background / surface** | Tidak ada LabPanel — transparan ke gradient background | `LabPanel` (`StyleBoxFlat_n7avp`) dark solid `#090E20` dengan content margin 8/18 | Tidak ada LabPanel, transparan |
| **Padding atas header** | `margin_top = 16` di Header MarginContainer | `margin_top = 16` TAPI ada `LabPanel.content_margin_top = 18` → total 34 px | `margin_top = 16` ✓ |
| **Animasi lingkaran berputar** | Tidak ada di permukaan tab | Tidak ada di permukaan tab | Shimmer + idle scale tween **di detail sheet** (bukan tab surface) |
| **Sub-filter bar** | Tidak ada | Tidak ada | Ada `AtlasFilters` (All/Scanned/Expedition/Duel) — ini konten khas Atlas |
| **Content wrapper** | VBoxContainer langsung di Control | VBoxContainer dalam PanelContainer LabSurface | VBoxContainer langsung di Control |

### 1.2 Root Causes

1. **Synthesis punya `LabPanel` wrapper** (`PanelContainer` dengan `theme_type_variation = "LabPanel"`)
   yang menambah solid dark background (`#090E20`) dan content margin 8/18 px. Collection dan Atlas
   tidak punya ini — ini yang menyebabkan Synthesis terasa berada di "container gelap" berbeda.

2. **Padding atas Synthesis bertumpuk**: `LabPanel.content_margin_top = 18` + `Header.margin_top = 16`
   = 34 px, sementara Collection dan Atlas hanya 16 px.

3. **Animasi Atlas**: `_detail_idle` (scale tween) dan shimmer ada di **detail bottom sheet**,
   bukan di permukaan tab — ini bukan inkonsistensi tab, ini fine untuk UX.

4. Dari sudut pandang game-ui-design: "Animation is communication, not decoration" —
   shimmer di Atlas detail sheet adalah komunikasi loading state yang valid. Tidak perlu dihapus.

---

## 2. Design Authority: Anima Collection

Struktur yang dijadikan patokan dari `collection_view.tscn`:

```
CollectionView (Control, anchors fill)
└── Column (VBoxContainer, separation=16, anchors fill)
    ├── Header (MarginContainer, margin_top=16, margin_bottom=2)
    │   └── Titles (VBoxContainer, separation=4)
    │       ├── Title (Label, PageTitleLabel)
    │       └── Subtitle (Label, MutedLabel)
    ├── [Tab Bar] (HBoxContainer, separation=8)
    │   └── Tab buttons (min_height=72, toggle_mode=true)
    └── [Content area — berbeda tiap tab]
```

**Prinsip yang disepakati:**
- Background: **tidak ada panel** — gradient background scene tembus
- Header margin atas: **16 px** (tidak lebih, tidak kurang)
- VBox separation antar section: **16 px**
- Tab bar: separation **8 px**, setiap tab `min_height = 72`
- Tidak ada idle animation di permukaan grid/list tab utama

---

## 3. Rencana Perubahan Spesifik

### 3.1 [UTAMA] Synthesis — Hapus LabSurface PanelContainer

**File:** `game/scenes/scan_flow.tscn`

**Node target:**
```
SynthesisLabView (Control)
└── LabSurface (PanelContainer, theme_type_variation="LabPanel")   ← HAPUS INI
    └── Column (VBoxContainer)   ← PROMOTE jadi anak langsung SynthesisLabView
```

**Setelah refactor:**
```
SynthesisLabView (Control)
└── Column (VBoxContainer, anchors fill seperti Collection)
    ├── Header (MarginContainer, margin_top=16)
    ├── CollectionTabs (HBoxContainer)
    └── Scroll (ScrollContainer) → Content → ...
```

**Langkah konkret:**
1. Hapus node `LabSurface` dari `scan_flow.tscn`
2. Set `Column` langsung sebagai child `SynthesisLabView` dengan layout anchors:
### 3.1 [UTAMA] Unifikasi Struktur Layout
Tiga tab Anima (Collection, Synthesis, Atlas) diseragamkan dengan menghapus PanelContainer `LabSurface` (`LabPanel`) dari `SynthesisLabView` di `scan_flow.tscn`, menyatukan struktur layout VBoxContainer `Column` di ketiga tab sebagai anak langsung Control view masing-masing dengan anchors fill (`layout_mode=1`, `anchors_preset=15`).

### 3.2 Panel Meredam Animasi Latar (Dimming Panel)
Untuk meredam animasi berputar (circle animation) di latar belakang agar tidak mengganggu fokus pemain, dibuat PanelContainer baru dengan style box flat gelap semi-transparan (`Color(0.025, 0.04, 0.095, 0.74)` dengan border 1px dan corner radius 18, setara dengan `ItemPanel` di Collection):
- **Synthesis (`scan_flow.tscn`)**: Membuat `SynthesisPanel` PanelContainer sebagai pembungkus `Scroll` (ScrollContainer).
- **Atlas (`atlas_view.tscn`)**: Membuat `AtlasPanel` PanelContainer sebagai pembungkus `AtlasScroll` (ScrollContainer).

### 3.3 Synthesis Transition & Bleeding Bug Fix
Bug transisi Synthesis di mana needs panel/CareDock bocor ke Synthesis Lab dan hilangnya animasi transisi kemunculan disembuhkan dengan memetakan `SYNTHESIS_DEST` pada `_active_view()` di `scan_flow.gd` agar mengembalikan `_synthesis_view` secara tepat. Ini mencegah fallback ke `_home_view` yang sebelumnya tidak sengaja memicu status reveal `_home_view` (menyebabkan `HomeView` dan CareDock menjadi visible kembali).

---

## 4. File yang Terdampak

| File | Jenis Perubahan | Urgency |
|------|----------------|---------|
| `game/scenes/scan_flow.tscn` | Hapus LabSurface, promote Column, buat SynthesisPanel pembungkus Scroll | HIGH |
| `game/scenes/ui/atlas_view.tscn` | Buat AtlasPanel pembungkus AtlasScroll | HIGH |
| `game/scripts/scan_flow.gd` | Map SYNTHESIS_DEST pada _active_view() | HIGH |
| `game/themes/mobile_theme.tres` | Audit saja | LOW |

---

## 5. Yang TIDAK Berubah

- Konten fungsional tiap tab (ItemList Collection, source picker Synthesis, filter+grid Atlas)
- Tab button styling (golden border active state) — sudah konsisten di ketiga tab

---

## 6. Acceptance Criteria

- [x] Switch antar tab tidak menyebabkan perubahan visual pada **posisi dan ukuran header** (title/subtitle/tabs)
- [x] Synthesis dan Atlas memiliki panel gelap transparan (`ItemPanel` style) membungkus area konten utama untuk meredam circle animation di latar belakang.
- [x] Padding atas title di ketiga tab: **16 px** (sama)
- [x] Needs panel (`CareDock`) milik Home tidak lagi bocor/muncul di tab Synthesis.
- [x] Animasi kemunculan (fade & scale in) berjalan mulus di ketiga tab (termasuk Synthesis).
- [x] Konten fungsional semua tab tetap bekerja.

---

## 7. Urutan Eksekusi

1. Hapus `LabSurface` PanelContainer, promote `Column` ke `SynthesisLabView`, set anchors.
2. Buat `SynthesisPanel` di `scan_flow.tscn` membungkus `Scroll`.
3. Buat `AtlasPanel` di `atlas_view.tscn` membungkus `AtlasScroll`.
4. Update `_active_view()` di `scan_flow.gd` untuk return `_synthesis_view` saat `SYNTHESIS_DEST`.
5. Uji transisi dan visualisasi konten.

---

## 8. Referensi Node Paths

```
# Synthesis (scan_flow.tscn)
UI/SafeMargin/Shell/ViewStack/SynthesisLabView                              ← Control
UI/SafeMargin/Shell/ViewStack/SynthesisLabView/Column                       ← VBoxContainer
UI/SafeMargin/Shell/ViewStack/SynthesisLabView/Column/SynthesisPanel         ← NEW PanelContainer
UI/SafeMargin/Shell/ViewStack/SynthesisLabView/Column/SynthesisPanel/Scroll  ← ScrollContainer

# Collection (scan_flow.tscn → collection_view.tscn instance)
UI/SafeMargin/Shell/ViewStack/CollectionView                                ← Control instance
CollectionView/Column                                                        ← VBoxContainer
CollectionView/Column/AnimaList                                              ← ItemList (uses ItemPanel)

# Atlas (scan_flow.tscn → atlas_view.tscn instance)
UI/SafeMargin/Shell/ViewStack/AtlasView                                     ← Control instance
AtlasView/Column                                                             ← VBoxContainer
AtlasView/Column/AtlasPanel                                                  ← NEW PanelContainer
AtlasView/Column/AtlasPanel/AtlasScroll                                      ← ScrollContainer
```
