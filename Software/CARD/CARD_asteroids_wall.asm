#include "../wall8.cpu"

; ============================================================================
; WALL-8 - ASTEROIDS
; ============================================================================
; Cartucho: $A000-$EFFF (20 KiB)
; Video:    grafico monocromatico 320x240
;
; O campo de jogo usa 256x192 pixels reais dentro da tela:
;   X mundo 0..255 -> pixels VGA 32..287
;   Y mundo 0..191 -> pixels VGA 32..223
;
; Isso permite X com precisao de 1 pixel usando apenas 8 bits. Os sprites
; atravessam bytes da VRAM por meio de 8 variantes pre-shiftadas (X mod 8).
; A renderizacao dinamica e XOR: desenhar o mesmo sprite duas vezes o apaga.
;
; Controles:
;   A / a = gira anti-horario
;   D / d = gira horario
;   W / w = propulsao (inercia, velocidade acumulada)
;   SPACE = tiro
;   S / s = hyperspace
;   P / p = pausa
;   R / r = reinicia
;   Q / q = retorna para a BIOS
;
; Recursos:
;   - nave em 8 direcoes;
;   - inercia / thrust;
;   - 3 tiros simultaneos;
;   - 8 slots de asteroides;
;   - asteroides grandes -> medios -> pequenos;
;   - duas formas de asteroide;
;   - wrap horizontal e vertical;
;   - score 4 digitos na VGA e nos displays fisicos;
;   - vidas e level no HUD;
;   - invulnerabilidade com blink apos morte;
;   - explosao grafica;
;   - sons de tiro, thrust, impacto, morte, level e game over;
;   - dificuldade progressiva: mais asteroides a cada level.
; ============================================================================

#bankdef cart {
    #addr 0xA000
    #size 0x5000
    #outp 0x0000
}

#bank cart
#addr 0xA000

; ============================================================================
; I/O
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

VIDEO_CLEAR      = $00
MODE_GFX_320     = $12
VRAM_READ        = $20
VIDEO_BUSY_MASK  = $01
VIDEO_FRAME_MASK = $08
KEY_READY_MASK   = $80
TIMER_1MS_MASK   = $01

; ============================================================================
; SPRITE IDS
; ============================================================================

SPR_SHIP_UP = $00
SPR_SHIP_NE = $01
SPR_SHIP_R  = $02
SPR_SHIP_SE = $03
SPR_SHIP_D  = $04
SPR_SHIP_SW = $05
SPR_SHIP_L  = $06
SPR_SHIP_NW = $07
SPR_LARGE_0 = $08
SPR_LARGE_1 = $09
SPR_MED_0   = $0A
SPR_MED_1   = $0B
SPR_SMALL_0 = $0C
SPR_SMALL_1 = $0D
SPR_BULLET  = $0E
SPR_EXPLODE = $0F

; ============================================================================
; RAM - ESTADO GLOBAL
; ============================================================================

SHIP_X          = $0200
SHIP_Y          = $0201
SHIP_DIR        = $0202
SHIP_VX         = $0203
SHIP_VY         = $0204
SHIP_VISIBLE    = $0205
INVULN_TIMER    = $0206
BLINK_PHASE     = $0207
LIVES           = $0208
LEVEL           = $0209
PAUSED_FLAG     = $020A
RESTART_FLAG    = $020B
EXIT_FLAG       = $020C
GAME_OVER_FLAG  = $020D
FRAME_DIV       = $020E
LAST_FRAME      = $020F
MOVE_PHASE      = $0210
RNG_STATE       = $0211
SOUND_TIMER     = $0212

SCORE_THOUSANDS = $0213
SCORE_HUNDREDS  = $0214
SCORE_TENS      = $0215
SCORE_ONES      = $0216

OBJ_INDEX       = $0217
BUL_INDEX       = $0218
HIT_AST_INDEX   = $0219
HIT_SIZE        = $021A
ACTIVE_COUNT    = $021B
TMP0            = $021C
TMP1            = $021D
TMP2            = $021E
ROT_PENDING     = $021F
THRUST_PENDING  = $0233
FIRE_PENDING    = $0234
HYPER_PENDING   = $0235
HEART_COUNT     = $0236
HEART_PHASE     = $0237

; Desenho
DRAW_X          = $0220
DRAW_Y          = $0221
DRAW_SPRITE     = $0222
DRAW_SHIFT      = $0223
DRAW_BYTE_BASE  = $0224
DRAW_BYTE_X     = $0225
DRAW_SCREEN_Y   = $0226
DRAW_ROWS       = $0227
DRAW_COLS       = $0228
DRAW_MASK       = $0229
DRAW_RESULT     = $022A
GLYPH_X         = $022B
GLYPH_Y         = $022C
GLYPH_VALUE     = $022D
GLYPH_BYTE      = $022E
HUD_X           = $022F
HUD_Y           = $0230
HUD_ROWS        = $0231
HUD_COLS        = $0232

; Asteroide temporario
AST_ACTIVE      = $0240
AST_SIZE        = $0241
AST_X           = $0242
AST_Y           = $0243
AST_DIR         = $0244
AST_SHAPE       = $0245

; Bullet temporario
BUL_ACTIVE      = $0250
BUL_X           = $0251
BUL_Y           = $0252
BUL_DIR         = $0253
BUL_LIFE        = $0254

; Fragmento a criar
SPAWN_SIZE      = $0260
SPAWN_X         = $0261
SPAWN_Y         = $0262
SPAWN_DIR       = $0263
SPAWN_SHAPE     = $0264

; Explosao unica
EXP_TIMER       = $0270
EXP_X           = $0271
EXP_Y           = $0272

; Objetos persistentes: 6 bytes por asteroide
AST0 = $0300
AST1 = $0306
AST2 = $030C
AST3 = $0312
AST4 = $0318
AST5 = $031E
AST6 = $0324
AST7 = $032A

; 5 bytes por tiro
BUL0 = $0340
BUL1 = $0345
BUL2 = $034A

; ============================================================================
; ENTRY
; ============================================================================

INICIO:
GAME_START:

    STI SOUND_CFG, #$00
    STI PAUSED_FLAG, #$00
    STI RESTART_FLAG, #$00
    STI EXIT_FLAG, #$00
    STI GAME_OVER_FLAG, #$00
    STI FRAME_DIV, #$00
    STI MOVE_PHASE, #$00
    STI SOUND_TIMER, #$00
    STI ROT_PENDING, #$00
    STI THRUST_PENDING, #$00
    STI FIRE_PENDING, #$00
    STI HYPER_PENDING, #$00
    STI HEART_COUNT, #$12
    STI HEART_PHASE, #$00
    STI EXP_TIMER, #$00
    STI SHIP_VISIBLE, #$00

    STI SCORE_THOUSANDS, #$00
    STI SCORE_HUNDREDS, #$00
    STI SCORE_TENS, #$00
    STI SCORE_ONES, #$00

    STI LIVES, #$03
    STI LEVEL, #$01

    ; Seed simples a partir dos status.
    LDA VIDEO_STATUS
    XOR A, #$A7
    LDB SYSTEM_STATUS
    XOR A, B
    CMP A, #$00
    JNZ GAME_SEED_OK
    LDA #$A7
GAME_SEED_OK:
    STA RNG_STATE

    CALL VIDEO_WAIT
    STI VIDEO_CMD, #MODE_GFX_320
    CALL VIDEO_WAIT
    STI VIDEO_CMD, #VIDEO_CLEAR
    CALL VIDEO_WAIT

    CALL DRAW_HUD
    CALL UPDATE_HUD_ALL
    CALL RESET_SHIP
    CALL CLEAR_BULLETS
    CALL INIT_ASTEROIDS

    ; Sincroniza edge detector do frame.
    LDA VIDEO_STATUS
    AND A, #VIDEO_FRAME_MASK
    STA LAST_FRAME

    CALL SOUND_START
    CALL DRAW_DYNAMIC

; ============================================================================
; LOOP PRINCIPAL - input a 60 Hz, simulacao/render a ~30 Hz
; ============================================================================

MAIN_LOOP:

    CALL WAIT_ONE_FRAME

    LDA EXIT_FLAG
    CMP A, #$01
    JZ EXIT_GAME

    LDA RESTART_FLAG
    CMP A, #$01
    JZ GAME_START

    LDA GAME_OVER_FLAG
    CMP A, #$01
    JZ GAME_OVER

    LDA PAUSED_FLAG
    CMP A, #$01
    JZ MAIN_LOOP

    LDA FRAME_DIV
    XOR A, #$01
    STA FRAME_DIV
    CMP A, #$00
    JNZ MAIN_LOOP

    CALL SOUND_TICK
    CALL ERASE_DYNAMIC
    CALL APPLY_PENDING_INPUT

    LDA MOVE_PHASE
    XOR A, #$01
    STA MOVE_PHASE

    CALL UPDATE_SHIP
    CALL UPDATE_BULLETS
    CALL UPDATE_ASTEROIDS
    CALL UPDATE_EXPLOSION
    CALL CHECK_BULLET_HITS
    CALL CHECK_SHIP_HIT

    LDA GAME_OVER_FLAG
    CMP A, #$01
    JZ GAME_OVER

    CALL CHECK_LEVEL_CLEAR
    CALL DRAW_DYNAMIC

    JMP MAIN_LOOP

; ============================================================================
; INPUT / FRAME
; ============================================================================

WAIT_ONE_FRAME:
WAIT_FRAME_LOOP:
    CALL POLL_KEYBOARD
    LDA VIDEO_STATUS
    AND A, #VIDEO_FRAME_MASK
    LDB LAST_FRAME
    CMP A, B
    JZ WAIT_FRAME_LOOP
    STA LAST_FRAME
    CALL RNG_NEXT
    RET

POLL_KEYBOARD:
    LDA SYSTEM_STATUS
    TEST A, #KEY_READY_MASK
    JZ KEY_DONE

    LDA KEY_DATA

    ; Q/q sempre funciona.
    CMP A, #$51
    JZ KEY_EXIT
    CMP A, #$71
    JZ KEY_EXIT

    ; R/r sempre funciona.
    CMP A, #$52
    JZ KEY_RESTART
    CMP A, #$72
    JZ KEY_RESTART

    ; P/p pausa.
    CMP A, #$50
    JZ KEY_PAUSE
    CMP A, #$70
    JZ KEY_PAUSE

    ; Durante pausa ignora controles de voo.
    LDB PAUSED_FLAG
    CMP B, #$01
    JZ KEY_DONE

    ; A/a gira esquerda.
    CMP A, #$41
    JZ KEY_ROT_LEFT
    CMP A, #$61
    JZ KEY_ROT_LEFT

    ; D/d gira direita.
    CMP A, #$44
    JZ KEY_ROT_RIGHT
    CMP A, #$64
    JZ KEY_ROT_RIGHT

    ; W/w thrust.
    CMP A, #$57
    JZ KEY_THRUST
    CMP A, #$77
    JZ KEY_THRUST

    ; S/s hyperspace.
    CMP A, #$53
    JZ KEY_HYPER
    CMP A, #$73
    JZ KEY_HYPER

    ; SPACE fire.
    CMP A, #$20
    JZ KEY_FIRE

KEY_DONE:
    RET

KEY_EXIT:
    STI EXIT_FLAG, #$01
    RET

KEY_RESTART:
    STI RESTART_FLAG, #$01
    RET

KEY_PAUSE:
    LDA PAUSED_FLAG
    XOR A, #$01
    STA PAUSED_FLAG
    STI SOUND_CFG, #$00
    STI SOUND_TIMER, #$00
    RET

KEY_ROT_LEFT:
    STI ROT_PENDING, #$01
    RET

KEY_ROT_RIGHT:
    STI ROT_PENDING, #$02
    RET

KEY_THRUST:
    STI THRUST_PENDING, #$01
    RET

KEY_FIRE:
    STI FIRE_PENDING, #$01
    RET

KEY_HYPER:
    STI HYPER_PENDING, #$01
    RET

; Aplica comandos somente depois de ERASE_DYNAMIC.
; Isso e essencial porque os sprites sao XOR.
APPLY_PENDING_INPUT:
    LDA ROT_PENDING
    CMP A, #$01
    JZ APPLY_ROT_LEFT
    CMP A, #$02
    JZ APPLY_ROT_RIGHT
    JMP APPLY_ROT_DONE

APPLY_ROT_LEFT:
    LDA SHIP_DIR
    CMP A, #$00
    JNZ APPLY_ROT_LEFT_DEC
    STI SHIP_DIR, #$07
    JMP APPLY_ROT_DONE
APPLY_ROT_LEFT_DEC:
    DEC A
    STA SHIP_DIR
    JMP APPLY_ROT_DONE

APPLY_ROT_RIGHT:
    LDA SHIP_DIR
    CMP A, #$07
    JNZ APPLY_ROT_RIGHT_INC
    STI SHIP_DIR, #$00
    JMP APPLY_ROT_DONE
APPLY_ROT_RIGHT_INC:
    INC A
    STA SHIP_DIR

APPLY_ROT_DONE:
    STI ROT_PENDING, #$00

    LDA THRUST_PENDING
    CMP A, #$01
    JNZ APPLY_NO_THRUST
    CALL APPLY_THRUST
    STI SOUND_CFG, #$61
    STI SOUND_TIMER, #$01
APPLY_NO_THRUST:
    STI THRUST_PENDING, #$00

    LDA HYPER_PENDING
    CMP A, #$01
    JNZ APPLY_NO_HYPER
    CALL HYPERSPACE
APPLY_NO_HYPER:
    STI HYPER_PENDING, #$00

    LDA FIRE_PENDING
    CMP A, #$01
    JNZ APPLY_NO_FIRE
    CALL FIRE_BULLET
APPLY_NO_FIRE:
    STI FIRE_PENDING, #$00
    RET

; ============================================================================
; NAVE / FISICA
; ============================================================================

RESET_SHIP:
    STI SHIP_X, #$78          ; 120
    STI SHIP_Y, #$58          ; 88
    STI SHIP_DIR, #$00
    STI SHIP_VX, #$00
    STI SHIP_VY, #$00
    STI INVULN_TIMER, #$3C    ; 60 ticks de jogo ~= 2 s
    STI BLINK_PHASE, #$00
    STI SHIP_VISIBLE, #$00
    RET

UPDATE_SHIP:
    ; X e modulo 256 naturalmente.
    LDA SHIP_X
    LDB SHIP_VX
    ADD A, B
    STA SHIP_X

    ; Y precisa wrap 0..191.
    LDA SHIP_VY
    CMP A, #$00
    JZ SHIP_VY_DONE
    CMP A, #$01
    JZ SHIP_VY_P1
    CMP A, #$02
    JZ SHIP_VY_P2
    CMP A, #$03
    JZ SHIP_VY_P3
    CMP A, #$FF
    JZ SHIP_VY_N1
    CMP A, #$FE
    JZ SHIP_VY_N2
    ; $FD = -3
    CALL SHIP_Y_DEC
SHIP_VY_N2:
    CALL SHIP_Y_DEC
SHIP_VY_N1:
    CALL SHIP_Y_DEC
    JMP SHIP_VY_DONE
SHIP_VY_P3:
    CALL SHIP_Y_INC
SHIP_VY_P2:
    CALL SHIP_Y_INC
SHIP_VY_P1:
    CALL SHIP_Y_INC
SHIP_VY_DONE:

    LDA INVULN_TIMER
    CMP A, #$00
    JZ SHIP_INV_DONE
    DEC A
    STA INVULN_TIMER
    LDA BLINK_PHASE
    XOR A, #$01
    STA BLINK_PHASE
SHIP_INV_DONE:
    RET

SHIP_Y_INC:
    LDA SHIP_Y
    CMP A, #$BF              ; 191
    JNZ SHIP_Y_INC_NORMAL
    STI SHIP_Y, #$00
    RET
SHIP_Y_INC_NORMAL:
    INC A
    STA SHIP_Y
    RET

SHIP_Y_DEC:
    LDA SHIP_Y
    CMP A, #$00
    JNZ SHIP_Y_DEC_NORMAL
    STI SHIP_Y, #$BF
    RET
SHIP_Y_DEC_NORMAL:
    DEC A
    STA SHIP_Y
    RET

; Velocidade limitada a -3..+3.
VX_POS:
    LDA SHIP_VX
    CMP A, #$03
    JZ VX_POS_DONE
    INC A
    STA SHIP_VX
VX_POS_DONE:
    RET

VX_NEG:
    LDA SHIP_VX
    CMP A, #$FD
    JZ VX_NEG_DONE
    DEC A
    STA SHIP_VX
VX_NEG_DONE:
    RET

VY_POS:
    LDA SHIP_VY
    CMP A, #$03
    JZ VY_POS_DONE
    INC A
    STA SHIP_VY
VY_POS_DONE:
    RET

VY_NEG:
    LDA SHIP_VY
    CMP A, #$FD
    JZ VY_NEG_DONE
    DEC A
    STA SHIP_VY
