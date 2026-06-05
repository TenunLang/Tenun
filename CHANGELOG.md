# Changelog Tenun

Catatan semua perubahan penting + keputusan desain. Format: terbaru di atas.

## 2026-06-05 — Builtin keBulat/keTeks + modul Redis & PostgreSQL (SELESAI)

- Builtin id 46 `keBulat(teks): bulat`, id 47 `keTeks(bulat): teks` (konversi angka↔teks via std.fmt). Total builtin id 0-47.
- **`TenunLang/modul-redis`** — klien Redis (RESP) ditulis dengan Tenun. Parser RESP (simple/error/integer/bulk/array) terverifikasi (uji sintetis).
- **`TenunLang/modul-postgres`** — klien PostgreSQL (protokol v3): startup + auth trust/cleartext/md5, query, parser DataRow. Terverifikasi ke PostgreSQL lokal (auth trust): `SELECT` multi-baris/kolom + `generate_series`. SCRAM-SHA-256 belum (perlu primitif kripto tambahan).
- Tiga modul resmi sekarang: mysql, redis, postgres — semua repo terpisah `TenunLang/modul-<nama>` dengan `tenun.json` + `src/`.

## 2026-06-05 — Impor berkas lokal (multi-berkas) (SELESAI)

`impor` kini mendukung berkas lokal selain modul, dengan resolusi rekursif — bisa membagi program ke banyak berkas (ala Node.js).

- `impor "./x.tenun"` / `"../y"` / `"lib/z.tenun"` → berkas lokal relatif terhadap berkas pengimpor (ekstensi `.tenun` otomatis). `impor "mysql"` → modul dari `tenun_modul/`.
- Loader (`driver.zig`) di-refactor: `expand` rekursif + set `seen` (anti duplikasi/siklus), `resolveImpor`, `modulEntryPath`, `imporLokal`. Resolusi relatif memakai direktori berkas saat ini (`std.fs.path`).
- Modul pun bisa multi-berkas: entry-nya mengimpor berkas lain di folder modul (mis. `modul-mysql/src/mysql.tenun` mengimpor `./lenenc.tenun`).
- Verified: app → `./lib/teks.tenun` → `./matematika.tenun` (bersarang) jalan; modul mysql multi-berkas query MariaDB jalan.
- Workflow: hapus target macOS (hanya Linux + Windows); perbaiki output NSIS (OutFile absolut).

## 2026-06-05 — Manifest proyek `tenun.json` (SELESAI)

- `tenun add <nama>` kini membuat/memperbarui `tenun.json` proyek (ala package.json): menambah `<nama>` ke `butuh` dengan rentang versi `^<versi-modul>` (versi dibaca dari `tenun_modul/<nama>/tenun.json`). (`driver.tambahKeManifest`, std.json, output rapi indent-2)
- Konvensi: tiap modul = repo sendiri `TenunLang/modul-<nama>` dengan `<nama>.tenun` + `tenun.json` (nama, versi, deskripsi, lisensi, berkas, kataKunci, butuh).
- Modul resmi pertama: **`TenunLang/modul-mysql`** (klien MySQL/MariaDB ditulis dengan Tenun). End-to-end terverifikasi: `tenun add mysql` (clone dari GitHub) + `tenun.json` proyek otomatis + `impor "mysql"` + login/`SELECT VERSION()` ke MariaDB lokal.

## 2026-06-05 — Primitif protokol: sha1Raw, xor, escape `\0` (SELESAI)

Melengkapi bahan untuk menulis klien protokol biner (mis. MySQL) sebagai modul Tenun.

- Builtin id 43 `sha1Raw(data)` (SHA-1 byte mentah 20 byte, bukan hex), id 44 `xor(a, b)` (XOR byte-per-byte) di `src/builtins/crypto.zig`.
- Lexer/parser: escape `\0` (null byte) di literal teks.
- **Terbukti:** modul MySQL (`modul-mysql/mysql.tenun`, ditulis murni dengan Tenun) berhasil connect + autentikasi `mysql_native_password` + `SELECT VERSION()` ke MariaDB 11.4.10 lokal. Driver DB pertama di bahasa Tenun, hanya memakai builtin inti (TCP, crypto, encode biner, teks).

## 2026-06-05 — Package manager: `tenun add` + `impor` (SELESAI)

