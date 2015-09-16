Linux 64bit用 Forth

## 仕様(予定)

- サブルーチン・スレッディング
- TOSをレジスタに置く
- プリミティブワードのインライン展開

## 起動

```sh
$ ./RFR64
```

ファイル読み込み

```sh
$ cat builtin.fs - | ./RFR64
```

## サンプル

```
$ cat builtin.fs - | ./RFR64
: counter:  create 0 ,  does> dup @ .  1 swap +! ;

: [get]  [compile] lit  read-token find >body , [compile] @ ; immediate
: countdown  begin  dup 0>=  while  dup .  1 -  repeat  drop ;

counter: i
: GO!  i i i i i i i i i i  [get] i countdown  bye ;

GO!
```
