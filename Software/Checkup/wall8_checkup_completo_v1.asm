#include "../wall8.cpu"

#bankdef bios {
    #addr 0x0000
    #size 0xA000
    #outp 0x0000
}

; ============================================================================
; WALL-8 COMPLETE HARDWARE CHECKUP v1.0
; Replaces the normal BIOS while the hardware is being validated.
;
; Test order:
;   1. Destructive RAM test over the complete 32 KiB.
;   2. Visual test of the 7-segment display and LED enable.
;   3. Functional test of the 76-opcode ISA.
;   4. TIMER_1MS and TIMER_500MS.
;   5. Video: text 40x30, graphics 320x240 and 160x120.
;   6. Keyboard / KEY_READY handshake.
;   7. Tone and noise, all eight selections, 500 ms each.
;   8. Cartridge detect and two stable checksum passes over 20 KiB.
;   9. Final HLT test.
;
; Display convention during CPU tests:
;   DISPLAY_LOW  = opcode under test.
;   DISPLAY_HIGH = 00 while running.
;
; Fatal failure:
;   DISPLAY_LOW remains the opcode/test identifier.
;   DISPLAY_HIGH alternates between expected and actual values.
;
; IMPORTANT:
;   The RAM test is destructive. It erases 0x0000..0x7FFF.
; ============================================================================


; ============================================================================
; I/O MAP
; ============================================================================

KEY_DATA       = $F000

DISPLAY_LOW    = $F100
DISPLAY_HIGH   = $F101

VIDEO_DATA     = $F200
VIDEO_CMD      = $F201
VIDEO_X        = $F202
VIDEO_Y        = $F203
VIDEO_STATUS   = $F204

SYSTEM_STATUS  = $F300
SOUND_CFG      = $F400
CPU_CFG        = $F500
PERIPH_CFG     = $F501

CART_ENTRY     = $A000


; ============================================================================
; STATUS BITS
; ============================================================================

TIMER_1MS_MASK       = $01
TIMER_500MS_MASK     = $02
CARD_DETECT_MASK     = $10
VIDEO_DETECT_MASK    = $20
KEY_READY_MASK       = $80

VIDEO_BUSY_MASK      = $01
VIDEO_VBLANK_MASK    = $02
VIDEO_HBLANK_MASK    = $04
VIDEO_FRAME_MASK     = $08
VIDEO_CURSOR_END     = $10


; ============================================================================
; VIDEO COMMANDS
; ============================================================================

VIDEO_CLEAR          = $00
CURSOR_HIDE          = $04
CURSOR_SHOW          = $05
MODE_TEXT_40X30      = $11
MODE_GFX_320X240     = $12
MODE_GFX_160X120     = $13
VRAM_READ            = $20


; ============================================================================
; NORMAL WORK RAM - initialized only after the destructive RAM test
; ============================================================================

CURRENT_TEST         = $0200
FAIL_EXPECTED        = $0201
FAIL_ACTUAL          = $0202
FAIL_DETAIL          = $0203

VIDEO_PRESENT        = $0204
VIDEO_OK             = $0205
KEY_OK               = $0206
KEY_VALUE            = $0207
CART_PRESENT         = $0208
CART_OK              = $0209
CART_SUM1            = $020A
CART_SUM2            = $020B
TIMER_OK             = $020C
SOUND_OK             = $020D

VIDEO_TEMP           = $020E
LOOP0                = $020F
LOOP1                = $0210
ROW_COUNT            = $0211
COL_COUNT            = $0212
PATTERN_VALUE        = $0213
FRAME_OLD            = $0214
SOUND_INDEX          = $0215
CHECKSUM_VALUE       = $0216
PAGE_COUNT           = $0217
BYTE_COUNT           = $0218

RAM_PATTERN          = $0219
RAM_PAGE_REMAIN      = $021A
RAM_BYTE_INDEX       = $021B
RAM_ACTUAL           = $021C

; High-RAM variables used while 0x0000..0x03FF is under test.
RAM2_PATTERN         = $7E00
RAM2_PAGE_REMAIN     = $7E01
RAM2_BYTE_INDEX      = $7E02
RAM2_ACTUAL          = $7E03

; CPU-test scratch bytes.
SCRATCH0              = $0300
SCRATCH1              = $0301
SCRATCH2              = $0302
SCRATCH3              = $0303
SCRATCH4              = $0304
SCRATCH5              = $0305


; ============================================================================
; BOOT OVERLAY STUB
; ============================================================================

#bank bios

#addr 0x0000
RESET:
    SP $03FF

    STI SOUND_CFG,     #$00
    STI PERIPH_CFG,    #$00
    STI DISPLAY_LOW,   #$00
    STI DISPLAY_HIGH,  #$00
    STI SYSTEM_STATUS, #$00

    ; Enter the fixed ROM window before releasing RAM at 0x0000.
    JMP CHECKUP_MAIN


; ============================================================================
; FIXED BIOS WINDOW
; ============================================================================

#addr 0x8000
CHECKUP_MAIN:
    ; bit0=1 releases RAM in the lower 32 KiB.
    ; bits4..6 remain at the same initial level used by the monitor BIOS.
    STI CPU_CFG, #$71

    ; No CALL here: the low-RAM stack will be overwritten in RAM phase 2.
    JMP RAM_TEST_ENTRY


; ============================================================================
; 1. COMPLETE DESTRUCTIVE RAM TEST
;
; Phase A:
;   Stack/variables in 0x0200..0x03FF.
;   Tests 0x0400..0x7FFF = 124 complete pages.
;
; Phase B:
;   Stack/variables moved to 0x7E00..0x7FFF, already tested in phase A.
;   Tests 0x0000..0x03FF = 4 complete pages.
;
; Patterns: 00, FF, 55, AA.
; ============================================================================

RAM_TEST_ENTRY:
    STI DISPLAY_LOW,  #$E1
    STI DISPLAY_HIGH, #$00

    LDA #$00
    CALL RAM_TEST_HIGH_PATTERN
    LDA #$FF
    CALL RAM_TEST_HIGH_PATTERN
    LDA #$55
    CALL RAM_TEST_HIGH_PATTERN
    LDA #$AA
    CALL RAM_TEST_HIGH_PATTERN

    ; Move the stack to tested high RAM before destroying the low 1 KiB.
    SP $7FFF

    STI DISPLAY_LOW,  #$E2
    STI DISPLAY_HIGH, #$00

    LDA #$00
    CALL RAM_TEST_LOW_PATTERN
    LDA #$FF
    CALL RAM_TEST_LOW_PATTERN
    LDA #$55
    CALL RAM_TEST_LOW_PATTERN
    LDA #$AA
    CALL RAM_TEST_LOW_PATTERN

    JMP AFTER_RAM_TEST


; Input: A = pattern.
RAM_TEST_HIGH_PATTERN:
    STA RAM_PATTERN

    ; Write 0x0400..0x7FFF.
    PTR $0400
    STI RAM_PAGE_REMAIN, #$7C

RAM_H_WRITE_PAGE:
    LDA RAM_PAGE_REMAIN
    STA DISPLAY_HIGH
    LDA RAM_PATTERN
    LDB #$00

RAM_H_WRITE_BYTE:
    STA [PTR+]
    INC B
    JNZ RAM_H_WRITE_BYTE

    LDA RAM_PAGE_REMAIN
    DEC A
    STA RAM_PAGE_REMAIN
    JNZ RAM_H_WRITE_PAGE

    ; Read and verify 0x0400..0x7FFF.
    PTR $0400
    STI RAM_PAGE_REMAIN, #$7C
    STI RAM_BYTE_INDEX,  #$00

RAM_H_READ_PAGE:
    LDA RAM_PAGE_REMAIN
    STA DISPLAY_HIGH
    STI RAM_BYTE_INDEX, #$00

RAM_H_READ_BYTE:
    LDA [PTR+]
    STA RAM_ACTUAL
    LDB RAM_PATTERN
    CMP A, B
    JNZ RAM_HIGH_FAIL

    LDA RAM_BYTE_INDEX
    INC A
    STA RAM_BYTE_INDEX
    JNZ RAM_H_READ_BYTE

    LDA RAM_PAGE_REMAIN
    DEC A
    STA RAM_PAGE_REMAIN
    JNZ RAM_H_READ_PAGE
    RET


RAM_HIGH_FAIL:
    LDA RAM_ACTUAL
    STA FAIL_ACTUAL
    LDA RAM_PATTERN
    STA FAIL_EXPECTED
    STI CURRENT_TEST, #$E1
    JMP FATAL_FAIL_FROM_MEMORY


; Input: A = pattern.
RAM_TEST_LOW_PATTERN:
    STA RAM2_PATTERN

    ; Write 0x0000..0x03FF.
    PTR $0000
    STI RAM2_PAGE_REMAIN, #$04

RAM_L_WRITE_PAGE:
    LDA RAM2_PAGE_REMAIN
    STA DISPLAY_HIGH
    LDA RAM2_PATTERN
    LDB #$00

RAM_L_WRITE_BYTE:
    STA [PTR+]
    INC B
    JNZ RAM_L_WRITE_BYTE

    LDA RAM2_PAGE_REMAIN
    DEC A
    STA RAM2_PAGE_REMAIN
    JNZ RAM_L_WRITE_PAGE

    ; Read and verify 0x0000..0x03FF.
    PTR $0000
    STI RAM2_PAGE_REMAIN, #$04
    STI RAM2_BYTE_INDEX,  #$00

RAM_L_READ_PAGE:
    LDA RAM2_PAGE_REMAIN
    STA DISPLAY_HIGH
    STI RAM2_BYTE_INDEX, #$00

