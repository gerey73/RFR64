: cell   (   -- n )  8 ;
: cells  ( n -- n ) cell * ;
: allot  ( n --   ) here +! ;

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


| 文字列
| ------------------------------------------------------------------------------
create strbuff 512 allot    ( 文字列リテラル用バッファ )

: litstr  ( -- a u )
   | コンパイルして使う。これがcallされた次の4byteに長さ、それ以降に文字列が
   | 置かれてるとして、長さとアドレスを返し、文字列部分をスキップする。
   r>
   dup 4 +   ( r a )
   over 4c@  ( r a u )
   rot 4 +   ( a u r  文字数を格納した位置を飛ばす )
   over +    ( a u r  文字数分飛ばす )
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
: reveal>>  ( -- )  here @ reveal-start ! ;
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
   var: sp
   var: stack
   : create-stack  ( n -- )
      create  here @  dup sp ! stack !  allot ;
   : create-sp  ( n -- )
      create  sp ,  does> @ @ ;

   : create-push  ( -- )
      create  ( none )
      does>  ( n a -- )  drop  sp @ !  8 sp +! ;

   : create-pop  ( -- )
      create  ( none )
      does>  ( -- n )  8 sp -!  sp @ @ ;

   reveal>>
   : make-stack:  ( n -- )
      create-stack create-sp create-push create-pop ;
/private
