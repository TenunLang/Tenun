# Grammar Formal Tenun

Notasi: EBNF. `*` = nol atau lebih, `?` = opsional, `|` = alternatif, `( )` = grup. Token terminal huruf besar (`IDENT`, `NUMBER`, `STRING`).

**Wajib diperbarui setiap ada perubahan sintaks.** Sumber kebenaran desain ada di skill `tenun-spec`; dokumen ini cerminannya untuk pengguna. Subset di bawah adalah yang sudah didukung parser (Fase 1b).

```ebnf
program     = deklarasi* EOF ;

deklarasi   = varDecl | fungsiDecl | statement ;

varDecl     = ("biar" | "tetap") IDENT (":" tipe)? "=" ekspresi ";" ;
fungsiDecl  = "fungsi" IDENT "(" params? ")" ":" tipe blok ;
params      = param ("," param)* ;
param       = IDENT ":" tipe ;
tipe        = "[" "]" tipe | "bulat" | "desimal" | "teks" | "bool" | "peta" | "kosong" ;

statement   = exprStmt | ifStmt | whileStmt | forStmt | returnStmt | "henti" ";" | "lanjut" ";" | blok ;
exprStmt    = ekspresi ";" ;
ifStmt      = "kalau" ekspresi blok ("lain" (ifStmt | blok))? ;
whileStmt   = "selama" ekspresi blok ;
forStmt     = "untuk" IDENT "dari" ekspresi "sampai" ekspresi blok ;
returnStmt  = "kembali" ekspresi? ";" ;
blok        = "{" deklarasi* "}" ;

ekspresi    = assignment ;
assignment  = lvalue "=" assignment | logicOr ;
lvalue      = IDENT | call ;   (* target harus IDENT atau akses indeks larik *)
logicOr     = logicAnd ("||" logicAnd)* ;
logicAnd    = equality ("&&" equality)* ;
equality    = comparison (("==" | "!=") comparison)* ;
comparison  = term (("<" | ">" | "<=" | ">=") term)* ;
term        = factor (("+" | "-") factor)* ;
factor      = unary (("*" | "/" | "%") unary)* ;
unary       = ("!" | "-") unary | call ;
call        = primary ("(" args? ")" | "[" ekspresi "]")* ;
args        = ekspresi ("," ekspresi)* ;
primary     = NUMBER | STRING | "benar" | "salah" | "kosong"
            | larik | peta | IDENT | "(" ekspresi ")" ;
larik       = "[" (ekspresi ("," ekspresi)*)? "]" ;
peta        = "peta" "{" (entri ("," entri)*)? "}" ;
entri       = ekspresi ":" ekspresi ;
```

## Token (terminal)

```
NUMBER  = digit+ ("." digit+)? ;
STRING  = '"' (karakter | escape)* '"' ;
escape  = '\' ('"' | '\' | 'n' | 't' | 'r') ;
IDENT   = (huruf | "_") (huruf | digit | "_")* ;
komentar = "//" sampai akhir baris (diabaikan) ;
```

## Belum di grammar (direncanakan)

- tipe komposit lain: struct
- langkah (step) kustom pada `untuk`
