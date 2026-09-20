#include "../wall8.cpu"

; ============================================================================
; WALL-8 - SNAKE / JOGO DA COBRINHA
; ============================================================================
;
; Cartucho:  $A000-$EFFF
; Video:     grafico monocromatico 320x240
; Grade:     40x30 celulas de 8x8 pixels
; Area util: X=1..38, Y=1..28
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
; A pontuacao e enviada ao display em DISPLAY_LOW.
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
    CALL DRAW_BORDER
    CALL DRAW_INITIAL_SNAKE
    CALL GENERATE_FOOD


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

    LDA NEW_X
    STA HEAD_X
    STA DRAW_X

    LDA NEW_Y
    STA HEAD_Y
    STA DRAW_Y

    STI DRAW_VALUE, #$FF
    CALL DRAW_CELL

    LDA GROW_FLAG
    CMP A, #$01
    JNZ STEP_DONE

    ; Crescimento e pontuacao.
    LDA SNAKE_LENGTH
    INC A
    STA SNAKE_LENGTH

    LDA SCORE
    INC A
    STA SCORE
    STA DISPLAY_LOW

    ; A cada quatro comidas, reduz um quadro do atraso ate o minimo.
    TEST A, #$03
    JNZ STEP_SPEED_DONE

    LDA MOVE_DELAY
    CMP A, #$02
    JZ STEP_SPEED_DONE

    DEC A
    STA MOVE_DELAY


STEP_SPEED_DONE:

    CALL BEEP_FOOD

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
    CMP A, #$00
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

    ; D0 e o pixel mais a esquerda: preserva a fase visual do padrao antigo $AA.
    STI DRAW_VALUE, #$55
    CALL DRAW_CELL

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


; Retorna A em 1..28.
RANDOM_INTERIOR_Y:

    CALL RNG_NEXT
    AND A, #$3F


RANDOM_Y_REDUCE:

    CMP A, #$1C
    JN RANDOM_Y_READY

    SUB A, #$1C
    JMP RANDOM_Y_REDUCE


RANDOM_Y_READY:

    ADD A, #$01
    RET


; ============================================================================
; VIDEO
; ============================================================================

VIDEO_WAIT:

    LDA VIDEO_STATUS
    TEST A, #$01
    JNZ VIDEO_WAIT
    RET


; Desenha uma celula de 8x8 pixels.
;
; Entrada em RAM:
;   DRAW_X     = coluna de byte 0..39
;   DRAW_Y     = linha da grade 0..29
;   DRAW_VALUE = byte repetido nas oito linhas
DRAW_CELL:

    ; DRAW_PIXEL_Y = DRAW_Y * 8
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


DRAW_BORDER:

    STI DRAW_VALUE, #$FF

    ; Linha superior.
    STI DRAW_Y,     #$00
    STI LOOP_COUNT, #$00


BORDER_TOP_LOOP:

    LDA LOOP_COUNT
    CMP A, #$28
    JZ BORDER_BOTTOM_BEGIN

    STA DRAW_X
    CALL DRAW_CELL

    LDA LOOP_COUNT
    INC A
    STA LOOP_COUNT
    JMP BORDER_TOP_LOOP


BORDER_BOTTOM_BEGIN:

    STI DRAW_Y,     #$1D
    STI LOOP_COUNT, #$00


BORDER_BOTTOM_LOOP:

    LDA LOOP_COUNT
    CMP A, #$28
    JZ BORDER_SIDES_BEGIN

    STA DRAW_X
    CALL DRAW_CELL

    LDA LOOP_COUNT
    INC A
    STA LOOP_COUNT
    JMP BORDER_BOTTOM_LOOP


BORDER_SIDES_BEGIN:

    STI LOOP_COUNT, #$01


BORDER_SIDES_LOOP:

    LDA LOOP_COUNT
    CMP A, #$1D
    JZ BORDER_DONE

    STA DRAW_Y

    STI DRAW_X, #$00
    CALL DRAW_CELL

    STI DRAW_X, #$27
    CALL DRAW_CELL

    LDA LOOP_COUNT
    INC A
    STA LOOP_COUNT
    JMP BORDER_SIDES_LOOP


BORDER_DONE:

    RET


DRAW_INITIAL_SNAKE:

    PTR SNAKE_BASE

    LDA SNAKE_LENGTH
    STA LOOP_COUNT

    STI DRAW_VALUE, #$FF


DRAW_INITIAL_LOOP:

    LDA LOOP_COUNT
    CMP A, #$00
    JZ DRAW_INITIAL_DONE

    LDA [PTR+]
    STA DRAW_X

    LDA [PTR+]
    STA DRAW_Y

    CALL DRAW_CELL

    LDA LOOP_COUNT
    DEC A
    STA LOOP_COUNT
    JMP DRAW_INITIAL_LOOP


DRAW_INITIAL_DONE:

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

BEEP_FOOD:

    ; /NOISE_EN=1, /TONE_EN=0, tom=011.
    STI SOUND_CFG, #$0D
    CALL WAIT_ONE_FRAME
    STI SOUND_CFG, #$00
    RET


; ============================================================================
; GAME OVER / VITORIA
; ============================================================================

GAME_OVER:

    STI PAUSED_FLAG, #$00
    STI FRAME_ACCUM, #$00

    ; Tom grave/forte de fim.
    STI SOUND_CFG, #$1D

    CALL DRAW_GAME_OVER_MARK

    CALL WAIT_ONE_FRAME
    CALL WAIT_ONE_FRAME
    CALL WAIT_ONE_FRAME

    STI SOUND_CFG, #$00


GAME_OVER_LOOP:

    CALL WAIT_ONE_FRAME

    LDA EXIT_FLAG
    CMP A, #$01
    JZ EXIT_GAME

    LDA RESTART_FLAG
    CMP A, #$01
    JZ GAME_START

    JMP GAME_OVER_LOOP


DRAW_GAME_OVER_MARK:

    PTR GAME_OVER_TABLE
    ; D0 e o pixel mais a esquerda: preserva a fase visual do padrao antigo $55.
    STI DRAW_VALUE, #$AA


GAME_OVER_DRAW_LOOP:

    LDA [PTR+]
    CMP A, #$FF
    JZ GAME_OVER_DRAW_DONE
    STA DRAW_X

    LDA [PTR+]
    STA DRAW_Y

    CALL DRAW_CELL
    JMP GAME_OVER_DRAW_LOOP


GAME_OVER_DRAW_DONE:

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
; TABELA DO "X" DE GAME OVER
; Cada entrada: X da grade, Y da grade
; ============================================================================

GAME_OVER_TABLE:

    #d8 $0E, $09
    #d8 $19, $09

    #d8 $0F, $0A
    #d8 $18, $0A

    #d8 $10, $0B
    #d8 $17, $0B

    #d8 $11, $0C
    #d8 $16, $0C

    #d8 $12, $0D
    #d8 $15, $0D

    #d8 $13, $0E
    #d8 $14, $0E

    #d8 $14, $0F
    #d8 $13, $0F

    #d8 $15, $10
    #d8 $12, $10

    #d8 $16, $11
    #d8 $11, $11

    #d8 $17, $12
    #d8 $10, $12

    #d8 $18, $13
    #d8 $0F, $13

    #d8 $19, $14
    #d8 $0E, $14

    #d8 $FF
