: offset-space  here @  0 4c, ;
: save-offset   dup here @  swap -  swap 4c! ;

: if    ' 0branch compile  offset-space ; immediate
: else  '  branch compile  offset-space swap save-offset ; immediate
: then  save-offset ; immediate

: back-branch  ' branch compile  here @ - 4c, ;
: begin  here @ ; immediate
: until  ' 0branch compile  here @ - 4c,  ; immediate
: again  back-branch  ; immediate

