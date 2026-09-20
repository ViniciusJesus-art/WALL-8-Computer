#include "../wall8.cpu"

; ============================================================================
; WALL-8 - PAC-MAN STYLE GAME
; ============================================================================
;
; Cartucho:  $A000-$EFFF (20 KiB)
; Video:     grafico monocromatico 320x240
; Maze:      28 x 31 tiles
; Tile:      8 x 7 pixels
; Offset:    X=6 bytes (48 px), Y=20 px
;
; Recursos:
;   - labirinto estilo classico;
;   - pellets e 4 power-pellets;
;   - score de 3 digitos na propria tela;
;   - 3 vidas;
;   - Pac-Man animado e orientado em 4 direcoes;
;   - 4 fantasmas com perseguicao simples;
;   - modo POWER: fantasmas mudam de sprite e podem ser comidos;
;   - tunel lateral;
;   - sons de READY, chomp, power, fantasma comido e game over;
;   - pausa, restart e retorno para BIOS.
;
; Controles:
;   W / w = cima
;   A / a = esquerda
;   S / s = baixo
;   D / d = direita
;   P / p = pausa
;   R / r = reiniciar
;   Q / q = sair para BIOS
;
; A BIOS deve entrar com CALL $A000. O cartucho nao reinicializa SP.
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


; ============================================================================
; VIDEO / STATUS
; ============================================================================

VIDEO_CLEAR          = $00
MODE_TEXT_40X30      = $11
MODE_GFX_320X240     = $12

VIDEO_BUSY_MASK      = $01
VIDEO_FRAME_MASK     = $08
KEY_READY_MASK       = $80

MAP_WIDTH            = $1C      ; 28
MAP_HEIGHT           = $1F      ; 31
MAP_X_OFFSET         = $06      ; 6 bytes = 48 pixels
MAP_Y_OFFSET         = $14      ; 20 pixels

TILE_EMPTY           = $00
TILE_DOT             = $01
TILE_POWER           = $02
TILE_WALL_MASK       = $10

DIR_UP               = $00
DIR_RIGHT            = $01
DIR_DOWN             = $02
DIR_LEFT             = $03

PLAYER_DELAY         = $05

NOTE_C5              = $02
NOTE_B4              = $06
NOTE_A4              = $0A
NOTE_G4              = $0E
NOTE_F4              = $12
NOTE_E4              = $16
NOTE_D4              = $1A
NOTE_C4              = $1E

SILENCE              = $00

MAP_RAM              = $0800


; ============================================================================
; RAM DE ESTADO
; ============================================================================

PLAYER_X          = $0200
PLAYER_Y          = $0201
DIR_CURRENT       = $0202
DIR_NEXT          = $0203

NEXT_X            = $0204
NEXT_Y            = $0205
MOVE_X            = $0206
MOVE_Y            = $0207
MOVE_DIR          = $0208
MOVE_VALID        = $0209
MOVE_OK           = $020A

TARGET_X          = $020B
TARGET_Y          = $020C
MAP_VALUE         = $020D

DRAW_SCREEN_X     = $020E
DRAW_PIXEL_Y      = $020F
DRAW_VALUE        = $0210
DRAW_ROWS         = $0211
LOOP_COUNT        = $0212

LAST_FRAME        = $0213
MOVE_ACCUM        = $0214
ANIM_FRAME        = $0215
CHOMP_TOGGLE      = $0216

SCORE_HUNDREDS    = $0217
SCORE_TENS        = $0218
SCORE_ONES        = $0219
DIGIT_VALUE       = $021A
LIVES             = $021B

POWER_TIMER       = $021C
SOUND_FRAMES      = $021D
GHOST_PHASE       = $021E

PAUSED_FLAG       = $021F
RESTART_FLAG      = $0220
EXIT_FLAG         = $0221
GAME_OVER_FLAG    = $0222
RESPAWN_FLAG      = $0223

G1_X              = $0224
G1_Y              = $0225
G2_X              = $0226
G2_Y              = $0227
G3_X              = $0228
G3_Y              = $0229
G4_X              = $022A
G4_Y              = $022B

GHOST_X_TMP       = $022C
GHOST_Y_TMP       = $022D
GHOST_ID          = $022E
COLLIDED_GHOST    = $022F

CHAR_VALUE        = $0230


; ============================================================================
; ENTRADA
; ============================================================================

INICIO:
GAME_START:

    ; A BIOS entrou com CALL $A000: nao alterar SP.

    CALL VIDEO_WAIT

    STI SOUND_CFG,     #SILENCE
    STI SOUND_FRAMES,  #$00
    STI POWER_TIMER,   #$00
    STI PAUSED_FLAG,   #$00
    STI RESTART_FLAG,  #$00
    STI EXIT_FLAG,     #$00
    STI GAME_OVER_FLAG, #$00
    STI RESPAWN_FLAG,  #$00
    STI MOVE_ACCUM,    #$00
    STI ANIM_FRAME,    #$01
    STI CHOMP_TOGGLE,  #$00
    STI GHOST_PHASE,   #$00

    STI SCORE_HUNDREDS, #$00
    STI SCORE_TENS,    #$00
    STI SCORE_ONES,    #$00
    STI LIVES,         #$03

    STI DISPLAY_LOW,   #$00
    STI DISPLAY_HIGH,  #$00

    ; 320x240 monocromatico.
    STI VIDEO_CMD, #MODE_GFX_320X240
    CALL VIDEO_WAIT

    STI VIDEO_CMD, #VIDEO_CLEAR
    CALL VIDEO_WAIT

    ; Constroi o mapa mutavel na RAM.
    CALL INIT_MAP_RAM

    ; Desenha labirinto, pellets e HUD.
    CALL DRAW_FULL_MAZE
    CALL DRAW_SCORE_LABEL
    CALL DRAW_SCORE
    CALL DRAW_LIVES

    CALL RESET_ENTITY_POSITIONS
    CALL DRAW_ALL_ENTITIES

    CALL READY_JINGLE
    CALL SYNC_FRAME_STATE


; ============================================================================
; LOOP PRINCIPAL
; ============================================================================

MAIN_LOOP:

    CALL WAIT_ONE_FRAME

    CALL SERVICE_SOUND

    LDA EXIT_FLAG
    CMP A, #$01
    JZ EXIT_GAME

    LDA RESTART_FLAG
    CMP A, #$01
    JZ GAME_START

    LDA PAUSED_FLAG
    CMP A, #$01
    JZ MAIN_LOOP

    CALL SERVICE_POWER

    ; Movimento do jogador a cada PLAYER_DELAY quadros.
    LDA MOVE_ACCUM
    INC A
    STA MOVE_ACCUM

    CMP A, #PLAYER_DELAY
    JNZ MAIN_LOOP

    STI MOVE_ACCUM, #$00

    CALL PLAYER_STEP

    LDA GAME_OVER_FLAG
    CMP A, #$01
    JZ GAME_OVER

    LDA RESPAWN_FLAG
    CMP A, #$01
    JZ MAIN_CLEAR_RESPAWN

    ; Fantasmas se movem a metade da velocidade do jogador:
    ; um par por passo, alternando.
    LDA GHOST_PHASE
    XOR A, #$01
    STA GHOST_PHASE

    CMP A, #$00
    JZ MOVE_GHOST_PAIR_A

MOVE_GHOST_PAIR_B:

    CALL MOVE_GHOST_2
    CALL MOVE_GHOST_4
    JMP GHOST_PAIR_DONE

MOVE_GHOST_PAIR_A:

    CALL MOVE_GHOST_1
    CALL MOVE_GHOST_3

GHOST_PAIR_DONE:

    CALL CHECK_COLLISIONS

    LDA GAME_OVER_FLAG
    CMP A, #$01
    JZ GAME_OVER

    LDA RESPAWN_FLAG
    CMP A, #$01
    JZ MAIN_CLEAR_RESPAWN

    JMP MAIN_LOOP


MAIN_CLEAR_RESPAWN:

    STI RESPAWN_FLAG, #$00
    JMP MAIN_LOOP


; ============================================================================
; PASSO DO JOGADOR
; ============================================================================

PLAYER_STEP:

    ; Tenta aceitar a direcao solicitada imediatamente.
    LDA PLAYER_X
    STA MOVE_X
    LDA PLAYER_Y
    STA MOVE_Y
    LDA DIR_NEXT
    STA MOVE_DIR

    CALL COMPUTE_MOVE_TARGET
    CALL CHECK_NEXT_WALKABLE

    LDA MOVE_OK
    CMP A, #$01
    JNZ PLAYER_KEEP_DIRECTION

    LDA DIR_NEXT
    STA DIR_CURRENT


PLAYER_KEEP_DIRECTION:

    ; Calcula a casa seguinte na direcao atual.
    LDA PLAYER_X
    STA MOVE_X
    LDA PLAYER_Y
    STA MOVE_Y
    LDA DIR_CURRENT
    STA MOVE_DIR

    CALL COMPUTE_MOVE_TARGET
    CALL CHECK_NEXT_WALKABLE

    LDA MOVE_OK
    CMP A, #$01
    JNZ PLAYER_STEP_DONE

    ; Apaga o sprite antigo restaurando o tile que existe na RAM.
    LDA PLAYER_X
    STA TARGET_X
    LDA PLAYER_Y
    STA TARGET_Y
    CALL DRAW_MAP_TILE_XY

    ; Move.
    LDA NEXT_X
    STA PLAYER_X
    LDA NEXT_Y
    STA PLAYER_Y

    ; Consome pellet/power-pellet, se houver.
    CALL CONSUME_PLAYER_TILE

    ; Alterna boca aberta/fechada.
    LDA ANIM_FRAME
    XOR A, #$01
    STA ANIM_FRAME

    CALL DRAW_PLAYER
    CALL CHECK_COLLISIONS


PLAYER_STEP_DONE:

    RET


; ============================================================================
; MOVIMENTO GENERICO EM GRADE
;
; Entrada:
;   MOVE_X, MOVE_Y, MOVE_DIR
;
; Saida:
;   NEXT_X, NEXT_Y
;   MOVE_VALID = 1 se a coordenada e valida
;
; O tunel lateral faz wrap X=0 <-> X=27.
; ============================================================================

COMPUTE_MOVE_TARGET:

    LDA MOVE_X
    STA NEXT_X

    LDA MOVE_Y
    STA NEXT_Y

    STI MOVE_VALID, #$01

    LDA MOVE_DIR

    CMP A, #DIR_UP
    JZ MOVE_TARGET_UP

    CMP A, #DIR_RIGHT
    JZ MOVE_TARGET_RIGHT

    CMP A, #DIR_DOWN
    JZ MOVE_TARGET_DOWN

    ; LEFT
MOVE_TARGET_LEFT:

    LDA MOVE_X
    CMP A, #$00
    JZ MOVE_TARGET_LEFT_WRAP

    DEC A
    STA NEXT_X
    RET


MOVE_TARGET_LEFT_WRAP:

    STI NEXT_X, #$1B
    RET


MOVE_TARGET_RIGHT:

    LDA MOVE_X
    CMP A, #$1B
    JZ MOVE_TARGET_RIGHT_WRAP

    INC A
    STA NEXT_X
    RET


