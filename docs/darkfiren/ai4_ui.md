# AI 4 — mode menu, HUD, dan gambar frame (putaran 1)

Dokumen ini mencatat apa yang sudah dan belum didukung. Nomor bagian merujuk DOCX "Daftar fitur LF2 Darkfiren (update 17)".
Tampilan hanya bisa dinilai pengguna di ponsel; yang diuji di sini adalah logika (posisi, urutan panggilan gambar, pembacaan data).

## 1. Pemilihan mode (§10, §14, §17.4, §18.1)

| Layout (opsi `battlefield_layout`) | Lebar gambar | Berkas mode | Status |
|---|---|---|---|
| `classic` | 794 | (menu bawaan kode) | tidak berubah |
| `expand` | 794 | (menu bawaan kode) | tidak berubah |
| `wide 1333` | 1333 | `mode4.dat` (lewat `mode.dat`, `respond: 1333`) | tidak berubah; sumber teks: `game/dat_text`, lalu `game/mode_file`, lalu berkas game didekode di Lua |
| `wide 1018` | 1018 | `mode2.dat` (`respond: 1018`) | didukung. Sumber teks berurutan: `game/dat_text` (AI 5) -> berkas game `data/mode.dat` + `data/mode/mode2.dat` didekode di Lua (`game/data_text.lua`) -> salinan blok layout di `game/mode2_builtin.lua` (dengan catatan kuning di Opsi dan di layar pilih karakter). Tidak pernah jatuh ke classic tanpa catatan |
| (mode3, 10 pemain) | 1018 | `mode3.dat` | belum; lihat rencana di bagian 5 |

- `game/ui_modes.lua`: `parse(mode.dat)`, `for_width`, `layout_width`, `text(entry)`, `layout_text(layout)`, `random_pool`, `title`, `combo`.
- Hanya layout 1333 yang boleh jalan tanpa berkas mode (nilai bawaan kode = mode4). Lebar lain wajib punya berkas mode.
- Entri `hidden` diabaikan saat memilih berkas: pemain memilih layout secara eksplisit.
- `mode.dat` memakai `name`/`file`/`hidden`/`respond` dalam satu baris; nilai kata pertama saja (nama dengan spasi tidak didukung).

### Tag berkas mode

| Tag | Status |
|---|---|
| `<menu_control>`, `<grid_char>`, `<grid_bg>`, `<grid_bg_mode>`, `<grid_stage>`, `<misc>` | dibaca (`mode_layout.apply`); mode1/2/4 diuji |
| `<menu_small>`, `<time>`, `<cost>`, `<battle>` | dibaca per mode (tes `small_menu_modes_test`) |
| `<random>` | dibaca dari berkas mode, cadangan `game/random_pool` |
| `<name>` | judul mode digambar di pojok kiri atas layar pilih karakter pada layout lebar (teks `hexf`, bayangan `hexb` 1 px) |
| `<combo>` | dibaca (`ui_modes.combo`), belum digambar: match belum punya penghitung combo |
| `<frame>` (mode3/mode4) | belum dipakai |
| `<menu_wait>`, `<background>`, `<bmp_begin>` | belum dipakai |
| blok `<mode>`/`<grid_bg>` ganda (mode3) | dibaca (`mode_layout.all_blocks`, diuji); belum dipetakan ke panel: `blocks` tetap hanya blok pertama. mode3: `<mode>` pertama = tingkat kesulitan (Easy..CRAZY!), kedua = mode permainan; `<grid_bg>` pertama berbentuk panel BOX_BGMODE, kedua BOX_STAGE [BELUM PASTI peran tiap blok] |

## 2. HUD per gaya (§8, §15.5, §16.6, §18.2)

- `game/ui_hud.lua` membaca `data/frame.dat` (name, file, hidden, respond, facing) dan berkas gaya (`<frame>`, `<hp_bar>`, `<mp_bar>`, `<team_flag>`).
- Layout klasik/expand memakai HUD bawaan. Layout lebar memakai gaya pertama yang tidak tersembunyi, berlebar sama atau tanpa `respond`, dan untuk 8 pemain (`Default`).
- Gambar gaya (`sprite/frame/...`) dipakai bila ada di game; jika tidak, tetap `pe/frame` dan `pe/bars`.
- Cadangan: angka bawaan (198x54, 4 kolom, bar 124x10 di (57,16) dan (57,36)) ada di `ui_hud.default_style()` dan salinan `fallback_hud` di `match_screen.lua` (untuk host/tes tanpa modul).
- Per objek (I8): `record.display.hp_bar` / `mp_bar` (hanya tipe 1 atau tanpa tipe, dengan `x`,`y`,`w`) dan `team_flag{x,y}` bila ada; selain itu gaya.
- Pemain memilih gaya di Opsi (baris "HUD style", opsi tersimpan `hud_style`, muncul bila game punya `data/frame.dat`): hanya gaya tidak tersembunyi, untuk 8 pemain, dengan `respond` kosong atau sama dengan lebar gambar; Default = HUD bawaan (tidak membaca berkas). Gaya `hidden` belum bisa dipilih (butuh `unlock.allows`).
- Radar (`<radar>` di berkas gaya, gaya Radar dan Widescreen_Radar): gambar dasar, satu titik per objek bertipe/berstate yang terdaftar (gambar per tim untuk petarung, per tipe untuk lainnya, `dead` bila hp habis), berkedip bila `fall: 1` dan objek sedang berkedip, dan bingkai kamera (`cover`, warna `rect`). Posisi titik: lebar stage -> `width` dikurangi 2x`offset_x`, `zboundary` -> `height` dikurangi 2x`offset_y`, dari `start_x/start_y` [BELUM PASTI: pemetaan persis aslinya]. Gaya berukuran classic digeser ke tengah pada layout lebar; Widescreen_Radar (respond 1018) tidak digeser. Gambar yang tidak ada di game dibuang; tanpa gambar dasar tidak ada radar. Belum: kotak centang radar saat jeda (`action`), `pic_hidden`/`pic_clone`/`pic_heal`, senjata yang dipegang (`facing`), `shadow`, `transparency`.
- Belum: `stats_count`, `name`, `minibar`, `bossbar`, `effect`; gaya `facing: 10`.
- [BELUM PASTI] arti `type` bar selain 1 dan `col_*` untuk gaya non-default.

