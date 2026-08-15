#include "../wall8.cpu"

; ============================================================================
; WALL-8 - SNAKE ARCADE / JOGO DA COBRINHA
; ============================================================================
;
; Cartucho:  $A000-$EFFF
; Video:     grafico monocromatico 320x240
; Grade:     40x30 celulas de 8x8 pixels
; Area util: X=1..38, Y=3..28 (HUD em Y=0, moldura superior em Y=2)
;
; Controles ASCII:
;   W / w = cima
;   A / a = esquerda
;   S / s = baixo
;   D / d = direita
;   P / p = pausa
;   R / r = reiniciar
;   Q / q = sair para a BIOS
;
; HUD na VGA: SCORE, LEN e LV. A pontuacao tambem vai aos 4 displays fisicos.
;
; A BIOS deve entrar no cartucho usando CALL $A000. O programa nao altera
; o Stack Pointer, preservando o endereco de retorno colocado pela BIOS.
;
; A documentacao atual nao define codigos para as setas. Por isso esta versao
; usa apenas teclas ASCII, que estao definidas de forma inequívoca.
; ============================================================================

#bankdef cart {
    #addr 0xA000
    #size 0x5000
    #outp 0x0000
}

#bank cart
#addr 0xA000


; ============================================================================
; I/O DO WALL-8
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
; COMANDOS E BITS
; ============================================================================

VIDEO_CLEAR          = $00
MODE_TEXT_40X30      = $11
MODE_GFX_320X240     = $12
VRAM_READ            = $20

VIDEO_BUSY_MASK      = $01
VIDEO_FRAME_MASK     = $08
KEY_READY_MASK       = $80

DIR_UP               = $00
DIR_RIGHT            = $01
DIR_DOWN             = $02
DIR_LEFT             = $03

CELL_EMPTY           = $00
CELL_SNAKE           = $FF
CELL_FOOD            = $AA
CELL_GAME_OVER       = $55

GRID_RIGHT_WALL      = $27       ; 39
GRID_BOTTOM_WALL     = $1D       ; 29
GRID_WIDTH_INTERIOR  = $26       ; 38
GRID_HEIGHT_INTERIOR = $1C       ; 28

INITIAL_LENGTH       = $05
MAX_LENGTH           = $80       ; 128 segmentos
INITIAL_DELAY        = $08
MIN_DELAY            = $02

; HUD ocupa as linhas de grade 0 e 1.
; A parede superior do campo fica em Y=2; area jogavel Y=3..28.
GRID_TOP_WALL        = $02
GRID_PLAY_TOP        = $03

; Tons reais do WALL (TONE_EN = bit 1).
NOTE_C5              = $02
NOTE_B4              = $06
NOTE_A4              = $0A
NOTE_G4              = $0E
NOTE_F4              = $12
NOTE_E4              = $16
NOTE_D4              = $1A
NOTE_C4              = $1E


; ============================================================================
; RAM DE ESTADO
; ============================================================================

DIR_CURRENT       = $0200
DIR_NEXT          = $0201

HEAD_X            = $0202
HEAD_Y            = $0203
NEW_X             = $0204
NEW_Y             = $0205

FOOD_X            = $0206
FOOD_Y            = $0207

SNAKE_LENGTH      = $0208
SCORE             = $0209
MOVE_DELAY        = $020A
FRAME_ACCUM       = $020B
LAST_FRAME        = $020C
RNG_STATE         = $020D

GROW_FLAG         = $020E
COLLISION_FLAG    = $020F
GAME_OVER_FLAG    = $0210
PAUSED_FLAG       = $0211
RESTART_FLAG      = $0212
EXIT_FLAG         = $0213
WIN_FLAG          = $0214

TAIL_X            = $0215
TAIL_Y            = $0216

LOOP_COUNT        = $0217
SHIFT_COUNT       = $0218
COLLISION_COUNT   = $0219

DRAW_X            = $021A
DRAW_Y            = $021B
DRAW_VALUE        = $021C
DRAW_PIXEL_Y      = $021D
DRAW_ROWS         = $021E

; HUD / animacao.
SCORE_ONES        = $021F
SCORE_TENS        = $0220
SCORE_HUNDREDS    = $0221
SCORE_THOUSANDS   = $0222
LEN_ONES          = $0223
LEN_TENS          = $0224
LEN_HUNDREDS      = $0225
LEVEL_VALUE       = $0226
ANIM_FLAG         = $0227

; Vetor intercalado:
;   segmento 0: X,Y
;   segmento 1: X,Y
;   ...
; 256 bytes = 128 segmentos.
SNAKE_BASE        = $0400


; ============================================================================
; ENTRADA DO CARTUCHO
; ============================================================================

INICIO:
GAME_START:

    ; Nao inicializa SP. A BIOS entrou com CALL $A000.

    CALL VIDEO_WAIT

    ; Desliga tom e ruido.
    STI SOUND_CFG, #$00

    STI GAME_OVER_FLAG, #$00
    STI PAUSED_FLAG,    #$00
    STI RESTART_FLAG,   #$00
    STI EXIT_FLAG,      #$00
    STI WIN_FLAG,       #$00
    STI GROW_FLAG,      #$00
    STI COLLISION_FLAG, #$00
    STI FRAME_ACCUM,    #$00

    STI DIR_CURRENT, #$01
    STI DIR_NEXT,    #$01

    STI HEAD_X, #$14             ; 20
    STI HEAD_Y, #$0F             ; 15

    STI SNAKE_LENGTH, #$05
    STI SCORE,        #$00
    STI MOVE_DELAY,   #$08

    STI SCORE_ONES,      #$00
    STI SCORE_TENS,      #$00
    STI SCORE_HUNDREDS,  #$00
    STI SCORE_THOUSANDS, #$00

    STI LEN_ONES,     #$05
    STI LEN_TENS,     #$00
    STI LEN_HUNDREDS, #$00
    STI LEVEL_VALUE,  #$01
    STI ANIM_FLAG,    #$00

    STI DISPLAY_LOW,  #$00
    STI DISPLAY_HIGH, #$00

    ; Semente usa o estado atual de video e do sistema.
    LDA VIDEO_STATUS
    AND A, #$08
    STA LAST_FRAME
    XOR A, #$A7
    LDB SYSTEM_STATUS
    XOR A, B
    CMP A, #$00
    JNZ RNG_SEED_OK
    LDA #$A7

