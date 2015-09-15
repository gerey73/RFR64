;; <スレッディング>
;; callによるサブルーチンスレッディング
;; <スタック>
;; リターンスタックはcall用のものをそのまま使う。(rspレジスタ)
;; データスタックはrbxをTOS、スタックポインタにrbpを使う。1cellは64bit。アドレス下位方向に伸びる。
;; <ワードのメモリ配置>
;; - Link (8bytes)
;; - Code Address (8bytes)
;; - Flags (1byte)
;; - Code Size (1byte)  インライン展開用
;; - Name Length (1byte)
;; - Name (n bytes)
;; - Definition (マシンコード)
;; Definitionが64bit境界から始まるように、Nameの後を0paddingする。
;; <ワードのフラグ>
;; 下位ビットから
;; - immediate
;; - hidden
;; - inline


extern	dlopen
extern  dlclose
extern  dlerror
extern  dlsym


;; Latest(prev_link)とフラグ
;; -------------------------------------------------------------------------------------------------
%define     prev_link 0
%define     f_immediate 0000_0001b
%define     f_hidden    0000_0010b
%define     f_inline    0000_0100b


;; マクロ定義
;; =================================================================================================

%macro DPUSH 1
    mov  [rbp], rbx
    lea  rbp, [rbp - 8]
    mov  rbx, %1
%endmacro

%macro DPOP 1
    mov  %1, rbx          ; TOSをレジスタに
    lea  rbp, [rbp + 8]
    mov  rbx, [rbp]       ; 2番目をTOSに
%endmacro

    
;; Entry Point
;; =================================================================================================
    global      main
main:
    cld

    ;; リターンスタックの初期位置を保存
    mov  [var_rs0], rsp         

    ;; データスタックを空に
    mov  rbp, data_stack_empty ; データスタックを空に
    xor  rbx, rbx

    call set_up_data_segment    
    call cold_start


cold_start:
    call code_testcode


;; Word Defining Macro
;; =================================================================================================
%macro defcode 3 ; name, flags, label

%strlen namelen %1

section .rodata
align 8

global header_%3
    header_%3:
    dq prev_link
    dq code_%3
%define prev_link header_%3
    db %2
    db 0
    db namelen
    db %1

align 8
section .text
global  code_%3
    code_%3:
%endmacro


;; =================================================================================================
;; Native Word Definition
;; =================================================================================================

;; テストコード
;; -------------------------------------------------------------------------------------------------
    section .data
    hmsg db  'Hello, world!', 0xa
    hlen equ $ - hmsg

    defcode "helloworld", 0, helloworld
    mov  rsi, hmsg
    mov  rdx, hlen
    call _print
    ret

    defcode "testcode", 0, testcode
    ; _emitのテスト
    ; ----------------------------------------------------------------------------------------------
    ; mov  al, 'H'
    ; call _emit
    ; mov  al, 0x0A
    ; call _emit

    ; _printのテスト
    ; ----------------------------------------------------------------------------------------------
    ; mov  rsi, hmsg
    ; mov  rdx, hlen
    ; call _print

    ; _keyのテスト 2回読み込み出力するので、1文字入力+改行して、1文字1行になることを確かめる
    ; ----------------------------------------------------------------------------------------------
    ; call _key
    ; call _emit
    ; call _key
    ; call _emit

    ; read-token、find、>&codeのテスト  ワード名を読み込んで実行する。(helloworld推奨)
    ; ----------------------------------------------------------------------------------------------
    call code_read_token
    call code_find
    call code_to_addr_code
    call code_fetch
    call code_call_absolute

    ; スタック操作のテスト yo!!(改行)と表示する
    ; ----------------------------------------------------------------------------------------------
    xor  rax, rax
    mov  al, 0xA    ; 改行
    DPUSH rax

    ; 改行を表示
    call code_dup
    call code_emit

    mov  al, '!'
    DPUSH rax
    call code_dup   ; !!
    
    xor  rax, rax
    mov  al, 'y'
    DPUSH rax

    xor  rax, rax
    mov  al, 'o'
    DPUSH rax

    ; この時点でスタックは oy!! + 改行
    call code_swap    ; yo!!
    call code_over    ; oyo!!
    call code_rrot    ; yoo!!
    call code_rrot    ; ooy!!
    call code_rrot    ; oyo!!
    call code_rot     ; ooy!!
    call code_drop    ; oy!!
    call code_swap    ; yo!!
    
    ; スタックトップから5文字表示
    call code_emit
    call code_emit
    call code_emit
    call code_emit
    call code_emit
    
    ; 終了
    ; ----------------------------------------------------------------------------------------------
    call code_bye

    
