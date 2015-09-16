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
%define prev_link   0
%define f_immediate 0000_0001b
%define f_hidden    0000_0010b
%define f_inline    0000_0100b


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

    call setup_data_segment
    call code_interpreter


;; データセグメント設定
;; =================================================================================================
%define INITIAL_DATA_SEGMENT_SIZE 65536
section .text
setup_data_segment:
    push rdi

    xor rdi, rdi                ; 0, hereをraxに取得
    mov rax, 12                 ; brk
    syscall
    mov [var_here], rax
    mov [var_h0], rax

    add rax, INITIAL_DATA_SEGMENT_SIZE
    mov rdi, rax
    mov rax, 12
    syscall

    pop rdi
    ret


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
    mov  al, 'H'
    call _emit
    mov  al, 0x0A
    call _emit

    ; _printのテスト
    ; ----------------------------------------------------------------------------------------------
    mov  rsi, hmsg
    mov  rdx, hlen
    call _print

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

    ret


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
    ; 改行かEOFまでsys_readで読み込む
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

.skip:
    ; 行頭の区切り文字を飛ばす
    ; 1文字読み込む
    push rdx
    push rdi
    call _key
    pop  rdi
    pop  rdx

    ; 区切り文字ならスキップ EOF(0), 改行(0xA), スペース(0x20)
    cmp  al, 0
    je   .skip
    cmp  al, 0xA
    je   .skip
    cmp  al, 0x20
    je   .skip

.read:
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

    ; 文字数インクリメント
    inc  rdx

    ; 1文字読み込む
    push rdx
    push rdi
    call _key
    pop  rdi
    pop  rdx
    jmp .read

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


;; 算術演算
;; -------------------------------------------------------------------------------------------------
    defcode "+", f_inline, w_add
    add  rbx, [rbp + 8]
    lea  rbp, [rbp + 8]
    ret

    defcode "-", f_inline, w_sub
    sub  rbx, [rbp + 8]
    neg  rbx
    lea  rbp, [rbp + 8]
    ret

    defcode "*", f_inline, w_mul
    mov  rax, rbx
    mov  rcx, [rbp + 8]
    mul  rcx
    mov  rbx, rax
    lea  rbp, [rbp + 8]
    ret

    ;; /mod  ( a b -- div mod )
    defcode "/mod", f_inline, w_divmod
    mov  rcx, rbx
    mov  rax, [rbp + 8]
    div  rcx
    mov  [rbp + 8], rax
    mov  rbx, rdx
    ret

    defcode "mod", f_inline, w_mod
    mov  rcx, rbx
    mov  rax, [rbp + 8]
    div  rcx
    mov  rbx, rdx
    lea  rbp, [rbp + 8]
    ret

    defcode "/", f_inline, w_div
    mov  rcx, rbx
    mov  rax, [rbp + 8]
    div  rcx
    mov  rbx, rax
    lea  rbp, [rbp + 8]
    ret


;; 比較
;; -------------------------------------------------------------------------------------------------
%macro compare 1    ; opcode
    mov  rax, [rbp + 8]
    cmp  rax, rbx
    %1   bl
    movzx rbx, bl
    lea  rbp, [rbp + 8]
    ret
%endmacro

    defcode "=", f_inline, w_equ
    compare sete

    defcode "<>", f_inline, neq
    compare setne

    defcode ">", f_inline, gt
    compare setg

    defcode "<", f_inline, lt
    compare setl

    defcode ">=", f_inline, ge
    compare setge

    defcode "<=", f_inline, le
    compare setle


%macro zcompare 1
    cmp  rbx, 0
    %1   bl
    movzx rbx, bl
    ret
%endmacro

    defcode "0=", f_inline, zequ
    zcompare sete

    defcode "0<>", f_inline, zneq
    zcompare setne

    defcode "0>", f_inline, zgt
    zcompare setg

    defcode "0<", f_inline, zlt
    zcompare setl

    defcode "0>=", f_inline, zge
    zcompare setge

    defcode "0<=", f_inline, zle
    zcompare setle