## 3. Tag gambar frame (§2, I10) — `match_screen.lua`

| Tag | Perilaku |
|---|---|
| `shadow: 1` | tanpa bayangan di frame itu |
| `bound: 1` | tanpa nama di bawah karakter di frame itu |
| `value.st.invisible` | gambar tidak digambar (state 20/21) |
| `amount`, `loop` | gambar diulang `amount` kali (maks 64), berjarak `loop` px (lebar gambar bila tanpa `loop`) — **tebakan**, meniru layer background |
| `center_z` | koreksi urutan gambar: `z + (center_z - 20000)` untuk 10000..29999, `z + (center_z - 200000)` untuk 100000..299999 (dokumentasi Darkfiren: yang z-nya terkecil digambar lebih dulu; 10000 = di belakang semua, 29999 = di depan semua). Hanya urutan, gambar tidak bergeser |
| skin `<pic>` / tombol D | belum: perlu `record.skins` (I1) dan perubahan di `character_select` |

Field snapshot baru `entry.invisible` dan `entry.depth` diisi ulang di setiap `screen.snapshot` (entri dipakai ulang; lihat A4-3). Tanpa tag, gambar sama dengan sebelumnya.
Perubahan tebakan: fungsi/kondisi ada di `draw_item` (blok `amount`/`loop`) dan `screen.snapshot` (`priority`).

## 4. Papan siapa-membunuh-siapa dan combo (§14.1, §16.7)

Combo: lihat bagian 11. Papan siapa-membunuh-siapa: lihat bagian 14 (sejak putaran 13).

## 5. Rencana (P3): 10 pemain dan lainnya

Tempat yang mengandaikan 8 slot (`for ... = 0, 7`, `slot + 10`, `slot < 8`, 4 kolom HP), jumlah baris yang cocok menurut grep (perkiraan, termasuk kecocokan palsu):
- `scripts/base/ui/battle_setup.lua`: 4 tempat
- `scripts/base/ui/championship.lua`: 17 tempat
- `scripts/base/ui/character_select.lua`: 27 tempat
- `scripts/base/ui/controls.lua`: 3 tempat
- `scripts/base/ui/demo.lua`: 3 tempat
- `scripts/base/ui/ending.lua`: 1 tempat
- `scripts/base/ui/flow.lua`: 1 tempat
- `scripts/base/ui/font.lua`: 1 tempat
- `scripts/base/ui/input.lua`: 1 tempat
- `scripts/base/ui/match_screen.lua`: 7 tempat
- `scripts/base/ui/title.lua`: 1 tempat

Usulan bertahap (tidak dikerjakan di putaran ini):
1. Satu konstanta `constants.player_slots` (8, atau 10 menurut mode) dan pembantu `slot_index(n)` yang menggantikan `slot + 10`; mulai dari `character_select` dan `battle_setup`.
2. HUD: gaya `facing: 10` (`frame/10/*.dat`, `row: 5`, `frame_x: 14`) lewat `ui_hud` (sudah membaca `row`, `frame_x`); `draw_status` perlu loop sampai 9.
3. `mode3.dat`: blok ganda sudah terbaca (`all_blocks`); tinggal memetakan tiap blok ke panelnya (perlu konfirmasi peran, lihat tabel tag), lalu layout 10P (`row: 5`, `facing: 10`) dengan tes seperti `layout_modes_test`.
4. `match.lua` (AI 2): 10 slot pemain dan hook maks 40 baris; ini berkas di luar lingkup AI 4.
5. Radar (§16.6), `minibar.dat` (§14.5), grid `<phase>` (§14.6), `<menu_wait>`, nama mode hitlag `_1.._5`: belum dimulai.

## 6. Tes (RESULT/tests)

