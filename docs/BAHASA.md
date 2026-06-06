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
- Teks mendukung escape: `\"` (kutip), `\\` (backslash), `\n` (baris baru), `\t` (tab), `\r`, `\0` (null byte).

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

## Modul & Paket [JALAN]

Pasang modul dari GitHub dengan `tenun add`:

```
tenun add mysql          # clone github.com/TenunLang/modul-mysql ke ./tenun_modul/mysql
tenun add https://github.com/akun/repo   # atau URL repo apa pun
```

Ada dua bentuk `impor` (satu per baris):

```tenun
impor "mysql";              // modul terpasang (dari tenun_modul/)
impor "./lib/util.tenun";   // berkas lokal (relatif berkas saat ini)
```

- **Modul**: nama polos (mis. `"mysql"`) → dimuat dari `tenun_modul/<nama>` (entry ditentukan `berkas` di `tenun.json` modul).
- **Berkas lokal**: diawali `./` atau `../`, mengandung `/`, atau berakhiran `.tenun` → dimuat relatif terhadap berkas yang mengimpor (ekstensi `.tenun` otomatis bila tidak ditulis).

Impor bersifat **rekursif** (berkas yang diimpor boleh mengimpor lagi) dan aman dari duplikasi/siklus. Fungsi top-level dari semua berkas digabung sehingga dapat dipanggil langsung. Inilah cara membagi program menjadi banyak berkas, mirip Node.js. Modul ditulis dalam bahasa Tenun biasa, memanfaatkan builtin inti (TCP, kripto, encode biner, dll).

`tenun add` juga mencatat dependensi di `tenun.json` proyek (dibuat otomatis bila belum ada):

```json
{
  "nama": "proyek-tenun",
  "versi": "0.1.0",
  "butuh": {
    "mysql": "^0.1.0"
  }
}
```

Setiap modul adalah repo sendiri: `TenunLang/modul-<nama>`, berisi `<nama>.tenun` (sumber) dan `tenun.json` (manifest: nama, versi, deskripsi, lisensi, berkas, kataKunci, butuh).

Catatan: saat ini `impor` menggabungkan fungsi modul ke ruang nama global (panggil langsung namanya). Bentuk bernamespace `tetap m = modul("mysql")` lalu `m.sambung(...)` direncanakan (perlu fungsi sebagai nilai / akses anggota).

## Larik (array) [JALAN]

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

## Peta (map) [JALAN]

Peta adalah kumpulan pasangan kunci-nilai berbasis teks (`teks` -> `teks`). Tipe ditulis `peta`. Literal memakai awalan `peta` diikuti kurung kurawal.

```tenun
biar u: peta = peta{ "nama": "taqin", "peran": "admin" };
cetak(u["nama"]);         // baca nilai: taqin
u["peran"] = "pengguna";  // ubah/tambah nilai
u["email"] = "a@x.id";    // kunci baru
cetak(u["telepon"]);      // kunci tidak ada -> "" (teks kosong)

cetak(petaPunya(u, "email"));   // benar
petaHapus(u, "email");
biar kunci: []teks = petaKunci(u);   // semua kunci sebagai []teks
```

- Kunci `teks`. **Nilai bisa tipe apa pun** (teks, bulat, bool, larik, bahkan `peta` lain — bisa bersarang). Hasil baca bertipe `dinamis` (cocok dengan tipe apa pun).
- Membaca kunci yang tidak ada mengembalikan `""` (teks kosong).
- Peta kosong: `peta{}`. Tambah/ubah nilai dengan `m["k"] = nilai;`.
- Cocok untuk objek JSON (termasuk bersarang), baris hasil DB, dan definisi model ORM.

```tenun
biar u: peta = peta{ "nama": "Taqin", "umur": 30, "aktif": benar };
biar data: peta = peta{ "tags": ["web", "tenun"], "alamat": peta{ "kota": "Solo" } };
biar tags: []teks = data["tags"];        // nilai larik
biar al: peta = data["alamat"];          // peta bersarang
cetak(al["kota"]);                        // Solo
```
- Builtin: `petaPunya(m, k): bool`, `petaKunci(m): []teks`, `petaHapus(m, k): kosong`.
- Belum didukung pada `tenun build` (native) — pakai `tenun run`.