MOVE_TARGET_RIGHT_WRAP:

    STI NEXT_X, #$00
    RET


MOVE_TARGET_UP:

    LDA MOVE_Y
    CMP A, #$00
    JZ MOVE_TARGET_INVALID

    DEC A
    STA NEXT_Y
    RET


MOVE_TARGET_DOWN:

    LDA MOVE_Y
    CMP A, #$1E
    JZ MOVE_TARGET_INVALID

    INC A
    STA NEXT_Y
    RET


MOVE_TARGET_INVALID:

    STI MOVE_VALID, #$00
    RET


CHECK_NEXT_WALKABLE:

    STI MOVE_OK, #$00

    LDA MOVE_VALID
    CMP A, #$01
    JNZ NEXT_NOT_WALKABLE

    LDA NEXT_X
    STA TARGET_X

    LDA NEXT_Y
    STA TARGET_Y

    CALL MAP_GET_TARGET

    ; Parede possui high nibble = 1.
    AND A, #$F0
    CMP A, #$10
    JZ NEXT_NOT_WALKABLE

    STI MOVE_OK, #$01


NEXT_NOT_WALKABLE:

    RET


; ============================================================================
; PELLETS / SCORE / POWER
; ============================================================================

CONSUME_PLAYER_TILE:

    LDA PLAYER_X
    STA TARGET_X
    LDA PLAYER_Y
    STA TARGET_Y

    CALL MAP_POINT
    LDA [PTR]
    STA MAP_VALUE

    CMP A, #TILE_DOT
    JZ PLAYER_ATE_DOT

    CMP A, #TILE_POWER
    JZ PLAYER_ATE_POWER

    RET


PLAYER_ATE_DOT:

    ; Remove da RAM para nunca reaparecer.
    LDA #TILE_EMPTY
    STA [PTR]

    CALL SCORE_ADD_ONE
    CALL DRAW_SCORE
    CALL PLAY_CHOMP

    RET


PLAYER_ATE_POWER:

    LDA #TILE_EMPTY
    STA [PTR]

    ; 5 pontos.
    CALL SCORE_ADD_ONE
    CALL SCORE_ADD_ONE
    CALL SCORE_ADD_ONE
    CALL SCORE_ADD_ONE
    CALL SCORE_ADD_ONE
    CALL DRAW_SCORE

    ; ~4 segundos a 60 Hz.
    STI POWER_TIMER, #$F0

    ; Tone + noise.
    STI SOUND_CFG,    #$A3
    STI SOUND_FRAMES, #$08

    ; Atualiza imediatamente o visual dos fantasmas.
    CALL DRAW_ALL_GHOSTS

    RET


SCORE_ADD_ONE:

    LDA SCORE_ONES
    INC A
    CMP A, #$0A
    JNZ SCORE_STORE_ONES

    STI SCORE_ONES, #$00

    LDA SCORE_TENS
    INC A
    CMP A, #$0A
    JNZ SCORE_STORE_TENS

    STI SCORE_TENS, #$00

    LDA SCORE_HUNDREDS
    INC A
    CMP A, #$0A
    JNZ SCORE_STORE_HUNDREDS

    STI SCORE_HUNDREDS, #$00
    RET


SCORE_STORE_HUNDREDS:

    STA SCORE_HUNDREDS
    RET


SCORE_STORE_TENS:

    STA SCORE_TENS
    RET


SCORE_STORE_ONES:

    STA SCORE_ONES
    RET


; ============================================================================
; FANTASMAS
; ============================================================================

MOVE_GHOST_1:

    LDA G1_X
    STA GHOST_X_TMP
    LDA G1_Y
    STA GHOST_Y_TMP
    STI GHOST_ID, #$00

    CALL MOVE_GHOST_GENERIC

    LDA GHOST_X_TMP
    STA G1_X
    LDA GHOST_Y_TMP
    STA G1_Y
    RET


MOVE_GHOST_2:

    LDA G2_X
    STA GHOST_X_TMP
    LDA G2_Y
    STA GHOST_Y_TMP
    STI GHOST_ID, #$01

    CALL MOVE_GHOST_GENERIC

    LDA GHOST_X_TMP
    STA G2_X
    LDA GHOST_Y_TMP
    STA G2_Y
    RET


MOVE_GHOST_3:

    LDA G3_X
    STA GHOST_X_TMP
    LDA G3_Y
    STA GHOST_Y_TMP
    STI GHOST_ID, #$02

    CALL MOVE_GHOST_GENERIC

    LDA GHOST_X_TMP
    STA G3_X
    LDA GHOST_Y_TMP
    STA G3_Y
    RET


MOVE_GHOST_4:

    LDA G4_X
    STA GHOST_X_TMP
    LDA G4_Y
    STA GHOST_Y_TMP
    STI GHOST_ID, #$03

    CALL MOVE_GHOST_GENERIC

    LDA GHOST_X_TMP
    STA G4_X
    LDA GHOST_Y_TMP
    STA G4_Y
    RET


MOVE_GHOST_GENERIC:

    CALL GHOST_CHOOSE_MOVE

    LDA MOVE_OK
    CMP A, #$01
    JNZ GHOST_MOVE_DONE

    ; Restaura fundo da casa antiga.
    LDA GHOST_X_TMP
    STA TARGET_X
    LDA GHOST_Y_TMP
    STA TARGET_Y
    CALL DRAW_MAP_TILE_XY

    ; Aplica movimento escolhido.
    LDA NEXT_X
    STA GHOST_X_TMP
    LDA NEXT_Y
    STA GHOST_Y_TMP

    CALL DRAW_GHOST_TEMP


GHOST_MOVE_DONE:

    RET


; IDs pares tentam horizontal primeiro.
; IDs impares tentam vertical primeiro.
GHOST_CHOOSE_MOVE:

    STI MOVE_OK, #$00

    LDA GHOST_ID
    TEST A, #$01
    JNZ GHOST_VERTICAL_FIRST


GHOST_HORIZONTAL_FIRST:

    CALL GHOST_TRY_HORIZONTAL

    LDA MOVE_OK
    CMP A, #$01
    JZ GHOST_CHOICE_DONE

    CALL GHOST_TRY_VERTICAL

    LDA MOVE_OK
    CMP A, #$01
    JZ GHOST_CHOICE_DONE

    CALL GHOST_FALLBACK
    RET


GHOST_VERTICAL_FIRST:

    CALL GHOST_TRY_VERTICAL

    LDA MOVE_OK
    CMP A, #$01
    JZ GHOST_CHOICE_DONE

    CALL GHOST_TRY_HORIZONTAL

    LDA MOVE_OK
    CMP A, #$01
    JZ GHOST_CHOICE_DONE

    CALL GHOST_FALLBACK


GHOST_CHOICE_DONE:

    RET


GHOST_TRY_HORIZONTAL:

    LDA GHOST_X_TMP
    LDB PLAYER_X
    CMP A, B
    JZ GHOST_HORIZONTAL_NONE

    ; Como coordenadas < 128, N=1 aqui representa GHOST_X < PLAYER_X.
    JN GHOST_WANTS_RIGHT

    STI MOVE_DIR, #DIR_LEFT
    JMP GHOST_TEST_DIR


GHOST_WANTS_RIGHT:

    STI MOVE_DIR, #DIR_RIGHT
    JMP GHOST_TEST_DIR


GHOST_HORIZONTAL_NONE:

    STI MOVE_OK, #$00
    RET


GHOST_TRY_VERTICAL:

    LDA GHOST_Y_TMP
    LDB PLAYER_Y
    CMP A, B
    JZ GHOST_VERTICAL_NONE

    JN GHOST_WANTS_DOWN

    STI MOVE_DIR, #DIR_UP
    JMP GHOST_TEST_DIR


GHOST_WANTS_DOWN:

    STI MOVE_DIR, #DIR_DOWN
    JMP GHOST_TEST_DIR


GHOST_VERTICAL_NONE:

    STI MOVE_OK, #$00
    RET


GHOST_TEST_DIR:

    LDA GHOST_X_TMP
    STA MOVE_X
    LDA GHOST_Y_TMP
    STA MOVE_Y

    CALL COMPUTE_MOVE_TARGET
    CALL CHECK_NEXT_WALKABLE
    RET


; Fallback com ordens diferentes para os 4 fantasmas.
GHOST_FALLBACK:

    LDA GHOST_ID

    CMP A, #$00
    JZ GHOST_FALLBACK_0

    CMP A, #$01
    JZ GHOST_FALLBACK_1

    CMP A, #$02
    JZ GHOST_FALLBACK_2

    JMP GHOST_FALLBACK_3


GHOST_FALLBACK_0:

    STI MOVE_DIR, #DIR_UP
    CALL GHOST_TEST_DIR
    LDA MOVE_OK
    CMP A, #$01
    JZ GHOST_FALLBACK_DONE

    STI MOVE_DIR, #DIR_RIGHT
    CALL GHOST_TEST_DIR
    LDA MOVE_OK
    CMP A, #$01
    JZ GHOST_FALLBACK_DONE

    STI MOVE_DIR, #DIR_DOWN
    CALL GHOST_TEST_DIR
    LDA MOVE_OK
    CMP A, #$01
    JZ GHOST_FALLBACK_DONE

    STI MOVE_DIR, #DIR_LEFT
    CALL GHOST_TEST_DIR
    RET


GHOST_FALLBACK_1:

    STI MOVE_DIR, #DIR_LEFT
    CALL GHOST_TEST_DIR
    LDA MOVE_OK
    CMP A, #$01
    JZ GHOST_FALLBACK_DONE

    STI MOVE_DIR, #DIR_DOWN
    CALL GHOST_TEST_DIR
    LDA MOVE_OK
    CMP A, #$01
    JZ GHOST_FALLBACK_DONE

    STI MOVE_DIR, #DIR_RIGHT
    CALL GHOST_TEST_DIR
    LDA MOVE_OK
    CMP A, #$01
    JZ GHOST_FALLBACK_DONE

    STI MOVE_DIR, #DIR_UP
    CALL GHOST_TEST_DIR
    RET


GHOST_FALLBACK_2:

    STI MOVE_DIR, #DIR_DOWN
    CALL GHOST_TEST_DIR
    LDA MOVE_OK
    CMP A, #$01
    JZ GHOST_FALLBACK_DONE

    STI MOVE_DIR, #DIR_LEFT
    CALL GHOST_TEST_DIR
    LDA MOVE_OK
    CMP A, #$01
    JZ GHOST_FALLBACK_DONE

    STI MOVE_DIR, #DIR_UP
    CALL GHOST_TEST_DIR
    LDA MOVE_OK
    CMP A, #$01
    JZ GHOST_FALLBACK_DONE

    STI MOVE_DIR, #DIR_RIGHT
    CALL GHOST_TEST_DIR
    RET