- **`tenun add <nama>`** — `git clone --depth 1` modul dari `github.com/TenunLang/modul-<nama>` ke `./tenun_modul/<nama>`. `tenun add <url>` untuk repo apa pun. (`driver.add`)
- **`impor "<nama>";`** — pernyataan impor (diproses di driver sebelum lexing, berbasis baris): memuat `tenun_modul/<nama>/<nama>.tenun` (atau `tenun_modul/<nama>.tenun`) dan menggabungkan fungsi top-level-nya ke program. Fungsi modul langsung bisa dipanggil (hoisted). (`driver.loadProgram`/`loadModule`)
- Verified: `tenun add https://github.com/octocat/Hello-World` clone OK; modul lokal `impor "sapa"` → `sapa("Tenun")` jalan.
- Keterbatasan: namespace flat (belum `tetap m = modul("mysql")` + `m.sambung()` — perlu fungsi-sebagai-nilai / akses anggota). `impor` harus satu baris `impor "x";`.
- Konvensi modul: repo `TenunLang/modul-<nama>`, berkas `<nama>.tenun` di root.

## 2026-06-05 — Encode/decode integer biner (SELESAI)

Fondasi untuk membangun klien protokol biner (Postgres/MySQL) sebagai modul Tenun.

- `src/builtins/binary.zig` — `keByte(nilai, lebar, besar)` encode integer ke `lebar` byte (1-8), big-endian bila `besar` benar (Postgres) atau little-endian (MySQL). `bacaInt(data, offset, lebar, besar)` baca integer unsigned dari byte.
- Builtin id 41 `keByte`, 42 `bacaInt`. Dispatch interp+VM (import VM dinamai `binmod` agar tidak bentrok dengan method `binary`).
- Verified: `keByte(196608,4,benar)` roundtrip = 196608; little vs big-endian beda (513 LE dibaca BE = 258).
- Struktur repo: proyek inti pindah ke folder `TenunLang/` (workspace `Tenun/` untuk modul). CI: `.github/workflows/release.yml` build Linux+Windows, auto tag & release.

## 2026-06-05 — Rename: Tenu → Tenun

Nama bahasa diperbaiki jadi **Tenun** (bukan Tenu). Rename menyeluruh kata utuh `Tenu`/`tenu` → `Tenun`/`tenun` di semua kode/docs/skill/memory. Binary `tenun`, package `.tenun`, ekstensi file `.tenun`, skill dir `tenun-spec`, memory `tenun-*`. Fingerprint build.zig.zon berubah → `0x7c8391e5737e79ae` (name baru). Teks user-facing pakai Bahasa Indonesia formal.

## 2026-06-05 — Built-in kripto (SELESAI)

Buat hashing password, token, dan membangun auth klien DB.

- `src/builtins/crypto.zig` — `sha256`/`sha1`/`md5` (hex via std.crypto.hash), `hmacSha256` (std.crypto.auth.hmac), `base64Enkode`/`base64Dekode` (std.base64.standard), `acak(n)` (std.crypto.random → hex). Helper `toHex`.
- Builtin id 34 `sha256`, 35 `sha1`, 36 `md5`, 37 `hmacSha256`, 38 `base64`, 39 `dariBase64`, 40 `acak`. Dispatch interp+VM.
- Verified: hash sha256/sha1/md5, hmac, base64 roundtrip ("Halo Tenun"↔"SGFsbyBUZW51bg=="), acak(16)→32 hex.
- Output hash heksadesimal (printable). Untuk SCRAM/biner mentah bisa dipadukan dengan base64. Docs `BAHASA.md` diperbarui.

## 2026-06-05 — Konektor TCP mentah (fondasi klien DB) (SELESAI)

Primitif jaringan low-level supaya klien DB/protokol dibangun sebagai modul Tenun nanti.

- VM+interp simpan daftar koneksi (`conns: ArrayList(?std.net.Stream)`, ditutup saat deinit).
- Builtin id 30 `sambung(host, port): bulat` (handel, via `std.net.tcpConnectToHost` — DNS + connect), 31 `kirim(soket, data)`, 32 `terima(soket, maks): teks` (baca byte mentah, boleh biner), 33 `tutup(soket)`.
- Verified: `sambung("example.com",80)` + HTTP GET manual → `terima` mengembalikan "HTTP/1.1 200 OK".
- Catatan: koneksi per-VM (per-worker). DB sungguhan (Postgres/Redis/MySQL) akan dibangun di atas primitif ini sebagai modul Tenun. Docs `BAHASA.md` diperbarui.

## 2026-06-05 — Penyimpanan persisten key-value (SELESAI)

Storage untuk web app (sesi/data) tanpa dependency eksternal.

