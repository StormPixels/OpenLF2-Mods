# AI 2 putaran 1-2 — input, gerak frame, state alur, time stop, charge, kamera, hit_Fa

Dasar: BASE `base-20261103-1-55f161e` (OpenLF2.zip, HEAD `55f161e`). Nomor bagian merujuk DOCX "Daftar fitur LF2 Darkfiren (update 17)".

## Yang dikerjakan

| Fitur | Bagian | Modul | Hook (satu panggilan) |
|---|---|---|---|
| `hit_f/b/uz/dz` | 2 | `st_input.lua` | `control.step` |
| `hold_a/d/j/f/b/uz/dz` | 2 | `st_input.lua` | `control.step` |
| `hit_Faj/Uaj/Daj` | 2, 16.3 | `st_input.lua` | `control.lua` (`recognize`) |
| `hit_g` (mendarat) | 2 | `st_frame.lua` | `physics.step` |
| `dx, dy, dz` | 2 | `st_frame.lua` | `physics.step` |
| `hp, chp, cmp` | 2 | `st_frame.lua` | `animation.advance` |
| `caught` | 2 | `st_frame.lua` | `control.enter_frame`, `animation.advance` |
| `next: 13XX` | 2 | `st_states.lua` | `animation.advance` |
| state 80/81/82, 121-139 | 3, 15.2 | `st_states.lua` | `animation.advance` |
| state 62-66, 85/86, 20/21, 150-159, 364X, 4xxx, 17xxx, 404, 405 | 3, 15.2 | `st_states.lua` | `frame_rules` (after_control, before_advance), `match.advance_item` |

Semua aktif hanya bila frame membawa kunci/state itu. Kunci baru dibaca dengan aman (`nil` = perilaku lama). Field runtime hanya di `value.st` (kontrak I7); `value.st.invisible` disediakan untuk AI 4 (I10).

## Keputusan dan [BELUM PASTI] (semua nilai ada di `st_constants.lua`)