VY_NEG_DONE:
    RET

APPLY_THRUST:
    LDA SHIP_DIR
    CMP A, #$00
    JZ THRUST_UP
    CMP A, #$01
    JZ THRUST_NE
    CMP A, #$02
    JZ THRUST_RIGHT
    CMP A, #$03
    JZ THRUST_SE
    CMP A, #$04
    JZ THRUST_DOWN
    CMP A, #$05
    JZ THRUST_SW
    CMP A, #$06
    JZ THRUST_LEFT
    ; NW
    CALL VX_NEG
    CALL VY_NEG
    RET
THRUST_UP:
    CALL VY_NEG
    RET
THRUST_NE:
    CALL VX_POS
    CALL VY_NEG
    RET
THRUST_RIGHT:
    CALL VX_POS
    RET
THRUST_SE:
    CALL VX_POS
    CALL VY_POS
    RET
THRUST_DOWN:
    CALL VY_POS
    RET
THRUST_SW:
    CALL VX_NEG
    CALL VY_POS
    RET
THRUST_LEFT:
    CALL VX_NEG
    RET

HYPERSPACE:
    CALL RNG_NEXT
    STA SHIP_X
    CALL RNG_NEXT
HYPER_Y_REDUCE:
    CMP A, #$C0
    JNC HYPER_Y_READY
    SUB A, #$C0
    JMP HYPER_Y_REDUCE
HYPER_Y_READY:
    STA SHIP_Y
    STI SHIP_VX, #$00
    STI SHIP_VY, #$00
    STI INVULN_TIMER, #$1E
    STI SOUND_CFG, #$E1       ; noise agudo
    STI SOUND_TIMER, #$03
    RET

; ============================================================================
; BULLETS
; ============================================================================

CLEAR_BULLETS:
    PTR BUL0
    STI TMP0, #$0F            ; 3 * 5 bytes
CLEAR_BULLETS_LOOP:
    LDA #$00
    STA [PTR+]
    LDA TMP0
    DEC A
    STA TMP0
    JNZ CLEAR_BULLETS_LOOP
    RET

FIRE_BULLET:
    STI BUL_INDEX, #$00
FIRE_FIND_LOOP:
    CALL LOAD_BULLET_SLOT
    LDA BUL_ACTIVE
    CMP A, #$00
    JZ FIRE_FOUND
    LDA BUL_INDEX
    INC A
    STA BUL_INDEX
    CMP A, #$03
    JNZ FIRE_FIND_LOOP
    RET

FIRE_FOUND:
    STI BUL_ACTIVE, #$01
    LDA SHIP_X
    ADD A, #$07
    STA BUL_X
    LDA SHIP_Y
    ADD A, #$07
    CMP A, #$C0
    JNC FIRE_Y_OK
    SUB A, #$C0
FIRE_Y_OK:
    STA BUL_Y
    LDA SHIP_DIR
    STA BUL_DIR
    STI BUL_LIFE, #$32        ; 50 ticks
    CALL STORE_BULLET_SLOT
    STI SOUND_CFG, #$02       ; C5 curto
    STI SOUND_TIMER, #$01
    RET

UPDATE_BULLETS:
    STI BUL_INDEX, #$00
UPDATE_BUL_LOOP:
    CALL LOAD_BULLET_SLOT
    LDA BUL_ACTIVE
    CMP A, #$01
    JNZ UPDATE_BUL_NEXT

    LDA BUL_LIFE
    DEC A
    STA BUL_LIFE
    CMP A, #$00
    JZ UPDATE_BUL_KILL

    CALL MOVE_BULLET_ONCE
    CALL MOVE_BULLET_ONCE
    CALL MOVE_BULLET_ONCE
    CALL STORE_BULLET_SLOT
    JMP UPDATE_BUL_NEXT

UPDATE_BUL_KILL:
    STI BUL_ACTIVE, #$00
    CALL STORE_BULLET_SLOT

UPDATE_BUL_NEXT:
    LDA BUL_INDEX
    INC A
    STA BUL_INDEX
    CMP A, #$03
    JNZ UPDATE_BUL_LOOP
    RET

MOVE_BULLET_ONCE:
    LDA BUL_DIR
    CMP A, #$00
    JZ BUL_MOVE_UP
    CMP A, #$01
    JZ BUL_MOVE_NE
    CMP A, #$02
    JZ BUL_MOVE_R
    CMP A, #$03
    JZ BUL_MOVE_SE
    CMP A, #$04
    JZ BUL_MOVE_D
    CMP A, #$05
    JZ BUL_MOVE_SW
    CMP A, #$06
    JZ BUL_MOVE_L
    ; NW
    CALL BUL_X_DEC
    CALL BUL_Y_DEC
    RET
BUL_MOVE_UP:
    CALL BUL_Y_DEC
    RET
BUL_MOVE_NE:
    CALL BUL_X_INC
    CALL BUL_Y_DEC
    RET
BUL_MOVE_R:
    CALL BUL_X_INC
    RET
BUL_MOVE_SE:
    CALL BUL_X_INC
    CALL BUL_Y_INC
    RET
BUL_MOVE_D:
    CALL BUL_Y_INC
    RET
BUL_MOVE_SW:
    CALL BUL_X_DEC
    CALL BUL_Y_INC
    RET
BUL_MOVE_L:
    CALL BUL_X_DEC
    RET

BUL_X_INC:
    LDA BUL_X
    INC A
    STA BUL_X
    RET
BUL_X_DEC:
    LDA BUL_X
    DEC A
    STA BUL_X
    RET
BUL_Y_INC:
    LDA BUL_Y
    CMP A, #$BF
    JNZ BUL_Y_INC_N
    STI BUL_Y, #$00
    RET
BUL_Y_INC_N:
    INC A
    STA BUL_Y
    RET
BUL_Y_DEC:
    LDA BUL_Y
    CMP A, #$00
    JNZ BUL_Y_DEC_N
    STI BUL_Y, #$BF
    RET
BUL_Y_DEC_N:
    DEC A
    STA BUL_Y
    RET

; ============================================================================
; ASTEROIDES
; Estrutura: ACTIVE,SIZE,X,Y,DIR,SHAPE
; SIZE 2=large, 1=medium, 0=small
; ============================================================================

INIT_ASTEROIDS:
    ; Limpa os 8 slots.
    PTR AST0
    STI TMP0, #$30            ; 8*6 = 48 bytes
INIT_AST_CLEAR:
    LDA #$00
    STA [PTR+]
    LDA TMP0
    DEC A
    STA TMP0
    JNZ INIT_AST_CLEAR

    ; Quatro grandes iniciais, longe do centro.
    STI OBJ_INDEX, #$00
    STI AST_ACTIVE, #$01
    STI AST_SIZE, #$02
    STI AST_X, #$10
    STI AST_Y, #$18
    STI AST_DIR, #$03
    STI AST_SHAPE, #$00
    CALL STORE_AST_SLOT

    STI OBJ_INDEX, #$01
    STI AST_X, #$D0
    STI AST_Y, #$18
    STI AST_DIR, #$05
    STI AST_SHAPE, #$01
    CALL STORE_AST_SLOT

    STI OBJ_INDEX, #$02
    STI AST_X, #$20
    STI AST_Y, #$98
    STI AST_DIR, #$01
    STI AST_SHAPE, #$01
    CALL STORE_AST_SLOT

    STI OBJ_INDEX, #$03
    STI AST_X, #$D8
    STI AST_Y, #$98
    STI AST_DIR, #$07
    STI AST_SHAPE, #$00
    CALL STORE_AST_SLOT

    ; Levels maiores adicionam slots.
    LDA LEVEL
    CMP A, #$02
    JNC INIT_AST_DONE
    STI OBJ_INDEX, #$04
    STI AST_X, #$70
    STI AST_Y, #$10
    STI AST_DIR, #$04
    STI AST_SHAPE, #$01
    CALL STORE_AST_SLOT

    LDA LEVEL
    CMP A, #$03
    JNC INIT_AST_DONE
    STI OBJ_INDEX, #$05
    STI AST_X, #$70
    STI AST_Y, #$A8
    STI AST_DIR, #$00
    STI AST_SHAPE, #$00
    CALL STORE_AST_SLOT

    LDA LEVEL
    CMP A, #$04
    JNC INIT_AST_DONE
    STI OBJ_INDEX, #$06
    STI AST_X, #$08
    STI AST_Y, #$58
    STI AST_DIR, #$02
    STI AST_SHAPE, #$01
    CALL STORE_AST_SLOT

    LDA LEVEL
    CMP A, #$05
    JNC INIT_AST_DONE
    STI OBJ_INDEX, #$07
    STI AST_X, #$E8
    STI AST_Y, #$58
    STI AST_DIR, #$06
    STI AST_SHAPE, #$00
    CALL STORE_AST_SLOT

INIT_AST_DONE:
    RET

UPDATE_ASTEROIDS:
    STI OBJ_INDEX, #$00
UPDATE_AST_LOOP:
    CALL LOAD_AST_SLOT
    LDA AST_ACTIVE
    CMP A, #$01
    JNZ UPDATE_AST_NEXT

    ; Large anda a 15 Hz; medium a 30 Hz; small a 60 px/s (2 passos).
    LDA AST_SIZE
    CMP A, #$02
    JNZ UPDATE_AST_NOT_LARGE
    LDA MOVE_PHASE
    CMP A, #$00
    JZ UPDATE_AST_STORE
    CALL MOVE_AST_ONCE
    JMP UPDATE_AST_STORE

UPDATE_AST_NOT_LARGE:
    CALL MOVE_AST_ONCE
    LDA AST_SIZE
    CMP A, #$00
    JNZ UPDATE_AST_STORE
    CALL MOVE_AST_ONCE

UPDATE_AST_STORE:
    CALL STORE_AST_SLOT

UPDATE_AST_NEXT:
    LDA OBJ_INDEX
    INC A
    STA OBJ_INDEX
    CMP A, #$08
    JNZ UPDATE_AST_LOOP
    RET

MOVE_AST_ONCE:
    LDA AST_DIR
    CMP A, #$00
    JZ AST_MOVE_UP
    CMP A, #$01
    JZ AST_MOVE_NE
    CMP A, #$02
    JZ AST_MOVE_R
    CMP A, #$03
    JZ AST_MOVE_SE
    CMP A, #$04
    JZ AST_MOVE_D
    CMP A, #$05
    JZ AST_MOVE_SW
    CMP A, #$06
    JZ AST_MOVE_L
    ; NW
    CALL AST_X_DEC
    CALL AST_Y_DEC
    RET
AST_MOVE_UP:
    CALL AST_Y_DEC
    RET
AST_MOVE_NE:
    CALL AST_X_INC
    CALL AST_Y_DEC
    RET
AST_MOVE_R:
    CALL AST_X_INC
    RET
AST_MOVE_SE:
    CALL AST_X_INC
    CALL AST_Y_INC
    RET
AST_MOVE_D:
    CALL AST_Y_INC
    RET
AST_MOVE_SW:
    CALL AST_X_DEC
    CALL AST_Y_INC
    RET
AST_MOVE_L:
    CALL AST_X_DEC
    RET

AST_X_INC:
    LDA AST_X
    INC A
    STA AST_X
    RET
AST_X_DEC:
    LDA AST_X
    DEC A
    STA AST_X
    RET
AST_Y_INC:
    LDA AST_Y
    CMP A, #$BF
    JNZ AST_Y_INC_N
    STI AST_Y, #$00
    RET
AST_Y_INC_N:
    INC A
    STA AST_Y
    RET
AST_Y_DEC:
    LDA AST_Y
    CMP A, #$00
    JNZ AST_Y_DEC_N
    STI AST_Y, #$BF
    RET
AST_Y_DEC_N:
    DEC A
    STA AST_Y
    RET

; ============================================================================
; COLISOES BULLET x ASTEROIDE
; ============================================================================

CHECK_BULLET_HITS:
    STI BUL_INDEX, #$00
CBH_BUL_LOOP:
    CALL LOAD_BULLET_SLOT
    LDA BUL_ACTIVE
    CMP A, #$01
    JNZ CBH_NEXT_BUL

    STI OBJ_INDEX, #$00
CBH_AST_LOOP:
    CALL LOAD_AST_SLOT
    LDA AST_ACTIVE
    CMP A, #$01
    JNZ CBH_NEXT_AST

    CALL BULLET_AST_COLLISION
    CMP A, #$01
    JNZ CBH_NEXT_AST

    ; Um tiro so acerta um asteroide.
    LDA OBJ_INDEX
    STA HIT_AST_INDEX
    CALL HANDLE_AST_HIT
    JMP CBH_NEXT_BUL

CBH_NEXT_AST:
    LDA OBJ_INDEX
    INC A
    STA OBJ_INDEX
    CMP A, #$08
    JNZ CBH_AST_LOOP

CBH_NEXT_BUL:
    LDA BUL_INDEX
    INC A
    STA BUL_INDEX
    CMP A, #$03
    JNZ CBH_BUL_LOOP
    RET

; Retorna A=1 em hit, A=0 caso contrario.
BULLET_AST_COLLISION:
    ; centro X do asteroide = AST_X+8
    LDA AST_X
    ADD A, #$08
    LDB BUL_X
    CALL ABS_DIFF
    STA TMP0

    ; limite por tamanho: large 10, med 8, small 6.
    LDA AST_SIZE
    CMP A, #$02
    JZ BAC_X_LARGE
    CMP A, #$01
    JZ BAC_X_MED
    LDA TMP0
    CMP A, #$07
    JC BAC_NO
    JMP BAC_Y
BAC_X_MED:
    LDA TMP0
    CMP A, #$09
    JC BAC_NO
    JMP BAC_Y
BAC_X_LARGE:
    LDA TMP0
    CMP A, #$0B
    JC BAC_NO

BAC_Y:
    LDA AST_Y
    ADD A, #$08
    LDB BUL_Y
    CALL ABS_DIFF
    STA TMP0

    LDA AST_SIZE
    CMP A, #$02
    JZ BAC_Y_LARGE
    CMP A, #$01
    JZ BAC_Y_MED
    LDA TMP0
    CMP A, #$07
    JC BAC_NO
    LDA #$01
    RET
BAC_Y_MED:
    LDA TMP0
    CMP A, #$09
    JC BAC_NO
    LDA #$01
    RET
BAC_Y_LARGE:
    LDA TMP0
    CMP A, #$0B
    JC BAC_NO
    LDA #$01
    RET
BAC_NO:
    CLR A
    RET

HANDLE_AST_HIT:
    ; Mata o bullet atual.
    STI BUL_ACTIVE, #$00
    CALL STORE_BULLET_SLOT

    LDA AST_SIZE
    STA HIT_SIZE

    ; Explosao no local.
    LDA AST_X
    STA EXP_X
    LDA AST_Y
    STA EXP_Y
    STI EXP_TIMER, #$06

    ; Score e som antes de alterar size.
    CALL ADD_HIT_SCORE
    STI SOUND_CFG, #$8F       ; tone + noise
    STI SOUND_TIMER, #$03

    LDA HIT_SIZE
    CMP A, #$00
    JZ HIT_DESTROY_SMALL

    ; Current vira um fragmento menor.
    LDA AST_SIZE
    DEC A
    STA AST_SIZE
    STA SPAWN_SIZE

    LDA AST_X
    STA SPAWN_X
    LDA AST_Y
    STA SPAWN_Y

    LDA AST_DIR
    INC A
    AND A, #$07
    STA AST_DIR

    ADD A, #$02
    AND A, #$07
    STA SPAWN_DIR

    LDA AST_SHAPE
    XOR A, #$01
    STA AST_SHAPE
    STA SPAWN_SHAPE

    ; Regrava o fragmento que ocupou o slot original.
    LDA HIT_AST_INDEX
    STA OBJ_INDEX
    CALL STORE_AST_SLOT

    ; Procura outro slot livre para o segundo fragmento.
    CALL SPAWN_FRAGMENT
    RET

HIT_DESTROY_SMALL:
    STI AST_ACTIVE, #$00
    LDA HIT_AST_INDEX
    STA OBJ_INDEX
    CALL STORE_AST_SLOT
    RET

SPAWN_FRAGMENT:
    STI OBJ_INDEX, #$00
SPAWN_FIND_LOOP:
    CALL LOAD_AST_SLOT
    LDA AST_ACTIVE
    CMP A, #$00
    JZ SPAWN_FOUND
    LDA OBJ_INDEX
    INC A
    STA OBJ_INDEX
    CMP A, #$08
    JNZ SPAWN_FIND_LOOP
    RET

SPAWN_FOUND:
    STI AST_ACTIVE, #$01
    LDA SPAWN_SIZE
    STA AST_SIZE
    LDA SPAWN_X
    STA AST_X
    LDA SPAWN_Y
    STA AST_Y
    LDA SPAWN_DIR
    STA AST_DIR
    LDA SPAWN_SHAPE
    STA AST_SHAPE
    CALL STORE_AST_SLOT
    RET