RAM_L_READ_BYTE:
    LDA [PTR+]
    STA RAM2_ACTUAL
    LDB RAM2_PATTERN
    CMP A, B
    JNZ RAM_LOW_FAIL

    LDA RAM2_BYTE_INDEX
    INC A
    STA RAM2_BYTE_INDEX
    JNZ RAM_L_READ_BYTE

    LDA RAM2_PAGE_REMAIN
    DEC A
    STA RAM2_PAGE_REMAIN
    JNZ RAM_L_READ_PAGE
    RET


RAM_LOW_FAIL:
    ; Low RAM is untrusted here, so the failure loop uses high-RAM values.
    LDA RAM2_PATTERN
    STA RAM2_PAGE_REMAIN      ; expected
    LDA RAM2_ACTUAL
    STA RAM2_BYTE_INDEX       ; actual

    STI DISPLAY_LOW, #$E2

RAM_LOW_FAIL_LOOP:
    LDA RAM2_PAGE_REMAIN
    STA DISPLAY_HIGH

    LDA #$FF
RAM_LOW_FAIL_D1:
    LDB #$FF
RAM_LOW_FAIL_D2:
    DEC B
    JNZ RAM_LOW_FAIL_D2
    DEC A
    JNZ RAM_LOW_FAIL_D1

    LDA RAM2_BYTE_INDEX
    STA DISPLAY_HIGH

    LDA #$FF
RAM_LOW_FAIL_D3:
    LDB #$FF
RAM_LOW_FAIL_D4:
    DEC B
    JNZ RAM_LOW_FAIL_D4
    DEC A
    JNZ RAM_LOW_FAIL_D3

    JMP RAM_LOW_FAIL_LOOP


AFTER_RAM_TEST:
    ; Low RAM currently contains AA. Initialize the normal state area.
    SP $7FFF

    STI CURRENT_TEST,  #$00
    STI FAIL_EXPECTED, #$00
    STI FAIL_ACTUAL,   #$00
    STI FAIL_DETAIL,   #$00

    STI VIDEO_PRESENT, #$00
    STI VIDEO_OK,      #$00
    STI KEY_OK,        #$00
    STI KEY_VALUE,     #$00
    STI CART_PRESENT,  #$00
    STI CART_OK,       #$00
    STI CART_SUM1,     #$00
    STI CART_SUM2,     #$00
    STI TIMER_OK,      #$00
    STI SOUND_OK,      #$00

    CALL TEST_DISPLAY_VISUAL

    ; Enter by JMP because the SP opcode test deliberately reinitializes SP.
    JMP TEST_CPU_ISA

AFTER_CPU_ISA:
    CALL TEST_TIMERS
    CALL TEST_VIDEO
    CALL TEST_KEYBOARD
    CALL TEST_SOUND
    CALL TEST_CARTRIDGE
    CALL SHOW_FINAL_SUMMARY

    ; HLT is the last opcode. If it works, execution stops here.
    STI CURRENT_TEST, #$01
    STI DISPLAY_LOW,  #$01
    STI DISPLAY_HIGH, #$A1
    HLT

    ; Reaching this point means HLT did not stop the CPU.
    LDA #$F1
    LDB #$01
    JMP FATAL_FAIL_AB


; ============================================================================
; 2. VISUAL DISPLAY / LED CONTROL TEST
; ============================================================================

TEST_DISPLAY_VISUAL:
    STI CURRENT_TEST, #$F1

    STI DISPLAY_HIGH, #$00
    STI DISPLAY_LOW,  #$00
    CALL DELAY_VISIBLE

    STI DISPLAY_HIGH, #$FF
    STI DISPLAY_LOW,  #$FF
    CALL DELAY_VISIBLE

    STI DISPLAY_HIGH, #$AA
    STI DISPLAY_LOW,  #$55
    CALL DELAY_VISIBLE

    STI DISPLAY_HIGH, #$55
    STI DISPLAY_LOW,  #$AA
    CALL DELAY_VISIBLE

    STI DISPLAY_HIGH, #$12
    STI DISPLAY_LOW,  #$34
    CALL DELAY_VISIBLE

    ; /LED_EN is bit2. Toggle it for visual verification.
    STI PERIPH_CFG, #$04
    CALL DELAY_VISIBLE
    STI PERIPH_CFG, #$00
    CALL DELAY_VISIBLE
    RET


; ============================================================================
; 3. COMPLETE ISA TEST
; ============================================================================

TEST_CPU_ISA:

    ; ------------------------------------------------------------------------
    ; 00 NOP
    ; ------------------------------------------------------------------------
    STI CURRENT_TEST, #$00
    STI DISPLAY_LOW,  #$00
    STI DISPLAY_HIGH, #$00
    LDA #$5A
    NOP
    CMP A, #$5A
    JZ CPU_00_OK
    LDB #$5A
    JMP FATAL_FAIL_AB
CPU_00_OK:

    ; ------------------------------------------------------------------------
    ; 10 LDA #imm
    ; ------------------------------------------------------------------------
    STI CURRENT_TEST, #$10
    STI DISPLAY_LOW,  #$10
    LDA #$A5
    CMP A, #$A5
    JZ CPU_10_OK
    LDB #$A5
    JMP FATAL_FAIL_AB
CPU_10_OK:

    ; ------------------------------------------------------------------------
    ; 11 LDB #imm
    ; ------------------------------------------------------------------------
    STI CURRENT_TEST, #$11
    STI DISPLAY_LOW,  #$11
    LDB #$3C
    CMP B, #$3C
    JZ CPU_11_OK
    MOV A, B
    LDB #$3C
    JMP FATAL_FAIL_AB
CPU_11_OK:

    ; ------------------------------------------------------------------------
    ; 27 STI absolute, immediate
    ; ------------------------------------------------------------------------
    STI CURRENT_TEST, #$27
    STI DISPLAY_LOW,  #$27
    STI SCRATCH0, #$A6
    LDA SCRATCH0
    CMP A, #$A6
    JZ CPU_27_OK
    LDB #$A6
    JMP FATAL_FAIL_AB
CPU_27_OK:

    ; ------------------------------------------------------------------------
    ; 14 STA absolute
    ; ------------------------------------------------------------------------
    STI CURRENT_TEST, #$14
    STI DISPLAY_LOW,  #$14
    LDA #$5C
    STA SCRATCH0
    LDA #$00
    LDA SCRATCH0
    CMP A, #$5C
    JZ CPU_14_OK
    LDB #$5C
    JMP FATAL_FAIL_AB
CPU_14_OK:

    ; ------------------------------------------------------------------------
    ; 15 STB absolute
    ; ------------------------------------------------------------------------
    STI CURRENT_TEST, #$15
    STI DISPLAY_LOW,  #$15
    LDB #$C5
    STB SCRATCH1
    LDA SCRATCH1
    CMP A, #$C5
    JZ CPU_15_OK
    LDB #$C5
    JMP FATAL_FAIL_AB
CPU_15_OK:

    ; ------------------------------------------------------------------------
    ; 12 LDA absolute
    ; ------------------------------------------------------------------------
    STI CURRENT_TEST, #$12
    STI DISPLAY_LOW,  #$12
    STI SCRATCH2, #$96
    LDA #$00
    LDA SCRATCH2
    CMP A, #$96
    JZ CPU_12_OK
    LDB #$96
    JMP FATAL_FAIL_AB
CPU_12_OK:

    ; ------------------------------------------------------------------------
    ; 13 LDB absolute
    ; ------------------------------------------------------------------------
    STI CURRENT_TEST, #$13
    STI DISPLAY_LOW,  #$13
    STI SCRATCH2, #$69
    LDB #$00
    LDB SCRATCH2
    CMP B, #$69
    JZ CPU_13_OK
    MOV A, B
    LDB #$69
    JMP FATAL_FAIL_AB
CPU_13_OK:

    ; ------------------------------------------------------------------------
    ; 16 MOV A,B
    ; ------------------------------------------------------------------------
    STI CURRENT_TEST, #$16
    STI DISPLAY_LOW,  #$16
    LDA #$00
    LDB #$7B
    MOV A, B
    CMP A, #$7B
    JZ CPU_16_OK
    LDB #$7B
    JMP FATAL_FAIL_AB
CPU_16_OK:

    ; ------------------------------------------------------------------------
    ; 17 MOV B,A
    ; ------------------------------------------------------------------------
    STI CURRENT_TEST, #$17
    STI DISPLAY_LOW,  #$17
    LDA #$B7
    LDB #$00
    MOV B, A
    CMP B, #$B7
    JZ CPU_17_OK
    MOV A, B
    LDB #$B7
    JMP FATAL_FAIL_AB
CPU_17_OK:

    ; ------------------------------------------------------------------------
    ; 20 PTR absolute
    ; 1A STA [PTR]
    ; 18 LDA [PTR]
    ; ------------------------------------------------------------------------
    STI CURRENT_TEST, #$20
    STI DISPLAY_LOW,  #$20
    PTR SCRATCH3

    STI CURRENT_TEST, #$1A
    STI DISPLAY_LOW,  #$1A
    LDA #$D2
    STA [PTR]

    STI CURRENT_TEST, #$18
    STI DISPLAY_LOW,  #$18
    LDA #$00
    LDA [PTR]
    CMP A, #$D2
    JZ CPU_18_1A_OK
    LDB #$D2
    JMP FATAL_FAIL_AB
CPU_18_1A_OK:

    ; ------------------------------------------------------------------------
    ; 1B STB [PTR]
    ; 19 LDB [PTR]
    ; ------------------------------------------------------------------------
    STI CURRENT_TEST, #$1B
    STI DISPLAY_LOW,  #$1B
    LDB #$2D
    STB [PTR]

    STI CURRENT_TEST, #$19
    STI DISPLAY_LOW,  #$19
    LDB #$00
    LDB [PTR]
    CMP B, #$2D
    JZ CPU_19_1B_OK
    MOV A, B
    LDB #$2D
    JMP FATAL_FAIL_AB