`bash RESULT/tests/run.sh` dari akar repo: `ui_modes_test`, `layout_modes_test`, `match_layout_test`, `small_menu_modes_test`, `ui_hud_test`, `frame_tags_test`.
Data contoh ada di `RESULT/tests/data` (salinan `mode.dat`, `mode1-4.dat`, `frame.dat`, dua berkas gaya HUD dari `darkfiren-knowledge`).

## 7. Putaran 2 (perbaikan)

- **Layout 1018 jadi classic (akar masalah)**: tiga sebab berurutan: (1) `game/dat_text` belum ada di C++ sehingga `mode.dat` tidak terbaca; (2) jalur `mode.dat` yang saya pakai salah (`data/mode/mode.dat`; yang benar `data/mode.dat`); (3) gambar menu mode2 `sprite/ui/charmenu.bmp` bukan berkas tersendiri (layout classic menggambar `pe/charmenu`). Perbaikan: `game/data_text.lua` membaca berkas game apa adanya dan mendekode `.dat` seperti `src/resources/data_file.cpp` (lewati 123 byte, kurangi kunci 37 huruf dari awal berkas); `character_select` memakai `pe/charmenu` bila berkas gambarnya tidak ada; salinan bawaan di `game/mode2_builtin.lua`; catatan di layar bila tidak membaca berkas game.
- **Gempa layar**: `match.st.quake_x/quake_y` (piksel, dibatasi +-50) menggeser seluruh arena (latar, objek, spark) lewat pembungkus `context` di `match_screen.lua`; HUD, perintah stage, dan gambar jeda tidak ikut. Positif = ke kanan/bawah (arah itu pilihan saya).
- **center_z**: aturan diperbaiki sesuai dokumentasi (lihat bagian 3).
- **Judul mode** (`<name>`) digambar; **gaya HUD pilihan pemain** ditambahkan (bagian 2).
- **Radar** digambar (lihat bagian 2); sebelumnya memilih gaya Radar hanya mengubah kotak HUD.

## 8. Putaran 5 (keputusan pengguna, BASE base-20261106-2-46e3dcd)

- **Lebar jendela pertandingan**: `match_screen.create` memanggil `background.set_window_width(options.wide_width(layout))` sebelum `match.create` setiap pertandingan dibuat (semua titik pembuatan, termasuk replay, demo, dan lanjutan stage, lewat satu fungsi). 1333 dan 1018 untuk layout lebar, nil untuk classic dan expand. [BELUM PASTI] replay yang direkam pada layout lain: lebar jendela hanya memengaruhi mode background bertag `width: -1`.
- **Kunci buka**: `match_screen.unlock_key(state)` meminta `stage.unlock_key(match)`; `flow.lua` (cabang `round_over`) memanggil `unlock.grant(key)` sekali per pertandingan bila ada kunci. UI tidak menilai kemenangan.
- **Tim 6**: pilihan tim di layar pilih karakter berputar modulo `constants.teams.enemies` (bukan 5), jadi tim 5 bisa dipilih setelah AI 2 mengubah konstanta; sebelum itu perilakunya sama. Huruf label tim (`pe/words<n>`) untuk tim di atas 4 jatuh ke `pe/words0` bila sheet-nya tidak ada. Radar: bila musuh stage tim 6, tim 5 memakai `pic_team5` dan musuh memakai gambar petarung (`pic_type0`) [BELUM PASTI]; selama musuh tim 5 perilakunya sama seperti sebelumnya.
- **Radar**: titik khusus `pic_hidden` (value.st.hidden, mengabaikan daftar state), `pic_clone` (value.st.clone), `pic_heal` (petarung yang sedang pulih), `pic_dead` tetap yang utama. Semua nil-safe.
- **Mode background**: `width`, `zboundary`, `dvy`, `centery`, `attacking` kini ditandai supported di layar pilih karakter (diterapkan oleh background.lua, match.lua, weapons.lua). `attacking` (persen damage mode) kini diterapkan game/combat.lua (BASE base-20261107-1-394e07b), jadi juga ditandai supported.
- Belum: skin per pemain (match.create belum memakai `options.slots[slot].skin`), 10 slot pemain di UI, `record.display` lengkap.

## 9. Putaran 6 (BASE base-20261107-1-394e07b)