1. **`hold_*`**: DOCX hanya menulis "sekitar 2 detik"; dipakai 60 tick (30 tick/detik). Putaran 3: hitungan dari **tombol** (bukan dari frame): tombol harus tertahan terus selama 60 tick, hitungan tidak direset saat frame berganti, dinolkan saat tombol dilepas dan setelah pindah frame. Komputer tidak pernah memakai `hold_*`.
2. **`hit_Faj/Uaj/Daj`**: tombol J menggantikan A pada urutan Defend, arah, tombol. Urutan itu sama dengan `hit_Fj/Uj/Dj`, jadi tag baru dibaca sebagai cadangan; `hit_Fj` menang bila keduanya ada. Nama pdk (`hit_aj`, `hit_jj`, `hit_aa`, §16.3) belum dipahami dan TIDAK dibaca.
3. **`hit_f/b/uz/dz`**: dipicu oleh tekanan baru (jendela 5 tick seperti `hit_a`). `hit_a/d/j` dicek lebih dulu dan menang.
4. **`dx/dy/dz`**: `dx` mengikuti arah hadap, `dy` < 0 ke atas, `dz` > 0 ke bawah layar. Tidak berlaku saat hit-lag. `dy` tidak mendorong objek di bawah tanah.
5. **`hp`**: mengurangi HP saat frame dimasuki (tidak jadi bila HP tidak cukup). **`chp`**: mengisi HP dan menaikkan HP gelap (dark hp) sebesar chp/3 [BELUM PASTI]; HP tidak melewati dark hp (dark hp ikut naik bila perlu) dan tidak melewati HP maks. **`cmp`**: mengisi MP (negatif mengurangi), batas 0..500.
6. **`mp` negatif "untuk menambah"** (DOCX): TIDAK diubah. Kode lama memakai `mp < 0` sebagai biaya MP berkelanjutan dan DOCX bertentangan dengan itu. Perlu keputusan.
7. **`caught`**: hanya prioritas frame (frame > `<stats>` > `<mode>`); dua yang terakhir belum ada. Berlaku saat frame dimasuki lewat tombol (`enter_frame`) dan lewat `next`.
8. **`next: 13XX`**: lompat acak ke frame sekarang +1 sampai +XX (`engine.random`). XX = 01..99.
9. **State 80/81/82**: ditambahkan ke besar `next` (tanda negatif/putar dipertahankan). 80: easy +3, normal +2, difficult +1, crazy +0. 81: +1 bila mode stage dan stage selesai (dikenali dari `round_counter` >= 350 atau `stage_run.ending`) [BELUM PASTI: definisi "selesai"]. 82: +1 untuk tim 5.
10. **121-139**: tambah acak 0..(state-120): 121 -> 0..1, 122 -> 0..2, 139 -> 0..19.
11. **150-159**: mengatur tambahan pemulihan MP 0..9 dan tetap berlaku sampai state 15x lain [BELUM PASTI: tetap atau hanya selama frame]. Ditambahkan pada rumus pemulihan di `match.regenerate`.
12. **62-66**: tiap tick selama frame: HP=1; HP dan dark HP=0; MP=0; HP dan dark HP=500; MP=500.
13. **85/86**: arah dibalik sekali saat frame dimasuki. 86 juga langsung mengambil `next` tanpa menunggu `wait` [BELUM PASTI: "maju satu frame" dibaca begitu; alternatifnya gerak maju satu langkah].
14. **20/21**: `value.st.invisible` selama frame; 21 tidak berlaku bila `value.st.clone` (penanda clone dari AI 3, belum ada; tanpa penanda dianggap bukan clone).
15. **364X**: tim = X (0-5) saat frame dimasuki. Efek itr 364 adalah urusan AI 3.
16. **4xxx**: cadangan nyawa = xxx saat frame dimasuki, hanya karakter; petarung dengan nyawa >= 2 dari state ini bangkit dan memakai satu nyawa (putaran 3). **17xxx**: HP + xxx (0 berarti 100), tidak melewati HP maks [BELUM PASTI: batas]; titik temu dengan `gain` (AI 3) hanya lewat angka mentah 17xxx.
17. **404**: tahan di frame sampai ronde habis (`round_counter` > 0). **405**: pindah ke tengah peta, x dan z (z dari `zboundary`) [BELUM PASTI: hanya x atau x dan z].

## Putaran 2

| Fitur | Bagian | Modul | Hook |
|---|---|---|---|
| `1xxxyyy` / `2xxxyyy` (cabang HP/MP) | 3 | `st_states.resolve_next` | `animation.advance` |
| `9xxx` (frame saat mendarat) | 15.2 | `st_frame.landing` | `physics.step` |
| `8XXXX` (transformasi id 0-9999) | 3, 20.4 | `st_states.transform` | `frame_rules.after_control` |
| `6XXX` (jurus charge) | 3, 20.2 | `st_states.charge` | `frame_rules` + `st_states.after_advance` |
| `3xxyzzz` (time stop) + `frame_rules.frozen` (I2) | 3 | `timestop.lua` | `match.lua` (control/physics/advance dilewati bila beku) |
| `99XXX` (kamera ikut objek), `5XXYY` (gempa) | 3 | `st_camera.lua` | `camera.step`, `match.step` |
| `7XXX` (AI mengambil alih manusia) | 3 | `st_states.run_takeover` | `match.read_input` |
| `9XX/9XXYY/7XX/7XXYY` (ganti background / bg mode) | 3 | `st_states.switch_background` | `frame_rules.after_control` |
| `hit_Fa` 24, 25, 26, 5xxx, 6xxx, 8xxx | 2, 20.2 | `st_fa.lua` | `match.read_input` |

### Keputusan dan [BELUM PASTI]