- `src/builtins/kv.zig` — KV store di berkas `tenun_data.json`. Operasi `simpan`/`muat`/`hapus` pakai `std.json` (parse leaky + stringify), dilindungi `std.Thread.Mutex` global (aman multi-worker). Tiap operasi baca-modifikasi-tulis berkas.
- Builtin id 27 `simpan(kunci, nilai)`, 28 `muat(kunci): teks`, 29 `hapus(kunci)`. Dispatch interp+VM.
- Verified: simpan/muat 2 key, hapus → muat balik "", file akhir `{"kota":"Jakarta"}`.
- `.gitignore`: `tenun_data.json`. Keterbatasan: KV sederhana (nilai teks, baca-tulis seluruh file per operasi) — untuk skala besar perlu DB sungguhan. Docs `BAHASA.md` diperbarui.

## 2026-06-05 — Baca header & cookie permintaan (SELESAI)

Auth & session jadi mungkin.

- VM+interp simpan header permintaan masuk (`req_headers`, di-capture dari `req.iterateHeaders()` tiap permintaan, dupe ke arena, reset per-request).
- Builtin id 25 `headerMasuk(nama): teks` (cari case-insensitive via `std.ascii.eqlIgnoreCase`), id 26 `cookie(nama): teks` (baca header Cookie lalu parse `k=v; k=v` via `text.cookieAmbil`).
- Set cookie/header respons tetap lewat `headerKan` (mis. `Set-Cookie`).
- Verified curl: `-H "Authorization: Bearer xyz"` → `headerMasuk`; `-H "Cookie: sesi=abc123"` → `cookie("sesi")="abc123"`; `headerKan("Set-Cookie",...)` muncul di respons.

## 2026-06-05 — Parsing query string + form (SELESAI)

- `src/builtins/text.zig`: `kueri(url, kunci)` (ambil `?k=v` setelah `?`), `form(badan, kunci)` (urlencoded body). Keduanya URL-decode nilai (`%XX` → byte, `+` → spasi) via helper `urlDecode`/`paramDari`.
- Builtin id 23 `kueri`, 24 `form`. Dispatch interp+VM.
- Verified: `kueri("/cari?q=halo+dunia","q")="halo dunia"`, `%20` decode, `form` body, key tak ada → "".

## 2026-06-05 — JSON (baca) + adaFile + web app penuh (SELESAI)

API + static serving lengkap dengan 404.

- `src/builtins/json.zig` — `teks`/`angka`/`boolean`(a, src, key) baca field top-level JSON via `std.json.parseFromSliceLeaky` (alokasi di arena, tanpa deinit). Builtin: `jsonTeks`,`jsonAngka`,`jsonBool` (json:teks, kunci:teks).
- `src/builtins/fs.zig` tambah `ada(path) bool` (access). Builtin `adaFile` → untuk 404.
- Dispatch interp+VM cases 19-22. Spec id 19-22.
- **Web app penuh** `examples/webapp.tenun`: static (HTML/CSS, content-type via `tipeKonten`), 404 via `adaFile`+`statusKan`, REST `POST /api` baca JSON body (`jsonTeks`) balikin JSON. Verified curl: GET / (200 html), /gaya.css (200 css), /ngawur (404), POST /api {"nama":"Tenun"} → {"halo":"Tenun"}.
- Keterbatasan JSON: hanya field top-level skalar; objek/larik bersarang & serialize otomatis belum (butuh tipe dinamis). Docs `BAHASA.md` diperbarui.

## 2026-06-05 — String ops + MIME + web app statis (SELESAI)

Builtin untuk bikin web app nyata: routing, parsing, file statis.

- `src/builtins/text.zig` tambah: `cari` (indexOf, -1), `ganti` (replace all via std.mem.replaceOwned), `pisah` (split → [][]const u8), `mulaiDengan`/`akhiriDengan` (prefix/suffix), `tipeKonten` (MIME by ekstensi).
- Spec: `cari`,`ganti`,`pisah`(ret `[]teks`),`gabung`(param `[]teks` → teks),`mulaiDengan`,`akhiriDengan`,`tipeKonten`. Tipe larik di spec via `const teks_el: Type = .teks; teks_array = .{ .array = &teks_el }`.
- Dispatch interp+VM: `pisah` bangun array Value, `gabung` baca array Value + join. Sisanya pure.
- Verified: `cari("halo dunia","dunia")=5`, `ganti`, `pisah`/`gabung`, `mulaiDengan`, `tipeKonten("gaya.css")=text/css`.
- **Web app statis** berjalan: `examples/webapp.tenun` + `examples/publik/{index.html,gaya.css}` — serve HTML+CSS dengan content-type benar (curl 200). Docs `BAHASA.md` diperbarui (tabel builtin + contoh file statis).

