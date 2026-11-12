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


## Putaran 7 (keputusan dan perubahan)
| Hal | Keputusan | Alasan |
|---|---|---|
| Jangkauan itr sumbu x | `constants.nobody_near` 1000 -> 10000 (nilai awal `nearest`/`nearest_catcher`); target yang jaraknya >= nilai itu tidak pernah terpilih pada pukulan biasa dan catch | DOCX bagian 1 [P]; AI 1 membenarkan lokasinya |
| Time stop | objek yang `timestop.frozen` benar tidak menyerang dan (bawaan) tidak diserang; `fx_constants.frozen_can_be_hit = true` membuat korban beku tetap bisa dipukul. Diterapkan di `prepare_collision` | AI 2 meminta keputusan; DOCX: hit spark berhenti saat time stop. Pemakai time stop boleh memukul objek beku atau tidak: [BELUM PASTI] |
| Damage global mode | `dealt()` mengalikan damage dengan `bg_modes.damage_percent(state.bg_area) / 100` (pembulatan ke nol). Racun tidak dikali | permintaan AI 5; satuan persen asumsi AI 5 |
| Tinggi jatuh senjata | `weapons.drop_background`: y awal = `state.bg_area.centery` bila ada, selain itu `weapon_spawn.initial_y` | permintaan AI 5 |
| `fx.killed_by` | tabel `{[slot pemilik penyerang] = jumlah}`; bola/senjata dihitung untuk pemiliknya; dicatat di tiga jalur kematian combat dan pada tick racun yang mematikan | permintaan AI 4 |
| `fx.last_killer` | slot pembunuh terakhir, nil bila tidak ada | permintaan AI 4 |
| `fx.combo`, `fx.combo_age` | +1 tiap pukulan yang kena (tidak ditangkis) pada karakter musuh oleh karakter pemilik; `combo_age` 0 pada tick pukulan, naik tiap tick; kembali 0 bila `combo_age` melewati `fx_constants.combo_reset_ticks` (60). Aturan `<combo>` mode.dat (times, respond) belum dibaca | [BELUM PASTI]: aturan reset Darkfiren tidak diketahui; nilai 60 tebakan |
| Racun mematikan | tick racun yang membuat HP <= 0 mencatat kill untuk penyebar racun (`killed_by`, `last_killer`, `kills`) | konsisten dengan pukulan pembunuh. Kematian itu sendiri tetap ditangani logika lama |
| Penghitung per ronde | `fx_stats.reset(value)` tersedia; nilai awal diisi saat objek dibuat seperti `kills` | tidak ada hook baru di match.lua |