; ============================================================================
; COLISAO DA NAVE
; ============================================================================

CHECK_SHIP_HIT:
    LDA INVULN_TIMER
    CMP A, #$00
    JNZ CSH_DONE

    STI OBJ_INDEX, #$00
CSH_LOOP:
    CALL LOAD_AST_SLOT
    LDA AST_ACTIVE
    CMP A, #$01
    JNZ CSH_NEXT

    CALL SHIP_AST_COLLISION
    CMP A, #$01
    JZ SHIP_HIT

CSH_NEXT:
    LDA OBJ_INDEX
    INC A
    STA OBJ_INDEX
    CMP A, #$08
    JNZ CSH_LOOP
CSH_DONE:
    RET

SHIP_AST_COLLISION:
    ; centros aproximados +8.
    LDA SHIP_X
    ADD A, #$08
    LDB AST_X
    ADD B, #$08
    CALL ABS_DIFF
    STA TMP0

    LDA AST_SIZE
    CMP A, #$02
    JZ SAC_X_L
    CMP A, #$01
    JZ SAC_X_M
    LDA TMP0
    CMP A, #$0A             ; small: diff <10
    JC SAC_NO
    JMP SAC_Y
SAC_X_M:
    LDA TMP0
    CMP A, #$0C             ; med: diff <12
    JC SAC_NO
    JMP SAC_Y
SAC_X_L:
    LDA TMP0
    CMP A, #$0E             ; large: diff <14
    JC SAC_NO

SAC_Y:
    LDA SHIP_Y
    ADD A, #$08
    LDB AST_Y
    ADD B, #$08
    CALL ABS_DIFF
    STA TMP0

    LDA AST_SIZE
    CMP A, #$02
    JZ SAC_Y_L
    CMP A, #$01
    JZ SAC_Y_M
    LDA TMP0
    CMP A, #$0A
    JC SAC_NO
    LDA #$01
    RET
SAC_Y_M:
    LDA TMP0
    CMP A, #$0C
    JC SAC_NO
    LDA #$01
    RET
SAC_Y_L:
    LDA TMP0
    CMP A, #$0E
    JC SAC_NO
    LDA #$01
    RET
SAC_NO:
    CLR A
    RET

SHIP_HIT:
    STI SOUND_CFG, #$00
    CALL SOUND_DEATH

    LDA LIVES
    DEC A
    STA LIVES
    CALL UPDATE_HUD_LIVES

    CMP A, #$00
    JNZ SHIP_RESPAWN
    STI GAME_OVER_FLAG, #$01
    RET

SHIP_RESPAWN:
    CALL CLEAR_BULLETS
    CALL RESET_SHIP
    RET

; A=|A-B|, B pode ser destruido.
ABS_DIFF:
    CMP A, B
    JC ABS_A_GE_B
    SUB B, A
    MOV A, B
    RET
ABS_A_GE_B:
    SUB A, B
    RET

; ============================================================================
; LEVEL / SCORE
; ============================================================================

CHECK_LEVEL_CLEAR:
    STI OBJ_INDEX, #$00
    STI ACTIVE_COUNT, #$00
CLC_LOOP:
    CALL LOAD_AST_SLOT
    LDA AST_ACTIVE
    CMP A, #$01
    JNZ CLC_NEXT
    LDA ACTIVE_COUNT
    INC A
    STA ACTIVE_COUNT
CLC_NEXT:
    LDA OBJ_INDEX
    INC A
    STA OBJ_INDEX
    CMP A, #$08
    JNZ CLC_LOOP

    LDA ACTIVE_COUNT
    CMP A, #$00
    JNZ CLC_DONE

    CALL SOUND_LEVEL
    LDA LEVEL
    CMP A, #$09
    JZ CLC_LEVEL_READY
    INC A
    STA LEVEL
CLC_LEVEL_READY:
    CALL UPDATE_HUD_LEVEL
    CALL INIT_ASTEROIDS
CLC_DONE:
    RET

ADD_HIT_SCORE:
    LDA HIT_SIZE
    CMP A, #$02
    JZ SCORE_ADD_20
    CMP A, #$01
    JZ SCORE_ADD_50
    JMP SCORE_ADD_100

SCORE_ADD_20:
    LDA SCORE_TENS
    ADD A, #$02
    STA SCORE_TENS
    JMP SCORE_NORMALIZE_TENS

SCORE_ADD_50:
    LDA SCORE_TENS
    ADD A, #$05
    STA SCORE_TENS
    JMP SCORE_NORMALIZE_TENS

SCORE_ADD_100:
    LDA SCORE_HUNDREDS
    INC A
    STA SCORE_HUNDREDS
    JMP SCORE_NORMALIZE_HUNDREDS

SCORE_NORMALIZE_TENS:
    LDA SCORE_TENS
    CMP A, #$0A
    JNC SCORE_AFTER_TENS
    SUB A, #$0A
    STA SCORE_TENS
    LDA SCORE_HUNDREDS
    INC A
    STA SCORE_HUNDREDS

SCORE_NORMALIZE_HUNDREDS:
    LDA SCORE_HUNDREDS
    CMP A, #$0A
    JNC SCORE_AFTER_TENS
    SUB A, #$0A
    STA SCORE_HUNDREDS
    LDA SCORE_THOUSANDS
    INC A
    CMP A, #$0A
    JNC SCORE_STORE_TH
    CLR A
SCORE_STORE_TH:
    STA SCORE_THOUSANDS

SCORE_AFTER_TENS:
    CALL UPDATE_HUD_SCORE
    RET

; ============================================================================
; OBJETO LOAD/STORE DISPATCH
; ============================================================================

LOAD_AST_SLOT:
    LDA OBJ_INDEX
    CMP A, #$00
    JZ LAS_0
    CMP A, #$01
    JZ LAS_1
    CMP A, #$02
    JZ LAS_2
    CMP A, #$03
    JZ LAS_3
    CMP A, #$04
    JZ LAS_4
    CMP A, #$05
    JZ LAS_5
    CMP A, #$06
    JZ LAS_6
    PTR AST7
    JMP LAS_READ
LAS_0:
    PTR AST0
    JMP LAS_READ
LAS_1:
    PTR AST1
    JMP LAS_READ
LAS_2:
    PTR AST2
    JMP LAS_READ
LAS_3:
    PTR AST3
    JMP LAS_READ
LAS_4:
    PTR AST4
    JMP LAS_READ
LAS_5:
    PTR AST5
    JMP LAS_READ
LAS_6:
    PTR AST6
LAS_READ:
    LDA [PTR+]
    STA AST_ACTIVE
    LDA [PTR+]
    STA AST_SIZE
    LDA [PTR+]
    STA AST_X
    LDA [PTR+]
    STA AST_Y
    LDA [PTR+]
    STA AST_DIR
    LDA [PTR]
    STA AST_SHAPE
    RET

STORE_AST_SLOT:
    LDA OBJ_INDEX
    CMP A, #$00
    JZ SAS_0
    CMP A, #$01
    JZ SAS_1
    CMP A, #$02
    JZ SAS_2
    CMP A, #$03
    JZ SAS_3
    CMP A, #$04
    JZ SAS_4
    CMP A, #$05
    JZ SAS_5
    CMP A, #$06
    JZ SAS_6
    PTR AST7
    JMP SAS_WRITE
SAS_0:
    PTR AST0
    JMP SAS_WRITE
SAS_1:
    PTR AST1
    JMP SAS_WRITE
SAS_2:
    PTR AST2
    JMP SAS_WRITE
SAS_3:
    PTR AST3
    JMP SAS_WRITE
SAS_4:
    PTR AST4
    JMP SAS_WRITE
SAS_5:
    PTR AST5
    JMP SAS_WRITE
SAS_6:
    PTR AST6
SAS_WRITE:
    LDA AST_ACTIVE
    STA [PTR+]
    LDA AST_SIZE
    STA [PTR+]
    LDA AST_X
    STA [PTR+]
    LDA AST_Y
    STA [PTR+]
    LDA AST_DIR
    STA [PTR+]
    LDA AST_SHAPE
    STA [PTR]
    RET

LOAD_BULLET_SLOT:
    LDA BUL_INDEX
    CMP A, #$00
    JZ LBS_0
    CMP A, #$01
    JZ LBS_1
    PTR BUL2
    JMP LBS_READ
LBS_0:
    PTR BUL0
    JMP LBS_READ
LBS_1:
    PTR BUL1
LBS_READ:
    LDA [PTR+]
    STA BUL_ACTIVE
    LDA [PTR+]
    STA BUL_X
    LDA [PTR+]
    STA BUL_Y
    LDA [PTR+]
    STA BUL_DIR
    LDA [PTR]
    STA BUL_LIFE
    RET

STORE_BULLET_SLOT:
    LDA BUL_INDEX
    CMP A, #$00
    JZ SBS_0
    CMP A, #$01
    JZ SBS_1
    PTR BUL2
    JMP SBS_WRITE
SBS_0:
    PTR BUL0
    JMP SBS_WRITE
SBS_1:
    PTR BUL1
SBS_WRITE:
    LDA BUL_ACTIVE
    STA [PTR+]
    LDA BUL_X
    STA [PTR+]
    LDA BUL_Y
    STA [PTR+]
    LDA BUL_DIR
    STA [PTR+]
    LDA BUL_LIFE
    STA [PTR]
    RET

; ============================================================================
; RENDER DINAMICO XOR
; ============================================================================

ERASE_DYNAMIC:
    ; Apaga apenas o que realmente foi desenhado no frame anterior.
    LDA SHIP_VISIBLE
    CMP A, #$01
    JNZ ERASE_NO_SHIP
    LDA SHIP_X
    STA DRAW_X
    LDA SHIP_Y
    STA DRAW_Y
    LDA SHIP_DIR
    STA DRAW_SPRITE
    CALL DRAW_SPRITE_XOR
ERASE_NO_SHIP:
    CALL DRAW_BULLETS_XOR
    CALL DRAW_ASTEROIDS_XOR
    LDA EXP_TIMER
    CMP A, #$00
    JZ ERASE_NO_EXP
    LDA EXP_X
    STA DRAW_X
    LDA EXP_Y
    STA DRAW_Y
    STI DRAW_SPRITE, #SPR_EXPLODE
    CALL DRAW_SPRITE_XOR
ERASE_NO_EXP:
    STI SHIP_VISIBLE, #$00
    RET

DRAW_DYNAMIC:
    ; Blink durante invulnerabilidade.
    LDA INVULN_TIMER
    CMP A, #$00
    JZ DRAW_SHIP_YES
    LDA BLINK_PHASE
    CMP A, #$00
    JNZ DRAW_SHIP_NO
DRAW_SHIP_YES:
    LDA SHIP_X
    STA DRAW_X
    LDA SHIP_Y
    STA DRAW_Y
    LDA SHIP_DIR
    STA DRAW_SPRITE
    CALL DRAW_SPRITE_XOR
    STI SHIP_VISIBLE, #$01
DRAW_SHIP_NO:
    CALL DRAW_BULLETS_XOR
    CALL DRAW_ASTEROIDS_XOR
    LDA EXP_TIMER
    CMP A, #$00
    JZ DRAW_DYN_DONE
    LDA EXP_X
    STA DRAW_X
    LDA EXP_Y
    STA DRAW_Y
    STI DRAW_SPRITE, #SPR_EXPLODE
    CALL DRAW_SPRITE_XOR
DRAW_DYN_DONE:
    RET

DRAW_BULLETS_XOR:
    STI BUL_INDEX, #$00
DBX_LOOP:
    CALL LOAD_BULLET_SLOT
    LDA BUL_ACTIVE
    CMP A, #$01
    JNZ DBX_NEXT
    LDA BUL_X
    STA DRAW_X
    LDA BUL_Y
    STA DRAW_Y
    STI DRAW_SPRITE, #SPR_BULLET
    CALL DRAW_SPRITE_XOR
DBX_NEXT:
    LDA BUL_INDEX
    INC A
    STA BUL_INDEX
    CMP A, #$03
    JNZ DBX_LOOP
    RET

DRAW_ASTEROIDS_XOR:
    STI OBJ_INDEX, #$00
DAX_LOOP:
    CALL LOAD_AST_SLOT
    LDA AST_ACTIVE
    CMP A, #$01
    JNZ DAX_NEXT

    LDA AST_X
    STA DRAW_X
    LDA AST_Y
    STA DRAW_Y

    LDA AST_SIZE
    CMP A, #$02
    JZ DAX_LARGE
    CMP A, #$01
    JZ DAX_MED

    LDA AST_SHAPE
    CMP A, #$00
    JZ DAX_SMALL0
    STI DRAW_SPRITE, #SPR_SMALL_1
    JMP DAX_DRAW
DAX_SMALL0:
    STI DRAW_SPRITE, #SPR_SMALL_0
    JMP DAX_DRAW

DAX_MED:
    LDA AST_SHAPE
    CMP A, #$00
    JZ DAX_MED0
    STI DRAW_SPRITE, #SPR_MED_1
    JMP DAX_DRAW
DAX_MED0:
    STI DRAW_SPRITE, #SPR_MED_0
    JMP DAX_DRAW

DAX_LARGE:
    LDA AST_SHAPE
    CMP A, #$00
    JZ DAX_LARGE0
    STI DRAW_SPRITE, #SPR_LARGE_1
    JMP DAX_DRAW
DAX_LARGE0:
    STI DRAW_SPRITE, #SPR_LARGE_0

DAX_DRAW:
    CALL DRAW_SPRITE_XOR

DAX_NEXT:
    LDA OBJ_INDEX
    INC A
    STA OBJ_INDEX
    CMP A, #$08
    JNZ DAX_LOOP
    RET

UPDATE_EXPLOSION:
    LDA EXP_TIMER
    CMP A, #$00
    JZ UPDATE_EXP_DONE
    DEC A
    STA EXP_TIMER
UPDATE_EXP_DONE:
    RET

; ---------------------------------------------------------------------------
; DRAW_SPRITE_XOR
; Todos os sprites usam canvas 16x16. Cada variante shifted possui 3 bytes
; por linha x 16 linhas = 48 bytes. O terceiro byte e necessario quando
; X mod 8 != 0.
; ---------------------------------------------------------------------------

DRAW_SPRITE_XOR:
    ; shift = X & 7
    LDA DRAW_X
    AND A, #$07
    STA DRAW_SHIFT

    ; byte base do campo = 4 + (X >> 3)
    LDA DRAW_X
    SHR A
    SHR A
    SHR A
    ADD A, #$04
    STA DRAW_BYTE_BASE

    ; y fisico = 32 + y mundo
    LDA DRAW_Y
    ADD A, #$20
    STA DRAW_SCREEN_Y

    CALL SELECT_SPRITE_PTR

    STI DRAW_ROWS, #$10
DSP_ROW_LOOP:
    LDA DRAW_BYTE_BASE
    STA DRAW_BYTE_X
    STI DRAW_COLS, #$03
DSP_COL_LOOP:
    LDA [PTR+]
    STA DRAW_MASK
    CMP A, #$00
    JZ DSP_SKIP_BYTE
    CALL XOR_VRAM_BYTE
DSP_SKIP_BYTE:
    CALL DRAW_XBYTE_INC
    LDA DRAW_COLS
    DEC A
    STA DRAW_COLS
    JNZ DSP_COL_LOOP

    ; Y fisico 32..223, com wrap.
    LDA DRAW_SCREEN_Y
    CMP A, #$DF             ; 223
    JNZ DSP_Y_INC
    LDA #$20
    STA DRAW_SCREEN_Y
    JMP DSP_Y_READY
DSP_Y_INC:
    INC A
    STA DRAW_SCREEN_Y
DSP_Y_READY:
    LDA DRAW_ROWS
    DEC A
    STA DRAW_ROWS
    JNZ DSP_ROW_LOOP
    RET

DRAW_XBYTE_INC:
    LDA DRAW_BYTE_X
    CMP A, #$23             ; byte 35 = ultimo do campo 256px
    JNZ DXBI_NORMAL
    STI DRAW_BYTE_X, #$04
    RET
DXBI_NORMAL:
    INC A
    STA DRAW_BYTE_X
    RET

XOR_VRAM_BYTE:
    CALL VIDEO_WAIT
    LDA DRAW_BYTE_X
    STA VIDEO_X
    LDA DRAW_SCREEN_Y
    STA VIDEO_Y
    STI VIDEO_CMD, #VRAM_READ
    CALL VIDEO_WAIT
    LDA VIDEO_DATA
    LDB DRAW_MASK
    XOR A, B
    STA DRAW_RESULT

    CALL VIDEO_WAIT
    LDA DRAW_BYTE_X
    STA VIDEO_X
    LDA DRAW_SCREEN_Y
    STA VIDEO_Y
    LDA DRAW_RESULT
    STA VIDEO_DATA
    RET

; ============================================================================
; HUD / BITMAPS
; ============================================================================

