# Changelog Tenun

Catatan semua perubahan penting + keputusan desain. Format: terbaru di atas.

## 2026-06-05 — Rename: Tenu → Tenun

Nama bahasa diperbaiki jadi **Tenun** (bukan Tenu). Rename menyeluruh kata utuh `Tenu`/`tenu` → `Tenun`/`tenun` di semua kode/docs/skill/memory. Binary `tenun`, package `.tenun`, ekstensi file `.tenun`, skill dir `tenun-spec`, memory `tenun-*`. Fingerprint build.zig.zon berubah → `0x7c8391e5737e79ae` (name baru). Teks user-facing pakai Bahasa Indonesia formal.

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