GHOST_FALLBACK_3:

    STI MOVE_DIR, #DIR_RIGHT
    CALL GHOST_TEST_DIR
    LDA MOVE_OK
    CMP A, #$01
    JZ GHOST_FALLBACK_DONE

    STI MOVE_DIR, #DIR_UP
    CALL GHOST_TEST_DIR
    LDA MOVE_OK
    CMP A, #$01
    JZ GHOST_FALLBACK_DONE

    STI MOVE_DIR, #DIR_LEFT
    CALL GHOST_TEST_DIR
    LDA MOVE_OK
    CMP A, #$01
    JZ GHOST_FALLBACK_DONE

    STI MOVE_DIR, #DIR_DOWN
    CALL GHOST_TEST_DIR


GHOST_FALLBACK_DONE:

    RET


; ============================================================================
; COLISAO COM FANTASMAS
; ============================================================================

CHECK_COLLISIONS:

    LDA PLAYER_X
    LDB G1_X
    CMP A, B
    JNZ CHECK_GHOST_2

    LDA PLAYER_Y
    LDB G1_Y
    CMP A, B
    JNZ CHECK_GHOST_2

    STI COLLIDED_GHOST, #$00
    CALL HANDLE_PLAYER_GHOST_COLLISION

    LDA RESPAWN_FLAG
    CMP A, #$01
    JZ COLLISION_CHECK_DONE


CHECK_GHOST_2:

    LDA PLAYER_X
    LDB G2_X
    CMP A, B
    JNZ CHECK_GHOST_3

    LDA PLAYER_Y
    LDB G2_Y
    CMP A, B
    JNZ CHECK_GHOST_3

    STI COLLIDED_GHOST, #$01
    CALL HANDLE_PLAYER_GHOST_COLLISION

    LDA RESPAWN_FLAG
    CMP A, #$01
    JZ COLLISION_CHECK_DONE


CHECK_GHOST_3:

    LDA PLAYER_X
    LDB G3_X
    CMP A, B
    JNZ CHECK_GHOST_4

    LDA PLAYER_Y
    LDB G3_Y
    CMP A, B
    JNZ CHECK_GHOST_4

    STI COLLIDED_GHOST, #$02
    CALL HANDLE_PLAYER_GHOST_COLLISION

    LDA RESPAWN_FLAG
    CMP A, #$01
    JZ COLLISION_CHECK_DONE


CHECK_GHOST_4:

    LDA PLAYER_X
    LDB G4_X
    CMP A, B
    JNZ COLLISION_CHECK_DONE

    LDA PLAYER_Y
    LDB G4_Y
    CMP A, B
    JNZ COLLISION_CHECK_DONE

    STI COLLIDED_GHOST, #$03
    CALL HANDLE_PLAYER_GHOST_COLLISION


COLLISION_CHECK_DONE:

    RET


HANDLE_PLAYER_GHOST_COLLISION:

    LDA POWER_TIMER
    CMP A, #$00
    JNZ EAT_GHOST

    CALL PLAYER_DIED
    RET


EAT_GHOST:

    ; Restaura o Pac-Man sobre a casa da colisao.
    CALL DRAW_PLAYER

    ; 5 pontos extras.
    CALL SCORE_ADD_ONE
    CALL SCORE_ADD_ONE
    CALL SCORE_ADD_ONE
    CALL SCORE_ADD_ONE
    CALL SCORE_ADD_ONE
    CALL DRAW_SCORE

    ; Reposiciona somente o fantasma atingido.
    LDA COLLIDED_GHOST
    STA GHOST_ID

    CALL SET_GHOST_TEMP_TO_SPAWN
    CALL STORE_GHOST_TEMP_BY_ID
    CALL DRAW_GHOST_TEMP

    ; Efeito agudo + ruido curto.
    STI SOUND_CFG,    #$03
    STI SOUND_FRAMES, #$06

    RET


PLAYER_DIED:

    STI SOUND_CFG,    #SILENCE
    STI SOUND_FRAMES, #$00
    STI POWER_TIMER,  #$00

    CALL DEATH_SOUND
    CALL ERASE_ALL_ENTITIES

    LDA LIVES
    DEC A
    STA LIVES

    CALL DRAW_LIVES

    LDA LIVES
    CMP A, #$00
    JZ PLAYER_NO_LIVES

    CALL RESET_ENTITY_POSITIONS
    CALL DRAW_ALL_ENTITIES

    STI MOVE_ACCUM,   #$00
    STI RESPAWN_FLAG, #$01

    CALL READY_JINGLE
    CALL SYNC_FRAME_STATE

    RET


PLAYER_NO_LIVES:

    STI GAME_OVER_FLAG, #$01
    RET


; ============================================================================
; POSICOES / ENTIDADES
; ============================================================================

RESET_ENTITY_POSITIONS:

    ; Jogador.
    STI PLAYER_X,    #$0D
    STI PLAYER_Y,    #$16
    STI DIR_CURRENT, #DIR_LEFT
    STI DIR_NEXT,    #DIR_LEFT
    STI ANIM_FRAME,  #$01

    ; Fantasmas.
    STI G1_X, #$0D
    STI G1_Y, #$0B

    STI G2_X, #$0E
    STI G2_Y, #$0B

    STI G3_X, #$0C
    STI G3_Y, #$11

    STI G4_X, #$0F
    STI G4_Y, #$11

    RET


SET_GHOST_TEMP_TO_SPAWN:

    LDA GHOST_ID

    CMP A, #$00
    JZ GHOST_SPAWN_1

    CMP A, #$01
    JZ GHOST_SPAWN_2

    CMP A, #$02
    JZ GHOST_SPAWN_3

    ; G4
    STI GHOST_X_TMP, #$0F
    STI GHOST_Y_TMP, #$11
    RET


GHOST_SPAWN_1:

    STI GHOST_X_TMP, #$0D
    STI GHOST_Y_TMP, #$0B
    RET


GHOST_SPAWN_2:

    STI GHOST_X_TMP, #$0E
    STI GHOST_Y_TMP, #$0B
    RET


GHOST_SPAWN_3:

    STI GHOST_X_TMP, #$0C
    STI GHOST_Y_TMP, #$11
    RET


STORE_GHOST_TEMP_BY_ID:

    LDA GHOST_ID

    CMP A, #$00
    JZ STORE_GHOST_1

    CMP A, #$01
    JZ STORE_GHOST_2

    CMP A, #$02
    JZ STORE_GHOST_3

    ; G4
    LDA GHOST_X_TMP
    STA G4_X
    LDA GHOST_Y_TMP
    STA G4_Y
    RET


STORE_GHOST_1:

    LDA GHOST_X_TMP
    STA G1_X
    LDA GHOST_Y_TMP
    STA G1_Y
    RET


STORE_GHOST_2:

    LDA GHOST_X_TMP
    STA G2_X
    LDA GHOST_Y_TMP
    STA G2_Y
    RET


STORE_GHOST_3:

    LDA GHOST_X_TMP
    STA G3_X
    LDA GHOST_Y_TMP
    STA G3_Y
    RET


DRAW_ALL_ENTITIES:

    CALL DRAW_PLAYER
    CALL DRAW_ALL_GHOSTS
    RET


DRAW_ALL_GHOSTS:

    LDA G1_X
    STA GHOST_X_TMP
    LDA G1_Y
    STA GHOST_Y_TMP
    STI GHOST_ID, #$00
    CALL DRAW_GHOST_TEMP

    LDA G2_X
    STA GHOST_X_TMP
    LDA G2_Y
    STA GHOST_Y_TMP
    STI GHOST_ID, #$01
    CALL DRAW_GHOST_TEMP

    LDA G3_X
    STA GHOST_X_TMP
    LDA G3_Y
    STA GHOST_Y_TMP
    STI GHOST_ID, #$02
    CALL DRAW_GHOST_TEMP

    LDA G4_X
    STA GHOST_X_TMP
    LDA G4_Y
    STA GHOST_Y_TMP
    STI GHOST_ID, #$03
    CALL DRAW_GHOST_TEMP

    RET


ERASE_ALL_ENTITIES:

    LDA PLAYER_X
    STA TARGET_X
    LDA PLAYER_Y
    STA TARGET_Y
    CALL DRAW_MAP_TILE_XY

    LDA G1_X
    STA TARGET_X
    LDA G1_Y
    STA TARGET_Y
    CALL DRAW_MAP_TILE_XY

    LDA G2_X
    STA TARGET_X
    LDA G2_Y
    STA TARGET_Y
    CALL DRAW_MAP_TILE_XY

    LDA G3_X
    STA TARGET_X
    LDA G3_Y
    STA TARGET_Y
    CALL DRAW_MAP_TILE_XY

    LDA G4_X
    STA TARGET_X
    LDA G4_Y
    STA TARGET_Y
    CALL DRAW_MAP_TILE_XY

    RET


; ============================================================================
; DESENHO DE SPRITES
; ============================================================================

DRAW_PLAYER:

    LDA PLAYER_X
    STA TARGET_X
    LDA PLAYER_Y
    STA TARGET_Y
    CALL SET_SCREEN_POS_FROM_TARGET

    LDA ANIM_FRAME
    CMP A, #$00
    JZ DRAW_PLAYER_CLOSED

    LDA DIR_CURRENT

    CMP A, #DIR_UP
    JZ DRAW_PLAYER_UP

    CMP A, #DIR_RIGHT
    JZ DRAW_PLAYER_RIGHT

    CMP A, #DIR_DOWN
    JZ DRAW_PLAYER_DOWN

    PTR PAC_LEFT_OPEN
    JMP DRAW_PATTERN7


DRAW_PLAYER_UP:

    PTR PAC_UP_OPEN
    JMP DRAW_PATTERN7


DRAW_PLAYER_RIGHT:

    PTR PAC_RIGHT_OPEN
    JMP DRAW_PATTERN7


DRAW_PLAYER_DOWN:

    PTR PAC_DOWN_OPEN
    JMP DRAW_PATTERN7


DRAW_PLAYER_CLOSED:

    PTR PAC_CLOSED
    JMP DRAW_PATTERN7


DRAW_GHOST_TEMP:

    LDA GHOST_X_TMP
    STA TARGET_X
    LDA GHOST_Y_TMP
    STA TARGET_Y
    CALL SET_SCREEN_POS_FROM_TARGET

    LDA POWER_TIMER
    CMP A, #$00
    JNZ DRAW_GHOST_FRIGHT

    LDA GHOST_ID

    CMP A, #$00
    JZ DRAW_GHOST_1_PATTERN

    CMP A, #$01
    JZ DRAW_GHOST_2_PATTERN

    CMP A, #$02
    JZ DRAW_GHOST_3_PATTERN

    PTR GHOST_4_PATTERN
    JMP DRAW_PATTERN7


DRAW_GHOST_1_PATTERN:

    PTR GHOST_1_PATTERN
    JMP DRAW_PATTERN7


DRAW_GHOST_2_PATTERN:

    PTR GHOST_2_PATTERN
    JMP DRAW_PATTERN7


DRAW_GHOST_3_PATTERN:

    PTR GHOST_3_PATTERN
    JMP DRAW_PATTERN7


DRAW_GHOST_FRIGHT:

    PTR GHOST_FRIGHT_PATTERN
    JMP DRAW_PATTERN7


; ============================================================================
; MAPA / VRAM
; ============================================================================

VIDEO_WAIT:

    LDA VIDEO_STATUS
    TEST A, #VIDEO_BUSY_MASK
    JNZ VIDEO_WAIT
    RET


