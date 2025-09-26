; =========================================================
; WOZMON (8085 / zasm --asm8080) — CUR sabit, sade akış
; OUTCH / GETCH: dışarıda (CALL OUTCH / CALL GETCH)
; =========================================================
;Ported to 8085 by Dr.Mustafa Peker - 2025
;From the Original 6502 version by Steve Wozniak - 1976 

; --- Sabitler ---
BS      EQU 08H
LF      EQU 0AH
CR      EQU 0DH
ESC     EQU 1BH
SPC     EQU ' '
DOT     EQU '.'
COLON   EQU ':'
BSLASH  EQU 5CH
STKTOP  EQU 0FFFFH

; --- RAM Değişkenleri ---
INBUF   EQU 0B000H

XAML    EQU 0B400H       ; examine addr low
XAMH    EQU 0B401H       ; examine addr high
STL     EQU 0B402H       ; store / END low   (range END burada)
STH     EQU 0B403H       ; store / END high
Low     EQU 0B404H       ; parsed 16-bit low
High    EQU 0B405H       ; parsed 16-bit high
YSAV    EQU 0B406H       ; token start low
YSAVH   EQU 0B407H       ; token start high
MODE    EQU 0B408H       ; 00=XAM, 40h=STORE, 80h=BLOCK XAM
CURLO   EQU 0B409H       ; current text pointer low
CURHI   EQU 0B40AH       ; current text pointer high

            ORG 0A000H

; =========================================================
; RESET / PROMPT
; =========================================================
RESET:
            LXI     SP,STKTOP
            MVI     A,BSLASH         ; '\' yalnız başlangıçta/ESC sonrası
            CALL    OUTCH
MAINPROMPT:
            MVI     A,CR             ; normalde sadece CRLF
            CALL    OUTCH
            MVI     A,LF
            CALL    OUTCH

; =========================================================
; GETLINE — INBUF’a satır al, NUL’la bitir
; =========================================================
GETLINE:
            LXI     H,INBUF

NEXTCHAR:
            CALL    GETCH
            CPI     0FFH
            JZ      NEXTCHAR

            CPI     BS
            JNZ     CHK_ESC
; BACKSPACE: HL > INBUF ise görsel sil (BS SP BS) + imleç geri
BACKPACK:
            LXI     D,INBUF
            MOV     A,H
            CMP     D
            JNZ     DO_BS
            MOV     A,L
            CMP     E
            JZ      NEXTCHAR
DO_BS:      DCX     H
            MVI     A,BS
            CALL    OUTCH
            MVI     A,' '
            CALL    OUTCH
            MVI     A,BS
            CALL    OUTCH
            JMP     NEXTCHAR

CHK_ESC:    CPI     ESC
            JNZ     CHK_CR
            JMP     RESET            ; ESC → '\' + CRLF + GETLINE

CHK_CR:     CPI     CR
            JNZ     STORECHR
            ; CR → NUL ve parser için CUR = INBUF, MODE=0
            MVI     A,00H
            MOV     M,A
            LXI     H,INBUF
            SHLD    CURLO            ; CUR := INBUF
            XRA     A
            STA     MODE
            JMP     PROCESS

STORECHR:
            MOV     M,A              ; [HL] ← A
            ; echo (HL bozulmasın)
            PUSH    H
            CALL    OUTCH
            POP     H
            INX     H
            JMP     NEXTCHAR

; =========================================================
; PROCESS — satırı CUR ile tara (Woz etiketi akışı)
; =========================================================
PROCESS:
SKIPSP:
            LHLD    CURLO            ; HL := CUR (her dönüşte)
            MOV     A,M
            CPI     00H
            JZ      MAINPROMPT       ; boş satır → yeni satır
            CPI     SPC
            JZ      BLSKIP
            CPI     09H
            JZ      BLSKIP
            JMP     TOKEN

BLSKIP:
            INX     H
            SHLD    CURLO
            JMP     SKIPSP

TOKEN:
            CPI     DOT
            JNZ     TK_COLON
SETBLOCK:   MVI     A,080H           ; BLOCK XAM
            STA     MODE
            INX     H
            SHLD    CURLO
            JMP     SKIPSP

