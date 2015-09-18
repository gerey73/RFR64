| メモリアロケーション
| ------------------------------------------------------------------------------

private/
   | (使用中かどうか記録するbyte + 1 cell) * SIZE を確保する
   : SIZE  256 ;
   : CELL-SIZE  9 ;
   create HEAP  SIZE cells allot
                SIZE 1 *   allot
   create LIMIT here @ ,
   : check-limit    ( a -- )
      dup LIMIT >=  if
         ." there is no more space"
         drop r> drop r> drop
     then ;
   : search-usable  ( -- a )
      | 先頭1バイトが0のセルを探し、その使用可能スペースのアドレスを返す
      HEAP begin  dup c@  while  CELL-SIZE +  check-limit  repeat  1+ ;
   : using     ( a -- )  1- 1 swap c! ;
   : not-using ( a -- )  1- 0 swap c! ;

   | テスト用
   SIZE cells make-stack: astack asp apush apop
reveal>>
   : new     (   -- a )  search-usable  dup using  ;
   : delete  ( a --   )  not-using ;

   : max-new-del  ( n -- )
      SIZE  dotimes . new   ." new: "    dup . cr  apush  end
      SIZE  dotimes . apop  ." delete: " dup . cr  delete end ;
/private
