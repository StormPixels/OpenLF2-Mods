# AI1: kunci Lua yang benar-benar diekspos oleh `engine.read_object_data`

BASE: `80a34ae` (StormPixels/OpenLF2-Mods, branch main). Daftar ini disusun dari keluaran program uji
`RESULT/tests/object_data_test.cpp` dan `RESULT/tests/expected/*.txt`; bila tidak cocok, keluaran program uji yang benar.

## Aturan
- Larik berindeks dari 1. `frames` berkunci nomor frame 0..998 (hanya frame yang didefinisikan).
- Kunci lama tidak berubah. Kunci baru muncul HANYA bila tag-nya ada di berkas (nil bila tidak ada), kecuali
  `opoint`, `bpoint`, `cpoint`, `wpoint`, `interactions`, `bodies` yang tetap selalu ada seperti sebelumnya.
- Semua angka diteruskan mentah (contoh `poison = 13005075`, `bdy.kind = 1052`).
- Tag yang sama muncul dua kali: nilai terakhir dipakai (seperti pembaca asli menimpa), kecuali tag berdaftar (di bawah).
- Tag tak dikenal: dicatat di `diagnostics` (maks 256 baris), tidak membuat parser gagal. Nilai tag tak dikenal ikut
  tercatat sebagai satu baris terpisah (perilaku lama, tidak diubah).
- Kegagalan fatal (objek tidak dimuat): >100 itr atau bdy, >20 opoint, >5 bpoint, >20 sound dalam satu frame.

## Tingkat atas
Sudah ada: `name, head, small, movement, weapon, sheets, strengths, frames, token_checksum, diagnostics`.

| Kunci baru | Isi |
|---|---|
| `header` | tag `<bmp_begin>` baru (lihat bawah); ada bila minimal satu tag ada |
| `stats` | `<stats>`: bleed_hp attacking regen_hp regen_mp regen_dhp defend normal_attack1 normal_attack2 jump_attack run_attack dash_attack light_throw heavy_throw sky_light_throw run_heavy_throw weapon_drink respond recmp max_mp ohp omp reserve phase caught caughtact bound y weaponact |
| `armor` | `<armor>`: type ratio decrease mp fall bdefend injury spark delay hp recover facing action (angka); sound1 sound2 (teks); `ids`, `states`, `effects` (larik dari tag berulang); `frames` (larik grup: tiap `frame: a b` jadi `{a, b}`, atau `{a}` bila satu angka) |
| `weapon_piece` | `team` dan `[1..5] = {act, framea, dvx, dvy, dvz, oid, amount}`; nomor piece di luar 1-5 dicatat di diagnostics |
| `sound_list` | suara senjata per background dan mode (readme `sound.txt`): `[i] = {bg, mode, weapon_hit, weapon_drop, weapon_broken}`. Satu entri per blok `bound:` ... `bound_end:` di dalam `<sound>` (maks 100). `bg` dan `mode` adalah HIMPUNAN dari tag `bg:`/`mode:` yang boleh berulang (maks 100 nilai): `entry.bg[n] == true` bila n terdaftar. Nilai mentah (mulai dari 0 atau 1 tidak ditetapkan dokumen). Entri cocok bila bg sekarang ada di `bg` DAN mode sekarang ada di `mode`; bila tidak ada yang cocok dipakai suara bawaan (`weapon.hit_sound` dkk). Bila BEBERAPA entri cocok, sumber (readme `sound.txt`) tidak menentukan prioritas; AI5 memakai entri pertama menurut urutan berkas **[BELUM PASTI]**, parser menyimpan urutan berkas apa adanya. Hanya untuk senjata t1, t2, t4, t6. Tag di luar `bound:` dicatat di diagnostics |
| `skins` | `random`, `sound`, `[i] = {pic, head, small, smallb, smallt, offset, respond}`; maks 10, sisanya dicatat dan diabaikan. `pic` = nomor setelah `pic:` (nil bila `pic:` ditulis tanpa nomor, seperti templat catatan); `i` = urutan blok |
| `command` | `[i] = {bound, type, respond, hp, mp, team, times, modes = {..}, actions = {..}}`; maks 10 |

| `phase` | `<phase>` (menu transformasi): `respond oid pic_x pic_y start_x start_y rect row centerx centery w h bound caughtact pickedact hidden` (angka), `sound1 sound2 pic` (teks), `ids` (larik dari `id:` berulang, maks 100; sisanya dicatat dan diabaikan) |
| `display` | blok tampilan, lihat bagian "display" di bawah; ada bila minimal satu blok ada |