- **`hidden:` per entri lewat `unlock.allows`**: `menu_small.shown/rows` dan `stage_levels.visible` menerima parameter `cheat` berupa boolean (aturan lama: 1 sampai 3 tampil bila kode dimasukkan) atau fungsi `allows(hidden)`; `character_select` memakai `unlock.allows` untuk daftar mode, level stage, dan baris panel kecil (tanpa `unlock.allows`, di host/tes lama, aturan lama tetap berlaku). Gaya HUD di `ui_hud` (daftar nama dan pemilihan) memakai `unlock.allows` untuk gaya `hidden: 1` dan `2` (Crazy_Ui2, Crazy_Ui4, Widescreen_Crazy_Ui1, Widescreen_Crazy_Ui3). Kunci kunci 10..1000 berlaku bila tersimpan.
- **Minibar** (`<minibar>` pada dat karakter, `record.display.minibar.layers`): digambar di bawah karakter (`match_screen.draw_minibar`). Layer tanpa `type` = gambar (bingkai); `type` 1 = hp, 2 = hp gelap, 3 = mp (lebar penuh = `max`, bawaan 500); `facing: 1` mengisi dari kanan; `transparency: 1` = hitam transparan; daftar `team:` (kode tabel readme/dat file/minibar.txt: 1-4, 5 = musuh stage, 10-13 independen pemain, 20-27 independen komputer) dan `respond` (0 versus, 1 stage) memilih untuk siapa dan mode apa. Belum: tipe 4 dan 5 (fusion time), `effect`, `cc`/`c1`/`c2`, `bound`/`centerx`. [BELUM PASTI] jangkar posisi (x dari tengah karakter, y dari garis tanah/z) dan bentuk `respond` berulang (AI 1 hanya mengekspos `teams` sebagai larik).
- **Mode background**: `attacking` kini ditandai supported (diterapkan `game/combat.lua`).
- **Belum**: 10 pemain di UI (HUD memakai slot 0..7, `controls`/`input` 0..7, layar pilih karakter 8 slot), skin `<pic>`, `record.display` selain hp_bar/mp_bar/team_flag/minibar, grid `<phase>`.

## 10. Putaran 7: skin <pic> (BASE base-20261107-1-394e07b)

- **Pilih skin**: di layar pilih karakter, tombol D (bertahan = huruf `f` dari `ui/controls`) menggilir skin karakter yang sedang dipilih, di semua mode kecuali championship dan team championship (readme/dat file/skin system.txt). Skin dibaca dari `record.data.skins` lewat `object_data.load` saat karakter pertama kali ditanyai (diingat per berkas); karakter dengan kurang dari dua skin atau `random: 1` tidak bisa digilir (pertandingan memilih skin acak lewat `st_spawn.skin`). Urutan: skin 1 (bawaan), lalu 2, 3, ... dan kembali ke 1. Ganti karakter melupakan skin.
- **Ke pertandingan**: `selection.match_options` mengisi `options.slots[slot].skin` (1..10, nil = bawaan) untuk manusia dan komputer; `st_spawn.skin` (AI 2) mengubahnya menjadi `value.pic_offset`.
- **Tampilan**: wajah di kotak karakter memakai `skins[i].head`, wajah kecil di HUD memakai `skins[i].small` (dicocokkan lewat `offset == pic_offset`); gambar yang tidak ada di game kembali ke milik karakter. Belum: bunyi skin (`skins.sound`; sekarang bunyi menu bawaan), `respond`, wajah skin di radar dan layar akhir.

## 11. Putaran 8: tampilan combo (BASE base-20261107-1-394e07b)

- **Combo** (`<combo>` pada berkas mode, readme/mode dat.txt): bila `value.fx.combo` (AI 3: jumlah pukulan beruntun penyerang) minimal 2 dan `value.fx.combo_age` kurang dari `times` (bawaan 30 tik), `match_screen.draw_combo` menulis teks `name` (bawaan `%d_hit`, `%d` = jumlah pukulan) di atas penyerang dengan gambar `pic` sebagai grid 16 x 16 blok `w` x `h` menurut kode ASCII (dokumentasi: "row and columns are 16 and 16"). Pengaturan dibaca per layout oleh `ui_modes.combo_settings(layout)`: layout classic dan expand memakai `mode1.dat`, layout lebar memakai berkasnya sendiri; mode4.dat tidak punya `<combo>`, jadi di wide 1333 tidak ada tampilan combo. `bound: 0` mematikannya.
- Aturan hitung (siapa yang dihitung: `effect`; `caughtact`; reset `respond`; klon ke pemilik) ada di AI 3 (`fx_stats.lua`); UI hanya menampilkan.
- [BELUM PASTI] mulai dari 2 pukulan, jangkar (di tengah atas kepala, `offset_y` ke atas, `offset_x` ke kanan), dan `facing: 0` (di atas korban, tidak digambar).

## 12. Putaran 10: 10 pemain di UI (BASE base-20261108-2-427e8d9)

