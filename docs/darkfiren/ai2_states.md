# AI 2 putaran 1 — input, gerak frame, dan state alur

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

1. **Lama `hold_*`**: DOCX hanya menulis "sekitar 2 detik". Dipakai 60 tick (30 tick/detik). Hitungan mulai ulang saat tombol dilepas atau frame berganti. Komputer tidak pernah memakai `hold_*`.
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
16. **4xxx**: cadangan nyawa = xxx saat frame dimasuki, hanya karakter. **17xxx**: HP + xxx (0 berarti 100), tidak melewati HP maks [BELUM PASTI: batas]; titik temu dengan `gain` (AI 3) hanya lewat angka mentah 17xxx.
17. **404**: tahan di frame sampai ronde habis (`round_counter` > 0). **405**: pindah ke tengah peta, x dan z (z dari `zboundary`) [BELUM PASTI: hanya x atau x dan z].

## Belum dikerjakan (putaran berikutnya)

- `1xxxyyy` / `2xxxyyy` (cabang menurut HP/MP) — arah cabang MP bertentangan antar catatan; belum ditentukan.
- P2: time stop `3xxyzzz` + `frame_rules.frozen` (I2), charge `6XXX`, transformasi `8XXXX` (bentrok dengan rentang `8000-8999` yang sudah ada di `frame_rules`), kamera `99XXX`, gempa `5XXYY`, nilai baru `hit_Fa`.
- P3: state `7XXX`, `9xxx`, `9XX/9XXYY/7XX/7XXYY`.
- `hit_Fj/Uj/Dj/ja/Ua/Da` untuk objek t3 (bagian 2, state 3000/3006): milik AI 3.
