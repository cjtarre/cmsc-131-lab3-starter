;
; args.asm - parse_args, the command line to a flag set, a pattern, and a
; file name. Callable from C.
;
; This is your starting point: it assembles and links as-is, so the build
; works before you write any code. Right now it returns -1, which makes
; rengrep print its usage line for every command. Nothing else runs until
; this routine works, so write it first. It is the shortest of the four.
;
; The contract, from driver.c:
;
;       struct args *out            [ebp+16]
;       char **argv                 [ebp+12]
;       int argc                    [ebp+8]
;
;       int parse_args(int argc, char **argv, struct args *out)
;
;       struct args { int flags; char *pattern; char *path; };
;                     +0         +4             +8
;
;       FLAG_N = 1, FLAG_C = 2, FLAG_V = 4, FLAG_I = 8, FLAG_W = 16
;
; Fill out and return 0. Return -1 when the pattern or the file is missing,
; or when a third positional token appears. Return the offending character,
; as a positive number, on an unknown flag. The driver prints it.
;
; Requirements from the manual:
;
;   * A token whose first byte is '-' and whose second byte is not NUL is a
;     flag group, wherever it appears. -nvi is -n -v -i. "-" alone is not a
;     flag group.
;   * Every other token is positional. The first is the pattern, the second
;     is the file.
;   * Keep the flag characters in a table, in bit order, and find each one
;     with scasb. The bit is 1 shifted left by the table index. A chain of
;     cmp/je is the structure the rubric marks down.
;   * Set cld explicitly. scasb honours the direction flag.
;   * Preserve ebx, esi, edi, and ebp. Return in eax.
;   * No calls into the C standard library.
;

; Windows C puts a leading underscore on every exported name. Linux C does
; not. The Makefile passes -d ELF_TYPE on Linux. This block then respells
; the names below to match. asm_io.inc does the same for _asm_main in the
; bootcamp blocks. Leave this block alone.
%ifdef ELF_TYPE
  %define _parse_args parse_args
  section .note.GNU-stack noalloc noexec nowrite progbits
%endif



segment .rodata
        flag_char       db      'n', 'c', 'v', 'i', 'w'         
        flag_bits_rev   db      16, 8, 4, 2, 1               ;for masking

        ;if for instance w was scanned by repne scasb so it counts down from 5 then 
        ;reaching w by subtracting at each comparison, ecx becomes 0
        ;and since w is 5th flag it is in vit pos. 4 ()counting 0...4 from right to left)
        ;to turn on bit 4 we need 10000 which is 16 in decimal


segment .text
        global  _parse_args

_parse_args:
        enter   0,0
        push    ebx                     
        push    esi
        push    edi

        ;
        ; TODO: parse.
        ;
        ; The steps the manual describes:
        ;
        ;   clear out->flags, out->pattern, out->path
        ;   for each token in argv[1..argc-1]:
        ;       if the token is a flag group:
        ;           for each byte after the dash:
        ;               find it in the table with repne scasb
        ;               not found: return the byte
        ;               set the bit for its index
        ;       else if out->pattern is empty: out->pattern = token
        ;       else if out->path is empty:    out->path = token
        ;       else: return -1
        ;   return -1 if the pattern or the path is still empty
        ;   return 0
        ;
        ; After repne scasb finds a byte, ecx has been decremented once for
        ; the hit as well. Work the index out from that before you shift.
        ;

        mov     edx, [ebp+16]    ;load address of struct args

        ;clear out's fields: 
        mov     dword [edx], 0          ;clear flags
        mov     dword [edx+4], 0       ; clear pattern
        mov     dword [edx + 8], 0      ;clear path


        mov     ebx, 1                  ; initialize to 1 counter for outer loop 
        cld                             ;clear direction flag
.outer_loop:
        cmp     ebx, [ebp +8]           ; [ebp+8]=arg count
        jge     .success                ; if ebx >=count  since there are 0 args left

        mov     esi, [ebp +12]          ;load argv address
        mov     esi, [esi + ebx*4 ]     ;get argv[ebx] which is pointer for the word


        cmp     byte [esi], '-'         ;check if the first character is -
        jne     .positional_pattern     


        ;check if valid flag group or just a single - is positional
        cmp     byte [esi + 1], 0       ;check if next already is a null terminator
        je      .positional_pattern    
        inc     esi                     ;move to next char after -


.flag_found_inner_loop:
        mov     al, [esi]               ;move next char after - to al 
        cmp     al, 0                   ;check if end of the word
        je      .next_token             ;finish w  this flag group


        ;check flag in the lookup table
        mov     edi, flag_char          ;address of table of flags
        mov     ecx, 5                  ;max num of bytes to check since there are 5 flag in table
        repne   scasb                   ;scan until [edi] == al or ecx ==0
        jne     .invalid_flag           ;wasnt found in table


        movzx   eax, byte [flag_bits_rev+ecx]           ;look for bit mask for this flag
        or      [edx], eax                              ;turn on flag

        inc     esi                             ;go to next char which can still be a flag unless \0
        jmp     .flag_found_inner_loop          ;repeat



.positional_pattern:
        cmp     dword [edx+4], 0        ;check if null
        jne     .positional_path        ;if not null check path
        mov     [edx+4], esi            ;if null then out->pattern = argv[i]
        jmp     .next_token             ;argv[i+1]


.positional_path:
        cmp     dword [edx+8], 0        ;check if null
        jne     .error                  ;if not null, extra arg -> error
        mov     [edx + 8], esi          ; if null then out->path = argv[i]


.next_token:
        inc     ebx                         ; i++ check next argv
        jmp     .outer_loop                 ; repeat for argv[i+1]


.success:
        ;check if pattern and path are still empty and return -1 if so
        cmp     dword [edx+4], 0   
        je      .missing_arg
        cmp     dword [edx+8], 0   
        je      .missing_arg

        mov     eax, 0          ;return 0 for success
        jmp     .done

.missing_arg:
        mov     eax, -1
        jmp     .done



.error:
        mov     eax, -1
        jmp     .done

.invalid_flag:
        movzx   eax, al         ;return bit
        jmp     .done



.done:
        pop     edi
        pop     esi
        pop     ebx
        leave
        ret