- **Layout baru "wide 1018 10P"** (`options.wide_layout_10p`): 1018 lebar, memakai `mode3.dat` (CHARMENU2, 5 kotak per baris, dua baris). `options.slot_count(layout)` = 10 untuk layout itu, 8 untuk yang lain; `options.wide_width` = 1018. Layout ini ditawarkan di Opsi hanya bila `mode3.dat` bisa dibaca dan `unlock.allows(hidden)` mengizinkan (`hidden: 1` di mode.dat); layout tersimpan yang terkunci jatuh ke menu klasik 8 slot dengan catatan layar. Tidak ada salinan bawaan untuk mode3.
- **Layar pilih karakter**: 10 slot selalu dibuat, `state.slot_count` (8 atau 10, hanya 10 bila layout 10P benar-benar tergambar) menentukan berapa yang dipakai; semua perulangan 0..7 (26 tempat) memakai `(state.slot_count or 8) - 1`. Pilihan tim slot 8 dan 9: siklus yang sama (independen dan tim sampai `constants.teams.enemies - 1`). Mode battle: dua sisi lima (slot 0-4 tim 1, 5-9 tim 2) di 10P, dua sisi empat di 8P. `selection.match_options` memuat slot 0..9.
- **HUD 10 pemain**: gaya `facing: 10` dari `frame.dat` (`ui_hud.pick(list, width, 10)`, `data/frame/10/default.dat`: lima kotak per baris mulai x=14, tidak digeser ke tengah). Gaya pilihan pemain (nama) dicari di antara gaya `facing: 10`; nama yang tidak ada: default 10. Tanpa `frame.dat` ada gaya bawaan 10 pemain (`ui_hud.default_style(10)`). `draw_status` memakai `style.slots`; item komputer slot 8 dan 9 = item 18 dan 19.
- **Papan skor akhir**: menampilkan 10 pemain di layout 10P (tinggi `players * 45 + 93` = 543, lewat 530 sehingga sedikit terpotong di atas; mode battle di 10P lebih tinggi lagi [BELUM PASTI]).
- **Belum**: tombol pemain manusia untuk slot 8 dan 9 (`ui/input.lua` hanya menyampel slot 0..7 dan tidak ada set tombol/konfigurasi untuk keduanya, jadi keduanya praktis diisi komputer lewat menu komputer); radar dan minibar untuk slot 8 dan 9; gaya HUD 10 pemain tersembunyi lain selain lewat `unlock.allows`; demo, replay, dan championship di 10P.

## 13. Putaran 12 (BASE base-20261109-1-f5cc706; dari Ringkasan balasan Darkfiren dan AI2)

- **BG_FRAME**: `character_select.small_background` menggambar `sprite/ui/bg_frame.bmp` (atau `pe/bg_frame` bila hanya ada di resource game) di (`frame_x`, `frame_y`) sebagai bingkai, lalu gambar latar. Sejak putaran 17 `misc.frame_pic` (`pic:` di berkas mode, MENU_CLIP2b) hanya dipakai sebagai bingkai bila BG_FRAME tidak ada, karena digambar di tempat yang sama ia menutupi BG_FRAME (laporan pengguna). [BELUM PASTI] posisi dan urutan: dugaan dari jawaban Darkfiren ("BG_FRAME.bmp adalah gambar dasar; background atau gambar khusus mode ditampilkan di atasnya").
- **Bayangan**: digambar di `z + value.floor_y` (snapshot `entry.floor_y`, 0 bila tidak ada); `floor_y` negatif = di atas tanah (platform).
- **Sprite di luar +-8192**: sprite utama objek yang posisinya melewati +-8192 (mis. opoint y 20000) dilewati di `draw_item`, tidak diserahkan ke host. Spark, label, minibar, dan HUD tidak dijaga (penolakan di host sebaiknya diubah menjadi "lewati").
- **Kamera vertikal** (`zcam` / `zcamera`): `match_screen` membaca `match.camera_z` (piksel, 0 atau lebih; nil-safe) dan menggeser seluruh arena (latar, objek, spark) ke atas sebesar itu, bersama gempa; HUD tetap. Yang belum: scroll paralel (latar lebih lambat) menunggu data dari AI 5, dan `camera_z` itu sendiri (AI 2, `camera.lua`).
- **Label nama**: item 0..9 memakai nomor pemain (`entry.index < constants.player_slots`), item 10..19 "Com" (perbaikan R11 yang opsional kini ikut).
- **HUD**: bar MP dijepit ke `constants.points.full` (500) sehingga MP sampai 1000 tampil penuh.

## 14. Putaran 13: papan siapa-membunuh-siapa (BASE base-20261110-1-96c6fa7; DOCX 14.1 dan 16.7, readme/mode dat.txt)

Sumber aturan: blok `<bmp_begin>` pertama di berkas mode (readme/mode dat.txt, "CUSTOM NAME DISPLAY OF WHO KILLED WHOM"). Catatan: ringkasan di DOCX
memetakan `x`, `dx`, `dvx` kurang tepat; yang berlaku readme: `x` = posisi nama penyerang, `dx` = posisi gambar tambahan, `dvx` = posisi nama korban.

- **Pengaturan** (`game/ui_modes.lua`): `ui_modes.kill_board(text)` membaca blok (baris `mode:` dan `id:` boleh berulang; maksimal 20 id; nama gambar
  `pic_type0..6` dan `sound1/2` dijadikan huruf kecil dengan `/`), `ui_modes.kill_settings(layout)` mengambil berkas mode layout itu (classic dan expand: mode1.dat,
  wide 1018: mode2.dat; mode3 dan mode4 tidak punya blok, jadi tidak ada papan). `bound: 0` mematikan.
- **Deteksi** (`ui/match_screen.lua`, `screen.snapshot`): `value.fx.killed_by` (AI 3) hanya menghitung per slot pembunuh, tanpa waktu. Snapshot menjumlahkannya per
  karakter dan menganggap kenaikan total sebagai satu pembunuhan baru (pelaku = `fx.last_killer`). Total yang turun (`fx.reset` antar ronde), slot yang diisi
  record lain, atau pertandingan baru (tabel state lain) hanya menjadi dasar baru, bukan kejadian. Kejadian pertama yang terlihat tidak dihitung (kill yang sudah ada).
  Jam = `state.elapsed`; kejadian dibagi oleh dua buffer snapshot dan tidak berubah. Maksimal 12 kejadian, umur maksimal 1200 tik.