RNG_SEED_OK:
    STA RNG_STATE

    ; Seleciona o modo e limpa toda a VRAM grafica.
    STI VIDEO_CMD, #$12
    CALL VIDEO_WAIT

    STI VIDEO_CMD, #$00
    CALL VIDEO_WAIT

    CALL INITIALIZE_SNAKE
    CALL DRAW_HUD
    CALL DRAW_BORDER
    CALL DRAW_INITIAL_SNAKE
    CALL GENERATE_FOOD
    CALL SOUND_START


; ============================================================================
; LOOP PRINCIPAL
; ============================================================================

MAIN_LOOP:

    CALL WAIT_ONE_FRAME

    LDA EXIT_FLAG
    CMP A, #$01
    JZ EXIT_GAME

    LDA RESTART_FLAG
    CMP A, #$01
    JZ GAME_START

    LDA PAUSED_FLAG
    CMP A, #$01
    JZ MAIN_PAUSED

    LDA FRAME_ACCUM
    INC A
    STA FRAME_ACCUM

    LDB MOVE_DELAY
    CMP A, B
    JNZ MAIN_LOOP

    STI FRAME_ACCUM, #$00

    CALL GAME_STEP

    LDA GAME_OVER_FLAG
    CMP A, #$01
    JZ GAME_OVER

    JMP MAIN_LOOP


MAIN_PAUSED:

    STI FRAME_ACCUM, #$00
    JMP MAIN_LOOP


; ============================================================================
; UM PASSO COMPLETO DO JOGO
; ============================================================================

GAME_STEP:

    ; A direcao solicitada passa a ser a direcao atual.
    LDA DIR_NEXT
    STA DIR_CURRENT

    CALL COMPUTE_NEW_HEAD
    CALL CHECK_WALL_COLLISION

    LDA COLLISION_FLAG
    CMP A, #$01
    JZ STEP_COLLISION

    ; Determina se a nova cabeca esta sobre a comida.
    STI GROW_FLAG, #$00

    LDA NEW_X
    LDB FOOD_X
    CMP A, B
    JNZ STEP_NOT_FOOD

    LDA NEW_Y
    LDB FOOD_Y
    CMP A, B
    JNZ STEP_NOT_FOOD

    STI GROW_FLAG, #$01


STEP_NOT_FOOD:

    ; Se nao crescer, a cauda sera removida neste passo. Nesse caso,
    ; ela nao participa da colisao: entrar na celula que a cauda esta
    ; abandonando e permitido.
    LDA SNAKE_LENGTH
    STA COLLISION_COUNT

    LDA GROW_FLAG
    CMP A, #$01
    JZ STEP_COLLISION_COUNT_READY

    LDA COLLISION_COUNT
    DEC A
    STA COLLISION_COUNT


STEP_COLLISION_COUNT_READY:

    CALL CHECK_POINT_ON_SNAKE

    LDA COLLISION_FLAG
    CMP A, #$01
    JZ STEP_COLLISION

    CALL SAVE_TAIL
    CALL SHIFT_SNAKE

    ; Grava a nova cabeca no segmento zero.
    PTR SNAKE_BASE

    LDA NEW_X
    STA [PTR+]

    LDA NEW_Y
    STA [PTR]

    ; Sem crescimento, apaga primeiro a cauda antiga.
    ; Essa ordem permite mover a cabeca para a antiga celula da cauda.
    LDA GROW_FLAG
    CMP A, #$01
    JZ STEP_KEEP_TAIL

    LDA TAIL_X
    STA DRAW_X

    LDA TAIL_Y
    STA DRAW_Y

    STI DRAW_VALUE, #$00
    CALL DRAW_CELL


STEP_KEEP_TAIL:

    ; A antiga cabeca vira um segmento arredondado do corpo.
    LDA HEAD_X
    STA DRAW_X
    LDA HEAD_Y
    STA DRAW_Y
    PTR SPRITE_BODY
    CALL DRAW_SPRITE

    ; Alterna a animacao da boca a cada movimento.
    LDA ANIM_FLAG
    XOR A, #$01
    STA ANIM_FLAG

    ; Desenha a nova cabeca com orientacao e animacao.
    LDA NEW_X
    STA HEAD_X
    STA DRAW_X

    LDA NEW_Y
    STA HEAD_Y
    STA DRAW_Y

    CALL DRAW_HEAD

    LDA GROW_FLAG
    CMP A, #$01
    JNZ STEP_DONE

    ; Crescimento e pontuacao. SCORE binario continua sendo usado
    ; para a progressao de velocidade; o HUD usa decimal separado.
    LDA SNAKE_LENGTH
    INC A
    STA SNAKE_LENGTH

    CALL INC_LENGTH_DECIMAL
    CALL ADD_SCORE_10
    CALL DRAW_LENGTH
    CALL DRAW_SCORE
    CALL UPDATE_PHYSICAL_SCORE

    LDA SCORE
    INC A
    STA SCORE

    CALL BEEP_FOOD

    ; A cada quatro comidas, reduz um quadro do atraso ate o minimo.
    TEST A, #$03
    JNZ STEP_SPEED_DONE

    LDA MOVE_DELAY
    CMP A, #$02
    JZ STEP_SPEED_DONE

    DEC A
    STA MOVE_DELAY

    LDA LEVEL_VALUE
    INC A
    STA LEVEL_VALUE
    CALL DRAW_LEVEL
    CALL BEEP_LEVEL


