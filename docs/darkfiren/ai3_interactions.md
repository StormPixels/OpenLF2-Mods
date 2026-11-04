# AI 3 — interaksi pertempuran (putaran 1-3: P1 lengkap kecuali batas suara; P2 butir 5 selesai)

BASE_ID: base-20261103-1-80a34ae. Rujukan: DOCX Darkfiren bagian 1, 4, 16.2.

## Sudah dikerjakan
- Kapasitas (§1): `item_slots` 400 -> 1000 (`constants.lua`). Batas keras 399 di `objects.free_slot`,
  `objects.lookup` dan loop kontrol AI di `match.lua` diganti `item_slots - 1`.
- Sampai 20 opoint per frame (`frame.opoints[1..20]`, semua dibuat; tanpa `opoints` dipakai `opoint` lama).
- itr/bdy sampai 100: kode Lua tidak membatasi jumlahnya (`ipairs`); dibuktikan dengan tes 100 itr x 100 bdy.
- itr (§4): `dvz`, `drain`, `gain` (17xxx = heal HP), `recover` 1/2/3, `dbdefend` 1-4, `spark` (-1 dan indeks).
  Semua di `fx_itr.lua`; tanpa tag = perilaku lama.

- itr kind 17 (whirlwind khusus t0) dan 18 (whirlwind khusus t1/t2/t4/t6) lewat `eligible`; kind 14 dengan `respond` 1-7
  hanya memblok objek bertipe respond-1.
- bdy (§5, `docs/txt/readme/frame/bdy.txt`): `zwidth`; kind 1xxx (dengan guncangan) dan 2xxx (tanpa) untuk semua tipe objek,
  `respond` = tim (0 = tim 1, -1 = tim penyerang, lainnya = tim itu); kind 50/51/52 (tanpa luka+jatuh / tanpa luka / tanpa jatuh);
  kind 53/54/55 (hanya tim sama / hanya pemilik sama / tim dan musuh); `1xxyyyzzzw` (peluang %, frame target, frame penyerang, efek 0-7);
  `respond` bdy senjata = frame pemungut (bawaan 115/116). Benturan mencatat bdy yang kena di `hit_list_body`.
- opoint (§6): `hp`, `team` (kind 1 dan 2), `z`, `mp`, `dvz`, `effect` (waktu kebal), kind 1 saja; `centerx/y/z` dan `framea` acak;
  `reserve` (t0/t5), `attacking`, `pic:1`; kind pegangan 3, 5, 6, 7 (selain kind 2 lama).
- wpoint `cover` 2: sumbu z sama dengan pemegang.
- Efek status itr (§4, DOCX 20.2; hanya itr kind 0 dan 9; `fx_status.lua`): `poison`, `manacle`, `delay`, `confus`, `weak`, `join`, `mimic`,
  `bound`, `facing`. Status disimpan di `value.fx.status`; `fx_status.active(value, nama)` dipakai kode kontrol/MP.
  Yang dikerjakan langsung di sini: damage racun, pertukaran tim `join`, dan damage separuh `weak`.
- Kontrak I7: semua field runtime baru AI 3 ada di `value.fx` (`hit_body`, `status`, `reserve`, `attacking`, `skin_owner`).

## Belum dikerjakan
P2 butir 6-8 (armor, stats/weapon_piece/weapon_strength_list, state t3) dan P3 (platform, cpoint/ppoint/bpoint diperluas).
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
| kind 17 / 18 | semua aturan kind 10 (whirlwind) berlaku; hanya jenis korban yang disaring | dokumen: "sama seperti kind 10 tapi hanya t0 / t1,t2,t4,t6" |
| kind 14 respond N | blok hanya objek bertipe N-1 | dokumen: "respond 1 = t0 saja ... 7 = t6 saja" |
| bdy `zwidth` | jendela kedalaman = yang lebih besar antara zwidth itr dan bdy | dokumen hanya bilang "dukung zwidth" |
| bdy 1xxx / 2xxx | pindah ke frame xxx, tim lewat `respond`, tanpa damage dan tanpa spark; berlaku di semua tipe objek. Di stage mode bdy >= 1000 tetap dilindungi aturan lama | dokumen; perlakuan di stage mode tebakan |
| bdy 50 / 51 / 52 | damage tetap dihitung, tetapi frame luka (51), jatuh (52), atau keduanya (50) dibatalkan: frame, `timer_b0`, `impulse_y` dikembalikan | dokumen: "kena damage tapi tidak masuk frame jatuh/DOP" |
| bdy 53 / 54 / 55 | 53 hanya tim sama, 54 hanya `owner` sama, 55 tanpa batas (tim dan musuh). Dokumen mencantumkan "kind 53" dua kali; yang kedua dianggap 55 | salah ketik di dokumen |
| bdy `1xxyyyzzzw` | digit: `1 XX YYY ZZZ W`; peluang XX% (0 = 100%), target ke frame YYY, penyerang ke ZZZ (0 = tidak pindah); W 0-3 tanpa guncangan, 4-7 dengan; bit 1 = ambil tim penyerang, bit 2 = damage `itr.injury`. Bila peluang gagal, benturan biasa terjadi | dokumen; "0 = tidak pindah" dan benturan biasa saat gagal tebakan |
| bdy `respond` senjata | frame pemungut = respond bila > 0, setelah `pick_up` (tidak untuk kind 7) | dokumen |
| opoint `dvz` | ditambahkan ke kecepatan z dari tombol atas/bawah | dokumen hanya bilang "dukung dvz" |
| opoint `z` | ditambahkan ke z pencipta (negatif naik, positif turun) | dokumen |
| opoint `centerx/y/z` | geser acak seragam -N..+N lewat `engine.random` | dokumen: "tambah keacakan posisi" |
| opoint `framea` | frame = action + acak 0..N | dokumen: "keacakan untuk action" |
| opoint `reserve`, `attacking`, `pic:1` | hanya disimpan: `value.reserve` (t0/t5), `value.attacking`, `value.skin_owner` = slot pencipta; pemakainya (nyawa cadangan, lempar dengan A, skin) ada di berkas lain | maknanya tidak cukup jelas untuk diterapkan di sini |
| wpoint `cover` 2 | z dan y senjata sama dengan pemegang (0 = depan, 1 = belakang seperti semula) | `leaf stuff.txt`: "same z axis as holder" |
| `poison` xyyyzzww | X jenis 0-5 (0 HP biasa, 1 HP tak di bawah 1, 2/3 persen HP sekarang, 4/5 persen HP maksimum; genap bisa membunuh, ganjil tidak), YYY durasi dalam frame, ZZ damage, WW peluang (0 = pasti); satu tick tiap 60 frame | contoh 13005075 dan "50 HP per 2 detik"; 60 frame = 2 detik pada 30 fps |
| `manacle/delay/confus/weak/join/mimic/bound/facing` xxyyy | XX peluang % (0 = pasti), YYY durasi dalam frame (300 = 10 detik). Contoh di dokumen (bound 90240 = 40%?) bertentangan dengan penjelasannya: dipakai XX = dua digit pertama | DOCX 20.2 mencatat sendiri ketidakcocokan itu |
| efek ditangkis | tidak ada efek status bila hit ditangkis | tebakan |
| pemberian ulang | durasi diperpanjang bila lebih lama, tidak dipersingkat | tebakan |
| `weak` | damage serangan sendiri karakter (t0) dibagi dua (pembulatan ke bawah); serangan objek opoint tetap normal. Regen HP/MP melambat: dikerjakan kode regen lewat `fx_status.active` (belum disambung) | dokumen |
| `join` | korban pindah ke tim penyerang selama durasi lalu kembali; dengan `effect: 364` tetap di tim penyerang. Hanya t0 | dokumen |
| `mimic` | hanya bila penyerang t0 dan korban t0; peniruan gerakan dikerjakan kode kontrol lewat `active` (belum disambung) | dokumen |
| `manacle`, `delay`, `confus`, `bound`, `facing` | hanya status dan timernya; pemakainya (kontrol, MP) adalah berkas lain | di luar lingkup berkas AI 3 |