SET_SCREEN_POS_FROM_TARGET:

    ; X do mapa e uma coluna de byte.
    LDA TARGET_X
    ADD A, #MAP_X_OFFSET
    STA DRAW_SCREEN_X

    ; Y pixel = 20 + TARGET_Y * 7
    ; y*7 = y*8 - y
    LDB TARGET_Y
    LDA TARGET_Y
    SHL A
    SHL A
    SHL A
    SUB A, B
    ADD A, #MAP_Y_OFFSET
    STA DRAW_PIXEL_Y

    RET


; PTR deve apontar para 7 bytes.
DRAW_PATTERN7:

    STI DRAW_ROWS, #$07


DRAW_PATTERN7_LOOP:

    LDA [PTR+]
    STA DRAW_VALUE

    CALL VIDEO_WAIT

    LDA DRAW_SCREEN_X
    STA VIDEO_X

    LDA DRAW_PIXEL_Y
    STA VIDEO_Y

    LDA DRAW_VALUE
    STA VIDEO_DATA

    LDA DRAW_PIXEL_Y
    INC A
    STA DRAW_PIXEL_Y

    LDA DRAW_ROWS
    DEC A
    STA DRAW_ROWS
    JNZ DRAW_PATTERN7_LOOP

    RET


DRAW_FULL_MAZE:

    STI TARGET_Y, #$00


DRAW_MAZE_ROW:

    STI TARGET_X, #$00


DRAW_MAZE_CELL:

    CALL DRAW_MAP_TILE_XY

    LDA TARGET_X
    INC A
    STA TARGET_X

    CMP A, #MAP_WIDTH
    JNZ DRAW_MAZE_CELL

    LDA TARGET_Y
    INC A
    STA TARGET_Y

    CMP A, #MAP_HEIGHT
    JNZ DRAW_MAZE_ROW

    RET


DRAW_MAP_TILE_XY:

    CALL MAP_GET_TARGET
    STA MAP_VALUE

    CALL SET_SCREEN_POS_FROM_TARGET

    LDA MAP_VALUE

    CMP A, #TILE_DOT
    JZ DRAW_TILE_DOT

    CMP A, #TILE_POWER
    JZ DRAW_TILE_POWER

    AND A, #$F0
    CMP A, #$10
    JZ DRAW_TILE_WALL

    PTR TILE_EMPTY_PATTERN
    JMP DRAW_PATTERN7


DRAW_TILE_DOT:

    PTR TILE_DOT_PATTERN
    JMP DRAW_PATTERN7


DRAW_TILE_POWER:

    PTR TILE_POWER_PATTERN
    JMP DRAW_PATTERN7


DRAW_TILE_WALL:

    LDA MAP_VALUE
    AND A, #$0F
    CMP A, #$00
    JZ DRAW_WALL_0

    CMP A, #$01
    JZ DRAW_WALL_1

    CMP A, #$02
    JZ DRAW_WALL_2

    CMP A, #$03
    JZ DRAW_WALL_3

    CMP A, #$04
    JZ DRAW_WALL_4

    CMP A, #$05
    JZ DRAW_WALL_5

    CMP A, #$06
    JZ DRAW_WALL_6

    CMP A, #$07
    JZ DRAW_WALL_7

    CMP A, #$08
    JZ DRAW_WALL_8

    CMP A, #$09
    JZ DRAW_WALL_9

    CMP A, #$0A
    JZ DRAW_WALL_A

    CMP A, #$0B
    JZ DRAW_WALL_B

    CMP A, #$0C
    JZ DRAW_WALL_C

    CMP A, #$0D
    JZ DRAW_WALL_D

    CMP A, #$0E
    JZ DRAW_WALL_E

    CMP A, #$0F
    JZ DRAW_WALL_F


DRAW_WALL_0:

    PTR WALL_0_PATTERN
    JMP DRAW_PATTERN7

DRAW_WALL_1:

    PTR WALL_1_PATTERN
    JMP DRAW_PATTERN7

DRAW_WALL_2:

    PTR WALL_2_PATTERN
    JMP DRAW_PATTERN7

DRAW_WALL_3:

    PTR WALL_3_PATTERN
    JMP DRAW_PATTERN7

DRAW_WALL_4:

    PTR WALL_4_PATTERN
    JMP DRAW_PATTERN7

DRAW_WALL_5:

    PTR WALL_5_PATTERN
    JMP DRAW_PATTERN7

DRAW_WALL_6:

    PTR WALL_6_PATTERN
    JMP DRAW_PATTERN7

DRAW_WALL_7:

    PTR WALL_7_PATTERN
    JMP DRAW_PATTERN7

DRAW_WALL_8:

    PTR WALL_8_PATTERN
    JMP DRAW_PATTERN7

DRAW_WALL_9:

    PTR WALL_9_PATTERN
    JMP DRAW_PATTERN7

DRAW_WALL_A:

    PTR WALL_A_PATTERN
    JMP DRAW_PATTERN7

DRAW_WALL_B:

    PTR WALL_B_PATTERN
    JMP DRAW_PATTERN7

DRAW_WALL_C:

    PTR WALL_C_PATTERN
    JMP DRAW_PATTERN7

DRAW_WALL_D:

    PTR WALL_D_PATTERN
    JMP DRAW_PATTERN7

DRAW_WALL_E:

    PTR WALL_E_PATTERN
    JMP DRAW_PATTERN7

DRAW_WALL_F:

    PTR WALL_F_PATTERN
    JMP DRAW_PATTERN7


; ============================================================================
; MAP_POINT
;
; Entrada: TARGET_X 0..27, TARGET_Y 0..30
; Saida:   PTR apontando para MAP_RAM + y*28 + x
;
; Como o WALL possui apenas um PTR e nao ha "PTR <- RAM", as 31 linhas usam
; enderecos absolutos. Depois so avancamos X vezes.
; ============================================================================

MAP_GET_TARGET:

    CALL MAP_POINT
    LDA [PTR]
    RET


MAP_POINT:

    LDA TARGET_Y
    CMP A, #$00
    JZ MAP_ROW_00
    CMP A, #$01
    JZ MAP_ROW_01
    CMP A, #$02
    JZ MAP_ROW_02
    CMP A, #$03
    JZ MAP_ROW_03
    CMP A, #$04
    JZ MAP_ROW_04
    CMP A, #$05
    JZ MAP_ROW_05
    CMP A, #$06
    JZ MAP_ROW_06
    CMP A, #$07
    JZ MAP_ROW_07
    CMP A, #$08
    JZ MAP_ROW_08
    CMP A, #$09
    JZ MAP_ROW_09
    CMP A, #$0A
    JZ MAP_ROW_10
    CMP A, #$0B
    JZ MAP_ROW_11
    CMP A, #$0C
    JZ MAP_ROW_12
    CMP A, #$0D
    JZ MAP_ROW_13
    CMP A, #$0E
    JZ MAP_ROW_14
    CMP A, #$0F
    JZ MAP_ROW_15
    CMP A, #$10
    JZ MAP_ROW_16
    CMP A, #$11
    JZ MAP_ROW_17
    CMP A, #$12
    JZ MAP_ROW_18
    CMP A, #$13
    JZ MAP_ROW_19
    CMP A, #$14
    JZ MAP_ROW_20
    CMP A, #$15
    JZ MAP_ROW_21
    CMP A, #$16
    JZ MAP_ROW_22
    CMP A, #$17
    JZ MAP_ROW_23
    CMP A, #$18
    JZ MAP_ROW_24
    CMP A, #$19
    JZ MAP_ROW_25
    CMP A, #$1A
    JZ MAP_ROW_26
    CMP A, #$1B
    JZ MAP_ROW_27
    CMP A, #$1C
    JZ MAP_ROW_28
    CMP A, #$1D
    JZ MAP_ROW_29
    CMP A, #$1E
    JZ MAP_ROW_30
    PTR MAP_RAM
    JMP MAP_ADVANCE_X

MAP_ROW_00:

    PTR $0800
    JMP MAP_ADVANCE_X

MAP_ROW_01:

    PTR $081C
    JMP MAP_ADVANCE_X

MAP_ROW_02:

    PTR $0838
    JMP MAP_ADVANCE_X

MAP_ROW_03:

    PTR $0854
    JMP MAP_ADVANCE_X

MAP_ROW_04:

    PTR $0870
    JMP MAP_ADVANCE_X

MAP_ROW_05:

    PTR $088C
    JMP MAP_ADVANCE_X

MAP_ROW_06:

    PTR $08A8
    JMP MAP_ADVANCE_X

MAP_ROW_07:

    PTR $08C4
    JMP MAP_ADVANCE_X

MAP_ROW_08:

    PTR $08E0
    JMP MAP_ADVANCE_X

MAP_ROW_09:

    PTR $08FC
    JMP MAP_ADVANCE_X

MAP_ROW_10:

    PTR $0918
    JMP MAP_ADVANCE_X

MAP_ROW_11:

    PTR $0934
    JMP MAP_ADVANCE_X

MAP_ROW_12:

    PTR $0950
    JMP MAP_ADVANCE_X

MAP_ROW_13:

    PTR $096C
    JMP MAP_ADVANCE_X

MAP_ROW_14:

    PTR $0988
    JMP MAP_ADVANCE_X

MAP_ROW_15:

    PTR $09A4
    JMP MAP_ADVANCE_X

MAP_ROW_16:

    PTR $09C0
    JMP MAP_ADVANCE_X

MAP_ROW_17:

    PTR $09DC
    JMP MAP_ADVANCE_X

MAP_ROW_18:

    PTR $09F8
    JMP MAP_ADVANCE_X

MAP_ROW_19:

    PTR $0A14
    JMP MAP_ADVANCE_X

MAP_ROW_20:

    PTR $0A30
    JMP MAP_ADVANCE_X

MAP_ROW_21:

    PTR $0A4C
    JMP MAP_ADVANCE_X

MAP_ROW_22:

    PTR $0A68
    JMP MAP_ADVANCE_X

MAP_ROW_23:

    PTR $0A84
    JMP MAP_ADVANCE_X

MAP_ROW_24:

    PTR $0AA0
    JMP MAP_ADVANCE_X

MAP_ROW_25:

    PTR $0ABC
    JMP MAP_ADVANCE_X

MAP_ROW_26:

    PTR $0AD8
    JMP MAP_ADVANCE_X

MAP_ROW_27:

    PTR $0AF4
    JMP MAP_ADVANCE_X

MAP_ROW_28:

    PTR $0B10
    JMP MAP_ADVANCE_X

MAP_ROW_29:

    PTR $0B2C
    JMP MAP_ADVANCE_X

MAP_ROW_30:

    PTR $0B48
    JMP MAP_ADVANCE_X


MAP_ADVANCE_X:

    LDA TARGET_X
    STA LOOP_COUNT

MAP_ADVANCE_X_LOOP:

    LDA LOOP_COUNT
    CMP A, #$00
    JZ MAP_POINT_DONE

    INC PTR

    DEC A
    STA LOOP_COUNT
    JMP MAP_ADVANCE_X_LOOP


MAP_POINT_DONE:

    RET


; ============================================================================
; HUD
; ============================================================================