CPU_19_1B_OK:

    ; ------------------------------------------------------------------------
    ; 21 INC PTR
    ; ------------------------------------------------------------------------
    STI CURRENT_TEST, #$21
    STI DISPLAY_LOW,  #$21
    PTR SCRATCH3
    INC PTR
    LDA #$71
    STA [PTR]
    LDA SCRATCH4
    CMP A, #$71
    JZ CPU_21_OK
    LDB #$71
    JMP FATAL_FAIL_AB
CPU_21_OK:

    ; ------------------------------------------------------------------------
    ; 22 DEC PTR
    ; ------------------------------------------------------------------------
    STI CURRENT_TEST, #$22
    STI DISPLAY_LOW,  #$22
    PTR SCRATCH4
    DEC PTR
    LDA #$72
    STA [PTR]
    LDA SCRATCH3
    CMP A, #$72
    JZ CPU_22_OK
    LDB #$72
    JMP FATAL_FAIL_AB
CPU_22_OK:

    ; ------------------------------------------------------------------------
    ; 25 STA [PTR+]
    ; 23 LDA [PTR+]
    ; ------------------------------------------------------------------------
    STI CURRENT_TEST, #$25
    STI DISPLAY_LOW,  #$25
    PTR SCRATCH0
    LDA #$11
    STA [PTR+]
    LDA #$22
    STA [PTR+]

    STI CURRENT_TEST, #$23
    STI DISPLAY_LOW,  #$23
    PTR SCRATCH0
    LDA [PTR+]
    CMP A, #$11
    JZ CPU_23_A_OK
    LDB #$11
    JMP FATAL_FAIL_AB
CPU_23_A_OK:
    LDA [PTR+]
    CMP A, #$22
    JZ CPU_23_OK
    LDB #$22
    JMP FATAL_FAIL_AB
CPU_23_OK:

    ; ------------------------------------------------------------------------
    ; 26 STB [PTR+]
    ; 24 LDB [PTR+]
    ; ------------------------------------------------------------------------
    STI CURRENT_TEST, #$26
    STI DISPLAY_LOW,  #$26
    PTR SCRATCH0
    LDB #$33
    STB [PTR+]
    LDB #$44
    STB [PTR+]

    STI CURRENT_TEST, #$24
    STI DISPLAY_LOW,  #$24
    PTR SCRATCH0
    LDB [PTR+]
    CMP B, #$33
    JZ CPU_24_A_OK
    MOV A, B
    LDB #$33
    JMP FATAL_FAIL_AB
CPU_24_A_OK:
    LDB [PTR+]
    CMP B, #$44
    JZ CPU_24_OK
    MOV A, B
    LDB #$44
    JMP FATAL_FAIL_AB
CPU_24_OK:

    ; ------------------------------------------------------------------------
    ; 30 ADD A,B
    ; ------------------------------------------------------------------------
    STI CURRENT_TEST, #$30
    STI DISPLAY_LOW,  #$30
    LDA #$12
    LDB #$34
    ADD A, B
    CMP A, #$46
    JZ CPU_30_OK
    LDB #$46
    JMP FATAL_FAIL_AB
CPU_30_OK:

    ; ------------------------------------------------------------------------
    ; 31 ADD B,A
    ; ------------------------------------------------------------------------
    STI CURRENT_TEST, #$31
    STI DISPLAY_LOW,  #$31
    LDA #$12
    LDB #$34
    ADD B, A
    CMP B, #$46
    JZ CPU_31_OK
    MOV A, B
    LDB #$46
    JMP FATAL_FAIL_AB
CPU_31_OK:

    ; ------------------------------------------------------------------------
    ; 32 SUB A,B
    ; ------------------------------------------------------------------------
    STI CURRENT_TEST, #$32
    STI DISPLAY_LOW,  #$32
    LDA #$50
    LDB #$11
    SUB A, B
    CMP A, #$3F
    JZ CPU_32_OK
    LDB #$3F
    JMP FATAL_FAIL_AB
CPU_32_OK:

    ; ------------------------------------------------------------------------
    ; 33 SUB B,A
    ; ------------------------------------------------------------------------
    STI CURRENT_TEST, #$33
    STI DISPLAY_LOW,  #$33
    LDA #$11
    LDB #$50
    SUB B, A
    CMP B, #$3F
    JZ CPU_33_OK
    MOV A, B
    LDB #$3F
    JMP FATAL_FAIL_AB
CPU_33_OK:

    ; ------------------------------------------------------------------------
    ; 34 AND A,B
    ; ------------------------------------------------------------------------
    STI CURRENT_TEST, #$34
    STI DISPLAY_LOW,  #$34
    LDA #$F0
    LDB #$3C
    AND A, B
    CMP A, #$30
    JZ CPU_34_OK
    LDB #$30
    JMP FATAL_FAIL_AB
CPU_34_OK:

    ; ------------------------------------------------------------------------
    ; 35 AND B,A
    ; ------------------------------------------------------------------------
    STI CURRENT_TEST, #$35
    STI DISPLAY_LOW,  #$35
    LDA #$3C
    LDB #$F0
    AND B, A
    CMP B, #$30
    JZ CPU_35_OK
    MOV A, B
    LDB #$30
    JMP FATAL_FAIL_AB
CPU_35_OK:

    ; ------------------------------------------------------------------------
    ; 36 OR A,B
    ; ------------------------------------------------------------------------
    STI CURRENT_TEST, #$36
    STI DISPLAY_LOW,  #$36
    LDA #$C0
    LDB #$0F
    OR A, B
    CMP A, #$CF
    JZ CPU_36_OK
    LDB #$CF
    JMP FATAL_FAIL_AB
CPU_36_OK:

    ; ------------------------------------------------------------------------
    ; 37 OR B,A
    ; ------------------------------------------------------------------------
    STI CURRENT_TEST, #$37
    STI DISPLAY_LOW,  #$37
    LDA #$0F
    LDB #$C0
    OR B, A
    CMP B, #$CF
    JZ CPU_37_OK
    MOV A, B
    LDB #$CF
    JMP FATAL_FAIL_AB
CPU_37_OK:

    ; ------------------------------------------------------------------------
    ; 38 XOR A,B
    ; ------------------------------------------------------------------------
    STI CURRENT_TEST, #$38
    STI DISPLAY_LOW,  #$38
    LDA #$AA
    LDB #$0F
    XOR A, B
    CMP A, #$A5
    JZ CPU_38_OK
    LDB #$A5
    JMP FATAL_FAIL_AB
CPU_38_OK:

    ; ------------------------------------------------------------------------
    ; 39 XOR B,A
    ; ------------------------------------------------------------------------
    STI CURRENT_TEST, #$39
    STI DISPLAY_LOW,  #$39
    LDA #$0F
    LDB #$AA
    XOR B, A
    CMP B, #$A5
    JZ CPU_39_OK
    MOV A, B
    LDB #$A5
    JMP FATAL_FAIL_AB
CPU_39_OK:

    ; ------------------------------------------------------------------------
    ; 3A NOT A
    ; ------------------------------------------------------------------------
    STI CURRENT_TEST, #$3A
    STI DISPLAY_LOW,  #$3A
    LDA #$55
    NOT A
    CMP A, #$AA
    JZ CPU_3A_OK
    LDB #$AA
    JMP FATAL_FAIL_AB
CPU_3A_OK:

    ; ------------------------------------------------------------------------
    ; 3B NOT B
    ; ------------------------------------------------------------------------
    STI CURRENT_TEST, #$3B
    STI DISPLAY_LOW,  #$3B
    LDB #$55
    NOT B
    CMP B, #$AA
    JZ CPU_3B_OK
    MOV A, B
    LDB #$AA
    JMP FATAL_FAIL_AB
CPU_3B_OK:

    ; ------------------------------------------------------------------------
    ; 3C SHL A
    ; ------------------------------------------------------------------------
    STI CURRENT_TEST, #$3C
    STI DISPLAY_LOW,  #$3C
    LDA #$81
    SHL A
    CMP A, #$02
    JZ CPU_3C_OK
    LDB #$02
    JMP FATAL_FAIL_AB
CPU_3C_OK:

    ; ------------------------------------------------------------------------
    ; 3D SHR A
    ; ------------------------------------------------------------------------
    STI CURRENT_TEST, #$3D
    STI DISPLAY_LOW,  #$3D
    LDA #$81
    SHR A
    CMP A, #$40
    JZ CPU_3D_OK
    LDB #$40
    JMP FATAL_FAIL_AB
CPU_3D_OK:

    ; ------------------------------------------------------------------------
    ; 3E SHL B
    ; ------------------------------------------------------------------------
    STI CURRENT_TEST, #$3E
    STI DISPLAY_LOW,  #$3E
    LDB #$81
    SHL B
    CMP B, #$02
    JZ CPU_3E_OK
    MOV A, B
    LDB #$02
    JMP FATAL_FAIL_AB
CPU_3E_OK:

    ; ------------------------------------------------------------------------
    ; 3F SHR B
    ; ------------------------------------------------------------------------
    STI CURRENT_TEST, #$3F
    STI DISPLAY_LOW,  #$3F
    LDB #$81
    SHR B
    CMP B, #$40
    JZ CPU_3F_OK
    MOV A, B
    LDB #$40
    JMP FATAL_FAIL_AB
CPU_3F_OK:

    ; ------------------------------------------------------------------------
    ; 40 CMP A,B - result only in flags, registers preserved
    ; ------------------------------------------------------------------------
    STI CURRENT_TEST, #$40
    STI DISPLAY_LOW,  #$40
    LDA #$77
    LDB #$77
    CMP A, B
    JNZ CPU_40_FAIL
    CMP A, #$77
    JNZ CPU_40_FAIL
    CMP B, #$77
    JZ CPU_40_OK
