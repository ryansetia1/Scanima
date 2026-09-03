# 03: Pilihan Seeker Avatar tersimpan dan terbaca

**What to build:** Seorang Seeker bisa punya avatar yang tersimpan di server dan
terbaca kembali lewat jalur profil yang sama dengan saldo dan statistiknya, dan
tidak bisa menyimpan sesuatu yang bukan anggota roster maupun menulis ke profil
pemain lain. Belum ada UI di tiket ini; yang dihasilkan adalah tempat
penyimpanan beserta pagarnya.

**Blocked by:** 02 (Seeker Roster, karena daftar slug-nya yang dijaga `CHECK`).

**Status:** ready-for-agent

- [ ] Satu kolom baru pada record profil pemain, bertipe teks, dengan `CHECK`
      terhadap daftar slug roster. `NULL` berarti belum memilih.
- [ ] Hak tulis diberikan lewat `grant update` per-kolom yang **aditif**. Jangan
      memakai `revoke update` pada tabelnya; hak `display_name` dan
      `last_seen_at` yang sudah ada harus tetap utuh sesudahnya, dan itu
      diperiksa.
- [ ] Tidak ada RPC baru dan tidak ada operasi Edge Function baru untuk
      menulisnya. Migrasinya memuat komentar singkat yang menyebut ini keputusan
      sadar — avatar bukan mata uang — supaya tidak "diperbaiki" menjadi RPC
      oleh pembaca berikutnya.
- [ ] Fungsi ringkasan profil Seeker mengembalikan kolom itu, sehingga client
      membacanya lewat jalur yang sudah ada.
- [ ] Uji pagar akses SQL membuktikan tiga hal: nilai di luar roster ditolak,
      update pada row sendiri lolos, update pada row pemain lain ditolak. Tetap
      berbentuk satu blok `DO` satu transaksi supaya aman dijalankan terhadap
      database remote.