DRAW_SCORE_LABEL:

    STI DRAW_PIXEL_Y, #$04

    STI DRAW_SCREEN_X, #$0A
    PTR FONT_S
    CALL DRAW_PATTERN7

    STI DRAW_PIXEL_Y, #$04
    STI DRAW_SCREEN_X, #$0B
    PTR FONT_C
    CALL DRAW_PATTERN7

    STI DRAW_PIXEL_Y, #$04
    STI DRAW_SCREEN_X, #$0C
    PTR FONT_O
    CALL DRAW_PATTERN7

    STI DRAW_PIXEL_Y, #$04
    STI DRAW_SCREEN_X, #$0D
    PTR FONT_R
    CALL DRAW_PATTERN7

    STI DRAW_PIXEL_Y, #$04
    STI DRAW_SCREEN_X, #$0E
    PTR FONT_E
    CALL DRAW_PATTERN7

    RET


DRAW_SCORE:

    LDA SCORE_HUNDREDS
    STA DIGIT_VALUE
    STI DRAW_SCREEN_X, #$10
    CALL DRAW_DIGIT

    LDA SCORE_TENS
    STA DIGIT_VALUE
    STI DRAW_SCREEN_X, #$11
    CALL DRAW_DIGIT

    LDA SCORE_ONES
    STA DIGIT_VALUE
    STI DRAW_SCREEN_X, #$12
    CALL DRAW_DIGIT

    RET


DRAW_DIGIT:

    STI DRAW_PIXEL_Y, #$04

    LDA DIGIT_VALUE

    CMP A, #$00
    JZ DIGIT_0_SELECT
    CMP A, #$01
    JZ DIGIT_1_SELECT
    CMP A, #$02
    JZ DIGIT_2_SELECT
    CMP A, #$03
    JZ DIGIT_3_SELECT
    CMP A, #$04
    JZ DIGIT_4_SELECT
    CMP A, #$05
    JZ DIGIT_5_SELECT
    CMP A, #$06
    JZ DIGIT_6_SELECT
    CMP A, #$07
    JZ DIGIT_7_SELECT
    CMP A, #$08
    JZ DIGIT_8_SELECT

    PTR DIGIT_9
    JMP DRAW_PATTERN7


DIGIT_0_SELECT:
    PTR DIGIT_0
    JMP DRAW_PATTERN7

DIGIT_1_SELECT:
    PTR DIGIT_1
    JMP DRAW_PATTERN7

DIGIT_2_SELECT:
    PTR DIGIT_2
    JMP DRAW_PATTERN7

DIGIT_3_SELECT:
    PTR DIGIT_3
    JMP DRAW_PATTERN7

DIGIT_4_SELECT:
    PTR DIGIT_4
    JMP DRAW_PATTERN7

DIGIT_5_SELECT:
    PTR DIGIT_5
    JMP DRAW_PATTERN7

DIGIT_6_SELECT:
    PTR DIGIT_6
    JMP DRAW_PATTERN7

DIGIT_7_SELECT:
    PTR DIGIT_7
    JMP DRAW_PATTERN7

DIGIT_8_SELECT:
    PTR DIGIT_8
    JMP DRAW_PATTERN7


DRAW_LIVES:

    ; Limpa os tres slots.
    STI DRAW_PIXEL_Y, #$04
    STI DRAW_SCREEN_X, #$1E
    PTR TILE_EMPTY_PATTERN
    CALL DRAW_PATTERN7

    STI DRAW_PIXEL_Y, #$04
    STI DRAW_SCREEN_X, #$1F
    PTR TILE_EMPTY_PATTERN
    CALL DRAW_PATTERN7

    STI DRAW_PIXEL_Y, #$04
    STI DRAW_SCREEN_X, #$20
    PTR TILE_EMPTY_PATTERN
    CALL DRAW_PATTERN7

    LDA LIVES
    CMP A, #$00
    JZ DRAW_LIVES_DONE

    STI DRAW_PIXEL_Y, #$04
    STI DRAW_SCREEN_X, #$1E
    PTR PAC_CLOSED
    CALL DRAW_PATTERN7

    LDA LIVES
    CMP A, #$01
    JZ DRAW_LIVES_DONE

    STI DRAW_PIXEL_Y, #$04
    STI DRAW_SCREEN_X, #$1F
    PTR PAC_CLOSED
    CALL DRAW_PATTERN7

    LDA LIVES
    CMP A, #$02
    JZ DRAW_LIVES_DONE

    STI DRAW_PIXEL_Y, #$04
    STI DRAW_SCREEN_X, #$20
    PTR PAC_CLOSED
    CALL DRAW_PATTERN7


DRAW_LIVES_DONE:

    RET


; ============================================================================
; SINCRONISMO / TECLADO
; ============================================================================

SYNC_FRAME_STATE:

    LDA VIDEO_STATUS
    AND A, #VIDEO_FRAME_MASK
    STA LAST_FRAME
    RET


WAIT_ONE_FRAME:

WAIT_FRAME_LOOP:

    CALL POLL_KEYBOARD

    LDA VIDEO_STATUS
    AND A, #VIDEO_FRAME_MASK

    LDB LAST_FRAME
    CMP A, B
    JZ WAIT_FRAME_LOOP

    STA LAST_FRAME
    RET


POLL_KEYBOARD:

    LDA SYSTEM_STATUS
    TEST A, #KEY_READY_MASK
    JZ KEY_DONE

    LDA KEY_DATA

    ; W / w
    CMP A, #$57
    JZ KEY_UP
    CMP A, #$77
    JZ KEY_UP

    ; S / s
    CMP A, #$53
    JZ KEY_DOWN
    CMP A, #$73
    JZ KEY_DOWN

    ; A / a
    CMP A, #$41
    JZ KEY_LEFT
    CMP A, #$61
    JZ KEY_LEFT

    ; D / d
    CMP A, #$44
    JZ KEY_RIGHT
    CMP A, #$64
    JZ KEY_RIGHT

    ; P / p
    CMP A, #$50
    JZ KEY_PAUSE
    CMP A, #$70
    JZ KEY_PAUSE

    ; R / r
    CMP A, #$52
    JZ KEY_RESTART
    CMP A, #$72
    JZ KEY_RESTART

    ; Q / q
    CMP A, #$51
    JZ KEY_EXIT
    CMP A, #$71
    JZ KEY_EXIT

    RET


KEY_UP:
    STI DIR_NEXT, #DIR_UP
    RET

KEY_DOWN:
    STI DIR_NEXT, #DIR_DOWN
    RET

KEY_LEFT:
    STI DIR_NEXT, #DIR_LEFT
    RET

KEY_RIGHT:
    STI DIR_NEXT, #DIR_RIGHT
    RET


KEY_PAUSE:

    LDA PAUSED_FLAG
    XOR A, #$01
    STA PAUSED_FLAG

    STI SOUND_CFG,    #SILENCE
    STI SOUND_FRAMES, #$00
    RET


KEY_RESTART:

    STI RESTART_FLAG, #$01
    RET


KEY_EXIT:

    STI EXIT_FLAG, #$01


KEY_DONE:

    RET


; ============================================================================
; POWER / SOM
; ============================================================================

SERVICE_POWER:

    LDA POWER_TIMER
    CMP A, #$00
    JZ SERVICE_POWER_DONE

    DEC A
    STA POWER_TIMER

    CMP A, #$00
    JNZ SERVICE_POWER_DONE

    ; Volta os sprites dos fantasmas ao normal.
    CALL DRAW_ALL_GHOSTS


SERVICE_POWER_DONE:

    RET


SERVICE_SOUND:

    LDA SOUND_FRAMES
    CMP A, #$00
    JZ SERVICE_SOUND_DONE

    DEC A
    STA SOUND_FRAMES

    CMP A, #$00
    JNZ SERVICE_SOUND_DONE

    STI SOUND_CFG, #SILENCE


SERVICE_SOUND_DONE:

    RET


PLAY_CHOMP:

    LDA CHOMP_TOGGLE
    XOR A, #$01
    STA CHOMP_TOGGLE

    CMP A, #$00
    JZ CHOMP_LOW

    STI SOUND_CFG, #NOTE_G4
    STI SOUND_FRAMES, #$02
    RET


CHOMP_LOW:

    STI SOUND_CFG, #NOTE_E4
    STI SOUND_FRAMES, #$02
    RET


; Timers de SYSTEM_STATUS sao flags retidas.
WAIT_500MS:

    STI SYSTEM_STATUS, #$00

WAIT_500MS_LOOP:

    LDA SYSTEM_STATUS
    TEST A, #$02
    JZ WAIT_500MS_LOOP
    RET


WAIT_1MS:

    STI SYSTEM_STATUS, #$00

WAIT_1MS_LOOP:

    LDA SYSTEM_STATUS
    TEST A, #$01
    JZ WAIT_1MS_LOOP
    RET


WAIT_125MS:

    LDB #$80

WAIT_125MS_LOOP:

    CALL WAIT_1MS
    DEC B
    JNZ WAIT_125MS_LOOP
    RET


WAIT_250MS:

    CALL WAIT_125MS
    CALL WAIT_125MS
    RET


READY_JINGLE:

    STI SOUND_CFG, #NOTE_C4
    CALL WAIT_125MS

    STI SOUND_CFG, #NOTE_E4
    CALL WAIT_125MS

    STI SOUND_CFG, #NOTE_G4
    CALL WAIT_125MS

    STI SOUND_CFG, #NOTE_C5
    CALL WAIT_250MS

    STI SOUND_CFG, #SILENCE
    RET


DEATH_SOUND:

    STI SOUND_CFG, #NOTE_C5
    CALL WAIT_125MS

    STI SOUND_CFG, #NOTE_A4
    CALL WAIT_125MS

    STI SOUND_CFG, #NOTE_F4
    CALL WAIT_125MS

    STI SOUND_CFG, #NOTE_D4
    CALL WAIT_125MS

    STI SOUND_CFG, #NOTE_C4
    CALL WAIT_250MS

    STI SOUND_CFG, #SILENCE
    RET


GAME_OVER_SOUND:

    STI SOUND_CFG, #NOTE_G4
    CALL WAIT_125MS

    STI SOUND_CFG, #NOTE_E4
    CALL WAIT_125MS

    STI SOUND_CFG, #NOTE_D4
    CALL WAIT_125MS

    STI SOUND_CFG, #NOTE_C4
    CALL WAIT_500MS

    STI SOUND_CFG, #SILENCE
    RET


; ============================================================================
; GAME OVER
; ============================================================================

