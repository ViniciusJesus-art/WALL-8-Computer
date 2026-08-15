#include "../wall8.cpu"

#bankdef cart {
    #addr 0xA000
    #size 0x5000
    #outp 0x0000
}

#bank cart
#addr 0xA000

; ============================================================================
; WALL-8 - JINGLE BELLS
; Player com duracoes variadas
;
; Usa TIMER_500MS sempre que possivel.
; Usa TIMER_1MS para:
;   - 125 ms
;   - 250 ms
;   - pequena articulacao entre notas
;
; TIMER_1MS = 1024 Hz
; 128 ticks = 125 ms aproximadamente/exatamente pela base de 1024 Hz
;
; SOUND_CFG:
;   C5 = $02
;   B4 = $06
;   A4 = $0A
;   G4 = $0E
;   F4 = $12
;   E4 = $16
;   D4 = $1A
;   C4 = $1E
;   REST = $00
;
; Formato da musica:
;   #d8 NOTA, DURACAO
;
; Duracoes:
;   $01 = 125 ms
;   $02 = 250 ms
;   $03 = 500 ms
;   $04 = 750 ms
;   $05 = 1000 ms
;   $06 = 1500 ms
;
; $FF = fim
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
REST    = $00

DUR_125  = $01
DUR_250  = $02
DUR_500  = $03
DUR_750  = $04
DUR_1000 = $05
DUR_1500 = $06

END_SONG = $FF


START:

    STI SOUND_CFG, #REST

    ; pequena espera antes de iniciar
    CALL WAIT_500MS

    PTR SONG_DATA


; ============================================================================
; PLAYER
; ============================================================================

PLAY_NEXT:

    ; le nota
    LDA [PTR+]

    CMP A, #END_SONG
    JZ SONG_FINISHED

    ; ativa nota (ou silencio, caso seja REST)
    STA SOUND_CFG

    ; le duracao
    LDA [PTR+]

    CMP A, #DUR_125
    JZ PLAY_125

    CMP A, #DUR_250
    JZ PLAY_250

    CMP A, #DUR_500
    JZ PLAY_500

    CMP A, #DUR_750
    JZ PLAY_750

    CMP A, #DUR_1000
    JZ PLAY_1000

    ; qualquer outro valor valido aqui = 1500 ms
PLAY_1500:
    CALL WAIT_500MS
    CALL WAIT_500MS
    CALL WAIT_500MS
    JMP NOTE_DONE


PLAY_125:
    CALL WAIT_125MS
    JMP NOTE_DONE


PLAY_250:
    CALL WAIT_250MS
    JMP NOTE_DONE


PLAY_500:
    CALL WAIT_500MS
    JMP NOTE_DONE


PLAY_750:
    CALL WAIT_500MS
    CALL WAIT_250MS
    JMP NOTE_DONE


PLAY_1000:
    CALL WAIT_500MS
    CALL WAIT_500MS


NOTE_DONE:

    ; articula as notas.
    ; aproximadamente 15.6 ms de silencio.
    STI SOUND_CFG, #REST
    CALL GAP_16MS

    JMP PLAY_NEXT


SONG_FINISHED:

    STI SOUND_CFG, #REST

    ; pausa antes de retornar para a BIOS
    CALL WAIT_500MS

    RET


; ============================================================================
; TIMER 500 ms
;
; SYSTEM_STATUS guarda flags retidas:
; limpa primeiro e espera o hardware setar novamente.
; ============================================================================

WAIT_500MS:

    STI SYSTEM_STATUS, #$00

WAIT_500MS_LOOP:

    LDA SYSTEM_STATUS
    TEST A, #TIMER_500MS_MASK
    JZ WAIT_500MS_LOOP

    RET


; ============================================================================
; Um tick do timer de ~1 ms
; ============================================================================

WAIT_1MS:

    STI SYSTEM_STATUS, #$00