STEP_SPEED_DONE:

    ; Ao completar os 128 segmentos disponiveis, encerra como vitoria.
    LDA SNAKE_LENGTH
    CMP A, #$80
    JNZ STEP_NEW_FOOD

    STI WIN_FLAG,       #$01
    STI GAME_OVER_FLAG, #$01
    RET


STEP_NEW_FOOD:

    CALL GENERATE_FOOD


STEP_DONE:

    RET


STEP_COLLISION:

    STI GAME_OVER_FLAG, #$01
    RET


; ============================================================================
; MOVIMENTO DA CABECA
; ============================================================================

COMPUTE_NEW_HEAD:

    LDA HEAD_X
    STA NEW_X

    LDA HEAD_Y
    STA NEW_Y

    LDA DIR_CURRENT

    CMP A, #$00
    JZ MOVE_UP

    CMP A, #$01
    JZ MOVE_RIGHT

    CMP A, #$02
    JZ MOVE_DOWN

    ; DIR_LEFT
    LDA NEW_X
    DEC A
    STA NEW_X
    RET


MOVE_UP:

    LDA NEW_Y
    DEC A
    STA NEW_Y
    RET


MOVE_RIGHT:

    LDA NEW_X
    INC A
    STA NEW_X
    RET


MOVE_DOWN:

    LDA NEW_Y
    INC A
    STA NEW_Y
    RET


; ============================================================================
; COLISOES
; ============================================================================

CHECK_WALL_COLLISION:

    STI COLLISION_FLAG, #$00

    LDA NEW_X
    CMP A, #$00
    JZ WALL_COLLISION_FOUND

    CMP A, #$27
    JZ WALL_COLLISION_FOUND

    LDA NEW_Y
    CMP A, #GRID_TOP_WALL
    JZ WALL_COLLISION_FOUND

    CMP A, #$1D
    JZ WALL_COLLISION_FOUND

    RET


WALL_COLLISION_FOUND:

    STI COLLISION_FLAG, #$01
    RET


; Verifica NEW_X/NEW_Y contra os primeiros COLLISION_COUNT segmentos.
CHECK_POINT_ON_SNAKE:

    STI COLLISION_FLAG, #$00
    PTR SNAKE_BASE


CHECK_SNAKE_LOOP:

    LDA COLLISION_COUNT
    CMP A, #$00
    JZ CHECK_SNAKE_DONE

    ; Compara X.
    LDA [PTR+]
    LDB NEW_X
    CMP A, B
    JNZ CHECK_SNAKE_SKIP_Y

    ; X igual: compara Y.
    LDA [PTR+]
    LDB NEW_Y
    CMP A, B
    JZ CHECK_SNAKE_HIT

    JMP CHECK_SNAKE_NEXT


CHECK_SNAKE_SKIP_Y:

    ; Pula o byte Y do segmento cujo X era diferente.
    INC PTR


CHECK_SNAKE_NEXT:

    LDA COLLISION_COUNT
    DEC A
    STA COLLISION_COUNT
    JMP CHECK_SNAKE_LOOP


CHECK_SNAKE_HIT:

    STI COLLISION_FLAG, #$01


CHECK_SNAKE_DONE:

    RET


; ============================================================================
; MANIPULACAO DO VETOR DA COBRINHA
; ============================================================================

INITIALIZE_SNAKE:

    ; Cabeca em (20,15), corpo seguindo para a esquerda.
    PTR SNAKE_BASE

    LDA #$14
    STA [PTR+]
    LDA #$0F
    STA [PTR+]

    LDA #$13
    STA [PTR+]
    LDA #$0F
    STA [PTR+]

    LDA #$12
    STA [PTR+]
    LDA #$0F
    STA [PTR+]

    LDA #$11
    STA [PTR+]
    LDA #$0F
    STA [PTR+]

    LDA #$10
    STA [PTR+]
    LDA #$0F
    STA [PTR]

    RET


SAVE_TAIL:

    PTR SNAKE_BASE

    LDA SNAKE_LENGTH
    DEC A
    STA LOOP_COUNT


SAVE_TAIL_ADVANCE:

    LDA LOOP_COUNT
    CMP A, #$00
    JZ SAVE_TAIL_READ

    INC PTR
    INC PTR

    DEC A
    STA LOOP_COUNT
    JMP SAVE_TAIL_ADVANCE


SAVE_TAIL_READ:

    LDA [PTR+]
    STA TAIL_X

    LDA [PTR]
    STA TAIL_Y

    RET


; Desloca todos os segmentos uma posicao para tras.
;
; Antes:
;   [0] cabeca, [1], [2] ... [length-1] cauda
;
; Depois:
;   [1] = antigo [0]
;   [2] = antigo [1]
;   ...
;   [length] = antiga cauda
;
; O segmento extra [length] so passa a fazer parte da cobrinha quando cresce.
SHIFT_SNAKE:

    PTR SNAKE_BASE

    LDA SNAKE_LENGTH
    STA LOOP_COUNT
    STA SHIFT_COUNT