CPU_40_FAIL:
    LDA #$40
    LDB #$00
    JMP FATAL_FAIL_AB
CPU_40_OK:

    ; ------------------------------------------------------------------------
    ; 41 CMP B,A
    ; ------------------------------------------------------------------------
    STI CURRENT_TEST, #$41
    STI DISPLAY_LOW,  #$41
    LDA #$66
    LDB #$66
    CMP B, A
    JNZ CPU_41_FAIL
    CMP A, #$66
    JNZ CPU_41_FAIL
    CMP B, #$66
    JZ CPU_41_OK
CPU_41_FAIL:
    LDA #$41
    LDB #$00
    JMP FATAL_FAIL_AB
CPU_41_OK:

    ; ------------------------------------------------------------------------
    ; 42 INC A
    ; ------------------------------------------------------------------------
    STI CURRENT_TEST, #$42
    STI DISPLAY_LOW,  #$42
    LDA #$7F
    INC A
    CMP A, #$80
    JZ CPU_42_OK
    LDB #$80
    JMP FATAL_FAIL_AB
CPU_42_OK:

    ; ------------------------------------------------------------------------
    ; 43 DEC A
    ; ------------------------------------------------------------------------
    STI CURRENT_TEST, #$43
    STI DISPLAY_LOW,  #$43
    LDA #$00
    DEC A
    CMP A, #$FF
    JZ CPU_43_OK
    LDB #$FF
    JMP FATAL_FAIL_AB
CPU_43_OK:

    ; ------------------------------------------------------------------------
    ; 44 INC B
    ; ------------------------------------------------------------------------
    STI CURRENT_TEST, #$44
    STI DISPLAY_LOW,  #$44
    LDB #$7F
    INC B
    CMP B, #$80
    JZ CPU_44_OK
    MOV A, B
    LDB #$80
    JMP FATAL_FAIL_AB
CPU_44_OK:

    ; ------------------------------------------------------------------------
    ; 45 DEC B
    ; ------------------------------------------------------------------------
    STI CURRENT_TEST, #$45
    STI DISPLAY_LOW,  #$45
    LDB #$00
    DEC B
    CMP B, #$FF
    JZ CPU_45_OK
    MOV A, B
    LDB #$FF
    JMP FATAL_FAIL_AB
CPU_45_OK:

    ; ------------------------------------------------------------------------
    ; 46 CLR A
    ; ------------------------------------------------------------------------
    STI CURRENT_TEST, #$46
    STI DISPLAY_LOW,  #$46
    LDA #$F5
    CLR A
    CMP A, #$00
    JZ CPU_46_OK
    LDB #$00
    JMP FATAL_FAIL_AB
CPU_46_OK:

    ; ------------------------------------------------------------------------
    ; 47 CLR B
    ; ------------------------------------------------------------------------
    STI CURRENT_TEST, #$47
    STI DISPLAY_LOW,  #$47
    LDB #$F5
    CLR B
    CMP B, #$00
    JZ CPU_47_OK
    MOV A, B
    LDB #$00
    JMP FATAL_FAIL_AB
CPU_47_OK:

    ; ------------------------------------------------------------------------
    ; 50 JMP
    ; ------------------------------------------------------------------------
    STI CURRENT_TEST, #$50
    STI DISPLAY_LOW,  #$50
    JMP CPU_50_TAKEN
    LDA #$F0
    LDB #$50
    JMP FATAL_FAIL_AB
CPU_50_TAKEN:

    ; ------------------------------------------------------------------------
    ; 51 JZ - taken and not taken
    ; ------------------------------------------------------------------------
    STI CURRENT_TEST, #$51
    STI DISPLAY_LOW,  #$51
    LDA #$00
    LDB #$00
    CMP A, B
    JZ CPU_51_TAKEN
    LDA #$F1
    LDB #$51
    JMP FATAL_FAIL_AB
CPU_51_TAKEN:
    LDA #$01
    LDB #$00
    CMP A, B
    JZ CPU_51_FAIL
    JMP CPU_51_OK
CPU_51_FAIL:
    LDA #$E1
    LDB #$51
    JMP FATAL_FAIL_AB
CPU_51_OK:

    ; ------------------------------------------------------------------------
    ; 52 JNZ
    ; ------------------------------------------------------------------------
    STI CURRENT_TEST, #$52
    STI DISPLAY_LOW,  #$52
    LDA #$01
    LDB #$00
    CMP A, B
    JNZ CPU_52_TAKEN
    LDA #$F2
    LDB #$52
    JMP FATAL_FAIL_AB
CPU_52_TAKEN:
    LDA #$00
    LDB #$00
    CMP A, B
    JNZ CPU_52_FAIL
    JMP CPU_52_OK
CPU_52_FAIL:
    LDA #$E2
    LDB #$52
    JMP FATAL_FAIL_AB
CPU_52_OK:

    ; ------------------------------------------------------------------------
    ; 53 JC
    ; ------------------------------------------------------------------------
    STI CURRENT_TEST, #$53
    STI DISPLAY_LOW,  #$53
    LDA #$FF
    LDB #$01
    ADD A, B
    JC CPU_53_TAKEN
    LDA #$F3
    LDB #$53
    JMP FATAL_FAIL_AB
CPU_53_TAKEN:
    LDA #$01
    LDB #$01
    ADD A, B
    JC CPU_53_FAIL
    JMP CPU_53_OK
CPU_53_FAIL:
    LDA #$E3
    LDB #$53
    JMP FATAL_FAIL_AB
CPU_53_OK:

    ; ------------------------------------------------------------------------
    ; 54 JNC
    ; ------------------------------------------------------------------------
    STI CURRENT_TEST, #$54
    STI DISPLAY_LOW,  #$54
    LDA #$01
    LDB #$01
    ADD A, B
    JNC CPU_54_TAKEN
    LDA #$F4
    LDB #$54
    JMP FATAL_FAIL_AB
CPU_54_TAKEN:
    LDA #$FF
    LDB #$01
    ADD A, B
    JNC CPU_54_FAIL
    JMP CPU_54_OK
CPU_54_FAIL:
    LDA #$E4
    LDB #$54
    JMP FATAL_FAIL_AB
CPU_54_OK:

    ; ------------------------------------------------------------------------
    ; 55 JN
    ; ------------------------------------------------------------------------
    STI CURRENT_TEST, #$55
    STI DISPLAY_LOW,  #$55
    LDA #$00
    LDB #$01
    CMP A, B
    JN CPU_55_TAKEN
    LDA #$F5
    LDB #$55
    JMP FATAL_FAIL_AB
CPU_55_TAKEN:
    LDA #$01
    LDB #$01
    CMP A, B
    JN CPU_55_FAIL
    JMP CPU_55_OK
CPU_55_FAIL:
    LDA #$E5
    LDB #$55
    JMP FATAL_FAIL_AB
CPU_55_OK:

    ; ------------------------------------------------------------------------
    ; 56 JP
    ; ------------------------------------------------------------------------
    STI CURRENT_TEST, #$56
    STI DISPLAY_LOW,  #$56
    LDA #$01
    LDB #$01
    CMP A, B
    JP CPU_56_TAKEN
    LDA #$F6
    LDB #$56
    JMP FATAL_FAIL_AB
CPU_56_TAKEN:
    LDA #$00
    LDB #$01
    CMP A, B
    JP CPU_56_FAIL
    JMP CPU_56_OK
CPU_56_FAIL:
    LDA #$E6
    LDB #$56
    JMP FATAL_FAIL_AB
CPU_56_OK:

    ; ------------------------------------------------------------------------
    ; 57 JV
    ; ------------------------------------------------------------------------
    STI CURRENT_TEST, #$57
    STI DISPLAY_LOW,  #$57
    LDA #$7F
    LDB #$01
    ADD A, B
    JV CPU_57_TAKEN
    LDA #$F7
    LDB #$57
    JMP FATAL_FAIL_AB
CPU_57_TAKEN:
    LDA #$01
    LDB #$01
    ADD A, B
    JV CPU_57_FAIL
    JMP CPU_57_OK
CPU_57_FAIL:
    LDA #$E7
    LDB #$57
    JMP FATAL_FAIL_AB
CPU_57_OK:

    ; ------------------------------------------------------------------------
    ; 58 JNV
    ; ------------------------------------------------------------------------
    STI CURRENT_TEST, #$58
    STI DISPLAY_LOW,  #$58
    LDA #$01
    LDB #$01
    ADD A, B
    JNV CPU_58_TAKEN
    LDA #$F8
    LDB #$58
    JMP FATAL_FAIL_AB
CPU_58_TAKEN:
    LDA #$7F
    LDB #$01
    ADD A, B
    JNV CPU_58_FAIL
    JMP CPU_58_OK
CPU_58_FAIL:
    LDA #$E8
    LDB #$58
    JMP FATAL_FAIL_AB
CPU_58_OK:

    ; ------------------------------------------------------------------------
    ; 5F SP, 5B PUSH A, 5C PUSH B, 5E POP B, 5D POP A
    ; ------------------------------------------------------------------------
    STI CURRENT_TEST, #$5F
    STI DISPLAY_LOW,  #$5F
    SP $7FFF

    STI CURRENT_TEST, #$5B
    STI DISPLAY_LOW,  #$5B
    LDA #$1A
    PUSH A

    STI CURRENT_TEST, #$5C
    STI DISPLAY_LOW,  #$5C
    LDB #$2B
    PUSH B

    CLR A
    CLR B

    STI CURRENT_TEST, #$5E
    STI DISPLAY_LOW,  #$5E
    POP B
    CMP B, #$2B
    JZ CPU_5E_OK
    MOV A, B
    LDB #$2B
    JMP FATAL_FAIL_AB