;; スタック操作
;; -------------------------------------------------------------------------------------------------
    defcode "drop", f_inline, drop
    DPOP rax
    ret
    
    defcode "swap", f_inline, swap
    mov  rax, rbx
    mov  rbx, [rbp + 8]
    mov  [rbp + 8], rax
    ret
    
    defcode "dup", f_inline, dup
    mov  [rbp], rbx
    lea  rbp, [rbp - 8]
    ret
    
;; ( x y -- x y x )
;; : over  swap dup -rot ;
    defcode "over", f_inline, over
    mov  rax, [rbp + 8]
    DPUSH rax
    ret

;; ( a b c -- b c a )
;; スタックの3番目をトップに
    defcode "rot", f_inline, rot
    mov  rcx, rbx           ; TOSをrcxに
    mov  rax, [rbp + 8]     ; 2番目をraxに
    mov  rbx, [rbp + 16]    ; 3 -> 1
    mov  [rbp + 8], rcx     ; 1 -> 2
    mov  [rbp + 16], rax    ; 2 -> 3
    ret

;; ( a b c -- c a b )
;; スタックトップを3番目に
    defcode "-rot", f_inline, rrot
    mov  rcx, [rbp + 16]    ; 3番目をrcxに
    mov  rax, [rbp + 8]     ; 2番目をraxに
    mov  [rbp + 16], rbx    ; 1 -> 3
    mov  [rbp + 8], rcx     ; 3 -> 2
    mov  rbx, rax           ; 2 -> 1
    ret

    
;; 文字入力
;; -------------------------------------------------------------------------------------------------
;; key  ( -- c ) 1バイト入力
;; _keyをコールすると、レジスタalに文字が入る
section .data
key_fd:   dq 0    ; 標準入力
key_tail: dq key_buff    ; 読み込んだ文字の末尾位置(バッファアドレス + バッファに読み込んだ文字数)
key_cur:  dq key_buff    ; 現在の読み込み位置

section .bss
key_buff: resb 4096    ; バッファサイズ
    
    defcode "key", 0, key
    xor rax, rax
    call _key
    DPUSH rax
    ret

_key:
    push rbx    ; TOS退避

.key:
    ; インプットバッファを処理済みの場合、新しく読み込む
    mov  rax, [key_cur]
    cmp  rax, [key_tail]
    jge  .read

    ; バッファに残っている場合、key_curが次の文字を指しているので読み込み、インクリメントして終了
    mov  rcx, [key_cur]
    xor  rax, rax
    mov  al, [rcx]
    inc  rcx
    mov  [key_cur], rcx
    jmp  .end

.read:
;; 改行かEOFまでsys_readで読み込む

    ; 読み込み先アドレスを指定し、key_curも先頭に戻す
    mov  rsi, key_buff
    mov  [key_cur], rsi

.input:
;; 改行かEOFまで1文字ずつ読み込む
    mov  rdi, [key_fd]    ; 読み込み元
    mov  rdx, 1           ; 1文字
    xor  rax, rax         ; sys_read
    syscall

    ; 読み込んだ文字数(rax)が0以下ならEOF
    cmp  rax, 0
    jle  .eof

    ; 読み込んだ最初の文字をレジスタに
    xor  rcx, rcx
    mov  cl, [rsi]

    ; key_tailを更新
    add  rsi, rax    ; バッファアドレス + 読み込んだ文字数
    mov  [key_tail], rsi

    ; 改行かEOFまで読み込み続ける
    cmp  cl, 0xA
    jne  .input

    ; バッファを更新したので、1文字返す
    jmp  .key