SHIFT_ADVANCE_TO_END:

    LDA LOOP_COUNT
    CMP A, #$00
    JZ SHIFT_COPY_LOOP

    INC PTR
    INC PTR

    DEC A
    STA LOOP_COUNT
    JMP SHIFT_ADVANCE_TO_END


SHIFT_COPY_LOOP:

    LDA SHIFT_COUNT
    CMP A, #$00
    JZ SHIFT_DONE

    ; PTR aponta para o X do destino.
    ; Copia primeiro Y da origem para Y do destino.
    DEC PTR
    LDA [PTR]
    INC PTR
    INC PTR
    STA [PTR]

    ; Copia X da origem para X do destino.
    DEC PTR
    DEC PTR
    DEC PTR
    LDA [PTR]
    INC PTR
    INC PTR
    STA [PTR]

    ; Volta para o X que sera o proximo destino.
    DEC PTR
    DEC PTR

    LDA SHIFT_COUNT
    DEC A
    STA SHIFT_COUNT
    JMP SHIFT_COPY_LOOP


SHIFT_DONE:

    RET


; ============================================================================
; COMIDA E NUMERO PSEUDOALEATORIO
; ============================================================================

GENERATE_FOOD:

FOOD_RETRY:

    CALL RANDOM_INTERIOR_X
    STA NEW_X

    CALL RANDOM_INTERIOR_Y
    STA NEW_Y

    LDA SNAKE_LENGTH
    STA COLLISION_COUNT
    CALL CHECK_POINT_ON_SNAKE

    LDA COLLISION_FLAG
    CMP A, #$01
    JZ FOOD_RETRY

    LDA NEW_X
    STA FOOD_X
    STA DRAW_X

    LDA NEW_Y
    STA FOOD_Y
    STA DRAW_Y

    PTR SPRITE_FOOD
    CALL DRAW_SPRITE

    RET


; LFSR de 8 bits. Polinomio representado pela mascara $B8.
; Entrada: RNG_STATE
; Saida:   A e RNG_STATE com o novo valor.
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

    ; Evita estado travado em zero.
    LDA #$A7


RNG_STORE:

    STA RNG_STATE
    RET


; Retorna A em 1..38.
RANDOM_INTERIOR_X:

    CALL RNG_NEXT
    AND A, #$3F


RANDOM_X_REDUCE:

    CMP A, #$26
    JN RANDOM_X_READY

    SUB A, #$26
    JMP RANDOM_X_REDUCE


RANDOM_X_READY:

    ADD A, #$01
    RET


; Retorna A em 3..28 (26 linhas jogaveis abaixo do HUD).
RANDOM_INTERIOR_Y:

    CALL RNG_NEXT
    AND A, #$3F


RANDOM_Y_REDUCE:

    CMP A, #$1A
    JN RANDOM_Y_READY

    SUB A, #$1A
    JMP RANDOM_Y_REDUCE


RANDOM_Y_READY:

    ADD A, #$03
    RET


; ============================================================================
; VIDEO
; ============================================================================

VIDEO_WAIT:

    LDA VIDEO_STATUS
    TEST A, #$01
    JNZ VIDEO_WAIT
    RET


; Desenha uma celula de 8x8 pixels com o mesmo byte nas 8 linhas.
;
; Entrada em RAM:
;   DRAW_X     = coluna de byte 0..39
;   DRAW_Y     = linha da grade 0..29
;   DRAW_VALUE = byte repetido nas oito linhas
DRAW_CELL:

    LDA DRAW_Y
    SHL A
    SHL A
    SHL A
    STA DRAW_PIXEL_Y

    STI DRAW_ROWS, #$08

DRAW_CELL_ROW:

    CALL VIDEO_WAIT

    LDA DRAW_X
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
    JNZ DRAW_CELL_ROW

    RET


; Desenha um sprite 8x8. PTR deve apontar para 8 bytes, um por linha.
; DRAW_X/DRAW_Y selecionam a celula.
DRAW_SPRITE:

    LDA DRAW_Y
    SHL A
    SHL A
    SHL A
    STA DRAW_PIXEL_Y

    STI DRAW_ROWS, #$08

DRAW_SPRITE_ROW:

    CALL VIDEO_WAIT

    LDA DRAW_X
    STA VIDEO_X

    LDA DRAW_PIXEL_Y
    STA VIDEO_Y

    LDA [PTR+]
    STA VIDEO_DATA

    LDA DRAW_PIXEL_Y
    INC A
    STA DRAW_PIXEL_Y

    LDA DRAW_ROWS
    DEC A
    STA DRAW_ROWS
    JNZ DRAW_SPRITE_ROW

    RET


; Cabeca animada: frame fechado alterna com frame aberto direcional.
DRAW_HEAD:

    LDA ANIM_FLAG
    CMP A, #$00
    JNZ DRAW_HEAD_OPEN

    PTR SPRITE_HEAD_CLOSED
    JMP DRAW_SPRITE

DRAW_HEAD_OPEN:

    LDA DIR_CURRENT
    CMP A, #DIR_UP
    JZ DRAW_HEAD_UP
    CMP A, #DIR_RIGHT
    JZ DRAW_HEAD_RIGHT
    CMP A, #DIR_DOWN
    JZ DRAW_HEAD_DOWN

DRAW_HEAD_LEFT:
    PTR SPRITE_HEAD_LEFT
    JMP DRAW_SPRITE

