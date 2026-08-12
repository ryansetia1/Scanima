-- Perbaikan kunci species_library, dan ini bug desain yang ikut dari
-- docs/01-architecture-dataflow.md, bukan salah tulis migrasi sebelumnya.
--
-- `species_key` sebagai primary key membuat seluruh gagasan dedup tidak bisa
-- jalan: `color_bucket` ada justru supaya mug merah dan mug biru mendapat art
-- berbeda, dan evolusi menambah baris stage 2 dan 3 untuk species_key yang sama.
-- Dengan PK lama, baris kedua mana pun ditolak, sementara indeks unik triple di
-- bawahnya tidak pernah bisa diuji. Kegagalannya juga di tempat terburuk: sheet
-- sudah dibayar dan diunggah, lalu insert-nya gagal.
--
-- Tabel masih kosong saat ini, jadi penggantiannya tidak perlu migrasi data.

alter table species_library drop constraint species_library_species_key_color_bucket_stage_key;
alter table species_library drop constraint species_library_pkey;
alter table species_library add primary key (species_key, color_bucket, stage);
