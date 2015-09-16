: offset-space  here @  0 4c, ;
: save-offset   dup here @  swap -  swap 4c! ;

: if    ' 0branch compile  offset-space ; immediate
: else  '  branch compile  offset-space swap save-offset ; immediate
: then  save-offset ; immediate