DRAW_HEAD_UP:
    PTR SPRITE_HEAD_UP
    JMP DRAW_SPRITE

DRAW_HEAD_RIGHT:
    PTR SPRITE_HEAD_RIGHT
    JMP DRAW_SPRITE

DRAW_HEAD_DOWN:
    PTR SPRITE_HEAD_DOWN
    JMP DRAW_SPRITE


; Campo com HUD em cima e moldura fina.
DRAW_BORDER:

    ; Parede superior em Y=2.
    STI DRAW_Y, #GRID_TOP_WALL
    STI LOOP_COUNT, #$00

BORDER_TOP_LOOP:

    LDA LOOP_COUNT
    CMP A, #$28
    JZ BORDER_BOTTOM_BEGIN

    STA DRAW_X
    PTR SPRITE_WALL_H
    CALL DRAW_SPRITE

    LDA LOOP_COUNT
    INC A
    STA LOOP_COUNT
    JMP BORDER_TOP_LOOP

BORDER_BOTTOM_BEGIN:

    STI DRAW_Y, #$1D
    STI LOOP_COUNT, #$00

BORDER_BOTTOM_LOOP:

    LDA LOOP_COUNT
    CMP A, #$28
    JZ BORDER_SIDES_BEGIN

    STA DRAW_X
    PTR SPRITE_WALL_H
    CALL DRAW_SPRITE

    LDA LOOP_COUNT
    INC A
    STA LOOP_COUNT
    JMP BORDER_BOTTOM_LOOP

BORDER_SIDES_BEGIN:

    STI LOOP_COUNT, #GRID_PLAY_TOP

BORDER_SIDES_LOOP:

    LDA LOOP_COUNT
    CMP A, #$1D
    JZ BORDER_DONE

    STA DRAW_Y

    STI DRAW_X, #$00
    PTR SPRITE_WALL_V
    CALL DRAW_SPRITE

    STI DRAW_X, #$27
    PTR SPRITE_WALL_V
    CALL DRAW_SPRITE

    LDA LOOP_COUNT
    INC A
    STA LOOP_COUNT
    JMP BORDER_SIDES_LOOP

BORDER_DONE:

    RET


; Desenho inicial conhecido: cabeca em 20,15 e quatro corpos a esquerda.
DRAW_INITIAL_SNAKE:

    STI DRAW_Y, #$0F

    STI DRAW_X, #$10
    PTR SPRITE_BODY
    CALL DRAW_SPRITE

    STI DRAW_X, #$11
    PTR SPRITE_BODY
    CALL DRAW_SPRITE

    STI DRAW_X, #$12
    PTR SPRITE_BODY
    CALL DRAW_SPRITE

    STI DRAW_X, #$13
    PTR SPRITE_BODY
    CALL DRAW_SPRITE

    STI DRAW_X, #$14
    CALL DRAW_HEAD

    RET


; ---------------------------------------------------------------------------
; HUD: SCORE 0000 | LEN 005 | LV 1 | SNAKE
; ---------------------------------------------------------------------------
DRAW_HUD:

    STI DRAW_Y, #$00

    ; SCORE
    STI DRAW_X, #$01
    PTR GLYPH_S
    CALL DRAW_SPRITE
    STI DRAW_X, #$02
    PTR GLYPH_C
    CALL DRAW_SPRITE
    STI DRAW_X, #$03
    PTR GLYPH_O
    CALL DRAW_SPRITE
    STI DRAW_X, #$04
    PTR GLYPH_R
    CALL DRAW_SPRITE
    STI DRAW_X, #$05
    PTR GLYPH_E
    CALL DRAW_SPRITE

    ; LEN
    STI DRAW_X, #$0D
    PTR GLYPH_L
    CALL DRAW_SPRITE
    STI DRAW_X, #$0E
    PTR GLYPH_E
    CALL DRAW_SPRITE
    STI DRAW_X, #$0F
    PTR GLYPH_N
    CALL DRAW_SPRITE

    ; LV
    STI DRAW_X, #$16
    PTR GLYPH_L
    CALL DRAW_SPRITE
    STI DRAW_X, #$17
    PTR GLYPH_V
    CALL DRAW_SPRITE

    ; Titulo SNAKE
    STI DRAW_X, #$22
    PTR GLYPH_S
    CALL DRAW_SPRITE
    STI DRAW_X, #$23
    PTR GLYPH_N
    CALL DRAW_SPRITE
    STI DRAW_X, #$24
    PTR GLYPH_A
    CALL DRAW_SPRITE
    STI DRAW_X, #$25
    PTR GLYPH_K
    CALL DRAW_SPRITE
    STI DRAW_X, #$26
    PTR GLYPH_E
    CALL DRAW_SPRITE

    CALL DRAW_SCORE
    CALL DRAW_LENGTH
    CALL DRAW_LEVEL
    CALL UPDATE_PHYSICAL_SCORE
    RET


DRAW_SCORE:

    STI DRAW_Y, #$00

    STI DRAW_X, #$07
    LDA SCORE_THOUSANDS
    CALL DRAW_DIGIT_A

    STI DRAW_X, #$08
    LDA SCORE_HUNDREDS
    CALL DRAW_DIGIT_A

    STI DRAW_X, #$09
    LDA SCORE_TENS
    CALL DRAW_DIGIT_A

    STI DRAW_X, #$0A
    LDA SCORE_ONES
    CALL DRAW_DIGIT_A

    RET