DRAW_HUD:
    ; Linha 1 em y=2..9.
    PTR HUD_LINE1
    STI HUD_Y, #$02
    CALL DRAW_HUD_40X8

    ; Linha 2 em y=14..21.
    PTR HUD_LINE2
    STI HUD_Y, #$0E
    CALL DRAW_HUD_40X8

    ; Separador horizontal em y=24.
    STI HUD_X, #$00
HUD_SEP_LOOP:
    CALL VIDEO_WAIT
    LDA HUD_X
    STA VIDEO_X
    STI VIDEO_Y, #$18
    STI VIDEO_DATA, #$FF
    LDA HUD_X
    INC A
    STA HUD_X
    CMP A, #$28
    JNZ HUD_SEP_LOOP
    RET

; PTR -> 8*40 bytes, HUD_Y = primeira linha.
DRAW_HUD_40X8:
    STI HUD_ROWS, #$08
DHUD_ROW:
    STI HUD_X, #$00
    STI HUD_COLS, #$28
DHUD_COL:
    LDA [PTR+]
    STA GLYPH_BYTE
    CALL VIDEO_WAIT
    LDA HUD_X
    STA VIDEO_X
    LDA HUD_Y
    STA VIDEO_Y
    LDA GLYPH_BYTE
    STA VIDEO_DATA
    LDA HUD_X
    INC A
    STA HUD_X
    LDA HUD_COLS
    DEC A
    STA HUD_COLS
    JNZ DHUD_COL
    LDA HUD_Y
    INC A
    STA HUD_Y
    LDA HUD_ROWS
    DEC A
    STA HUD_ROWS
    JNZ DHUD_ROW
    RET

UPDATE_HUD_ALL:
    CALL UPDATE_HUD_SCORE
    CALL UPDATE_HUD_LIVES
    CALL UPDATE_HUD_LEVEL
    RET

UPDATE_HUD_SCORE:
    ; SCORE digits ficam nos bytes 7,8,9,10 em y=2.
    STI GLYPH_Y, #$02
    STI GLYPH_X, #$07
    LDA SCORE_THOUSANDS
    STA GLYPH_VALUE
    CALL DRAW_DIGIT
    STI GLYPH_X, #$08
    LDA SCORE_HUNDREDS
    STA GLYPH_VALUE
    CALL DRAW_DIGIT
    STI GLYPH_X, #$09
    LDA SCORE_TENS
    STA GLYPH_VALUE
    CALL DRAW_DIGIT
    STI GLYPH_X, #$0A
    LDA SCORE_ONES
    STA GLYPH_VALUE
    CALL DRAW_DIGIT

    ; Display fisico em BCD: TH em HIGH, TO em LOW.
    LDA SCORE_THOUSANDS
    SHL A
    SHL A
    SHL A
    SHL A
    LDB SCORE_HUNDREDS
    OR A, B
    STA DISPLAY_HIGH

    LDA SCORE_TENS
    SHL A
    SHL A
    SHL A
    SHL A
    LDB SCORE_ONES
    OR A, B
    STA DISPLAY_LOW
    RET

UPDATE_HUD_LIVES:
    STI GLYPH_Y, #$02
    STI GLYPH_X, #$15        ; 21
    LDA LIVES
    STA GLYPH_VALUE
    CALL DRAW_DIGIT
    RET

UPDATE_HUD_LEVEL:
    STI GLYPH_Y, #$02
    STI GLYPH_X, #$1D        ; 29
    LDA LEVEL
    STA GLYPH_VALUE
    CALL DRAW_DIGIT
    RET

DRAW_DIGIT:
    LDA GLYPH_VALUE
    CMP A, #$00
    JZ DIGIT_0
    CMP A, #$01
    JZ DIGIT_1
    CMP A, #$02
    JZ DIGIT_2
    CMP A, #$03
    JZ DIGIT_3
    CMP A, #$04
    JZ DIGIT_4
    CMP A, #$05
    JZ DIGIT_5
    CMP A, #$06
    JZ DIGIT_6
    CMP A, #$07
    JZ DIGIT_7
    CMP A, #$08
    JZ DIGIT_8
    PTR DIGIT9
    JMP DIGIT_DRAW
DIGIT_0:
    PTR DIGIT0
    JMP DIGIT_DRAW
DIGIT_1:
    PTR DIGIT1
    JMP DIGIT_DRAW
DIGIT_2:
    PTR DIGIT2
    JMP DIGIT_DRAW
DIGIT_3:
    PTR DIGIT3
    JMP DIGIT_DRAW
DIGIT_4:
    PTR DIGIT4
    JMP DIGIT_DRAW
DIGIT_5:
    PTR DIGIT5
    JMP DIGIT_DRAW
DIGIT_6:
    PTR DIGIT6
    JMP DIGIT_DRAW
DIGIT_7:
    PTR DIGIT7
    JMP DIGIT_DRAW
DIGIT_8:
    PTR DIGIT8
DIGIT_DRAW:
    LDA GLYPH_Y
    STA TMP0
    STI TMP1, #$08
DIGIT_ROW:
    LDA [PTR+]
    STA GLYPH_BYTE
    CALL VIDEO_WAIT
    LDA GLYPH_X
    STA VIDEO_X
    LDA TMP0
    STA VIDEO_Y
    LDA GLYPH_BYTE
    STA VIDEO_DATA
    LDA TMP0
    INC A
    STA TMP0
    LDA TMP1
    DEC A
    STA TMP1
    JNZ DIGIT_ROW
    RET

; ============================================================================
; SOM
; ============================================================================

SOUND_TICK:
    ; Sons de evento tem prioridade.
    LDA SOUND_TIMER
    CMP A, #$00
    JZ SOUND_HEARTBEAT
    DEC A
    STA SOUND_TIMER
    CMP A, #$00
    JNZ SOUND_TICK_DONE
    STI SOUND_CFG, #$00

SOUND_HEARTBEAT:
    ; "heartbeat" classico de Asteroids quando nenhum outro efeito toca.
    LDA SOUND_TIMER
    CMP A, #$00
    JNZ SOUND_TICK_DONE

    LDA HEART_COUNT
    CMP A, #$00
    JZ HEART_FIRE
    DEC A
    STA HEART_COUNT
    RET

HEART_FIRE:
    LDA HEART_PHASE
    XOR A, #$01
    STA HEART_PHASE
    CMP A, #$00
    JZ HEART_LOW
    STI SOUND_CFG, #$1A       ; D4
    JMP HEART_NOTE_SET
HEART_LOW:
    STI SOUND_CFG, #$1E       ; C4
HEART_NOTE_SET:
    STI SOUND_TIMER, #$01

    ; Heartbeat acelera um pouco com o level.
    LDA LEVEL
    CMP A, #$03
    JC HEART_FAST
    CMP A, #$02
    JC HEART_MED
    STI HEART_COUNT, #$12     ; level 1: ~0,6 s
    RET
HEART_MED:
    STI HEART_COUNT, #$0F
    RET
HEART_FAST:
    STI HEART_COUNT, #$0C

SOUND_TICK_DONE:
    RET

SOUND_START:
    STI SOUND_CFG, #$1E       ; C4
    CALL WAIT_64MS
    STI SOUND_CFG, #$16       ; E4
    CALL WAIT_64MS
    STI SOUND_CFG, #$0E       ; G4
    CALL WAIT_64MS
    STI SOUND_CFG, #$02       ; C5
    CALL WAIT_64MS
    STI SOUND_CFG, #$00
    RET

SOUND_DEATH:
    STI SOUND_CFG, #$02
    CALL WAIT_125MS
    STI SOUND_CFG, #$0A
    CALL WAIT_125MS
    STI SOUND_CFG, #$12
    CALL WAIT_125MS
    STI SOUND_CFG, #$1E
    CALL WAIT_125MS
    STI SOUND_CFG, #$A1       ; noise grave
    CALL WAIT_125MS
    STI SOUND_CFG, #$00
    RET

SOUND_LEVEL:
    STI SOUND_CFG, #$1E
    CALL WAIT_64MS
    STI SOUND_CFG, #$12
    CALL WAIT_64MS
    STI SOUND_CFG, #$0E
    CALL WAIT_64MS
    STI SOUND_CFG, #$0A
    CALL WAIT_64MS
    STI SOUND_CFG, #$02
    CALL WAIT_125MS
    STI SOUND_CFG, #$00
    RET

SOUND_GAMEOVER:
    STI SOUND_CFG, #$0A
    CALL WAIT_125MS
    STI SOUND_CFG, #$12
    CALL WAIT_125MS
    STI SOUND_CFG, #$16
    CALL WAIT_125MS
    STI SOUND_CFG, #$1A
    CALL WAIT_125MS
    STI SOUND_CFG, #$1E
    CALL WAIT_125MS
    STI SOUND_CFG, #$81
    CALL WAIT_125MS
    STI SOUND_CFG, #$00
    RET

WAIT_1MS:
    STI SYSTEM_STATUS, #$00
WAIT_1MS_LOOP:
    LDA SYSTEM_STATUS
    TEST A, #TIMER_1MS_MASK
    JZ WAIT_1MS_LOOP
    RET

WAIT_64MS:
    LDB #$40
WAIT_64_LOOP:
    CALL WAIT_1MS
    DEC B
    JNZ WAIT_64_LOOP
    RET

WAIT_125MS:
    LDB #$80
WAIT_125_LOOP:
    CALL WAIT_1MS
    DEC B
    JNZ WAIT_125_LOOP
    RET

; ============================================================================
; RNG
; ============================================================================

RNG_NEXT:
    LDA RNG_STATE
    TEST A, #$01
    JZ RNG_EVEN
    SHR A
    XOR A, #$B8
    STA RNG_STATE
    RET
RNG_EVEN:
    SHR A
    CMP A, #$00
    JNZ RNG_STORE
    LDA #$A7
RNG_STORE:
    STA RNG_STATE
    RET

; ============================================================================
; GAME OVER
; ============================================================================

GAME_OVER:
    STI SOUND_CFG, #$00
    CALL SOUND_GAMEOVER

    CALL VIDEO_WAIT
    STI VIDEO_CMD, #VIDEO_CLEAR
    CALL VIDEO_WAIT
    CALL DRAW_HUD
    CALL UPDATE_HUD_ALL
    CALL DRAW_GAME_OVER

GAME_OVER_LOOP:
    CALL WAIT_ONE_FRAME
    LDA EXIT_FLAG
    CMP A, #$01
    JZ EXIT_GAME
    LDA RESTART_FLAG
    CMP A, #$01
    JZ GAME_START
    JMP GAME_OVER_LOOP

DRAW_GAME_OVER:
    ; GAME OVER: 9 bytes x 8 rows, x=15, y=96
    PTR GAME_OVER_LINE1
    STI HUD_X, #$0F
    STI HUD_Y, #$60
    STI TMP2, #$09
    CALL DRAW_BANNER_8

    ; R RESTART  Q QUIT: 17 bytes, x=11, y=112
    PTR GAME_OVER_LINE2
    STI HUD_X, #$0B
    STI HUD_Y, #$70
    STI TMP2, #$11
    CALL DRAW_BANNER_8
    RET

; PTR bitmap, HUD_X start, HUD_Y start, TMP2 width.
DRAW_BANNER_8:
    STI HUD_ROWS, #$08
DBAN_ROW:
    LDA HUD_X
    STA TMP0
    LDA TMP2
    STA HUD_COLS
DBAN_COL:
    LDA [PTR+]
    STA GLYPH_BYTE
    CALL VIDEO_WAIT
    LDA TMP0
    STA VIDEO_X
    LDA HUD_Y
    STA VIDEO_Y
    LDA GLYPH_BYTE
    STA VIDEO_DATA
    LDA TMP0
    INC A
    STA TMP0
    LDA HUD_COLS
    DEC A
    STA HUD_COLS
    JNZ DBAN_COL
    LDA HUD_Y
    INC A
    STA HUD_Y
    LDA HUD_ROWS
    DEC A
    STA HUD_ROWS
    JNZ DBAN_ROW
    RET

; ============================================================================
; VIDEO
; ============================================================================

VIDEO_WAIT:
    LDA VIDEO_STATUS
    TEST A, #VIDEO_BUSY_MASK
    JNZ VIDEO_WAIT
    RET

; ============================================================================
; SAIDA
; ============================================================================

EXIT_GAME:
    CALL VIDEO_WAIT
    STI SOUND_CFG, #$00
    STI VIDEO_CMD, #$11       ; texto
    CALL VIDEO_WAIT
    STI VIDEO_CMD, #$00       ; clear
    CALL VIDEO_WAIT
    RET

; ============================================================================
; SELECT_SPRITE_PTR
; Gerado abaixo: 16 sprites x 8 shifts.
; ============================================================================
SELECT_SPRITE_PTR:
    LDA DRAW_SPRITE
    CMP A, #$00
    JZ SEL_SPR_00
    CMP A, #$01
    JZ SEL_SPR_01
    CMP A, #$02
    JZ SEL_SPR_02
    CMP A, #$03
    JZ SEL_SPR_03
    CMP A, #$04
    JZ SEL_SPR_04
    CMP A, #$05
    JZ SEL_SPR_05
    CMP A, #$06
    JZ SEL_SPR_06
    CMP A, #$07
    JZ SEL_SPR_07
    CMP A, #$08
    JZ SEL_SPR_08
    CMP A, #$09
    JZ SEL_SPR_09
    CMP A, #$0A
    JZ SEL_SPR_0A
    CMP A, #$0B
    JZ SEL_SPR_0B
    CMP A, #$0C
    JZ SEL_SPR_0C
    CMP A, #$0D
    JZ SEL_SPR_0D
    CMP A, #$0E
    JZ SEL_SPR_0E
    JMP SEL_SPR_0F

SEL_SPR_00:
    LDA DRAW_SHIFT
    CMP A, #$00
    JZ SEL_SPR_00_S0
    CMP A, #$01
    JZ SEL_SPR_00_S1
    CMP A, #$02
    JZ SEL_SPR_00_S2
    CMP A, #$03
    JZ SEL_SPR_00_S3
    CMP A, #$04
    JZ SEL_SPR_00_S4
    CMP A, #$05
    JZ SEL_SPR_00_S5
    CMP A, #$06
    JZ SEL_SPR_00_S6
    PTR SPR_00_SH7
    RET
SEL_SPR_00_S0:
    PTR SPR_00_SH0
    RET
SEL_SPR_00_S1:
    PTR SPR_00_SH1
    RET
SEL_SPR_00_S2:
    PTR SPR_00_SH2
    RET
SEL_SPR_00_S3:
    PTR SPR_00_SH3
    RET
SEL_SPR_00_S4:
    PTR SPR_00_SH4
    RET
SEL_SPR_00_S5:
    PTR SPR_00_SH5
    RET
SEL_SPR_00_S6:
    PTR SPR_00_SH6
    RET

SEL_SPR_01:
    LDA DRAW_SHIFT
    CMP A, #$00
    JZ SEL_SPR_01_S0
    CMP A, #$01
    JZ SEL_SPR_01_S1
    CMP A, #$02
    JZ SEL_SPR_01_S2
    CMP A, #$03
    JZ SEL_SPR_01_S3
    CMP A, #$04
    JZ SEL_SPR_01_S4
    CMP A, #$05
    JZ SEL_SPR_01_S5
    CMP A, #$06
    JZ SEL_SPR_01_S6
    PTR SPR_01_SH7
    RET
SEL_SPR_01_S0:
    PTR SPR_01_SH0
    RET
SEL_SPR_01_S1:
    PTR SPR_01_SH1
    RET
SEL_SPR_01_S2:
    PTR SPR_01_SH2
    RET
SEL_SPR_01_S3:
    PTR SPR_01_SH3
    RET
SEL_SPR_01_S4:
    PTR SPR_01_SH4
    RET
SEL_SPR_01_S5:
    PTR SPR_01_SH5
    RET
SEL_SPR_01_S6:
    PTR SPR_01_SH6
    RET

SEL_SPR_02:
    LDA DRAW_SHIFT
    CMP A, #$00
    JZ SEL_SPR_02_S0
    CMP A, #$01
    JZ SEL_SPR_02_S1
    CMP A, #$02
    JZ SEL_SPR_02_S2
    CMP A, #$03
    JZ SEL_SPR_02_S3
    CMP A, #$04
    JZ SEL_SPR_02_S4
    CMP A, #$05
    JZ SEL_SPR_02_S5
    CMP A, #$06
    JZ SEL_SPR_02_S6
    PTR SPR_02_SH7
    RET
SEL_SPR_02_S0:
    PTR SPR_02_SH0
    RET
SEL_SPR_02_S1:
    PTR SPR_02_SH1
    RET
SEL_SPR_02_S2:
    PTR SPR_02_SH2
    RET
SEL_SPR_02_S3:
    PTR SPR_02_SH3
    RET
SEL_SPR_02_S4:
    PTR SPR_02_SH4
    RET
SEL_SPR_02_S5:
    PTR SPR_02_SH5
    RET