- **Gambar** (`draw_kill_board`, sesudah HUD): satu baris per pembunuhan yang berumur < `times` tik, `loop` piksel antar baris mulai dari `y`, yang tertua di atas,
  paling banyak `respond` baris. Baris: gambar menurut jenis objek pembunuh (`pic_type<n>`; sampai AI 3 mengisi `fx.last_killer_type`, selalu `pic_type0`) di `dx`,
  nama penyerang di `x`, nama korban di `dvx`. Nama = label di atas kepala ("P1", "Com") ditambah nama karakter (dari `catalog.load`, `_` jadi spasi) bila
  `caughtact` (penyerang) atau `catchingact` (korban) = 1; huruf tim bila `arest`/`vrest` = 1; `pickedact`/`pickingact` = 1 menulis "mundur" (di sini: berakhir di x).
  Hanya mode yang disebut `mode:` (bila tidak ada baris `mode:`, semua mode); id yang dikecualikan (korban atau penyerang) tidak tampil.
- **[BELUM PASTI]** posisi dan jangkar (gambar dan teks sama-sama di `y`), `respond` sebagai batas baris (readme tanpa keterangan), baris yang lama berhenti menggeser
  yang baru (dipadatkan), "mundur" = rata kanan di x, penghitungan id kecualian untuk penyerang juga, PNG beralpha (`sprite\\kill\\*.png`) bisa digambar host,
  kotak centang di jeda (`bound: 1`) belum ada (kotak ringkasan jeda belum ada di UI), `slot` korban yang dihapus pada tik yang sama tidak terlihat.
- **Belum**: suara `sound1`/`sound2` (hanya stage mode); jenis pembunuh t1..t6 (menunggu `fx.last_killer_type` dari AI 3; pencatat exe punya tipe per pukulan).
- Tes: `tests/kill_board_test.lua` (jalur nyata: mode1.dat/mode2.dat/mode4.dat asli, snapshot lalu draw).

## 15. Putaran 14: tata letak di gambar lebar (1018 dan 1333)

Semua tata letak AI 4 tadinya ditulis untuk gambar klasik 794 piksel. Di gambar lebar, selisih lebar = `gap` (1018: 224, 1333: 539) dan `gap / 2` = `center` (112, 270):

- **Menu pilih karakter** (`ui/character_select.lua`): pratinjau latar (`frame_x`/`small_x` dari `<misc>`, 531/538 di file mode) dan baris musik (`music_x`) bergeser `gap`, jadi di pojok kanan atas gambar lebar seperti di klasik (musik 603, bingkai 531). Tiga popup (daftar latar, daftar mode, daftar stage; panel 790 lebar) digambar di tengah: `state.dx = center` selama popup dibuka, ditambahkan oleh `image/keyed_image/text/sprite/fill`, dan koordinat sentuh dikurangi `state.dx`. Dialog sudah di tengah sejak dulu (`dx` di baris 447).
- **Pertandingan** (`ui/match_screen.lua`): papan ringkasan (`draw_scoreboard`) digeser `center`; perintah stage/battle (`view.stage`, ditulis `game/stage.lua`/`battle.lua` untuk 794) lewat `stage_dx(x, y)`: baris atas (y < 200): x < 200 tetap, x < 400 (judul) ke tengah, sisanya (tim kanan) ke tepi kanan (+gap); spanduk di bawah (stage clear, GO) ke tengah kecuali panah GO (x >= 600) ke tepi kanan. Petunjuk keluar demo (0x262) +gap, gambar DEMO (0x168) +center, batang hitam baris tombol fungsi selebar gambar. Gambar PAUSE sudah di tengah (360 + center, diuji).
- **[BELUM PASTI]** ambang `stage_dx` (menebak dari koordinat klasik), baris musik ikut ke kanan (diputuskan agar tetap bersebelahan dengan pratinjau), `xpos` judul stage Darkfiren yang melewati 400, papan kill memakai koordinat dari berkas mode apa adanya, strip replay.
- Tes: `tests/wide_match_test.lua`, `tests/wide_character_select_test.lua`; lima tes harness lama (`grid_test`, `mode_test`, `mode_filter_test`, `stage_grid_test`, `layout_integration_test`) menyimpan koordinat 794 untuk layout wide 1333 dan disesuaikan (`harness_update/`).

## 16. Putaran 15: darah (bpoint) dan bleed_hp (readme/frame/bpoint.txt, dat file/stats.txt)