.eof:
    ; 読み込み元が標準入力(0)以外なら閉じる
    mov  rdi, [key_fd]
    cmp  rdi, 0
    je   .close
    
    ; 読み込めなかった事を表す0を返す
    xor  rax, rax
    jmp  .end

.close:
    ; 読み込み元ファイルを閉じて、再び改行かEOFまでread
    mov  rdi, [key_fd]
    mov  rax, 3          ; close
    syscall
    
    ; とりあえず標準入力に戻す
    xor  rax, rax
    mov  [key_fd], rax
    jmp  .read
    
.end:
    pop  rbx    ; TOSを戻す
    ret


;; read-token  ( -- a u )
;; スペース、改行、EOFで区切られたトークンを読み込む。_keyを使って1文字ずつ読み込む。
;; _read_tokenをコールすると、rsiにアドレス、rdxに長さが返る。
%define MAX_TOKEN_SIZE 256
section .bss
token_buff: resb MAX_TOKEN_SIZE

    defcode "read-token", 0, read_token
    call _read_token
    DPUSH rsi
    DPUSH rdx
    ret

_read_token:
    push rbx             ; TOSを退避
    xor  rdx, rdx        ; 長さ
    mov  rdi, token_buff ; 現在の位置

.read:
    ; 1文字読み込む
    push rdx
    push rdi
    call _key
    pop  rdi
    pop  rdx

    ; 区切り文字かどうかにかかわらず、バッファにコピーする
    mov  [rdi], al
    inc  rdi          ; 次の位置へ

    ; 区切り文字なら終了 EOF(0), 改行(0xA), スペース(0x20)
    cmp  al, 0
    je   .end
    cmp  al, 0xA
    je   .end
    cmp  al, 0x20
    je   .end

    ; 文字数をインクリメントして、次の文字へ
    inc  rdx
    jmp  .read
    
.end:
    mov  rsi, token_buff
    pop  rbx    ; TOSを戻す
    ret

    
;; 文字出力
;; -------------------------------------------------------------------------------------------------
;; emit  ( c -- )  1バイト出力
;; レジスタalに1バイト入れて_emitをコールすると、他の組み込みワードからも使える。
section .data
emit_buff: dq 0

    defcode "emit", 0, emit
    xor rax, rax
    DPOP rax
    call _emit
    ret
    
_emit:
    mov [emit_buff], al   ; sys_writeのために文字をメモリに置いておく。
    
    push rbx                  ; TOS退避
    mov  rdi, 1            ; stdout
    mov  rsi, emit_buff
    mov  rdx, 1            ; 1バイト出力
    mov  rax, 1            ; sys_write
    syscall
    pop  rbx                   ; TOSを戻す
    ret

    
;; print  ( a u -- )  文字列出力
;; レジスタrsiにアドレス、rdxに長さを入れて_printをコールすると、他の組み込みワードからも使える。
    defcode "print", 0, print
    DPOP  rdx
    DPOP  rsi
    call _print
    ret

_print:
    push rbx      ; TOS退避
    mov  rdi, 1   ; stdout
    mov  rax, 1   ; sys_write
    syscall
    pop  rbx      ; TOSを戻す
    ret

    
;; Forth処理系関連
;; -------------------------------------------------------------------------------------------------
;; >&namelen  ( a -- a )
;; ヘッダアドレスを、ワード名の長さを記録するアドレスに変換する。
;; rdiに入れて_namelenをコールすると、rdiに結果が返る。
    defcode ">&namelen", 0, to_addr_namelen
    DPOP rdi
    call _namelen
    DPUSH rdi
    ret
_namelen:
    add  rdi, 18    ; Link(8) + Code(8) + Flags(1) + Size(1)
    ret

;; >&name  ( a -- a )
;; ヘッダアドレスを、ワード名のアドレスに変換する。
;; rdiに入れて_nameaddrをコールすると、rdiに結果が返る。
    defcode ">&name", 0, to_addr_name
    DPOP rdi
    call _nameaddr
    DPUSH rdi
    ret