SEL_SPR_02_S6:
    PTR SPR_02_SH6
    RET

SEL_SPR_03:
    LDA DRAW_SHIFT
    CMP A, #$00
    JZ SEL_SPR_03_S0
    CMP A, #$01
    JZ SEL_SPR_03_S1
    CMP A, #$02
    JZ SEL_SPR_03_S2
    CMP A, #$03
    JZ SEL_SPR_03_S3
    CMP A, #$04
    JZ SEL_SPR_03_S4
    CMP A, #$05
    JZ SEL_SPR_03_S5
    CMP A, #$06
    JZ SEL_SPR_03_S6
    PTR SPR_03_SH7
    RET
SEL_SPR_03_S0:
    PTR SPR_03_SH0
    RET
SEL_SPR_03_S1:
    PTR SPR_03_SH1
    RET
SEL_SPR_03_S2:
    PTR SPR_03_SH2
    RET
SEL_SPR_03_S3:
    PTR SPR_03_SH3
    RET
SEL_SPR_03_S4:
    PTR SPR_03_SH4
    RET
SEL_SPR_03_S5:
    PTR SPR_03_SH5
    RET
SEL_SPR_03_S6:
    PTR SPR_03_SH6
    RET

SEL_SPR_04:
    LDA DRAW_SHIFT
    CMP A, #$00
    JZ SEL_SPR_04_S0
    CMP A, #$01
    JZ SEL_SPR_04_S1
    CMP A, #$02
    JZ SEL_SPR_04_S2
    CMP A, #$03
    JZ SEL_SPR_04_S3
    CMP A, #$04
    JZ SEL_SPR_04_S4
    CMP A, #$05
    JZ SEL_SPR_04_S5
    CMP A, #$06
    JZ SEL_SPR_04_S6
    PTR SPR_04_SH7
    RET
SEL_SPR_04_S0:
    PTR SPR_04_SH0
    RET
SEL_SPR_04_S1:
    PTR SPR_04_SH1
    RET
SEL_SPR_04_S2:
    PTR SPR_04_SH2
    RET
SEL_SPR_04_S3:
    PTR SPR_04_SH3
    RET
SEL_SPR_04_S4:
    PTR SPR_04_SH4
    RET
SEL_SPR_04_S5:
    PTR SPR_04_SH5
    RET
SEL_SPR_04_S6:
    PTR SPR_04_SH6
    RET

SEL_SPR_05:
    LDA DRAW_SHIFT
    CMP A, #$00
    JZ SEL_SPR_05_S0
    CMP A, #$01
    JZ SEL_SPR_05_S1
    CMP A, #$02
    JZ SEL_SPR_05_S2
    CMP A, #$03
    JZ SEL_SPR_05_S3
    CMP A, #$04
    JZ SEL_SPR_05_S4
    CMP A, #$05
    JZ SEL_SPR_05_S5
    CMP A, #$06
    JZ SEL_SPR_05_S6
    PTR SPR_05_SH7
    RET
SEL_SPR_05_S0:
    PTR SPR_05_SH0
    RET
SEL_SPR_05_S1:
    PTR SPR_05_SH1
    RET
SEL_SPR_05_S2:
    PTR SPR_05_SH2
    RET
SEL_SPR_05_S3:
    PTR SPR_05_SH3
    RET
SEL_SPR_05_S4:
    PTR SPR_05_SH4
    RET
SEL_SPR_05_S5:
    PTR SPR_05_SH5
    RET
SEL_SPR_05_S6:
    PTR SPR_05_SH6
    RET

SEL_SPR_06:
    LDA DRAW_SHIFT
    CMP A, #$00
    JZ SEL_SPR_06_S0
    CMP A, #$01
    JZ SEL_SPR_06_S1
    CMP A, #$02
    JZ SEL_SPR_06_S2
    CMP A, #$03
    JZ SEL_SPR_06_S3
    CMP A, #$04
    JZ SEL_SPR_06_S4
    CMP A, #$05
    JZ SEL_SPR_06_S5
    CMP A, #$06
    JZ SEL_SPR_06_S6
    PTR SPR_06_SH7
    RET
SEL_SPR_06_S0:
    PTR SPR_06_SH0
    RET
SEL_SPR_06_S1:
    PTR SPR_06_SH1
    RET
SEL_SPR_06_S2:
    PTR SPR_06_SH2
    RET
SEL_SPR_06_S3:
    PTR SPR_06_SH3
    RET
SEL_SPR_06_S4:
    PTR SPR_06_SH4
    RET
SEL_SPR_06_S5:
    PTR SPR_06_SH5
    RET
SEL_SPR_06_S6:
    PTR SPR_06_SH6
    RET

SEL_SPR_07:
    LDA DRAW_SHIFT
    CMP A, #$00
    JZ SEL_SPR_07_S0
    CMP A, #$01
    JZ SEL_SPR_07_S1
    CMP A, #$02
    JZ SEL_SPR_07_S2
    CMP A, #$03
    JZ SEL_SPR_07_S3
    CMP A, #$04
    JZ SEL_SPR_07_S4
    CMP A, #$05
    JZ SEL_SPR_07_S5
    CMP A, #$06
    JZ SEL_SPR_07_S6
    PTR SPR_07_SH7
    RET
SEL_SPR_07_S0:
    PTR SPR_07_SH0
    RET
SEL_SPR_07_S1:
    PTR SPR_07_SH1
    RET
SEL_SPR_07_S2:
    PTR SPR_07_SH2
    RET
SEL_SPR_07_S3:
    PTR SPR_07_SH3
    RET
SEL_SPR_07_S4:
    PTR SPR_07_SH4
    RET
SEL_SPR_07_S5:
    PTR SPR_07_SH5
    RET
SEL_SPR_07_S6:
    PTR SPR_07_SH6
    RET

SEL_SPR_08:
    LDA DRAW_SHIFT
    CMP A, #$00
    JZ SEL_SPR_08_S0
    CMP A, #$01
    JZ SEL_SPR_08_S1
    CMP A, #$02
    JZ SEL_SPR_08_S2
    CMP A, #$03
    JZ SEL_SPR_08_S3
    CMP A, #$04
    JZ SEL_SPR_08_S4
    CMP A, #$05
    JZ SEL_SPR_08_S5
    CMP A, #$06
    JZ SEL_SPR_08_S6
    PTR SPR_08_SH7
    RET
SEL_SPR_08_S0:
    PTR SPR_08_SH0
    RET
SEL_SPR_08_S1:
    PTR SPR_08_SH1
    RET
SEL_SPR_08_S2:
    PTR SPR_08_SH2
    RET
SEL_SPR_08_S3:
    PTR SPR_08_SH3
    RET
SEL_SPR_08_S4:
    PTR SPR_08_SH4
    RET
SEL_SPR_08_S5:
    PTR SPR_08_SH5
    RET
SEL_SPR_08_S6:
    PTR SPR_08_SH6
    RET

SEL_SPR_09:
    LDA DRAW_SHIFT
    CMP A, #$00
    JZ SEL_SPR_09_S0
    CMP A, #$01
    JZ SEL_SPR_09_S1
    CMP A, #$02
    JZ SEL_SPR_09_S2
    CMP A, #$03
    JZ SEL_SPR_09_S3
    CMP A, #$04
    JZ SEL_SPR_09_S4
    CMP A, #$05
    JZ SEL_SPR_09_S5
    CMP A, #$06
    JZ SEL_SPR_09_S6
    PTR SPR_09_SH7
    RET
SEL_SPR_09_S0:
    PTR SPR_09_SH0
    RET
SEL_SPR_09_S1:
    PTR SPR_09_SH1
    RET
SEL_SPR_09_S2:
    PTR SPR_09_SH2
    RET
SEL_SPR_09_S3:
    PTR SPR_09_SH3
    RET
SEL_SPR_09_S4:
    PTR SPR_09_SH4
    RET
SEL_SPR_09_S5:
    PTR SPR_09_SH5
    RET
SEL_SPR_09_S6:
    PTR SPR_09_SH6
    RET

SEL_SPR_0A:
    LDA DRAW_SHIFT
    CMP A, #$00
    JZ SEL_SPR_0A_S0
    CMP A, #$01
    JZ SEL_SPR_0A_S1
    CMP A, #$02
    JZ SEL_SPR_0A_S2
    CMP A, #$03
    JZ SEL_SPR_0A_S3
    CMP A, #$04
    JZ SEL_SPR_0A_S4
    CMP A, #$05
    JZ SEL_SPR_0A_S5
    CMP A, #$06
    JZ SEL_SPR_0A_S6
    PTR SPR_0A_SH7
    RET
SEL_SPR_0A_S0:
    PTR SPR_0A_SH0
    RET
SEL_SPR_0A_S1:
    PTR SPR_0A_SH1
    RET
SEL_SPR_0A_S2:
    PTR SPR_0A_SH2
    RET
SEL_SPR_0A_S3:
    PTR SPR_0A_SH3
    RET
SEL_SPR_0A_S4:
    PTR SPR_0A_SH4
    RET
SEL_SPR_0A_S5:
    PTR SPR_0A_SH5
    RET
SEL_SPR_0A_S6:
    PTR SPR_0A_SH6
    RET

SEL_SPR_0B:
    LDA DRAW_SHIFT
    CMP A, #$00
    JZ SEL_SPR_0B_S0
    CMP A, #$01
    JZ SEL_SPR_0B_S1
    CMP A, #$02
    JZ SEL_SPR_0B_S2
    CMP A, #$03
    JZ SEL_SPR_0B_S3
    CMP A, #$04
    JZ SEL_SPR_0B_S4
    CMP A, #$05
    JZ SEL_SPR_0B_S5
    CMP A, #$06
    JZ SEL_SPR_0B_S6
    PTR SPR_0B_SH7
    RET
SEL_SPR_0B_S0:
    PTR SPR_0B_SH0
    RET
SEL_SPR_0B_S1:
    PTR SPR_0B_SH1
    RET
SEL_SPR_0B_S2:
    PTR SPR_0B_SH2
    RET
SEL_SPR_0B_S3:
    PTR SPR_0B_SH3
    RET
SEL_SPR_0B_S4:
    PTR SPR_0B_SH4
    RET
SEL_SPR_0B_S5:
    PTR SPR_0B_SH5
    RET
SEL_SPR_0B_S6:
    PTR SPR_0B_SH6
    RET

SEL_SPR_0C:
    LDA DRAW_SHIFT
    CMP A, #$00
    JZ SEL_SPR_0C_S0
    CMP A, #$01
    JZ SEL_SPR_0C_S1
    CMP A, #$02
    JZ SEL_SPR_0C_S2
    CMP A, #$03
    JZ SEL_SPR_0C_S3
    CMP A, #$04
    JZ SEL_SPR_0C_S4
    CMP A, #$05
    JZ SEL_SPR_0C_S5
    CMP A, #$06
    JZ SEL_SPR_0C_S6
    PTR SPR_0C_SH7
    RET
SEL_SPR_0C_S0:
    PTR SPR_0C_SH0
    RET
SEL_SPR_0C_S1:
    PTR SPR_0C_SH1
    RET
SEL_SPR_0C_S2:
    PTR SPR_0C_SH2
    RET
SEL_SPR_0C_S3:
    PTR SPR_0C_SH3
    RET
SEL_SPR_0C_S4:
    PTR SPR_0C_SH4
    RET
SEL_SPR_0C_S5:
    PTR SPR_0C_SH5
    RET
SEL_SPR_0C_S6:
    PTR SPR_0C_SH6
    RET

SEL_SPR_0D:
    LDA DRAW_SHIFT
    CMP A, #$00
    JZ SEL_SPR_0D_S0
    CMP A, #$01
    JZ SEL_SPR_0D_S1
    CMP A, #$02
    JZ SEL_SPR_0D_S2
    CMP A, #$03
    JZ SEL_SPR_0D_S3
    CMP A, #$04
    JZ SEL_SPR_0D_S4
    CMP A, #$05
    JZ SEL_SPR_0D_S5
    CMP A, #$06
    JZ SEL_SPR_0D_S6
    PTR SPR_0D_SH7
    RET
SEL_SPR_0D_S0:
    PTR SPR_0D_SH0
    RET
SEL_SPR_0D_S1:
    PTR SPR_0D_SH1
    RET
SEL_SPR_0D_S2:
    PTR SPR_0D_SH2
    RET
SEL_SPR_0D_S3:
    PTR SPR_0D_SH3
    RET
SEL_SPR_0D_S4:
    PTR SPR_0D_SH4
    RET
SEL_SPR_0D_S5:
    PTR SPR_0D_SH5
    RET
SEL_SPR_0D_S6:
    PTR SPR_0D_SH6
    RET

SEL_SPR_0E:
    LDA DRAW_SHIFT
    CMP A, #$00
    JZ SEL_SPR_0E_S0
    CMP A, #$01
    JZ SEL_SPR_0E_S1
    CMP A, #$02
    JZ SEL_SPR_0E_S2
    CMP A, #$03
    JZ SEL_SPR_0E_S3
    CMP A, #$04
    JZ SEL_SPR_0E_S4
    CMP A, #$05
    JZ SEL_SPR_0E_S5
    CMP A, #$06
    JZ SEL_SPR_0E_S6
    PTR SPR_0E_SH7
    RET
SEL_SPR_0E_S0:
    PTR SPR_0E_SH0
    RET
SEL_SPR_0E_S1:
    PTR SPR_0E_SH1
    RET
SEL_SPR_0E_S2:
    PTR SPR_0E_SH2
    RET
SEL_SPR_0E_S3:
    PTR SPR_0E_SH3
    RET
SEL_SPR_0E_S4:
    PTR SPR_0E_SH4
    RET
SEL_SPR_0E_S5:
    PTR SPR_0E_SH5
    RET
SEL_SPR_0E_S6:
    PTR SPR_0E_SH6
    RET

SEL_SPR_0F:
    LDA DRAW_SHIFT
    CMP A, #$00
    JZ SEL_SPR_0F_S0
    CMP A, #$01
    JZ SEL_SPR_0F_S1
    CMP A, #$02
    JZ SEL_SPR_0F_S2
    CMP A, #$03
    JZ SEL_SPR_0F_S3
    CMP A, #$04
    JZ SEL_SPR_0F_S4
    CMP A, #$05
    JZ SEL_SPR_0F_S5
    CMP A, #$06
    JZ SEL_SPR_0F_S6
    PTR SPR_0F_SH7
    RET
SEL_SPR_0F_S0:
    PTR SPR_0F_SH0
    RET
SEL_SPR_0F_S1:
    PTR SPR_0F_SH1
    RET
SEL_SPR_0F_S2:
    PTR SPR_0F_SH2
    RET
SEL_SPR_0F_S3:
    PTR SPR_0F_SH3
    RET
SEL_SPR_0F_S4:
    PTR SPR_0F_SH4
    RET
SEL_SPR_0F_S5:
    PTR SPR_0F_SH5
    RET
SEL_SPR_0F_S6:
    PTR SPR_0F_SH6
    RET


; ============================================================================
; BITMAP DATA
; Em cada byte: D0 = pixel mais a esquerda, D7 = pixel mais a direita.
; ============================================================================

HUD_LINE1:
    #d8 $00, $3C, $3C, $3C, $3E, $7E, $00, $3C, $3C, $3C, $3C, $00, $00, $00, $00, $06, $7E, $66, $7E, $3C, $00, $3C, $00, $00, $00, $00, $06, $66, $00, $18, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    #d8 $00, $66, $66, $66, $66, $06, $00, $66, $66, $66, $66, $00, $00, $00, $00, $06, $18, $66, $06, $66, $00, $66, $00, $00, $00, $00, $06, $66, $00, $1C, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    #d8 $00, $06, $06, $66, $66, $06, $00, $76, $76, $76, $76, $00, $00, $00, $00, $06, $18, $66, $06, $06, $00, $60, $00, $00, $00, $00, $06, $66, $00, $18, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    #d8 $00, $3C, $06, $66, $3E, $3E, $00, $6E, $6E, $6E, $6E, $00, $00, $00, $00, $06, $18, $66, $3E, $3C, $00, $38, $00, $00, $00, $00, $06, $66, $00, $18, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    #d8 $00, $60, $06, $66, $1E, $06, $00, $66, $66, $66, $66, $00, $00, $00, $00, $06, $18, $66, $06, $60, $00, $60, $00, $00, $00, $00, $06, $66, $00, $18, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    #d8 $00, $66, $66, $66, $36, $06, $00, $66, $66, $66, $66, $00, $00, $00, $00, $06, $18, $3C, $06, $66, $00, $66, $00, $00, $00, $00, $06, $3C, $00, $18, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    #d8 $00, $3C, $3C, $3C, $66, $7E, $00, $3C, $3C, $3C, $3C, $00, $00, $00, $00, $7E, $7E, $18, $7E, $3C, $00, $3C, $00, $00, $00, $00, $7E, $18, $00, $7E, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    #d8 $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00