## Putaran 8 (keputusan pengguna, menggantikan baris putaran 7 yang bertentangan)
| Hal | Aturan sekarang | Sumber |
|---|---|---|
| Klon (penanda) | Diisi SEKALI saat objek dibuat, di `fx_point.extend` (dipanggil dari `objects.spawn_from_frame`). Aturan persis: objek berjenis karakter (t0) yang dibuat oleh opoint dan `record.id`-nya sama dengan `record.id` pembuatnya, ATAU sama dengan `record.id` pemilik pembuatnya (`state.items[parent.owner]`). Hasil: `value.fx.clone = true` dan `value.fx.clone_owner = slot pembuat`. Bola, senjata, dan karakter ber-id lain tidak pernah klon. AI 2 menyalinnya ke `value.st.clone`; AI 4 membacanya untuk radar | keputusan pengguna 3 |
| Time stop | `fx_constants.frozen_can_be_hit = true` (bawaan): objek beku (`timestop.frozen`) tidak pernah menyerang, tetapi tetap bisa dipukul; pemakai time stop tidak beku sehingga tetap menyerang. `false` mengembalikan aturan "tidak ada interaksi dua arah" | keputusan pengguna 4 |
| Tim musuh stage = 6 | Tidak ada berkas AI 3 yang memakai angka 5 harfiah untuk tim; `combat.lua` baris 209 dan 212 membaca `constants.teams.enemies`. `constants.lua` tidak disentuh AI 3 untuk ini | keputusan pengguna 1 |
| `mimic_by` | `value.fx.status.mimic_by` = slot pemilik penyerang pemasang mimic; nil saat timer mimic habis. `fx_status.mimic_target` dan `fx_status.remap` tidak ada | keputusan pengguna 7 |
| Arti efek (koreksi AI 2) | delay = tak bisa bergerak cepat; weak = regen MP melambat, regen HP berhenti, damage serangan dekat separuh (hanya t0); facing = pemakaian MP korban dua kali lipat; bound = korban tak bisa menekan J; manacle = jurus kombinasi mati (hit_a/hit_j/hit_d tetap). Di sisi AI 3 hanya damage separuh weak yang dikerjakan; sisanya dibaca AI 2 lewat `fx_status.active` | DOCX, dijelaskan AI 2 |
| Combo | `fx.combo` naik per pukulan yang kena (tidak ditangkis) pada karakter musuh. Dari `<combo>` mode.dat lewat `sd_global.combo()`: `respond` = tick tanpa pukulan sebelum kembali 0 (bawaan `fx_constants.combo_reset_ticks = 50`), `caughtact = 1` = pukulan saat menangkap ikut dihitung (`grab.place_victims`), `effect` = siapa yang dihitung (8 manusia lewat `value.human`, 20 ber-slot menu lewat `value.slot`, lainnya semua). Pukulan klon dihitung untuk pencipta karena `clone.owner` = pencipta | readme <combo>, AI 4/AI 5 |
| Kill saat menangkap | `grab.place_victims` kini juga mencatat `fx.killed_by` / `fx.last_killer` (sebelumnya terlewat); tick racun mematikan juga memanggil `battle.count_kill` | perbaikan putaran 8 |
| system.dat | `<henry_arrow>` (objek dihapus setelah memukul t0) dan `<john_biscuit>` (HP penyerang jadi 0 setelah memukul t0) dibaca lewat `system_data.ids`; daftar kosong = id LF2 asli. Pemakaian id lain di `combat.lua` (perlindungan stage, kekecualian armor Knight/Louis/Julian) tetap memakai id asli | AI 5 |
| ID suara | `sounds.item` / `sounds.effect` kini menerima `record.id` objek yang posisinya dipakai sebagai argumen terakhir (korban untuk efek, penyerang atau objek untuk suara pecah) | AI 5 |
| State 70 dan 75 | Seperti state 7 (bertahan) tetapi menangkis dari kedua sisi (syarat arah hadap berbeda diabaikan); selebihnya sama dengan state 7 (damage sepersepuluh, frame bertahan) | DOCX 15.2 baris "70, 75" |
| State 601 / 602 / 603 (korban) | Korban tidak masuk frame luka (601), tidak jatuh (602), atau keduanya (603), damage tetap diterima; sama dengan bdy 51 / 52 / 50. Bila bdy kind 50-52 ikut kena, bdy yang menang | DOCX 15.2; pembanding HP 601-699 dan 6xxx TIDAK dikerjakan (keputusan pengguna 5) |
| Belum dikerjakan | state 3007, 180/190, 3005 pada karakter, hit_Fj/Uj/Dj/ja/Ua/Da untuk objek 3000/3006: spesifikasi DOCX hanya satu baris yang ambigu (lihat REPORT) | |


## Putaran 9 (armor dan kunci baru weapon_strike)
Armor (`armor.lua`, DOCX 16.5 / armor.txt). Bentuk data dari parser C++: angka `type ratio decrease mp fall bdefend injury spark delay hp recover facing action`, teks `sound1 sound2`, larik `ids states effects`, dan `frames` = daftar `{awal, akhir}`. Dibaca dari `record.data.armor`; tanpa blok itu armor lama (Knight/Louis/Julian) di `combat.armored` tetap dipakai.
| Hal | Aturan | Catatan |
|---|---|---|
| type 0 | tidak menahan; hanya suara sound2 saat bertahan | armor.txt |
| type 1 | menahan bila semua syarat di bawah lolos | |
| type 2 | hanya memeriksa `ids` dan `effects` (frame, state, fall, bdefend, injury, ratio, facing, mp diabaikan) | armor.txt: "hanya efek"; [BELUM PASTI] |
| type 3 | seperti 1 tetapi `fall` itr diabaikan | armor.txt |
| type 4 | tidak menahan; hanya mengalikan damage dengan `decrease`% dan memakai `delay` / sound2 | armor.txt |
| `ratio` | armor mati bila `timer_b8 > ratio` (Knight 15, Louis 1 sama dengan batas lama 16 dan 2) | dicocokkan dengan kode lama |
| `ids`, `effects` | id penyerang / efek itr yang menembus armor | |
| `fall`, `bdefend`, `injury` | itr dengan nilai >= angka itu menembus armor; -1 = tidak dipakai | armor.txt |
| `frames` dan `states` | masing-masing menyebut tempat armor aktif; bila KEDUANYA ada, aktif di salah satunya (ATAU); bila satu, hanya itu; bila tidak ada, di mana pun. `<armor_s>` dari system_data (cadangan: 8 11 12 13 14 16 18) selalu mematikan armor | ATAU dipilih karena armor Louis asli = frame < 20 ATAU dashing/jumping/defending; AND membuatnya hampir tak pernah aktif [BELUM PASTI] |
| `facing` (type 1) | -1 hanya serangan dari depan, -2 hanya dari belakang, 0 keduanya | armor.txt |
| `mp` | biaya MP tiap kali armor menahan; MP kurang = armor tidak bekerja | |
| `hp`, `recover`, `action` | HP armor berkurang `injury` per tahanan; habis = armor rusak; `recover` frame sampai pulih (-1 tak pernah); `action` = frame pemilik saat armor habis bila fall itr < 80. Status di `value.fx.armor` | |
| `decrease` | persen damage yang tetap diterima saat menahan (0 tak ada, 100 penuh); -1 = sepersepuluh seperti LF2 asli | |
| `delay` | >= 0 mengganti lama guncangan (kedua petarung), -1 = asli | |
| `spark` | mengganti indeks spark pukulan yang ditahan | |
| `sound1`, `sound2` | sound1 saat armor menahan, sound2 saat ditangkis tanpa armor; lewat `sounds.item` dengan id korban | |
| `<defend>` | id yang boleh ditangkis dari dua sisi, lewat `system_data.ids("defend")`, ditambah id lama | |
Kesetaraan dengan kode lama dibuktikan di `armor_real_test.lua` memakai blok `<armor>` asli Knight, Julian, dan Louis dari parser C++ (efek 24-29 dan 31-39 bisa berbeda dari kode lama karena daftar `effects` di data lebih sempit).