DRAW_LENGTH:

    STI DRAW_Y, #$00

    STI DRAW_X, #$11
    LDA LEN_HUNDREDS
    CALL DRAW_DIGIT_A

    STI DRAW_X, #$12
    LDA LEN_TENS
    CALL DRAW_DIGIT_A

    STI DRAW_X, #$13
    LDA LEN_ONES
    CALL DRAW_DIGIT_A

    RET


DRAW_LEVEL:

    STI DRAW_Y, #$00
    STI DRAW_X, #$19
    LDA LEVEL_VALUE
    CALL DRAW_DIGIT_A
    RET


DRAW_DIGIT_A:

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

DIGIT_9:
    PTR GLYPH_9
    JMP DRAW_SPRITE
DIGIT_8:
    PTR GLYPH_8
    JMP DRAW_SPRITE
DIGIT_7:
    PTR GLYPH_7
    JMP DRAW_SPRITE
DIGIT_6:
    PTR GLYPH_6
    JMP DRAW_SPRITE
DIGIT_5:
    PTR GLYPH_5
    JMP DRAW_SPRITE
DIGIT_4:
    PTR GLYPH_4
    JMP DRAW_SPRITE
DIGIT_3:
    PTR GLYPH_3
    JMP DRAW_SPRITE
DIGIT_2:
    PTR GLYPH_2
    JMP DRAW_SPRITE
DIGIT_1:
    PTR GLYPH_1
    JMP DRAW_SPRITE
DIGIT_0:
    PTR GLYPH_0
    JMP DRAW_SPRITE


; Score = 10 pontos por comida.
ADD_SCORE_10:

    LDA SCORE_TENS
    INC A
    CMP A, #$0A
    JNZ SCORE_STORE_TENS

    LDA #$00
    STA SCORE_TENS

    LDA SCORE_HUNDREDS
    INC A
    CMP A, #$0A
    JNZ SCORE_STORE_HUNDREDS

    LDA #$00
    STA SCORE_HUNDREDS

    LDA SCORE_THOUSANDS
    INC A
    CMP A, #$0A
    JNZ SCORE_STORE_THOUSANDS
    LDA #$00

SCORE_STORE_THOUSANDS:
    STA SCORE_THOUSANDS
    RET

SCORE_STORE_HUNDREDS:
    STA SCORE_HUNDREDS
    RET

SCORE_STORE_TENS:
    STA SCORE_TENS
    RET


INC_LENGTH_DECIMAL:

    LDA LEN_ONES
    INC A
    CMP A, #$0A
    JNZ LENGTH_STORE_ONES

    LDA #$00
    STA LEN_ONES

    LDA LEN_TENS
    INC A
    CMP A, #$0A
    JNZ LENGTH_STORE_TENS

    LDA #$00
    STA LEN_TENS

    LDA LEN_HUNDREDS
    INC A
    STA LEN_HUNDREDS
    RET

LENGTH_STORE_TENS:
    STA LEN_TENS
    RET

LENGTH_STORE_ONES:
    STA LEN_ONES
    RET


; Empacota os quatro digitos decimais em dois bytes HEX para o display fisico.
UPDATE_PHYSICAL_SCORE:

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


; ============================================================================
; SINCRONIZACAO E TECLADO
; ============================================================================

WAIT_ONE_FRAME:

WAIT_FRAME_LOOP:

    CALL POLL_KEYBOARD

    LDA VIDEO_STATUS
    AND A, #$08

    LDB LAST_FRAME
    CMP A, B
    JZ WAIT_FRAME_LOOP

    STA LAST_FRAME

    ; Faz o LFSR evoluir mesmo quando nenhuma comida e criada.
    CALL RNG_NEXT
    RET


POLL_KEYBOARD:

    LDA SYSTEM_STATUS
    TEST A, #$80
    JZ KEY_DONE

    ; A leitura de KEY_DATA consome o byte pronto no teclado.
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

    ; Nao permite inverter de baixo diretamente para cima.
    LDA DIR_CURRENT
    CMP A, #$02
    JZ KEY_DONE

    STI DIR_NEXT, #$00
    RET


KEY_DOWN:

    LDA DIR_CURRENT
    CMP A, #$00
    JZ KEY_DONE

    STI DIR_NEXT, #$02
    RET


KEY_LEFT:

    LDA DIR_CURRENT
    CMP A, #$01
    JZ KEY_DONE

    STI DIR_NEXT, #$03
    RET


KEY_RIGHT:

    LDA DIR_CURRENT
    CMP A, #$03
    JZ KEY_DONE

    STI DIR_NEXT, #$01
    RET


KEY_PAUSE:

    LDA PAUSED_FLAG
    XOR A, #$01
    STA PAUSED_FLAG

    CMP A, #$01
    JZ KEY_PAUSE_ON

    ; Remove o indicador P do HUD.
    STI DRAW_X, #$1E
    STI DRAW_Y, #$00
    STI DRAW_VALUE, #$00
    CALL DRAW_CELL
    CALL BEEP_PAUSE
    RET

KEY_PAUSE_ON:

    STI DRAW_X, #$1E
    STI DRAW_Y, #$00
    PTR GLYPH_P
    CALL DRAW_SPRITE
    CALL BEEP_PAUSE
    RET


KEY_RESTART:

    STI RESTART_FLAG, #$01
    RET


KEY_EXIT:

    STI EXIT_FLAG, #$01


KEY_DONE:

    RET


; ============================================================================
; SOM
; ============================================================================

; Um tick do TIMER_1MS (~0,9765625 ms). As flags sao retidas.
WAIT_1MS:

    STI SYSTEM_STATUS, #$00