## 2026-06-05 — Server multi-threaded (production) (SELESAI)

Server jadi konkuren — siap menangani banyak permintaan paralel.

- **Thread pool**: `layani` menjalankan 1 worker per inti CPU (`std.Thread.getCpuCount`). Semua worker `accept()` dari listener yang sama.
- **Isolasi worker**: tiap worker punya VM sendiri (stack/frame/arena terpisah), berbagi tabel fungsi (bytecode immutable, aman dibaca bersama), dan meng-clone variabel global saat startup (tanpa lock, tanpa data race). Arena nilai di-reset tiap permintaan (memori terbatas).
- `serve` di-refactor: `WorkerCtx` + `workerLoop` (free fn untuk thread) + `handleConn` (per-permintaan). Interpreter (`--interp`) tetap single-thread (untuk diagnosa).
- Terverifikasi: 16 worker, 50 permintaan paralel, semua 200.
- Catatan/keterbatasan: modifikasi variabel global di handler tidak terbagi antar worker (clone per-worker) — state persisten harus lewat file/DB. Docs `BAHASA.md` diperbarui (catatan konkurensi).

## 2026-06-05 — Server web diperkaya + escape string (SELESAI)

Fokus: web programming (lihat arah project). Server jadi layak untuk web app.

- **Handler diperkaya**: `tangani(metode: teks, jalur: teks, badan: teks): teks` — sekarang menerima method HTTP, path, dan request body (sebelumnya hanya path). Server membaca `req.head.method`, `req.head.target`, dan body via `req.reader()`.
- **Builtin respons**: `statusKan(kode: bulat)` set status code; `headerKan(nama, nilai)` tambah header. Disimpan di state VM/interp (`resp_status`, `resp_headers`), direset tiap permintaan, diterapkan di `req.respond` (`.status`, `.extra_headers`).
- **Escape string** di lexer/parser: `\"` `\\` `\n` `\t` `\r`. Lexer tidak terminate pada `\"`; parser mendekode escape ke nilai string (di arena). Penting untuk JSON. interp/vm pakai nilai terdekode; codegen native me-escape ulang ke literal C; dumper AST membungkus dengan kutip.
- Terverifikasi via curl: GET / (200 text/html), GET /api (200 application/json dengan JSON ber-escape), POST (method+body), 404 (statusKan).
- `examples/server.tenun` diperbarui jadi router (GET/POST/JSON/404). Docs `BAHASA.md` + `GRAMMAR.md` diperbarui.

## 2026-06-05 — Stdlib registry + math/teks/file + HTTP server `layani` (SELESAI)

Fondasi stdlib + batch builtin, semua via `tenun run` (VM/interp), tanpa build.

- **Registry builtin**: `src/builtins/spec.zig` (tabel `{name, params, ret}`) jadi satu sumber buat sema (cek tipe/arity) + compiler (id) + dispatch. Logika builtin di modul Value-agnostic: `builtins/math` (inline), `builtins/text.zig` (`potong`), `builtins/fs.zig` (baca/tulis), `builtins/http.zig`.
- **VM**: opcode generik `builtin id argc` (ganti `http_get`); `callBuiltin(id, args)`. Dispatch sama di interp (`callBuiltin`). Sema loop `spec.list` (hapus special-case `ambil`). Codegen native: builtin runtime → unsupported.
- **Builtin baru**: `akar`, `pangkat`, `mutlak`, `bulatkan` (math), `panjangTeks`, `potong` (teks), `bacaFile`, `tulisFile` (file).
- **HTTP server `layani(port)`** — mirip Node.js: `tenun run server.tenun` langsung jadi web server, tanpa kompilasi. Memakai `std.http.Server`. Tiap permintaan memanggil fungsi user `tangani(jalur: teks): teks` dan mengirim hasilnya sebagai body. Mekanisme: VM di-refactor `run`→`execLoop(stop)` + `callTenunFn` (panggil fungsi Tenun re-entran dari dalam builtin); interp pakai `invokeUser`. Terverifikasi dengan curl (respons dinamis per path).
- `examples/server.tenun`, `examples/web.tenun`. Docs `BAHASA.md` diperbarui (tabel builtin + bagian server).

## 2026-06-05 — Stdlib jaringan: builtin `ambil` (HTTP/HTTPS GET) (SELESAI)

Builtin pertama untuk jaringan. `ambil(url: teks): teks` melakukan HTTP GET dan mengembalikan body. HTTPS/TLS ditangani otomatis oleh `std.http.Client` (sertifikat sistem) — tidak perlu konfigurasi.