_nameaddr:
    call _namelen
    add  rdi, 1    ; NameLen(1)
    ret
    
    
;; >&code-addr  ( a -- a )
;; ヘッダアドレスを、コードアドレスに変換する
;; rdiに入れて_codeaddrをコールすると、rdiに結果が返る。
    defcode ">&code", 0, to_addr_code
    DPOP rdi
    call _codeaddr
    DPUSH rdi
    ret
_codeaddr:
    add  rdi, 8    ; Link(8)
    ret

    
;; find  ( a u -- a? )
;; ワードのヘッダアドレスを探して返す。
;; rsiにアドレス、rdxに長さを入れて_findをコールすると、raxに結果が返る。
    defcode "find", 0, find
    DPOP rdx
    DPOP rsi
    call _find
    DPUSH rax
    ret

_find:
    push rbx              ; TOS退避
    mov  rbx, [latest]    ; 検索開始位置
    mov  rcx, rdx         ; 長さをrcxに
    
.find:
    ; 長さが同じかどうか調べる
    xor  rax, rax
    mov  rdi, rbx    ; 検索対象
    call _namelen    ; rdiに長さのアドレスが返ってくる
    mov  al, [rdi]
    cmp  al, cl
    jne  .next       ; 長さが違うので次へ

    ; repeを使って名前が一致するか調べる
    ; rsiとrdiに開始アドレス、rcxに長さを入れる
    mov  rdi, rbx
    call _nameaddr   ; rdiに名前の位置が返ってくる
    push rsi
    push rcx
    repe cmpsb
    pop  rcx
    pop  rsi

    ; 一致しなかったので次へ
    jne  .next

    ; 一致したので、ヘッダアドレスを返す
    mov  rax, rbx
    jmp  .end
    
.next:
    mov  rbx, [rbx]    ; 次のワードへ。Linkは先頭
    cmp  rbx, 0        ; まだ検索対象があれば、続ける
    jne  .find
    
    ; 検索対象がもう無いので、0を返す
    xor rax, rax

.end:
    pop  rbx    ; TOSを戻す
    ret


;; call  ( a -- )
;; 絶対アドレスaをcallする。
    defcode "call", 0, call_absolute
    DPOP rax
    call rax
    ret


;; メモリ操作
;; -------------------------------------------------------------------------------------------------
    defcode "@", f_inline, fetch
    mov rbx, [rbx]
    ret

    defcode "!", f_inline, store
    mov  rbx, [rbp + 8]
    lea  rbp, [rbp + 8]
    ret
    

;; システム操作
;; -------------------------------------------------------------------------------------------------
    defcode "bye", 0, bye
    xor  rdi, rdi  ; 終了コード
    mov  rax, 60   ; sys_exit
    syscall
    

%define INITIAL_DATA_SEGMENT_SIZE 65536
section .text
set_up_data_segment:
    push rdi

    ;; データセグメント開始位置を取得
    xor  rdi, rdi   ; rdi(サイズ)が0なら開始位置を取得できる
    mov  rax, 12    ; brk
    syscall
    mov  [var_here], rax
    mov  [var_h0], rax

    ;; データセグメント確保
    add  rax, INITIAL_DATA_SEGMENT_SIZE
    mov  rdi, rax   ; サイズを指定
    mov  rax, 12    ; brk
    syscall
    
    pop  rdi
    ret


;; Data Section
;; -------------------------------------------------------------------------------------------------
section .data
;; latest
latest: dq prev_link
    
;; リターンスタックの初期位置
var_rs0: dq 0
    
;; 辞書アドレス
var_here: dq 0
var_h0:   dq 0


section     .bss

alignb 4096
    
;; <データスタック>
;; rbpがdata_stack_emptyを指している場合、スタックの内容は空。
;; スタックに1つデータを入れた場合、rbxがTOS、rbpはdata_stack_secondを指す。
;; 以降、pushごとにアドレス下位方向に伸びていく。
data_stack:        resb 256
data_stack_second: resb 8
data_stack_empty:  resb 8