GAME_OVER:

    STI SOUND_CFG,    #SILENCE
    STI SOUND_FRAMES, #$00
    STI PAUSED_FLAG,  #$00

    CALL DRAW_GAME_OVER
    CALL GAME_OVER_SOUND
    CALL SYNC_FRAME_STATE


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

    ; "GAME OVER" no centro.
    STI DRAW_PIXEL_Y, #$70

    STI DRAW_SCREEN_X, #$0F
    PTR FONT_G
    CALL DRAW_PATTERN7

    STI DRAW_PIXEL_Y, #$70
    STI DRAW_SCREEN_X, #$10
    PTR FONT_A
    CALL DRAW_PATTERN7

    STI DRAW_PIXEL_Y, #$70
    STI DRAW_SCREEN_X, #$11
    PTR FONT_M
    CALL DRAW_PATTERN7

    STI DRAW_PIXEL_Y, #$70
    STI DRAW_SCREEN_X, #$12
    PTR FONT_E
    CALL DRAW_PATTERN7

    STI DRAW_PIXEL_Y, #$70
    STI DRAW_SCREEN_X, #$13
    PTR TILE_EMPTY_PATTERN
    CALL DRAW_PATTERN7

    STI DRAW_PIXEL_Y, #$70
    STI DRAW_SCREEN_X, #$14
    PTR FONT_O
    CALL DRAW_PATTERN7

    STI DRAW_PIXEL_Y, #$70
    STI DRAW_SCREEN_X, #$15
    PTR FONT_V
    CALL DRAW_PATTERN7

    STI DRAW_PIXEL_Y, #$70
    STI DRAW_SCREEN_X, #$16
    PTR FONT_E
    CALL DRAW_PATTERN7

    STI DRAW_PIXEL_Y, #$70
    STI DRAW_SCREEN_X, #$17
    PTR FONT_R
    CALL DRAW_PATTERN7

    RET


; ============================================================================
; SAIDA
; ============================================================================

EXIT_GAME:

    CALL VIDEO_WAIT

    STI SOUND_CFG, #SILENCE

    STI VIDEO_CMD, #MODE_TEXT_40X30
    CALL VIDEO_WAIT

    STI VIDEO_CMD, #VIDEO_CLEAR
    CALL VIDEO_WAIT

    RET


; ============================================================================
; INICIALIZACAO DO MAPA MUTAVEL
;
; Cada byte RAM:
;   $00 = vazio
;   $01 = pellet
;   $02 = power pellet
;   $10..$1F = parede; low nibble = conectividade N/E/S/W
; ============================================================================