- `src/builtins/http.zig` — `get(allocator, url) -> []u8` via `std.http.Client.fetch` (response_storage dynamic).
- Sema: `ambil` 1 arg `teks` → `teks`.
- Interpreter + VM: jalankan `ambil` (VM pakai opcode baru `http_get`). Body dialokasikan di arena nilai.
- Codegen native: `ambil` dilaporkan belum didukung (butuh runtime) — pakai `tenun run`.
- Terverifikasi: `tenun run examples/web.tenun` mengambil `https://example.com` (TLS) dan mencetak HTML-nya.
- `examples/web.tenun` ditambah. Docs `BAHASA.md` diperbarui (builtin + bagian jaringan).
- Catatan: parsing JSON, soket mentah, dan method lain (POST/header) menyusul.

## 2026-06-05 — Codegen native: larik + UX build (SELESAI)

- **Larik di codegen native.** Representasi C universal `typedef struct { void* data; int64_t len; } TenunArr`. Literal `[..]` via statement-expression (`({ T* _arr = malloc(...); _arr[i]=..; (TenunArr){...}; })`, didukung clang/zig cc). Indeks baca/tulis: `((T*)(arr).data)[i]`. `panjang(a)` → `(a).len`. `cetak` larik skalar → loop printf `[a, b, c]`. **Larik bersarang jalan** (mis. `m[1][0]`) karena elemen `[][]bulat` bertipe `TenunArr` rekursif. Cetak larik bersarang belum (pakai VM).
- **UX `tenun build`:** file C perantara dihapus otomatis setelah kompilasi — output hanya `.exe`. Flag `--emit-c` untuk menyimpan C buat inspeksi. (Transpile-ke-C cuma strategi internal; user tetap dapat exe native langsung.)
- Test: codegen menghasilkan C larik yang benar (TenunArr decl, literal, .len, index-assign). `examples/larik.tenun` kompilasi native + jalan ([5,10,15,20] lalu 50). Contoh buangan dibersihkan.

## 2026-06-05 — Fase 5: Codegen native via transpile C (SELESAI, subset skalar)

`tenun build <file>` mentranspilasi Tenun ke C, lalu `zig cc -O2` menghasilkan executable native. Jalur tercepat.

- `src/codegen/codegen.zig` — `generate(allocator, program, diags) -> []u8` (sumber C). Prelude (stdio/stdint/string/stdlib/math + `tenun_concat`). Map tipe: bulat→int64_t, desimal→double, teks→const char*, bool→int, kosong→void. Global Tenun → C file-scope static (init di main, urut). Fungsi → `tf_<nama>`, variabel → `t_<nama>` (hindari bentrok keyword C). `untuk` → C for-loop. `+` teks → `tenun_concat`. `cetak` → printf sesuai tipe (inferensi tipe internal di codegen). Punya symbol table (global + scope lokal) untuk inferensi.
- `src/driver.zig` — `build()`: lexer→parser→sema→codegen→tulis `<base>.c`→`zig cc -O2 -o <base>.exe`. Lapor sukses/gagal.
- **Performa (loop 50jt, ReleaseFast):** native ~0.014s, VM ~1.06s, interpreter ~2.69s. Native ~75x lebih cepat dari VM, ~190x dari interpreter (C compiler mengoptimasi loop agresif; kasus nyata bervariasi tapi native selalu tercepat).
- **Batas saat ini:** subset skalar saja. Larik (`[]T`), `panjang`, indeks belum di codegen native → lapor "belum didukung" dan sarankan `tenun run` (VM). Map/struct juga belum.
- Test: codegen menghasilkan C yang benar untuk program skalar (cek substring signature/return/printf/main).
- `.gitignore`: abaikan `*.exe`, `examples/*.c`. Docs `BAHASA.md` diperbarui (pipeline + `tenun build` + benchmark).

## 2026-06-05 — Fase 4: Bytecode VM (SELESAI) — backend default, ~2.3x lebih cepat

Backend eksekusi baru: compile AST ke bytecode lalu jalankan di stack VM. Jadi DEFAULT `tenun run`; `--interp` untuk tree-walker. Output identik di semua contoh + test.

