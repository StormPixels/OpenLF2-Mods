# AI 5 — data global, suara/musik, kunci buka, area background (R1)

Sumber virtual: `game/dat_text/<jalur>` (teks terdekripsi, maks 1 MB, tanpa peka huruf besar-kecil) dan `game/mode_file/<k>` (k=1..4; kosong bila tidak ada).
Modul Lua: `sd_text` (pemindai), `system_data` (I4), `unlock` (I5), `music` (bgm.dat), `sounds` (sound.dat), `sd_global` (kind/fusion/dmg), `bg_modes`/`background` (area mode).

## Keputusan [BELUM PASTI]
- Format `saves.txt` tidak terdokumentasi (berkas bawaan kosong): dibaca sebagai semua bilangan bulat 10..1000. Ganti `unlock.parse_saves` bila format asli berbeda.
- `hidden` 5..9 dan >1000: terkunci. `hidden` <= 0: selalu boleh.
- `mode:`/`respond:` trek bgm: himpunan angka opak; `music.selectable(mode, respond)`, argumen nil = tanpa penyaring.
- `hex:` bgm disimpan sebagai teks dan angka heksadesimal bila polos.
- `kind.dat`: daftar `bound` dan `respond` dikembalikan dengan nama tag aslinya, arti pemicu/terdampak tidak ditebak.
- `attacking` diasumsikan persen (`bg_modes.damage_percent`, bawaan 100).
- `width: -1` = `constants.screen.width` (794); layout lebar mungkin ingin lebar jendela sebenarnya.
- Penulisan `saves.txt` belum bisa: tidak ada API tulis berkas di Lua. `unlock.on_change(text)` disiapkan.
