# resource.dat: bagaimana game membacanya (AI1, putaran R12)

BASE: base-20261116-1-fe234c5. Sumber: readme `resource dat.txt` dan hasil tes `tests/resource_names`.

## Aturan
- Berkas `data/resource.dat` berisi baris `pic: <jalur gambar>`. Menurut readme, **urutan baris menentukan nama** ("jangan ubah urutan berkas"): baris ke-1 adalah `LF2_CURSOR`, baris ke-2 `MENU_CLIP`, dan seterusnya sampai baris ke-48 `LOADING`. Daftar 48 nama itu sama dengan `resource.dat` bawaan.
- Game memetakan baris ke-n ke nama ke-n. Isi jalurnya bebas: boleh folder lain, nama lain, atau ekstensi lain (.bmp atau .png). Berkas PNG dikenali dari isinya (8 byte tanda PNG), bukan dari nama, jadi gambar bawaan yang dipanggil tanpa ekstensi (pe/menu_clip, pe/menu_back3) tetap dibaca sebagai PNG dan transparansi alpha-nya dipertahankan (BMP tetap memakai hitam murni sebagai warna transparan bila digambar "keyed").
- Baris yang jalurnya tidak dapat dipakai (mis. memakai `..\`) ditolak, tetapi tetap menempati urutannya; baris lain tidak bergeser.
- Baris setelah ke-48 disimpan memakai nama berkasnya (tanpa ekstensi, huruf besar), seperti pada versi OpenLF2 sebelumnya.
- Bila nama tidak ditemukan (berkas lebih pendek dari 48 baris, atau baris tak terpakai), game memakai gambar cadangan dari `lf2_exe/` (hasil `tools/extract_lf2_exe.py`).

## Sebelum perbaikan
Kunci pemetaan adalah nama berkas tanpa ekstensi. Mengganti folder atau nama berkas di `resource.dat` (mis. `custom\my_clip.png` pada baris ke-2) diabaikan: game tetap meminta `MENU_CLIP` dan hanya mencari `lf2_exe/menu_clip.*`. Mengganti ekstensi saja masih berjalan.

## Gambar yang TIDAK ada di resource.dat (jalur masih tertanam di kode)
`MENU_BACK1` sampai `MENU_BACK13` (`sprite/menu/N.bmp`), `MENU_WAIT` (`sprite/loading/menu_wait.bmp`), `BARS` (`sprite/frame/bars.bmp`), `FRAME` (`sprite/frame/default/frame.bmp`), `BACK99_*` dan `SHADOW1` (`bg/sys/lor/`). Dokumen yang AI1 punya tidak menyebut berkas mana yang seharusnya menentukan jalur ini **[PERLU DICEK]**; itu urusan pemilik data global (AI5).

## Tidak diuji
Aplikasi penuh (tidak ada SDL3/NDK di lingkungan kerja). Perilaku diuji pada pembaca (`load_resource_names` dan `bitmap_candidates`) dengan `resource.dat` terenkripsi seperti aslinya.