;; ビット比較・操作
;; -------------------------------------------------------------------------------------------------
    defcode "and", f_inline, wand
    mov  rax, [rbp + 8]
    and  rbx, rax
    lea  rbp, [rbp + 8]
    ret

    defcode "or", f_inline, wor
    mov  rax, [rbp + 8]
    or   rbx, rax
    lea  rbp, [rbp + 8]
    ret

    defcode "xor", f_inline, wxor
    mov  rax, [rbp + 8]
    xor  rbx, rax
    lea  rbp, [rbp + 8]
    ret

    defcode "invert", f_inline, winvert
    not  rbx
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


;; >&code  ( a -- a )
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


;; >&flag  ( a -- a )
;; ヘッダアドレスを、フラグアドレスに変換する
;; rdiに入れて_flagaddrをコールすると、rdiに結果が返る。
    defcode ">&flag", 0, to_addr_flag
    DPOP rdi
    call _flagaddr
    DPUSH rdi
    ret
_flagaddr:
    add  rdi, 16    ; Link(8) + Code(8)
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
    mov  rbx, [var_latest]    ; 検索開始位置
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

    ; フラグがhiddenなら飛ばす
    push rax
    xor  rax, rax
    mov  rdi, rbx
    call _flagaddr
    mov  al, [rdi]
    and  al, f_hidden
    cmp  al, 0
    pop  rax
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

;; jump  ( a -- )
;; 絶対アドレスaにjmpする。
    defcode "jump", 0, jump_absolute
    DPOP rax
    jmp  rax
    ret

;; branch  ( -- )
;; ワードbranchへのcallの次4byteをオフセットとして取得し、相対ジャンプを行う。
;; オフセット開始点は、オフセット値が入っている辞書アドレスから。(call branchの元のリターン先から)
    defcode "branch", 0, branch
    pop  rax           ; オフセットアドレスが入っている / 相対ジャンプの開始点
    xor  rcx, rcx
    mov  ecx, [rax]    ; オフセット

    ; オフセットを加算してジャンプする
    ; popしているのでretする必要無し
    add  eax, ecx
    jmp  rax

;; 0branch  ( x -- )
;; スタックトップが0ならbranch、そうでなければオフセットを飛ばしてそのまま進む。
    defcode "0branch", 0, zbranch
    DPOP rax
    cmp  rax, 0
    je   code_branch

    ; スキップ
    pop  rax
    add  rax, 4    ; オフセットアドレスを飛ばす
    jmp  rax       ; 次へ

;; [  ( -- )
;; executeモードに切り替える
    defcode "[", f_immediate, execute_mode
    xor  rax, rax
    mov  [var_state], rax
    ret

;; ]  ( -- )
;; compileモードに切り替える
    defcode "]", 0, compile_mode
    mov  rax, 1
    mov  [var_state], rax
    ret


;; メモリ操作
;; -------------------------------------------------------------------------------------------------
    defcode "@", f_inline, fetch
    mov rbx, [rbx]
    ret

    defcode "!", f_inline, store
    mov  rax, [rbp + 8]
    mov  [rbx], rax
    lea  rbp, [rbp + 16]
    mov  rbx, [rbp]
    ret

    defcode "+!", f_inline, add_store
    mov  rax, [rbp + 8 ]    ; 足す数値
    mov  rcx, [rbx]         ; メモリの内容
    add  rcx, rax
    mov  [rbx], rcx
    lea  rbp, [rbp + 16]
    mov  rbx, [rbp]
    ret

    defcode "-!", f_inline, sub_store
    mov  rax, [rbp + 8 ]    ; 足す数値
    mov  rcx, [rbx]         ; メモリの内容
    sub  rcx, rax
    mov  [rbx], rcx
    lea  rbp, [rbp + 16]
    mov  rbx, [rbp]
    ret

    defcode "c@", f_inline, byte_fetch
    xor  rax, rax
    mov  al, [rbx]
    mov  rbx, rax
    ret

    defcode "c!", f_inline, byte_store
    xor  rax, rax
    mov  rcx,  [rbp + 8]
    mov  al, cl
    mov  [rbx], rax
    lea  rbp, [rbp + 16]
    mov  rbx, [rbp]
    ret

    defcode "4c@", f_inline, byte4_fetch
    xor rax, rax
    mov eax, [rbx]
    mov rbx, rax
    ret

    defcode "4c!", f_inline, byte4_store
    xor  rax, rax
    mov  ecx,  [rbp + 8]
    mov  eax, ecx
    mov  [rbx], eax
    lea  rbp, [rbp + 16]
    mov  rbx, [rbp]
    ret


