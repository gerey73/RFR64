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

;; Hello World
;; -------------------------------------------------------------------------------------------------
    section .data
    hmsg db  'Hello, world!', 0xa
    hlen equ $ - hmsg

    defcode "helloworld", 0, helloworld
    push rbx
    mov  rdi,1        ; stdout
    mov  rsi, hmsg
    mov  rdx, hlen
    mov  rax,1        ; sys_write
    syscall
    pop  rbx
    ret

    
    defcode "testcode", 0, testcode
    call code_helloworld

    ; _emitのテスト
    ; ----------------------------------------------------------------------------------------------
    mov  al, 'H'
    call _emit
    mov  al, 0x0A
    call _emit

    ; _printのテスト
    ; ----------------------------------------------------------------------------------------------
    mov  rsi, hmsg
    mov  rdx, hlen
    call _print

    ; _keyのテスト 2回読み込み出力するので、1文字入力+改行して、1文字1行になることを確かめる
    ; ----------------------------------------------------------------------------------------------
    call _key
    call _emit
    call _key
    call _emit

    ; スタック操作のテスト yo!!(改行)と表示する
    ; ----------------------------------------------------------------------------------------------
    xor  rax, rax
    mov  al, 0xA    ; 改行
    DPUSH rax

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
;; スタックの3番目をトップに持ってくる
    defcode "rot", f_inline, rot
    mov  rcx, rbx           ; TOSをrcxに
    mov  rax, [rbp + 8]     ; 2番目をraxに
    
    mov  rbx, [rbp + 16]    ; 3 -> 1
    mov  [rbp + 8], rcx     ; 1 -> 2
    mov  [rbp + 16], rax    ; 2 -> 3

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

    
;; print  ( addr len -- )  文字列出力
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
section     .bss

align 4096
    
;; リターンスタックの初期位置
var_rs0: resb 8

;; 辞書アドレス
var_here: resb 8
var_h0:   resb 8

;; <データスタック>
;; rbpがdata_stack_emptyを指している場合、スタックの内容は空。
;; スタックに1つデータを入れた場合、rbxがTOS、rbpはdata_stack_secondを指す。
;; 以降、pushごとにアドレス下位方向に伸びていく。
data_stack:        resb 256
data_stack_second: resb 8
data_stack_empty:  resb 8
