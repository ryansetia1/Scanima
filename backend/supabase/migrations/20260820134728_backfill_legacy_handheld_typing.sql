-- Backfill typing legacy yang tidak pernah kena retyper.
--
-- `inferCanonicalLegacyTyping()` di `_shared/legacy_typing.mjs` menerjemahkan
-- elemen legacy enam-siklus menjadi roster 18, tetapi ia hanya jalan lewat
-- `legacy_art_migration.mjs`, dan jalur itu return dini untuk row yang sudah
-- `isAlreadyMigrated()`. Capture cache hit sampai di keadaan itu tanpa pernah
-- punya `generations.vision_result`, jadi elemennya tertinggal di nilai legacy
-- dengan `secondary_element` null walau `typing_version` sudah 2.
--
-- Terukur di production: tiga Anima ber-`species_key` `console_plastic_handheld`
-- yang sama, dua bertyping `plastic`/`spark` hasil retyper dan satu masih
-- `spark` tanpa elemen kedua. Update di bawah adalah keluaran fungsi kanonis
-- itu untuk input yang sama (`material:plastic_tech`), bukan penilaian baru;
-- predikatnya menyalin syarat drift-nya sehingga aman dijalankan ulang.
--
-- Anima legacy lain sengaja tidak disentuh: Hydron (`legacy:ambiguous`),
-- Veridian (`material:plant`), dan Sunhound (`subject:animal`) memang bertipe
-- tunggal menurut fungsi yang sama, dan mengarang elemen kedua untuk mereka
-- akan mengubah damage tanpa bukti dari foto.

update public.animas
set element = 'plastic',
    secondary_element = 'spark'
where typing_version = 2
  and subject_kind = 'object'
  and species_key = 'console_plastic_handheld'
  and element = 'spark'
  and secondary_element is null;

-- `atlas_forms` menyimpan proyeksi typing miliknya sendiri dan hanya di-upsert
-- saat Scan/Evolve, jadi tanpa baris ini Atlas tetap menampilkan typing lama
-- sampai Anima itu berevolusi.
update public.atlas_forms f
set element = a.element,
    secondary_element = a.secondary_element
from public.animas a
where f.anima_id = a.id
  and (f.element, f.secondary_element) is distinct from (a.element, a.secondary_element);
