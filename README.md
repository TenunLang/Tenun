# Tenun

Tenun adalah bahasa pemrograman dengan kata kunci Bahasa Indonesia, dibangun agar mudah dipahami pemula namun tetap kencang. Compiler-nya ditulis dengan Zig. Nama "Tenun" berasal dari kata tenun: kode dijalin menjadi satu.

```tenun
fungsi salam(nama: teks): kosong {
    cetak("Halo, " + nama);
}

biar angka: bulat = 10;

kalau angka > 5 {
    salam("Tenun");
} lain {
    cetak("kecil");
}

untuk i dari 1 sampai 4 {
    cetak(i);
}
```

## Sorotan

- Kata kunci Bahasa Indonesia: `biar`, `tetap`, `fungsi`, `kembali`, `kalau`, `lain`, `selama`, `untuk`, dan lainnya.
- Bertipe statis: kesalahan tipe terdeteksi saat kompilasi.
- Tiga backend eksekusi:
  - Bytecode VM (default, cepat)
  - Tree-walking interpreter (untuk diagnosa)
  - Kompilasi native ke executable (tercepat)

## Instalasi

Linux / macOS:

```
curl -fsSL https://raw.githubusercontent.com/TenunLang/Tenun/main/install.sh | bash
```

Windows (PowerShell):

```
irm https://raw.githubusercontent.com/TenunLang/Tenun/main/install.ps1 | iex
```

Skrip mengunduh binari rilis terbaru ke `~/.tenun/bin` dan menambahkannya ke PATH. Tersedia juga installer di halaman [Releases](https://github.com/TenunLang/Tenun/releases): `.deb` (Linux), `.msi` (Windows), dan binari mentah Linux/macOS/Windows.

## Membangun compiler (dari sumber)

Membutuhkan Zig 0.14.0.

```
zig build              # bangun compiler ke zig-out/bin/tenun
zig build test         # jalankan seluruh unit test
zig build -Doptimize=ReleaseFast   # build teroptimasi
```

## Penggunaan

```
tenun version                 menampilkan versi
tenun run <file>              menjalankan program (bytecode VM, default)
tenun run <file> --interp     menjalankan via tree-walking interpreter
tenun build <file>            kompilasi ke executable native (<file>.exe)
tenun build <file> --emit-c   simpan juga sumber C perantara
```

Contoh:

```
$ tenun run examples/hello.tenun
Halo, Tenun

$ tenun build examples/faktorial.tenun
[tenun] build sukses: examples/faktorial.exe
$ ./examples/faktorial.exe
120
```

## Performa

`tenun build` mentranspilasi program ke C lalu mengompilasinya dengan `zig cc -O2`, menghasilkan executable native. Perbandingan pada loop 50 juta iterasi (ReleaseFast):

| Backend | Waktu |
|---|---|
| Native (`tenun build`) | ~0.01 s |
| Bytecode VM (`tenun run`) | ~1.1 s |
| Interpreter (`--interp`) | ~2.7 s |

## Dokumentasi

- [docs/BAHASA.md](docs/BAHASA.md) — referensi bahasa
- [docs/GRAMMAR.md](docs/GRAMMAR.md) — grammar formal (EBNF)
- [docs/ROADMAP.md](docs/ROADMAP.md) — rencana pengembangan
- [CHANGELOG.md](CHANGELOG.md) — riwayat perubahan

## Struktur

```
src/
  main.zig          entry point CLI
  driver.zig        orkestrasi pipeline
  lexer/            sumber -> token
  parser/           token -> AST
  sema/             resolusi nama + pengecekan tipe
  interp/           tree-walking interpreter
  vm/               bytecode + virtual machine
  codegen/          transpiler ke C (native)
  diagnostics/      pelaporan kesalahan
examples/           contoh program .tenun
docs/               dokumentasi
```

## Status

Inti bahasa lengkap: variabel/konstanta, tipe dasar (`bulat`, `desimal`, `teks`, `bool`, `kosong`) dan larik `[]T`, operator dengan precedence, percabangan, perulangan (`selama`, `untuk`), fungsi dengan rekursi, dan builtin `cetak`/`panjang`. Tahap berikutnya: pustaka standar, tipe komposit lanjutan, dan perkakas (REPL, formatter).

## Lisensi

Belum ditentukan.
