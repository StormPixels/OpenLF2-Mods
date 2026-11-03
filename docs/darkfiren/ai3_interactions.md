# AI 3 — interaksi pertempuran (putaran 1, sebagian)

BASE_ID: base-20261103-1-80a34ae. Rujukan: DOCX Darkfiren bagian 1, 4, 16.2.

## Sudah dikerjakan
- Kapasitas (§1): `item_slots` 400 -> 1000 (`constants.lua`). Batas keras 399 di `objects.free_slot`,
  `objects.lookup` dan loop kontrol AI di `match.lua` diganti `item_slots - 1`.
- Sampai 20 opoint per frame (`frame.opoints[1..20]`, semua dibuat; tanpa `opoints` dipakai `opoint` lama).
- itr/bdy sampai 100: kode Lua tidak membatasi jumlahnya (`ipairs`); dibuktikan dengan tes 100 itr x 100 bdy.
- itr (§4): `dvz`, `drain`, `gain` (17xxx = heal HP), `recover` 1/2/3, `dbdefend` 1-4, `spark` (-1 dan indeks).
  Semua di `fx_itr.lua`; tanpa tag = perilaku lama.

## Belum dikerjakan
kind 17/18/14+respond, bdy baru (§5), titik lain selain opoint ganda (§6), seluruh P2 dan P3.
Batas 20 suara bersamaan ada di `sounds.lua` (milik AI 5): lihat Permintaan perubahan di REPORT.

## Keputusan atas [BELUM PASTI] (semua nilai ada di `fx_itr.lua`, mudah diubah)
| Hal | Keputusan | Alasan |
|---|---|---|
| `drain` | kurangi MP korban sebesar nilainya, batas bawah 0; juga bila serangan ditangkis | dokumen hanya bilang "kurangi MP korban" |
| `gain` | + / - MP penyerang, dibatasi 0..500 | "tambah/kurangi MP penyerang" |
| `gain` 17xxx | heal HP penyerang xxx; xxx = 0 -> 100; batas `max_hp` | dokumen: "heal HP sebesar xxx (default 100)"; batas atas tebakan |
| `recover` | setelah damage, `hit_lag` = 0: 1 penyerang, 2 korban, 3 keduanya | sesuai dokumen; urutan penerapan tebakan |
| `dvz` | ditambahkan ke `impulse_z` korban, tanpa cermin arah hadap, tidak dipakai bila ditangkis | tanda dan skala tidak dijelaskan |
| `dbdefend` 2 | hanya mengenai tim sendiri | dokumen |
| `dbdefend` 3 | hanya mengenai objek dengan `owner` sama | dokumen |
| `dbdefend` 4 | musuh dan tim sendiri | dokumen |
| `dbdefend` 1 | bisa ditangkis dari dua sisi: syarat arah hadap berbeda diabaikan | dokumen |
| `spark` | -1 = tanpa spark; selain itu `spark_id` (nilai mentah) disimpan di catatan spark untuk AI 4 | kontrak: indeks disimpan, AI 4 menggambar |
| `601-699` vs `601-603` | belum disentuh (P2) | |