HUD_LINE2:
    #d8 $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $18, $3C, $7E, $7E, $3E, $3C, $7E, $1E, $3C, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    #d8 $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $3C, $66, $18, $06, $66, $66, $18, $36, $66, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    #d8 $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $66, $06, $18, $06, $66, $66, $18, $66, $06, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    #d8 $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $66, $3C, $18, $3E, $3E, $66, $18, $66, $3C, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    #d8 $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $7E, $60, $18, $06, $1E, $66, $18, $66, $60, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    #d8 $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $66, $66, $18, $06, $36, $66, $18, $36, $66, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    #d8 $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $66, $3C, $18, $7E, $66, $3C, $7E, $1E, $3C, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    #d8 $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00

GAME_OVER_LINE1:
    #d8 $3C, $18, $C6, $7E, $00, $3C, $66, $7E, $3E
    #d8 $66, $3C, $EE, $06, $00, $66, $66, $06, $66
    #d8 $06, $66, $FE, $06, $00, $66, $66, $06, $66
    #d8 $76, $66, $D6, $3E, $00, $66, $66, $3E, $3E
    #d8 $66, $7E, $C6, $06, $00, $66, $66, $06, $1E
    #d8 $66, $66, $C6, $06, $00, $66, $3C, $06, $36
    #d8 $7C, $66, $C6, $7E, $00, $3C, $18, $7E, $66
    #d8 $00, $00, $00, $00, $00, $00, $00, $00, $00

GAME_OVER_LINE2:
    #d8 $3E, $00, $3E, $7E, $3C, $7E, $18, $3E, $7E, $00, $00, $3C, $00, $3C, $00, $7E, $7E
    #d8 $66, $00, $66, $06, $66, $18, $3C, $66, $18, $00, $00, $66, $00, $66, $00, $18, $18
    #d8 $66, $00, $66, $06, $06, $18, $66, $66, $18, $00, $00, $66, $00, $66, $00, $18, $18
    #d8 $3E, $00, $3E, $3E, $3C, $18, $66, $3E, $18, $00, $00, $66, $00, $66, $00, $18, $18
    #d8 $1E, $00, $1E, $06, $60, $18, $7E, $1E, $18, $00, $00, $76, $00, $76, $00, $18, $18
    #d8 $36, $00, $36, $06, $66, $18, $66, $36, $18, $00, $00, $3C, $00, $3C, $00, $18, $18
    #d8 $66, $00, $66, $7E, $3C, $18, $66, $66, $18, $00, $00, $60, $00, $60, $00, $7E, $18
    #d8 $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00

DIGIT0:
    #d8 $3C, $66, $76, $6E, $66, $66, $3C, $00
DIGIT1:
    #d8 $18, $1C, $18, $18, $18, $18, $7E, $00
DIGIT2:
    #d8 $3C, $66, $60, $30, $18, $0C, $7E, $00
DIGIT3:
    #d8 $3C, $66, $60, $38, $60, $66, $3C, $00
DIGIT4:
    #d8 $30, $38, $3C, $36, $7E, $30, $30, $00
DIGIT5:
    #d8 $7E, $06, $3E, $60, $60, $66, $3C, $00
DIGIT6:
    #d8 $38, $0C, $06, $3E, $66, $66, $3C, $00
DIGIT7:
    #d8 $7E, $60, $30, $18, $0C, $0C, $0C, $00
DIGIT8:
    #d8 $3C, $66, $66, $3C, $66, $66, $3C, $00
DIGIT9:
    #d8 $3C, $66, $66, $7C, $60, $30, $1C, $00

; ============================================================================
; SPRITE DATA - 48 bytes por shift
; ============================================================================

SPR_00_SH0:
    #d8 $00, $01, $00, $00, $01, $00, $80, $02, $00, $80, $02, $00, $40, $02, $00, $40
    #d8 $02, $00, $20, $04, $00, $20, $04, $00, $20, $04, $00, $10, $08, $00, $10, $09
    #d8 $00, $C8, $0A, $00, $28, $0C, $00, $1C, $18, $00, $04, $10, $00, $00, $00, $00

SPR_00_SH1:
    #d8 $00, $02, $00, $00, $02, $00, $00, $05, $00, $00, $05, $00, $80, $04, $00, $80
    #d8 $04, $00, $40, $08, $00, $40, $08, $00, $40, $08, $00, $20, $10, $00, $20, $12
    #d8 $00, $90, $15, $00, $50, $18, $00, $38, $30, $00, $08, $20, $00, $00, $00, $00

SPR_00_SH2:
    #d8 $00, $04, $00, $00, $04, $00, $00, $0A, $00, $00, $0A, $00, $00, $09, $00, $00
    #d8 $09, $00, $80, $10, $00, $80, $10, $00, $80, $10, $00, $40, $20, $00, $40, $24
    #d8 $00, $20, $2B, $00, $A0, $30, $00, $70, $60, $00, $10, $40, $00, $00, $00, $00

SPR_00_SH3:
    #d8 $00, $08, $00, $00, $08, $00, $00, $14, $00, $00, $14, $00, $00, $12, $00, $00
    #d8 $12, $00, $00, $21, $00, $00, $21, $00, $00, $21, $00, $80, $40, $00, $80, $48
    #d8 $00, $40, $56, $00, $40, $61, $00, $E0, $C0, $00, $20, $80, $00, $00, $00, $00

SPR_00_SH4:
    #d8 $00, $10, $00, $00, $10, $00, $00, $28, $00, $00, $28, $00, $00, $24, $00, $00
    #d8 $24, $00, $00, $42, $00, $00, $42, $00, $00, $42, $00, $00, $81, $00, $00, $91
    #d8 $00, $80, $AC, $00, $80, $C2, $00, $C0, $81, $01, $40, $00, $01, $00, $00, $00

SPR_00_SH5:
    #d8 $00, $20, $00, $00, $20, $00, $00, $50, $00, $00, $50, $00, $00, $48, $00, $00
    #d8 $48, $00, $00, $84, $00, $00, $84, $00, $00, $84, $00, $00, $02, $01, $00, $22
    #d8 $01, $00, $59, $01, $00, $85, $01, $80, $03, $03, $80, $00, $02, $00, $00, $00

SPR_00_SH6:
    #d8 $00, $40, $00, $00, $40, $00, $00, $A0, $00, $00, $A0, $00, $00, $90, $00, $00
    #d8 $90, $00, $00, $08, $01, $00, $08, $01, $00, $08, $01, $00, $04, $02, $00, $44
    #d8 $02, $00, $B2, $02, $00, $0A, $03, $00, $07, $06, $00, $01, $04, $00, $00, $00

SPR_00_SH7:
    #d8 $00, $80, $00, $00, $80, $00, $00, $40, $01, $00, $40, $01, $00, $20, $01, $00
    #d8 $20, $01, $00, $10, $02, $00, $10, $02, $00, $10, $02, $00, $08, $04, $00, $88
    #d8 $04, $00, $64, $05, $00, $14, $06, $00, $0E, $0C, $00, $02, $08, $00, $00, $00

SPR_01_SH0:
    #d8 $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $18, $00, $00, $16, $00, $80
    #d8 $09, $00, $70, $08, $00, $0C, $04, $00, $03, $04, $00, $0C, $04, $00, $30, $02
    #d8 $00, $20, $02, $00, $40, $01, $00, $40, $01, $00, $80, $00, $00, $80, $00, $00

SPR_01_SH1:
    #d8 $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $30, $00, $00, $2C, $00, $00
    #d8 $13, $00, $E0, $10, $00, $18, $08, $00, $06, $08, $00, $18, $08, $00, $60, $04
    #d8 $00, $40, $04, $00, $80, $02, $00, $80, $02, $00, $00, $01, $00, $00, $01, $00

SPR_01_SH2:
    #d8 $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $60, $00, $00, $58, $00, $00
    #d8 $26, $00, $C0, $21, $00, $30, $10, $00, $0C, $10, $00, $30, $10, $00, $C0, $08
    #d8 $00, $80, $08, $00, $00, $05, $00, $00, $05, $00, $00, $02, $00, $00, $02, $00

SPR_01_SH3:
    #d8 $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $C0, $00, $00, $B0, $00, $00
    #d8 $4C, $00, $80, $43, $00, $60, $20, $00, $18, $20, $00, $60, $20, $00, $80, $11
    #d8 $00, $00, $11, $00, $00, $0A, $00, $00, $0A, $00, $00, $04, $00, $00, $04, $00

SPR_01_SH4:
    #d8 $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $80, $01, $00, $60, $01, $00
    #d8 $98, $00, $00, $87, $00, $C0, $40, $00, $30, $40, $00, $C0, $40, $00, $00, $23
    #d8 $00, $00, $22, $00, $00, $14, $00, $00, $14, $00, $00, $08, $00, $00, $08, $00

SPR_01_SH5:
    #d8 $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $03, $00, $C0, $02, $00
    #d8 $30, $01, $00, $0E, $01, $80, $81, $00, $60, $80, $00, $80, $81, $00, $00, $46
    #d8 $00, $00, $44, $00, $00, $28, $00, $00, $28, $00, $00, $10, $00, $00, $10, $00

SPR_01_SH6:
    #d8 $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $06, $00, $80, $05, $00
    #d8 $60, $02, $00, $1C, $02, $00, $03, $01, $C0, $00, $01, $00, $03, $01, $00, $8C
    #d8 $00, $00, $88, $00, $00, $50, $00, $00, $50, $00, $00, $20, $00, $00, $20, $00

SPR_01_SH7:
    #d8 $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $0C, $00, $00, $0B, $00
    #d8 $C0, $04, $00, $38, $04, $00, $06, $02, $80, $01, $02, $00, $06, $02, $00, $18
    #d8 $01, $00, $10, $01, $00, $A0, $00, $00, $A0, $00, $00, $40, $00, $00, $40, $00

SPR_02_SH0:
    #d8 $00, $00, $00, $00, $00, $00, $00, $00, $00, $0C, $00, $00, $34, $00, $00, $C8
    #d8 $01, $00, $08, $06, $00, $10, $18, $00, $10, $60, $00, $08, $1C, $00, $88, $03
    #d8 $00, $74, $00, $00, $0C, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00

SPR_02_SH1:
    #d8 $00, $00, $00, $00, $00, $00, $00, $00, $00, $18, $00, $00, $68, $00, $00, $90
    #d8 $03, $00, $10, $0C, $00, $20, $30, $00, $20, $C0, $00, $10, $38, $00, $10, $07
    #d8 $00, $E8, $00, $00, $18, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00

SPR_02_SH2:
    #d8 $00, $00, $00, $00, $00, $00, $00, $00, $00, $30, $00, $00, $D0, $00, $00, $20
    #d8 $07, $00, $20, $18, $00, $40, $60, $00, $40, $80, $01, $20, $70, $00, $20, $0E
    #d8 $00, $D0, $01, $00, $30, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00

SPR_02_SH3:
    #d8 $00, $00, $00, $00, $00, $00, $00, $00, $00, $60, $00, $00, $A0, $01, $00, $40
    #d8 $0E, $00, $40, $30, $00, $80, $C0, $00, $80, $00, $03, $40, $E0, $00, $40, $1C
    #d8 $00, $A0, $03, $00, $60, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00

SPR_02_SH4:
    #d8 $00, $00, $00, $00, $00, $00, $00, $00, $00, $C0, $00, $00, $40, $03, $00, $80
    #d8 $1C, $00, $80, $60, $00, $00, $81, $01, $00, $01, $06, $80, $C0, $01, $80, $38
    #d8 $00, $40, $07, $00, $C0, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00

SPR_02_SH5:
    #d8 $00, $00, $00, $00, $00, $00, $00, $00, $00, $80, $01, $00, $80, $06, $00, $00
    #d8 $39, $00, $00, $C1, $00, $00, $02, $03, $00, $02, $0C, $00, $81, $03, $00, $71
    #d8 $00, $80, $0E, $00, $80, $01, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00

SPR_02_SH6:
    #d8 $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $03, $00, $00, $0D, $00, $00
    #d8 $72, $00, $00, $82, $01, $00, $04, $06, $00, $04, $18, $00, $02, $07, $00, $E2
    #d8 $00, $00, $1D, $00, $00, $03, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00

SPR_02_SH7:
    #d8 $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $06, $00, $00, $1A, $00, $00
    #d8 $E4, $00, $00, $04, $03, $00, $08, $0C, $00, $08, $30, $00, $04, $0E, $00, $C4
    #d8 $01, $00, $3A, $00, $00, $06, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00

SPR_03_SH0:
    #d8 $80, $00, $00, $80, $00, $00, $40, $01, $00, $40, $01, $00, $20, $02, $00, $30
    #d8 $02, $00, $0C, $02, $00, $03, $04, $00, $0C, $04, $00, $30, $08, $00, $C0, $09
    #d8 $00, $00, $16, $00, $00, $18, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00

SPR_03_SH1:
    #d8 $00, $01, $00, $00, $01, $00, $80, $02, $00, $80, $02, $00, $40, $04, $00, $60
    #d8 $04, $00, $18, $04, $00, $06, $08, $00, $18, $08, $00, $60, $10, $00, $80, $13
    #d8 $00, $00, $2C, $00, $00, $30, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00

SPR_03_SH2:
    #d8 $00, $02, $00, $00, $02, $00, $00, $05, $00, $00, $05, $00, $80, $08, $00, $C0
    #d8 $08, $00, $30, $08, $00, $0C, $10, $00, $30, $10, $00, $C0, $20, $00, $00, $27
    #d8 $00, $00, $58, $00, $00, $60, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00

SPR_03_SH3:
    #d8 $00, $04, $00, $00, $04, $00, $00, $0A, $00, $00, $0A, $00, $00, $11, $00, $80
    #d8 $11, $00, $60, $10, $00, $18, $20, $00, $60, $20, $00, $80, $41, $00, $00, $4E
    #d8 $00, $00, $B0, $00, $00, $C0, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00

SPR_03_SH4:
    #d8 $00, $08, $00, $00, $08, $00, $00, $14, $00, $00, $14, $00, $00, $22, $00, $00
    #d8 $23, $00, $C0, $20, $00, $30, $40, $00, $C0, $40, $00, $00, $83, $00, $00, $9C
    #d8 $00, $00, $60, $01, $00, $80, $01, $00, $00, $00, $00, $00, $00, $00, $00, $00

SPR_03_SH5:
    #d8 $00, $10, $00, $00, $10, $00, $00, $28, $00, $00, $28, $00, $00, $44, $00, $00
    #d8 $46, $00, $80, $41, $00, $60, $80, $00, $80, $81, $00, $00, $06, $01, $00, $38
    #d8 $01, $00, $C0, $02, $00, $00, $03, $00, $00, $00, $00, $00, $00, $00, $00, $00

SPR_03_SH6:
    #d8 $00, $20, $00, $00, $20, $00, $00, $50, $00, $00, $50, $00, $00, $88, $00, $00
    #d8 $8C, $00, $00, $83, $00, $C0, $00, $01, $00, $03, $01, $00, $0C, $02, $00, $70
    #d8 $02, $00, $80, $05, $00, $00, $06, $00, $00, $00, $00, $00, $00, $00, $00, $00

SPR_03_SH7:
    #d8 $00, $40, $00, $00, $40, $00, $00, $A0, $00, $00, $A0, $00, $00, $10, $01, $00
    #d8 $18, $01, $00, $06, $01, $80, $01, $02, $00, $06, $02, $00, $18, $04, $00, $E0
    #d8 $04, $00, $00, $0B, $00, $00, $0C, $00, $00, $00, $00, $00, $00, $00, $00, $00

SPR_04_SH0:
    #d8 $00, $00, $00, $00, $10, $00, $0C, $18, $00, $78, $0E, $00, $88, $09, $00, $10
    #d8 $08, $00, $10, $04, $00, $20, $04, $00, $20, $04, $00, $40, $04, $00, $40, $02
    #d8 $00, $80, $02, $00, $80, $02, $00, $00, $01, $00, $00, $01, $00, $00, $00, $00

SPR_04_SH1:
    #d8 $00, $00, $00, $00, $20, $00, $18, $30, $00, $F0, $1C, $00, $10, $13, $00, $20
    #d8 $10, $00, $20, $08, $00, $40, $08, $00, $40, $08, $00, $80, $08, $00, $80, $04
    #d8 $00, $00, $05, $00, $00, $05, $00, $00, $02, $00, $00, $02, $00, $00, $00, $00

SPR_04_SH2:
    #d8 $00, $00, $00, $00, $40, $00, $30, $60, $00, $E0, $39, $00, $20, $26, $00, $40
    #d8 $20, $00, $40, $10, $00, $80, $10, $00, $80, $10, $00, $00, $11, $00, $00, $09
    #d8 $00, $00, $0A, $00, $00, $0A, $00, $00, $04, $00, $00, $04, $00, $00, $00, $00

