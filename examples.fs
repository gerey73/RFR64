| Cons Cell & Garbage Collection
| ------------------------------------------------------------------------------
| <GC>
|    ConsCell用変数でのExactGC + スタック、セル内の保守的GC。
|    Mark&Sweepを使用。
private/
reveal>>
   | (使用中かどうか記録するbyte + 1 cell) * SIZE を確保する
   : MAX-CELLS  16 ;
   : CELL-BODY  2 cells ;
   : CELL-SIZE  CELL-BODY 1 + ;

   create HEAP  MAX-CELLS CELL-SIZE * allot
   here @ const> LIMIT

   | Cell Variable -------------------------------------------------------------
   |   セル保持用の変数を宣言、記録する。
   |   変数はリンクリストになっており、辿ってmarkすることでGCを避ける。
   var: latest-cvar  0 latest-cvar !
   : cvar:  ( -- ) create ,  here @  latest-cvar @ ,  latest-cvar !  does> @ ;
   : del:   ( -- )
      read-token find >body  ( &&car )
      dup 0 swap !  ( 保持しているセルを消す )
      ( TODO: リンクを消す ) ;

   | Accessor ------------------------------------------------------------------
   : car    ( a -- a )  ( noop ) ;
   : cdr    ( a -- a )  cell + ;
   : first  ( a -- x )  ( car ) @ ;
   : rest   ( a -- x )  cdr @ ;


   | Garbage Collection --------------------------------------------------------
   : mark     ( a -- )  1 swap c! ;
   : unmark   ( a -- )  0 swap c! ;
   : marked?  ( a -- )  c@ ;

   var: marked
   : sweeped  ( -- )  MAX-CELLS marked @ - ;

   : unmark-all  ( -- )
      HEAP  begin
         dup LIMIT <
      while
         dup unmark
         CELL-SIZE +
      repeat drop ;

   : in-heap?        ( a -- ? )  HEAP LIMIT in-range? ;
   : top-of-cell?    ( a -- ? )  HEAP - CELL-SIZE divisible? ;
   : regard-as-ref?  ( a -- ? )  dup in-heap? and>> top-of-cell? ;

   : mark-recur  ( car -- )
      ( 再帰的にリンクを辿り、マークする )
      1-  ( &flag )
      dup  regard-as-ref? not  if drop exit then  ( セルではない )
      dup  marked?             if drop exit then  ( これ以上辿らなくていい )
      dup  mark  marked inc!  ."     marked: " dup . cr
      1+ dup  first recur  rest  recur ;

   : mark-from-stack  ( -- ) ' mark-recur stack-foreach ;

   : mark-from-vars ( -- )
      ( 0になるまでcvarリンクを辿り、マークしていく )
      latest-cvar @
      begin
        ?dup
      while
        dup  8 - @ mark-recur  @
      repeat ;

   : mark-refed  ( -- n )
      0 marked !
      mark-from-vars  ." Vars  marked. empty:" sweeped . cr
      mark-from-stack ." Stack marked. empty:" sweeped . cr ;

   : mark&sweep  ( -- )
      unmark-all  ." unmark-all success" cr
      mark-refed  ." mark-refed success" cr ;

   defer: search-usable

   : gc  ( --  )
      ." GC START" cr
      mark&sweep
      ." GC COMPLETE" cr cr ;

   : gc-and-allot  ( -- a )
      gc  ( ? )
      sweeped  if search-usable exit then
      ." [Error] There is no more space." cr 0
      ( TODO: 強制終了 ) ;

   | Allocation ----------------------------------------------------------------
   : check-limit  ( a -- a )  dup LIMIT <  if exit then  drop gc-and-allot ;

   : search-usable  ( -- &flag )  is search-usable
      | 先頭1バイトが0のセルを探し、返す
      HEAP begin  dup c@  while  CELL-SIZE +  check-limit  repeat ;


   | Debug ---------------------------------------------------------------------
   : dump-cells
      HEAP begin
        dup LIMIT <
      while
        dup . ."   "
        dup c@ ." FLAG:" .
        dup 1+ first ." CAR:" .
        dup 1+ rest  ." CDR:" .
        cr
        CELL-SIZE +
      repeat drop
      cr ;

( reveal>> )
   : new     (     -- a )  search-usable  dup mark 1+ ;
   : delete  ( car --   )  1- unmark ;

   : second  ( a -- x )  rest first ;
   : third   ( a -- x )  rest rest first ;

   : cons   ( cdr car -- a )  new  ( cdr car a )
      rot  over  ( car a cdr a )  cdr !  ( car a )
      swap over  ( a car a     )  car ! ;

   : map  ( &car xt -- &car )
      >r
      ( nilが無いのでセル範囲かどうかで判断する )
      dup in-heap? not  if r> call exit then
      dup rest r> dup >r recur  ( &car cdr )
      swap first r> call        ( cdr car )
      cons ;

   : map  ( &car 'word -- &car )  | word ( x -- x )
      >code map ;

   : gc-test  ( -- )
      1 2 cons 3 cons 4 cons ( 3セル確保 )
      ." BEFORE GC" cr dump-cells
      MAX-CELLS  dotimes  drop new drop  end  drop  dump-cells
      MAX-CELLS  dotimes  drop new drop  end  drop  dump-cells
      drop gc dump-cells ;
/private


| dlopen & C functions
| ------------------------------------------------------------------------------
: LIBC s" /lib/x86_64-linux-gnu/libc.so.6" ;

: c-library   ( a u -- )  | #lib-name
   >cstr.dict  1  dlopen  const> ;

: c-function  ( handle -- )  |  #c-name #f-name
   read-token >cstr.dict  swap dlsym  const> ;

LIBC c-library libc
libc c-function printf printf
libc c-function fflush fflush
libc c-function puts   cputs

: printf1  ( a u -- )
   >cstr.dict  printf  c-funcall-1
   0 fflush c-funcall-1 ;

: printf2  ( n a u -- )
   >cstr.dict swap  printf c-funcall-2
   0 fflush c-funcall-1 ;
