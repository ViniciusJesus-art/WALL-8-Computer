#include "../wall8.cpu"

#bankdef cart {
    #addr 0xA000
    #size 0x5000
    #outp 0x0000
}

#bank cart
#addr 0xA000

; ============================================================================
; WALL-8 - ODE TO JOY - FIXED
;
; CORRECOES IMPORTANTES:
;   1. Codigo montado no endereco real do cartucho: $A000.
;      Assim CALL/JMP apontam para $Axxx, e nao para RAM baixa.
;
;   2. Os timers de SYSTEM_STATUS sao FLAGS RETIDAS.
;      Para esperar um novo tick:
;          STI SYSTEM_STATUS, #$00
;          esperar o bit ficar 1
;
;      Nao se deve esperar o bit voltar a zero sozinho.
;
; SOUND_CFG ($F400)
;   bit 0     = NOISE_EN
;   bit 1     = TONE_EN
;   bits 4..2 = TONE[2:0]
;   bits 7..5 = NOISE[2:0]
;
; Tones usados:
;   C5 = 000 -> $02
;   B4 = 001 -> $06
;   A4 = 010 -> $0A
;   G4 = 011 -> $0E
;   F4 = 100 -> $12
;   E4 = 101 -> $16
;   D4 = 110 -> $1A
;   C4 = 111 -> $1E
;
; SYSTEM_STATUS ($F300)
;   bit 0 = TIMER_1MS   (~1024 Hz, 0.9765625 ms)
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


; ============================================================================
; ENTRY POINT - BIOS chama CALL $A000
; ============================================================================

START:

    ; Garante silencio inicial.
    STI SOUND_CFG, #SILENCE

    ; Pequena pausa antes de iniciar.
    CALL WAIT_500MS


; ============================================================================
; ODE TO JOY
;
; E E F G | G F E D | C C D E | E D D
; E E F G | G F E D | C C D E | D C C
; ============================================================================

    ; ------------------------------------------------------------------------
    ; Frase 1
    ; ------------------------------------------------------------------------

    STI SOUND_CFG, #NOTE_E4
    CALL NOTE_SHORT

    STI SOUND_CFG, #NOTE_E4
    CALL NOTE_SHORT

    STI SOUND_CFG, #NOTE_F4
    CALL NOTE_SHORT

    STI SOUND_CFG, #NOTE_G4
    CALL NOTE_SHORT


    STI SOUND_CFG, #NOTE_G4
    CALL NOTE_SHORT

    STI SOUND_CFG, #NOTE_F4
    CALL NOTE_SHORT

    STI SOUND_CFG, #NOTE_E4
    CALL NOTE_SHORT

    STI SOUND_CFG, #NOTE_D4
    CALL NOTE_SHORT


    STI SOUND_CFG, #NOTE_C4
    CALL NOTE_SHORT

    STI SOUND_CFG, #NOTE_C4
    CALL NOTE_SHORT

    STI SOUND_CFG, #NOTE_D4
    CALL NOTE_SHORT

    STI SOUND_CFG, #NOTE_E4
    CALL NOTE_SHORT


    STI SOUND_CFG, #NOTE_E4
    CALL NOTE_SHORT

    STI SOUND_CFG, #NOTE_D4
    CALL NOTE_SHORT

    STI SOUND_CFG, #NOTE_D4
    CALL NOTE_LONG


    ; ------------------------------------------------------------------------
    ; Frase 2
    ; ------------------------------------------------------------------------

    STI SOUND_CFG, #NOTE_E4
    CALL NOTE_SHORT

    STI SOUND_CFG, #NOTE_E4
    CALL NOTE_SHORT

    STI SOUND_CFG, #NOTE_F4
    CALL NOTE_SHORT

    STI SOUND_CFG, #NOTE_G4
    CALL NOTE_SHORT


    STI SOUND_CFG, #NOTE_G4
    CALL NOTE_SHORT

    STI SOUND_CFG, #NOTE_F4
    CALL NOTE_SHORT

    STI SOUND_CFG, #NOTE_E4
    CALL NOTE_SHORT

    STI SOUND_CFG, #NOTE_D4
    CALL NOTE_SHORT


    STI SOUND_CFG, #NOTE_C4
    CALL NOTE_SHORT

    STI SOUND_CFG, #NOTE_C4
    CALL NOTE_SHORT

    STI SOUND_CFG, #NOTE_D4
    CALL NOTE_SHORT

    STI SOUND_CFG, #NOTE_E4
    CALL NOTE_SHORT


    STI SOUND_CFG, #NOTE_D4
    CALL NOTE_SHORT

    STI SOUND_CFG, #NOTE_C4
    CALL NOTE_SHORT

    STI SOUND_CFG, #NOTE_C4
    CALL NOTE_LONG


    ; Silencio antes de retornar para a BIOS.
    STI SOUND_CFG, #SILENCE
    CALL WAIT_500MS

    RET


; ============================================================================
; NOTE_SHORT
;
; A nota JA esta ativa quando entramos aqui.
; Mantem por ~500 ms, desliga e cria pequeno gap (~20 ms).
; ============================================================================

NOTE_SHORT:

    CALL WAIT_500MS

    STI SOUND_CFG, #SILENCE
    CALL GAP_20MS

    RET


; ============================================================================
; NOTE_LONG
;
; Mantem por ~1 segundo.
; ============================================================================

NOTE_LONG:

    CALL WAIT_500MS
    CALL WAIT_500MS

    STI SOUND_CFG, #SILENCE
    CALL GAP_20MS

    RET


; ============================================================================
; WAIT_500MS
;
; Forma CORRETA para o timer latched do WALL:
;
;   1. limpa os flags escrevendo SYSTEM_STATUS;
;   2. espera TIMER_500MS ser novamente setado pelo hardware.
;
; Igual ao metodo usado pelo checkup oficial.
; ============================================================================

WAIT_500MS:

    STI SYSTEM_STATUS, #$00

WAIT_500MS_LOOP:

    LDA SYSTEM_STATUS
    TEST A, #TIMER_500MS_MASK
    JZ WAIT_500MS_LOOP

    RET


; ============================================================================
; WAIT_1MS
;
; TIMER_1MS tambem e uma flag retida.
; ============================================================================

WAIT_1MS:

    STI SYSTEM_STATUS, #$00

WAIT_1MS_LOOP:

    LDA SYSTEM_STATUS
    TEST A, #TIMER_1MS_MASK
    JZ WAIT_1MS_LOOP

    RET


; ============================================================================
; GAP_20MS
;
; Aproximadamente 20 ticks do TIMER_1MS.
; B e usado como contador.
; ============================================================================

GAP_20MS:

    LDB #$14

GAP_20MS_LOOP:

    CALL WAIT_1MS

    DEC B
    JNZ GAP_20MS_LOOP

    RET


; ============================================================================
; Seguranca: caso a CPU caia no final da area de cartucho por algum motivo.
; ============================================================================

#addr 0xEFFD
    JMP START
