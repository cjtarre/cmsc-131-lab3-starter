;
; match.asm - line_matches, substring search with case folding and word
; boundaries. Callable from C.
;
; This is your starting point: it assembles and links as-is, so the build
; works before you write any code. Right now it always returns 0 (no
; match), which makes rengrep print nothing. Your job is to replace that
; with the search described below.
;
; The contract, from driver.c:
;
;       int line_matches(char *line, int linelen,
;                        char *pat, int patlen,
;                        int fold, int whole)
;
; so on the stack after a cdecl call:
;       [ebp+8]  = line
;       [ebp+12] = linelen
;       [ebp+16] = pat
;       [ebp+20] = patlen
;       [ebp+24] = fold
;       [ebp+28] = whole
;
; Return 1 in eax if pat occurs in line, 0 otherwise.
;
; Requirements from the manual:
;
;   * Use the x86 string instructions for the inner comparison. repe cmpsb
;     at minimum. A mov/cmp loop does not satisfy the activity.
;   * fold: compare case-insensitively WITHOUT modifying the buffer. Fold
;     in a register at comparison time. This path cannot use repe cmpsb
;     (it compares raw bytes), so a folding loop for that path is expected.
;   * whole: a match counts only when the byte before the match and the
;     byte after it are both non-word characters or absent. A failed
;     word-boundary check does NOT end the search. Keep scanning.
;   * The search bound is linelen - patlen, not linelen. Compare it with a
;     signed jump. When patlen is larger than linelen the difference is
;     negative. An unsigned jump reads it as enormous, and the scan runs
;     off the line into memory the process does not own and faults. This
;     is the Block 5 lesson.
;   * An empty pattern matches at every position, as it does in grep. A
;     rep prefix with ecx = 0 executes nothing and leaves the flags as they
;     were, so set ZF yourself before repe cmpsb. A bottom-tested folding
;     loop needs its own guard.
;   * Set cld explicitly. The direction flag persists across calls and
;     assuming it is clear is how a routine that works alone breaks when
;     called after something else.
;   * Preserve ebx, esi, edi, and ebp. Return in eax.
;   * No calls into the C standard library.
;
; Word characters are A-Z, a-z, 0-9, and _.
;

; Windows C puts a leading underscore on every exported name. Linux C does
; not. The Makefile passes -d ELF_TYPE on Linux. This block then respells
; the names below to match. asm_io.inc does the same for _asm_main in the
; bootcamp blocks. Leave this block alone.
%ifdef ELF_TYPE
  %define _line_matches line_matches
  section .note.GNU-stack noalloc noexec nowrite progbits
%endif

segment .text
        global  _line_matches

; _line_matches: returns 1 in eax if pat occurs in line, else 0.
; Sets up the frame and works out the last start position to try.
_line_matches:
        enter   0,0                 ; build stack frame, args now at [ebp+8..28]
        pusha                       ; save all regs; popa restores ebx/esi/edi for us
        cld                         ; make string ops go forward

        mov     edx, [ebp+12]       ; edx = linelen
        sub     edx, [ebp+20]       ; edx = linelen - patlen (the last valid start)
        js      .nomatch            ; negative (SIGNED) -> pattern too long, skip loop
        xor     ebx, ebx            ; ebx = start = 0

; .start_loop: runs once per start position; resets pointers and picks the fast or folding path.
.start_loop:
        cmp     ebx, edx            ; start vs. bound
        jg      .nomatch            ; SIGNED: start > bound -> out of positions

        mov     esi, [ebp+8]        ; reset esi = line  
        add     esi, ebx            ; esi = line + start (window begins here)
        mov     edi, [ebp+16]       ; reset edi = pat
        mov     ecx, [ebp+20]       ; reset ecx = patlen
        cmp     dword [ebp+24], 0   ; fold flag?
        jne     .fold_cmp           ; nonzero -> use the folding loop

        test    ecx, ecx            ; empty pattern? forces ZF=1 if ecx==0
        repe    cmpsb               ; compare until mismatch or ecx==0; ZF=1 if all equal
        jmp     .compared           ; both paths meet here with ZF set