## Fungsi sebagai nilai (first-class) [JALAN]

Nama fungsi top-level bisa disimpan ke variabel, dioper sebagai argumen, dan dipanggil tak langsung. Tipenya `fungsi`.

```tenun
fungsi tambah(a: bulat, b: bulat): bulat { kembali a + b; }
fungsi kali(a: bulat, b: bulat): bulat { kembali a * b; }

biar op: fungsi = tambah;
cetak(op(3, 4));               // 7
op = kali;
cetak(op(3, 4));               // 12

// higher-order: fungsi menerima fungsi
fungsi terapkan(f: fungsi, x: bulat, y: bulat): dinamis { kembali f(x, y); }
cetak(terapkan(tambah, 10, 5));   // 15

// larik fungsi + registrasi dinamis
biar ops: []fungsi = [tambah, kali];
ops = dorong(ops, tambah);
cetak(ops[1](6, 7));           // 42
```

- Hasil panggilan tak langsung bertipe `dinamis` (kompatibel dengan tipe apa pun).
- `dorong(larik, item)` bekerja untuk larik tipe apa pun, termasuk `[]fungsi`.
- Nilai fungsi belum didukung pada `tenun build` (native) — pakai `tenun run`.
- Semua elemen literal harus bertipe sama; tipe elemen disimpulkan dari elemen pertama.
- Larik bisa bersarang: `[][]bulat`.

Map dan struct belum tersedia `[RENCANA]`.

## 5. Operator [JALAN]

| Kategori | Operator |
|---|---|
| Aritmatika | `+` `-` `*` `/` `%` |
| Perbandingan | `==` `!=` `<` `>` `<=` `>=` |
| Logika | `&&` `\|\|` `!` |
| Bitwise (bulat) | `&` `\|` `^` `<<` `>>` |
| Penugasan | `=` `+=` `-=` `*=` `/=` `%=` |

Urutan precedence dari paling longgar ke paling erat: `=` `+=` ... lalu `||` lalu `&&` lalu `|` lalu `^` lalu `&` lalu `== !=` lalu `< > <= >=` lalu `<< >>` lalu `+ -` lalu `* / %` lalu unary `! -` lalu pemanggilan/grup. Detail lengkap di `GRAMMAR.md`.

- Bitwise (`& | ^ << >>`) hanya untuk `bulat`.
- Penugasan majemuk: `x += e` setara `x = x + e` (juga `-= *= /= %=`). Increment/decrement: `x++` / `x--`.
- Literal angka: desimal `42`, heksadesimal `0xFF`, biner `0b1010`.
- Komentar: baris `// ...` dan blok `/* ... */`.

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

Iterasi elemen larik (for-each) `[JALAN]`:

```tenun
biar buah: []teks = ["apel", "mangga", "jeruk"];
untuk b dari buah {
    cetak(b);
}
```

`untuk <nama> dari <larik>` (tanpa `sampai`) mengulang tiap elemen; `nama` bertipe sama dengan elemen larik. Bedakan dengan bentuk rentang `untuk i dari A sampai B`.

### cocok (pencocokan nilai / switch) `[JALAN]`

```tenun
cocok n {
    1 { cetak("satu"); }
    2 { cetak("dua"); }
    lain { cetak("lainnya"); }
}
```

Mencocokkan subjek dengan tiap nilai arm (perbandingan `==`); arm pertama yang cocok dijalankan lalu berhenti (tanpa fall-through). `lain` = default (opsional). Subjek & nilai arm harus bertipe sama.

### coba & tangkap (error handling) `[JALAN]`

Tangkap galat runtime (pembagian nol, indeks di luar batas, gagal builtin/koneksi, dll) supaya program tidak berhenti:

```tenun
coba {
    biar x: bulat = 10 / 0;
} tangkap (e) {
    cetak("galat: " + e);    // e: teks berisi pesan galat
}
cetak("tetap jalan");
```

- `e` bertipe `teks` (pesan galat), hanya hidup di blok `tangkap`.
- Galat dari fungsi yang dipanggil di dalam `coba` ikut tertangkap (unwind lintas pemanggilan). Bisa bersarang.
- Berguna untuk server agar satu request gagal tidak mematikan proses.