CPU_5E_OK:

    STI CURRENT_TEST, #$5D
    STI DISPLAY_LOW,  #$5D
    POP A
    CMP A, #$1A
    JZ CPU_5D_OK
    LDB #$1A
    JMP FATAL_FAIL_AB
CPU_5D_OK:

    ; ------------------------------------------------------------------------
    ; 59 CALL and 5A RET
    ; ------------------------------------------------------------------------
    STI CURRENT_TEST, #$59
    STI DISPLAY_LOW,  #$59
    STI SCRATCH5, #$00
    CALL CPU_CALL_TARGET
    LDA SCRATCH5
    CMP A, #$5A
    JZ CPU_59_5A_OK
    LDB #$5A
    JMP FATAL_FAIL_AB
CPU_59_5A_OK:

    ; ------------------------------------------------------------------------
    ; 60 ADD A,#imm
    ; ------------------------------------------------------------------------
    STI CURRENT_TEST, #$60
    STI DISPLAY_LOW,  #$60
    LDA #$10
    LDB #$77
    ADD A, #$05
    CMP A, #$15
    JNZ CPU_60_FAIL
    CMP B, #$77
    JZ CPU_60_OK
CPU_60_FAIL:
    LDB #$15
    JMP FATAL_FAIL_AB
CPU_60_OK:

    ; ------------------------------------------------------------------------
    ; 61 ADD B,#imm
    ; ------------------------------------------------------------------------
    STI CURRENT_TEST, #$61
    STI DISPLAY_LOW,  #$61
    LDA #$77
    LDB #$10
    ADD B, #$05
    CMP B, #$15
    JNZ CPU_61_FAIL
    CMP A, #$77
    JZ CPU_61_OK
CPU_61_FAIL:
    MOV A, B
    LDB #$15
    JMP FATAL_FAIL_AB
CPU_61_OK:

    ; ------------------------------------------------------------------------
    ; 62 SUB A,#imm
    ; ------------------------------------------------------------------------
    STI CURRENT_TEST, #$62
    STI DISPLAY_LOW,  #$62
    LDA #$20
    LDB #$77
    SUB A, #$05
    CMP A, #$1B
    JNZ CPU_62_FAIL
    CMP B, #$77
    JZ CPU_62_OK
CPU_62_FAIL:
    LDB #$1B
    JMP FATAL_FAIL_AB
CPU_62_OK:

    ; ------------------------------------------------------------------------
    ; 63 SUB B,#imm
    ; ------------------------------------------------------------------------
    STI CURRENT_TEST, #$63
    STI DISPLAY_LOW,  #$63
    LDA #$77
    LDB #$20
    SUB B, #$05
    CMP B, #$1B
    JNZ CPU_63_FAIL
    CMP A, #$77
    JZ CPU_63_OK
CPU_63_FAIL:
    MOV A, B
    LDB #$1B
    JMP FATAL_FAIL_AB
CPU_63_OK:

    ; ------------------------------------------------------------------------
    ; 64 AND A,#imm
    ; ------------------------------------------------------------------------
    STI CURRENT_TEST, #$64
    STI DISPLAY_LOW,  #$64
    LDA #$A5
    LDB #$77
    AND A, #$0F
    CMP A, #$05
    JNZ CPU_64_FAIL
    CMP B, #$77
    JZ CPU_64_OK
CPU_64_FAIL:
    LDB #$05
    JMP FATAL_FAIL_AB
CPU_64_OK:

    ; ------------------------------------------------------------------------
    ; 65 AND B,#imm
    ; ------------------------------------------------------------------------
    STI CURRENT_TEST, #$65
    STI DISPLAY_LOW,  #$65
    LDA #$77
    LDB #$A5
    AND B, #$0F
    CMP B, #$05
    JNZ CPU_65_FAIL
    CMP A, #$77
    JZ CPU_65_OK
CPU_65_FAIL:
    MOV A, B
    LDB #$05
    JMP FATAL_FAIL_AB
CPU_65_OK:

    ; ------------------------------------------------------------------------
    ; 66 OR A,#imm
    ; ------------------------------------------------------------------------
    STI CURRENT_TEST, #$66
    STI DISPLAY_LOW,  #$66
    LDA #$A0
    LDB #$77
    OR A, #$05
    CMP A, #$A5
    JNZ CPU_66_FAIL
    CMP B, #$77
    JZ CPU_66_OK
CPU_66_FAIL:
    LDB #$A5
    JMP FATAL_FAIL_AB
CPU_66_OK:

    ; ------------------------------------------------------------------------
    ; 67 OR B,#imm
    ; ------------------------------------------------------------------------
    STI CURRENT_TEST, #$67
    STI DISPLAY_LOW,  #$67
    LDA #$77
    LDB #$A0
    OR B, #$05
    CMP B, #$A5
    JNZ CPU_67_FAIL
    CMP A, #$77
    JZ CPU_67_OK
CPU_67_FAIL:
    MOV A, B
    LDB #$A5
    JMP FATAL_FAIL_AB
CPU_67_OK:

    ; ------------------------------------------------------------------------
    ; 68 XOR A,#imm
    ; ------------------------------------------------------------------------
    STI CURRENT_TEST, #$68
    STI DISPLAY_LOW,  #$68
    LDA #$AA
    LDB #$77
    XOR A, #$0F
    CMP A, #$A5
    JNZ CPU_68_FAIL
    CMP B, #$77
    JZ CPU_68_OK
CPU_68_FAIL:
    LDB #$A5
    JMP FATAL_FAIL_AB
CPU_68_OK:

    ; ------------------------------------------------------------------------
    ; 69 XOR B,#imm
    ; ------------------------------------------------------------------------
    STI CURRENT_TEST, #$69
    STI DISPLAY_LOW,  #$69
    LDA #$77
    LDB #$AA
    XOR B, #$0F
    CMP B, #$A5
    JNZ CPU_69_FAIL
    CMP A, #$77
    JZ CPU_69_OK
CPU_69_FAIL:
    MOV A, B
    LDB #$A5
    JMP FATAL_FAIL_AB
CPU_69_OK:

    ; ------------------------------------------------------------------------
    ; 6A CMP A,#imm - flags only, A/B preserved
    ; ------------------------------------------------------------------------
    STI CURRENT_TEST, #$6A
    STI DISPLAY_LOW,  #$6A
    LDA #$5C
    LDB #$A7
    CMP A, #$5C
    JNZ CPU_6A_FAIL
    CMP A, #$5C
    JNZ CPU_6A_FAIL
    CMP B, #$A7
    JZ CPU_6A_OK
CPU_6A_FAIL:
    LDA #$6A
    LDB #$00
    JMP FATAL_FAIL_AB
CPU_6A_OK:

    ; ------------------------------------------------------------------------
    ; 6B CMP B,#imm
    ; ------------------------------------------------------------------------
    STI CURRENT_TEST, #$6B
    STI DISPLAY_LOW,  #$6B
    LDA #$A7
    LDB #$5C
    CMP B, #$5C
    JNZ CPU_6B_FAIL
    CMP B, #$5C
    JNZ CPU_6B_FAIL
    CMP A, #$A7
    JZ CPU_6B_OK
CPU_6B_FAIL:
    LDA #$6B
    LDB #$00
    JMP FATAL_FAIL_AB
CPU_6B_OK:

    ; ------------------------------------------------------------------------
    ; 6C TEST A,#imm - flags only, A/B preserved
    ; ------------------------------------------------------------------------
    STI CURRENT_TEST, #$6C
    STI DISPLAY_LOW,  #$6C
    LDA #$A5
    LDB #$77
    TEST A, #$0F
    JZ CPU_6C_FAIL
    CMP A, #$A5
    JNZ CPU_6C_FAIL
    CMP B, #$77
    JZ CPU_6C_OK
CPU_6C_FAIL:
    LDA #$6C
    LDB #$00
    JMP FATAL_FAIL_AB
CPU_6C_OK:

    ; ------------------------------------------------------------------------
    ; 6D TEST B,#imm
    ; ------------------------------------------------------------------------
    STI CURRENT_TEST, #$6D
    STI DISPLAY_LOW,  #$6D
    LDA #$77
    LDB #$A5
    TEST B, #$0F
    JZ CPU_6D_FAIL
    CMP B, #$A5
    JNZ CPU_6D_FAIL
    CMP A, #$77
    JZ CPU_6D_OK
CPU_6D_FAIL:
    LDA #$6D
    LDB #$00
    JMP FATAL_FAIL_AB
CPU_6D_OK:

    ; Opcode 01 HLT is intentionally tested only after every other subsystem.
    STI DISPLAY_HIGH, #$C0
    JMP AFTER_CPU_ISA


CPU_CALL_TARGET:
    ; Arriving here verifies CALL. Returning verifies RET.
    STI CURRENT_TEST, #$5A
    STI DISPLAY_LOW,  #$5A
    STI SCRATCH5, #$5A
    RET


; ============================================================================
; 4. TIMER TESTS
; ============================================================================

TEST_TIMERS:
    STI CURRENT_TEST, #$F3
    STI DISPLAY_LOW,  #$F3
    STI DISPLAY_HIGH, #$01

    STI SYSTEM_STATUS, #$00

    ; TIMER_1MS must eventually latch.
    STI LOOP0, #$04
TIMER_1MS_OUTER:
    LDB #$00
TIMER_1MS_LOOP:
    LDA SYSTEM_STATUS
    TEST A, #$01
    JNZ TIMER_1MS_OK
    INC B
    JNZ TIMER_1MS_LOOP

    LDA LOOP0
    DEC A
    STA LOOP0
    JNZ TIMER_1MS_OUTER

    LDA #$00
    LDB #$01
    JMP FATAL_FAIL_AB

TIMER_1MS_OK:
    STI DISPLAY_HIGH, #$02
    STI SYSTEM_STATUS, #$00

    ; TIMER_500MS must eventually latch.
    ; 08 * 256 * 256 polling attempts provides a large software timeout.
    STI LOOP0, #$08

