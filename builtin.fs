: cell   (   -- n )  8 ;
: cells  ( n -- n ) cell * ;
: allot  ( n --   ) here +! ;

: DEC  ( -- )  10 base ! ;
: HEX  ( -- )  16 base ! ;

: ret    ( -- n )  195 ;    ( 0xC3 ret命令 )
: [ret]  ( --   )  ret c, ; ( ret命令をコンパイルする )
: exit   ( --   )  [ret] ; immediate


: [postpone]  ( -- )  read-token find compile ; immediate
: [compile]   ( -- )  ( 次の命令をコンパイルするコード、をコンパイルする )
   ' lit compile  read-token find ,  ' compile compile ; immediate


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