TK_COLON:
            CPI     COLON
            JNZ     TK_Q
SETSTOR:    MVI     A,040H           ; STORE
            STA     MODE
            INX     H
            SHLD    CURLO
            JMP     SKIPSP

TK_Q:
            CPI     'Q'
            JNZ     TK_R
            INX     H
            SHLD    CURLO
            JMP     MAINPROMPT

TK_R:
            CPI     'R'
            JNZ     HEXIN
            INX     H
            SHLD    CURLO
            LHLD    XAML
            PCHL

; =========================================================
; HEXIN — ASCII hex → High:Low (HL her adımda CUR’dan alınır)
; =========================================================
HEXIN:
            LHLD    CURLO
            SHLD    YSAV             ; YSAV := CUR
            XRA     A
            STA     Low
            STA     High

HXL1:
            LHLD    CURLO
            MOV     A,M              ; A = [CUR]
            CPI     CR
            JZ      HXL_DONE_CK
            ORA     A
            JZ      HXL_DONE_CK
            PUSH    H
            CALL    HEXDIG           ; geçerli nibble ise CY=0, A=nibble
            POP     H
            JC      HXL_DONE_CK

            ; value = (value<<4) | nibble
            MOV     E,A              ; nibble
            MVI     B,04H
HXL_SHIFT:
            STC
            CMC                       ; CY=0
            LDA     Low
            RAL
            STA     Low
            LDA     High
            RAL
            STA     High
            DCR     B
            JNZ     HXL_SHIFT

            LDA     Low
            ORA     E
            STA     Low

            ; geçerli hane tüketildi → CUR++
            LHLD    CURLO
            INX     H
            SHLD    CURLO
            JMP     HXL1

HXL_DONE_CK:
            ; hiç hex tüketilmediyse → prompt (CUR == YSAV ?)
            LHLD    CURLO
            XCHG                        ; DE = CUR
            LHLD    YSAV
            MOV     A,H
            CMP     D
            JNZ     GOTHEX
            MOV     A,L
            CMP     E
            JNZ     GOTHEX
            JMP     MAINPROMPT

GOTHEX:
            ; STORE modu?
            LDA     MODE
            ANI     040H
            JZ      NOTSTORE
            ; *ST++ = Low
            LHLD    STL
            LDA     Low
            MOV     M,A
            INX     H
            SHLD    STL
            JMP     SKIPSP

NOTSTORE:
            ; BLOCK?
            LDA     MODE
            ANI     080H
            JZ      SINGLEADDR

BLOCKSET:
            ; ikinci sayı: END = High:Low, ilk bayt zaten basıldı → XAM++
            LDA     Low
            STA     STL
            LDA     High
            STA     STH
            LHLD    XAML
            INX     H
            SHLD    XAML
            JMP     DO_XAM

SINGLEADDR:
            ; SINGLE: XAM/ST = High:Low ve başlık
            LDA     Low
            STA     XAML
            STA     STL
            LDA     High
            STA     XAMH
            STA     STH
            JMP     PR_HEAD

; =========================================================
; Başlık + Examine Döngüsü
; =========================================================
PR_HEAD:
            ; CRLF + addr + ':'
            MVI     A,CR
            CALL    OUTCH
            MVI     A,LF
            CALL    OUTCH

            LDA     XAMH
            PUSH    H
            CALL    PRBYTE
            POP     H

            LDA     XAML
            PUSH    H
            CALL    PRBYTE
            POP     H

            MVI     A,':'
            CALL    OUTCH

DO_XAM:
            ; ' ' + [XAM] byte
            MVI     A,' '
            CALL    OUTCH
            LHLD    XAML
            MOV     A,M
            PUSH    H
            CALL    PRBYTE
            POP     H

            ; BLOCK modda mıyız?
            LDA     MODE
            ANI     080H
            JZ      XAM_SINGLE_DONE

            ; Bitiş? (XAM == END)
            LDA     XAML
            MOV     B,A
            LDA     STL
            CMP     B
            JNZ     XAM_CONT
            LDA     XAMH
            MOV     B,A
            LDA     STH
            CMP     B
            JNZ     XAM_CONT

            ; eşit → bitir
            XRA     A
            STA     MODE
            JMP     SKIPSP

