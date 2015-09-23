Linux 64bit用 Forth

## 仕様

- サブルーチン・スレッディング
- TOSをレジスタに置く

## TODO

- プリミティブワードのインライン展開

## 起動

```sh
$ ./RFR64
```

ファイル読み込み

```sh
$ cat yourfile.fs - | ./RFR64
```

## サンプル

```
$ ./RFR64
load examples.fs

( Mark&Sweep Garbage Collection Test )
gc-test


: counter:  create 0 ,  does> dup @ .  1 swap +! ;

: [get]  [compile] lit  read-token find >body , [compile] @ ; immediate
: countdown  begin  dup 0>=  while  dup .  1 -  repeat  drop ;

counter: i
: GO!  i i i i i i i i i i  [get] i countdown  bye ;

GO!
```