`weapon_strike` (serangan dengan senjata yang dipegang) kini juga menyalin kunci baru dari `<weapon_strength_list>`: `dvz drain gain spark recover dbdefend z sound cover selfinjury`. Efek tambahan (drain, gain, recover) dikreditkan ke PEMEGANG: `gain` menambah MP pemegang; `recover` 1/3 juga menghapus guncangan senjata. `selfinjury` = damage ke pemegang tiap pukulan senjata yang kena (lewat `dealt`, tanpa penanganan kematian pemegang). `decrease` (damage ke senjata) BELUM diterapkan: tidak ada mekanisme daya tahan senjata di skrip. `caughtact` di strengths juga belum dipakai (hanya relevan untuk itr penangkap).

## R10: ppoint, cpoint diperluas, itr respond (kind 1/3)
- `ppoint` (`fx_point.lua`: `follow`, `follow_all`; dipanggil di akhir `weapons.carry`, jadi tanpa hook ke match.lua): objek yang frame-nya punya `ppoint` (kind 1) berada di (x, y, z) relatif terhadap pemiliknya (`value.owner`) tiap tick. Dua tebakan bernama di `fx_constants.lua`: `ppoint_mirror_x` (x dicerminkan bila pemilik menghadap kiri) dan `ppoint_copy_facing` (arah hadap ikut pemilik) [BELUM PASTI]. Objek tanpa pemilik (99 / slot kosong) tidak disentuh; karakter tidak pernah mengikuti.
- `cpoint` (`grab.lua` + `fx_point.lua`): `daction`, `faction`, `baction`, `uzaction`, `dzaction` = lompat ke frame saat tombol (defend / maju / mundur / atas / bawah) baru ditekan selama genggaman, hanya bila aaction/taction/jaction belum bertindak pada tick itu [BELUM PASTI: urutan bila beberapa tombol sekaligus; maju/mundur relatif terhadap arah hadap pemegang]. `z`: z korban = z pemegang + z, geseran `cover` tidak berlaku (readme). `drain`, `gain`, `recover`: memakai `fx_itr.after_hit` (gain 17xxx = heal tetap berlaku), hanya pada tick yang melukai (injury > 0).
- itr kind 1/3 `respond` > 0 = lama menggenggam (`catch_timer`), bawaan 300 (`combat.lua`, fungsi `catch`).
- TIDAK dikerjakan di R10: `bpoint` (w, h, rect, respond; belum ada mekanisme gambar darah di skrip), platform (kind 30-89), pantulan tanah, efek Leaf.F, dan catchingact/caughtact/pickingact/pickedact per sisi pada itr (lihat REPORT: parser belum memberi data yang bisa dipakai).