INIT_MAP_RAM:
    STI $0800, #$16
    STI $0801, #$1A
    STI $0802, #$1A
    STI $0803, #$1A
    STI $0804, #$1A
    STI $0805, #$1A
    STI $0806, #$1A
    STI $0807, #$1A
    STI $0808, #$1A
    STI $0809, #$1A
    STI $080A, #$1A
    STI $080B, #$1A
    STI $080C, #$1A
    STI $080D, #$1E
    STI $080E, #$1E
    STI $080F, #$1A
    STI $0810, #$1A
    STI $0811, #$1A
    STI $0812, #$1A
    STI $0813, #$1A
    STI $0814, #$1A
    STI $0815, #$1A
    STI $0816, #$1A
    STI $0817, #$1A
    STI $0818, #$1A
    STI $0819, #$1A
    STI $081A, #$1A
    STI $081B, #$1C
    STI $081C, #$15
    STI $081D, #$01
    STI $081E, #$01
    STI $081F, #$01
    STI $0820, #$01
    STI $0821, #$01
    STI $0822, #$01
    STI $0823, #$01
    STI $0824, #$01
    STI $0825, #$01
    STI $0826, #$01
    STI $0827, #$01
    STI $0828, #$01
    STI $0829, #$17
    STI $082A, #$1D
    STI $082B, #$01
    STI $082C, #$01
    STI $082D, #$01
    STI $082E, #$01
    STI $082F, #$01
    STI $0830, #$01
    STI $0831, #$01
    STI $0832, #$01
    STI $0833, #$01
    STI $0834, #$01
    STI $0835, #$01
    STI $0836, #$01
    STI $0837, #$15
    STI $0838, #$15
    STI $0839, #$01
    STI $083A, #$16
    STI $083B, #$1E
    STI $083C, #$1E
    STI $083D, #$1C
    STI $083E, #$01
    STI $083F, #$16
    STI $0840, #$1E
    STI $0841, #$1E
    STI $0842, #$1E
    STI $0843, #$1C
    STI $0844, #$01
    STI $0845, #$17
    STI $0846, #$1D
    STI $0847, #$01
    STI $0848, #$16
    STI $0849, #$1E
    STI $084A, #$1E
    STI $084B, #$1E
    STI $084C, #$1C
    STI $084D, #$01
    STI $084E, #$16
    STI $084F, #$1E
    STI $0850, #$1E
    STI $0851, #$1C
    STI $0852, #$01
    STI $0853, #$15
    STI $0854, #$15
    STI $0855, #$02
    STI $0856, #$17
    STI $0857, #$1F
    STI $0858, #$1F
    STI $0859, #$1D
    STI $085A, #$01
    STI $085B, #$17
    STI $085C, #$1F
    STI $085D, #$1F
    STI $085E, #$1F
    STI $085F, #$1D
    STI $0860, #$01
    STI $0861, #$17
    STI $0862, #$1D
    STI $0863, #$01
    STI $0864, #$17
    STI $0865, #$1F
    STI $0866, #$1F
    STI $0867, #$1F
    STI $0868, #$1D
    STI $0869, #$01
    STI $086A, #$17
    STI $086B, #$1F
    STI $086C, #$1F
    STI $086D, #$1D
    STI $086E, #$02
    STI $086F, #$15
    STI $0870, #$15
    STI $0871, #$01
    STI $0872, #$13
    STI $0873, #$1B
    STI $0874, #$1B
    STI $0875, #$19
    STI $0876, #$01
    STI $0877, #$13
    STI $0878, #$1B
    STI $0879, #$1B
    STI $087A, #$1B
    STI $087B, #$19
    STI $087C, #$01
    STI $087D, #$13
    STI $087E, #$19
    STI $087F, #$01
    STI $0880, #$13
    STI $0881, #$1B
    STI $0882, #$1B
    STI $0883, #$1B
    STI $0884, #$19
    STI $0885, #$01
    STI $0886, #$13
    STI $0887, #$1B
    STI $0888, #$1B
    STI $0889, #$19
    STI $088A, #$01
    STI $088B, #$15
    STI $088C, #$15
    STI $088D, #$01
    STI $088E, #$01
    STI $088F, #$01
    STI $0890, #$01
    STI $0891, #$01
    STI $0892, #$01
    STI $0893, #$01
    STI $0894, #$01
    STI $0895, #$01
    STI $0896, #$01
    STI $0897, #$01
    STI $0898, #$01
    STI $0899, #$01
    STI $089A, #$01
    STI $089B, #$01
    STI $089C, #$01
    STI $089D, #$01
    STI $089E, #$01
    STI $089F, #$01
    STI $08A0, #$01
    STI $08A1, #$01
    STI $08A2, #$01
    STI $08A3, #$01
    STI $08A4, #$01
    STI $08A5, #$01
    STI $08A6, #$01
    STI $08A7, #$15
    STI $08A8, #$15
    STI $08A9, #$01
    STI $08AA, #$16
    STI $08AB, #$1E
    STI $08AC, #$1E
    STI $08AD, #$1C
    STI $08AE, #$01
    STI $08AF, #$16
    STI $08B0, #$1C
    STI $08B1, #$01
    STI $08B2, #$16
    STI $08B3, #$1E
    STI $08B4, #$1E
    STI $08B5, #$1E
    STI $08B6, #$1E
    STI $08B7, #$1E
    STI $08B8, #$1E
    STI $08B9, #$1C
    STI $08BA, #$01
    STI $08BB, #$16
    STI $08BC, #$1C
    STI $08BD, #$01
    STI $08BE, #$16
    STI $08BF, #$1E
    STI $08C0, #$1E
    STI $08C1, #$1C
    STI $08C2, #$01
    STI $08C3, #$15
    STI $08C4, #$15
    STI $08C5, #$01
    STI $08C6, #$13
    STI $08C7, #$1B
    STI $08C8, #$1B
    STI $08C9, #$19
    STI $08CA, #$01
    STI $08CB, #$17
    STI $08CC, #$1D
    STI $08CD, #$01
    STI $08CE, #$13
    STI $08CF, #$1B
    STI $08D0, #$1B
    STI $08D1, #$1F
    STI $08D2, #$1F
    STI $08D3, #$1B
    STI $08D4, #$1B
    STI $08D5, #$19
    STI $08D6, #$01
    STI $08D7, #$17
    STI $08D8, #$1D
    STI $08D9, #$01
    STI $08DA, #$13
    STI $08DB, #$1B
    STI $08DC, #$1B
    STI $08DD, #$19
    STI $08DE, #$01
    STI $08DF, #$15
    STI $08E0, #$15
    STI $08E1, #$01
    STI $08E2, #$01
    STI $08E3, #$01
    STI $08E4, #$01
    STI $08E5, #$01
    STI $08E6, #$01
    STI $08E7, #$17
    STI $08E8, #$1D
    STI $08E9, #$01
    STI $08EA, #$01
    STI $08EB, #$01
    STI $08EC, #$01
    STI $08ED, #$17
    STI $08EE, #$1D
    STI $08EF, #$01
    STI $08F0, #$01
    STI $08F1, #$01
    STI $08F2, #$01
    STI $08F3, #$17
    STI $08F4, #$1D
    STI $08F5, #$01
    STI $08F6, #$01
    STI $08F7, #$01
    STI $08F8, #$01
    STI $08F9, #$01
    STI $08FA, #$01
    STI $08FB, #$15
    STI $08FC, #$13
    STI $08FD, #$1A
    STI $08FE, #$1A
    STI $08FF, #$1A
    STI $0900, #$1A
    STI $0901, #$1C
    STI $0902, #$01
    STI $0903, #$17
    STI $0904, #$1F
    STI $0905, #$1E
    STI $0906, #$1E
    STI $0907, #$1C
    STI $0908, #$01
    STI $0909, #$17
    STI $090A, #$1D
    STI $090B, #$01
    STI $090C, #$16
    STI $090D, #$1E
    STI $090E, #$1E
    STI $090F, #$1F
    STI $0910, #$1D
    STI $0911, #$01
    STI $0912, #$16
    STI $0913, #$1A
    STI $0914, #$1A
    STI $0915, #$1A
    STI $0916, #$1A
    STI $0917, #$19
    STI $0918, #$00
    STI $0919, #$00
    STI $091A, #$00
    STI $091B, #$00
    STI $091C, #$00
    STI $091D, #$15
    STI $091E, #$01
    STI $091F, #$17
    STI $0920, #$1F
    STI $0921, #$1B
    STI $0922, #$1B
    STI $0923, #$19
    STI $0924, #$01
    STI $0925, #$13
    STI $0926, #$19
    STI $0927, #$01
    STI $0928, #$13
    STI $0929, #$1B
    STI $092A, #$1B
    STI $092B, #$1F
    STI $092C, #$1D
    STI $092D, #$01
    STI $092E, #$15
    STI $092F, #$00
    STI $0930, #$00
    STI $0931, #$00
    STI $0932, #$00
    STI $0933, #$00
    STI $0934, #$00
    STI $0935, #$00
    STI $0936, #$00
    STI $0937, #$00
    STI $0938, #$00
    STI $0939, #$15
    STI $093A, #$01
    STI $093B, #$17
    STI $093C, #$1D
    STI $093D, #$01
    STI $093E, #$01
    STI $093F, #$01
    STI $0940, #$01
    STI $0941, #$00
    STI $0942, #$00
    STI $0943, #$01
    STI $0944, #$01
    STI $0945, #$01
    STI $0946, #$01
    STI $0947, #$17
    STI $0948, #$1D
    STI $0949, #$01
    STI $094A, #$15
    STI $094B, #$00
    STI $094C, #$00
    STI $094D, #$00
    STI $094E, #$00
    STI $094F, #$00
    STI $0950, #$00
    STI $0951, #$00
    STI $0952, #$00
    STI $0953, #$00
    STI $0954, #$00
    STI $0955, #$15
    STI $0956, #$01
    STI $0957, #$17
    STI $0958, #$1D
    STI $0959, #$01
    STI $095A, #$16
    STI $095B, #$1A
    STI $095C, #$18
    STI $095D, #$01
    STI $095E, #$01
    STI $095F, #$12
    STI $0960, #$1A
    STI $0961, #$1C
    STI $0962, #$01
    STI $0963, #$17
    STI $0964, #$1D
    STI $0965, #$01
    STI $0966, #$15
    STI $0967, #$00
    STI $0968, #$00
    STI $0969, #$00
    STI $096A, #$00
    STI $096B, #$00
    STI $096C, #$12
    STI $096D, #$1A
    STI $096E, #$1A
    STI $096F, #$1A
    STI $0970, #$1A
    STI $0971, #$19
    STI $0972, #$01
    STI $0973, #$13
    STI $0974, #$19
    STI $0975, #$01
    STI $0976, #$15
    STI $0977, #$01
    STI $0978, #$01
    STI $0979, #$01
    STI $097A, #$01
    STI $097B, #$01
    STI $097C, #$01
    STI $097D, #$15
    STI $097E, #$01
    STI $097F, #$13
    STI $0980, #$19
    STI $0981, #$01
    STI $0982, #$13
    STI $0983, #$1A
    STI $0984, #$1A
    STI $0985, #$1A
    STI $0986, #$1A
    STI $0987, #$18
    STI $0988, #$00
    STI $0989, #$00
    STI $098A, #$00
    STI $098B, #$00
    STI $098C, #$00
    STI $098D, #$00
    STI $098E, #$01
    STI $098F, #$01
    STI $0990, #$01
    STI $0991, #$01
    STI $0992, #$15
    STI $0993, #$01
    STI $0994, #$01
    STI $0995, #$01
    STI $0996, #$01
    STI $0997, #$01
    STI $0998, #$01
    STI $0999, #$15
    STI $099A, #$01
    STI $099B, #$01
    STI $099C, #$01
    STI $099D, #$01
    STI $099E, #$00
    STI $099F, #$00
    STI $09A0, #$00
    STI $09A1, #$00
    STI $09A2, #$00
    STI $09A3, #$00
    STI $09A4, #$12
    STI $09A5, #$1A
    STI $09A6, #$1A
    STI $09A7, #$1A
    STI $09A8, #$1A
    STI $09A9, #$1C
    STI $09AA, #$01
    STI $09AB, #$16
    STI $09AC, #$1C
    STI $09AD, #$01
    STI $09AE, #$15
    STI $09AF, #$01
    STI $09B0, #$01
    STI $09B1, #$01
    STI $09B2, #$01
    STI $09B3, #$01
    STI $09B4, #$01
    STI $09B5, #$15
    STI $09B6, #$01
    STI $09B7, #$16
    STI $09B8, #$1C
    STI $09B9, #$01
    STI $09BA, #$16
    STI $09BB, #$1A
    STI $09BC, #$1A
    STI $09BD, #$1A
    STI $09BE, #$1A
    STI $09BF, #$18
    STI $09C0, #$00
    STI $09C1, #$00
    STI $09C2, #$00
    STI $09C3, #$00
    STI $09C4, #$00
    STI $09C5, #$15
    STI $09C6, #$01
    STI $09C7, #$17
    STI $09C8, #$1D
    STI $09C9, #$01
    STI $09CA, #$13
    STI $09CB, #$1A
    STI $09CC, #$1A
    STI $09CD, #$1A
    STI $09CE, #$1A
    STI $09CF, #$1A
    STI $09D0, #$1A
    STI $09D1, #$19
    STI $09D2, #$01
    STI $09D3, #$17
    STI $09D4, #$1D
    STI $09D5, #$01
    STI $09D6, #$15
    STI $09D7, #$00
    STI $09D8, #$00
    STI $09D9, #$00
    STI $09DA, #$00
    STI $09DB, #$00
    STI $09DC, #$00
    STI $09DD, #$00
    STI $09DE, #$00
    STI $09DF, #$00
    STI $09E0, #$00
    STI $09E1, #$15
    STI $09E2, #$01
    STI $09E3, #$17
    STI $09E4, #$1D
    STI $09E5, #$01
    STI $09E6, #$01
    STI $09E7, #$01
    STI $09E8, #$00
    STI $09E9, #$01
    STI $09EA, #$01
    STI $09EB, #$00
    STI $09EC, #$01
    STI $09ED, #$01
    STI $09EE, #$01
    STI $09EF, #$17
    STI $09F0, #$1D
    STI $09F1, #$01
    STI $09F2, #$15
    STI $09F3, #$00
    STI $09F4, #$00
    STI $09F5, #$00
    STI $09F6, #$00
    STI $09F7, #$00
    STI $09F8, #$00
    STI $09F9, #$00
    STI $09FA, #$00
    STI $09FB, #$00
    STI $09FC, #$00
    STI $09FD, #$15
    STI $09FE, #$01
    STI $09FF, #$17
    STI $0A00, #$1D
    STI $0A01, #$01
    STI $0A02, #$16
    STI $0A03, #$1E
    STI $0A04, #$1E
    STI $0A05, #$1E
    STI $0A06, #$1E
    STI $0A07, #$1E
    STI $0A08, #$1E
    STI $0A09, #$1C
    STI $0A0A, #$01
    STI $0A0B, #$17
    STI $0A0C, #$1D
    STI $0A0D, #$01
    STI $0A0E, #$15
    STI $0A0F, #$00
    STI $0A10, #$00
    STI $0A11, #$00
    STI $0A12, #$00
    STI $0A13, #$00
    STI $0A14, #$16
    STI $0A15, #$1A
    STI $0A16, #$1A
    STI $0A17, #$1A
    STI $0A18, #$1A
    STI $0A19, #$19
    STI $0A1A, #$01
    STI $0A1B, #$13
    STI $0A1C, #$19
    STI $0A1D, #$01
    STI $0A1E, #$13
    STI $0A1F, #$1B
    STI $0A20, #$1B
    STI $0A21, #$1F
    STI $0A22, #$1F
    STI $0A23, #$1B
    STI $0A24, #$1B
    STI $0A25, #$19
    STI $0A26, #$01
    STI $0A27, #$13
    STI $0A28, #$19
    STI $0A29, #$01
    STI $0A2A, #$13
    STI $0A2B, #$1A
    STI $0A2C, #$1A
    STI $0A2D, #$1A
    STI $0A2E, #$1A
    STI $0A2F, #$1C
    STI $0A30, #$15
    STI $0A31, #$01
    STI $0A32, #$01
    STI $0A33, #$01
    STI $0A34, #$01
    STI $0A35, #$01
    STI $0A36, #$01
    STI $0A37, #$01
    STI $0A38, #$01
    STI $0A39, #$01
    STI $0A3A, #$01
    STI $0A3B, #$01
    STI $0A3C, #$01
    STI $0A3D, #$17
    STI $0A3E, #$1D
    STI $0A3F, #$01
    STI $0A40, #$01
    STI $0A41, #$01
    STI $0A42, #$01
    STI $0A43, #$01
    STI $0A44, #$01
    STI $0A45, #$01
    STI $0A46, #$01
    STI $0A47, #$01
    STI $0A48, #$01
    STI $0A49, #$01
    STI $0A4A, #$01
    STI $0A4B, #$15
    STI $0A4C, #$15
    STI $0A4D, #$01
    STI $0A4E, #$12
    STI $0A4F, #$1A
    STI $0A50, #$1E
    STI $0A51, #$1C
    STI $0A52, #$01
    STI $0A53, #$12
    STI $0A54, #$1A
    STI $0A55, #$1A
    STI $0A56, #$1A
    STI $0A57, #$18
    STI $0A58, #$01
    STI $0A59, #$13
    STI $0A5A, #$19
    STI $0A5B, #$01
    STI $0A5C, #$12
    STI $0A5D, #$1A
    STI $0A5E, #$1A
    STI $0A5F, #$1A
    STI $0A60, #$18
    STI $0A61, #$01
    STI $0A62, #$16
    STI $0A63, #$1E
    STI $0A64, #$1A
    STI $0A65, #$18
    STI $0A66, #$01
    STI $0A67, #$15
    STI $0A68, #$15
    STI $0A69, #$02
    STI $0A6A, #$01
    STI $0A6B, #$01
    STI $0A6C, #$17
    STI $0A6D, #$1D
    STI $0A6E, #$01
    STI $0A6F, #$01
    STI $0A70, #$01
    STI $0A71, #$01
    STI $0A72, #$01
    STI $0A73, #$01
    STI $0A74, #$01
    STI $0A75, #$00
    STI $0A76, #$01
    STI $0A77, #$01
    STI $0A78, #$01
    STI $0A79, #$01
    STI $0A7A, #$01
    STI $0A7B, #$01
    STI $0A7C, #$01
    STI $0A7D, #$01
    STI $0A7E, #$17
    STI $0A7F, #$1D
    STI $0A80, #$01
    STI $0A81, #$01
    STI $0A82, #$02
    STI $0A83, #$15
    STI $0A84, #$17
    STI $0A85, #$1E
    STI $0A86, #$1C
    STI $0A87, #$01
    STI $0A88, #$17
    STI $0A89, #$1D
    STI $0A8A, #$01
    STI $0A8B, #$16
    STI $0A8C, #$1C
    STI $0A8D, #$01
    STI $0A8E, #$16
    STI $0A8F, #$1E
    STI $0A90, #$1E
    STI $0A91, #$1E
    STI $0A92, #$1E
    STI $0A93, #$1E
    STI $0A94, #$1E
    STI $0A95, #$1C
    STI $0A96, #$01
    STI $0A97, #$16
    STI $0A98, #$1C
    STI $0A99, #$01
    STI $0A9A, #$17
    STI $0A9B, #$1D
    STI $0A9C, #$01
    STI $0A9D, #$16
    STI $0A9E, #$1E
    STI $0A9F, #$1D
    STI $0AA0, #$17
    STI $0AA1, #$1B
    STI $0AA2, #$19
    STI $0AA3, #$01
    STI $0AA4, #$13
    STI $0AA5, #$19
    STI $0AA6, #$01
    STI $0AA7, #$17
    STI $0AA8, #$1D
    STI $0AA9, #$01
    STI $0AAA, #$13
    STI $0AAB, #$1B
    STI $0AAC, #$1B
    STI $0AAD, #$1F
    STI $0AAE, #$1F
    STI $0AAF, #$1B
    STI $0AB0, #$1B
    STI $0AB1, #$19
    STI $0AB2, #$01
    STI $0AB3, #$17
    STI $0AB4, #$1D
    STI $0AB5, #$01
    STI $0AB6, #$13
    STI $0AB7, #$19
    STI $0AB8, #$01
    STI $0AB9, #$13
    STI $0ABA, #$1B
    STI $0ABB, #$1D
    STI $0ABC, #$15
    STI $0ABD, #$01
    STI $0ABE, #$01
    STI $0ABF, #$01
    STI $0AC0, #$01
    STI $0AC1, #$01
    STI $0AC2, #$01
    STI $0AC3, #$17
    STI $0AC4, #$1D
    STI $0AC5, #$01
    STI $0AC6, #$01
    STI $0AC7, #$01
    STI $0AC8, #$01
    STI $0AC9, #$17
    STI $0ACA, #$1D
    STI $0ACB, #$01
    STI $0ACC, #$01
    STI $0ACD, #$01
    STI $0ACE, #$01
    STI $0ACF, #$17
    STI $0AD0, #$1D
    STI $0AD1, #$01
    STI $0AD2, #$01
    STI $0AD3, #$01
    STI $0AD4, #$01
    STI $0AD5, #$01
    STI $0AD6, #$01
    STI $0AD7, #$15
    STI $0AD8, #$15
    STI $0AD9, #$01
    STI $0ADA, #$16
    STI $0ADB, #$1E
    STI $0ADC, #$1E
    STI $0ADD, #$1E
    STI $0ADE, #$1E
    STI $0ADF, #$1F
    STI $0AE0, #$1F
    STI $0AE1, #$1E
    STI $0AE2, #$1E
    STI $0AE3, #$1C
    STI $0AE4, #$01
    STI $0AE5, #$17
    STI $0AE6, #$1D
    STI $0AE7, #$01
    STI $0AE8, #$16
    STI $0AE9, #$1E
    STI $0AEA, #$1E
    STI $0AEB, #$1F
    STI $0AEC, #$1F
    STI $0AED, #$1E
    STI $0AEE, #$1E
    STI $0AEF, #$1E
    STI $0AF0, #$1E
    STI $0AF1, #$1C
    STI $0AF2, #$01
    STI $0AF3, #$15
    STI $0AF4, #$15
    STI $0AF5, #$01
    STI $0AF6, #$13
    STI $0AF7, #$1B
    STI $0AF8, #$1B
    STI $0AF9, #$1B
    STI $0AFA, #$1B
    STI $0AFB, #$1B
    STI $0AFC, #$1B
    STI $0AFD, #$1B
    STI $0AFE, #$1B
    STI $0AFF, #$19
    STI $0B00, #$01
    STI $0B01, #$13
    STI $0B02, #$19
    STI $0B03, #$01
    STI $0B04, #$13
    STI $0B05, #$1B
    STI $0B06, #$1B
    STI $0B07, #$1B
    STI $0B08, #$1B
    STI $0B09, #$1B
    STI $0B0A, #$1B
    STI $0B0B, #$1B
    STI $0B0C, #$1B
    STI $0B0D, #$19
    STI $0B0E, #$01
    STI $0B0F, #$15
    STI $0B10, #$15
    STI $0B11, #$01
    STI $0B12, #$01
    STI $0B13, #$01
    STI $0B14, #$01
    STI $0B15, #$01
    STI $0B16, #$01
    STI $0B17, #$01
    STI $0B18, #$01
    STI $0B19, #$01
    STI $0B1A, #$01
    STI $0B1B, #$01
    STI $0B1C, #$01
    STI $0B1D, #$01
    STI $0B1E, #$01
    STI $0B1F, #$01
    STI $0B20, #$01
    STI $0B21, #$01
    STI $0B22, #$01
    STI $0B23, #$01
    STI $0B24, #$01
    STI $0B25, #$01
    STI $0B26, #$01
    STI $0B27, #$01
    STI $0B28, #$01
    STI $0B29, #$01
    STI $0B2A, #$01
    STI $0B2B, #$15
    STI $0B2C, #$15
    STI $0B2D, #$01
    STI $0B2E, #$16
    STI $0B2F, #$1E
    STI $0B30, #$1E
    STI $0B31, #$1E
    STI $0B32, #$1E
    STI $0B33, #$1E
    STI $0B34, #$1E
    STI $0B35, #$1E
    STI $0B36, #$1E
    STI $0B37, #$1C
    STI $0B38, #$01
    STI $0B39, #$16
    STI $0B3A, #$1C
    STI $0B3B, #$01
    STI $0B3C, #$16
    STI $0B3D, #$1E
    STI $0B3E, #$1E
    STI $0B3F, #$1E
    STI $0B40, #$1E
    STI $0B41, #$1E
    STI $0B42, #$1E
    STI $0B43, #$1E
    STI $0B44, #$1E
    STI $0B45, #$1C
    STI $0B46, #$01
    STI $0B47, #$15
    STI $0B48, #$13
    STI $0B49, #$1A
    STI $0B4A, #$1B
    STI $0B4B, #$1B
    STI $0B4C, #$1B
    STI $0B4D, #$1B
    STI $0B4E, #$1B
    STI $0B4F, #$1B
    STI $0B50, #$1B
    STI $0B51, #$1B
    STI $0B52, #$1B
    STI $0B53, #$1B
    STI $0B54, #$1A
    STI $0B55, #$1B
    STI $0B56, #$1B
    STI $0B57, #$1A
    STI $0B58, #$1B
    STI $0B59, #$1B
    STI $0B5A, #$1B
    STI $0B5B, #$1B
    STI $0B5C, #$1B
    STI $0B5D, #$1B
    STI $0B5E, #$1B
    STI $0B5F, #$1B
    STI $0B60, #$1B
    STI $0B61, #$1B
    STI $0B62, #$1A
    STI $0B63, #$19
    RET


