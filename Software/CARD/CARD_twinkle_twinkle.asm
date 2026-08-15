#include "../wall8.cpu"

#bankdef cart {
    #addr 0xA000
    #size 0x5000
    #outp 0x0000
}

#bank cart
#addr 0xA000

; ============================================================================
; WALL-8 - TWINKLE TWINKLE LITTLE STAR
;
; SOUND_CFG ($F400)
;   bit 0     = NOISE_EN
;   bit 1     = TONE_EN
;   bits 4..2 = TONE[2:0]
;
; Mapeamento atual do hardware:
;   C5 = $02
;   B4 = $06
;   A4 = $0A
;   G4 = $0E
;   F4 = $12
;   E4 = $16
;   D4 = $1A
;   C4 = $1E
;
; SYSTEM_STATUS ($F300)
;   bit 0 = TIMER_1MS
;   bit 1 = TIMER_500MS
; ============================================================================

SYSTEM_STATUS = $F300
SOUND_CFG     = $F400

TIMER_1MS_MASK   = $01
TIMER_500MS_MASK = $02

NOTE_C4 = $1E
NOTE_D4 = $1A
NOTE_E4 = $16
NOTE_F4 = $12
NOTE_G4 = $0E
NOTE_A4 = $0A
NOTE_B4 = $06
NOTE_C5 = $02

SILENCE = $00


START:

    STI SOUND_CFG, #SILENCE
    CALL WAIT_500MS


; ============================================================================
; TWINKLE TWINKLE
;
; C C G G A A G
; F F E E D D C
; G G F F E E D
; G G F F E E D
; C C G G A A G
; F F E E D D C
; ============================================================================

    ; C C G G A A G
    STI SOUND_CFG, #NOTE_C4
    CALL NOTE_SHORT

    STI SOUND_CFG, #NOTE_C4
    CALL NOTE_SHORT

    STI SOUND_CFG, #NOTE_G4
    CALL NOTE_SHORT

    STI SOUND_CFG, #NOTE_G4
    CALL NOTE_SHORT

    STI SOUND_CFG, #NOTE_A4
    CALL NOTE_SHORT

    STI SOUND_CFG, #NOTE_A4
    CALL NOTE_SHORT

    STI SOUND_CFG, #NOTE_G4
    CALL NOTE_LONG


    ; F F E E D D C
    STI SOUND_CFG, #NOTE_F4
    CALL NOTE_SHORT

    STI SOUND_CFG, #NOTE_F4
    CALL NOTE_SHORT

    STI SOUND_CFG, #NOTE_E4
    CALL NOTE_SHORT

    STI SOUND_CFG, #NOTE_E4
    CALL NOTE_SHORT

    STI SOUND_CFG, #NOTE_D4
    CALL NOTE_SHORT

    STI SOUND_CFG, #NOTE_D4
    CALL NOTE_SHORT

    STI SOUND_CFG, #NOTE_C4
    CALL NOTE_LONG


    ; G G F F E E D
    STI SOUND_CFG, #NOTE_G4
    CALL NOTE_SHORT

    STI SOUND_CFG, #NOTE_G4
    CALL NOTE_SHORT

    STI SOUND_CFG, #NOTE_F4
    CALL NOTE_SHORT

    STI SOUND_CFG, #NOTE_F4
    CALL NOTE_SHORT

    STI SOUND_CFG, #NOTE_E4
    CALL NOTE_SHORT

    STI SOUND_CFG, #NOTE_E4
    CALL NOTE_SHORT

    STI SOUND_CFG, #NOTE_D4
    CALL NOTE_LONG


    ; G G F F E E D
    STI SOUND_CFG, #NOTE_G4
    CALL NOTE_SHORT

    STI SOUND_CFG, #NOTE_G4
    CALL NOTE_SHORT

    STI SOUND_CFG, #NOTE_F4
    CALL NOTE_SHORT

    STI SOUND_CFG, #NOTE_F4
    CALL NOTE_SHORT

    STI SOUND_CFG, #NOTE_E4
    CALL NOTE_SHORT

    STI SOUND_CFG, #NOTE_E4
    CALL NOTE_SHORT

    STI SOUND_CFG, #NOTE_D4
    CALL NOTE_LONG


    ; C C G G A A G
    STI SOUND_CFG, #NOTE_C4
    CALL NOTE_SHORT

    STI SOUND_CFG, #NOTE_C4
    CALL NOTE_SHORT

    STI SOUND_CFG, #NOTE_G4
    CALL NOTE_SHORT

    STI SOUND_CFG, #NOTE_G4
    CALL NOTE_SHORT

    STI SOUND_CFG, #NOTE_A4
    CALL NOTE_SHORT

    STI SOUND_CFG, #NOTE_A4
    CALL NOTE_SHORT

    STI SOUND_CFG, #NOTE_G4
    CALL NOTE_LONG


    ; F F E E D D C
    STI SOUND_CFG, #NOTE_F4
    CALL NOTE_SHORT

    STI SOUND_CFG, #NOTE_F4
    CALL NOTE_SHORT

    STI SOUND_CFG, #NOTE_E4
    CALL NOTE_SHORT

    STI SOUND_CFG, #NOTE_E4
    CALL NOTE_SHORT

    STI SOUND_CFG, #NOTE_D4
    CALL NOTE_SHORT

    STI SOUND_CFG, #NOTE_D4
    CALL NOTE_SHORT

    STI SOUND_CFG, #NOTE_C4
    CALL NOTE_LONG


    STI SOUND_CFG, #SILENCE
    CALL WAIT_500MS
    RET


; ============================================================================
; Duracoes
; ============================================================================

NOTE_SHORT:
    CALL WAIT_500MS
    STI SOUND_CFG, #SILENCE
    CALL GAP_20MS
    RET


NOTE_LONG:
    CALL WAIT_500MS
    CALL WAIT_500MS
    STI SOUND_CFG, #SILENCE
    CALL GAP_20MS
    RET


; ============================================================================
; Timer 500 ms - flag retida
; ============================================================================

WAIT_500MS:
    STI SYSTEM_STATUS, #$00

WAIT_500MS_LOOP:
    LDA SYSTEM_STATUS
    TEST A, #TIMER_500MS_MASK
    JZ WAIT_500MS_LOOP
    RET


; ============================================================================
; Timer ~1 ms - flag retida
; ============================================================================

WAIT_1MS:
    STI SYSTEM_STATUS, #$00

WAIT_1MS_LOOP:
    LDA SYSTEM_STATUS
    TEST A, #TIMER_1MS_MASK
    JZ WAIT_1MS_LOOP
    RET


; ============================================================================
; Gap curto entre notas
; ============================================================================

GAP_20MS:
    LDB #$14

GAP_20MS_LOOP:
    CALL WAIT_1MS
    DEC B
    JNZ GAP_20MS_LOOP
    RET


#addr 0xEFFD
    JMP START