SPR_04_SH3:
    #d8 $00, $00, $00, $00, $80, $00, $60, $C0, $00, $C0, $73, $00, $40, $4C, $00, $80
    #d8 $40, $00, $80, $20, $00, $00, $21, $00, $00, $21, $00, $00, $22, $00, $00, $12
    #d8 $00, $00, $14, $00, $00, $14, $00, $00, $08, $00, $00, $08, $00, $00, $00, $00

SPR_04_SH4:
    #d8 $00, $00, $00, $00, $00, $01, $C0, $80, $01, $80, $E7, $00, $80, $98, $00, $00
    #d8 $81, $00, $00, $41, $00, $00, $42, $00, $00, $42, $00, $00, $44, $00, $00, $24
    #d8 $00, $00, $28, $00, $00, $28, $00, $00, $10, $00, $00, $10, $00, $00, $00, $00

SPR_04_SH5:
    #d8 $00, $00, $00, $00, $00, $02, $80, $01, $03, $00, $CF, $01, $00, $31, $01, $00
    #d8 $02, $01, $00, $82, $00, $00, $84, $00, $00, $84, $00, $00, $88, $00, $00, $48
    #d8 $00, $00, $50, $00, $00, $50, $00, $00, $20, $00, $00, $20, $00, $00, $00, $00

SPR_04_SH6:
    #d8 $00, $00, $00, $00, $00, $04, $00, $03, $06, $00, $9E, $03, $00, $62, $02, $00
    #d8 $04, $02, $00, $04, $01, $00, $08, $01, $00, $08, $01, $00, $10, $01, $00, $90
    #d8 $00, $00, $A0, $00, $00, $A0, $00, $00, $40, $00, $00, $40, $00, $00, $00, $00

SPR_04_SH7:
    #d8 $00, $00, $00, $00, $00, $08, $00, $06, $0C, $00, $3C, $07, $00, $C4, $04, $00
    #d8 $08, $04, $00, $08, $02, $00, $10, $02, $00, $10, $02, $00, $20, $02, $00, $20
    #d8 $01, $00, $40, $01, $00, $40, $01, $00, $80, $00, $00, $80, $00, $00, $00, $00

SPR_05_SH0:
    #d8 $00, $01, $00, $00, $01, $00, $80, $02, $00, $80, $02, $00, $40, $04, $00, $40
    #d8 $0C, $00, $20, $30, $00, $20, $C0, $00, $20, $30, $00, $10, $0E, $00, $90, $01
    #d8 $00, $68, $00, $00, $18, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00

SPR_05_SH1:
    #d8 $00, $02, $00, $00, $02, $00, $00, $05, $00, $00, $05, $00, $80, $08, $00, $80
    #d8 $18, $00, $40, $60, $00, $40, $80, $01, $40, $60, $00, $20, $1C, $00, $20, $03
    #d8 $00, $D0, $00, $00, $30, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00

SPR_05_SH2:
    #d8 $00, $04, $00, $00, $04, $00, $00, $0A, $00, $00, $0A, $00, $00, $11, $00, $00
    #d8 $31, $00, $80, $C0, $00, $80, $00, $03, $80, $C0, $00, $40, $38, $00, $40, $06
    #d8 $00, $A0, $01, $00, $60, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00

SPR_05_SH3:
    #d8 $00, $08, $00, $00, $08, $00, $00, $14, $00, $00, $14, $00, $00, $22, $00, $00
    #d8 $62, $00, $00, $81, $01, $00, $01, $06, $00, $81, $01, $80, $70, $00, $80, $0C
    #d8 $00, $40, $03, $00, $C0, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00

SPR_05_SH4:
    #d8 $00, $10, $00, $00, $10, $00, $00, $28, $00, $00, $28, $00, $00, $44, $00, $00
    #d8 $C4, $00, $00, $02, $03, $00, $02, $0C, $00, $02, $03, $00, $E1, $00, $00, $19
    #d8 $00, $80, $06, $00, $80, $01, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00

SPR_05_SH5:
    #d8 $00, $20, $00, $00, $20, $00, $00, $50, $00, $00, $50, $00, $00, $88, $00, $00
    #d8 $88, $01, $00, $04, $06, $00, $04, $18, $00, $04, $06, $00, $C2, $01, $00, $32
    #d8 $00, $00, $0D, $00, $00, $03, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00

SPR_05_SH6:
    #d8 $00, $40, $00, $00, $40, $00, $00, $A0, $00, $00, $A0, $00, $00, $10, $01, $00
    #d8 $10, $03, $00, $08, $0C, $00, $08, $30, $00, $08, $0C, $00, $84, $03, $00, $64
    #d8 $00, $00, $1A, $00, $00, $06, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00

SPR_05_SH7:
    #d8 $00, $80, $00, $00, $80, $00, $00, $40, $01, $00, $40, $01, $00, $20, $02, $00
    #d8 $20, $06, $00, $10, $18, $00, $10, $60, $00, $10, $18, $00, $08, $07, $00, $C8
    #d8 $00, $00, $34, $00, $00, $0C, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00

SPR_06_SH0:
    #d8 $00, $00, $00, $00, $00, $00, $00, $60, $00, $00, $38, $00, $00, $16, $00, $C0
    #d8 $11, $00, $30, $08, $00, $0C, $04, $00, $03, $08, $00, $3C, $10, $00, $C0, $11
    #d8 $00, $00, $3E, $00, $00, $60, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00

SPR_06_SH1:
    #d8 $00, $00, $00, $00, $00, $00, $00, $C0, $00, $00, $70, $00, $00, $2C, $00, $80
    #d8 $23, $00, $60, $10, $00, $18, $08, $00, $06, $10, $00, $78, $20, $00, $80, $23
    #d8 $00, $00, $7C, $00, $00, $C0, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00

SPR_06_SH2:
    #d8 $00, $00, $00, $00, $00, $00, $00, $80, $01, $00, $E0, $00, $00, $58, $00, $00
    #d8 $47, $00, $C0, $20, $00, $30, $10, $00, $0C, $20, $00, $F0, $40, $00, $00, $47
    #d8 $00, $00, $F8, $00, $00, $80, $01, $00, $00, $00, $00, $00, $00, $00, $00, $00

SPR_06_SH3:
    #d8 $00, $00, $00, $00, $00, $00, $00, $00, $03, $00, $C0, $01, $00, $B0, $00, $00
    #d8 $8E, $00, $80, $41, $00, $60, $20, $00, $18, $40, $00, $E0, $81, $00, $00, $8E
    #d8 $00, $00, $F0, $01, $00, $00, $03, $00, $00, $00, $00, $00, $00, $00, $00, $00

SPR_06_SH4:
    #d8 $00, $00, $00, $00, $00, $00, $00, $00, $06, $00, $80, $03, $00, $60, $01, $00
    #d8 $1C, $01, $00, $83, $00, $C0, $40, $00, $30, $80, $00, $C0, $03, $01, $00, $1C
    #d8 $01, $00, $E0, $03, $00, $00, $06, $00, $00, $00, $00, $00, $00, $00, $00, $00

SPR_06_SH5:
    #d8 $00, $00, $00, $00, $00, $00, $00, $00, $0C, $00, $00, $07, $00, $C0, $02, $00
    #d8 $38, $02, $00, $06, $01, $80, $81, $00, $60, $00, $01, $80, $07, $02, $00, $38
    #d8 $02, $00, $C0, $07, $00, $00, $0C, $00, $00, $00, $00, $00, $00, $00, $00, $00

SPR_06_SH6:
    #d8 $00, $00, $00, $00, $00, $00, $00, $00, $18, $00, $00, $0E, $00, $80, $05, $00
    #d8 $70, $04, $00, $0C, $02, $00, $03, $01, $C0, $00, $02, $00, $0F, $04, $00, $70
    #d8 $04, $00, $80, $0F, $00, $00, $18, $00, $00, $00, $00, $00, $00, $00, $00, $00

SPR_06_SH7:
    #d8 $00, $00, $00, $00, $00, $00, $00, $00, $30, $00, $00, $1C, $00, $00, $0B, $00
    #d8 $E0, $08, $00, $18, $04, $00, $06, $02, $80, $01, $04, $00, $1E, $08, $00, $E0
    #d8 $08, $00, $00, $1F, $00, $00, $30, $00, $00, $00, $00, $00, $00, $00, $00, $00

SPR_07_SH0:
    #d8 $00, $00, $00, $00, $00, $00, $00, $00, $00, $18, $00, $00, $68, $00, $00, $90
    #d8 $03, $00, $10, $0C, $00, $20, $30, $00, $20, $C0, $00, $40, $30, $00, $40, $0C
    #d8 $00, $40, $04, $00, $80, $02, $00, $80, $02, $00, $00, $01, $00, $00, $01, $00

SPR_07_SH1:
    #d8 $00, $00, $00, $00, $00, $00, $00, $00, $00, $30, $00, $00, $D0, $00, $00, $20
    #d8 $07, $00, $20, $18, $00, $40, $60, $00, $40, $80, $01, $80, $60, $00, $80, $18
    #d8 $00, $80, $08, $00, $00, $05, $00, $00, $05, $00, $00, $02, $00, $00, $02, $00

SPR_07_SH2:
    #d8 $00, $00, $00, $00, $00, $00, $00, $00, $00, $60, $00, $00, $A0, $01, $00, $40
    #d8 $0E, $00, $40, $30, $00, $80, $C0, $00, $80, $00, $03, $00, $C1, $00, $00, $31
    #d8 $00, $00, $11, $00, $00, $0A, $00, $00, $0A, $00, $00, $04, $00, $00, $04, $00

SPR_07_SH3:
    #d8 $00, $00, $00, $00, $00, $00, $00, $00, $00, $C0, $00, $00, $40, $03, $00, $80
    #d8 $1C, $00, $80, $60, $00, $00, $81, $01, $00, $01, $06, $00, $82, $01, $00, $62
    #d8 $00, $00, $22, $00, $00, $14, $00, $00, $14, $00, $00, $08, $00, $00, $08, $00

SPR_07_SH4:
    #d8 $00, $00, $00, $00, $00, $00, $00, $00, $00, $80, $01, $00, $80, $06, $00, $00
    #d8 $39, $00, $00, $C1, $00, $00, $02, $03, $00, $02, $0C, $00, $04, $03, $00, $C4
    #d8 $00, $00, $44, $00, $00, $28, $00, $00, $28, $00, $00, $10, $00, $00, $10, $00

SPR_07_SH5:
    #d8 $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $03, $00, $00, $0D, $00, $00
    #d8 $72, $00, $00, $82, $01, $00, $04, $06, $00, $04, $18, $00, $08, $06, $00, $88
    #d8 $01, $00, $88, $00, $00, $50, $00, $00, $50, $00, $00, $20, $00, $00, $20, $00

SPR_07_SH6:
    #d8 $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $06, $00, $00, $1A, $00, $00
    #d8 $E4, $00, $00, $04, $03, $00, $08, $0C, $00, $08, $30, $00, $10, $0C, $00, $10
    #d8 $03, $00, $10, $01, $00, $A0, $00, $00, $A0, $00, $00, $40, $00, $00, $40, $00

SPR_07_SH7:
    #d8 $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $0C, $00, $00, $34, $00, $00
    #d8 $C8, $01, $00, $08, $06, $00, $10, $18, $00, $10, $60, $00, $20, $18, $00, $20
    #d8 $06, $00, $20, $02, $00, $40, $01, $00, $40, $01, $00, $80, $00, $00, $80, $00

SPR_08_SH0:
    #d8 $38, $1C, $00, $C4, $23, $00, $04, $20, $00, $02, $40, $00, $01, $40, $00, $02
    #d8 $80, $00, $02, $40, $00, $04, $40, $00, $04, $20, $00, $02, $40, $00, $02, $40
    #d8 $00, $01, $80, $00, $02, $80, $00, $82, $41, $00, $64, $36, $00, $18, $08, $00

SPR_08_SH1:
    #d8 $70, $38, $00, $88, $47, $00, $08, $40, $00, $04, $80, $00, $02, $80, $00, $04
    #d8 $00, $01, $04, $80, $00, $08, $80, $00, $08, $40, $00, $04, $80, $00, $04, $80
    #d8 $00, $02, $00, $01, $04, $00, $01, $04, $83, $00, $C8, $6C, $00, $30, $10, $00

SPR_08_SH2:
    #d8 $E0, $70, $00, $10, $8F, $00, $10, $80, $00, $08, $00, $01, $04, $00, $01, $08
    #d8 $00, $02, $08, $00, $01, $10, $00, $01, $10, $80, $00, $08, $00, $01, $08, $00
    #d8 $01, $04, $00, $02, $08, $00, $02, $08, $06, $01, $90, $D9, $00, $60, $20, $00

SPR_08_SH3:
    #d8 $C0, $E1, $00, $20, $1E, $01, $20, $00, $01, $10, $00, $02, $08, $00, $02, $10
    #d8 $00, $04, $10, $00, $02, $20, $00, $02, $20, $00, $01, $10, $00, $02, $10, $00
    #d8 $02, $08, $00, $04, $10, $00, $04, $10, $0C, $02, $20, $B3, $01, $C0, $40, $00

SPR_08_SH4:
    #d8 $80, $C3, $01, $40, $3C, $02, $40, $00, $02, $20, $00, $04, $10, $00, $04, $20
    #d8 $00, $08, $20, $00, $04, $40, $00, $04, $40, $00, $02, $20, $00, $04, $20, $00
    #d8 $04, $10, $00, $08, $20, $00, $08, $20, $18, $04, $40, $66, $03, $80, $81, $00

SPR_08_SH5:
    #d8 $00, $87, $03, $80, $78, $04, $80, $00, $04, $40, $00, $08, $20, $00, $08, $40
    #d8 $00, $10, $40, $00, $08, $80, $00, $08, $80, $00, $04, $40, $00, $08, $40, $00
    #d8 $08, $20, $00, $10, $40, $00, $10, $40, $30, $08, $80, $CC, $06, $00, $03, $01

SPR_08_SH6:
    #d8 $00, $0E, $07, $00, $F1, $08, $00, $01, $08, $80, $00, $10, $40, $00, $10, $80
    #d8 $00, $20, $80, $00, $10, $00, $01, $10, $00, $01, $08, $80, $00, $10, $80, $00
    #d8 $10, $40, $00, $20, $80, $00, $20, $80, $60, $10, $00, $99, $0D, $00, $06, $02

SPR_08_SH7:
    #d8 $00, $1C, $0E, $00, $E2, $11, $00, $02, $10, $00, $01, $20, $80, $00, $20, $00
    #d8 $01, $40, $00, $01, $20, $00, $02, $20, $00, $02, $10, $00, $01, $20, $00, $01
    #d8 $20, $80, $00, $40, $00, $01, $40, $00, $C1, $20, $00, $32, $1B, $00, $0C, $04

SPR_09_SH0:
    #d8 $30, $00, $00, $CC, $38, $00, $02, $47, $00, $02, $40, $00, $02, $80, $00, $04
    #d8 $80, $00, $04, $40, $00, $04, $20, $00, $02, $10, $00, $02, $20, $00, $01, $40
    #d8 $00, $01, $80, $00, $02, $40, $00, $02, $30, $00, $E4, $09, $00, $1C, $06, $00

SPR_09_SH1:
    #d8 $60, $00, $00, $98, $71, $00, $04, $8E, $00, $04, $80, $00, $04, $00, $01, $08
    #d8 $00, $01, $08, $80, $00, $08, $40, $00, $04, $20, $00, $04, $40, $00, $02, $80
    #d8 $00, $02, $00, $01, $04, $80, $00, $04, $60, $00, $C8, $13, $00, $38, $0C, $00

SPR_09_SH2:
    #d8 $C0, $00, $00, $30, $E3, $00, $08, $1C, $01, $08, $00, $01, $08, $00, $02, $10
    #d8 $00, $02, $10, $00, $01, $10, $80, $00, $08, $40, $00, $08, $80, $00, $04, $00
    #d8 $01, $04, $00, $02, $08, $00, $01, $08, $C0, $00, $90, $27, $00, $70, $18, $00

SPR_09_SH3:
    #d8 $80, $01, $00, $60, $C6, $01, $10, $38, $02, $10, $00, $02, $10, $00, $04, $20
    #d8 $00, $04, $20, $00, $02, $20, $00, $01, $10, $80, $00, $10, $00, $01, $08, $00
    #d8 $02, $08, $00, $04, $10, $00, $02, $10, $80, $01, $20, $4F, $00, $E0, $30, $00

SPR_09_SH4:
    #d8 $00, $03, $00, $C0, $8C, $03, $20, $70, $04, $20, $00, $04, $20, $00, $08, $40
    #d8 $00, $08, $40, $00, $04, $40, $00, $02, $20, $00, $01, $20, $00, $02, $10, $00
    #d8 $04, $10, $00, $08, $20, $00, $04, $20, $00, $03, $40, $9E, $00, $C0, $61, $00