Di `ui/match_screen.lua` (`draw_blood`, sebelum `draw_item`):
- Semua titik di `frame.bpoints` (sampai 5; bila tidak ada, `{frame.bpoint}`) yang `x > 0` meneteskan darah bila HP di bawah ambangnya. Ambang (persen dari `max_hp`): `point.respond` bila > 0, lalu `record.data.stats.bleed_hp` bila > 0 (dibaca langsung, bukan lewat `st_stats.of`), lalu sepertiga (bawaan lama).
- Data lama (hanya x dan y): gambar 1x3 `pe/bars` seperti sebelumnya. Bila ada `w`, `h`, `rect` atau `rect32`: persegi `fill` (lebar bawaan 1, tinggi bawaan 3).
- Warna: `rect` = RGB565 mentah, dikonversi seperti `convert_rgb565` di `background_data.cpp` ((r*0x200+g)*0x80+b)*8+0x070707, dipotong 24 bit; `rect32` = 24 bit (byte atas dibuang, seperti `background.lua`) dan menang bila keduanya ada; bawaan 0xF800 = (255,7,7). Contoh readme `rect: 4706` = (23,83,23), warna yang sama dengan tabel `remapped` di `background.lua`. Teks readme "0ff000" kemungkinan salah ketik untuk 0xF800 (merah RGB565).
- Parser (`object_data.cpp`): tag yang tidak ditulis tidak ada di tabel (nil, bukan 0); `bpoint_tags` hanya `w h rect respond`, belum `rect32` (diminta ke AI 1).
- [BELUM PASTI] persegi lebih lebar dari 1 yang menghadap kiri menutup piksel cermin; `respond`/`bleed_hp` 0 = tidak ditulis.
- Tes: `tests/blood_test.lua`.

## 17. Putaran 16: lebar kotak pesan ETC (`etc_width`)

Penanda perintah tim (`team_order_marker`: "Come!", "Stay!", ...) dijepit ke layar di `draw_item`; lebar jepitnya dulu literal 80 (`0x2ca` = 794 - 80). Sekarang `snapshot.etc_width` = `state.bg_area.etc_width` (AI 5, RESULT_AI5_R19; bilangan bulat > 0, nil bila tidak ada) dan jepitan memakai nilai itu, dipotong ke bilangan bulat; tanpa nilai (atau nilai bukan angka, nol, negatif) tetap 80. Dibawa juga ke view layout lebar. Penempelan ke pemain (`etc_mode: 1`) adalah penempatan objek di sisi AI 2; AI 4 tidak membacanya. Tes: `tests/etc_width_test.lua`. [BELUM PASTI] satuan etc_width (piksel, cocok dengan 80).

## 18. Putaran 18: `stats_count` dan `effect` di panel HUD (readme/dat file/stats count.txt, effect.txt)

`ui/match_screen.lua`: `draw_stats_count` dan `draw_effects`, dipanggil di `draw_status` untuk tiap petarung di slotnya (juga yang sudah mati), dari pojok kiri atas panel HUD pemain itu. [BELUM PASTI] jangkar panel (readme tidak menyebut; contoh `y: 75` di effect melewati tinggi panel 54, `y: 0/13/28` di stats_count cocok dengan panel).
- **stats_count** (maks 10 `count`): angka `type` (1 hp, 2 dhp, 3 mp, 4 total serangan = `damage_dealt`, 5 hp hilang, 6 mp terpakai, 7 kill, 8 pickings, 16 total hp, 17 total mp (500), 18/19 "sekarang/total" hp/mp, 20 sisa nyawa, 21 sampai 29 timer status poison, weak, manacle, delay, confus, join, mimic, bound, facing), paling banyak `max` (999 bila tak ditulis), huruf `pe/words<pic>` (`pic` 0..5, bawaan 0), rata kanan di x (`facing: 1` rata kiri), `respond: 1` hanya bila tombol fungsi dipakai (`cheat_lock > 0`). Tipe 18/19 mengabaikan max, pic, facing. Sejak putaran 19 (nama medan dari AI 3): 9 invincible = `value.blink`, 10 fall point = `value.timer_b0`, 11 fusion = `value.merge_timer`, 12 armor hp = `value.fx.armor.hp` (sebelum pukulan pertama: `record.data.armor.hp`), 13 waktu pulih armor = `value.fx.armor.timer` (-1 tampil 0), 14 defense = `<stats> defend` (bila > 0, selain itu `value.armor`; mengabaikan `max` dan `facing`) [BELUM PASTI sumber mana yang benar], 15 jumlah mati = `value.fx.deaths` (RESULT_AI3_R27, 0 bila belum ada). Belum ada nilainya sehingga tidak digambar: 30 sampai 37 (rage, unlimited, timer tak ditentukan) dan 38 (jumlah pukulan; hanya combo berjalan yang ada).
- **effect** (maks 100 layer): gambar (sumber dx,dy; w x h) selama status `type` aktif: -1 tidak ada, 0..5 poison berjenis itu, 6 poison, 7 weak, 8 manacle, 9 delay, 10 confus, 11 join, 12 mimic, 13 bound, 14 facing (timer dari `value.fx.status`, AI 3). 15 sampai 20 (rage, unlimited) belum. `bound: 1` memendekkan gambar menurut timer (`max` 999): `facing` 0 dari kanan, 1 dari kiri, 2 dari bawah, 3 dari atas. `respond` tidak dipakai (readme: semua mode). Belum: `cc`, `c1`, `c2` (animasi).
- Belum: `bossbar` (hanya stage mode; siapa bos belum jelas), `menu_face`, `name`.
- Tes: `tests/display_hud_test.lua`.