- `src/vm/vm.zig` — satu modul berisi: `OpCode` (~33 opcode), `Chunk` (code + consts), `Function` (name/arity/chunk), `Compiler` (AST→bytecode, clox-style), `VM` (eksekusi).
- Compiler: resolusi lokal berbasis slot (bukan hashmap), scope depth (depth 0 di main = global, sisanya lokal). Fungsi top-level di-hoist ke tabel fungsi, panggil by index. Builtin `cetak`→OP print, `panjang`→OP array_len. Short-circuit `&&`/`||` via jump. `untuk` pakai 2 lokal tersembunyi (var + `$end`).
- VM: stack pre-alokasi tetap (64K) + index `top` (bukan ArrayList), push/pop inline tanpa cek kapasitas. Call frame {func, ip, base}; lokal hidup di stack mulai base. `frame`+`code` di-cache di register, refresh hanya saat call/ret. Global via hashmap (DEFINE/GET/SET_GLOBAL).
- **Performa:** loop 50 juta (`untuk` + akumulasi lokal), ReleaseFast: interpreter ~2.66s vs VM ~1.15s = ~2.3x. Startup ~16ms.
- **Bug penting (Zig 0.14):** `get_local` push nilai yang dibaca dari ArrayList stack yang sama → saat `append` realloc, sumber pointer dangling (Value dioper by-pointer ABI) → tag rusak jadi teks. Diperbaiki total dengan stack tetap (tanpa realloc). Pelajaran: jangan append elemen yang aliasing buffer ArrayList itu sendiri.
- Test: 10 golden VM (aritmatika, konkat, kalau/lain, selama, untuk, rekursi faktorial, panggil sebelum definisi, short-circuit, larik+panjang, isi larik). Semua cocok dengan interpreter.
- `examples/bench.tenun` (loop 10 juta) ditambah. Docs `BAHASA.md` diperbarui (pipeline + backend).

## 2026-06-05 — Fitur: penugasan elemen larik `a[i] = x` (SELESAI)

Larik kini bisa diisi/diubah. `untuk i dari 0 sampai 5 { a[i] = i * 2; }` lalu `cetak(a)` → `[0, 2, 4, 6, 8]`.

- `ast.Expr.Assign` diubah dari `{name, value}` jadi `{target: *Expr, value}` — target boleh `ident` atau `index`. Dumper assign pakai `dumpExpr(target)`.
- Parser `assignment()`: terima LHS `ident` ATAU `index` (akses `a[i]`).
- Sema: assign ke ident (cek const + tipe) atau ke index (target harus larik, indeks bulat, tipe nilai == tipe elemen).
- Interp: assign index → mutasi elemen di tempat (`arr[i] = v`, semantik referensi), cek di luar batas → RuntimeError.
- Test: parser (`(= (indeks a 1) 9)`), sema (tipe elemen salah ditolak), interp (ubah 1 elemen, isi larik lewat `untuk`).
- Docs `BAHASA.md`/`GRAMMAR.md`/`tenun-spec` diperbarui.

## 2026-06-05 — Fitur: larik / array (SELESAI)

Tipe komposit pertama. `tenun run examples/larik.tenun` keluar `[5, 10, 15, 20]` lalu `50`.

- Token `[` `]` (`src/lexer/token.zig`, `lexer.zig`).
- **Refactor `ast.Type`: enum → union(enum)** dengan varian `array: *const Type` (bisa nested). Tambah method `eql` (deep compare), `isNumeric`, `writeName` (rekursif, mis. "[]bulat"). Semua pembandingan tipe di sema pindah dari `==` ke `.eql()` / `std.meta.activeTag`.
- AST: `Expr.array` (literal `[]*Expr`) + `Expr.index` ({target, idx}) + dumper (`larik`, `indeks`).
- Parser: `parseType` dukung `[]T`; primary dukung literal `[...]`; postfix `[i]` di `call()` (gabung dengan pemanggilan fungsi).
- Sema: literal (semua elemen tipe sama, disimpulkan dari elemen pertama; larik kosong ditolak), indeks (target harus array, indeks `bulat`, hasil = tipe elemen), builtin `panjang(array): bulat`. Type arena untuk tipe hasil inferensi.
- Interp: `Value.array`, eval literal (alloc di arena nilai), indeks + cek di luar batas (RuntimeError), builtin `panjang`, cetak larik (`[a, b, c]`), `valueEql` rekursif.
- Catatan: penugasan ke elemen (`a[i] = x`) belum didukung.
- Test: parser (literal + indeks), sema (via interp), interp (akses + panjang, jumlah lewat `untuk`, cetak larik).
- Docs: `BAHASA.md`, `GRAMMAR.md`, `tenun-spec` diperbarui. `examples/larik.tenun` ditambah.

## 2026-06-05 — Fitur: perulangan `untuk` (SELESAI)

Perulangan iterasi rentang. Sintaks: `untuk i dari 0 sampai n { ... }` — `i` dari `0` sampai `n-1` (akhir eksklusif, langkah +1). `tenun run` contoh `untuk i dari 1 sampai 6 { cetak(i * i); }` keluar 1 4 9 16 25.

