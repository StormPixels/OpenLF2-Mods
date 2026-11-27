# Pilih karakter: gerak atas/bawah di grid

Berkas diubah: `scripts/base/ui/character_select.lua`

- Di menu yang punya grid roster (`<grid_char>`, layout lebar seperti mode4/mode2), tombol atas/bawah
  menggeser pilihan satu baris (21 kolom per baris), kolom tetap. Berlaku untuk pemain (menu 1)
  dan pemilihan karakter komputer (menu 2).
- Lewat baris pertama/terakhir: berputar. Baris terakhir yang pendek: ke sel terakhir.
- Mode `bound: 0` (tanpa karakter kembar): karakter yang sudah dipakai slot lain dilewati.
- Random = sel pertama grid (kiri atas). Di grid, "atas" tidak lagi langsung ke Random.
- Menu tanpa grid (layout klasik, mode3/10 pemain): perilaku lama (atas = Random, bawah = tidak ada).
- Kisi transformasi (`<phase>`) tidak diubah.

Status: kode belum dijalankan (tidak ada Lua/LuaJIT di lingkungan ini). Perlu uji di ponsel.
