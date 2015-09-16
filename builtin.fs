: cell   8 ;
: cells  cell * ;
: allot  here +! ;

: DEC  10 base ! ;
: HEX  16 base ! ;

: ret    195 ;
: [ret]  ret c, ;
: exit   [ret] ; immediate


: [postpone]  read-token find compile ; immediate
: [compile]   ' lit compile  read-token find ,  ' compile compile ; immediate


: offset-space  here @  0 4c, ;
: save-offset   dup here @  swap -  swap 4c! ;


: if    [compile] 0branch  offset-space ; immediate
: else  [compile]  branch  offset-space swap save-offset ; immediate
: then  save-offset ; immediate


: back-branch  [compile] branch  here @ - 4c, ;
: begin  here @ ; immediate
: until  [compile] 0branch  here @ - 4c,  ; immediate
: again  back-branch  ; immediate

: while   [postpone] if ; immediate
: repeat  swap back-branch  save-offset ; immediate


: create  read-token create-header DOVAR compile-call ;
: var:    create cell allot ;
: var>    create , ;

var: here.old
: save-here       here @ here.old ! ;
: restore-here    here.old @ here ! ;
: compile-offset  save-here  here ! compile-call  restore-here ;
: (does)          latest @  >&code @  compile-offset ;
: does>
   [compile] lit  here @  cell allot  [compile] (does)  [ret]
   here @ swap !  DODOES compile-call ; immediate

: const>  create ,  does> @ ;
: >body   >&code @  5 + ;