- Keyword baru `dari` + `sampai` (`src/lexer/token.zig`).
- AST node `Stmt.For` {var_name, start, end, body} + dumper (`src/parser/ast.zig`).
- Parser `forStmt` (`src/parser/parser.zig`).
- Sema: batas awal/akhir wajib `bulat`, var iterasi `bulat` di scope blok (`src/sema/sema.zig`).
- Interp: scope loop terpisah, var di-set tiap iterasi, hormati `kembali` (`src/interp/interp.zig`).
- Test: parser golden, sema (batas non-bulat ditolak, var iterasi terlihat di body), interp (iterasi + akumulasi).
- Docs: `BAHASA.md`, `GRAMMAR.md`, `tenun-spec` diperbarui.

## 2026-06-05 — Fase 2 + 3: Sema + Interpreter (SELESAI) — BAHASA HIDUP

Program Tenun sekarang BENERAN JALAN. `tenun run examples/hello.tenun` keluar "Halo, Tenun". `faktorial(5)` = 120. Semua test ijo.

- `src/sema/sema.zig` — analisis semantik 3-pass: (1) registrasi signature fungsi (hoisting top-level), (2) cek statement top-level (bangun scope global), (3) cek body tiap fungsi. Name resolution (scope stack, deklarasi-sebelum-pakai, no-redeklarasi di scope sama, block scope). Type checking: inferensi tipe var dari nilai, cek anotasi, operand aritmatika/perbandingan/logika, `+` untuk teks, kondisi `kalau`/`selama` harus bool, `tetap` immutable, jumlah+tipe argumen fungsi, tipe `kembali` cocok, builtin `cetak` (1 argumen apa pun). Semua error via diagnostics dengan posisi.
- `src/interp/interp.zig` — tree-walking interpreter. `Value` union (bulat/desimal/teks/bool/kosong). Scope: global + stack lokal per blok; fungsi dapat scope bersih (param + global), tidak melihat lokal pemanggil. Eksekusi: var/assign, if/lain, selama, kembali (via flag returning/ret_value), pemanggilan fungsi + rekursi, builtin `cetak` (+newline), konkatenasi teks, aritmatika int/float, pembagian/modulo nol → runtime error. Arena untuk string hasil konkatenasi.
- `src/driver.zig` — pipeline penuh: lexer → parser → sema → interpreter. Error fase mana pun → cetak diagnostics dan berhenti.
- **Catatan teknis (gotcha Zig):** pola `const result = if (cond) self.field else X; self.field = X2;` ternyata meng-corrupt `result` (result-location aliasing di Zig 0.14). Solusi: jangan reset `ret_value` setelah capture; cukup reset flag `returning` (nilai hanya dibaca saat returning=true, selalu ditulis ulang tiap `kembali`).
- Test: sema (program valid, tipe tidak cocok, var tidak dikenal, ubah konstanta, kondisi non-bool, argumen salah jumlah). Interp (cetak teks/angka, konkatenasi, kalau/lain, selama, rekursi faktorial, panggil sebelum definisi, operator logika, scope lokal tidak bocor).
- `examples/faktorial.tenun` ditambahkan.

## 2026-06-05 — Fase 1b: AST + Parser (SELESAI)

`zig build test` semua ijo (10 test parser). `tenun run examples/hello.tenun` → "5 deklarasi".

- `src/parser/ast.zig` — node: `Expr` (number, string, boolean, nil, ident, unary, binary, call, assign), `Stmt` (var_decl, fungsi_decl, expr_stmt, if_stmt, while_stmt, return_stmt, block), `Type`, `BinaryOp`, `UnaryOp`, `Param`, `Program`. Tiap node simpan `Pos`. Plus dumper S-expression (`dumpProgram`) buat golden test.
- `src/parser/parser.zig` — recursive descent ikut precedence EBNF spec (assignment → or → and → equality → comparison → term → factor → unary → call → primary). Pakai arena allocator. Error parsing jelas via diagnostics + `error.ParseError` buat unwind. `parse(arena, tokens, diags) → Program`.
- `src/driver.zig` — `run()` sekarang lexer→parser; error di fase mana pun → print diagnostics; sukses → print jumlah deklarasi top-level.
- **Perubahan desain:** `cetak` BUKAN keyword lagi — jadi fungsi builtin (identifier biasa), supaya bisa diperlakukan seperti fungsi lain. Diregistrasi nanti di sema/interp.
- Golden test: precedence aritmatika/logika, unary, assignment, var decl beranotasi, fungsi+param+return, kalau/lain+call, selama. Plus struktur test + error case.