## R11: platform.plane_at (itr kind 30-89, tahap 1 = kind X0)
- `platform.plane_at(match, value)` (`platform.lua`) mengembalikan tinggi bidang (<= 0, negatif = ke atas) atau `nil`. `physics.lua` (AI2) memakainya sebagai pengganti tanah (y = 0). Belum ada pemanggil di BASE: R11 sendiri tidak mengubah perilaku permainan.
- Bidang = `y_int` objek platform + `dvy` itr (readme). Item dihitung bila titik tengahnya (x_int, z_int) ada di dalam itr: rentang x seperti kotak itr biasa (dicerminkan bila platform menghadap kiri), jendela z = `z_int` platform + `itr.z` +- `zwidth` (0 = bawaan 15) [BELUM PASTI: `itr.z` menggeser jendela, `zwidth` setengah lebarnya; y dan tinggi itr tidak dipakai].
- Menembus dari bawah: item yang kaki sebelumnya (y - vy) ada di bawah bidang tidak mendarat (jalan di bawah / melompat menembus). Berdiri tepat di bidang tetap ditopang (`fx_constants.platform.land_tolerance`).
- Rentang kind: 30-59 = tipe 0 (karakter), 60-89 = tipe 1, 2, 4, 5, 6 (bukan bola/3); dalam satu dekade 0-9 semua tim, 40-49 / 70-79 sama tim dengan platform, 50-59 / 80-89 tim lain.
- Tahap 1 hanya X0 (`fx_constants.platform.supported_subtypes`); X1 (blok mutlak), X2/X3 (bergerak), X4 (resistansi), X5 (pantul) diabaikan sampai ada spesifikasi. Itr kind > 18 sudah diabaikan combat (`combat.lua` baris 149), jadi platform tidak melukai siapa pun.
- Gelombang t3 (state 3000/3006/3007, `hit_g`) belum dikerjakan: spesifikasi state itu belum jelas.

## R12: platform.plane_at diperluas, combat memakai floor_y
- `platform.plane_at(match, value, current)`: aman bila `match` atau `match.items` nil (mengembalikan nil). Parameter ketiga opsional = bidang yang dipakai item tick lalu (`value.floor_y`): bidang yang paling banyak `fx_constants.platform.rise_limit` (24, [BELUM PASTI]) di atasnya tetap menopang item, jadi platform yang naik membawa item tanpa trik AI2 (value.y diturunkan 24).
- `combat.lua`: korban di bidang platform dianggap di tanah: tiga tempat `victim.y_int < 0` dan satu `victim.y_int == 0` kini memakai `(victim.floor_y or 0)` (field milik AI2; nil = tanah). Belum diuji dengan unit test (cabang itu butuh adegan pukulan penuh); tes lama membuktikan perilaku tanpa `floor_y` tidak berubah.
- Belum: `objects.lua` 499/537 (`me.y > 0.0`, bola pengejar di bawah tanah) dan gelombang t3 / `hit_g` memakai `floor_y`.

## R13: objects.lua memakai floor_y
- `objects.update` (bola pengejar / proyektil, hit_Fa 1, 2, 4, 7, 10, 12, 14): tanah y = 0 diganti `ground(me) = me.floor_y or 0`. Berubah: pemeriksaan `me.y > 0.0` (2 tempat), batas `y <= 1.0` / `1.4` / `3.0` (kini bidang + nilai itu), dan tinggi 25 (`-25`, salinan pengembali, kini bidang - 25). Tanpa `floor_y` hasilnya sama persis. Unit test hanya hit_Fa 1 dan 10 (`r13_objects_floor_test.lua`); hit_Fa 7 (`-25`) dan cabang `hp <= 0` belum diuji (jalur 7 memanggil `create_effect` di awal, sulit di-stub).
- `hit_g` (frame pendaratan) ada di `st_frame.landing` milik AI2: pemeriksaan `value.y < 0 or value.y_int ~= 0` masih memakai tanah 0, jadi di platform hit_g tidak berlaku. Permintaan ke AI2: ganti 0 dengan `(value.floor_y or 0)` di dua tempat itu.

## R14: itr kind 1, tangkapan per sisi (catchingact / caughtact / pickingact / pickedact)
- `fx_itr.catch_frames(itr, facing)` dipakai `combat.catch`: sisi KIRI (penyerang menghadap kiri) memakai `catchingact` / `caughtact`, sisi KANAN `pickingact` / `pickedact`, masing-masing jatuh ke pasangan kiri bila tidak ditulis; hanya angka pertama dipakai (angka kedua gaya LF2 2.0a [BELUM PASTI]). Frame negatif memutar karakter itu (penyerang / korban) lalu memakai nilai mutlaknya.
- Data lama (tanpa kunci baru, atau pasangan tidak lengkap) tetap memakai `catching_actions[1]` / `caught_actions[1]`.
- Catatan: pada data gaya readme parser mengisi slot lama `catching_actions` dari `pickingact`/`pickedact` dan `caught_actions[1]` = `caughtact` (bisa negatif). Kode BASE lama membaca slot itu langsung dan crash (`cpoint.x` nil) pada frame negatif; terbukti dengan tes `r14_catch_test.lua` pada BASE tanpa patch.
- Tebakan [BELUM PASTI]: "sisi" = arah hadap penyerang setelah ia menghadap korban; tata letak korban setelah pemutaran memakai arah hadap akhir penyerang.
- Bukti data nyata (karakter Kyu / Naruto, bukan Darkfiren, gaya LF2 2.0a): 6 itr, semuanya `kind: 3` dengan dua angka per kunci yang SELALU sama (`catchingact: 266 266 caughtact: 130 130`, `120 120 / 130 130`); frame 120/265/266 = `catching` (state 9, cpoint kind 1), frame 130 = `picked_caught` (cpoint kind 2). Jadi data nyata tidak membedakan arti angka kedua; keduanya sama, dan hasil `catch_frames` sama dengan kode lama (tes `r14_catch_test.lua` memakai frame-frame itu lewat `fixtures/kyu_catch.lua`). Catatan: `kind 3` dan `kind 1` sama-sama menuju `catch`.