## display (P3)
Hanya blok yang ada di berkas yang muncul. Bar berlapis memakai `layers[i]` (urutan di berkas).
- `hp_bar`, `mp_bar`, `minibar`, `bossbar`, `effect`, `menu_face`: tag blok (`type x y w h dx dy facing effect amount loop respond bound transparency max cc c1 c2 centerx cover mp start_frame end_frame throwx`, teks `pic`,
  `teams` = larik dari `team:` berulang) ditambah `layers[i]` dengan kunci yang sama. Maks layer: minibar 50, bossbar 50, menu_face 30, lainnya 100 (**[BELUM PASTI]** angka 100); kelebihan dicatat dan diabaikan.
  Tiap layer juga punya `layer` (angka setelah `layer:` bila ada) dan `comment` (teks `#...` di sebelahnya, tanpa `#`), mis. `"hit_Fa"`, `"stage bar hpbar"`. Ini tambahan, bukan dari kontrak.
- `stats_count[i]`: `x y type max respond facing loop` dan `pic` (angka bila tertulis angka, selain itu teks); maks 10.
- `team_flag`: `x` (dari `team_flag_x`), `y` (dari `team_flag_y`), `team0..team5` (teks, dari `teamN_flag`; **[BELUM PASTI]** tipe nilainya).
- `name`: `respond name_x name_y x y hexf hexb` (angka), `name` (teks). Blok ini ditulis `<name>` di data contoh dan `<n>` di catatan; keduanya diterima.
- `display.small` dari kontrak **tidak** diekspos: tidak ada tag `small` di blok tampilan mana pun pada data contoh.

## `strengths[i]` (entri 0-9, tidak berubah jumlahnya)
Kunci lama utuh. Baru: `dvz drain gain spark recover dbdefend z sound cover caughtact selfinjury decrease`.

## `header` (tag `<bmp_begin>`; `name: v` dan `name v` sama-sama diterima)
Angka: `heavy_walking_frame_rate heavy_running_frame_rate hidden random kind ratio use_ai drop bound shadow shadowsize effect start_frame cost respond pic frame_0mp small_x small_y property`.
Teks: `shadow_pic frame bars smallb smallc smalld smallp smallt hidden_head hidden_small sound1 sound2`.
Larik (`tag: N v1..vN`, N 0-100): `walking_frame running_frame heavy_walking_frame heavy_running_frame`.
Juga disalin ke sini: `weapon_hp weapon_drop_hurt weapon_hit_sound weapon_drop_sound weapon_broken_sound` (nilainya tetap ada di `weapon` seperti dulu).

## Frame
Lama: `name picture state wait next dvx dvy dvz center_x center_y mp hits opoint bpoint cpoint wpoint interactions bodies interaction_bounds body_bounds sound`.
Baru (angka, nil bila tidak ada): `dx dy dz hp chp cmp caught loop amount shadow bound center_z respond cover attacking caughtact music`
(`center_z` = tag `centerz`).

| Kunci | Isi |
|---|---|
| `hold` | `a d j f b uz dz` dari `hold_a` dst. |
| `hit_ext` | `f b uz dz g Faj Uaj Daj`; alias nama mode pdk `hit_aj hit_jj hit_aa` disimpan terpisah sebagai `aj jj aa` (slot yang sama dengan Faj/Uaj/Daj di exe; yang dipakai ditentukan flag `dicontrol` mode background, jadi pemilihan ada di sisi skrip). `hit_Fa` dkk tetap di `hits` |
| `ppoint` | `{kind, x, y, z}` bila blok `ppoint:` ada |
| `opoints[1..20]` | larik opoint; `opoint` lama = `opoints[1]` |
| `bpoints[1..5]` | larik bpoint; `bpoint` lama = `bpoints[1]` |
| `sounds[1..20]` | larik teks; `sound` lama = `sounds[1]` |
| `interactions[1..100]`, `bodies[1..100]` | kapasitas naik dari 5 |

## itr (`interactions[i]`, juga `strengths`)
Lama: `kind x y width height dvx dvy fall arest vrest respond effect catching_actions caught_actions bdefend injury zwidth`.
Baru (angka): `dvz drain gain recover dbdefend spark cover z dx dy dz delay poison confus weak manacle join mimic bound facing sound`.
### itr: catchingact, caughtact, pickingact, pickedact
Tiap tag disimpan SETIA seperti tertulis sebagai larik satu atau dua angka (nil bila tag tidak ada; nilai negatif dipertahankan; tanpa diagnostik bila hanya satu angka):
`interactions[i].catchingact`, `.caughtact`, `.pickingact`, `.pickedact`. Contoh gaya readme `catchingact: -120  pickingact: 120  caughtact: -130  pickedact: 130`
menghasilkan `catchingact = {-120}`, `pickingact = {120}`, `caughtact = {-130}`, `pickedact = {130}`.
- Arti sisi menurut readme `cpoint.txt`: catchingact/caughtact = sisi KIRI (X1/Y1), pickingact/pickedact = sisi KANAN (X2/Y2); bila X2/Y2 tidak ditulis dipakai X1/Y1; negatif = ganti arah hadap.
  Parser TIDAK menerapkan aturan itu; pemakai yang menurunkannya, mis. kanan-tangkap = `(pickingact or catchingact)[1]`, kanan-tertangkap = `(pickedact or caughtact)[1]`.