### henti & lanjut (break / continue) `[JALAN]`

Di dalam `selama` atau `untuk`:

- `henti;` — keluar dari loop (break).
- `lanjut;` — lompat ke iterasi berikutnya (continue).

```tenun
biar total: bulat = 0;
untuk i dari 0 sampai 10 {
    kalau i % 2 == 0 { lanjut; }   // lewati genap
    kalau i > 7 { henti; }         // berhenti setelah lewat 7
    total = total + i;
}
```

`henti`/`lanjut` hanya boleh di dalam loop (di luar loop = error kompilasi).

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
| `cetak(x)` | menampilkan nilai ke output (diakhiri baris baru) | `[JALAN]` |
| `panjang(larik): bulat` | jumlah elemen larik | `[JALAN]` |
| `petaPunya(m: peta, k: teks): bool` | apakah kunci ada di peta | `[JALAN]` |
| `petaKunci(m: peta): []teks` | semua kunci peta | `[JALAN]` |
| `petaHapus(m: peta, k: teks): kosong` | hapus kunci dari peta | `[JALAN]` |
| `httpKirim(metode, url, header, body: teks): teks` | HTTP request (TLS auto utk https) | `[JALAN]` |
| `sambungAman(inang: teks, port: bulat): bulat` | sambung soket TLS, kembalikan handle | `[JALAN]` |
| `kirimAman(soket: bulat, data: teks): kosong` | kirim lewat soket TLS | `[JALAN]` |
| `terimaAman(soket: bulat, n: bulat): teks` | terima dari soket TLS | `[JALAN]` |
| `tutupAman(soket: bulat): kosong` | tutup soket TLS | `[JALAN]` |
| `panjangTeks(teks): bulat` | panjang teks (jumlah byte) | `[JALAN]` |
| `potong(teks, mulai: bulat, jumlah: bulat): teks` | substring | `[JALAN]` |
| `akar(desimal): desimal` | akar kuadrat | `[JALAN]` |
| `pangkat(desimal, desimal): desimal` | perpangkatan | `[JALAN]` |
| `mutlak(desimal): desimal` | nilai mutlak | `[JALAN]` |
| `bulatkan(desimal): bulat` | pembulatan ke `bulat` | `[JALAN]` |
| `bacaFile(path: teks): teks` | baca isi file | `[JALAN]` |
| `tulisFile(path: teks, isi: teks): kosong` | tulis isi ke file | `[JALAN]` |
| `ambil(url: teks): teks` | HTTP/HTTPS GET (TLS otomatis) | `[JALAN]` |
| `layani(port: bulat): kosong` | jalankan HTTP server | `[JALAN]` |
| `statusKan(kode: bulat): kosong` | set kode status respons (dalam `tangani`) | `[JALAN]` |
| `headerKan(nama: teks, nilai: teks): kosong` | tambah header respons (dalam `tangani`) | `[JALAN]` |
| `cari(teks, sub: teks): bulat` | indeks kemunculan pertama `sub`, atau -1 | `[JALAN]` |
| `ganti(teks, dari: teks, ke: teks): teks` | ganti semua kemunculan | `[JALAN]` |
| `pisah(teks, pemisah: teks): []teks` | pecah teks jadi larik | `[JALAN]` |
| `gabung(bagian: []teks, pemisah: teks): teks` | gabung larik teks | `[JALAN]` |
| `mulaiDengan(teks, awalan: teks): bool` | cek prefix | `[JALAN]` |
| `akhiriDengan(teks, akhiran: teks): bool` | cek suffix | `[JALAN]` |
| `tipeKonten(namaBerkas: teks): teks` | MIME type dari ekstensi | `[JALAN]` |
| `adaFile(path: teks): bool` | cek file ada | `[JALAN]` |
| `kueri(url: teks, kunci: teks): teks` | ambil parameter query (`?k=v`), URL-decoded | `[JALAN]` |
| `form(badan: teks, kunci: teks): teks` | ambil field form urlencoded, URL-decoded | `[JALAN]` |
| `headerMasuk(nama: teks): teks` | baca header permintaan (dalam `tangani`) | `[JALAN]` |
| `cookie(nama: teks): teks` | baca cookie permintaan (dalam `tangani`) | `[JALAN]` |
| `simpan(kunci: teks, nilai: teks): kosong` | simpan data persisten (key-value) | `[JALAN]` |
| `muat(kunci: teks): teks` | baca data persisten | `[JALAN]` |
| `hapus(kunci: teks): kosong` | hapus data persisten | `[JALAN]` |
| `sambung(host: teks, port: bulat): bulat` | buka koneksi TCP, kembalikan handel | `[JALAN]` |
| `kirim(soket: bulat, data: teks): kosong` | kirim byte ke koneksi | `[JALAN]` |
| `terima(soket: bulat, maks: bulat): teks` | baca sampai `maks` byte dari koneksi | `[JALAN]` |
| `tutup(soket: bulat): kosong` | tutup koneksi | `[JALAN]` |
| `sha256(data: teks): teks` | hash SHA-256 (hex) | `[JALAN]` |
| `sha1(data: teks): teks` | hash SHA-1 (hex) | `[JALAN]` |
| `md5(data: teks): teks` | hash MD5 (hex) | `[JALAN]` |
| `hmacSha256(kunci: teks, data: teks): teks` | HMAC-SHA-256 (hex) | `[JALAN]` |
| `base64(data: teks): teks` | encode base64 | `[JALAN]` |
| `dariBase64(teks): teks` | decode base64 | `[JALAN]` |
| `acak(jumlah: bulat): teks` | byte acak aman (hex, 2×jumlah char) | `[JALAN]` |
| `sha1Raw(data: teks): teks` | SHA-1 byte mentah (20 byte, untuk protokol) | `[JALAN]` |
| `xor(a: teks, b: teks): teks` | XOR byte-per-byte | `[JALAN]` |
| `terimaPasti(soket: bulat, n: bulat): teks` | baca persis `n` byte dari koneksi | `[JALAN]` |
| `keBulat(teks): bulat` | ubah teks ke bilangan | `[JALAN]` |
| `keTeks(bulat): teks` | ubah bilangan ke teks | `[JALAN]` |
| `keByte(nilai: bulat, lebar: bulat, besar: bool): teks` | encode integer ke `lebar` byte (besar=big-endian) | `[JALAN]` |
| `bacaInt(data: teks, offset: bulat, lebar: bulat, besar: bool): bulat` | baca integer dari byte | `[JALAN]` |
| `jsonTeks(json: teks, kunci: teks): teks` | ambil field teks dari JSON (top-level) | `[JALAN]` |
| `jsonAngka(json: teks, kunci: teks): bulat` | ambil field angka dari JSON | `[JALAN]` |
| `jsonBool(json: teks, kunci: teks): bool` | ambil field bool dari JSON | `[JALAN]` |