## Jalur data -> efek (putaran 4, diperiksa dengan parser C++ asli)
Cara memeriksa: `object_data.cpp` dikompilasi dengan `g++ -std=c++23`, `.dat` uji dilewatkan `object_data::parse` lalu
`to_script_value`, dan tabelnya dicetak sebagai Lua (hasilnya jadi fixture di `RESULT/tests/fixtures/`).
Pemuat: nama berkas berakhiran `dat` di-decode (`data_file.cpp`: awalan 123 byte, kunci 37 karakter); nama lain dibaca polos.

| Teks `.dat` | Kunci tabel Lua dari C++ | Dibaca oleh | Dipanggil dari | Terlihat |
|---|---|---|---|---|
| `bdy: kind: 1110 respond: -1` | `frame.bodies[i].kind` (int32, maks 2147483647), `.respond` | `fx_body.frame_hit` lewat `fx.hit_body[posisi]` dari `record_targets` | `plain_hit` <- `combat.apply` <- `match.lua` (apply_character_hit / apply_object_hit) | korban pindah frame, ganti tim, tanpa damage |
| `bdy: kind: 1002200953` | sama (10 digit muat int32) | `fx_body.complex` | `plain_hit` | korban ke frame 220, penyerang ke frame 95, damage bila W&2 |
| `bdy: kind: 53/54/55` | `bodies[i].kind` | `fx_body.has_team_body/allows` | `record_targets` (eligible kedua dengan `force_friendly`) | tim sama / pemilik sama / semua |
| `bdy: zwidth: 30`, `respond: 102` | `bodies[i].zwidth`, `.respond` (extras) | `fx_body.depth_ok`; `combat.apply` (pick_up) | `record_targets`, `apply` | jendela kedalaman; frame pemungut |
| `itr: recover/dbdefend/spark/drain/gain/dvz/poison/weak/join/...` | `interactions[i].<nama>` (extras) | `fx_itr`, `fx_status` | `combat.eligible`, `apply`, `reset_lists` | lihat PANDUAN_UJI.md |
| `itr: kind: 17/18/14 respond: N` | `interactions[i].kind`, `.respond` (inti) | `fx_itr.whirl_matches/obstacle_matches` | `combat.eligible` | penyaringan jenis korban |
| `opoint:` (banyak blok) | `frame.opoints[1..n]` + `frame.opoint` (pertama) | `objects.spawn_from_frame`, `fx_point.extend` | `frame_rules` / `objects` | objek baru |
| `wpoint: cover: 2` | `frame.wpoint.cover` | `weapons.carry` | `match.lua` (`weapons.carry`) | z senjata = z pemegang |

Titik putus pertama yang ditemukan: gerbang mode stage di `combat.record_targets` memblokir SEMUA `bdy.kind >= 1000` dari penyerang
non-"protected" (aturan asli untuk si kriminal), sehingga bdy 1xxx / 1xxyyyzzzw pada objek biasa di mode stage tidak pernah mengenai
penyerang tim musuh. Diperbaiki: gerbang hanya berlaku bila korbannya `record_ids.criminal`.
Selain itu tidak ditemukan ketidakcocokan nama kunci; tes `realdata_test.lua` dan `testpack_test.lua` memakai tabel nyata dari C++.
