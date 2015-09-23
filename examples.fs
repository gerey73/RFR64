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
      MAX-CELLS 2 *  dotimes
         drop new drop
      end  drop  dump-cells
      drop gc dump-cells ;
/private


| dlopen & C functions
| ------------------------------------------------------------------------------

private/
   var: handle
   var: csym
   var: word-u
   var: argc
   create word-buff  256 allot

   : close-c-library  ( -- )  ( handle @ dlclose ) ;

   : [compile-call]  immediate  ( -- )
      [compile]  over
      [compile]  =
      [postpone] if
      [compile]  drop
      [postpone] [compile]
      [postpone] exit
      [postpone] then ;

   : compile-call  ( n -- )
      0  [compile-call] c-funcall-0
      1  [compile-call] c-funcall-1
      2  [compile-call] c-funcall-2
      drop ." [Error] Wrong arg number" cr ;

   : create-caller  ( -- )  word-buff word-u @  create-header ;

   : create-call  ( -- )
      [compile] lit
      csym @ ,
      argc @ compile-call
      [ret] ;
reveal>>
   : c-library  ( -- )  | lib-path#
      read-token >cstr.dict 1 dlopen  handle !
      ' close-c-library scs-push ;

   : name:  ( -- )  | c-fname#
      read-token >cstr.dict  handle @  dlsym  csym ! ;

   : as:  ( -- )  | word-name#
      read-token  dup word-u !  word-buff block-copy
      create-caller  create-call ;

   : with:  ( -- )  | args#
      read-token  >number  ( n ? )
      not  if  drop ." [Error] Wrond number!" cr exit  then
      argc ! ;

   : sym:  ( -- )  create csym @ ,  does> @ ;

   : [now-csym]  immediate  ( -- a )  [compile] lit  csym @ , ; ( デバッグ用 )
/private


c-library /lib/x86_64-linux-gnu/libc.so.6
  name: printf  sym: &printf
                with: 1 as: printf1
                with: 2 as: printf2
  name: fflush  with: 1 as: fflush
  name: puts    with: 1 as: cputs
end

: fflush   ( -- )  0 fflush drop ;
: printf1  (   a u -- )  >cstr.dict      printf1 drop  fflush ;
: printf2  ( n a u -- )  >cstr.dict swap printf2 drop  fflush ;

: xprintf1  ( a u -- )
   >cstr.dict  1 ( xmmレジスタ数 ) freg1 &printf c-funcall-1-xmm drop
   fflush ;

: xmm.ex.setup  ( -- )  ( F: -- a b )  7 dup . >fp  10 dup . >fp  ;
: xmm.ex  ( -- )  ( F: a b -- )
   xmm.ex.setup  f+  s" + = %lf"  xprintf1 cr
   xmm.ex.setup  f-  s" - = %lf"  xprintf1 cr
   xmm.ex.setup  f*  s" * = %lf"  xprintf1 cr
   xmm.ex.setup  f/  s" / = %lf"  xprintf1 cr ;


| Curses
| ------------------------------------------------------------------------------

c-library libncurses.so.5
  name: initscr   with: 0  as: initscr
  name: endwin    with: 0  as: endwin
  name: cbreak    with: 0  as: cbreak
  name: nocbreak  with: 0  as: nocbreak
  name: echo      with: 0  as: echo
  name: noecho    with: 0  as: noecho
  name: getch     with: 0  as: getch
  name: addch     with: 1  as: addch
  name: addstr    with: 1  as: addstr
  name: move      with: 2  as: move
  name: flash     with: 0  as: flash
  name: clear     with: 0  as: clear
end

: curses-test
   initscr
   noecho cbreak
   clear
   0 0 move  s" press three keys." >cstr.dict  addstr
   1 2 move  getch addch
   2 4 move  getch addch
   3 6 move  getch addch
   4 0 move  s" press any key." >cstr.dict addstr
   getch drop flash
   echo nocbreak
   endwin ;