TIMER_500_OUTER:
    STI LOOP1, #$00

TIMER_500_MIDDLE:
    LDB #$00

TIMER_500_LOOP:
    LDA SYSTEM_STATUS
    TEST A, #$02
    JNZ TIMER_500MS_OK
    INC B
    JNZ TIMER_500_LOOP

    LDA LOOP1
    INC A
    STA LOOP1
    JNZ TIMER_500_MIDDLE

    LDA LOOP0
    DEC A
    STA LOOP0
    JNZ TIMER_500_OUTER

    LDA #$00
    LDB #$02
    JMP FATAL_FAIL_AB

TIMER_500MS_OK:
    STI TIMER_OK, #$01
    STI SYSTEM_STATUS, #$00
    STI DISPLAY_HIGH, #$01
    RET


; ============================================================================
; 5. VIDEO TESTS
; ============================================================================

TEST_VIDEO:
    ; /VIDEO_DETECT is active low.
    LDA SYSTEM_STATUS
    TEST A, #$20
    JNZ VIDEO_NOT_PRESENT

    STI VIDEO_PRESENT, #$01

    CALL VIDEO_TEST_TEXT
    CALL VIDEO_TEST_320
    CALL VIDEO_TEST_160
    CALL VIDEO_TEXT_STATUS_SCREEN

    STI VIDEO_OK, #$01
    RET

VIDEO_NOT_PRESENT:
    STI VIDEO_PRESENT, #$00
    STI VIDEO_OK,      #$FE
    RET


VIDEO_TEST_TEXT:
    STI CURRENT_TEST, #$11
    STI DISPLAY_LOW,  #$11
    STI DISPLAY_HIGH, #$00

    CALL VIDEO_WAIT
    STI VIDEO_CMD, #$11
    CALL VIDEO_WAIT
    STI VIDEO_CMD, #$00
    CALL VIDEO_WAIT
    STI VIDEO_CMD, #$04

    STI VIDEO_X, #$00
    STI VIDEO_Y, #$00
    STI ROW_COUNT, #$00

VIDEO_TEXT_ROW:
    LDA ROW_COUNT
    STA DISPLAY_HIGH
    TEST A, #$01
    JZ VIDEO_TEXT_EVEN

    STI PATTERN_VALUE, #$58
    JMP VIDEO_TEXT_PATTERN_READY

VIDEO_TEXT_EVEN:
    STI PATTERN_VALUE, #$2E

VIDEO_TEXT_PATTERN_READY:
    STI COL_COUNT, #$28

VIDEO_TEXT_COL:
    LDA PATTERN_VALUE
    XOR A, #$76
    STA PATTERN_VALUE
    CALL VIDEO_WRITE_A

    LDA COL_COUNT
    DEC A
    STA COL_COUNT
    JNZ VIDEO_TEXT_COL

    LDA ROW_COUNT
    INC A
    STA ROW_COUNT
    CMP A, #$1E
    JNZ VIDEO_TEXT_ROW

    CALL VIDEO_WAIT

    ; Detailed protocol defines CURSOR_END at bit4 after the last cell.
    LDA VIDEO_STATUS
    TEST A, #$10
    JNZ VIDEO_TEXT_CURSOR_OK

    LDA VIDEO_STATUS
    LDB #$10
    JMP FATAL_FAIL_AB

VIDEO_TEXT_CURSOR_OK:
    ; Read back top-left: expected 'X'.
    CALL VIDEO_WAIT
    STI VIDEO_X, #$00
    STI VIDEO_Y, #$00
    STI VIDEO_CMD, #$20
    CALL VIDEO_WAIT
    LDA VIDEO_DATA
    CMP A, #$58
    JZ VIDEO_TEXT_READ0_OK
    LDB #$58
    JMP FATAL_FAIL_AB
VIDEO_TEXT_READ0_OK:

    ; Read back bottom-right: expected 'X'.
    CALL VIDEO_WAIT
    STI VIDEO_X, #$27
    STI VIDEO_Y, #$1D
    STI VIDEO_CMD, #$20
    CALL VIDEO_WAIT
    LDA VIDEO_DATA
    CMP A, #$58
    JZ VIDEO_TEXT_DONE
    LDB #$58
    JMP FATAL_FAIL_AB

VIDEO_TEXT_DONE:
    CALL DELAY_VISIBLE
    RET


VIDEO_TEST_320:
    STI CURRENT_TEST, #$12
    STI DISPLAY_LOW,  #$12
    STI DISPLAY_HIGH, #$00

    CALL VIDEO_WAIT
    STI VIDEO_CMD, #$12
    CALL VIDEO_WAIT
    STI VIDEO_CMD, #$00
    CALL VIDEO_WAIT

    STI VIDEO_X, #$00
    STI VIDEO_Y, #$00
    STI ROW_COUNT, #$00

VIDEO_320_ROW:
    LDA ROW_COUNT
    STA DISPLAY_HIGH
    TEST A, #$08
    JZ VIDEO_320_START_ZERO
    STI PATTERN_VALUE, #$FF
    JMP VIDEO_320_PATTERN_READY

VIDEO_320_START_ZERO:
    STI PATTERN_VALUE, #$00

VIDEO_320_PATTERN_READY:
    STI COL_COUNT, #$28

VIDEO_320_COL:
    LDA PATTERN_VALUE
    CALL VIDEO_WRITE_A
    XOR A, #$FF
    STA PATTERN_VALUE

    LDA COL_COUNT
    DEC A
    STA COL_COUNT
    JNZ VIDEO_320_COL

    LDA ROW_COUNT
    INC A
    STA ROW_COUNT
    CMP A, #$F0
    JNZ VIDEO_320_ROW

    CALL VIDEO_WAIT

    ; (0,0) = 00.
    CALL VIDEO_WAIT
    STI VIDEO_X, #$00
    STI VIDEO_Y, #$00
    STI VIDEO_CMD, #$20
    CALL VIDEO_WAIT
    LDA VIDEO_DATA
    CMP A, #$00
    JZ VIDEO_320_READ0_OK
    LDB #$00
    JMP FATAL_FAIL_AB
VIDEO_320_READ0_OK:

    ; Center sample (X=20, Y=120) = FF.
    CALL VIDEO_WAIT
    STI VIDEO_X, #$14
    STI VIDEO_Y, #$78
    STI VIDEO_CMD, #$20
    CALL VIDEO_WAIT
    LDA VIDEO_DATA
    CMP A, #$FF
    JZ VIDEO_320_READ1_OK
    LDB #$FF
    JMP FATAL_FAIL_AB
VIDEO_320_READ1_OK:

    ; Bottom-right (X=39, Y=239) = 00.
    CALL VIDEO_WAIT
    STI VIDEO_X, #$27
    STI VIDEO_Y, #$EF
    STI VIDEO_CMD, #$20
    CALL VIDEO_WAIT
    LDA VIDEO_DATA
    CMP A, #$00
    JZ VIDEO_320_DONE
    LDB #$00
    JMP FATAL_FAIL_AB

VIDEO_320_DONE:
    CALL DELAY_VISIBLE
    RET


VIDEO_TEST_160:
    STI CURRENT_TEST, #$13
    STI DISPLAY_LOW,  #$13
    STI DISPLAY_HIGH, #$00

    CALL VIDEO_WAIT
    STI VIDEO_CMD, #$13
    CALL VIDEO_WAIT
    STI VIDEO_CMD, #$00
    CALL VIDEO_WAIT

    STI VIDEO_X, #$00
    STI VIDEO_Y, #$00
    STI ROW_COUNT, #$00

VIDEO_160_ROW:
    LDA ROW_COUNT
    STA DISPLAY_HIGH
    TEST A, #$08
    JZ VIDEO_160_START_ZERO
    STI PATTERN_VALUE, #$FF
    JMP VIDEO_160_PATTERN_READY

VIDEO_160_START_ZERO:
    STI PATTERN_VALUE, #$00

VIDEO_160_PATTERN_READY:
    STI COL_COUNT, #$14

VIDEO_160_COL:
    LDA PATTERN_VALUE
    CALL VIDEO_WRITE_A
    XOR A, #$FF
    STA PATTERN_VALUE

    LDA COL_COUNT
    DEC A
    STA COL_COUNT
    JNZ VIDEO_160_COL

    LDA ROW_COUNT
    INC A
    STA ROW_COUNT
    CMP A, #$78
    JNZ VIDEO_160_ROW

    CALL VIDEO_WAIT

    ; (0,0) = 00.
    CALL VIDEO_WAIT
    STI VIDEO_X, #$00
    STI VIDEO_Y, #$00
    STI VIDEO_CMD, #$20
    CALL VIDEO_WAIT
    LDA VIDEO_DATA
    CMP A, #$00
    JZ VIDEO_160_READ0_OK
    LDB #$00
    JMP FATAL_FAIL_AB
VIDEO_160_READ0_OK:

    ; Center sample (X=10, Y=60) = FF.
    CALL VIDEO_WAIT
    STI VIDEO_X, #$0A
    STI VIDEO_Y, #$3C
    STI VIDEO_CMD, #$20
    CALL VIDEO_WAIT
    LDA VIDEO_DATA
    CMP A, #$FF
    JZ VIDEO_160_READ1_OK
    LDB #$FF
    JMP FATAL_FAIL_AB
VIDEO_160_READ1_OK:

    ; Bottom-right (X=19, Y=119) = FF.
    CALL VIDEO_WAIT
    STI VIDEO_X, #$13
    STI VIDEO_Y, #$77
    STI VIDEO_CMD, #$20
    CALL VIDEO_WAIT
    LDA VIDEO_DATA
    CMP A, #$FF
    JZ VIDEO_160_READ2_OK
    LDB #$FF
    JMP FATAL_FAIL_AB