;; 辞書操作
;; -------------------------------------------------------------------------------------------------
;; lit  ( -- n )
;; 辞書で call code_lit の次の位置にある8バイトをスタックに置く
    defcode "lit", 0, lit
    pop   rdi
    mov   rax, [rdi]
    add   rdi, 8
    push  rdi
    DPUSH rax
    ret

;; ,  ( n -- )
;; 辞書に値n(8bytes)を置いて、辞書ポインタを更新
    defcode ",", 0, comma
    DPOP rax
    mov  rdi, [var_here]
    mov  [rdi], rax
    add  rdi, 8
    mov  [var_here], rdi
    ret

;; c,  ( n -- )
;; 辞書に値n(1byte)を置いて、辞書ポインタを更新
    defcode "c,", 0, bytecomma
    DPOP rax
    xor  rcx, rcx
    mov  cl, al
    mov  rdi, [var_here]
    mov  [rdi], cl
    inc  rdi
    mov  [var_here], rdi
    ret

;; 4c,  ( n -- )
;; 辞書に値n(4byte)を置いて、辞書ポインタを更新
    defcode "4c,", 0, byte4comma
    DPOP rax
    xor  rcx, rcx
    mov  ecx, eax
    mov  rdi, [var_here]
    mov  [rdi], ecx
    add  rdi, 4
    mov  [var_here], rdi
    ret


;; compile  ( a -- )
;; ワードのヘッダアドレスaから、そのワードへのcallを現在の辞書にコンパイルする。
;; raxにコードアドレスを入れ、_compileをコールしても使える。rdiに現在の辞書アドレスが入って返る。
    defcode "compile", 0, compile_word
    DPOP rdi
    call _codeaddr
    mov  rax, rdi
    mov  rax, [rax]

_compile:
    ; rdi以外のレジスタ退避
    push rcx
    push rax

    mov  rdi, [var_here]    ; 辞書ポインタ
    xor  rcx, rcx
    ; callのオフセットは E8 XX XX XX XX の5バイト先から
    mov  rcx, rdi
    add  rcx, 5
    sub  rax, rcx

    ; call命令追加
    xor  rcx, rcx
    mov  cl, 0xE8
    mov  [rdi], cl
    inc  rdi

    ; オフセット設置
    mov  [rdi], eax
    add  rdi, 4

    ; 辞書ポインタ更新
    mov  [var_here], rdi

    ; レジスタ復帰
    pop  rax
    pop  rcx
    ret


;; compile-call  ( a -- )
;; 絶対アドレスaへのcallをコンパイルする。
    defcode "compile-call", 0, compile_addr
    DPOP rax
    call _compile
    ret


;; '  ( -- )
;; 次のワード名のヘッダアドレスをスタックに置く
;; コンパイルモードの場合は、lit addr の形にコンパイルする
    defcode "'", f_immediate, tick
    call code_read_token    ; ( -- a u )
    call code_find          ; ( -- a )
    cmp  rbx, 0
    je   .notfound

    ; コンパイルモードの場合
    mov  rcx, [var_state]
    cmp  rcx, 1
    je   .compile

    ; 実行モードの場合、そのまま置いて終了
    ret

.notfound:
    ; ワード名が見つからなかった場合、そのまま終了
    ; TODO: エラーメッセージ表示
    ret

.compile:
    ; rbxにワードのヘッダアドレスが入っている
    mov  rax, code_lit
    call _compile

    ; ワードアドレス設置
    mov  [rdi], rbx
    add  rdi, 8

    ; TOS更新
    lea  rbp, [rbp - 8]
    mov  rbx, [rbp]

    ; 辞書ポインタ更新
    mov  [var_here], rdi

    ret