18. **`1xxxyyy`**: xxx = batas HP; HP di atas xxx pergi ke yyy, selain itu ke `next` (juga saat `next` = 0: tetap di frame). **`2xxxyyy`** mengikuti `txt/readme` (kedua catatan saling bertentangan): MP di atas xxx pergi ke `next`, selain itu ke yyy. Satu tempat untuk membaliknya: `st_constants.branch.mp_swapped = false` (arah sama dengan HP).
19. **`9xxx`**: frame tujuan = state - 9000 (0-399); `hit_g` menang bila keduanya ada; 9400-9994 bukan state mendarat. Bentrokan dengan `9XXYY` dihindari karena itu 5 digit. "Mendukung cpoint" belum ada.
20. **`8XXXX`**: objek menjadi record XXXX (= state - 80000), pergi ke `next` frame lama (0 atau 999 berarti frame 0), offset skin tidak diubah. Aturan `wait`/`respond` untuk offset skin dan pengikut (`pass_record`) belum ada. Rentang lama `8000-8999` tidak disentuh.
21. **`6XXX`**: tombol yang ditahan saat frame dimasuki (A, D, J, maju, mundur menurut arah hadap) membuat petarung tetap di frame. Ditahan `wait` tick: pergi ke `hit_a/d/j` atau `hit_ext.f/b` sesuai tombol (frame itu harus terbayar). Dilepas lebih awal: ke `next`. Tiap tick menahan memakai `mp` frame itu. Bila MP kurang atau frame tujuan tak terbayar: `caught` frame charge (atau `caught` frame tujuan). [BELUM PASTI] DOCX menulis frame itu hanya "XXX". Tanpa tombol yang ditahan, frame berjalan seperti biasa.
22. **`3xxyzzz`**: xx = peluang persen (0 = selalu), y = jenis (0 semua kecuali pemakai, 1 semua kecuali tim pemakai, 2 semua objek bukan karakter), zzz = lama dalam tick (`st_constants.timestop.unit_ticks`) [BELUM PASTI satuan]. Hanya satu time stop berjalan; yang kedua diabaikan sampai selesai. Objek beku tidak menjalankan kontrol, fisika, dan pergantian frame; pemakai tidak pernah beku. Deteksi tabrakan adalah urusan AI 3 lewat `frame_rules.frozen` (I2): `combat.lua` belum memeriksanya.
23. **`99XXX`**: kamera mengikuti objek itu XXX tick (0: selama objek di frame itu). `match.st.camera_z` memuat z objek untuk kamera sumbu Y yang belum ada di kamera port ini.
24. **`5XXYY`**: x = XX - 50, y = YY - 50; sumbu yang ditulis `00` tidak bergerak (jadi `55200` = x +2 saja, `54800` = x -2). Hasil diumumkan di `match.st.quake_x/quake_y` (bilangan bulat, piksel, offset tick itu, nol bila tak ada gempa); AI 4 yang menerapkannya.
25. **`7XXX`**: komputer memainkan petarung manusia selama XXX tick (`st_constants.ai_takeover.unit_ticks`). Memakai `ai.control` yang ada; belum dicoba dengan `ai.lua` nyata.
26. **Ganti background** (9XX, 9XXYY, 7XX, 7XXYY): AI 2 hanya meneruskan nomor state mentah ke `background.switch_state(match, nomor)` milik AI 5 lewat `pcall`; aturan artinya (9XX pasang background XX, 9XXYY bila background sekarang XX ganti ke YY, 7XX pasang mode XX, 7XXYY bila mode sekarang XX ganti ke YY) ada di AI 5. Dilewati bila fungsinya tidak ada. (Pemetaan lama (row, mode) di putaran sebelumnya salah dan sudah dihapus.)
27. **`hit_Fa` baru** (objek serangan, id dari `constants.object_ids`): 24 bola api chase saja (221), 25 bola es chase saja (222), 4 bola bila musuh <= 4, tambah satu per musuh, maksimum 10; 26 ledakan Firen: nyala frame 109 (y 2, sama seperti opoint ledakan Firen frame 289: centery 79, y 81) dan enam api tanah frame 50 (y -1), semuanya di tanah dan tanpa kecepatan vertikal, jadi tidak melayang walau objeknya di udara, tanpa kolom es atau bola chase; 5xxx malaikat id xxx satu per rekan hidup (termasuk pembuatnya, seperti mode 5 lama); 6xxx iblis id xxx satu per musuh, maksimum 7; 8xxx kelelawar id xxx: 3, tambah satu per dua musuh di atas empat, mengejar musuh acak. Kecepatan awal disalin dari mode lama di `objects.lua`. Nilai lain (1-12) tetap ke `objects.update`.