VIDEO_160_READ2_OK:

    ; Short animation: one lit 8-pixel block crosses the center line.
    CALL VIDEO_WAIT
    STI VIDEO_CMD, #$00
    CALL VIDEO_WAIT

    STI COL_COUNT, #$00

VIDEO_160_ANIM_DRAW:
    CALL VIDEO_WAIT
    LDA COL_COUNT
    STA VIDEO_X
    STI VIDEO_Y, #$3C
    STI VIDEO_DATA, #$FF
    CALL VIDEO_WAIT

    CALL VIDEO_WAIT_3_FRAMES

    ; Erase the current block.
    CALL VIDEO_WAIT
    LDA COL_COUNT
    STA VIDEO_X
    STI VIDEO_Y, #$3C
    STI VIDEO_DATA, #$00
    CALL VIDEO_WAIT

    LDA COL_COUNT
    INC A
    STA COL_COUNT
    CMP A, #$14
    JNZ VIDEO_160_ANIM_DRAW

    RET


VIDEO_TEXT_STATUS_SCREEN:
    STI CURRENT_TEST, #$11
    STI DISPLAY_LOW,  #$11
    STI DISPLAY_HIGH, #$01

    CALL VIDEO_WAIT
    STI VIDEO_CMD, #$11
    CALL VIDEO_WAIT
    STI VIDEO_CMD, #$00
    CALL VIDEO_WAIT
    STI VIDEO_CMD, #$04

    STI VIDEO_X, #$00
    STI VIDEO_Y, #$00
    PTR STR_VIDEO_OK
    CALL VIDEO_PRINT_STRING
    RET


; Wait until BUSY clears. A detected-but-stuck video board is a failure.
VIDEO_WAIT:
    STI LOOP0, #$08

VIDEO_WAIT_OUTER:
    STI LOOP1, #$00

VIDEO_WAIT_MIDDLE:
    LDB #$00

VIDEO_WAIT_LOOP:
    LDA VIDEO_STATUS
    TEST A, #$01
    JZ VIDEO_WAIT_DONE

    INC B
    JNZ VIDEO_WAIT_LOOP

    LDA LOOP1
    INC A
    STA LOOP1
    JNZ VIDEO_WAIT_MIDDLE

    LDA LOOP0
    DEC A
    STA LOOP0
    JNZ VIDEO_WAIT_OUTER

    LDA VIDEO_STATUS
    LDB #$00
    JMP FATAL_FAIL_AB

VIDEO_WAIT_DONE:
    RET


; Input: A = byte to write.
VIDEO_WRITE_A:
    STA VIDEO_TEMP
    CALL VIDEO_WAIT
    LDA VIDEO_TEMP
    STA VIDEO_DATA
    RET


VIDEO_PRINT_STRING:
VIDEO_PRINT_STRING_LOOP:
    LDA [PTR+]
    CMP A, #$00
    JZ VIDEO_PRINT_STRING_DONE
    CALL VIDEO_WRITE_A
    JMP VIDEO_PRINT_STRING_LOOP

VIDEO_PRINT_STRING_DONE:
    CALL VIDEO_WAIT
    RET


VIDEO_WAIT_FRAME_CHANGE:
    STI BYTE_COUNT, #$00
    LDA VIDEO_STATUS
    AND A, #$08
    STA FRAME_OLD

    STI LOOP0, #$04

VIDEO_FRAME_OUTER:
    STI LOOP1, #$00

VIDEO_FRAME_MIDDLE:
    LDB #$00

VIDEO_FRAME_LOOP:
    LDA VIDEO_STATUS
    AND A, #$08
    LDB FRAME_OLD
    CMP A, B
    JNZ VIDEO_FRAME_DONE

    LDB BYTE_COUNT
    INC B
    STB BYTE_COUNT
    JNZ VIDEO_FRAME_LOOP

    LDA LOOP1
    INC A
    STA LOOP1
    JNZ VIDEO_FRAME_MIDDLE

    LDA LOOP0
    DEC A
    STA LOOP0
    JNZ VIDEO_FRAME_OUTER

    LDA #$00
    LDB #$08
    JMP FATAL_FAIL_AB

VIDEO_FRAME_DONE:
    RET


VIDEO_WAIT_3_FRAMES:
    CALL VIDEO_WAIT_FRAME_CHANGE
    CALL VIDEO_WAIT_FRAME_CHANGE
    CALL VIDEO_WAIT_FRAME_CHANGE
    RET


; ============================================================================
; 6. KEYBOARD TEST
; ============================================================================

TEST_KEYBOARD:
    STI CURRENT_TEST, #$F0
    STI DISPLAY_LOW,  #$F0
    STI DISPLAY_HIGH, #$00

    ; /KEYBOARD_DETECT is SYSTEM_STATUS bit 6 and is active low.
    ; High means that no keyboard is connected, so skip the test immediately.
    LDA SYSTEM_STATUS
    TEST A, #$40
    JNZ KEYBOARD_NOT_PRESENT

    LDA VIDEO_PRESENT
    CMP A, #$01
    JNZ KEYBOARD_NO_PROMPT

    PTR STR_KEY_PROMPT
    CALL VIDEO_PRINT_STRING

KEYBOARD_NO_PROMPT:
    ; Ten half-second windows. The absence of a key press is recorded as
    ; skipped, not as a fatal hardware error.
    STI LOOP0, #$14

KEYBOARD_HALF_SECOND:
    STI SYSTEM_STATUS, #$00

KEYBOARD_WAIT:
    LDA SYSTEM_STATUS
    TEST A, #$80
    JNZ KEYBOARD_GOT_KEY

    TEST A, #$02
    JZ KEYBOARD_WAIT

    LDA LOOP0
    DEC A
    STA LOOP0
    JNZ KEYBOARD_HALF_SECOND

KEYBOARD_NOT_PRESENT:
    STI KEY_OK, #$FE
    STI DISPLAY_HIGH, #$FE

    LDA VIDEO_PRESENT
    CMP A, #$01
    JNZ KEYBOARD_DONE

    PTR STR_KEY_SKIPPED
    CALL VIDEO_PRINT_STRING
    RET

KEYBOARD_GOT_KEY:
    LDA KEY_DATA
    STA KEY_VALUE
    STA DISPLAY_HIGH

    ; Reading KEY_DATA must clear KEY_READY.
    LDA SYSTEM_STATUS
    TEST A, #$80
    JZ KEYBOARD_HANDSHAKE_OK

    LDA SYSTEM_STATUS
    LDB #$00
    JMP FATAL_FAIL_AB

KEYBOARD_HANDSHAKE_OK:
    STI KEY_OK, #$01

    LDA VIDEO_PRESENT
    CMP A, #$01
    JNZ KEYBOARD_DONE

    PTR STR_KEY_OK
    CALL VIDEO_PRINT_STRING

KEYBOARD_DONE:
    RET


; ============================================================================
; 7. SOUND TEST
;
; Based on the detailed I/O table:
;   bit0 = NOISE_EN
;   bit1 = TONE_EN
;   bits2..4 = tone select
;   bits5..7 = noise select
; ============================================================================

TEST_SOUND:
    STI CURRENT_TEST, #$F4
    STI DISPLAY_HIGH, #$01
    STI SOUND_INDEX, #$00

SOUND_TONE_LOOP:
    LDA SOUND_INDEX
    SHL A
    SHL A
    OR A, #$02
    STA SOUND_CFG
    STA DISPLAY_LOW

    CALL WAIT_500MS

    LDA SOUND_INDEX
    INC A
    STA SOUND_INDEX
    CMP A, #$08
    JNZ SOUND_TONE_LOOP

    STI SOUND_CFG, #$00
    CALL WAIT_500MS

    STI DISPLAY_HIGH, #$02
    STI SOUND_INDEX, #$00

SOUND_NOISE_LOOP:
    LDA SOUND_INDEX
    SHL A
    SHL A
    SHL A
    SHL A
    SHL A
    OR A, #$01
    STA SOUND_CFG
    STA DISPLAY_LOW

    CALL WAIT_500MS

    LDA SOUND_INDEX
    INC A
    STA SOUND_INDEX
    CMP A, #$08
    JNZ SOUND_NOISE_LOOP

    STI SOUND_CFG, #$00
    STI SOUND_OK, #$01
    STI DISPLAY_HIGH, #$01
    RET


WAIT_500MS:
    STI SYSTEM_STATUS, #$00

WAIT_500MS_LOOP:
    LDA SYSTEM_STATUS
    TEST A, #$02
    JZ WAIT_500MS_LOOP
    RET


; ============================================================================
; 8. CARTRIDGE TEST
; ============================================================================

TEST_CARTRIDGE:
    STI CURRENT_TEST, #$A0
    STI DISPLAY_LOW,  #$A0
    STI DISPLAY_HIGH, #$00

    ; /CARD_DETECT is active low.
    LDA SYSTEM_STATUS
    TEST A, #$10
    JNZ CART_NOT_PRESENT

    STI CART_PRESENT, #$01

    CALL CART_CHECKSUM
    STA CART_SUM1
    STA DISPLAY_HIGH

    CALL CART_CHECKSUM
    STA CART_SUM2

    LDB CART_SUM1
    CMP A, B
    JZ CART_STABLE

    ; A = second checksum, B = first checksum.
    JMP FATAL_FAIL_AB

CART_STABLE:
    STI CART_OK, #$01
    LDA CART_SUM1
    STA DISPLAY_HIGH
    RET

CART_NOT_PRESENT:
    STI CART_PRESENT, #$00
    STI CART_OK,      #$FE
    STI DISPLAY_HIGH, #$FE
    RET