## R15: pantulan di itr (dx / dy / dz + pickingact / pickedact)
- Spesifikasi: `docs/txt/readme/frame/itr.txt` ("bounce in itr"): "on hitting the ground t0 victim will gain x y and z velocity based on dx: dy: dz:"; pickingact / pickedact = frame tujuan korban.
- `fx_point.bounce_mark` (dipanggil dari `fx_itr.after_hit`, tidak bila ditangkis, hanya korban karakter) menyimpan `value.fx.bounce = {dx, dy, dz, frame, facing, air, age}`. `fx_point.bounce_step` / `bounce_all` (dipanggil di akhir `weapons.carry`, setelah gerak): saat korban mendarat setelah sempat di udara (y_int lebih kecil dari `floor_y or 0`), kecepatan menjadi (dx x arah, dy, dz) dan frame dipaksa ke tujuan; tanda dipakai sekali. Tanda dilupakan setelah `fx_constants.bounce_ticks` (120) tick tanpa mendarat.
- [BELUM PASTI] (semuanya di satu fungsi): frame `pickingact` untuk penyerang menghadap kanan dan `pickedact` untuk kiri (sama dengan sisi tangkapan); dx dikali +1 / -1 menurut arah hadap penyerang; frame dipaksa pada tick pendaratan; hanya satu pantulan; "t0" = karakter. DOCX: "dua frame tujuan (hadap kanan dan kiri)".
- Pemicu pendaratan memakai `floor_y` (platform). Pendaratan sebenarnya diputuskan AI2 (`st_frame.landing`); AI3 hanya mengamati posisi korban, jadi frame pendaratan bawaan sempat berjalan satu tick sebelum ditimpa.

## R16: Leaf.F efek 8-16 (itr kind 0 / 9; spesifikasi: `addons by Leaf.F.txt`, "New effects working")
- Tipe = nilai `record_kinds`. Efek 8 = t0, 9 = t3, 10 = t0 + t3, 11 = t1/t2/t4/t6, 12 = semua; 13-16 = daftar yang sama dengan 8-11 tetapi HANYA mengenai tipe itu.
- `fx_itr.leaf_blocks` (dipakai `combat.eligible`): efek 13-16 tidak mengenai tipe di luar daftar (tidak ada pukulan sama sekali). Efek 8-12 pada tipe lain = pukulan biasa tanpa ekstra.
- `fx_itr.leaf_extras` (dipakai `combat.plain_hit`): `respond` (tidak nol) = hanya korban yang state frame-nya sama; `catchingact` > 0 memindahkan penyerang ke frame itu, `caughtact` > 0 memindahkan korban; `caughtact` -1 = korban tidak masuk frame terluka (220/224/226/228), -2 = tidak masuk frame jatuh dan dvx/dvy penyerang dibatalkan (dvz tetap), -3 = keduanya.
- [BELUM PASTI]: ketidakcocokan state `respond` pada efek 8-12 hanya menghilangkan ekstra, pada 13-16 menggagalkan pukulan; frame dipaksa di akhir `plain_hit` (menimpa frame terluka/jatuh); -2 membatalkan dorongan dvx dan seluruh blok jatuh (termasuk dvy dan jatuhnya benda yang dipegang).
- BELUM: kunci `sound` 1-18 (butuh tabel suara bawaan, AI5), perluasan kind 8 (`dvx`/`dvy`/`bdefend`/`respond`/`caughtact` MP), daftar kekuatan senjata (`catchingact` memang tidak berlaku di sana). Pukulan dengan efek 8-16 saat ini tanpa suara bawaan karena `plain_hit` hanya memutar suara untuk efek 0/1.