WAIT_1MS_LOOP:

    LDA SYSTEM_STATUS
    TEST A, #TIMER_1MS_MASK
    JZ WAIT_1MS_LOOP

    RET


; ============================================================================
; 125 ms
;
; 128 / 1024 s = 0.125 s
; ============================================================================

WAIT_125MS:

    LDB #$80

WAIT_125MS_LOOP:

    CALL WAIT_1MS

    DEC B
    JNZ WAIT_125MS_LOOP

    RET


; ============================================================================
; 250 ms = 125 + 125
; ============================================================================

WAIT_250MS:

    CALL WAIT_125MS
    CALL WAIT_125MS

    RET


; ============================================================================
; Articulacao ~15.625 ms
; ============================================================================

GAP_16MS:

    LDB #$10

GAP_16MS_LOOP:

    CALL WAIT_1MS

    DEC B
    JNZ GAP_16MS_LOOP

    RET


; ============================================================================
; JINGLE BELLS
;
; Ritmo aproximado da melodia tradicional.
;
; E E E
; E E E
; E G C D E
; F F F F F E E
; E D D E D G
;
; E E E
; E E E
; E G C D E
; F F F F F E E
; G G F D C
; ============================================================================

SONG_DATA:

    ; "Jingle bells, jingle bells"
    #d8 NOTE_E4, DUR_500
    #d8 NOTE_E4, DUR_500
    #d8 NOTE_E4, DUR_1000

    #d8 NOTE_E4, DUR_500
    #d8 NOTE_E4, DUR_500
    #d8 NOTE_E4, DUR_1000

    ; "Jingle all the way"
    #d8 NOTE_E4, DUR_500
    #d8 NOTE_G4, DUR_500
    #d8 NOTE_C4, DUR_750
    #d8 NOTE_D4, DUR_250
    #d8 NOTE_E4, DUR_1500

    ; "Oh what fun it is to ride"
    #d8 NOTE_F4, DUR_500
    #d8 NOTE_F4, DUR_500
    #d8 NOTE_F4, DUR_750
    #d8 NOTE_F4, DUR_250

    #d8 NOTE_F4, DUR_500
    #d8 NOTE_E4, DUR_500
    #d8 NOTE_E4, DUR_500
    #d8 NOTE_E4, DUR_250
    #d8 NOTE_E4, DUR_250

    ; "In a one horse open sleigh"
    #d8 NOTE_E4, DUR_500
    #d8 NOTE_D4, DUR_500
    #d8 NOTE_D4, DUR_500
    #d8 NOTE_E4, DUR_500
    #d8 NOTE_D4, DUR_1000
    #d8 NOTE_G4, DUR_1000


    ; Segunda passagem
    #d8 NOTE_E4, DUR_500
    #d8 NOTE_E4, DUR_500
    #d8 NOTE_E4, DUR_1000

    #d8 NOTE_E4, DUR_500
    #d8 NOTE_E4, DUR_500
    #d8 NOTE_E4, DUR_1000

    #d8 NOTE_E4, DUR_500
    #d8 NOTE_G4, DUR_500
    #d8 NOTE_C4, DUR_750
    #d8 NOTE_D4, DUR_250
    #d8 NOTE_E4, DUR_1500

    #d8 NOTE_F4, DUR_500
    #d8 NOTE_F4, DUR_500
    #d8 NOTE_F4, DUR_500
    #d8 NOTE_F4, DUR_500

    #d8 NOTE_F4, DUR_500
    #d8 NOTE_E4, DUR_500
    #d8 NOTE_E4, DUR_500
    #d8 NOTE_E4, DUR_250
    #d8 NOTE_E4, DUR_250

    ; Final
    #d8 NOTE_G4, DUR_500
    #d8 NOTE_G4, DUR_500
    #d8 NOTE_F4, DUR_500
    #d8 NOTE_D4, DUR_500
    #d8 NOTE_C4, DUR_1500

    #d8 END_SONG


; ============================================================================
; Protecao
; ============================================================================

#addr 0xEFFD
    JMP START
