# Referensi Bahasa Tenun

Dokumen ini adalah referensi lengkap bahasa Tenun untuk pengguna. **Wajib diperbarui setiap ada penambahan atau perubahan fitur bahasa** (keyword baru, tipe baru, operator, builtin, aturan semantik). Lihat juga `GRAMMAR.md` (grammar formal) dan `../CHANGELOG.md` (riwayat perubahan).

Penanda status: `[JALAN]` sudah berfungsi - `[BANGUN]` sedang dikerjakan - `[RENCANA]` direncanakan.

---

## 1. Gambaran Umum

Tenun adalah bahasa pemrograman general-purpose dengan kata kunci Bahasa Indonesia. Bahasa ini bertipe statis (static typing) - kesalahan tipe terdeteksi saat kompilasi. Engine compiler ditulis dengan Zig.

Contoh program:

```tenun
fungsi salam(nama: teks): kosong {
    cetak("Halo, " + nama);
}

biar angka: bulat = 10;
tetap pi = 3.14;

kalau angka > 5 && pi < 4.0 {
    salam("Tenun");
} lain {
    cetak("kecil");
}

selama angka > 0 {
    angka = angka - 1;
}
```

## 2. Sintaks Dasar

- Setiap pernyataan (statement) diakhiri titik koma `;`.
- Blok kode dibungkus kurung kurawal `{ }`. Blok tidak diakhiri titik koma.
- Komentar satu baris diawali `//` sampai akhir baris.
- File sumber berekstensi `.tenun`.

## 3. Variabel & Konstanta [JALAN]

| Kata kunci | Arti | Bisa diubah? |
|---|---|---|
| `biar` | deklarasi variabel | ya |
| `tetap` | deklarasi konstanta | tidak |

```tenun
biar umur: bulat = 17;   // tipe ditulis eksplisit
biar nama = "Tenun";     // tipe disimpulkan otomatis (teks)
tetap pi = 3.14;         // konstanta, tidak boleh di-assign ulang
umur = 18;               // boleh, karena 'biar'
```

Aturan:
- Variabel wajib dideklarasikan sebelum dipakai.
- Tidak boleh mendeklarasikan ulang nama yang sama dalam satu scope.
- `tetap` tidak boleh di-assign ulang setelah inisialisasi.

## 4. Tipe Data [JALAN]

| Tipe | Keterangan | Contoh nilai |
|---|---|---|
| `bulat` | bilangan bulat 64-bit | `10`, `-3` |
| `desimal` | bilangan pecahan 64-bit | `3.14` |
| `teks` | rangkaian karakter (UTF-8) | `"halo"` |
| `bool` | nilai logika | `benar`, `salah` |
| `kosong` | ketiadaan nilai | `kosong` |

### Larik (array) [JALAN]

Larik adalah deretan nilai bertipe sama. Tipe ditulis `[]T` (mis. `[]bulat`). Literal ditulis dengan kurung siku.

```tenun
biar angka: []bulat = [5, 10, 15, 20];
cetak(angka[0]);          // akses elemen (indeks mulai 0): 5
cetak(panjang(angka));    // jumlah elemen: 4
angka[1] = 99;            // ubah elemen
cetak(angka);             // [5, 99, 15, 20]
```

- Indeks dimulai dari 0 dan harus bertipe `bulat`.
- Elemen dapat diubah dengan `larik[indeks] = nilai;` (tipe nilai harus sama dengan tipe elemen).
- Akses atau penugasan di luar batas menimbulkan kesalahan runtime.
- Semua elemen literal harus bertipe sama; tipe elemen disimpulkan dari elemen pertama.
- Larik bisa bersarang: `[][]bulat`.

Map dan struct belum tersedia `[RENCANA]`.

## 5. Operator [JALAN]

| Kategori | Operator |
|---|---|
| Aritmatika | `+` `-` `*` `/` `%` |
| Perbandingan | `==` `!=` `<` `>` `<=` `>=` |
| Logika | `&&` `\|\|` `!` |
| Penugasan | `=` |