Penyimpanan persisten `simpan`/`muat`/`hapus` adalah key-value sederhana yang ditulis ke berkas `tenun_data.json` (aman antar-thread). Cocok untuk sesi/konfigurasi/data ringan; untuk skala besar, DB sungguhan akan menyusul.

Konektor jaringan `sambung`/`kirim`/`terima`/`tutup` adalah primitif TCP mentah — fondasi untuk membangun klien protokol apa pun (Postgres, Redis, MySQL, SMTP) sebagai modul Tenun. `sambung` melakukan resolusi DNS dan koneksi, mengembalikan handel; `terima` membaca byte mentah (boleh biner). Contoh HTTP GET manual:

```tenun
biar s: bulat = sambung("example.com", 80);
kirim(s, "GET / HTTP/1.0\r\nHost: example.com\r\n\r\n");
cetak(terima(s, 4096));
tutup(s);
```

### Kripto

`sha256`/`sha1`/`md5` mengembalikan hash heksadesimal; `hmacSha256` untuk tanda tangan/SCRAM; `base64`/`dariBase64` untuk encoding; `acak(n)` menghasilkan `n` byte acak aman (CSPRNG) sebagai hex — cocok untuk token sesi / nonce. Berguna untuk hashing password, token, dan membangun autentikasi klien DB.

```tenun
biar token: teks = acak(32);                 // 64 char hex
biar hash: teks = sha256("password123");
biar tanda: teks = hmacSha256(rahasia, data);
```

