: cell   8 ;
: cells  cell * ;
: allot  here +! ;

: DEC  10 base ! ;
: HEX  16 base ! ;

: offset-space  here @  0 4c, ;
: save-offset   dup here @  swap -  swap 4c! ;

: [postpone]  read-token find compile ; immediate

: if    ' 0branch compile  offset-space ; immediate
: else  '  branch compile  offset-space swap save-offset ; immediate
: then  save-offset ; immediate

: back-branch  ' branch compile  here @ - 4c, ;
: begin  here @ ; immediate
: until  ' 0branch compile  here @ - 4c,  ; immediate
: again  back-branch  ; immediate

: while   [postpone] if ; immediate
: repeat  swap back-branch  save-offset ; immediate
