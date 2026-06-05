# Roadmap Tenun

Prinsip utama: **bikin yang jalan dulu, baru bikin yang cepat.** Validasi desain bahasa pakai interpreter sederhana sebelum sentuh codegen yang ribet. Banyak proyek bahasa mati karena loncat ke LLVM duluan.

## Fase 0 — Fondasi [SELESAI]

- Init project Zig (`build.zig`, `build.zig.zon`)
- CLI skeleton: `tenun version`, `tenun run <file>`, `tenun build <file>`
- Modul `diagnostics` siap dipakai

## Fase 1 — Front end (lexer + parser) [SELESAI]

- Definisi token + lexer (sumber -> token, dengan posisi line & kolom)
- Definisi AST + parser recursive descent (token -> AST)
- Error parsing yang jelas

## Fase 2 — Analisis semantik [SELESAI]

- Name resolution: scope, binding variabel, deteksi variabel tidak dikenal
- Type checking statis
- Diagnostik error semantik

## Fase 3 — Interpreter [SELESAI]

- Tree-walking interpreter: jalankan AST langsung
- Runtime value, environment, pemanggilan fungsi, kontrol alur
- Builtin `cetak`

## Fase 4 — Bytecode VM [SELESAI]

- Compile AST -> bytecode
- Stack-based virtual machine, jauh lebih cepat dari tree-walking
- Backend default untuk `tenun run`

## Fase 5 — Native codegen [SELESAI, tahap awal]

- Transpile ke C, kompilasi dengan `zig cc` -> executable native
- Jalur tercepat (`tenun build`)
- Berikutnya bisa naik ke QBE atau LLVM bila dibutuhkan

## Fase 6 — Stdlib & tooling [BERIKUTNYA]

- Pustaka standar (string, math, file I/O, lalu jaringan)
- Tipe komposit lanjutan (map, struct)
- Formatter (`tenun fmt`) dan REPL (`tenun repl`)
- Dasar sistem modul/paket

## Catatan

Fase 3 adalah garis finish untuk "MVP yang bisa dipamerkan". Fase 4 ke atas soal kualitas & kecepatan.