- Bentuk dua angka gaya LF2 2.0a (`catchingact: 121 122`, `caughtact: 130 131`) ada di data dan tetap terbaca: angka pertama dan kedua masuk `catchingact = {121, 122}`. **[BELUM PASTI]**
  Arti angka kedua pada bentuk ini (sisi atau hal lain) tidak ditulis oleh sumber mana pun; AI1 tidak menafsirkannya.
- Slot lama `catching_actions` dan `caught_actions` (dua slot, untuk data LF2 asli) tetap diisi seperti sebelumnya: `catchingact` mengisi `catching_actions[1..2]`, `caughtact` mengisi `caught_actions[1..2]`,
  TETAPI `pickingact` menimpa `catching_actions[1]` dan `pickedact` menimpa `catching_actions[2]` (perilaku 2.0a yang dipertahankan). Jadi untuk data gaya Darkfiren slot lama BISA tertimpa
  (contoh di atas: `catching_actions = {120, 130}`, bukan {-120, ...}). Untuk data Darkfiren pakai larik per tag di atas, bukan slot lama.

## bdy (`bodies[i]`)
Lama: `kind x y width height`. Baru: `zwidth`, `respond`. `kind` mentah.

## Point
- `opoint`/`opoints[i]`: lama `kind x y action dvx dvy oid facing`; baru `hp mp team z dvz reserve effect centerx centery centerz framea attacking pic join join_reserve join_pic`.
- `bpoint`/`bpoints[i]`: `x y`; baru `w h rect respond`.
- `cpoint`: kunci lama utuh; baru `z faction baction uzaction dzaction respond drain gain recover throwz` dan `catchingact caughtact pickingact pickedact` (larik satu atau dua angka sesuai berkas; arti kiri/kanan seperti pada itr, untuk cpoint belum ada dokumen setara). `daction` dan `throwinjury` sudah ada sebelumnya.
- `wpoint`: tidak berubah (`cover` dan `weaponact` sudah ada).

## Perubahan perilaku yang terlihat pada data lama
Hanya satu: frame dengan lebih dari satu blok `opoint`/`bpoint`/`sound`. Dulu blok berikutnya menimpa/menggabung ke satu rekaman;
sekarang tiap blok disimpan di larik, dan kunci lama menunjuk blok pertama (sesuai kontrak). Data LF2 2.0a asli tidak punya kasus ini.
`token_checksum` data tanpa blok baru tidak berubah; untuk berkas Darkfiren yang punya `<stats>`/`<armor>`/`<pic>`/dst. nilainya
berubah karena token di dalam blok itu kini dibaca oleh parser blok (bukan dihitung sebagai token tingkat atas).

## Catatan R2
`mp` (mp_bar), `start_frame`/`end_frame`/`throwx` (minibar), dan `times` (command) ditambahkan setelah dicocokkan dengan dokumen asli `docs/txt/exe/*.txt`. **[BELUM PASTI]** nama tag persis `start_frame`/`end_frame`/`throwx`: dokumen asli hanya menulis "start frame", "end frame", "throwx" di tabel struct, tanpa templat tag.

`start_frame` ada di `header` (dari `<bmp_begin>`), bukan di `stats`: `record.data.header.start_frame` (readme `new in bmp part.txt`; prioritas di atas tag mode background).
`stats.caughtact` adalah nama field exe untuk hal yang di readme disebut `caught` (frame tujuan bila MP/HP tidak cukup); parser meneruskan kedua nama.

## Catatan R2 (revisi)
- `hit_aj/jj/aa` tetap terpisah di `hit_ext.aj/jj/aa` (keputusan AI2: pemilihan menurut `dicontrol` di sisi skrip).
- `strengths[i]`: `catching_actions` dan `caught_actions` tetap `{0, 0}` (strength list 2.0a tidak membawanya; tidak berubah). `caughtact` di strengths adalah kunci baru berisi SATU angka (`strengths[i].caughtact`). `pickingact`/`pickedact` hanya dibaca di itr, bukan di strengths.
- Offset skin: `skins[i].offset` dipakai langsung sebagai `pic_offset` di `object_data.picture(data, frame, offset)` (menghitung `frame.picture + offset`). Dari data contoh, offset sama dengan `first_picture` sheet pertama skin itu (dennis: 210; woody: 210, 420, 630, 840). **[BELUM PASTI]** sampai diuji di game.
- Suara bawaan senjata: `record.data.weapon.hit_sound`, `.drop_sound`, `.broken_sound` (teks, nil bila tag tidak ada); salinan di `record.data.header.weapon_hit_sound` dkk. `sound_list[i]` adalah penggantinya per bg dan mode.