; .fold_cmp: case-insensitive comparison, folding both bytes in registers. Leaves ZF=1 if equal.
.fold_cmp:
        test    ecx, ecx            ; guard: empty pattern -> ZF=1 ...
        jz      .compared           ; ... and skip the bottom-tested loop

; .fold_loop: compares one pair of bytes per pass.
.fold_loop:
        mov     al, [esi]           ; al = line byte (copy in register)
        mov     ah, [edi]           ; ah = pattern byte
        inc     esi                 ; advance both pointers
        inc     edi
        cmp     al, 'A'             ; below 'A'? not uppercase
        jb      .a_done
        cmp     al, 'Z'             ; above 'Z'? not uppercase
        ja      .a_done
        add     al, 32              ; uppercase -> lowercase

; .a_done: line byte is folded; now fold the pattern byte.
.a_done:
        cmp     ah, 'A'             ; same lowercasing for the pattern byte
        jb      .b_done
        cmp     ah, 'Z'
        ja      .b_done
        add     ah, 32

; .b_done: both bytes are folded; compare them.
.b_done:
        cmp     al, ah              ; compare folded bytes
        jne     .compared           ; mismatch: ZF=0, leave the loop
        dec     ecx                 ; one fewer byte to go
        jnz     .fold_loop          ; more bytes -> repeat; when 0, ZF=1 falls through

; .compared: both paths meet here. ZF=0 means try the next start;
; ZF=1 means a match, after the word-boundary check if -w is on.
.compared:
        jne     .next               ; ZF=0 -> window differs, try next start
        cmp     dword [ebp+28], 0   ; whole-word mode?
        je      .match              ; no -> plain match, done

        mov     esi, [ebp+8]        ; esi = line (for boundary reads)
        test    ebx, ebx            ; start == 0?
        jz      .before_ok          ; yes -> nothing before, OK
        movzx   eax, byte [esi+ebx-1] ; al = byte before the match
        call    is_word
        test    eax, eax
        jnz     .next               ; word char before -> fail, keep scanning

; .before_ok: left side passed; check the byte after the match.
.before_ok:
        mov     ecx, [ebp+20]       ; ecx = patlen
        add     ecx, ebx            ; ecx = start + patlen (index just past match)
        cmp     ecx, [ebp+12]       ; == linelen?
        je      .match              ; yes -> nothing after, OK
        movzx   eax, byte [esi+ecx] ; al = byte after the match
        call    is_word
        test    eax, eax
        jnz     .next               ; word char after -> fail, keep scanning

; .match: valid match found; restore registers and return 1.
.match:
        popa                        ; restore all registers
        mov     eax, 1              ; return 1
        leave
        ret

; .next: this start failed; move to the next start and keep scanning.
.next:
        inc     ebx                 ; start++
        jmp     .start_loop

; .nomatch: out of start positions (or pattern too long); return 0.
.nomatch:
        popa
        mov     eax, 0              ; return 0
        leave
        ret

; is_word: al = byte in, eax = 1 if it is a word char (A-Z a-z 0-9 _), else 0.
; '_' is checked first because 'or al, 20h' would push it outside a-z.
is_word:
        cmp     al, '_'
        je      .yes
        cmp     al, '0'
        jb      .no                 ; below '0' -> not a word char
        cmp     al, '9'
        jbe     .yes                ; digit
        or      al, 20h             ; fold letters to lowercase (other bytes land outside a-z)
        cmp     al, 'a'
        jb      .no
        cmp     al, 'z'
        ja      .no

; .yes: word character, return 1.
.yes:
        mov     eax, 1
        ret

; .no: not a word character, return 0.
.no:
        xor     eax, eax
        ret