; Returns A = XOR checksum over 0xA000..0xEFFF (20 KiB).
CART_CHECKSUM:
    PTR $A000
    STI CHECKSUM_VALUE, #$00
    STI PAGE_COUNT,     #$50

CART_CHECKSUM_PAGE:
    LDA PAGE_COUNT
    STA DISPLAY_HIGH
    STI BYTE_COUNT, #$00

CART_CHECKSUM_BYTE:
    LDA [PTR+]
    LDB CHECKSUM_VALUE
    XOR A, B
    STA CHECKSUM_VALUE

    LDA BYTE_COUNT
    INC A
    STA BYTE_COUNT
    JNZ CART_CHECKSUM_BYTE

    LDA PAGE_COUNT
    DEC A
    STA PAGE_COUNT
    JNZ CART_CHECKSUM_PAGE

    LDA CHECKSUM_VALUE
    RET


; ============================================================================
; FINAL SUMMARY
; ============================================================================

SHOW_FINAL_SUMMARY:
    LDA VIDEO_PRESENT
    CMP A, #$01
    JNZ FINAL_NO_VIDEO

    CALL VIDEO_WAIT
    STI VIDEO_CMD, #$11
    CALL VIDEO_WAIT
    STI VIDEO_CMD, #$00
    CALL VIDEO_WAIT
    STI VIDEO_CMD, #$04
    STI VIDEO_X,   #$00
    STI VIDEO_Y,   #$00

    PTR STR_FINAL_1
    CALL VIDEO_PRINT_STRING
    PTR STR_FINAL_2
    CALL VIDEO_PRINT_STRING
    PTR STR_FINAL_3
    CALL VIDEO_PRINT_STRING
    PTR STR_FINAL_4
    CALL VIDEO_PRINT_STRING
    PTR STR_FINAL_5
    CALL VIDEO_PRINT_STRING

    LDA KEY_OK
    CMP A, #$01
    JZ FINAL_KEY_OK
    PTR STR_FINAL_KEY_SKIP
    CALL VIDEO_PRINT_STRING
    JMP FINAL_CART_LINE

FINAL_KEY_OK:
    PTR STR_FINAL_KEY_OK
    CALL VIDEO_PRINT_STRING

FINAL_CART_LINE:
    LDA CART_OK
    CMP A, #$01
    JZ FINAL_CART_OK
    PTR STR_FINAL_CART_SKIP
    CALL VIDEO_PRINT_STRING
    JMP FINAL_HALT_LINE

FINAL_CART_OK:
    PTR STR_FINAL_CART_OK
    CALL VIDEO_PRINT_STRING

FINAL_HALT_LINE:
    PTR STR_FINAL_HALT
    CALL VIDEO_PRINT_STRING

FINAL_NO_VIDEO:
    STI DISPLAY_HIGH, #$A0
    STI DISPLAY_LOW,  #$00
    CALL DELAY_VISIBLE
    RET


; ============================================================================
; FATAL FAILURE
; ============================================================================

; Input: A = actual, B = expected.
FATAL_FAIL_AB:
    STA FAIL_ACTUAL
    STB FAIL_EXPECTED

FATAL_FAIL_FROM_MEMORY:
    LDA CURRENT_TEST
    STA DISPLAY_LOW

FATAL_FAIL_LOOP:
    LDA FAIL_EXPECTED
    STA DISPLAY_HIGH

    LDA #$FF
FATAL_FAIL_D1:
    LDB #$FF
FATAL_FAIL_D2:
    DEC B
    JNZ FATAL_FAIL_D2
    DEC A
    JNZ FATAL_FAIL_D1

    LDA FAIL_ACTUAL
    STA DISPLAY_HIGH

    LDA #$FF
FATAL_FAIL_D3:
    LDB #$FF
FATAL_FAIL_D4:
    DEC B
    JNZ FATAL_FAIL_D4
    DEC A
    JNZ FATAL_FAIL_D3

    JMP FATAL_FAIL_LOOP


; ============================================================================
; SOFTWARE DELAY FOR VISUAL-ONLY STEPS
; ============================================================================

DELAY_VISIBLE:
    LDA #$FF

DELAY_VISIBLE_OUTER:
    LDB #$FF

DELAY_VISIBLE_INNER:
    DEC B
    JNZ DELAY_VISIBLE_INNER
    DEC A
    JNZ DELAY_VISIBLE_OUTER
    RET


; ============================================================================
; TEXT STRINGS
; ============================================================================

STR_VIDEO_OK:
    #d8 0x0D
    #d8 0x56, 0x49, 0x44, 0x45, 0x4F, 0x3A, 0x20, 0x54, 0x45, 0x58, 0x54, 0x20, 0x34, 0x30, 0x78, 0x33
    #d8 0x30, 0x20, 0x4F, 0x4B, 0x0D
    #d8 0x56, 0x49, 0x44, 0x45, 0x4F, 0x3A, 0x20, 0x33, 0x32, 0x30, 0x78, 0x32, 0x34, 0x30, 0x20, 0x4F
    #d8 0x4B, 0x0D
    #d8 0x56, 0x49, 0x44, 0x45, 0x4F, 0x3A, 0x20, 0x31, 0x36, 0x30, 0x78, 0x31, 0x32, 0x30, 0x20, 0x4F
    #d8 0x4B, 0x0D, 0x00

STR_KEY_PROMPT:
    #d8 0x50, 0x52, 0x45, 0x53, 0x53, 0x20, 0x41, 0x4E, 0x59, 0x20, 0x4B, 0x45, 0x59, 0x20, 0x2D, 0x20
    #d8 0x31, 0x30, 0x20, 0x53, 0x45, 0x43, 0x0D, 0x00

STR_KEY_OK:
    #d8 0x4B, 0x45, 0x59, 0x42, 0x4F, 0x41, 0x52, 0x44, 0x3A, 0x20, 0x4F, 0x4B, 0x0D, 0x00

STR_KEY_SKIPPED:
    #d8 0x4B, 0x45, 0x59, 0x42, 0x4F, 0x41, 0x52, 0x44, 0x3A, 0x20, 0x4E, 0x4F, 0x20, 0x4B, 0x45
    #d8 0x59, 0x20, 0x2D, 0x20, 0x53, 0x4B, 0x49, 0x50, 0x0D, 0x00

STR_FINAL_1:
    #d8 0x57, 0x41, 0x4C, 0x4C, 0x2D, 0x38, 0x20, 0x43, 0x48, 0x45, 0x43, 0x4B, 0x55, 0x50, 0x20, 0x43
    #d8 0x4F, 0x4D, 0x50, 0x4C, 0x45, 0x54, 0x45, 0x0D, 0x00

STR_FINAL_2:
    #d8 0x52, 0x41, 0x4D, 0x20, 0x33, 0x32, 0x4B, 0x3A, 0x20, 0x4F, 0x4B, 0x0D, 0x00

STR_FINAL_3:
    #d8 0x43, 0x50, 0x55, 0x20, 0x49, 0x53, 0x41, 0x20, 0x37, 0x36, 0x20, 0x4F, 0x50, 0x43, 0x4F, 0x44
    #d8 0x45, 0x53, 0x3A, 0x20, 0x4F, 0x4B, 0x0D, 0x00

STR_FINAL_4:
    #d8 0x54, 0x49, 0x4D, 0x45, 0x52, 0x53, 0x20, 0x31, 0x4D, 0x53, 0x2F, 0x35, 0x30, 0x30, 0x4D, 0x53
    #d8 0x3A, 0x20, 0x4F, 0x4B, 0x0D, 0x00

STR_FINAL_5:
    #d8 0x53, 0x4F, 0x55, 0x4E, 0x44, 0x20, 0x54, 0x4F, 0x4E, 0x45, 0x2F, 0x4E, 0x4F, 0x49, 0x53, 0x45
    #d8 0x3A, 0x20, 0x4F, 0x4B, 0x0D, 0x00

STR_FINAL_KEY_OK:
    #d8 0x4B, 0x45, 0x59, 0x42, 0x4F, 0x41, 0x52, 0x44, 0x3A, 0x20, 0x4F, 0x4B, 0x0D, 0x00

STR_FINAL_KEY_SKIP:
    #d8 0x4B, 0x45, 0x59, 0x42, 0x4F, 0x41, 0x52, 0x44, 0x3A, 0x20, 0x53, 0x4B, 0x49, 0x50, 0x0D, 0x00

STR_FINAL_CART_OK:
    #d8 0x43, 0x41, 0x52, 0x54, 0x52, 0x49, 0x44, 0x47, 0x45, 0x3A, 0x20, 0x50, 0x52, 0x45, 0x53, 0x45
    #d8 0x4E, 0x54, 0x20, 0x2F, 0x20, 0x53, 0x54, 0x41, 0x42, 0x4C, 0x45, 0x0D, 0x00

STR_FINAL_CART_SKIP:
    #d8 0x43, 0x41, 0x52, 0x54, 0x52, 0x49, 0x44, 0x47, 0x45, 0x3A, 0x20, 0x4E, 0x4F, 0x54, 0x20, 0x50
    #d8 0x52, 0x45, 0x53, 0x45, 0x4E, 0x54, 0x20, 0x2D, 0x20, 0x53, 0x4B, 0x49, 0x50, 0x0D, 0x00

STR_FINAL_HALT:
    #d8 0x48, 0x4C, 0x54, 0x20, 0x54, 0x45, 0x53, 0x54, 0x3A, 0x20, 0x43, 0x50, 0x55, 0x20, 0x53, 0x48
    #d8 0x4F, 0x55, 0x4C, 0x44, 0x20, 0x53, 0x54, 0x4F, 0x50, 0x20, 0x4E, 0x4F, 0x57, 0x0D, 0x00


; Safety jump in the final three bytes of the fixed 8 KiB ROM window.
#addr 0x9FFD
    JMP CHECKUP_MAIN