;; create-header  ( a u -- )
;; 渡されたワード名のヘッダを作成する。
    defcode "create-header", 0, create_header
    DPOP rdx
    DPOP rsi
    push rbx    ; TOS退避

    ; 辞書ポインタ取得
    mov  rdi, [var_here]

    ; latest更新
    mov  rax, [var_latest]
    mov  [rdi], rax
    mov  [var_latest], rdi
    add  rdi, 8

    ; コード開始アドレスをr8に保存しておく
    mov  r8, rdi
    add  rdi, 8

    ; フラグとサイズを0にセット
    xor  rax, rax
    mov  [rdi], ax
    add  rdi, 2

    ; ワード名の長さをセット
    mov  [rdi], dl
    inc  rdi

    ; ワード名をコピー
    push rdi
    mov  rcx, rdx    ; 長さ
    rep movsb        ; コピー先: rdi, コピー元: rsi
    pop  rdi
    add  rdi, rdx    ; 辞書ポインタを更新

    ; 辞書ポインタを64bit境界にアライメント
    add  rdi, 7
    and  rdi, ~7

    ; コード開始アドレスを保存
    mov  [r8], rdi

    ; 辞書ポインタ更新
    mov  [var_here], rdi

    pop  rbx    ; TOSを戻す
    ret


;; immediate  ( -- )
;; latestワードのimmediateフラグをトグルする。
    defcode "immediate", f_immediate, immediate
    mov  rdi, [var_latest]
    call _flagaddr
    mov  al, [rdi]
    xor  al, f_immediate
    mov  [rdi], al
    ret

;; hidden  ( -- )
;; latestワードのhiddenフラグをトグルする。
    defcode "hidden", 0, hidden
    mov  rdi, [var_latest]
    call _flagaddr
    mov  al, [rdi]
    xor  al, f_hidden
    mov  [rdi], al
    ret

;; :  ( -- )
;; コロン定義開始
    defcode ":", 0, colon_start
    call code_read_token
    call code_create_header
    call code_hidden
    call code_compile_mode
    ret


;; ;  ( -- )
;; コロン定義終了
    defcode ";", f_immediate, colon_end
    call code_execute_mode
    call code_hidden

    ; ret命令(0xC3)をコンパイルする
    mov  rdi, [var_here]
    mov  al, 0xC3
    mov  [rdi], al
    inc  rdi
    mov  [var_here], rdi

    ret


;; VAR & DOES
;; -------------------------------------------------------------------------------------------------
;; CREATE, DOES>, VAR などを作るためのルーチン

;; DOVAR
;; ワード: DOVARのアドレスを置く
;; コード: DOVARへのコールの戻りアドレス、CREATEでallotする場所をスタックに積む。
    defcode "DOVAR", 0, const_DOVAR
    mov  rax, DOVAR
    DPUSH rax
    ret

DOVAR:
    pop  rax
    DPUSH rax
    ret


;; DODOES
;; ワード: DODOESのアドレスを置く
;; コード: 二段階のcallによって使う。CREATEで作ったワードのコード(A)を、DOES>時点の
;; 辞書アドレス(B)へのcallに上書きする。BにDODOESへのcallをコンパイルする。
;; DODOES時点でcallスタックは A -> B -> (DODOES) となっている。Aのリターン先がCREATEでの保存場所
;; なので、それを取り出しスタックに積む。そしてBに戻ればDOES>用の動作となる。
    defcode "DODOES", 0, const_DODOES
    mov  rax, DODOES
    DPUSH rax
    ret

DODOES:
    pop  rdi    ; 戻り先
    pop  rax    ; CREATEの次
    DPUSH rax
    push rdi
    ret


;; システム操作
;; -------------------------------------------------------------------------------------------------
    defcode "bye", 0, bye
    xor  rdi, rdi  ; 終了コード
    mov  rax, 60   ; sys_exit
    syscall


;; インタープリタ
;; -------------------------------------------------------------------------------------------------
;; space  ( -- )
    defcode "space", 0, space
    mov  rax, ' '
    call _emit
    ret


;; cr  ( -- )
    defcode "cr", 0, cr
    mov  rax, 0xA
    call _emit
    ret