WAIT_1MS_LOOP:

    LDA SYSTEM_STATUS
    TEST A, #$01
    JZ WAIT_1MS_LOOP
    RET


; Espera B ticks do timer de 1 ms.
WAIT_TICKS_B:

    CALL WAIT_1MS
    DEC B
    JNZ WAIT_TICKS_B
    RET


SOUND_START:

    STI SOUND_CFG, #NOTE_C4
    LDB #$28
    CALL WAIT_TICKS_B
    STI SOUND_CFG, #NOTE_E4
    LDB #$28
    CALL WAIT_TICKS_B
    STI SOUND_CFG, #NOTE_G4
    LDB #$28
    CALL WAIT_TICKS_B
    STI SOUND_CFG, #NOTE_C5
    LDB #$50
    CALL WAIT_TICKS_B
    STI SOUND_CFG, #$00
    RET


BEEP_FOOD:

    STI SOUND_CFG, #NOTE_G4
    LDB #$18
    CALL WAIT_TICKS_B
    STI SOUND_CFG, #NOTE_C5
    LDB #$28
    CALL WAIT_TICKS_B
    STI SOUND_CFG, #$00
    RET


BEEP_LEVEL:

    STI SOUND_CFG, #NOTE_C4
    LDB #$18
    CALL WAIT_TICKS_B
    STI SOUND_CFG, #NOTE_E4
    LDB #$18
    CALL WAIT_TICKS_B
    STI SOUND_CFG, #NOTE_G4
    LDB #$18
    CALL WAIT_TICKS_B
    STI SOUND_CFG, #NOTE_C5
    LDB #$30
    CALL WAIT_TICKS_B
    STI SOUND_CFG, #$00
    RET


BEEP_PAUSE:

    STI SOUND_CFG, #NOTE_E4
    LDB #$30
    CALL WAIT_TICKS_B
    STI SOUND_CFG, #$00
    RET


SOUND_DEATH:

    ; Queda de tons com ruido nos dois ultimos passos.
    STI SOUND_CFG, #NOTE_C5
    LDB #$50
    CALL WAIT_TICKS_B
    STI SOUND_CFG, #NOTE_A4
    LDB #$50
    CALL WAIT_TICKS_B
    STI SOUND_CFG, #NOTE_F4
    LDB #$50
    CALL WAIT_TICKS_B
    STI SOUND_CFG, #$1B       ; D4 + NOISE
    LDB #$60
    CALL WAIT_TICKS_B
    STI SOUND_CFG, #$1F       ; C4 + NOISE
    LDB #$78
    CALL WAIT_TICKS_B
    STI SOUND_CFG, #$00
    RET


SOUND_WIN:

    STI SOUND_CFG, #NOTE_C4
    LDB #$30
    CALL WAIT_TICKS_B
    STI SOUND_CFG, #NOTE_E4
    LDB #$30
    CALL WAIT_TICKS_B
    STI SOUND_CFG, #NOTE_G4
    LDB #$30
    CALL WAIT_TICKS_B
    STI SOUND_CFG, #NOTE_C5
    LDB #$A0
    CALL WAIT_TICKS_B
    STI SOUND_CFG, #$00
    RET


; ============================================================================
; GAME OVER / VITORIA
; ============================================================================

GAME_OVER:

    STI PAUSED_FLAG, #$00
    STI FRAME_ACCUM, #$00

    LDA WIN_FLAG
    CMP A, #$01
    JZ GAME_WIN_SEQUENCE

    CALL SOUND_DEATH
    CALL DRAW_GAME_OVER_TEXT
    JMP GAME_OVER_LOOP

GAME_WIN_SEQUENCE:

    CALL SOUND_WIN
    CALL DRAW_YOU_WIN_TEXT

GAME_OVER_LOOP:

    CALL WAIT_ONE_FRAME

    LDA EXIT_FLAG
    CMP A, #$01
    JZ EXIT_GAME

    LDA RESTART_FLAG
    CMP A, #$01
    JZ GAME_START

    JMP GAME_OVER_LOOP


; Limpa uma faixa central de 12 celulas para a mensagem final.
CLEAR_MESSAGE_BAR:

    STI DRAW_Y, #$0E
    STI LOOP_COUNT, #$0E
    STI DRAW_VALUE, #$00

CLEAR_MESSAGE_LOOP:

    LDA LOOP_COUNT
    CMP A, #$1A
    JZ CLEAR_MESSAGE_DONE
    STA DRAW_X
    CALL DRAW_CELL
    LDA LOOP_COUNT
    INC A
    STA LOOP_COUNT
    JMP CLEAR_MESSAGE_LOOP

CLEAR_MESSAGE_DONE:
    RET


DRAW_GAME_OVER_TEXT:

    CALL CLEAR_MESSAGE_BAR
    STI DRAW_Y, #$0E

    STI DRAW_X, #$0F
    PTR GLYPH_G
    CALL DRAW_SPRITE
    STI DRAW_X, #$10
    PTR GLYPH_A
    CALL DRAW_SPRITE
    STI DRAW_X, #$11
    PTR GLYPH_M
    CALL DRAW_SPRITE
    STI DRAW_X, #$12
    PTR GLYPH_E
    CALL DRAW_SPRITE

    STI DRAW_X, #$14
    PTR GLYPH_O
    CALL DRAW_SPRITE
    STI DRAW_X, #$15
    PTR GLYPH_V
    CALL DRAW_SPRITE
    STI DRAW_X, #$16
    PTR GLYPH_E
    CALL DRAW_SPRITE
    STI DRAW_X, #$17
    PTR GLYPH_R
    CALL DRAW_SPRITE
    RET


