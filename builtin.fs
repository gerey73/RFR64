: cell   (   -- n )  8 ;
: cells  ( n -- n ) cell * ;
: allot  ( n --   ) here +! ;

: align  ( x n -- x )  1- dup  rot +  swap invert and ;
: cell-align  ( x -- x )  8 align ;

: DEC  ( -- )  10 base ! ;
: HEX  ( -- )  16 base ! ;

: ret    ( -- n )  195 ;    | 0xC3 ret命令
: [ret]  ( --   )  ret c, ; | ret命令をコンパイルする。
: exit   ( --   )  [ret] ; immediate

: compile-mode?  ( -- ? )  state @ 1 = ;
: execute-mode?  ( -- ? )  state @ 0= ;

: [postpone]  ( -- )  read-token find compile ; immediate
: [compile]   ( -- )  | 次の命令をコンパイルするコード、をコンパイルする。
   ' lit compile  read-token find ,  ' compile compile ; immediate

: >code  ( -- )  >&code @ ;  | コードアドレスを直接取得する。

: find>       ( -- a )  read-token find ;
: find-code>  ( -- a )  find> >code ;


| 制御構造
| ------------------------------------------------------------------------------
: offset-space  (   -- a )  here @  0 4c, ;
: save-offset   ( a --   )  dup here @  swap -  swap 4c! ;

: if    (   -- a )  [compile] 0branch  offset-space ; immediate
: else  ( a -- a )  [compile]  branch  offset-space swap save-offset ; immediate
: then  ( a --   )  save-offset ; immediate

: back-branch  ( a -- )  [compile] branch  here @ - 4c, ;
: begin  (   -- a )  here @ ; immediate
: until  ( a --   )  [compile] 0branch  here @ - 4c,  ; immediate
: again  ( a --   )  back-branch  ; immediate

: while   ( a   -- a a )  [postpone] if ; immediate
: repeat  ( a a --     )  swap back-branch  save-offset ; immediate


| CREATE & DOES>
| ------------------------------------------------------------------------------
( CREATE, VARIABLE )
: create  (   -- )  read-token create-header DOVAR compile-call ;
: var:    (   -- )  create cell allot ;
: var>    ( x -- )  create , ;

( DOES> )
var: here.old
: save-here       ( -- )  here @ here.old ! ;
: restore-here    ( -- )  here.old @ here ! ;

: compile-offset  ( a1 a2 -- )
   ( ワードアドレスa1を呼び出すcallを、アドレスa2にコンパイルする )
   save-here  here ! compile-call  restore-here ;

: (does)  ( a -- )  latest @  >&code @  compile-offset ;

: does>   ( -- )
   [compile] lit  here @  cell allot  [compile] (does)  [ret]
   here @ swap !  DODOES compile-call ; immediate

( CONSTANT )
: const>  create ,  does> @ ;
: >body   >&code @  5 + ;


| 再帰
| ------------------------------------------------------------------------------
: recur  ( -- )   latest @ compile ; immediate
: trec   ( -- )  | ブランチによる再帰。(最適化された末尾再帰的なもの)
   [compile] branch  latest @ >code  here @ - 4c, ; immediate


| 文字、文字列
| ------------------------------------------------------------------------------
: spaces  ( n -- )  begin  dup 0>  while  1- space  repeat ;

create strbuff 512 allot    ( 文字列リテラル用バッファ )

: litstr  ( -- a u )
   | コンパイルして使う。これがcallされた次の4byteに長さ、それ以降に文字列が
   | 置かれてるとして、長さとアドレスを返し、文字列部分をスキップする。
   r>        ( r  リターン先                       )
   dup 4 +   ( r a                                 )
   over 4c@  ( r a u                               )
   rot 4 +   ( a u r  文字数を格納した位置を飛ばす )
   over +    ( a u r  文字数分飛ばす               )
   >r ;

: [char]  ( -- )
   | 区切り文字の次の文字を読み込み、lit 文字コード の形にコンパイルする。
   [compile] lit  key , ; immediate