## Belum dikerjakan

- `caught` hanya membaca frame (belum `<stats>` dan `<mode>`).
- `mp` negatif "untuk menambah": tidak diubah (bertentangan dengan kode lama).
- Cabang `hit_Fj/Uj/Dj/ja/Ua/Da` untuk objek t3 (state 3000/3006), state 3007, 601-603, 180/190, 70/75: milik AI 3.
- Aturan `loop/amount/shadow/bound/center_z`: AI 4 yang menggambar; datanya tersedia lewat record.

## Putaran 7 (keputusan pengguna: tim 6, klon, time stop, confus, kamera, stats)

Dasar: base-20261106-2-46e3dcd. Keputusan pengguna yang dijalankan:
- **Tim musuh stage = 6** (`constants.teams.enemies = 6`), tim 5 menjadi tim biasa (`teams.player_five`), 10 slot pemain (`constants.player_slots = 10`; pemain komputer pilihan menu di slot + 10 = 10..19). Loop slot di `match.lua` (create, read_input, akhir ronde, exit) memakai konstanta itu; demo dan replay tetap 8 slot (format rekaman belum 10 slot). State 82 tetap "tim musuh stage" lewat konstanta.
- **Klon**: AI 3 mengisi `value.fx.clone`; `st_states.after_control` menyalinnya ke `value.st.clone` (state 21 tidak menyembunyikan klon; state 20 menyembunyikan semuanya).
- **Time stop**: bagian AI 3 (`frozen_can_be_hit = true`); AI 2 tidak berubah.
- **State 6xxx tetap charge**; pembanding HP 601-699 dan 6xxx dari DOCX 15.2 tidak dikerjakan.
- **Efek status** (`st_status.lua`, memakai `fx_status.active`): manacle = tanpa jurus kombinasi; bound (efek) = tombol lompat dicabut; facing = biaya MP x2 (`mp:` saja); weak = pemulihan HP berhenti, pemulihan MP dibagi 2 (berhenti bila hp = dark hp); confus = kiri/kanan dan atas/bawah ditukar (tabel milik AI 2, BUKAN dari exe; [BELUM PASTI] isi tabel aslinya tidak ada di dokumen); mimic = korban menyalin tombol penyerang (`value.fx.status.mimic_by`, slot penyerang; menunggu AI 3). **delay** (tak bisa bergerak cepat) belum dikerjakan: arti tepatnya belum pasti.
- **`<stats>`** (`st_stats.lua`, `record.data.stats`): `caught` (prioritas frame > stats; `caughtact` bukan cadangan karena itu kunci senjata), `recmp` (persen biaya MP), `regen_hp` (-1 tidak, X = +1+X), `regen_dhp` (1..5 menambah dark hp per langkah pemulihan; interval = sama seperti hp [BELUM PASTI]), `regen_mp` (-1 tidak; -2..-6 mengurangi 1..5; 0..4 default +X; 10..14 tetap 1+(X-10) tanpa memedulikan HP), `reserve` (nyawa pemain pilihan menu). Tidak diterapkan AI 2: `bleed_hp` (tidak ada kode darah di mesin), `ohp`/`omp` (spawn opoint, AI 3), `attacking`/`defend` (pertempuran, AI 3), pengaturan senjata (`weapons.lua`).
- **Data mulai ronde** (`st_spawn.lua`, dari `match.create`): `options.slots[slot].skin` (indeks 1..10) -> `value.pic_offset` (acak bila `skins.random = 1` dan tanpa pilihan); `start_frame` (header karakter > mode); `reserve` (stats > mode) -> `value.lives` dan penanda bangkit; `dx/dvx/dz/dvz` mode (dvx dan dx tidak dipakai di battle mode [BELUM PASTI]). Mode stage menimpa posisi x seperti sebelumnya.
- **`centery`** mode: tinggi jatuh penjahat yang dibangkitkan (`frame_rules.drop_in`) dan senjata acak jatuh (`match.lua`); hanya bila < 0, kalau tidak nilai lama.
- **`id_no_blink`**: `animation.lua` memakai `system_data.ids("id_no_blink")` bila daftar tidak kosong, kalau tidak aturan lama (id 30-39 selain kelelawar).
- **`dicontrol`** mode = 1 (kontrol pdk): `hit_ext.aj/jj/aa` dibaca lebih dulu daripada `Faj/Uaj/Daj`.
- **Lebar kamera** mengikuti layout: `background.window_width()` (1333/1018) dipakai `camera.lua`, nil = 794 (layout expand tetap 794).
- **`value.st.hidden`** = `value.st.invisible` (state 20/21), untuk radar AI 4.