;; . ( n -- )
;; スタックトップの数値をvar_base進数で表示する。1-16進数が表示可能。
    defcode ".", 0, dot
    DPOP rax               ; 数値
    push rbx               ; TOSを退避
    xor  rcx, rcx          ; 桁数カウント
    mov  r8, [var_base]    ; n進数

    cmp  rax, 0
    jge  .dot

    ; 負なので符号を表示
    push rax
    push rcx
    push r8
    mov  al, '-'
    call _emit
    pop  r8
    pop  rcx
    pop  rax
    neg  rax

.dot:
    xor  rdx, rdx    ; 上位桁
    div  r8
    push rdx         ; 最下位桁をpush
    inc  rcx         ; 桁数を更新

    ; 終了判定
    cmp  rax, 0
    jne  .dot

.print:
    pop  rax        ; 最上位桁をpop
    dec  rcx

    cmp  rax, 10    ; 10以上なら、アルファベットで表示
    jge  .alphabet

    add  rax, '0'
    jmp  .loop

.alphabet:
    add  rax, 0x37    ; 'A' - 10
    jmp .loop

.loop:
    push rcx
    call _emit
    pop  rcx
    cmp  rcx, 0
    jne .print

.end:
    pop  rbx    ; TOSを戻す
    call code_space
    ret


;; >number  ( a u -- n flag )
;; 文字列を数字として処理する。大文字A-Zを使った1-16進数が使用可能。var_baseの値で何進数か指定する。
;; rsiにアドレス、rdxに長さを指定して_to_numberをコールすると、raxに数値、rcxにフラグが返る。
;; flagが0なら解釈失敗。
    defcode ">number", 0, to_number
    DPOP rdx
    DPOP rsi
    call _to_number
    DPUSH rax
    DPUSH rcx
    ret

_to_number:
    push rbx    ; TOSを退避

    ; 数値、ベース
    xor  rax, rax          ; 数値
    mov  r8, [var_base]    ; ベース

    ; 符号を判定
    xor  rcx, rcx
    mov  bl, '-'
    mov  cl, [rsi]
    cmp  cl, bl
    je   .min

    ; 符号を表す数値を置く。0なら負、それ以外なら正の数とする。
    mov  rbx, 1
    push rbx

.read:
    ; 文字取得
    xor  rcx, rcx
    mov  cl, [rsi]

    ; アスキーコード'0'未満
    mov  bl, '0'
    cmp  cl, bl
    jb   .notnumber

    ; アスキーコード'0'-'9'  '9'は0x39
    mov  bl, 0x3A
    cmp  cl, bl
    jb   .ascii_num

    ; アスキーコード 0x39以上、0x41未満  'A'は0x41
    mov  bl, 0x41
    cmp  cl, bl
    jb   .notnumber

    ; アスキーコード 'G'以上
    mov  bl, 'G'
    cmp  cl, bl
    jge  .notnumber

.ascii_char:
    ; アスキーコード A - F の場合
    mov  bl, 'A'
    sub  cl, bl
    add  cl, 10
    add  rax, rcx
    jmp  .next

.ascii_num:
    ; アスキーコード 0 - 9 の場合
    mov  bl, '0'
    sub  cl, bl
    add  rax, rcx
    jmp  .next

.next:
    inc  rsi
    dec  rdx

    ; 残り文字数を判定
    cmp  rdx, 0
    jle .result

    ; 次の桁へ
    push rdx
    mul  r8
    pop  rdx
    jmp  .read

.min:
    ; 符号をマイナスに
    mov  rbx, 0
    push rbx
    ; 符号の分進める
    inc  rsi
    dec  rdx
    jmp  .read

.result:
    ; フラグを設定
    mov  rcx, 1

    ; 符号を与える
    pop  rbx
    cmp  rbx, 0
    jne  .end
    neg  rax
    jmp  .end

.notnumber:
    ; 数字として解釈できなかった
    pop  rax         ; 符号を取り除く
    xor  rax, rax
    xor  rcx, rcx

.end:
    pop  rbx
    ret