: load-strlit  ( -- u )    ( " までバッファに読み込む )
   0 ( 文字数 )
   begin
      key dup  [char] " <>
   while
      over       ( u c u )
      strbuff +  ( u c a )
      c! 1+      ( u )
   repeat
   drop ( " を捨てる ) ;

: str,  ( a u -- )
   | 文字列を現在の辞書位置にコピーする。辞書ポインタも更新する。
   swap over          ( u a u )
   here @ block-copy  ( u )
   here +! ;

: s"  ( -- a u )
   | 文字列リテラル )
   | 実行モードの場合、バッファに書き込みアドレスと長さを返す。
   | コンパイルモードの場合、その場に書き込み、アドレスと長さを
   | スタックに置く命令にコンパイルする。
   strbuff load-strlit  ( a u )
   execute-mode?  if exit then
   [compile] litstr  dup 4c,  str, ; immediate

: ."  ( -- )
   | 文字列出力
   | 実行モードの場合、そのまま出力する。
   | コンパイルモードの場合、文字列を出力するコードをコンパイルする。
   [postpone] s"
   execute-mode?  if print exit then
   [compile] print ; immediate

( 文字列比較 ----------------------------------------------------------------- )
: 3drop  ( x x x -- )  2drop drop ;

: block-eq  ( a a' u -- ? )
   dup 0<=  if 3drop 1 exit then  ( 比較残りが0、同じだった )
   -rot 2dup c@ swap c@ <>        ( u a a' ?  同じか?       )
   if 3drop 0 exit then           ( 違った / u a a'         )
   1+ -rot 1+ swap 1-  ( a' a u )  trec ;

: str-eq  ( a u  a' u' -- ? )
   | 文字列比較
   rot over <>          ( a a' u ? )
   if 3drop 0 exit then ( 長さが違った )
   block-eq ;


| Arithmetic
| ------------------------------------------------------------------------------
: divisible?  ( a b -- ? )  mod 0= ;
: in-range?   ( x lo hi -- ? )  | lo <= x < hi  アドレス比較に都合がいいので。
   rot swap over ( lo x hi x )
   <=  if 2drop 0 exit then  ( lo x )
   >   if       0 exit then  1 ;


| Logical
| ------------------------------------------------------------------------------
: not  ( ? -- ? )  0= ;

: and>>  immediate  ( -- )
   | <例>  : check dup 2 divisible? and>> dup 0 10 in-range? and>> 1 ;
   | not ?dup if drop 0 exit then をコンパイルする。
   | フラグ以外に何らかの値を置いておく。
   [compile]  not
   [postpone] if
   [compile]  drop
   [compile]  lit
   0 ,
   [postpone] exit
   [postpone] then ;

| Private
| ------------------------------------------------------------------------------
| Retroを参考にしたPrivateなワードの名前空間定義。
| private/ /privateで囲まれた部分でのワード定義は、外(後)からは見えなくなる。
| ただし、private中にreveal>>を使うと、それ以降のワードは外(後)からも見え、
| かつprivateなワードも使うことができる。
| 制限として、reveal>>の次はコロン定義やcreateなど、ワードヘッダを定義する
| ものから始める必要がある。
|
| <例>
| private/
|    : yo  ." yo!" ;
|    reveal>>
|    : greeting  yo ;
| /private
| yo        ( Notfound... )
| greeting  ( => yo!      )
|
| <実装>
| - private/ で、その時点でのlatestを保存する。reveal-startを0にクリア。
| - reveal>> で、その時点での辞書アドレスをreveal-startに保存する。
|   制限は、ここにlatestを変更すべきワードが来ることを期待するためにある。
| - /privateで、reveal-startが0ならばそのままlatestを戻す。
|   0でなければ、revealを開始すべき最初のワードのlatestを、保存しておいた
|   latestで書き換える。これによってprivate部分を飛ばすことができる。

var: private-latest
var: reveal-start

: private/  ( -- )  latest @ private-latest !  0 reveal-start ! ;
: reveal>>  ( -- )  here @ cell-align reveal-start ! ;
: /private  ( -- )
   private-latest @
   reveal-start @  ?dup if ! exit then  latest ! ;


| Stack Maker
| ------------------------------------------------------------------------------
| サイズ(バイト数)を指定してスタックを作れる。スタックの1セルは8byte固定。
| スタックはアドレスが大きい方向に伸びる。push, pop 用のワードも定義できる。
| TODO: under/overのエラー処理
|
| <例>
| 30 cells make-stack: astack asp apush apop    ( stack, sp, push, popの順番 )
| 50 apush
| 30 apush
| apop .      ( => 30 )
| apop .      ( => 50 )

private/
   var: stack
   var: sp
   : create-stack  ( n -- )
      create  here @ stack !  allot ;

   : create-sp  ( n -- )
      create  here @ sp !  stack @ ,  does> @ ;

   : create-push  ( -- )
      create  sp @ ,
      does>  @ ( n &sp -- )
         swap over  ( &sp n &sp )
         @          ( &sp n sp  )
         !          ( &sp       )
         8 swap +! ;

   : create-pop  ( -- )
      create  sp @ ,
      does>  @ ( &sp -- n )
         dup        ( &sp &sp )
         8 swap -!  ( &sp     )
         @          ( sp      )
         @          ( n       ) ;
   reveal>>
   : make-stack:  ( n -- )
      create-stack create-sp create-push create-pop ;
/private


| Structure Closer Stack (SCS)
| ------------------------------------------------------------------------------
| クォーテーションや配列リテラルなどコードに構造を与えるとき、endなどの共通な
| ワードでその構造を閉じるために使う。
| 閉じるワード end ] } などは、すべてimmediateワード。
| <例>
| : closer  ( noop ) ;
| : start   ' closer scs-push ;
| start  ...  end

private/
   8 cells make-stack:  scs-stack scs-sp scs-push scs-pop

   : scs-closer:  ( -- )
     create  ( noop )  [postpone] immediate
     does>   drop scs-pop call ;

reveal>>
   : scs-push  ( a -- )  >code scs-push ;

   scs-closer: end
   scs-closer: }
   scs-closer: ]

   | "]" を利用している実行モード切り替えを再定義
   : compile-mode  ( -- )  1 state ! ;
   : [  immediate  ( -- )  0 state !  ' compile-mode scs-push ;
/private


| Record
| ------------------------------------------------------------------------------
| Reforthを参考にした、名前を先頭で定義できる構造体。
| <例>
| record MixedJuice
|   cell field: banana
|   cell field: apple
|   cell field: orange
| end
| : mix  ( rec -- n )  dup banana @  over apple @  over orange @  + + ;
| MixedJuice m
| m banana @ .  ( => 0 )
| 50 m apple !
| 30 m orange !
| 20 m banana !
| mix .         ( => 100 )

private/
   create name-buff  128 allot
   var: name-len
   : buff-name   ( a u -- )   dup name-len !  name-buff block-copy ;

   : field-addr  ( &rec &o -- &field )  @ + ;

   : record-allot  ( size -- )
      4 -      | レコードサイズに、サイズ記録用の4byteは含めない。
      dup 4c,  | サイズを記録
      allot ;
   : close-record  ( size -- )
      name-buff name-len @ create-header
      [compile] create
      [compile] lit
      ,
      [compile] record-allot
      [ret] ;
reveal>>
   : record  ( -- o )
      read-token buff-name
      ' close-record scs-push
      4 ( オフセット。レコードサイズの分空けてスタート。 ) ;
   : field:  ( o u -- o )
      create over , +  ( オフセットを更新する )
      does>  field-addr ;
   : size  ( rec )  4c@ ;
/private


| C String
| ------------------------------------------------------------------------------
| Forth文字列をCのヌル終端文字列に変える。
|
| >cstr.dict  ( a u -- a )
|    文字列をhere位置にコピーして1バイトの0を足す。辞書ポインタは更新しない。
| puts  ( a -- )
|    C文字列を出力する。改行は追加しない。

private/
   : add-null-end  (       a u -- )  + 0 swap ! ;
   : copy&null+    ( src u dst -- )  2dup add-null-end  block-copy ;
reveal>>
   : >cstr.dict  (       a u -- a )  here @  copy&null+  here @ ;
   : >cstr.at    ( src u dst --   )  copy&null+ ;
   : puts  ( a -- )   begin  dup c@ ?dup  while  emit 1+  repeat  drop ;
/private


| Load
| ------------------------------------------------------------------------------
| ファイルを読み込み、そのまま解釈実行する。二重読み込みの検査などはしない。
: load  ( -- )  | #filename
   read-token >cstr.dict open-key-input ;


| System Call Numbers
| ------------------------------------------------------------------------------
: SYS-READ   0 ;
: SYS-WRITE  1 ;
: SYS-OPEN   2 ;
: SYS-CLOSE  3 ;
: SYS-BRK    12 ;


| File
| ------------------------------------------------------------------------------

private/
   create cbuff  cell allot  ( 1文字読み込むためのバッファ )

   : RONLY 0 ;
   : WONLY 1 ;
   : RDWR  2 ;

   : readc  ( fd buff -- u )
      | fdから1文字buffに読み込む
      | 読み込んだ文字数 (1 or 0) を返す。
      1 ( 文字数 )  SYS-READ  syscall-3  ( result ) ;
reveal>>
   : open-read-file  ( a u -- fd )  | 読み込み専用のopen
      >cstr.dict RONLY SYS-OPEN syscall-2 ;

   : close-file  ( fd -- r )  SYS-CLOSE syscall-1 ;

   : read-char  ( fd -- c ? )
      | fdから1文字読み込み、その文字と結果(読み込んだ文字数)を返す。
      cbuff readc  cbuff c@ swap ;

   | Examples ------------------------------------------------------------------

   : show-file  ( a u -- )
      | ファイルの中身を全て出力する
      open-read-file  ( fd )
      begin  dup read-char ( fd c ? )  while  emit  repeat  ( fd )
      close-file ;
/private


| Defer & Is
| ------------------------------------------------------------------------------
: noop    ( -- )  ;
: defer:  ( -- )  create  ' noop >code ,  does> @ call ;
: is      ( -- )  latest @ >code  read-token find >body ! ; immediate


| Loop 2
| ------------------------------------------------------------------------------
| SCSなどを使った繰り返し。
|    dotimes ... end  ( n -- )
|       ...をn回繰り返す。n回目(1..n)がスタックに積まれる。

private/
   : NEST-DEPTH  8 ;
   NEST-DEPTH cells make-stack: dtstack dtsp dtpush dtpop
   NEST-DEPTH cells make-stack: sfstack sfsp sfpush sfpop

   ( dotimes )
   : dtbegin  ( max -- )  dtpush 0 dtpush ;
   : dtcond   ( -- n ? )
      dtpop 1+ dtpop ( n max )
      dup  dtpush
      over dtpush
      over >= ;
   : dtend  ( -- )
      [postpone] repeat dtpop drop dtpop drop ;

   ( stack-foreach )
   : sfcall             (   -- a )  sfpop dup sfpush call ;
reveal>>
   : dotimes  ( n -- )
      |  dtbegin  begin  dtcond  while ... repeat  dtend
      [compile]  dtbegin
      [postpone] begin
      [compile]  dtcond
      [postpone] while
      ' dtend scs-push ; immediate

   : pick-from-under    ( n -- x )  cells ds0 swap - @ ;
   : stack-foreach  ( 'a -- )
      | ワード ( a -- ) のアドレスを取り、スタックの値を引数としてワードを実行する
      >code sfpush
      dsdepth 2 -                           ( TOSとdsdepthの分を引く )
      dup 0<  if drop sfpop drop exit then  ( スタックが空なので何もしない )
      dotimes  pick-from-under  sfcall  end  drop
      dup sfpop call ;
/private


| Debug Tools
| ------------------------------------------------------------------------------

: .s  ( -- )
   dsdepth 2 -  ( TOSとdsdepthの分を引く )
   dup 0<  if drop ." empty" cr exit then
   dotimes  pick-from-under . end  drop
   dup . cr ( TOS ) ;


private/
   var: dumpcount
   create dumpcbuff  4 cells allot

   : dump-count-reset  ( -- )  0 dumpcount ! ;

   : byte>ascii  ( c -- )
      dup 32  <  if drop [char] . exit then
      dup 126 >  if drop [char] . exit then ;

   : mem-dumpc  ( c -- )
      byte>ascii  dumpcbuff dumpcount @ +  c! ;

   : dump-ascii  ( c -- )
      mem-dumpc
      dumpcount @  15 <  if dumpcount inc! exit then
      dump-count-reset
      dumpcbuff 16 print cr ;
reveal>>
   : byte.  ( c -- )   dup 16 <  if ." 0" then . ;

   : dump  ( a u -- )
      dump-count-reset
      HEX
      dotimes  1- over + c@  dup  byte.  dump-ascii  end
      drop dumpcount @ ?dup  if 3 * spaces byte. then
      DEC drop ;
/private

private/
   : show-name  ( a -- )
      2 cells + 3 + dup ( -- a a )
      1- c@          ( -- a u )
      print space ;
   : word-list  ( a -- )
      ?dup 0=  if cr exit then
      dup show-name @ trec ;
reveal>>
   : word-list  ( -- ) latest @ word-list ;
/private


| Vocabulary
| ------------------------------------------------------------------------------
| ボキャブラリを生成する。
|
| ボキャブラリワードは、create does>によって以下のようなデータを持つ
| [ (1) ボキャブラリ呼び出し時点のlatestへのリンク(空のヘッダ分の4cell) ]
| [ (2) latest保存場所 (1 cell) ]
| [ (3) context保存場所 (1 cell) ]
|
| a) ボキャブラリを使用するだけでcontextは変更しない場合、(1)に現在のlatestを
| 書き込み、latestを(2)から読み込んでそれに書き換える。
|
| b) ボキャブラリのを作成する場合、(1)に現在のlatestを書き込み、(2)に
| (1)のアドレスを書き込み、(3)に現在のcontextを保存し、最後に
| contextを(2)のアドレスにする。
| 作成を終了する際は、contextを(3)から戻す。ボキャブラリワードはcreateの時点で
| (3)に保存したcontextのlatestになっている。
private/
   context @ const> core-context
   : >voc-latest      ( a -- a )  ;
   : >voc-ctx         ( a -- a )  4 cells + ;
   : >voc-before-ctx  ( a -- a )  5 cells + ;

   : 3ind cr 3 spaces drop ;
   : h  ( a -- a ) HEX
      ." ctx:" context @ .
      ." latest:"  latest @ .
      3ind dup dup . @ .
      3ind dup 4 cells + dup . @ .
      3ind dup 5 cells + dup . @ .
      3ind ." context:" context @ .
      3ind ." latest:" latest @ .
      word-list
      cr DEC ;

   ( ボキャブラリ使用 )
   : save-now-latest  ( a -- )  >voc-latest latest @ swap ! ;
   : update-latest    ( a -- )  >voc-ctx @  latest ! ;
   : use-voc  ( a -- )  dup save-now-latest update-latest ;

   ( ボキャブラリ作成 )
   : save-ctx-link  ( a -- )  dup >voc-latest swap >voc-ctx ! ;
   : save-now-ctx   ( a -- )  >voc-before-ctx context @ swap ! ;
   : set-now-ctx    ( a -- )  >voc-ctx context ! ;
   : prepare-voc  ( a -- )
      dup save-now-latest
      dup save-ctx-link
      dup save-now-ctx
      set-now-ctx ;
   : close-voc  ( a -- )  >voc-before-ctx @ context ! ;
reveal>>
   : vocabulary  ( -- a )
      create  here @  6 cells allot  ( -- a )
              dup prepare-voc        ( -- a )
              ' close-voc scs-push ;

   : Core  ( -- )  core-context dup  @ latest !  context ! ;
/private