XAM_CONT:
            ; XAM++ ve 8’de bir başlık
            LHLD    XAML
            INX     H
            SHLD    XAML
            LDA     XAML
            ANI     07H
            JNZ     DO_XAM           ; iç döngü → ilerlemeye devam
            JMP     PR_HEAD

XAM_SINGLE_DONE:
            XRA     A
            STA     MODE
            JMP     SKIPSP

; =========================================================
; Yardımcılar
; =========================================================
PRBYTE:                         ; A = byte → iki hex
            PUSH    PSW
            ANI     0F0H
            RRC
            RRC
            RRC
            RRC
            ANI     00FH
            CALL    PRHEX
            POP     PSW
            ANI     00FH
            CALL    PRHEX
            RET

PRHEX:
            ANI     00FH
            ORI     030H
            CPI     03AH
            JC      ECHO
            ADI     07H
ECHO:
            PUSH    H
            CALL    OUTCH           ; DIŞ RUTİN
            POP     H
            RET

; ASCII → nibble (A), geçerliyse CY=0, değilse CY=1
HEXDIG:
            CPI     '0'
            JC      HXBAD
            CPI     '9'+1
            JC      HXOKD
            CPI     'A'
            JC      HXBAD
            CPI     'F'+1
            JNC     HXBAD
            SUI     'A'
            ADI     10
            CMC
            CMC
            RET
HXOKD:      SUI     '0'
            CMC
            CMC
            RET
HXBAD:      STC
            RET

           

;By changing the OUTCH and GETCH routines, this code can be used
;on 8080 or z80 microprocessors.
           




;This communication code is for interfacing to the RIM and SIM
;pins from the 80C85 microprocessor. It uses the standard
;TI serial I/O format of 1 start bit (0), 8 data bits (LSB
;first), and 1 stop bit (1). The baud rate is set by
;changing the DELAY_XT and HALF_DELAY constants. The
;values shown are for a 6MHz crystal. The 80C85 XTAL is
;divided by 3 to get the instruction rate. The RIM and SIM
;cards run at 1/16 the baud rate of the 80C85.
;OKI80C85 can stabile run by 12MHz crystal. and 9600 baud
;communication is possible by changing the constants in
;DELAY_XT and HALF_DELAY routines. 
;Dr.Mustafa Peker - 2025

OUTCH:
        PUSH H
        PUSH D
        PUSH B
        MOV B,A
        MVI C,0BH
        XRA A
NEXXXT:
        MVI A,80H
        RAR
        .DB 030H ;SIM command code for 8085, to trick zasm 
        CALL DELAY_XT
        STC
        MOV A,B
        RAR
        MOV B,A
        DCR C
        JNZ NEXXXT
        POP B
        POP D
        POP H
        RET

DELAY_XT: ;SIM-RIM COMMUNICATION TIMER ROUTINES;@ 6MHZ XTAL
        LXI D,0016H; ;0030H FOR 2400 BAUD, 0060H FOR 1200 BAUD,0016  FOR 4800
LOOP_TXD:
        DCX D
        MOV A,D
        ORA E
        JNZ LOOP_TXD
        RET

HALF_DELAY:     ;80C85 6MHZ XTAL VALUES.(12mhz doubles speed)
        LXI D,000AH  ;;0018H FOR 2400H, 0030H FOR 1200 BAUD, 000A FOR 4800
LOOP_HXD:
        DCX D
        MOV A,D
        ORA E
        JNZ LOOP_HXD
        RET

;;RXD: ROUTINE receives 1 byte from serial to A REGISTER
GETCH:
        PUSH H
        PUSH D
        PUSH B
RXD1:
        .DB 020H ;RIM command code for 8085, to trick zasm
        RAL
        JC RXD1
        CALL HALF_DELAY
        .DB 020H ;RIM
        RAL
        JC RXD1
        MVI C,09H
NXTBIT:
        CALL DELAY_XT
        .DB 020H ;RIM
        RAL
        DCR C
        JZ RXDENDED
        MOV A,B
        RAR
        MOV B,A
        JMP NXTBIT
RXDENDED:
        MOV A,B
        POP B
        POP D
        POP H
        RET

  END