SPR_09_SH5:
    #d8 $00, $06, $00, $80, $19, $07, $40, $E0, $08, $40, $00, $08, $40, $00, $10, $80
    #d8 $00, $10, $80, $00, $08, $80, $00, $04, $40, $00, $02, $40, $00, $04, $20, $00
    #d8 $08, $20, $00, $10, $40, $00, $08, $40, $00, $06, $80, $3C, $01, $80, $C3, $00

SPR_09_SH6:
    #d8 $00, $0C, $00, $00, $33, $0E, $80, $C0, $11, $80, $00, $10, $80, $00, $20, $00
    #d8 $01, $20, $00, $01, $10, $00, $01, $08, $80, $00, $04, $80, $00, $08, $40, $00
    #d8 $10, $40, $00, $20, $80, $00, $10, $80, $00, $0C, $00, $79, $02, $00, $87, $01

SPR_09_SH7:
    #d8 $00, $18, $00, $00, $66, $1C, $00, $81, $23, $00, $01, $20, $00, $01, $40, $00
    #d8 $02, $40, $00, $02, $20, $00, $02, $10, $00, $01, $08, $00, $01, $10, $80, $00
    #d8 $20, $80, $00, $40, $00, $01, $20, $00, $01, $18, $00, $F2, $04, $00, $0E, $03

SPR_0A_SH0:
    #d8 $00, $00, $00, $00, $00, $00, $60, $18, $00, $98, $27, $00, $04, $20, $00, $08
    #d8 $40, $00, $08, $40, $00, $10, $20, $00, $08, $20, $00, $08, $10, $00, $04, $10
    #d8 $00, $04, $20, $00, $04, $20, $00, $E8, $18, $00, $18, $07, $00, $00, $00, $00

SPR_0A_SH1:
    #d8 $00, $00, $00, $00, $00, $00, $C0, $30, $00, $30, $4F, $00, $08, $40, $00, $10
    #d8 $80, $00, $10, $80, $00, $20, $40, $00, $10, $40, $00, $10, $20, $00, $08, $20
    #d8 $00, $08, $40, $00, $08, $40, $00, $D0, $31, $00, $30, $0E, $00, $00, $00, $00

SPR_0A_SH2:
    #d8 $00, $00, $00, $00, $00, $00, $80, $61, $00, $60, $9E, $00, $10, $80, $00, $20
    #d8 $00, $01, $20, $00, $01, $40, $80, $00, $20, $80, $00, $20, $40, $00, $10, $40
    #d8 $00, $10, $80, $00, $10, $80, $00, $A0, $63, $00, $60, $1C, $00, $00, $00, $00

SPR_0A_SH3:
    #d8 $00, $00, $00, $00, $00, $00, $00, $C3, $00, $C0, $3C, $01, $20, $00, $01, $40
    #d8 $00, $02, $40, $00, $02, $80, $00, $01, $40, $00, $01, $40, $80, $00, $20, $80
    #d8 $00, $20, $00, $01, $20, $00, $01, $40, $C7, $00, $C0, $38, $00, $00, $00, $00

SPR_0A_SH4:
    #d8 $00, $00, $00, $00, $00, $00, $00, $86, $01, $80, $79, $02, $40, $00, $02, $80
    #d8 $00, $04, $80, $00, $04, $00, $01, $02, $80, $00, $02, $80, $00, $01, $40, $00
    #d8 $01, $40, $00, $02, $40, $00, $02, $80, $8E, $01, $80, $71, $00, $00, $00, $00

SPR_0A_SH5:
    #d8 $00, $00, $00, $00, $00, $00, $00, $0C, $03, $00, $F3, $04, $80, $00, $04, $00
    #d8 $01, $08, $00, $01, $08, $00, $02, $04, $00, $01, $04, $00, $01, $02, $80, $00
    #d8 $02, $80, $00, $04, $80, $00, $04, $00, $1D, $03, $00, $E3, $00, $00, $00, $00

SPR_0A_SH6:
    #d8 $00, $00, $00, $00, $00, $00, $00, $18, $06, $00, $E6, $09, $00, $01, $08, $00
    #d8 $02, $10, $00, $02, $10, $00, $04, $08, $00, $02, $08, $00, $02, $04, $00, $01
    #d8 $04, $00, $01, $08, $00, $01, $08, $00, $3A, $06, $00, $C6, $01, $00, $00, $00

SPR_0A_SH7:
    #d8 $00, $00, $00, $00, $00, $00, $00, $30, $0C, $00, $CC, $13, $00, $02, $10, $00
    #d8 $04, $20, $00, $04, $20, $00, $08, $10, $00, $04, $10, $00, $04, $08, $00, $02
    #d8 $08, $00, $02, $10, $00, $02, $10, $00, $74, $0C, $00, $8C, $03, $00, $00, $00

SPR_0B_SH0:
    #d8 $00, $00, $00, $00, $00, $00, $20, $00, $00, $D0, $1C, $00, $10, $23, $00, $08
    #d8 $20, $00, $04, $40, $00, $04, $40, $00, $08, $30, $00, $08, $08, $00, $08, $10
    #d8 $00, $08, $10, $00, $74, $20, $00, $8C, $19, $00, $00, $06, $00, $00, $00, $00

SPR_0B_SH1:
    #d8 $00, $00, $00, $00, $00, $00, $40, $00, $00, $A0, $39, $00, $20, $46, $00, $10
    #d8 $40, $00, $08, $80, $00, $08, $80, $00, $10, $60, $00, $10, $10, $00, $10, $20
    #d8 $00, $10, $20, $00, $E8, $40, $00, $18, $33, $00, $00, $0C, $00, $00, $00, $00

SPR_0B_SH2:
    #d8 $00, $00, $00, $00, $00, $00, $80, $00, $00, $40, $73, $00, $40, $8C, $00, $20
    #d8 $80, $00, $10, $00, $01, $10, $00, $01, $20, $C0, $00, $20, $20, $00, $20, $40
    #d8 $00, $20, $40, $00, $D0, $81, $00, $30, $66, $00, $00, $18, $00, $00, $00, $00

SPR_0B_SH3:
    #d8 $00, $00, $00, $00, $00, $00, $00, $01, $00, $80, $E6, $00, $80, $18, $01, $40
    #d8 $00, $01, $20, $00, $02, $20, $00, $02, $40, $80, $01, $40, $40, $00, $40, $80
    #d8 $00, $40, $80, $00, $A0, $03, $01, $60, $CC, $00, $00, $30, $00, $00, $00, $00

SPR_0B_SH4:
    #d8 $00, $00, $00, $00, $00, $00, $00, $02, $00, $00, $CD, $01, $00, $31, $02, $80
    #d8 $00, $02, $40, $00, $04, $40, $00, $04, $80, $00, $03, $80, $80, $00, $80, $00
    #d8 $01, $80, $00, $01, $40, $07, $02, $C0, $98, $01, $00, $60, $00, $00, $00, $00

SPR_0B_SH5:
    #d8 $00, $00, $00, $00, $00, $00, $00, $04, $00, $00, $9A, $03, $00, $62, $04, $00
    #d8 $01, $04, $80, $00, $08, $80, $00, $08, $00, $01, $06, $00, $01, $01, $00, $01
    #d8 $02, $00, $01, $02, $80, $0E, $04, $80, $31, $03, $00, $C0, $00, $00, $00, $00

SPR_0B_SH6:
    #d8 $00, $00, $00, $00, $00, $00, $00, $08, $00, $00, $34, $07, $00, $C4, $08, $00
    #d8 $02, $08, $00, $01, $10, $00, $01, $10, $00, $02, $0C, $00, $02, $02, $00, $02
    #d8 $04, $00, $02, $04, $00, $1D, $08, $00, $63, $06, $00, $80, $01, $00, $00, $00

SPR_0B_SH7:
    #d8 $00, $00, $00, $00, $00, $00, $00, $10, $00, $00, $68, $0E, $00, $88, $11, $00
    #d8 $04, $10, $00, $02, $20, $00, $02, $20, $00, $04, $18, $00, $04, $04, $00, $04
    #d8 $08, $00, $04, $08, $00, $3A, $10, $00, $C6, $0C, $00, $00, $03, $00, $00, $00

SPR_0C_SH0:
    #d8 $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $E0, $0C, $00, $10
    #d8 $13, $00, $10, $10, $00, $20, $20, $00, $20, $10, $00, $10, $08, $00, $10, $10
    #d8 $00, $A0, $19, $00, $60, $06, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00

SPR_0C_SH1:
    #d8 $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $C0, $19, $00, $20
    #d8 $26, $00, $20, $20, $00, $40, $40, $00, $40, $20, $00, $20, $10, $00, $20, $20
    #d8 $00, $40, $33, $00, $C0, $0C, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00

SPR_0C_SH2:
    #d8 $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $80, $33, $00, $40
    #d8 $4C, $00, $40, $40, $00, $80, $80, $00, $80, $40, $00, $40, $20, $00, $40, $40
    #d8 $00, $80, $66, $00, $80, $19, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00

SPR_0C_SH3:
    #d8 $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $67, $00, $80
    #d8 $98, $00, $80, $80, $00, $00, $01, $01, $00, $81, $00, $80, $40, $00, $80, $80
    #d8 $00, $00, $CD, $00, $00, $33, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00

SPR_0C_SH4:
    #d8 $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $CE, $00, $00
    #d8 $31, $01, $00, $01, $01, $00, $02, $02, $00, $02, $01, $00, $81, $00, $00, $01
    #d8 $01, $00, $9A, $01, $00, $66, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00

SPR_0C_SH5:
    #d8 $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $9C, $01, $00
    #d8 $62, $02, $00, $02, $02, $00, $04, $04, $00, $04, $02, $00, $02, $01, $00, $02
    #d8 $02, $00, $34, $03, $00, $CC, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00

SPR_0C_SH6:
    #d8 $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $38, $03, $00
    #d8 $C4, $04, $00, $04, $04, $00, $08, $08, $00, $08, $04, $00, $04, $02, $00, $04
    #d8 $04, $00, $68, $06, $00, $98, $01, $00, $00, $00, $00, $00, $00, $00, $00, $00

SPR_0C_SH7:
    #d8 $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $70, $06, $00
    #d8 $88, $09, $00, $08, $08, $00, $10, $10, $00, $10, $08, $00, $08, $04, $00, $08
    #d8 $08, $00, $D0, $0C, $00, $30, $03, $00, $00, $00, $00, $00, $00, $00, $00, $00

SPR_0D_SH0:
    #d8 $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $C0, $03, $00, $40
    #d8 $0C, $00, $20, $10, $00, $20, $08, $00, $20, $08, $00, $10, $10, $00, $10, $10
    #d8 $00, $A0, $0D, $00, $60, $02, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00

SPR_0D_SH1:
    #d8 $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $80, $07, $00, $80
    #d8 $18, $00, $40, $20, $00, $40, $10, $00, $40, $10, $00, $20, $20, $00, $20, $20
    #d8 $00, $40, $1B, $00, $C0, $04, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00

SPR_0D_SH2:
    #d8 $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $0F, $00, $00
    #d8 $31, $00, $80, $40, $00, $80, $20, $00, $80, $20, $00, $40, $40, $00, $40, $40
    #d8 $00, $80, $36, $00, $80, $09, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00

SPR_0D_SH3:
    #d8 $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $1E, $00, $00
    #d8 $62, $00, $00, $81, $00, $00, $41, $00, $00, $41, $00, $80, $80, $00, $80, $80
    #d8 $00, $00, $6D, $00, $00, $13, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00

SPR_0D_SH4:
    #d8 $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $3C, $00, $00
    #d8 $C4, $00, $00, $02, $01, $00, $82, $00, $00, $82, $00, $00, $01, $01, $00, $01
    #d8 $01, $00, $DA, $00, $00, $26, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00

SPR_0D_SH5:
    #d8 $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $78, $00, $00
    #d8 $88, $01, $00, $04, $02, $00, $04, $01, $00, $04, $01, $00, $02, $02, $00, $02
    #d8 $02, $00, $B4, $01, $00, $4C, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00

SPR_0D_SH6:
    #d8 $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $F0, $00, $00
    #d8 $10, $03, $00, $08, $04, $00, $08, $02, $00, $08, $02, $00, $04, $04, $00, $04
    #d8 $04, $00, $68, $03, $00, $98, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00

SPR_0D_SH7:
    #d8 $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $E0, $01, $00
    #d8 $20, $06, $00, $10, $08, $00, $10, $04, $00, $10, $04, $00, $08, $08, $00, $08
    #d8 $08, $00, $D0, $06, $00, $30, $01, $00, $00, $00, $00, $00, $00, $00, $00, $00

SPR_0E_SH0:
    #d8 $03, $00, $00, $03, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    #d8 $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    #d8 $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00

SPR_0E_SH1:
    #d8 $06, $00, $00, $06, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    #d8 $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    #d8 $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00

SPR_0E_SH2:
    #d8 $0C, $00, $00, $0C, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    #d8 $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    #d8 $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00

SPR_0E_SH3:
    #d8 $18, $00, $00, $18, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    #d8 $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    #d8 $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00

SPR_0E_SH4:
    #d8 $30, $00, $00, $30, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    #d8 $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    #d8 $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00

SPR_0E_SH5:
    #d8 $60, $00, $00, $60, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    #d8 $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    #d8 $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00

SPR_0E_SH6:
    #d8 $C0, $00, $00, $C0, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    #d8 $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    #d8 $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00

SPR_0E_SH7:
    #d8 $80, $01, $00, $80, $01, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    #d8 $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    #d8 $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00

SPR_0F_SH0:
    #d8 $80, $00, $00, $00, $00, $00, $04, $20, $00, $80, $00, $00, $10, $08, $00, $00
    #d8 $00, $00, $00, $00, $00, $09, $90, $00, $00, $00, $00, $00, $00, $00, $00, $00
    #d8 $00, $10, $08, $00, $80, $00, $00, $04, $20, $00, $00, $00, $00, $80, $00, $00

SPR_0F_SH1:
    #d8 $00, $01, $00, $00, $00, $00, $08, $40, $00, $00, $01, $00, $20, $10, $00, $00
    #d8 $00, $00, $00, $00, $00, $12, $20, $01, $00, $00, $00, $00, $00, $00, $00, $00
    #d8 $00, $20, $10, $00, $00, $01, $00, $08, $40, $00, $00, $00, $00, $00, $01, $00

SPR_0F_SH2:
    #d8 $00, $02, $00, $00, $00, $00, $10, $80, $00, $00, $02, $00, $40, $20, $00, $00
    #d8 $00, $00, $00, $00, $00, $24, $40, $02, $00, $00, $00, $00, $00, $00, $00, $00
    #d8 $00, $40, $20, $00, $00, $02, $00, $10, $80, $00, $00, $00, $00, $00, $02, $00

SPR_0F_SH3:
    #d8 $00, $04, $00, $00, $00, $00, $20, $00, $01, $00, $04, $00, $80, $40, $00, $00
    #d8 $00, $00, $00, $00, $00, $48, $80, $04, $00, $00, $00, $00, $00, $00, $00, $00
    #d8 $00, $80, $40, $00, $00, $04, $00, $20, $00, $01, $00, $00, $00, $00, $04, $00

SPR_0F_SH4:
    #d8 $00, $08, $00, $00, $00, $00, $40, $00, $02, $00, $08, $00, $00, $81, $00, $00
    #d8 $00, $00, $00, $00, $00, $90, $00, $09, $00, $00, $00, $00, $00, $00, $00, $00
    #d8 $00, $00, $81, $00, $00, $08, $00, $40, $00, $02, $00, $00, $00, $00, $08, $00

SPR_0F_SH5:
    #d8 $00, $10, $00, $00, $00, $00, $80, $00, $04, $00, $10, $00, $00, $02, $01, $00
    #d8 $00, $00, $00, $00, $00, $20, $01, $12, $00, $00, $00, $00, $00, $00, $00, $00
    #d8 $00, $00, $02, $01, $00, $10, $00, $80, $00, $04, $00, $00, $00, $00, $10, $00

SPR_0F_SH6:
    #d8 $00, $20, $00, $00, $00, $00, $00, $01, $08, $00, $20, $00, $00, $04, $02, $00
    #d8 $00, $00, $00, $00, $00, $40, $02, $24, $00, $00, $00, $00, $00, $00, $00, $00
    #d8 $00, $00, $04, $02, $00, $20, $00, $00, $01, $08, $00, $00, $00, $00, $20, $00

SPR_0F_SH7:
    #d8 $00, $40, $00, $00, $00, $00, $00, $02, $10, $00, $40, $00, $00, $08, $04, $00
    #d8 $00, $00, $00, $00, $00, $80, $04, $48, $00, $00, $00, $00, $00, $00, $00, $00
    #d8 $00, $00, $08, $04, $00, $40, $00, $00, $02, $10, $00, $00, $00, $00, $40, $00


#addr 0xEFFD
    JMP GAME_START