Urutan precedence dari paling longgar ke paling erat: `=` lalu `||` lalu `&&` lalu `== !=` lalu `< > <= >=` lalu `+ -` lalu `* / %` lalu unary `! -` lalu pemanggilan/grup. Detail lengkap di `GRAMMAR.md`.

## 6. Kontrol Alur [JALAN]

Percabangan:

```tenun
kalau nilai > 90 {
    cetak("A");
} lain kalau nilai > 80 {
    cetak("B");
} lain {
    cetak("C");
}
```

Perulangan kondisi:

```tenun
selama angka > 0 {
    angka = angka - 1;
}
```

Perulangan iterasi rentang `[JALAN]`:

```tenun
untuk i dari 1 sampai 5 {
    cetak(i);
}
```

`untuk <nama> dari <awal> sampai <akhir>` mengulang dengan `nama` bernilai `awal`, `awal+1`, ... sampai `akhir - 1` (batas akhir **eksklusif**, langkah +1). Contoh di atas mencetak 1, 2, 3, 4. `awal` dan `akhir` harus bertipe `bulat`. Variabel iterasi bertipe `bulat` dan hanya hidup di dalam blok.

## 7. Fungsi [JALAN]

Fungsi mendukung rekursi.


```tenun
fungsi tambah(a: bulat, b: bulat): bulat {
    kembali a + b;
}
```

- Setiap parameter wajib beranotasi tipe.
- Tipe kembalian ditulis setelah `:` pada signature.
- Fungsi yang tidak mengembalikan nilai memakai tipe kembalian `kosong`.
- Fungsi tingkat atas (top-level) boleh dipanggil sebelum definisinya.

## 8. Builtin

| Nama | Arti | Status |
|---|---|---|
| `cetak` | menampilkan nilai ke output (diakhiri baris baru) | `[JALAN]` |
| `panjang` | jumlah elemen sebuah larik (mengembalikan `bulat`) | `[JALAN]` |

`cetak` bukan kata kunci, melainkan fungsi builtin biasa, sehingga dapat diperlakukan seperti fungsi lain.

## 9. Status Pipeline Compiler

| Fase | Komponen | Status |
|---|---|---|
| 0 | Fondasi + CLI (`version`/`run`/`build`) | `[JALAN]` |
| 1a | Lexer (sumber ke token) | `[JALAN]` |
| 1b | Parser (token ke AST) | `[JALAN]` |
| 2 | Analisis semantik (resolusi nama + tipe) | `[JALAN]` |
| 3 | Interpreter tree-walking (eksekusi) | `[JALAN]` |
| 4 | Bytecode VM (eksekusi cepat, default) | `[JALAN]` |
| 5 | Codegen native (transpile ke C) | `[JALAN]` |

`tenun run <file>` menjalankan program secara penuh: lexing, parsing, pengecekan tipe, kompilasi ke bytecode, lalu eksekusi oleh virtual machine. Kesalahan pada fase mana pun dilaporkan dengan posisi baris dan kolom.

Backend eksekusi:
- Default: **bytecode VM** (sekitar 2x lebih kencang dari tree-walking).
- `tenun run <file> --interp` memakai tree-walking interpreter (untuk perbandingan/diagnosa).

Kompilasi native (`tenun build`):
- `tenun build <file>` menghasilkan executable native (`<file>.exe`). Ini jalur tercepat.
- Secara internal Tenun mentranspilasi program ke C lalu mengompilasinya dengan `zig cc -O2`. File C perantara dihapus otomatis; pakai `--emit-c` kalau ingin menyimpannya untuk inspeksi.
- Didukung: bulat, desimal, teks, bool, larik (termasuk bersarang), fungsi, kontrol alur, `cetak`, `panjang`. (Cetak larik bersarang belum didukung di native — pakai `tenun run`.)

Contoh:

```
$ tenun run examples/hello.tenun
Halo, Tenun

$ tenun build examples/faktorial.tenun
[tenun] build sukses: examples/faktorial.exe
$ ./examples/faktorial.exe
120
```

Perbandingan kecepatan (loop 50 juta, ReleaseFast): native ~0.01s, VM ~1.1s, interpreter ~2.7s.