## 19. Putaran 20: jangkar perintah stage dan battle, bossbar (readme/dat file/bossbar.txt)

- **Jangkar**: perintah `text`, `sprite` (dari `game/stage.lua`, AI 5 R20) dan `caption` serta `text` dari `game/battle.lua` (milik AI 4 menurut AI 2 dan AI 5; diubah di putaran ini) berakhir dengan elemen terakhir opsional "L", "C" atau "R" (indeks 6; pada `text` tanpa warna jangkar boleh di indeks 5). `match_screen` memakainya di gambar lebar (`stage_dx(x, y, anchor)`: L +0, C +center, R +gap) dan menebak dari koordinat hanya bila tidak ada. battle.lua: baris tim kiri dan caption kiri "L", kanan "R". Sebelum R20 AI 5 tergabung, perintah stage tetap ditebak.
- **Bossbar** (hanya stage mode): `draw_bossbar` menggambar layer `record.display.bossbar` dari bos `state.stage_run.boss_slot` (AI 5, nil bila tidak ada; dibawa lewat `snapshot.boss_slot`) di koordinat layar x, y apa adanya (di gambar lebar di tengah: +center). Layer tanpa `type` = gambar utuh; `type` 1 (hp), 2 (dhp), 3 (mp) = batang selebar w sebanding nilai / `max` (bawaan: max_hp bos untuk 1 dan 2, 500 untuk 3), `facing: 1` mengosongkan ke arah kanan (x dan sumber x bergeser). Tipe 4, 5 dan animasi (effect, cc, c1, c2) belum. [BELUM PASTI] siapa yang tampil bila bos lebih dari satu (yang pertama), bar tetap tampil pada hp 0 sampai bos keluar dari state.items (tanpa isi), dan `max`.
- Tes: `tests/anchor_boss_test.lua`, `tests/battle_anchor_test.lua`.

## 20. Putaran 21: strip replay, combo facing 0, bunyi skin dan papan kill, wajah skin di ringkasan, `name`, grid `<phase>`

- **Strip replay** (`menu_clip4`, 725 lebar, berakhir di tepi kanan 794): di gambar lebar x = 67 + `wide_gap()` ([BELUM PASTI] mengikuti tepi kanan).
- **Combo `facing: 0`** (di atas korban): `entry.combo_victim` = `value.fx.combo_victim` (slot korban pukulan terakhir; AI 3, nil bila belum ada) dan, di akhir `screen.snapshot`, hitungan combo pelaku dipindahkan ke korban (`over_combo`; bila ada dua pelaku, yang combo_age-nya terkecil). `draw_combo` memakai hitungan itu bila `facing` 0, hitungan sendiri bila 1. Tanpa `fx.combo_victim` facing 0 tidak menggambar apa pun (seperti sebelumnya).
- **Bunyi skin**: `skins.sound` (jalur data) diputar saat D mengganti skin bila game punya berkasnya, selain itu "join".
- **Bunyi papan kill**: di stage mode, bila korban tim 1: `sound1`, bila musuh stage (`constants.teams.enemies`): `sound2`; hanya bila mode ada di daftar `mode:` blok, id tidak dikecualikan, dan berkasnya ada; masuk `state.direct_sounds` (antrean yang dipakai `sounds.direct`; `sounds.flush` memutarnya pada tik yang sama).
- **Wajah skin di radar**: radar menggambar titik tim (frame.dat `<radar>`), bukan wajah; tidak ada yang digambar. Layar ringkasan (`draw_scoreboard`) kini memakai `small_face` (wajah skin).
- **`<name>`** (nama panggilan di panel HUD, readme/dat file/name.txt): `respond` 2 menampilkan label pemain ("P1", "Com" untuk komputer) di (name_x, name_y) dari sudut panel; `respond` 1 (hanya online) dan 0 tidak; `team: 1` huruf tim (tag `team` belum ada di daftar AI 1, dibaca bila muncul). [BELUM PASTI] jangkar, huruf, dan teks.
- **Grid `<phase>`** (transformasi, `data.phase` dari AI 1; readme/dat file/phase.txt): tombol A pada petarung yang punya blok membuka grid (A di layar pilih karakter) berisi petarung ber-id di daftar `ids` (yang ada di game dan boleh dipilih): panah memindah, A mengambil (langsung lanjut seperti konfirmasi biasa), J menutup; `respond` seperti `hidden` (0 selalu, 1 sampai 3 setelah karakter dibuka cheat, 4 dan 10 ke atas tidak pernah); sound1 saat buka, sound2 saat tutup; `pic` di (pic_x, pic_y), sel dari (start_x, start_y) tiap centerx dan centery dengan `row` baris, kotak w x h berwarna `rect` (`bound` 1 berkedip, 2 tetap). [BELUM PASTI] jangkar sudut slot, urutan sel (per baris), `oid`, `hidden`, `caughtact`, `pickedact`, D untuk skin.
- Tes: `result21_match_test.lua`, `skin_sound_test.lua`, `phase_grid_test.lua`.