## 2026-06-05 — Fase 1a: Lexer (SELESAI)

`zig build test` semua ijo (incl. 8 test lexer). `tenun run examples/hello.tenun` → "66 token".

- `src/lexer/token.zig` — `TokenKind` (literal, keyword, tipe, operator 1-2 char, pemisah, eof, invalid), struct `Token` (kind, lexeme, line, column), `keywords` StaticStringMap + `lookupKeyword`.
- `src/lexer/lexer.zig` — struct `Lexer`: `init`/`tokenize`. Skip whitespace + komentar `//`, skip BOM UTF-8 di awal. Scan number (int+float `3.14`), string (deteksi belum ditutup → diagnostics), identifier + keyword lookup, operator 1-2 char (`==` `!=` `<=` `>=` `&&` `||`). Lapor `&`/`|` tunggal + karakter tak dikenal ke diagnostics, lanjut. Track line/kolom.
- `src/driver.zig` — `run()` sekarang lex beneran: kalau ada error → print diagnostics; kalau bersih → print jumlah token. (`build()` masih placeholder.)
- Test: deklarasi var, operator 2-char, float/string/komentar, posisi line/kolom, string belum ditutup, karakter tak dikenal, sumber kosong.

## 2026-06-05 — Keputusan desain bahasa (DIKUNCI)

Empat keputusan inti diambil bareng user, ngebuka `[PUTUSIN]` di `tenun-spec`:

- **Tipe sistem: Statically typed.** Tipe dicek pas compile (fase sema). Boleh eksplisit (`biar umur: bulat = 17;`) atau inferred (`biar umur = 17;`). Parameter fungsi wajib beranotasi.
- **Sintaks: kurung kurawal `{}` + titik koma `;`.** Tiap statement diakhiri `;`; blok (`fungsi`/`kalau`/`selama`/`untuk`) tidak. Komentar baris `//`.
- **Operator logika: simbol** `&&` `||` `!` (bukan kata `dan`/`atau`/`bukan`).
- Tipe dasar: `bulat` (i64), `desimal` (f64), `teks` (string UTF-8), `bool`, `kosong` (void/null).
- Semantik: wajib deklarasi sebelum pakai; ga boleh redeklarasi di scope sama; block scope + shadowing; `tetap` ga bisa re-assign; fungsi top-level di-hoist (variabel tidak).
- Grammar EBNF subset Fase 1 ditulis lengkap di `.claude/skills/tenun-spec/SKILL.md`.

Keyword (sudah ada sebelumnya, dipertahankan): `biar` `tetap` `fungsi` `kembali` `kalau` `lain` `selama` `untuk` `benar` `salah` `kosong` `cetak`.

## 2026-06-05 — Fase 0: Fondasi (SELESAI)

Setup project Zig dari nol. Hasil: `zig build` sukses, `zig build test` 11/11 ijo, CLI jalan.

- `build.zig` — exe `tenun` + step `run` & `test`. Zig 0.14.0.
- `build.zig.zon` — name `.tenun`, fingerprint `0x7c8391e5737e79ae`, min zig 0.14.0.
- `src/main.zig` — CLI: `tenun version` / `tenun run <file>` / `tenun build <file>` + usage. Test root (refAllDeclsRecursive + import semua modul).
- `src/driver.zig` — `run()` & `build()`: baca file → (pipeline placeholder). Helper `readFile`.
- `src/diagnostics/diagnostics.zig` — `Diagnostics` collector: `report` / `hasErrors` / `print`. `Severity = enum { err, warning }`. Sudah ada test.
- `src/{lexer,parser,sema,interp,vm,codegen}/*.zig` — stub modul (placeholder test) siap diisi.
- `examples/hello.tenun` — contoh program target sintaks (sesuai spec terkunci).
- `.gitignore` — zig-cache, zig-out.

Catatan teknis:
- `run`/`build` saat ini cuma baca file + print "pipeline belum diimplementasi". Pipeline asli mulai Fase 1.
- Tiap modul fase di-`_ = @import(...)` di `src/main.zig` test block biar test-nya kebawa `zig build test`.

## Berikutnya — Fase 1 (Front end)

Lexer dulu: `src/lexer/token.zig` (definisi `TokenKind` dari keyword spec) + `src/lexer/lexer.zig` (scanner source → token + line/kolom). Lalu AST + parser recursive descent ikut precedence di spec. Wajib golden test. Baca skill `add-language-feature`.