Builtin yang membutuhkan runtime (jaringan, file, server) tersedia lewat `tenun run` (VM atau `--interp`). Pada `tenun build` (native), builtin ini belum didukung — kompilasi matematika/teks/larik murni saja yang bisa native.

### Jaringan: `ambil`

```tenun
biar isi: teks = ambil("https://example.com");
cetak(isi);
```

`ambil` melakukan HTTP GET dan mengembalikan body. URL `https://` ditangani dengan TLS otomatis (sertifikat sistem).

### Server HTTP: `layani`

`tenun run` bisa langsung menjadi web server, mirip Node.js — tanpa kompilasi. Definisikan fungsi `tangani(metode: teks, jalur: teks, badan: teks): teks` (dipanggil tiap permintaan), lalu panggil `layani(port)`. Handler menerima method HTTP, jalur (path), dan body permintaan; mengembalikan teks sebagai body respons. Status dan header diatur dengan `statusKan`/`headerKan`.

```tenun
fungsi tangani(metode: teks, jalur: teks, badan: teks): teks {
    kalau jalur == "/" {
        headerKan("Content-Type", "text/html; charset=utf-8");
        kembali "<h1>Halo dari Tenun</h1>";
    }
    kalau jalur == "/api" {
        headerKan("Content-Type", "application/json");
        kembali "{\"pesan\":\"halo\",\"metode\":\"" + metode + "\"}";
    }
    kalau metode == "POST" {
        kembali "Kamu kirim: " + badan;
    }
    statusKan(404);
    kembali "404 - tidak ditemukan: " + jalur;
}

layani(8080);
```

```
$ tenun run server.tenun
[tenun] server berjalan di http://localhost:8080
```

`layani` memblokir (melayani permintaan terus-menerus). Status respons default 200; `statusKan`/`headerKan` berlaku untuk permintaan yang sedang ditangani dan direset tiap permintaan baru.

Server bersifat **multi-threaded**: otomatis menjalankan satu worker per inti CPU sehingga permintaan ditangani secara paralel. Tiap worker punya konteks eksekusi sendiri (stack terpisah) dan salinan variabel global saat startup. Catatan: hindari memodifikasi variabel global di dalam `tangani` untuk menyimpan state antar-permintaan — tiap worker memegang salinannya sendiri, jadi perubahan tidak terbagi dan tidak persisten. State bersama yang persisten sebaiknya lewat file/DB (akan ada builtin-nya).

### Contoh: menyajikan file statis

```tenun
fungsi tangani(metode: teks, jalur: teks, badan: teks): teks {
    biar berkas: teks = "publik" + jalur;
    kalau jalur == "/" {
        berkas = "publik/index.html";
        headerKan("Content-Type", "text/html; charset=utf-8");
    } lain {
        headerKan("Content-Type", tipeKonten(jalur));
    }
    kembali bacaFile(berkas);
}
layani(8080);
```

Gabungkan `pisah`/`cari`/`mulaiDengan` untuk routing dan mem-parsing query/form, `bacaFile` + `tipeKonten` + `adaFile` untuk file statis (dengan 404).

### Contoh: REST API JSON

```tenun
fungsi tangani(metode: teks, jalur: teks, badan: teks): teks {
    kalau jalur == "/api" {
        headerKan("Content-Type", "application/json");
        biar nama: teks = jsonTeks(badan, "nama");
        kembali "{\"halo\":\"" + nama + "\"}";
    }
    statusKan(404);
    kembali "tidak ditemukan";
}
layani(8080);
```

`jsonTeks`/`jsonAngka`/`jsonBool` membaca field top-level dari teks JSON (mis. body permintaan). Untuk membangun JSON, susun teks dengan `+` (escape `\"` didukung). Parser JSON penuh (objek/larik bersarang) menyusul.

### Header & cookie permintaan

Di dalam `tangani`, baca header masuk dengan `headerMasuk(nama)` dan cookie dengan `cookie(nama)`. Set cookie/header respons dengan `headerKan`:

```tenun
fungsi tangani(metode: teks, jalur: teks, badan: teks): teks {
    biar token: teks = headerMasuk("Authorization");
    biar sesi: teks = cookie("sesi");
    kalau sesi == "" {
        headerKan("Set-Cookie", "sesi=abc123; Path=/; HttpOnly");
    }
    kembali "token=" + token;
}
```

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