## R17: platform sesuai PDK, grab.release_victim, Leaf.F itk8 (kind 8)
- platform.lua (sumber: pembacaan PDK.exe oleh pembantu pengguna, lewat AI2 putaran 18, [KODE]): kind 30-59 mengenai tipe 0 dan 3, kind 60-89 tipe 1, 2, 4, 6; tipe 5 (prisoner) tidak pernah. Dekade 3x/6x semua tim, 4x/7x tim platform, 5x/8x tim lain. Gerbang: `x_int` di (kiri, kanan) EKSKLUSIF, |z_int - (z platform + itr.z)| < zwidth (0 = 15) eksklusif. Bidang = round(y_int + dvy). Dicatat bila kaki di atas bidang sekarang ATAU tick lalu (`y <= bidang` atau `y - vy <= bidang`); bidang di bawah tanah (> 0) diabaikan. Diekspor: `platform.affects(itr_kind, platform_item, item)`, `platform.inside(platform_item, frame, itr, item)`, `platform.itr_box(platform_item, frame, itr)` -> kiri, kanan, z_tengah, z_jendela. Batas naik 24 (`rise_limit`) tetap sebagai pengaman, bukan dari PDK. [BELUM PASTI]: rentang x dicerminkan bila platform menghadap kiri (catatan PDK tidak menyebutnya).
- `grab.release_victim(state, victim_index)` -> true bila korban sedang digenggam: pemegang kembali ke frame 0 dan `catching = 0`; `update_holds` berikutnya menjatuhkan korban (frame jump + 2, vy -3). false bila tidak digenggam. Dipakai AI2 untuk platform X5 pada korban tertangkap.
- Leaf.F itk8 (kind 8): `dvx` = frame penyembuh (999 = tidak ganti); `dvy` = gerak penyembuh (-1 tidak, 0 x/z (asli), 1 y/z, 2 x/y/z; di luar -1..2 dianggap 0); `bdefend` = tipe yang dipulihkan (0-6 tipe itu, 7 senjata 1/2/4/6, 8 semua; di luar 0-8 dianggap 0 = karakter saja); `respond` = tim (0 semua, 1 teman, 2 musuh, 3 diri sendiri termasuk klon dan objek buatan diri (`owner` atau `fx.clone_owner`), 4 diri saja; di luar 1-4 dianggap 0); `caughtact` > 0 = regenerasi MP selama itu tick (+8 tiap 8 tick, `value.fx.mp_regen`, batas `fx_constants.heal_mp_limit` = 1000 [BELUM PASTI], proses di `weapons.carry` lewat `fx_point.heal_mp_all`); `injury: 0` tidak menimpa `regen_timer`; kind 8 pada benda berat (t2) tidak lagi membagi dua dvx/dvy (sebelumnya `dvx` 150 menjadi 75). Regenerasi HP / MP hanya untuk karakter; tipe lain hanya memindahkan penyembuh (frame / gerak).
- Perubahan perilaku untuk data lama kind 8: `injury: 0` kini tidak memulai regenerasi; `bdefend` 1-8 atau `respond` 1-4 yang tidak sengaja tertulis di data lama kini berlaku sebagai filter. Data LF2 asli diperkirakan tidak memakainya [BELUM PASTI].

## R18: Leaf.F efek 8-16 dan `caughtact` di `<weapon_strength_list>`
- `weapon_strike` menyalin `strengths[i].caughtact` (satu angka dari parser) ke itr sebagai `{angka}`; `effect` dan `respond` sudah disalin sebelumnya. `catchingact` tidak berlaku di daftar kekuatan (sesuai readme) dan tidak disalin.
- Itr senjata (kind 5) lolos `eligible` sebagai itr biasa; karena itu efek 13-16 dari daftar kekuatan disaring lagi di `combat.apply` sesudah `weapon_strike` (`fx_itr.leaf_blocks`); pukulan yang tersaring tidak terjadi (korban tidak terluka), tetapi pasangan sempat terbentuk di `detect`.
- Paket uji ponsel diperbarui: langkah D4 (menembus platform dari bawah) dan F1 sampai F3 (kind 8: HP, hanya teman, MP).