; ============================================================================
; PADROES GRAFICOS 8x7
; Em cada byte: D0 = pixel mais a esquerda, D7 = pixel mais a direita.
; ============================================================================

; Vazio
TILE_EMPTY_PATTERN:
    #d8 $00, $00, $00, $00, $00, $00, $00

; Pellet
TILE_DOT_PATTERN:
    #d8 $00, $00, $00, $08, $00, $00, $00

; Power pellet
TILE_POWER_PATTERN:
    #d8 $00, $18, $3C, $3C, $3C, $18, $00


; Pac-Man
PAC_CLOSED:
    #d8 $3C, $7E, $FF, $FF, $FF, $7E, $3C

PAC_RIGHT_OPEN:
    #d8 $3C, $7E, $1F, $07, $1F, $7E, $3C

PAC_LEFT_OPEN:
    #d8 $3C, $7E, $F8, $E0, $F8, $7E, $3C

PAC_UP_OPEN:
    #d8 $3C, $7E, $DB, $81, $C3, $7E, $3C

PAC_DOWN_OPEN:
    #d8 $3C, $7E, $C3, $81, $DB, $7E, $3C


; Fantasmas - variantes monocromaticas
GHOST_1_PATTERN:
    #d8 $3C, $7E, $DB, $FF, $FF, $A5, $A5

GHOST_2_PATTERN:
    #d8 $3C, $7E, $ED, $FF, $FF, $A5, $5A

GHOST_3_PATTERN:
    #d8 $3C, $7E, $B7, $FF, $FF, $5A, $A5

GHOST_4_PATTERN:
    #d8 $3C, $7E, $DB, $FF, $FF, $5A, $5A

GHOST_FRIGHT_PATTERN:
    #d8 $3C, $7E, $FF, $DB, $FF, $55, $AA


; ============================================================================
; DIGITOS 0..9
; ============================================================================

DIGIT_0:
    #d8 $3C, $42, $62, $52, $4A, $46, $3C
DIGIT_1:
    #d8 $18, $14, $10, $10, $10, $10, $7C
DIGIT_2:
    #d8 $3C, $42, $40, $30, $0C, $02, $7E
DIGIT_3:
    #d8 $3E, $40, $40, $3C, $40, $40, $3E
DIGIT_4:
    #d8 $30, $28, $24, $22, $7E, $20, $20
DIGIT_5:
    #d8 $7E, $02, $02, $3E, $40, $42, $3C
DIGIT_6:
    #d8 $38, $04, $02, $3E, $42, $42, $3C
DIGIT_7:
    #d8 $7E, $40, $20, $10, $08, $08, $08
DIGIT_8:
    #d8 $3C, $42, $42, $3C, $42, $42, $3C
DIGIT_9:
    #d8 $3C, $42, $42, $7C, $40, $20, $1C


; ============================================================================
; LETRAS NECESSARIAS
; ============================================================================

FONT_A:
    #d8 $18, $24, $42, $42, $7E, $42, $42

FONT_C:
    #d8 $3C, $42, $02, $02, $02, $42, $3C

FONT_E:
    #d8 $7E, $02, $02, $3E, $02, $02, $7E

FONT_G:
    #d8 $3C, $42, $02, $72, $42, $42, $3C

FONT_M:
    #d8 $42, $66, $5A, $5A, $42, $42, $42

FONT_O:
    #d8 $3C, $42, $42, $42, $42, $42, $3C

FONT_R:
    #d8 $3E, $42, $42, $3E, $12, $22, $42

FONT_S:
    #d8 $3C, $42, $02, $3C, $40, $42, $3C

FONT_V:
    #d8 $42, $42, $42, $42, $42, $24, $18


; ============================================================================
; PAREDES
;
; Low nibble:
;   bit0 N
;   bit1 E
;   bit2 S
;   bit3 W
; ============================================================================

WALL_0_PATTERN:
    #d8 $00, $00, $00, $08, $00, $00, $00

WALL_1_PATTERN:
    #d8 $08, $08, $08, $08, $00, $00, $00

WALL_2_PATTERN:
    #d8 $00, $00, $00, $F8, $00, $00, $00

WALL_3_PATTERN:
    #d8 $08, $08, $08, $F8, $00, $00, $00

WALL_4_PATTERN:
    #d8 $00, $00, $00, $08, $08, $08, $08

WALL_5_PATTERN:
    #d8 $08, $08, $08, $08, $08, $08, $08

WALL_6_PATTERN:
    #d8 $00, $00, $00, $F8, $08, $08, $08

WALL_7_PATTERN:
    #d8 $08, $08, $08, $F8, $08, $08, $08

WALL_8_PATTERN:
    #d8 $00, $00, $00, $0F, $00, $00, $00

WALL_9_PATTERN:
    #d8 $08, $08, $08, $0F, $00, $00, $00

WALL_A_PATTERN:
    #d8 $00, $00, $00, $FF, $00, $00, $00

WALL_B_PATTERN:
    #d8 $08, $08, $08, $FF, $00, $00, $00

WALL_C_PATTERN:
    #d8 $00, $00, $00, $0F, $08, $08, $08

WALL_D_PATTERN:
    #d8 $08, $08, $08, $0F, $08, $08, $08

WALL_E_PATTERN:
    #d8 $00, $00, $00, $FF, $08, $08, $08

WALL_F_PATTERN:
    #d8 $08, $08, $08, $FF, $08, $08, $08


; ============================================================================
; Protecao no fim do cartucho
; ============================================================================

#addr 0xEFFD
    JMP INICIO