## Putaran 8 (paket uji R7, tanpa perubahan perilaku)

Dasar: base-20261107-3-a050971. Tidak ada kode permainan yang diubah. Ditambah: karakter uji AI2STAT (id 992, `RESULT/testpack/data/ai2_stat.txt`), `PANDUAN_UJI_R7.md` dan tes `st_testpack_r7_test` (data asli lewat parser C++). Cakupan ponsel: start_frame, skin acak, reserve, regen_hp, regen_mp, recmp. Belum ada langkah ponsel untuk efek status, tag mode, kamera layout. centery pasukan battle mode: diminta ke AI 4 (`battle.lua` baris 168, milik AI 4); AI 5 mengonfirmasi bahwa pasukan memakai `centery`, bukan `dvy`, dan tanpa tag tetap -300.

## Putaran 9 (platform: bidang pendaratan)

Dasar: base-20261108-1-299f016. AI 3 menyediakan `platform.plane_at(match, value)` (`platform.lua`, R11): tinggi bidang (<= 0) atau nil. `physics.lua` memanggilnya lewat `pcall(require, "base/game/platform")`; tanpa modul itu atau tanpa platform, setiap angka sama dengan yang lama (hash regresi 2336476036 tetap).
- `value.floor_y`: bidang yang sedang dipakai item (nil = tanah, y 0). Diisi `physics.step` setiap tick setelah `y = y + vy` (supaya "kaki sebelumnya" = y - vy sesuai platform.lua). Hanya diminta bila item di udara, bergerak vertikal, atau sudah berdiri di bidang (hemat: pemindaian 1000 slot).
- `physics.lua`: semua pembanding dan pengisi `y` terhadap 0 memakai `floor` (karakter, light_item, baseball/drink, heavy_item, broken weapon; `landed`, `character_ground`). Sambil berdiri di bidang, gaya gesek tanah berlaku (memakai `floor_y` tick sebelumnya).
- Pemeriksaan "di tanah" yang ikut memakai `floor_y or 0`: `control.lua` (jalan, lari, lompat, 9 tempat), `animation.lua` (4), `frame_rules.lua` (2), `st_frame.lua` (`direct_move` dy, `landing`/hit_g), `ai.lua`, `camera.lua`, `match.lua` (baris 660).
- Tahap 1 = kind X0 saja (sesuai AI 3). X1 blok mutlak, X2/X3 bergerak, X4 resistansi, X5 pantul: belum. Gelombang t3 (3000/3006/3007 + hit_g): bagian AI 3.
- [BELUM PASTI] Belum diubah karena bukan berkas AI 2: `combat.lua` 592-599 (korban di bidang dianggap melayang), bayangan karakter (AI 4: masih digambar di y 0), kamera tidak mengikuti tinggi.

Perbaikan R10 (platform naik): platform.lua membiarkan item yang kakinya di bawah bidang menembusnya (jalan di bawah). Saat platform naik, kaki karakter yang berdiri di atasnya jadi lebih rendah dari bidang baru, sehingga karakter jatuh tembus. `physics.lua`: item yang berdiri di bidang (`floor_y` ada, `y == floor_y`, `vy == 0`) bertanya ke `plane_at` dengan kaki diangkat `platform_lift` (24), dan bila bidang baru lebih tinggi, `y` ikut dinaikkan ke bidang itu. [BELUM PASTI] 24 = batas naik per tick; platform yang naik lebih cepat tidak diikuti. Platform turun sudah benar (karakter jatuh ke bidang baru).