## R19: tipe 5 pada platform, bola state 3007, dan arti status itr
- `platform.lua`: kind 60-89 kini juga mengenai tipe 5 (prisoner), atas keputusan pengembang Darkfiren (PDK tidak punya; readme benar). Kind 30-59 tetap tipe 0 dan 3.
- `platform.land_ball(value)` (dipanggil AI2 dari `physics_item` di match.lua SESUDAH `physics.step` item yang sama pada tick yang sama; `objects.update` tidak dipakai karena hanya berjalan untuk objek ber-hit_Fa dan sebelum fisika; `floor_y` hanya ada pada tick bola melewati bidang): untuk bola tipe 3 yang frame-nya ber-state 3007 dan `y >= floor_y`, bola ditaruh di bidang (y := bidang), kecepatan 0, dan pindah ke frame `hit_g` (`frame.hit_ext.g`) bila ada dan belum di frame itu. Fungsi memeriksa kind dan state sendiri, aman dipanggil untuk item apa pun (kembali false). Sumber: aturan PDK dari pembaca (relay AI2, [KODE]). [BELUM PASTI]: tanpa `hit_g` bola tetap dihentikan di bidang; bola hanya dihentikan oleh bidang yang dicatat `physics.lua` (`floor_y`); keterlambatan satu tick tidak dikejar. State 3007 sendiri (bola dengan HP sendiri, lewat `hp:` di opoint) tidak dikerjakan; `fx_constants.platform.ball_state` = 3007.
- Arti status itr (readme `special functions.txt`; hanya itr kind 0 dan 9) dicocokkan dengan `fx_status.lua`; tidak ada perubahan kode. poison xyyyzzww (efek 0-5, durasi, damage, peluang; 0 = 100%) dan manacle / delay / confus / weak / join / mimic / bound / facing xxyyy (peluang %, 0 = 100%, lalu durasi) sama dengan `parse_poison` / `parse_timed`; `weak` hanya untuk karakter, melemahkan cedera pukulan dekat korban (benda opoint tetap normal) di `combat.lua`; join efek 364 = korban tetap di tim penyerang. Yang dibaca pihak lain lewat `fx_status.active(value, nama)`: weak (MP lambat, HP berhenti, MP berhenti bila hp = dhp), delay (gerak lambat), confus (tombol diacak), manacle (jurus kombinasi terblokir, bukan hit_a/j/d), bound (tombol J), facing (MP dua kali lipat untuk `mp:`, `cmp:` separuh).

## R21: `platform.land_ball(value, frame_before)`
- Temuan AI2 (R24): `physics.step` memindahkan item yang mendarat ke frame `hit_g` pada tick yang sama, jadi `land_ball` yang dipanggil sesudah `physics.step` melihat frame `hit_g` (bukan state 3007) dan menolak. Parameter opsional `frame_before` = frame bola SEBELUM `physics.step`: state 3007 dan `hit_g` dibaca dari frame itu, y := bidang dan kecepatan 0 diterapkan, frame tidak diubah bila sudah sama dengan tujuan. Tanpa parameter perilaku tetap seperti R20. Pemanggil (AI2, `match.physics_item`) cukup `platform.land_ball(value, frame_sebelum)` sesudah `physics.step`, tanpa menyetel y dan kecepatan sendiri; `objects.update` (hook R19 di BASE `96c6fa7`) tetap idempoten.

## R22: Leaf.F `sound` (1-18)
- Spesifikasi (`addons by Leaf.F.txt`, butir 5): `sound` memilih suara bawaan; hanya untuk objek t0; 0 = tanpa suara; 1-18 = daftar (1 benturan biasa, 2 benturan pada blok, 3 pukulan keras, 4 batu, 5 tongkat bisbol, 6 langkah/mendarat, 7 tubuh jatuh, 8 lompat dash, 9 benda t3 mengenai sesuatu, 10 batu runtuh, 11 panah Henry di tanah, 12 tusukan teredam, 13 tusukan nyaring, 14 memukul bola dengan tongkat, 15 membeku, 16 es pecah, 17 terbakar, 18 armor Louis/Knight).
- Pemetaan: suara n = kanal tetap `n - 1` di `sounds.lua` (18 buffer tetap, indeks 0-17). Bukti dari kode BASE sendiri, bukan tebakan: `combat.lua` sudah memutar kanal 0 untuk benturan biasa, 2 untuk pukulan keras / jatuh, 11 dan 12 untuk tusukan teredam / nyaring, 13 untuk bisbol, 14 untuk membeku, 15 untuk es pecah (`objects.lua`), 16 untuk api, 17 untuk armor; `control.lua` kanal 7 untuk lompat dash dan `physics.lua` kanal 6 untuk tubuh jatuh. Semuanya cocok dengan daftar Leaf.F bila dikurangi 1.
- `fx_itr.leaf_extras` mengembalikan `sound` (1 sampai 1000, selain itu 0); `combat.plain_hit` memutar `sounds.effect(state, victim.x_int, sound - 1, victim.record.id)` untuk pukulan efek 8-16 yang cocok pada karakter. Nomor di atas 18 adalah entri tambahan yang ditulis mod di `data\sound.dat` (update log Darkfiren baris "added sound.dat for harcorded sound list, you can add more sounds to it and use them with effect 8~16 with sound: tag"; `sounds.lua` menyimpan paling banyak 1000); `sounds.effect` mengabaikan kanal yang tidak ada di daftar tanpa galat (konfirmasi AI5). Efek 8-16 tanpa `sound` tetap sunyi (tidak ada suara bawaan untuk efek itu); efek 0-3 tidak memakai `sound`. Daftar kekuatan senjata menyalin `sound` (kunci sudah ada), sehingga pukulan senjata dengan efek 8-16 juga bersuara; belum diuji.
- Konfirmasi AI5: `sound.dat` pengganti mengisi indeks 0 dari baris `file:` pertama; berkas stok urut 001, 002, 006, 010, 011, 004, 016, 017, 020, 021, 025, 032, 033, 039, 065, 066, 068, 085 (indeks 0-17). Berbasis 1 pada nomor `sound`: readme eksplisit "0 = no sound; 1 = normal sound of an impact"; urutan 1-18 sama dengan indeks 0-17 dibuktikan lewat kanal yang sudah dipakai kode BASE (lihat di atas). Yang masih [BELUM PASTI]: bila mod mengubah urutan 18 entri awal, arti nomor 1-18 ikut berubah (sama seperti kanal bawaan game).