;; eval-word  ( a -- ... )
;; ワードのヘッダアドレスを受け取り、モードに合わせて処理する
    defcode "eval-word", 0, eval_word
    mov  rax, rbx    ; TOSのワードアドレスを保存
    push rax

    ; コードアドレスに変換
    call code_to_addr_code
    call code_fetch
    DPOP rax

    pop  rdi    ; ヘッダアドレスを戻す

    ; executeモードならそのまま実行
    mov  rdx, [var_state]
    cmp  rdx, 0
    je   .execute

    ; immediateワードなら実行
    call _flagaddr    ; rdiをフラグのアドレスに
    xor  rcx, rcx
    mov  cl, [rdi]    ; フラグを取得
    and  cl, f_immediate
    cmp  cl, 0
    jne  .execute

    ; それ以外ならコンパイル
    jmp  .compile

.execute:
    DPUSH rax
    call code_call_absolute
    ret

.compile:
    ; raxにコードアドレスが入っているので、そのアドレスへのcallをコンパイルする。
    call _compile
    ret


;; eval-number  ( n -- ... )
;; モードに合わせて数字を処理する。コンパイルモードの場合、 call lit [8byte] の形にコンパイルする。
    defcode "eval-number", 0, eval_number
    ; compileモード
    mov  rdx, [var_state]
    cmp  rdx, 1
    je   .compile

    ; executeモードならそのままスタックに置いておく
    ret

.compile:
    ; E8 [ litのアドレス ] にコンパイルする
    mov  rax, code_lit
    call _compile    ; rdiに辞書の最新位置が入ってくる

    ; 数値を辞書に置く
    DPOP rax
    mov  [rdi], rax
    add  rdi, 8

    ; 辞書ポインタ更新
    mov  [var_here], rdi

    ret


;; eval-token  ( a u -- ... )
;; トークンをモードに合わせて処理する
word_notfound_msg: db "Word not found: "
word_notfound_len  equ $ - word_notfound_msg

    defcode "eval-token", 0, eval_token
    DPOP rdx
    DPOP rsi

    ; find
    push rdx    ; 名前を退避
    push rsi
    call _find
    pop  rsi    ; 名前を戻す
    pop  rdx

    cmp  rax, 0
    jne  .found

    ; ワードが見つからなかった場合
    ; とりあえず数字として処理
    push rdx
    push rsi
    call _to_number
    pop  rsi
    pop  rdx
    cmp  rcx, 0
    je   .notfound    ; 数字としても処理できなかった

    DPUSH rax
    call  code_eval_number
    jmp   .end

.found:
    ; ワードが見つかった
    DPUSH rax
    call code_eval_word
    jmp .end

.notfound:
    ; 数字としても処理できなかった場合
    push rdx
    push rsi
    mov  rsi, word_notfound_msg
    mov  rdx, word_notfound_len
    call _print    ; "Word not found: "
    pop  rsi
    pop  rdx
    call _print        ; ワード名出力
    mov  rax, 0xA      ; 改行
    call _emit

.end:
    ret


;; interpreter  ( -- )
;; READ-EVAL-LOOP
    defcode "interpreter", 0, interpreter
.loop:
    call code_read_token
    call code_eval_token
    jmp  .loop


;; 変数
;; -------------------------------------------------------------------------------------------------
    defcode "latest", 0, v_latest
    mov  rax, var_latest
    DPUSH rax
    ret

    defcode "state", 0, v_state
    mov  rax, var_state
    DPUSH rax
    ret

    defcode "here", 0, v_here
    mov  rax, var_here
    DPUSH rax
    ret

    defcode "base", 0, v_base
    mov  rax, var_base
    DPUSH rax
    ret

section .data

var_state: dq 0     ; 0: execute, 1: compile
var_base:  dq 10

;; リターンスタックの初期位置
var_rs0: dq 0

;; 辞書アドレス
var_here: dq 0
var_h0:   dq 0

var_latest: dq prev_link

section     .bss
alignb 8

;; <データスタック>
;; rbpがdata_stack_emptyを指している場合、スタックの内容は空。
;; スタックに1つデータを入れた場合、rbxがTOS、rbpはdata_stack_secondを指す。
;; 以降、pushごとにアドレス下位方向に伸びていく。
data_stack:        resb 256
data_stack_second: resb 8
data_stack_empty:  resb 8
