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

Belum. Data yang ada: `kills`, `damage_dealt`, `hp_spent`, `mp_spent`, `pickings` (papan skor akhir yang sudah ada). Yang belum tersedia: siapa membunuh siapa
(`killed_by`/matriks) dan penghitung combo; keduanya perlu field baru di `value.fx` (I6, AI 3) atau di `match.lua` (AI 2).

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
- **Mode background**: `width`, `zboundary`, `dvy`, `centery` kini ditandai supported di layar pilih karakter (diterapkan oleh background.lua, match.lua, weapons.lua). `attacking` (persen damage mode) belum diterapkan di game, jadi tetap meredupkan mode.
- Belum: skin per pemain (match.create belum memakai `options.slots[slot].skin`), 10 slot pemain di UI, `record.display` lengkap.