DRAW_YOU_WIN_TEXT:

    CALL CLEAR_MESSAGE_BAR
    STI DRAW_Y, #$0E

    STI DRAW_X, #$10
    PTR GLYPH_Y
    CALL DRAW_SPRITE
    STI DRAW_X, #$11
    PTR GLYPH_O
    CALL DRAW_SPRITE
    STI DRAW_X, #$12
    PTR GLYPH_U
    CALL DRAW_SPRITE

    STI DRAW_X, #$14
    PTR GLYPH_W
    CALL DRAW_SPRITE
    STI DRAW_X, #$15
    PTR GLYPH_I
    CALL DRAW_SPRITE
    STI DRAW_X, #$16
    PTR GLYPH_N
    CALL DRAW_SPRITE
    RET


; ============================================================================
; SAIDA PARA A BIOS
; ============================================================================

EXIT_GAME:

    CALL VIDEO_WAIT
    STI SOUND_CFG, #$00

    ; Restaura o modo texto e limpa a area textual.
    STI VIDEO_CMD, #$11
    CALL VIDEO_WAIT

    STI VIDEO_CMD, #$00
    CALL VIDEO_WAIT

    RET


; ============================================================================
; SPRITES 8x8 - 1 bit
; ============================================================================

; Corpo arredondado, com textura interna para diferenciar segmentos.
SPRITE_BODY:
    #d8 $3C, $7E, $E7, $FF, $FF, $E7, $7E, $3C

; Cabeca fechada.
SPRITE_HEAD_CLOSED:
    #d8 $3C, $7E, $F3, $FF, $FF, $FF, $7E, $3C

; Cabecas abertas por direcao.
SPRITE_HEAD_RIGHT:
    #d8 $3C, $7E, $F3, $F0, $F0, $FF, $7E, $3C
SPRITE_HEAD_LEFT:
    #d8 $3C, $7E, $CF, $0F, $0F, $FF, $7E, $3C
SPRITE_HEAD_UP:
    #d8 $18, $3C, $66, $C3, $E7, $FF, $7E, $3C
SPRITE_HEAD_DOWN:
    #d8 $3C, $7E, $FF, $E7, $C3, $66, $3C, $18

; Maca/fruta: haste + fruto arredondado.
SPRITE_FOOD:
    #d8 $0C, $18, $3C, $7E, $FF, $FF, $7E, $3C

; Moldura fina do campo.
SPRITE_WALL_H:
    #d8 $00, $00, $00, $FF, $FF, $00, $00, $00
SPRITE_WALL_V:
    #d8 $18, $18, $18, $18, $18, $18, $18, $18


; ============================================================================
; FONTE 8x8 SIMPLES PARA HUD E MENSAGENS
; ============================================================================

GLYPH_0:
    #d8 $3C, $66, $6E, $76, $66, $66, $3C, $00
GLYPH_1:
    #d8 $18, $38, $18, $18, $18, $18, $7E, $00
GLYPH_2:
    #d8 $3C, $66, $06, $0C, $30, $60, $7E, $00
GLYPH_3:
    #d8 $3C, $66, $06, $1C, $06, $66, $3C, $00
GLYPH_4:
    #d8 $0C, $1C, $3C, $6C, $7E, $0C, $0C, $00
GLYPH_5:
    #d8 $7E, $60, $7C, $06, $06, $66, $3C, $00
GLYPH_6:
    #d8 $1C, $30, $60, $7C, $66, $66, $3C, $00
GLYPH_7:
    #d8 $7E, $66, $06, $0C, $18, $18, $18, $00
GLYPH_8:
    #d8 $3C, $66, $66, $3C, $66, $66, $3C, $00
GLYPH_9:
    #d8 $3C, $66, $66, $3E, $06, $0C, $38, $00

GLYPH_A:
    #d8 $18, $3C, $66, $66, $7E, $66, $66, $00
GLYPH_C:
    #d8 $3C, $66, $60, $60, $60, $66, $3C, $00
GLYPH_E:
    #d8 $7E, $60, $60, $7C, $60, $60, $7E, $00
GLYPH_G:
    #d8 $3C, $66, $60, $6E, $66, $66, $3C, $00
GLYPH_I:
    #d8 $7E, $18, $18, $18, $18, $18, $7E, $00
GLYPH_K:
    #d8 $66, $6C, $78, $70, $78, $6C, $66, $00
GLYPH_L:
    #d8 $60, $60, $60, $60, $60, $60, $7E, $00
GLYPH_M:
    #d8 $63, $77, $7F, $6B, $63, $63, $63, $00
GLYPH_N:
    #d8 $66, $76, $7E, $7E, $6E, $66, $66, $00
GLYPH_O:
    #d8 $3C, $66, $66, $66, $66, $66, $3C, $00
GLYPH_P:
    #d8 $7C, $66, $66, $7C, $60, $60, $60, $00
GLYPH_R:
    #d8 $7C, $66, $66, $7C, $78, $6C, $66, $00
GLYPH_S:
    #d8 $3C, $66, $60, $3C, $06, $66, $3C, $00
GLYPH_U:
    #d8 $66, $66, $66, $66, $66, $66, $3C, $00
GLYPH_V:
    #d8 $66, $66, $66, $66, $66, $3C, $18, $00
GLYPH_W:
    #d8 $63, $63, $63, $6B, $7F, $77, $63, $00
GLYPH_Y:
    #d8 $66, $66, $3C, $18, $18, $18, $18, $00


; Protecao no fim do cartucho.
#addr 0xEFFD
    JMP INICIO