## R23: `fx.last_killer_type` (permintaan AI4, papan siapa-membunuh-siapa)
- `fx_stats.record_kill(victim, killer, killer_type)`: parameter ketiga = `record.kind` objek yang benar-benar memukul (0 karakter, 1 senjata ringan, 2 senjata berat, 3 bola, 4 baseball, 5 tawanan, 6 minuman); disimpan di `value.fx.last_killer_type` bersama `last_killer` (slot pemilik, yang dikreditkan). Pembunuhan oleh karakter lewat tangkapan (`grab.lua`) memberi 0; kill oleh itr (`combat.lua`, tiga tempat) memberi jenis penyerang (senjata yang dipegang = jenis senjata, bukan pemegang); racun (`fx_status.lua`) tidak tahu jenisnya: `nil` (menimpa jenis lama, tidak pernah tersisa usang). `fx_stats.reset` mengosongkannya.
- Korban tetap ada di `state.items` pada tick pembunuhan (pembacaan kode, belum diuji penuh): `combat.lua` tidak menghapus korban; penghapusan hanya lewat frame ber-state `removed` / `next: 1000` (`match.lua` 657/785, `frame_rules.lua` 180), dan frame pukulan / jatuh yang dipasang pada tick pembunuhan bukan frame seperti itu. Pengecualian yang mungkin: data yang sengaja memasang frame ber-state `removed` sebagai frame jatuh.

## R24: `<stats>` (attacking, defend, ohp, omp)
- Sumber: `docs/txt/readme/dat file/stats.txt`. Parser: `record.data.stats = {attacking, defend, ohp, omp, regen_hp, regen_mp, regen_dhp, bleed_hp, recmp, ...}` (angka; tidak ada bila tidak ditulis). Pembagian: AI2 (`st_stats.lua`) membaca regen_hp / regen_dhp / regen_mp / recmp / caught / reserve; AI3 (`fx_stats.lua`) membaca attacking / defend / ohp / omp; `bleed_hp` adalah efek darah di UI (AI4, lihat bpoint); pengaturan senjata (oid, normal_attack1 ..., phase, respond, weaponact) belum dikerjakan.
- `fx_stats.stat_damage(attacker, victim, damage)`: `attacking` = persen dari injury objek PENYERANG (semua tipe objek; 0, 100 dan negatif = bawaan); `defend` = persen pertahanan korban, hanya t0: cedera DIBAGI X / 100 ("defense 0.5x" = menerima dua kali lipat); `fx_constants.defend_divides = false` memakai arah sebaliknya [BELUM PASTI]. Dipakai di empat tempat `combat.lua` yang memakai `itr.injury` (pukulan biasa, bdy kompleks, pukulan yang ditangkis, kind 16 pembeku) dengan urutan attacking -> weak -> defend -> armor -> pengali mode global. Tidak berlaku untuk kotak ringkasan damage, seruling dan es pecah (sesuai readme); badan yang dilempar memakai `<stats>` objek yang dilempar, bukan pelempar [BELUM PASTI].
- `fx_stats.scaled_opoint(parent, "ohp" | "omp", angka)` dipakai `fx_point.extend`: persen pengali hp: / mp: setiap opoint milik berkas data PEMBUAT objek, hanya bila opoint menulis hp: / mp:; satuan persen seperti attacking [BELUM PASTI].

## R25: `<stats>` `phase: 1` pada senjata
- Sumber: `docs/txt/readme/dat file/stats.txt` baris 83-84 ("Add phase:1 in weapon data only - to make the weapon not leave map area [t1,t2,t4 and t6 only]"). Parser: `record.data.stats.phase` (angka).
- `weapons.carry` (akhir tick): senjata t1, t2, t4, t6 yang `data.stats.phase == 1` dijepit ke area: x di [0, `state.stage.width`] dan z di [`zboundary` dekat, jauh] (batas yang sama dengan kamera, jawaban AI2 putaran 31). Nilai phase lain (0, 2, nil) tidak berpengaruh; bola (t3) dan karakter tidak terpengaruh (karakter sudah dijepit z oleh `weapons.carry`). [BELUM PASTI]: kecepatan tidak dinolkan di tepi; batas x memakai 0 sampai lebar stage tanpa margin.
