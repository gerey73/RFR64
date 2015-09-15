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
    lea  rbp, [rbp + 8]
    mov  rbx, [rbp]
    mov  %1, rbx
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
    mov  al, 'H'
    call _emit
    mov  al, 0x0A
    call _emit

    ; _printのテスト
    mov  rsi, hmsg
    mov  rdx, hlen
    call _print
    
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

    
;; 文字出力
;; -------------------------------------------------------------------------------------------------

;; emit  ( c -- )  1バイト出力
;; レジスタalに1バイト入れて_emitをコールすると、他の組み込みワードからも使える。
section     .data
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
