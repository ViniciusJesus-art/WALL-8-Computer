#include "../wall8.cpu"

#bankdef bios {
    #addr 0x0000
    #size 0xA000
    #outp 0x0000
}

; ============================================================
; WALL-8 BIOS / Monitor v4.0
; Terminal interativo, mini assembler e histórico controlado pela própria BIOS.
; A janela fixa da BIOS ocupa somente 0x8000..0x9FFF (8 KiB).
; O pequeno stub em 0x0000 roda apenas durante o boot overlay.
; ============================================================

KEY_DATA         = 0xF000
DISPLAY_LOW      = 0xF100
DISPLAY_HIGH     = 0xF101
VIDEO_DATA       = 0xF200
VIDEO_CMD        = 0xF201
VIDEO_X          = 0xF202
VIDEO_Y          = 0xF203
VIDEO_STATUS     = 0xF204
SYSTEM_STATUS    = 0xF300
SOUND_CFG        = 0xF400
CPU_CFG          = 0xF500
PERIPH_CFG       = 0xF501
CART_ENTRY       = 0xA000
CMD_BUFFER       = 0x0300
CMD_LEN          = 0x0240
PARSE_OK         = 0x0241
PARSE_VALUE      = 0x0242
PARSE_DIGIT      = 0x0243
PARSE_COUNT      = 0x0244
ARG1             = 0x0245
ARG2             = 0x0246
ADDR_HI          = 0x0247
ADDR_LO          = 0x0248
PRINT_VALUE      = 0x0249
TEMP0            = 0x024A
TEMP1            = 0x024B
TEMP2            = 0x024C
ASM_ADDR_HI       = 0x024D
ASM_ADDR_LO       = 0x024E
ASM_LEN           = 0x024F
ASM_B0            = 0x0250
ASM_B1            = 0x0251
ASM_B2            = 0x0252
ASM_B3            = 0x0253
ASM_REG1          = 0x0254
ASM_REG2          = 0x0255
ASM_META0         = 0x0256
ASM_META1         = 0x0257

; ------------------------------------------------------------
; Memória de edição e histórico do terminal
; ------------------------------------------------------------
; LAST_CMD guarda até 38 caracteres do último comando confirmado
; com Enter. A tecla TAB copia essa linha de volta para CMD_BUFFER,
; deixando-a apenas editada na tela; a execução só acontece depois
; de um novo Enter.
LAST_CMD          = 0x0350       ; 79 bytes: 0350h..039Eh
LAST_LEN          = 0x02A0

; O histórico pertence ao WALL-8, não ao widget do emulador.
; A BIOS mantém 128 linhas de 40 caracteres a partir de 4C00h.
; São 10 KiB reservados, deixando 0400h..4BFFh para programas e 7400h..7FFFh para a pilha.
HIST_LINE         = 0x02A1       ; linha lógica atual, 0..127
HIST_COL          = 0x02A2       ; coluna atual, 0..79
VIEW_TOP          = 0x02A3       ; primeira linha mostrada na tela
VIEW_MAX          = 0x02A4       ; maior VIEW_TOP permitido
VIEW_MODE         = 0x02A5       ; 0=acompanha final, 1=lendo histórico
HIST_PTR_HI       = 0x02A6       ; endereço da próxima célula a escrever
HIST_PTR_LO       = 0x02A7
HIST_WORK_HI      = 0x02A8       ; endereço temporário para redesenho
HIST_WORK_LO      = 0x02A9
HIST_COUNT        = 0x02AA       ; contador temporário de laços
HIST_ROW          = 0x02AB       ; linha física durante redesenho
HIST_LAST_CR      = 0x02AC       ; evita contar CR+LF como duas linhas
HIST_WRAP_PENDING = 0x02AD       ; linha avançou por completar 40 colunas
OUTPUT_CHAR       = 0x02AE       ; preserva o byte enquanto o histórico trabalha
VIDEO_BATCH          = 0x02AF       ; 0=saída imediata, 1=lote do comando em RAM
VIDEO_REDRAW_PENDING = 0x02B0       ; VIEW_TOP mudou e a tela precisa ser redesenhada
VIDEO_OLD_VIEW_TOP   = 0x02B1       ; valor anterior usado para detectar mudança da janela

HIST_BASE         = 0x4C00
HIST_CAPACITY     = 0x0080       ; 128 linhas
TEXT_WIDTH        = 0x0028       ; 40 caracteres
TEXT_HEIGHT       = 0x001E       ; 30 linhas = 320x240 com fonte 8x8
CMD_MAX           = 0x0026       ; 38 + prompt de 2 células = 40 colunas

#bank bios

#addr 0x0000
RESET:
    SP $7FFF    ; stack para a RAM depois do swap
    STI $F400, #$00    ; som desligado
    STI $F501, #$00    ; display em HEX, LEDs padrão
    STI $F100, #$00    ; display LOW
    STI $F101, #$00    ; display HIGH
    STI $F300, #$00    ; limpa flags dos timers
    STI VIDEO_CMD, #$11    ; texto 40x30, fonte 8x8, escala 2x, VGA 640x480
    STI VIDEO_CMD, #$00    ; limpa os 1.200 bytes da VRAM textual
    JMP BIOS_MAIN    ; entra na janela fixa antes de liberar RAM

#addr 0x8000
BIOS_MAIN:
    STI $F500, #$71    ; bit0=1: libera RAM; demais bits = configuração inicial

    ; Trampolins em RAM para acesso/chamada por endereco variavel.
    ; 0100: STA $xxxx / RET
    ; 0104: CALL $xxxx / RET
    ; 0108: JMP $xxxx
    ; 010B: LDA $xxxx / RET
    STI $0100, #$14
    STI $0101, #$00
    STI $0102, #$00
    STI $0103, #$5A
    STI $0104, #$59
    STI $0105, #$00
    STI $0106, #$00
    STI $0107, #$5A
    STI $0108, #$50
    STI $0109, #$00
    STI $010A, #$00
    STI $010B, #$12
    STI $010C, #$00
    STI $010D, #$00
    STI $010E, #$5A

    ; Mais dois trampolins são usados pelo histórico sem alterar PTR:
    ; 0110: PTR $xxxx / RET  -> carrega PTR com endereço variável
    ; 0114: STA $xxxx / RET  -> grava uma célula variável do histórico
    STI $0110, #$20
    STI $0111, #$00
    STI $0112, #$00
    STI $0113, #$5A
    STI $0114, #$14
    STI $0115, #$00
    STI $0116, #$00
    STI $0117, #$5A

    ; O mini assembler inicia em $0400.
    STI $024D, #$04
    STI $024E, #$00
    STI $0240, #$00
    STI $0241, #$00
    STI LAST_LEN, #$00

    ; Inicializa a tela 40x30 e a área de histórico em RAM.
    ; A partir daqui toda saída passa por PUT_CHAR, que grava a cópia
    ; textual no WALL-8 antes de enviá-la para a placa de vídeo.
    CALL HISTORY_RESET

    PTR STR_BANNER
    CALL PRINT_STRING
    PTR STR_PROMPT
    CALL PRINT_STRING
    JMP SHELL_LOOP

SHELL_LOOP:
    CALL READ_LINE
    CALL DISPATCH

    ; O resultado completo do comando e o próximo prompt já estão no
    ; histórico. A VRAM é redesenhada uma única vez antes de voltar
    ; a esperar a próxima linha digitada.
    PTR STR_PROMPT
    CALL PRINT_STRING
    CALL VIDEO_BATCH_FLUSH
    JMP SHELL_LOOP

GET_KEY:
; ------------------------------------------------------------
; Espera bloqueante por uma tecla.
; SYSTEM_STATUS bit7 é KEY_READY. A leitura de KEY_DATA gera o
; pulso /KEY_RD, limpando apenas o flip-flop READY do teclado.
; ------------------------------------------------------------
GET_KEY_WAIT:
    LDA SYSTEM_STATUS
    TEST A, #$80
    JZ GET_KEY_WAIT
    LDA KEY_DATA
    RET

; ============================================================
; Editor de linha do monitor
; ============================================================
; Teclas especiais tratadas aqui:
;   TAB  (09h): recupera o último comando, sem executá-lo.
;   UP   (80h): sobe uma linha no histórico mantido pelo WALL-8.
;   DOWN (81h): desce uma linha; no final volta a acompanhar a saída.
; O buffer aceita 38 caracteres: com o prompt "> " ocupa as 40 colunas.
; ============================================================
READ_LINE:
    STI CMD_LEN, #$00
    PTR CMD_BUFFER

READ_LINE_LOOP:
    CALL GET_KEY

    CMP A, #$80
    JZ READ_LINE_SCROLL_UP
    CMP A, #$81
    JZ READ_LINE_SCROLL_DOWN
    CMP A, #$09
    JZ READ_LINE_TAB
    CMP A, #$0D
    JZ READ_LINE_DONE_PREPARE
    CMP A, #$0A
    JZ READ_LINE_DONE_PREPARE
    CMP A, #$08
    JZ READ_LINE_BACKSPACE_PREPARE
    CMP A, #$1B
    JZ READ_LINE_ESCAPE_PREPARE

    ; Ignora controles e códigos estendidos que não são caracteres.
    CMP A, #$20
    JNC READ_LINE_LOOP
    CMP A, #$7F
    JC READ_LINE_LOOP

    ; O monitor trabalha em maiúsculas. Caracteres a..z são convertidos
    ; antes de entrar no buffer, simplificando todo o parser de comandos.
    CMP A, #$61
    JNC READ_LINE_STORE_PREPARE
    CMP A, #$7B
    JC READ_LINE_STORE_PREPARE
    SUB A, #$20

READ_LINE_STORE_PREPARE:
    STA TEMP2
    CALL VIEW_TO_BOTTOM        ; digitar sempre retorna à linha atual
    LDA TEMP2

READ_LINE_STORE_CHECK:
    LDB CMD_LEN
    CMP B, #$26
    JZ READ_LINE_LOOP
    STA [PTR+]
    CALL PUT_CHAR              ; eco + cópia no histórico do WALL-8
    INC B
    STB CMD_LEN
    JMP READ_LINE_LOOP

READ_LINE_BACKSPACE_PREPARE:
    CALL VIEW_TO_BOTTOM
READ_LINE_BACKSPACE:
    LDB CMD_LEN
    CMP B, #$00
    JZ READ_LINE_LOOP
    DEC PTR
    DEC B
    STB CMD_LEN
    LDA #$08
    CALL PUT_CHAR
    JMP READ_LINE_LOOP

READ_LINE_ESCAPE_PREPARE:
    CALL VIEW_TO_BOTTOM
READ_LINE_ESCAPE:
    STI CMD_LEN, #$00
    STI CMD_BUFFER, #$00       ; ESC cancela: DISPATCH verá uma linha vazia
    STI VIDEO_BATCH, #$01
    CALL PRINT_NEWLINE
    RET

READ_LINE_DONE_PREPARE:
    CALL VIEW_TO_BOTTOM
READ_LINE_DONE:
    LDA #$00
    STA [PTR]

    ; A partir do Enter, a quebra da linha, toda a saída do comando e o
    ; próximo prompt são acumulados somente no histórico. O laço principal
    ; fará um único HISTORY_REDRAW ao final da operação.
    STI VIDEO_BATCH, #$01

    ; Uma linha vazia não apaga o comando anterior. Assim TAB continua
    ; útil mesmo depois de o usuário pressionar Enter sem digitar nada.
    CALL SAVE_LAST_COMMAND
    CALL PRINT_NEWLINE
    RET

READ_LINE_SCROLL_UP:
    CALL HISTORY_SCROLL_UP
    JMP READ_LINE_LOOP

READ_LINE_SCROLL_DOWN:
    CALL HISTORY_SCROLL_DOWN
    JMP READ_LINE_LOOP

READ_LINE_TAB:
    CALL VIEW_TO_BOTTOM
    CALL RECALL_LAST_COMMAND
    JMP READ_LINE_LOOP

; ------------------------------------------------------------
; Copia CMD_BUFFER para LAST_CMD quando a linha tem conteúdo.
; A cópia usa DYN_WRITE, portanto não precisa de um segundo registrador
; de ponteiro para origem e destino.
; ------------------------------------------------------------
SAVE_LAST_COMMAND:
    LDA CMD_LEN
    CMP A, #$00
    JZ SAVE_LAST_DONE
    STA LAST_LEN
    STA HIST_COUNT
    PTR CMD_BUFFER
    STI ADDR_HI, #$03
    STI ADDR_LO, #$50
SAVE_LAST_LOOP:
    LDA HIST_COUNT
    CMP A, #$00
    JZ SAVE_LAST_DONE
    LDA [PTR+]
    CALL DYN_WRITE
    LDA ADDR_LO
    INC A
    STA ADDR_LO
    LDA HIST_COUNT
    DEC A
    STA HIST_COUNT
    JMP SAVE_LAST_LOOP
SAVE_LAST_DONE:
    RET

; ------------------------------------------------------------
; TAB: apaga visualmente a linha atual, copia LAST_CMD para CMD_BUFFER,
; ecoa os caracteres e deixa o cursor no final aguardando Enter.
; ------------------------------------------------------------
RECALL_LAST_COMMAND:
RECALL_ERASE_LOOP:
    LDA CMD_LEN
    CMP A, #$00
    JZ RECALL_COPY_START
    DEC PTR
    DEC A
    STA CMD_LEN
    LDA #$08
    CALL PUT_CHAR
    JMP RECALL_ERASE_LOOP

RECALL_COPY_START:
    LDA LAST_LEN
    CMP A, #$00
    JZ RECALL_DONE
    STA CMD_LEN
    STA HIST_COUNT
    PTR LAST_CMD
    STI ADDR_HI, #$03
    STI ADDR_LO, #$00

RECALL_COPY_LOOP:
    LDA HIST_COUNT
    CMP A, #$00
    JZ RECALL_RESTORE_PTR
    LDA [PTR+]
    STA TEMP2
    CALL DYN_WRITE
    LDA TEMP2
    CALL PUT_CHAR
    LDA ADDR_LO
    INC A
    STA ADDR_LO
    LDA HIST_COUNT
    DEC A
    STA HIST_COUNT
    JMP RECALL_COPY_LOOP

RECALL_RESTORE_PTR:
    CALL RESTORE_COMMAND_PTR
RECALL_DONE:
    RET

; ============================================================
; Texto 40x30 / imagem lógica 320x240 / escala 2x / VGA 640x480
; ============================================================
; VIDEO_RAW_CHAR é a única rotina que fala diretamente com VIDEO_DATA.
; PUT_CHAR fica acima dela e mantém uma cópia do texto em RAM. Durante
; um redesenho, a BIOS usa VIDEO_RAW_CHAR para não duplicar o histórico.
; ============================================================
VIDEO_RAW_CHAR:
    ; Aguarda somente a operação anterior. Depois que VIDEO_DATA aceita
    ; o novo byte, a CPU pode continuar e a próxima chamada fará o polling.
    STA OUTPUT_CHAR
    CALL VIDEO_WAIT
    LDA OUTPUT_CHAR
    STA VIDEO_DATA
    RET

VIDEO_WAIT:
    LDA VIDEO_STATUS
    TEST A, #$01
    JNZ VIDEO_WAIT
    RET

; Decide como sincronizar a superfície visível com o histórico.
; Quando VIEW_TOP mudou, o byte atual já está na RAM; portanto um redraw
; contém esse byte e ele não deve ser enviado novamente para VIDEO_DATA.
; Durante VIDEO_BATCH, toda a saída fica somente no histórico até o redraw final.
VIDEO_OUTPUT_OR_REDRAW:
    LDA VIEW_MODE
    CMP A, #$00
    JNZ VIDEO_OUTPUT_OR_REDRAW_DONE

    LDA VIDEO_BATCH
    CMP A, #$00
    JNZ VIDEO_OUTPUT_OR_REDRAW_DONE

    LDA VIDEO_REDRAW_PENDING
    CMP A, #$00
    JZ VIDEO_OUTPUT_OR_REDRAW_DIRECT

    CALL HISTORY_REDRAW
    RET

VIDEO_OUTPUT_OR_REDRAW_DIRECT:
    LDA OUTPUT_CHAR
    CALL VIDEO_RAW_CHAR
VIDEO_OUTPUT_OR_REDRAW_DONE:
    RET

PUT_CHAR:
    STA OUTPUT_CHAR

    CMP A, #$0D
    JZ PUT_CHAR_CR
    CMP A, #$0A
    JZ PUT_CHAR_LF

    STI HIST_LAST_CR, #$00

    CMP A, #$0C
    JZ PUT_CHAR_CLEAR
    CMP A, #$08
    JZ PUT_CHAR_BACKSPACE
    CMP A, #$20
    JNC PUT_CHAR_CONTROL
    CMP A, #$7F
    JC PUT_CHAR_CONTROL

    ; Ao concluir a coluna 39, a GPU incrementa X/Y antes de baixar BUSY.
    ; A flag mantém a política de CR/LF da BIOS alinhada com esse avanço.
    STI HIST_WRAP_PENDING, #$00
    LDA OUTPUT_CHAR
    CALL HISTORY_WRITE_RAW

    LDA HIST_COL
    INC A
    STA HIST_COL
    CMP A, #$28
    JNZ PUT_CHAR_PRINTABLE_OUTPUT

    STI HIST_COL, #$00
    CALL HISTORY_ADVANCE_LINE
    STI HIST_WRAP_PENDING, #$01

PUT_CHAR_PRINTABLE_OUTPUT:
    CALL VIDEO_OUTPUT_OR_REDRAW
    JMP PUT_CHAR_DONE

PUT_CHAR_CONTROL:
    ; Controles desconhecidos não ocupam células na RAM, mas ainda podem
    ; ser encaminhados à placa de vídeo quando a tela acompanha o final.
    CALL VIDEO_OUTPUT_OR_REDRAW
    JMP PUT_CHAR_DONE

PUT_CHAR_CLEAR:
    CALL HISTORY_RESET
    JMP PUT_CHAR_DONE

PUT_CHAR_BACKSPACE:
    CALL HISTORY_BACKSPACE
    JMP PUT_CHAR_DONE

PUT_CHAR_CR:
    ; CR executa a quebra. Se a linha acabou exatamente na coluna 39,
    ; o wrap automático já avançou e CR apenas confirma esse avanço.
    STI HIST_LAST_CR, #$01
    LDA HIST_WRAP_PENDING
    CMP A, #$01
    JZ PUT_CHAR_CR_ALREADY_WRAPPED
    CALL HISTORY_NEWLINE
    JMP PUT_CHAR_NEWLINE_OUTPUT
PUT_CHAR_CR_ALREADY_WRAPPED:
    STI HIST_WRAP_PENDING, #$00
    JMP PUT_CHAR_DONE

PUT_CHAR_LF:
    ; CR+LF representa uma única quebra de linha. LF isolado continua
    ; válido e executa a quebra normalmente.
    LDA HIST_LAST_CR
    CMP A, #$01
    JZ PUT_CHAR_LF_AFTER_CR
    STI HIST_LAST_CR, #$00
PUT_CHAR_LF_STANDALONE:
    LDA HIST_WRAP_PENDING
    CMP A, #$01
    JZ PUT_CHAR_LF_ALREADY_WRAPPED
    CALL HISTORY_NEWLINE
    JMP PUT_CHAR_NEWLINE_OUTPUT
PUT_CHAR_LF_ALREADY_WRAPPED:
    STI HIST_WRAP_PENDING, #$00
    JMP PUT_CHAR_DONE
PUT_CHAR_LF_AFTER_CR:
    STI HIST_LAST_CR, #$00
    JMP PUT_CHAR_DONE

PUT_CHAR_NEWLINE_OUTPUT:
    CALL VIDEO_OUTPUT_OR_REDRAW
PUT_CHAR_DONE:
    RET

PRINT_NEWLINE:
    LDA #$0D
    CALL PUT_CHAR
    RET

PRINT_STRING:
; Imprime uma string terminada em 00h apontada por PTR. PUT_CHAR foi
; projetada para não tocar em PTR, portanto o laço pode caminhar pela ROM.
PRINT_STRING_LOOP:
    LDA [PTR+]
    CMP A, #$00
    JZ PRINT_STRING_DONE
    CALL PUT_CHAR
    JMP PRINT_STRING_LOOP
PRINT_STRING_DONE:
    RET

; Encerra uma operação em lote. Enquanto VIDEO_BATCH estava ativo,
; PUT_CHAR alterou apenas o histórico em RAM. O redraw abaixo transfere
; somente o estado final das 30 linhas visíveis para a VRAM.
VIDEO_BATCH_FLUSH:
    STI VIDEO_BATCH, #$00
    CALL HISTORY_REDRAW
    RET

; Mantida como rotina auxiliar para mensagens que precisem iniciar e
; concluir seu próprio lote fora do despachante principal.
PRINT_STRING_BATCH:
    STI VIDEO_BATCH, #$01
    CALL PRINT_STRING
    CALL VIDEO_BATCH_FLUSH
    RET

; ============================================================
; Histórico textual mantido pelo próprio WALL-8
; ============================================================
; Organização da RAM:
;   4C00h + linha*40 + coluna
; São 128 linhas. Quando a capacidade é atingida, a BIOS reinicia o
; histórico; isso evita a lógica e o custo de um buffer circular na v3.
; ============================================================
HISTORY_RESET:
    STI HIST_LINE, #$00
    STI HIST_COL, #$00
    STI VIEW_TOP, #$00
    STI VIEW_MAX, #$00
    STI VIEW_MODE, #$00
    STI HIST_PTR_HI, #$4C
    STI HIST_PTR_LO, #$00
    STI HIST_LAST_CR, #$00
    STI HIST_WRAP_PENDING, #$00
    STI VIDEO_BATCH, #$00
    STI VIDEO_REDRAW_PENDING, #$00
    STI VIDEO_OLD_VIEW_TOP, #$00
    CALL HISTORY_CLEAR_VISIBLE
    CALL VIDEO_WAIT
    STI VIDEO_CMD, #$11          ; garante modo texto 40x30
    CALL VIDEO_WAIT
    STI VIDEO_CMD, #$00
    CALL VIDEO_WAIT
    STI VIDEO_X, #$00
    STI VIDEO_Y, #$00
    STI VIDEO_CMD, #$05
    RET

; Atualiza o operando do trampolim STA em 0114h e grava A na posição
; HIST_PTR. Esta rotina não modifica PTR, requisito essencial para que
; PRINT_STRING continue percorrendo uma mensagem da ROM.
HISTORY_POKE:
    STA TEMP2
    LDA HIST_PTR_LO
    STA $0115
    LDA HIST_PTR_HI
    STA $0116
    LDA TEMP2
    CALL $0114
    RET

HISTORY_WRITE_RAW:
    CALL HISTORY_POKE
    CALL HISTORY_PTR_INC
    RET

HISTORY_PTR_INC:
    LDA HIST_PTR_LO
    INC A
    STA HIST_PTR_LO
    CMP A, #$00
    JNZ HISTORY_PTR_INC_DONE
    LDA HIST_PTR_HI
    INC A
    STA HIST_PTR_HI
HISTORY_PTR_INC_DONE:
    RET

HISTORY_PTR_DEC:
    LDA HIST_PTR_LO
    CMP A, #$00
    JNZ HISTORY_PTR_DEC_LOW
    LDA HIST_PTR_HI
    DEC A
    STA HIST_PTR_HI
HISTORY_PTR_DEC_LOW:
    LDA HIST_PTR_LO
    DEC A
    STA HIST_PTR_LO
    RET

; Limpa os 40 bytes da linha apontada por HIST_PTR, mas restaura o
; ponteiro ao início. Isso garante que posições ainda não escritas sejam
; espaços mesmo em uma SRAM física que ligue com conteúdo indefinido.
HISTORY_CLEAR_CURRENT_LINE:
    LDA HIST_PTR_HI
    STA HIST_WORK_HI
    LDA HIST_PTR_LO
    STA HIST_WORK_LO
    STI HIST_COUNT, #$28
HISTORY_CLEAR_LINE_LOOP:
    LDA #$20
    CALL HISTORY_WRITE_RAW
    LDA HIST_COUNT
    DEC A
    STA HIST_COUNT
    JNZ HISTORY_CLEAR_LINE_LOOP
    LDA HIST_WORK_HI
    STA HIST_PTR_HI
    LDA HIST_WORK_LO
    STA HIST_PTR_LO
    RET

; Limpa as 30 linhas que podem ser copiadas imediatamente para a VRAM por
; HISTORY_REDRAW. As demais linhas do histórico são limpas quando passam a
; ser usadas por HISTORY_ADVANCE_LINE. Assim CLS não restaura texto antigo
; no flush seguinte e continua cabendo na janela fixa de 8 KiB da BIOS.
HISTORY_CLEAR_VISIBLE:
    STI VIDEO_OLD_VIEW_TOP, #$1E
HISTORY_CLEAR_VISIBLE_LOOP:
    CALL HISTORY_CLEAR_CURRENT_LINE
    LDA HIST_PTR_LO
    ADD A, #$28
    STA HIST_PTR_LO
    JNC HISTORY_CLEAR_VISIBLE_NO_CARRY
    LDA HIST_PTR_HI
    INC A
    STA HIST_PTR_HI
HISTORY_CLEAR_VISIBLE_NO_CARRY:
    LDA VIDEO_OLD_VIEW_TOP
    DEC A
    STA VIDEO_OLD_VIEW_TOP
    JNZ HISTORY_CLEAR_VISIBLE_LOOP
    STI HIST_PTR_HI, #$4C
    STI HIST_PTR_LO, #$00
    STI VIDEO_OLD_VIEW_TOP, #$00
    RET

; Nova linha explícita antes da coluna 40: pula as células restantes
; para que o próximo texto comece no início da linha seguinte.
HISTORY_NEWLINE:
    LDA #$28
    LDB HIST_COL
    SUB A, B
    STA HIST_COUNT
HISTORY_NEWLINE_SKIP_LOOP:
    LDA HIST_COUNT
    CMP A, #$00
    JZ HISTORY_NEWLINE_ADVANCE
    CALL HISTORY_PTR_INC
    LDA HIST_COUNT
    DEC A
    STA HIST_COUNT
    JMP HISTORY_NEWLINE_SKIP_LOOP
HISTORY_NEWLINE_ADVANCE:
    STI HIST_COL, #$00
    STI HIST_WRAP_PENDING, #$00
    CALL HISTORY_ADVANCE_LINE
    RET

HISTORY_ADVANCE_LINE:
    LDA HIST_LINE
    CMP A, #$7F
    JZ HISTORY_CAPACITY_REACHED
    INC A
    STA HIST_LINE
    CALL HISTORY_CLEAR_CURRENT_LINE
    CALL HISTORY_UPDATE_VIEW_LIMIT
    RET
HISTORY_CAPACITY_REACHED:
    ; Limite simples e determinístico: ao completar 128 linhas, começa
    ; uma nova sessão visual em vez de sobrescrever RAM da pilha.
    CALL HISTORY_RESET
    RET

HISTORY_UPDATE_VIEW_LIMIT:
    ; Guarda a janela anterior para saber se o acompanhamento automático
    ; realmente deslocou a área visível.
    LDA VIEW_TOP
    STA VIDEO_OLD_VIEW_TOP

    LDA HIST_LINE
    CMP A, #$1E
    JNC HISTORY_VIEW_LIMIT_ZERO
    SUB A, #$1D
    STA VIEW_MAX
    JMP HISTORY_VIEW_FOLLOW_CHECK
HISTORY_VIEW_LIMIT_ZERO:
    STI VIEW_MAX, #$00
HISTORY_VIEW_FOLLOW_CHECK:
    LDA VIEW_MODE
    CMP A, #$00
    JNZ HISTORY_VIEW_LIMIT_DONE

    LDA VIEW_MAX
    STA VIEW_TOP
    LDB VIDEO_OLD_VIEW_TOP
    CMP A, B
    JZ HISTORY_VIEW_LIMIT_DONE

    ; O histórico já contém a nova linha/célula. O chamador fará um único
    ; redraw em vez de copiar a VRAM linha por linha.
    STI VIDEO_REDRAW_PENDING, #$01
HISTORY_VIEW_LIMIT_DONE:
    RET

HISTORY_BACKSPACE:
    STI HIST_LAST_CR, #$00

    ; Se houve wrap automático, voltamos logicamente à linha anterior
    ; antes de remover o último caractere dela.
    LDA HIST_WRAP_PENDING
    CMP A, #$01
    JNZ HISTORY_BACKSPACE_NORMAL
    STI HIST_WRAP_PENDING, #$00
    LDA HIST_LINE
    CMP A, #$00
    JZ HISTORY_BACKSPACE_DONE
    DEC A
    STA HIST_LINE
    STI HIST_COL, #$28
    CALL HISTORY_UPDATE_VIEW_LIMIT

HISTORY_BACKSPACE_NORMAL:
    LDA HIST_COL
    CMP A, #$00
    JZ HISTORY_BACKSPACE_DONE
    DEC A
    STA HIST_COL
    CALL HISTORY_PTR_DEC
    LDA #$20
    CALL HISTORY_POKE

    LDA #$08
    STA OUTPUT_CHAR
    CALL VIDEO_OUTPUT_OR_REDRAW
HISTORY_BACKSPACE_DONE:
    RET

; Seta para cima: desloca a janela uma linha em direção ao início.
HISTORY_SCROLL_UP:
    LDA VIEW_TOP
    CMP A, #$00
    JZ HISTORY_SCROLL_UP_DONE
    DEC A
    STA VIEW_TOP
    STI VIEW_MODE, #$01
    CALL HISTORY_REDRAW
HISTORY_SCROLL_UP_DONE:
    RET

; Seta para baixo: avança uma linha. Ao chegar a VIEW_MAX, o modo de
; acompanhamento automático é restaurado e novas mensagens voltam à tela.
HISTORY_SCROLL_DOWN:
    LDA VIEW_MODE
    CMP A, #$00
    JZ HISTORY_SCROLL_DOWN_DONE
    LDA VIEW_TOP
    LDB VIEW_MAX
    CMP A, B
    JC HISTORY_SCROLL_DOWN_AT_END
    INC A
    STA VIEW_TOP
    CMP A, B
    JNZ HISTORY_SCROLL_DOWN_REDRAW
HISTORY_SCROLL_DOWN_AT_END:
    LDA VIEW_MAX
    STA VIEW_TOP
    STI VIEW_MODE, #$00
HISTORY_SCROLL_DOWN_REDRAW:
    CALL HISTORY_REDRAW
HISTORY_SCROLL_DOWN_DONE:
    RET

; Chamado antes de digitar, apagar ou confirmar uma linha. Caso o usuário
; estivesse lendo conteúdo antigo, volta à tela mais recente e redesenha.
VIEW_TO_BOTTOM:
    LDA VIEW_MODE
    CMP A, #$00
    JZ VIEW_TO_BOTTOM_DONE
    LDA VIEW_MAX
    STA VIEW_TOP
    STI VIEW_MODE, #$00
    CALL HISTORY_REDRAW
VIEW_TO_BOTTOM_DONE:
    RET

; Calcula HIST_BASE + VIEW_TOP*40 por adições sucessivas. A rotina é
; pequena e o custo ocorre apenas quando o usuário pressiona uma seta.
HISTORY_CALC_VIEW_ADDRESS:
    STI HIST_WORK_HI, #$4C
    STI HIST_WORK_LO, #$00
    LDA VIEW_TOP
    STA HIST_COUNT
HISTORY_CALC_VIEW_LOOP:
    LDA HIST_COUNT
    CMP A, #$00
    JZ HISTORY_CALC_VIEW_DONE
    LDA HIST_WORK_LO
    ADD A, #$28
    STA HIST_WORK_LO
    JNC HISTORY_CALC_VIEW_NO_CARRY
    LDA HIST_WORK_HI
    INC A
    STA HIST_WORK_HI
HISTORY_CALC_VIEW_NO_CARRY:
    LDA HIST_COUNT
    DEC A
    STA HIST_COUNT
    JMP HISTORY_CALC_VIEW_LOOP
HISTORY_CALC_VIEW_DONE:
    RET

; Carrega PTR por meio do pequeno programa montado em RAM em 0110h.
SET_PTR_FROM_WORK:
    LDA HIST_WORK_LO
    STA $0111
    LDA HIST_WORK_HI
    STA $0112
    CALL $0110
    RET

; Lê o byte apontado por HIST_WORK sem alterar PTR. Isso permite que um
; redraw aconteça no meio de PRINT_STRING sem perder o ponteiro da ROM.
HISTORY_READ_WORK:
    LDA HIST_WORK_LO
    STA $010C
    LDA HIST_WORK_HI
    STA $010D
    CALL $010B
    RET

HISTORY_WORK_PTR_INC:
    LDA HIST_WORK_LO
    INC A
    STA HIST_WORK_LO
    CMP A, #$00
    JNZ HISTORY_WORK_PTR_INC_DONE
    LDA HIST_WORK_HI
    INC A
    STA HIST_WORK_HI
HISTORY_WORK_PTR_INC_DONE:
    RET

; Depois de um redesenho, READ_LINE precisa continuar escrevendo no fim
; do CMD_BUFFER. Como PTR não possui instrução de leitura, ele é recriado
; a partir de CMD_BUFFER + CMD_LEN.
RESTORE_COMMAND_PTR:
    STI HIST_WORK_HI, #$03
    STI HIST_WORK_LO, #$00
    CALL SET_PTR_FROM_WORK
    LDA CMD_LEN
    STA HIST_COUNT
RESTORE_COMMAND_PTR_LOOP:
    LDA HIST_COUNT
    CMP A, #$00
    JZ RESTORE_COMMAND_PTR_DONE
    INC PTR
    DEC A
    STA HIST_COUNT
    JMP RESTORE_COMMAND_PTR_LOOP
RESTORE_COMMAND_PTR_DONE:
    RET

; Redesenha exclusivamente as 30 linhas visíveis. Não existe barra ou
; scrollback do Tkinter: o conteúdo mostrado é exatamente o selecionado
; por VIEW_TOP dentro da RAM do WALL-8.
HISTORY_REDRAW:
    ; O redraw usa somente a RAM de histórico como fonte. VIDEO_X e VIDEO_Y
    ; são definidos uma única vez; as 1.200 escritas seguintes usam o
    ; incremento automático da GPU.
    STI VIDEO_REDRAW_PENDING, #$00
    CALL VIDEO_WAIT
    STI VIDEO_CMD, #$04          ; esconde cursor durante a cópia
    STI VIDEO_X, #$00            ; também limpa CURSOR_END
    STI VIDEO_Y, #$00

    CALL HISTORY_CALC_VIEW_ADDRESS
    STI HIST_ROW, #$00

HISTORY_REDRAW_ROW_LOOP:
    STI HIST_COUNT, #$28

HISTORY_REDRAW_COL_LOOP:
    CALL HISTORY_READ_WORK
    CALL VIDEO_RAW_CHAR
    CALL HISTORY_WORK_PTR_INC

    LDA HIST_COUNT
    DEC A
    STA HIST_COUNT
    JNZ HISTORY_REDRAW_COL_LOOP

    LDA HIST_ROW
    INC A
    STA HIST_ROW
    CMP A, #$1E
    JNZ HISTORY_REDRAW_ROW_LOOP

    ; A última escrita pode ter ativado CURSOR_END em (39,29). Espera sua
    ; conclusão antes de reposicionar, pois escritas de X/Y durante BUSY
    ; não são aceitas pela interface.
    CALL VIDEO_WAIT

    ; Cursor só aparece quando a visão está no final. A linha física é
    ; HIST_LINE - VIEW_TOP, sempre dentro de 0..29 nessa condição.
    LDA VIEW_MODE
    CMP A, #$00
    JNZ HISTORY_REDRAW_CURSOR_HIDDEN

    LDA HIST_COL
    STA VIDEO_X
    LDA HIST_LINE
    LDB VIEW_TOP
    SUB A, B
    STA VIDEO_Y
    STI VIDEO_CMD, #$05
    RET

HISTORY_REDRAW_CURSOR_HIDDEN:
    ; Mesmo escondido, reposiciona para limpar CURSOR_END retido.
    STI VIDEO_X, #$00
    STI VIDEO_Y, #$00
    STI VIDEO_CMD, #$04
    RET

; ============================================================
; Conversão e formatação de números
; ============================================================
; PARSE_U8 aceita decimal, $HEX e 0xHEX. PARSE_HEX16 recebe endereços
; de quatro dígitos. As rotinas usam PARSE_OK para não depender das flags
; depois de chamadas auxiliares.
; ============================================================
SKIP_SPACES:
SKIP_SPACES_LOOP:
    LDA [PTR]
    CMP A, #$20
    JNZ SKIP_SPACES_DONE
    INC PTR
    JMP SKIP_SPACES_LOOP
SKIP_SPACES_DONE:
    RET

PARSE_U8:
    STI $0241, #$00
    STI $0242, #$00
    STI $0244, #$00
    CALL SKIP_SPACES
    LDA [PTR]
    CMP A, #$00
    JZ PARSE_U8_FAIL
    CMP A, #$24
    JZ PARSE_U8_HEX_PREFIX
    CMP A, #$30
    JNZ PARSE_U8_DEC_LOOP
    INC PTR
    LDA [PTR]
    CMP A, #$58
    JZ PARSE_U8_0X
    LDA #$01
    STA $0244
    JMP PARSE_U8_DEC_LOOP
PARSE_U8_0X:
    INC PTR
    JMP PARSE_U8_HEX_LOOP
PARSE_U8_HEX_PREFIX:
    INC PTR
    JMP PARSE_U8_HEX_LOOP
PARSE_U8_DEC_LOOP:
    LDA [PTR]
    CMP A, #$00
    JZ PARSE_U8_FINISH
    CMP A, #$20
    JZ PARSE_U8_FINISH
    CMP A, #$30
    JNC PARSE_U8_FAIL
    CMP A, #$3A
    JC PARSE_U8_FAIL
    SUB A, #$30
    STA $0243
    LDA $0242
    CMP A, #$1A
    JC PARSE_U8_FAIL
    CMP A, #$19
    JNZ PARSE_U8_DEC_MUL
    LDA $0243
    CMP A, #$06
    JC PARSE_U8_FAIL
PARSE_U8_DEC_MUL:
    LDA $0242
    MOV B, A
    SHL A
    SHL B
    SHL B
    SHL B
    ADD A, B
    LDB $0243
    ADD A, B
    STA $0242
    INC PTR
    LDA $0244
    INC A
    STA $0244
    JMP PARSE_U8_DEC_LOOP
PARSE_U8_HEX_LOOP:
    LDA [PTR]
    CMP A, #$00
    JZ PARSE_U8_FINISH
    CMP A, #$20
    JZ PARSE_U8_FINISH
    CALL HEX_CHAR_TO_NIBBLE
    LDA $0241
    CMP A, #$01
    JNZ PARSE_U8_FAIL
    LDA $0243
    STA $024A
    LDA $0242
    TEST A, #$F0
    JNZ PARSE_U8_FAIL
    SHL A
    SHL A
    SHL A
    SHL A
    LDB $024A
    OR A, B
    STA $0242
    INC PTR
    LDA $0244
    INC A
    STA $0244
    STI $0241, #$00
    JMP PARSE_U8_HEX_LOOP
PARSE_U8_FINISH:
    LDA $0244
    CMP A, #$00
    JZ PARSE_U8_FAIL
    STI $0241, #$01
    LDA $0242
    RET
PARSE_U8_FAIL:
    STI $0241, #$00
    LDA #$00
    RET

HEX_CHAR_TO_NIBBLE:
    STI $0241, #$00
    CMP A, #$30
    JNC HEX_CHAR_FAIL
    CMP A, #$3A
    JNC HEX_CHAR_DECIMAL
    CMP A, #$41
    JNC HEX_CHAR_FAIL
    CMP A, #$47
    JC HEX_CHAR_FAIL
    SUB A, #$37
    STA $0243
    STI $0241, #$01
    RET
HEX_CHAR_DECIMAL:
    SUB A, #$30
    STA $0243
    STI $0241, #$01
    RET
HEX_CHAR_FAIL:
    RET

PARSE_HEX16:
    STI $0241, #$00
    STI $0247, #$00
    STI $0248, #$00
    CALL SKIP_SPACES
    LDA [PTR]
    CMP A, #$24
    JNZ PARSE_HEX16_CHECK_0X
    INC PTR
    JMP PARSE_HEX16_DIGITS
PARSE_HEX16_CHECK_0X:
    CMP A, #$30
    JNZ PARSE_HEX16_DIGITS
    INC PTR
    LDA [PTR]
    CMP A, #$58
    JNZ PARSE_HEX16_FAIL
    INC PTR
PARSE_HEX16_DIGITS:
    LDA [PTR+]
    CALL HEX_CHAR_TO_NIBBLE
    LDA $0241
    CMP A, #$01
    JNZ PARSE_HEX16_FAIL
    LDA $0243
    SHL A
    SHL A
    SHL A
    SHL A
    STA $0247
    LDA [PTR+]
    CALL HEX_CHAR_TO_NIBBLE
    LDA $0241
    CMP A, #$01
    JNZ PARSE_HEX16_FAIL
    LDA $0243
    LDB $0247
    OR A, B
    STA $0247
    LDA [PTR+]
    CALL HEX_CHAR_TO_NIBBLE
    LDA $0241
    CMP A, #$01
    JNZ PARSE_HEX16_FAIL
    LDA $0243
    SHL A
    SHL A
    SHL A
    SHL A
    STA $0248
    LDA [PTR+]
    CALL HEX_CHAR_TO_NIBBLE
    LDA $0241
    CMP A, #$01
    JNZ PARSE_HEX16_FAIL
    LDA $0243
    LDB $0248
    OR A, B
    STA $0248
    LDA [PTR]
    CMP A, #$00
    JZ PARSE_HEX16_OK
    CMP A, #$20
    JZ PARSE_HEX16_OK
    CMP A, #$2C
    JNZ PARSE_HEX16_FAIL
PARSE_HEX16_OK:
    STI $0241, #$01
    RET
PARSE_HEX16_FAIL:
    STI $0241, #$00
    RET

PARSE_ONE_U8:
    CALL PARSE_U8
    LDB $0241
    CMP B, #$01
    JNZ PARSE_ONE_DONE
    STA $0245
PARSE_ONE_DONE:
    RET
PARSE_TWO_U8:
    CALL PARSE_U8
    LDB $0241
    CMP B, #$01
    JNZ PARSE_TWO_DONE
    STA $0245
    CALL PARSE_U8
    LDB $0241
    CMP B, #$01
    JNZ PARSE_TWO_DONE
    STA $0246
PARSE_TWO_DONE:
    RET

PRINT_HEX_NIBBLE:
    AND A, #$0F
    CMP A, #$0A
    JC PRINT_HEX_NIBBLE_ALPHA
    ADD A, #$30
    CALL PUT_CHAR
    RET
PRINT_HEX_NIBBLE_ALPHA:
    ADD A, #$37
    CALL PUT_CHAR
    RET
PRINT_HEX8:
    STA $0249
    SHR A
    SHR A
    SHR A
    SHR A
    CALL PRINT_HEX_NIBBLE
    LDA $0249
    AND A, #$0F
    CALL PRINT_HEX_NIBBLE
    RET

PRINT_U8_DEC:
    STA $0249
    STI $024A, #$00
    STI $024B, #$00
PRINT_DEC_HUND_LOOP:
    LDA $0249
    CMP A, #$64
    JNC PRINT_DEC_TENS_START
    SUB A, #$64
    STA $0249
    LDA $024A
    INC A
    STA $024A
    JMP PRINT_DEC_HUND_LOOP
PRINT_DEC_TENS_START:
PRINT_DEC_TENS_LOOP:
    LDA $0249
    CMP A, #$0A
    JNC PRINT_DEC_OUTPUT
    SUB A, #$0A
    STA $0249
    LDA $024B
    INC A
    STA $024B
    JMP PRINT_DEC_TENS_LOOP
PRINT_DEC_OUTPUT:
    LDA $024A
    CMP A, #$00
    JZ PRINT_DEC_NO_HUND
    ADD A, #$30
    CALL PUT_CHAR
    LDA $024B
    ADD A, #$30
    CALL PUT_CHAR
    JMP PRINT_DEC_ONES
PRINT_DEC_NO_HUND:
    LDA $024B
    CMP A, #$00
    JZ PRINT_DEC_ONES
    ADD A, #$30
    CALL PUT_CHAR
PRINT_DEC_ONES:
    LDA $0249
    ADD A, #$30
    CALL PUT_CHAR
    RET

PRINT_RESULT:
    STA $024C
    PTR STR_RESULT_PREFIX
    CALL PRINT_STRING
    LDA $024C
    CALL PRINT_U8_DEC
    PTR STR_RESULT_HEX
    CALL PRINT_STRING
    LDA $024C
    CALL PRINT_HEX8
    PTR STR_RESULT_END
    CALL PRINT_STRING
    RET

; ============================================================
; Despacho de comandos
; ============================================================
; O parser abaixo é uma árvore de comparação de caracteres. Ela ocupa
; menos ROM do que uma tabela genérica de strings e evita exigir uma
; instrução de indexação mais sofisticada da CPU.
; ============================================================
DISPATCH:
    PTR CMD_BUFFER
    CALL SKIP_SPACES
    JMP TRIE_ROOT
TRIE_ROOT:
    LDA [PTR+]
    CMP A, #$41
    JZ TRIE_ROOT_A
    CMP A, #$43
    JZ TRIE_ROOT_C
    CMP A, #$44
    JZ TRIE_ROOT_D
    CMP A, #$47
    JZ TRIE_ROOT_G
    CMP A, #$48
    JZ TRIE_ROOT_H
    CMP A, #$49
    JZ TRIE_ROOT_I
    CMP A, #$4D
    JZ TRIE_ROOT_M
    CMP A, #$4E
    JZ TRIE_ROOT_N
    CMP A, #$4F
    JZ TRIE_ROOT_O
    CMP A, #$52
    JZ TRIE_ROOT_R
    CMP A, #$53
    JZ TRIE_ROOT_S
    CMP A, #$54
    JZ TRIE_ROOT_T
    CMP A, #$56
    JZ TRIE_ROOT_V
    CMP A, #$57
    JZ TRIE_ROOT_W
    CMP A, #$58
    JZ TRIE_ROOT_X
    JMP CMD_UNKNOWN
TRIE_ROOT_A:
    LDA [PTR+]
    CMP A, #$00
    JZ CMD_ASM_START
    CMP A, #$20
    JZ CMD_ASM
    CMP A, #$44
    JZ TRIE_ROOT_A_D
    CMP A, #$4E
    JZ TRIE_ROOT_A_N
    CMP A, #$53
    JZ TRIE_ROOT_A_S
    JMP CMD_UNKNOWN
TRIE_ROOT_A_S:
    LDA [PTR+]
    CMP A, #$4D
    JZ TRIE_ROOT_A_S_M
    JMP CMD_UNKNOWN
TRIE_ROOT_A_S_M:
    LDA [PTR+]
    CMP A, #$00
    JZ CMD_ASM_START
    CMP A, #$20
    JZ CMD_ASM
    JMP CMD_UNKNOWN
TRIE_ROOT_A_D:
    LDA [PTR+]
    CMP A, #$44
    JZ TRIE_ROOT_A_D_D
    JMP CMD_UNKNOWN
TRIE_ROOT_A_D_D:
    LDA [PTR+]
    CMP A, #$00
    JZ CMD_ADD
    CMP A, #$20
    JZ CMD_ADD
    JMP CMD_UNKNOWN
TRIE_ROOT_A_N:
    LDA [PTR+]
    CMP A, #$44
    JZ TRIE_ROOT_A_N_D
    JMP CMD_UNKNOWN
TRIE_ROOT_A_N_D:
    LDA [PTR+]
    CMP A, #$00
    JZ CMD_AND
    CMP A, #$20
    JZ CMD_AND
    JMP CMD_UNKNOWN
TRIE_ROOT_C:
    LDA [PTR+]
    CMP A, #$41
    JZ TRIE_ROOT_C_A
    CMP A, #$46
    JZ TRIE_ROOT_C_F
    CMP A, #$4C
    JZ TRIE_ROOT_C_L
    CMP A, #$4D
    JZ TRIE_ROOT_C_M
    JMP CMD_UNKNOWN
TRIE_ROOT_C_A:
    LDA [PTR+]
    CMP A, #$52
    JZ TRIE_ROOT_C_A_R
    JMP CMD_UNKNOWN
TRIE_ROOT_C_A_R:
    LDA [PTR+]
    CMP A, #$44
    JZ TRIE_ROOT_C_A_R_D
    JMP CMD_UNKNOWN
TRIE_ROOT_C_A_R_D:
    LDA [PTR+]
    CMP A, #$00
    JZ CMD_CARD
    CMP A, #$20
    JZ CMD_CARD
    JMP CMD_UNKNOWN
TRIE_ROOT_C_F:
    LDA [PTR+]
    CMP A, #$47
    JZ TRIE_ROOT_C_F_G
    JMP CMD_UNKNOWN
TRIE_ROOT_C_F_G:
    LDA [PTR+]
    CMP A, #$00
    JZ CMD_WRITE
    CMP A, #$20
    JZ CMD_WRITE
    JMP CMD_UNKNOWN
TRIE_ROOT_C_L:
    LDA [PTR+]
    CMP A, #$45
    JZ TRIE_ROOT_C_L_E
    CMP A, #$53
    JZ TRIE_ROOT_C_L_S
    JMP CMD_UNKNOWN
TRIE_ROOT_C_L_E:
    LDA [PTR+]
    CMP A, #$41
    JZ TRIE_ROOT_C_L_E_A
    JMP CMD_UNKNOWN
TRIE_ROOT_C_L_E_A:
    LDA [PTR+]
    CMP A, #$52
    JZ TRIE_ROOT_C_L_E_A_R
    JMP CMD_UNKNOWN
TRIE_ROOT_C_L_E_A_R:
    LDA [PTR+]
    CMP A, #$00
    JZ CMD_CLS
    CMP A, #$20
    JZ CMD_CLS
    JMP CMD_UNKNOWN
TRIE_ROOT_C_L_S:
    LDA [PTR+]
    CMP A, #$00
    JZ CMD_CLS
    CMP A, #$20
    JZ CMD_CLS
    JMP CMD_UNKNOWN
TRIE_ROOT_C_M:
    LDA [PTR+]
    CMP A, #$50
    JZ TRIE_ROOT_C_M_P
    JMP CMD_UNKNOWN
TRIE_ROOT_C_M_P:
    LDA [PTR+]
    CMP A, #$00
    JZ CMD_CMP
    CMP A, #$20
    JZ CMD_CMP
    JMP CMD_UNKNOWN
TRIE_ROOT_D:
    LDA [PTR+]
    CMP A, #$45
    JZ TRIE_ROOT_D_E
    CMP A, #$49
    JZ TRIE_ROOT_D_I
    JMP CMD_UNKNOWN
TRIE_ROOT_D_E:
    LDA [PTR+]
    CMP A, #$43
    JZ TRIE_ROOT_D_E_C
    JMP CMD_UNKNOWN
TRIE_ROOT_D_E_C:
    LDA [PTR+]
    CMP A, #$00
    JZ CMD_DEC
    CMP A, #$20
    JZ CMD_DEC
    JMP CMD_UNKNOWN
TRIE_ROOT_D_I:
    LDA [PTR+]
    CMP A, #$53
    JZ TRIE_ROOT_D_I_S
    CMP A, #$56
    JZ TRIE_ROOT_D_I_V
    JMP CMD_UNKNOWN
TRIE_ROOT_D_I_S:
    LDA [PTR+]
    CMP A, #$50
    JZ TRIE_ROOT_D_I_S_P
    JMP CMD_UNKNOWN
TRIE_ROOT_D_I_S_P:
    LDA [PTR+]
    CMP A, #$00
    JZ CMD_DISP
    CMP A, #$20
    JZ CMD_DISP
    CMP A, #$4C
    JZ TRIE_ROOT_D_I_S_P_L
    JMP CMD_UNKNOWN
TRIE_ROOT_D_I_S_P_L:
    LDA [PTR+]
    CMP A, #$41
    JZ TRIE_ROOT_D_I_S_P_L_A
    JMP CMD_UNKNOWN
TRIE_ROOT_D_I_S_P_L_A:
    LDA [PTR+]
    CMP A, #$59
    JZ TRIE_ROOT_D_I_S_P_L_A_Y
    JMP CMD_UNKNOWN
TRIE_ROOT_D_I_S_P_L_A_Y:
    LDA [PTR+]
    CMP A, #$00
    JZ CMD_DISP
    CMP A, #$20
    JZ CMD_DISP
    JMP CMD_UNKNOWN
TRIE_ROOT_D_I_V:
    LDA [PTR+]
    CMP A, #$00
    JZ CMD_DIV
    CMP A, #$20
    JZ CMD_DIV
    JMP CMD_UNKNOWN
TRIE_ROOT_G:
    LDA [PTR+]
    CMP A, #$00
    JZ CMD_GO
    CMP A, #$20
    JZ CMD_GO
    CMP A, #$4F
    JZ TRIE_ROOT_G_O
    JMP CMD_UNKNOWN
TRIE_ROOT_G_O:
    LDA [PTR+]
    CMP A, #$00
    JZ CMD_GO
    CMP A, #$20
    JZ CMD_GO
    JMP CMD_UNKNOWN
TRIE_ROOT_H:
    LDA [PTR+]
    CMP A, #$45
    JZ TRIE_ROOT_H_E
    JMP CMD_UNKNOWN
TRIE_ROOT_H_E:
    LDA [PTR+]
    CMP A, #$4C
    JZ TRIE_ROOT_H_E_L
    JMP CMD_UNKNOWN
TRIE_ROOT_H_E_L:
    LDA [PTR+]
    CMP A, #$50
    JZ TRIE_ROOT_H_E_L_P
    JMP CMD_UNKNOWN
TRIE_ROOT_H_E_L_P:
    LDA [PTR+]
    CMP A, #$00
    JZ CMD_HELP
    CMP A, #$20
    JZ CMD_HELP
    JMP CMD_UNKNOWN
TRIE_ROOT_I:
    LDA [PTR+]
    CMP A, #$4E
    JZ TRIE_ROOT_I_N
    JMP CMD_UNKNOWN
TRIE_ROOT_I_N:
    LDA [PTR+]
    CMP A, #$43
    JZ TRIE_ROOT_I_N_C
    CMP A, #$46
    JZ TRIE_ROOT_I_N_F
    JMP CMD_UNKNOWN
TRIE_ROOT_I_N_C:
    LDA [PTR+]
    CMP A, #$00
    JZ CMD_INC
    CMP A, #$20
    JZ CMD_INC
    JMP CMD_UNKNOWN
TRIE_ROOT_I_N_F:
    LDA [PTR+]
    CMP A, #$4F
    JZ TRIE_ROOT_I_N_F_O
    JMP CMD_UNKNOWN
TRIE_ROOT_I_N_F_O:
    LDA [PTR+]
    CMP A, #$00
    JZ CMD_INFO
    CMP A, #$20
    JZ CMD_INFO
    JMP CMD_UNKNOWN
TRIE_ROOT_M:
    LDA [PTR+]
    CMP A, #$55
    JZ TRIE_ROOT_M_U
    JMP CMD_UNKNOWN
TRIE_ROOT_M_U:
    LDA [PTR+]
    CMP A, #$4C
    JZ TRIE_ROOT_M_U_L
    JMP CMD_UNKNOWN
TRIE_ROOT_M_U_L:
    LDA [PTR+]
    CMP A, #$00
    JZ CMD_MUL
    CMP A, #$20
    JZ CMD_MUL
    JMP CMD_UNKNOWN
TRIE_ROOT_N:
    LDA [PTR+]
    CMP A, #$4F
    JZ TRIE_ROOT_N_O
    JMP CMD_UNKNOWN
TRIE_ROOT_N_O:
    LDA [PTR+]
    CMP A, #$54
    JZ TRIE_ROOT_N_O_T
    JMP CMD_UNKNOWN
TRIE_ROOT_N_O_T:
    LDA [PTR+]
    CMP A, #$00
    JZ CMD_NOT
    CMP A, #$20
    JZ CMD_NOT
    JMP CMD_UNKNOWN
TRIE_ROOT_O:
    LDA [PTR+]
    CMP A, #$52
    JZ TRIE_ROOT_O_R
    JMP CMD_UNKNOWN
TRIE_ROOT_O_R:
    LDA [PTR+]
    CMP A, #$00
    JZ CMD_OR
    CMP A, #$20
    JZ CMD_OR
    JMP CMD_UNKNOWN
TRIE_ROOT_R:
    LDA [PTR+]
    CMP A, #$45
    JZ TRIE_ROOT_R_E
    CMP A, #$55
    JZ TRIE_ROOT_R_U
    JMP CMD_UNKNOWN
TRIE_ROOT_R_E:
    LDA [PTR+]
    CMP A, #$41
    JZ TRIE_ROOT_R_E_A
    CMP A, #$42
    JZ TRIE_ROOT_R_E_B
    JMP CMD_UNKNOWN
TRIE_ROOT_R_E_A:
    LDA [PTR+]
    CMP A, #$44
    JZ TRIE_ROOT_R_E_A_D
    JMP CMD_UNKNOWN
TRIE_ROOT_R_E_A_D:
    LDA [PTR+]
    CMP A, #$00
    JZ CMD_READ
    CMP A, #$20
    JZ CMD_READ
    JMP CMD_UNKNOWN
TRIE_ROOT_R_E_B:
    LDA [PTR+]
    CMP A, #$4F
    JZ TRIE_ROOT_R_E_B_O
    JMP CMD_UNKNOWN
TRIE_ROOT_R_E_B_O:
    LDA [PTR+]
    CMP A, #$4F
    JZ TRIE_ROOT_R_E_B_O_O
    JMP CMD_UNKNOWN
TRIE_ROOT_R_E_B_O_O:
    LDA [PTR+]
    CMP A, #$54
    JZ TRIE_ROOT_R_E_B_O_O_T
    JMP CMD_UNKNOWN
TRIE_ROOT_R_E_B_O_O_T:
    LDA [PTR+]
    CMP A, #$00
    JZ CMD_REBOOT
    CMP A, #$20
    JZ CMD_REBOOT
    JMP CMD_UNKNOWN
TRIE_ROOT_R_U:
    LDA [PTR+]
    CMP A, #$4E
    JZ TRIE_ROOT_R_U_N
    JMP CMD_UNKNOWN
TRIE_ROOT_R_U_N:
    LDA [PTR+]
    CMP A, #$00
    JZ CMD_RUN
    CMP A, #$20
    JZ CMD_RUN
    JMP CMD_UNKNOWN
TRIE_ROOT_S:
    LDA [PTR+]
    CMP A, #$48
    JZ TRIE_ROOT_S_H
    CMP A, #$4F
    JZ TRIE_ROOT_S_O
    CMP A, #$54
    JZ TRIE_ROOT_S_T
    CMP A, #$55
    JZ TRIE_ROOT_S_U
    JMP CMD_UNKNOWN
TRIE_ROOT_S_H:
    LDA [PTR+]
    CMP A, #$4C
    JZ TRIE_ROOT_S_H_L
    CMP A, #$52
    JZ TRIE_ROOT_S_H_R
    JMP CMD_UNKNOWN
TRIE_ROOT_S_H_L:
    LDA [PTR+]
    CMP A, #$00
    JZ CMD_SHL
    CMP A, #$20
    JZ CMD_SHL
    JMP CMD_UNKNOWN
TRIE_ROOT_S_H_R:
    LDA [PTR+]
    CMP A, #$00
    JZ CMD_SHR
    CMP A, #$20
    JZ CMD_SHR
    JMP CMD_UNKNOWN
TRIE_ROOT_S_O:
    LDA [PTR+]
    CMP A, #$55
    JZ TRIE_ROOT_S_O_U
    JMP CMD_UNKNOWN
TRIE_ROOT_S_O_U:
    LDA [PTR+]
    CMP A, #$4E
    JZ TRIE_ROOT_S_O_U_N
    JMP CMD_UNKNOWN
TRIE_ROOT_S_O_U_N:
    LDA [PTR+]
    CMP A, #$44
    JZ TRIE_ROOT_S_O_U_N_D
    JMP CMD_UNKNOWN
TRIE_ROOT_S_O_U_N_D:
    LDA [PTR+]
    CMP A, #$00
    JZ CMD_SOUND
    CMP A, #$20
    JZ CMD_SOUND
    JMP CMD_UNKNOWN
TRIE_ROOT_S_T:
    LDA [PTR+]
    CMP A, #$41
    JZ TRIE_ROOT_S_T_A
    JMP CMD_UNKNOWN
TRIE_ROOT_S_T_A:
    LDA [PTR+]
    CMP A, #$54
    JZ TRIE_ROOT_S_T_A_T
    JMP CMD_UNKNOWN
TRIE_ROOT_S_T_A_T:
    LDA [PTR+]
    CMP A, #$55
    JZ TRIE_ROOT_S_T_A_T_U
    JMP CMD_UNKNOWN
TRIE_ROOT_S_T_A_T_U:
    LDA [PTR+]
    CMP A, #$53
    JZ TRIE_ROOT_S_T_A_T_U_S
    JMP CMD_UNKNOWN
TRIE_ROOT_S_T_A_T_U_S:
    LDA [PTR+]
    CMP A, #$00
    JZ CMD_STATUS
    CMP A, #$20
    JZ CMD_STATUS
    JMP CMD_UNKNOWN
TRIE_ROOT_S_U:
    LDA [PTR+]
    CMP A, #$42
    JZ TRIE_ROOT_S_U_B
    JMP CMD_UNKNOWN
TRIE_ROOT_S_U_B:
    LDA [PTR+]
    CMP A, #$00
    JZ CMD_SUB
    CMP A, #$20
    JZ CMD_SUB
    JMP CMD_UNKNOWN
TRIE_ROOT_T:
    LDA [PTR+]
    CMP A, #$49
    JZ TRIE_ROOT_T_I
    JMP CMD_UNKNOWN
TRIE_ROOT_T_I:
    LDA [PTR+]
    CMP A, #$4D
    JZ TRIE_ROOT_T_I_M
    JMP CMD_UNKNOWN
TRIE_ROOT_T_I_M:
    LDA [PTR+]
    CMP A, #$45
    JZ TRIE_ROOT_T_I_M_E
    JMP CMD_UNKNOWN
TRIE_ROOT_T_I_M_E:
    LDA [PTR+]
    CMP A, #$52
    JZ TRIE_ROOT_T_I_M_E_R
    JMP CMD_UNKNOWN
TRIE_ROOT_T_I_M_E_R:
    LDA [PTR+]
    CMP A, #$00
    JZ CMD_TIMER
    CMP A, #$20
    JZ CMD_TIMER
    JMP CMD_UNKNOWN
TRIE_ROOT_V:
    LDA [PTR+]
    CMP A, #$45
    JZ TRIE_ROOT_V_E
    JMP CMD_UNKNOWN
TRIE_ROOT_V_E:
    LDA [PTR+]
    CMP A, #$52
    JZ TRIE_ROOT_V_E_R
    JMP CMD_UNKNOWN
TRIE_ROOT_V_E_R:
    LDA [PTR+]
    CMP A, #$00
    JZ CMD_VER
    CMP A, #$20
    JZ CMD_VER
    JMP CMD_UNKNOWN
TRIE_ROOT_W:
    LDA [PTR+]
    CMP A, #$52
    JZ TRIE_ROOT_W_R
    JMP CMD_UNKNOWN
TRIE_ROOT_W_R:
    LDA [PTR+]
    CMP A, #$49
    JZ TRIE_ROOT_W_R_I
    JMP CMD_UNKNOWN
TRIE_ROOT_W_R_I:
    LDA [PTR+]
    CMP A, #$54
    JZ TRIE_ROOT_W_R_I_T
    JMP CMD_UNKNOWN
TRIE_ROOT_W_R_I_T:
    LDA [PTR+]
    CMP A, #$45
    JZ TRIE_ROOT_W_R_I_T_E
    JMP CMD_UNKNOWN
TRIE_ROOT_W_R_I_T_E:
    LDA [PTR+]
    CMP A, #$00
    JZ CMD_WRITE
    CMP A, #$20
    JZ CMD_WRITE
    JMP CMD_UNKNOWN
TRIE_ROOT_X:
    LDA [PTR+]
    CMP A, #$4F
    JZ TRIE_ROOT_X_O
    JMP CMD_UNKNOWN
TRIE_ROOT_X_O:
    LDA [PTR+]
    CMP A, #$52
    JZ TRIE_ROOT_X_O_R
    JMP CMD_UNKNOWN
TRIE_ROOT_X_O_R:
    LDA [PTR+]
    CMP A, #$00
    JZ CMD_XOR
    CMP A, #$20
    JZ CMD_XOR
    JMP CMD_UNKNOWN

CMD_UNKNOWN:
    JMP CMD_TRY_ASM
CMD_SYNTAX:
    PTR STR_SYNTAX
    CALL PRINT_STRING
    RET
CMD_RANGE_ERROR:
    PTR STR_RANGE
    CALL PRINT_STRING
    RET

CMD_ADD:
    CALL SKIP_SPACES
    LDA [PTR]
    CMP A, #$41
    JZ CMD_TRY_ASM
    CMP A, #$42
    JZ CMD_TRY_ASM
    CALL PARSE_TWO_U8
    LDA $0241
    CMP A, #$01
    JNZ CMD_SYNTAX
    LDA $0245
    LDB $0246
    ADD A, B
    CALL PRINT_RESULT
    RET
CMD_SUB:
    CALL SKIP_SPACES
    LDA [PTR]
    CMP A, #$41
    JZ CMD_TRY_ASM
    CMP A, #$42
    JZ CMD_TRY_ASM
    CALL PARSE_TWO_U8
    LDA $0241
    CMP A, #$01
    JNZ CMD_SYNTAX
    LDA $0245
    LDB $0246
    SUB A, B
    CALL PRINT_RESULT
    RET
CMD_AND:
    CALL SKIP_SPACES
    LDA [PTR]
    CMP A, #$41
    JZ CMD_TRY_ASM
    CMP A, #$42
    JZ CMD_TRY_ASM
    CALL PARSE_TWO_U8
    LDA $0241
    CMP A, #$01
    JNZ CMD_SYNTAX
    LDA $0245
    LDB $0246
    AND A, B
    CALL PRINT_RESULT
    RET
CMD_OR:
    CALL SKIP_SPACES
    LDA [PTR]
    CMP A, #$41
    JZ CMD_TRY_ASM
    CMP A, #$42
    JZ CMD_TRY_ASM
    CALL PARSE_TWO_U8
    LDA $0241
    CMP A, #$01
    JNZ CMD_SYNTAX
    LDA $0245
    LDB $0246
    OR A, B
    CALL PRINT_RESULT
    RET
CMD_XOR:
    CALL SKIP_SPACES
    LDA [PTR]
    CMP A, #$41
    JZ CMD_TRY_ASM
    CMP A, #$42
    JZ CMD_TRY_ASM
    CALL PARSE_TWO_U8
    LDA $0241
    CMP A, #$01
    JNZ CMD_SYNTAX
    LDA $0245
    LDB $0246
    XOR A, B
    CALL PRINT_RESULT
    RET
CMD_NOT:
    CALL SKIP_SPACES
    LDA [PTR]
    CMP A, #$41
    JZ CMD_TRY_ASM
    CMP A, #$42
    JZ CMD_TRY_ASM
    CALL PARSE_ONE_U8
    LDA $0241
    CMP A, #$01
    JNZ CMD_SYNTAX
    LDA $0245
    NOT A
    CALL PRINT_RESULT
    RET
CMD_SHL:
    CALL SKIP_SPACES
    LDA [PTR]
    CMP A, #$41
    JZ CMD_TRY_ASM
    CMP A, #$42
    JZ CMD_TRY_ASM
    CALL PARSE_ONE_U8
    LDA $0241
    CMP A, #$01
    JNZ CMD_SYNTAX
    LDA $0245
    SHL A
    CALL PRINT_RESULT
    RET
CMD_SHR:
    CALL SKIP_SPACES
    LDA [PTR]
    CMP A, #$41
    JZ CMD_TRY_ASM
    CMP A, #$42
    JZ CMD_TRY_ASM
    CALL PARSE_ONE_U8
    LDA $0241
    CMP A, #$01
    JNZ CMD_SYNTAX
    LDA $0245
    SHR A
    CALL PRINT_RESULT
    RET
CMD_INC:
    CALL SKIP_SPACES
    LDA [PTR]
    CMP A, #$41
    JZ CMD_TRY_ASM
    CMP A, #$42
    JZ CMD_TRY_ASM
    CMP A, #$50
    JZ CMD_TRY_ASM
    CALL PARSE_ONE_U8
    LDA $0241
    CMP A, #$01
    JNZ CMD_SYNTAX
    LDA $0245
    INC A
    CALL PRINT_RESULT
    RET
CMD_DEC:
    CALL SKIP_SPACES
    LDA [PTR]
    CMP A, #$41
    JZ CMD_TRY_ASM
    CMP A, #$42
    JZ CMD_TRY_ASM
    CMP A, #$50
    JZ CMD_TRY_ASM
    CALL PARSE_ONE_U8
    LDA $0241
    CMP A, #$01
    JNZ CMD_SYNTAX
    LDA $0245
    DEC A
    CALL PRINT_RESULT
    RET
CMD_CMP:
    CALL SKIP_SPACES
    LDA [PTR]
    CMP A, #$41
    JZ CMD_TRY_ASM
    CMP A, #$42
    JZ CMD_TRY_ASM
    CALL PARSE_TWO_U8
    LDA $0241
    CMP A, #$01
    JNZ CMD_SYNTAX
    LDA $0245
    LDB $0246
    CMP A, B
    JZ CMD_CMP_EQ
    JC CMD_CMP_GT
    PTR STR_CMP_LT
    CALL PRINT_STRING
    RET
CMD_CMP_EQ:
    PTR STR_CMP_EQ
    CALL PRINT_STRING
    RET
CMD_CMP_GT:
    PTR STR_CMP_GT
    CALL PRINT_STRING
    RET
CMD_MUL:
    CALL PARSE_TWO_U8
    LDA $0241
    CMP A, #$01
    JNZ CMD_SYNTAX
    STI $024A, #$00
CMD_MUL_LOOP:
    LDA $0246
    CMP A, #$00
    JZ CMD_MUL_DONE
    LDA $024A
    LDB $0245
    ADD A, B
    STA $024A
    LDA $0246
    DEC A
    STA $0246
    JMP CMD_MUL_LOOP
CMD_MUL_DONE:
    LDA $024A
    CALL PRINT_RESULT
    RET
CMD_DIV:
    CALL PARSE_TWO_U8
    LDA $0241
    CMP A, #$01
    JNZ CMD_SYNTAX
    LDA $0246
    CMP A, #$00
    JZ CMD_DIV_ZERO
    STI $024A, #$00
    LDA $0245
    STA $024C
CMD_DIV_LOOP:
    LDA $024C
    LDB $0246
    CMP A, B
    JNC CMD_DIV_DONE
    SUB A, B
    STA $024C
    LDA $024A
    INC A
    STA $024A
    JMP CMD_DIV_LOOP
CMD_DIV_DONE:
    PTR STR_DIV_Q
    CALL PRINT_STRING
    LDA $024A
    CALL PRINT_U8_DEC
    PTR STR_DIV_R
    CALL PRINT_STRING
    LDA $024C
    CALL PRINT_U8_DEC
    CALL PRINT_NEWLINE
    RET
CMD_DIV_ZERO:
    PTR STR_DIV_ZERO
    CALL PRINT_STRING
    RET
CMD_HELP:
    PTR STR_HELP
    CALL PRINT_STRING
    RET
CMD_INFO:
    PTR STR_INFO
    CALL PRINT_STRING
    RET
CMD_VER:
    PTR STR_VERSION
    CALL PRINT_STRING
    RET
CMD_CLS:
    ; CLS apaga também o histórico da BIOS. Isso é diferente de apenas
    ; limpar a superfície da GPU, pois seta para cima não deve recuperar
    ; o conteúdo que o usuário decidiu descartar.
    CALL HISTORY_RESET
    ; HISTORY_RESET inicializa VIDEO_BATCH em zero. Reativa o lote para
    ; que o próximo prompt seja incluído no único redraw final.
    STI VIDEO_BATCH, #$01
    RET
CMD_STATUS:
    LDA $F300
    STA $024A
    PTR STR_STATUS_HEX
    CALL PRINT_STRING
    LDA $024A
    CALL PRINT_HEX8
    CALL PRINT_NEWLINE
    LDA $024A
    TEST A, #$01
    JZ STATUS_1MS_ZERO
    PTR STR_BIT_1MS_1
    CALL PRINT_STRING
    JMP STATUS_1MS_DONE
STATUS_1MS_ZERO:
    PTR STR_BIT_1MS_0
    CALL PRINT_STRING
STATUS_1MS_DONE:
    LDA $024A
    TEST A, #$02
    JZ STATUS_500MS_ZERO
    PTR STR_BIT_500_1
    CALL PRINT_STRING
    JMP STATUS_500MS_DONE
STATUS_500MS_ZERO:
    PTR STR_BIT_500_0
    CALL PRINT_STRING
STATUS_500MS_DONE:
    LDA $024A
    TEST A, #$80
    JZ STATUS_KEY_ZERO
    PTR STR_BIT_KEY_1
    CALL PRINT_STRING
    JMP STATUS_KEY_DONE
STATUS_KEY_ZERO:
    PTR STR_BIT_KEY_0
    CALL PRINT_STRING
STATUS_KEY_DONE:
    LDA $024A
    TEST A, #$10
    JNZ STATUS_CARD_ABSENT
    PTR STR_CARD_ON
    CALL PRINT_STRING
    JMP STATUS_CARD_DONE
STATUS_CARD_ABSENT:
    PTR STR_CARD_OFF
    CALL PRINT_STRING
STATUS_CARD_DONE:
    LDA $024A
    TEST A, #$20
    JNZ STATUS_VIDEO_ABSENT
    PTR STR_VIDEO_ON
    CALL PRINT_STRING
    JMP STATUS_VIDEO_DONE
STATUS_VIDEO_ABSENT:
    PTR STR_VIDEO_OFF
    CALL PRINT_STRING
STATUS_VIDEO_DONE:
    CALL PRINT_NEWLINE
    RET
CMD_TIMER:
    CALL SKIP_SPACES
    LDA [PTR]
    CMP A, #$00
    JZ CMD_STATUS
    CMP A, #$43
    JNZ CMD_SYNTAX
    STI $F300, #$00
    PTR STR_TIMER_CLEARED
    CALL PRINT_STRING
    RET
CMD_SOUND:
    CALL PARSE_ONE_U8
    LDA $0241
    CMP A, #$01
    JNZ CMD_SYNTAX
    LDA $0245
    STA $F400
    PTR STR_SOUND_SET
    CALL PRINT_STRING
    LDA $0245
    CALL PRINT_HEX8
    CALL PRINT_NEWLINE
    RET
CMD_DISP:
    CALL PARSE_HEX16
    LDA $0241
    CMP A, #$01
    JNZ CMD_SYNTAX
    LDA $0248
    STA $F100
    LDA $0247
    STA $F101
    PTR STR_DISPLAY_SET
    CALL PRINT_STRING
    LDA $0247
    CALL PRINT_HEX8
    LDA $0248
    CALL PRINT_HEX8
    CALL PRINT_NEWLINE
    RET
CMD_READ:
    CALL PARSE_HEX16
    LDA $0241
    CMP A, #$01
    JNZ CMD_SYNTAX
    CALL DYN_READ
    STA $024A
    PTR STR_READ_OPEN
    CALL PRINT_STRING
    LDA $0247
    CALL PRINT_HEX8
    LDA $0248
    CALL PRINT_HEX8
    PTR STR_READ_MID
    CALL PRINT_STRING
    LDA $024A
    CALL PRINT_HEX8
    PTR STR_READ_DEC
    CALL PRINT_STRING
    LDA $024A
    CALL PRINT_U8_DEC
    CALL PRINT_NEWLINE
    RET

CMD_WRITE:
    CALL PARSE_HEX16
    LDA $0241
    CMP A, #$01
    JNZ CMD_SYNTAX
    CALL PARSE_U8
    LDB $0241
    CMP B, #$01
    JNZ CMD_SYNTAX
    STA $0245
    CALL DYN_WRITE
    PTR STR_WRITE_OPEN
    CALL PRINT_STRING
    LDA $0247
    CALL PRINT_HEX8
    LDA $0248
    CALL PRINT_HEX8
    PTR STR_WRITE_MID
    CALL PRINT_STRING
    LDA $0245
    CALL PRINT_HEX8
    CALL PRINT_NEWLINE
    RET

CMD_CARD:
    JMP RUN_CARD_IMPL
CMD_RUN:
    CALL SKIP_SPACES
    LDA [PTR]
    CMP A, #$43
    JZ CMD_RUN_CARD_TEXT
    CALL PARSE_HEX16
    LDA $0241
    CMP A, #$01
    JNZ CMD_SYNTAX
    PTR STR_RUN_ADDR
    CALL PRINT_STRING
    LDA $0247
    CALL PRINT_HEX8
    LDA $0248
    CALL PRINT_HEX8
    CALL PRINT_NEWLINE

    ; Antes de entregar o controle ao programa, torna visível toda a saída
    ; pendente e deixa VIDEO_BATCH desligado para programas interativos.
    CALL VIDEO_BATCH_FLUSH
    CALL DYN_CALL

    ; O texto de retorno volta a integrar o lote do shell.
    STI VIDEO_BATCH, #$01
    STA $0256
    STB $0257
    PTR STR_RUN_RETURN
    CALL PRINT_STRING
    LDA $0256
    CALL PRINT_HEX8
    PTR STR_RUN_B
    CALL PRINT_STRING
    LDA $0257
    CALL PRINT_HEX8
    CALL PRINT_NEWLINE
    RET
CMD_RUN_CARD_TEXT:
    LDA [PTR+]
    CMP A, #$43
    JNZ CMD_SYNTAX
    LDA [PTR+]
    CMP A, #$41
    JNZ CMD_SYNTAX
    LDA [PTR+]
    CMP A, #$52
    JNZ CMD_SYNTAX
    LDA [PTR+]
    CMP A, #$44
    JNZ CMD_SYNTAX
    CALL SKIP_SPACES
    LDA [PTR]
    CMP A, #$00
    JNZ CMD_SYNTAX
    JMP RUN_CARD_IMPL

CMD_GO:
    CALL PARSE_HEX16
    LDA $0241
    CMP A, #$01
    JNZ CMD_SYNTAX
    PTR STR_GO_ADDR
    CALL PRINT_STRING
    LDA $0247
    CALL PRINT_HEX8
    LDA $0248
    CALL PRINT_HEX8
    CALL PRINT_NEWLINE
    ; GO não retorna ao shell, portanto precisa tornar a mensagem visível
    ; antes de transferir definitivamente o controle.
    CALL VIDEO_BATCH_FLUSH
    JMP DYN_GO

RUN_CARD_IMPL:
    LDA $F300
    TEST A, #$10
    JNZ RUN_CARD_NONE
    PTR STR_RUN_CARD
    CALL PRINT_STRING

    ; O cartucho pode ser interativo. Sincroniza a tela e libera a saída
    ; imediata enquanto o código externo estiver executando.
    CALL VIDEO_BATCH_FLUSH
    CALL $A000
    STI VIDEO_BATCH, #$01

    PTR STR_CARD_RETURN
    CALL PRINT_STRING
    RET
RUN_CARD_NONE:
    PTR STR_NO_CARD
    CALL PRINT_STRING
    RET

; ============================================================
; Escrita/leitura dinamica em RAM e chamada por endereco.
; Os trampolins 0x0100..0x010E sao montados no boot.
; ============================================================

DYN_WRITE:
    STA $024C
    LDA $0248
    STA $0101
    LDA $0247
    STA $0102
    LDA $024C
    CALL $0100
    RET

DYN_READ:
    LDA $0248
    STA $010C
    LDA $0247
    STA $010D
    CALL $010B
    RET

DYN_CALL:
    LDA $0248
    STA $0105
    LDA $0247
    STA $0106
    CALL $0104
    RET

DYN_GO:
    LDA $0248
    STA $0109
    LDA $0247
    STA $010A
    JMP $0108

PRINT_HEX16_ADDR:
    LDA $0247
    CALL PRINT_HEX8
    LDA $0248
    CALL PRINT_HEX8
    RET

; ============================================================
; Mini assembler interativo
; ============================================================
; Cada linha é convertida diretamente em opcode e operandos na RAM.
; O endereço corrente fica em ASM_ADDR_HI:ASM_ADDR_LO. RUN chama o bloco
; e exige RET; GO transfere o controle sem preparar retorno.
; ASM $0400 entra no modo; linha vazia sai.
; ============================================================

CMD_ASM:
    CALL SKIP_SPACES
    LDA [PTR]
    CMP A, #$00
    JZ CMD_ASM_START
    CALL PARSE_HEX16
    LDA $0241
    CMP A, #$01
    JNZ CMD_SYNTAX
    LDA $0247
    STA $024D
    LDA $0248
    STA $024E
CMD_ASM_START:
    PTR STR_ASM_ENTER
    CALL PRINT_STRING
ASM_MODE_LOOP:
    LDA $024D
    STA $0247
    LDA $024E
    STA $0248
    CALL PRINT_HEX16_ADDR
    PTR STR_ASM_PROMPT
    CALL PRINT_STRING

    ; Exibe de uma vez o resultado da linha anterior e o novo prompt.
    ; Depois do flush, a digitação volta a aparecer imediatamente.
    CALL VIDEO_BATCH_FLUSH
    CALL READ_LINE
    LDA $0240
    CMP A, #$00
    JZ ASM_MODE_EXIT
    PTR CMD_BUFFER
    CALL SKIP_SPACES
    CALL ASM_PARSE_LINE
    JMP ASM_MODE_LOOP
ASM_MODE_EXIT:
    PTR STR_ASM_EXIT
    CALL PRINT_STRING
    RET

CMD_TRY_ASM:
    PTR CMD_BUFFER
    CALL SKIP_SPACES
    CALL ASM_PARSE_LINE
    LDA $0241
    CMP A, #$01
    JNZ CMD_TRY_ASM_DONE
    PTR STR_ASM_INLINE_OK
    CALL PRINT_STRING
    LDA $024D
    STA $0247
    LDA $024E
    STA $0248
    CALL PRINT_HEX16_ADDR
    CALL PRINT_NEWLINE
CMD_TRY_ASM_DONE:
    RET

ASM_PARSE_LINE:
    JMP ASM_TRIE_ROOT

ASM_BAD:
    STI $0241, #$00
    PTR STR_ASM_ERROR
    CALL PRINT_STRING
    RET

ASM_EXPECT_END:
    STI $0241, #$00
    CALL SKIP_SPACES
    LDA [PTR]
    CMP A, #$00
    JNZ ASM_EXPECT_END_FAIL
    STI $0241, #$01
ASM_EXPECT_END_FAIL:
    RET

ASM_PARSE_REG:
    STI $0241, #$00
    CALL SKIP_SPACES
    LDA [PTR+]
    CMP A, #$41
    JZ ASM_REG_A
    CMP A, #$42
    JZ ASM_REG_B
    RET
ASM_REG_A:
    STI $0254, #$00
    STI $0241, #$01
    RET
ASM_REG_B:
    STI $0254, #$01
    STI $0241, #$01
    RET

ASM_EXPECT_COMMA:
    STI $0241, #$00
    CALL SKIP_SPACES
    LDA [PTR]
    CMP A, #$2C
    JNZ ASM_EXPECT_COMMA_FAIL
    INC PTR
    STI $0241, #$01
ASM_EXPECT_COMMA_FAIL:
    RET

ASM_PARSE_HASH_U8:
    STI $0241, #$00
    CALL SKIP_SPACES
    LDA [PTR]
    CMP A, #$23
    JNZ ASM_HASH_FAIL
    INC PTR
    CALL PARSE_U8
ASM_HASH_FAIL:
    RET

ASM_PARSE_PTR_FORM:
    ; Retorna PARSE_OK=1. TEMP0=0 para [PTR], 1 para [PTR+].
    STI $0241, #$00
    STI $024A, #$00
    CALL SKIP_SPACES
    LDA [PTR+]
    CMP A, #$5B
    JNZ ASM_PTR_FORM_FAIL
    LDA [PTR+]
    CMP A, #$50
    JNZ ASM_PTR_FORM_FAIL
    LDA [PTR+]
    CMP A, #$54
    JNZ ASM_PTR_FORM_FAIL
    LDA [PTR+]
    CMP A, #$52
    JNZ ASM_PTR_FORM_FAIL
    LDA [PTR]
    CMP A, #$2B
    JNZ ASM_PTR_FORM_CLOSE
    INC PTR
    STI $024A, #$01
ASM_PTR_FORM_CLOSE:
    LDA [PTR+]
    CMP A, #$5D
    JNZ ASM_PTR_FORM_FAIL
    STI $0241, #$01
ASM_PTR_FORM_FAIL:
    RET

ASM_EMIT_A:
    STA $024C
    LDA $024D
    STA $0247
    LDA $024E
    STA $0248
    LDA $024C
    CALL DYN_WRITE
    LDA $024E
    INC A
    STA $024E
    JNZ ASM_EMIT_DONE
    LDA $024D
    INC A
    STA $024D
ASM_EMIT_DONE:
    RET

ASM_COMMIT:
    CALL ASM_EXPECT_END
    LDA $0241
    CMP A, #$01
    JNZ ASM_BAD
    LDA $0250
    CALL ASM_EMIT_A
    LDA $024F
    CMP A, #$01
    JZ ASM_COMMIT_DONE
    LDA $0251
    CALL ASM_EMIT_A
    LDA $024F
    CMP A, #$02
    JZ ASM_COMMIT_DONE
    LDA $0252
    CALL ASM_EMIT_A
    LDA $024F
    CMP A, #$03
    JZ ASM_COMMIT_DONE
    LDA $0253
    CALL ASM_EMIT_A
ASM_COMMIT_DONE:
    STI $0241, #$01
    RET

ASM_ONE:
    STA $0250
    STI $024F, #$01
    JMP ASM_COMMIT

ASM_ADDR_OP:
    STA $0250
    CALL PARSE_HEX16
    LDA $0241
    CMP A, #$01
    JNZ ASM_BAD
    LDA $0248
    STA $0251
    LDA $0247
    STA $0252
    STI $024F, #$03
    JMP ASM_COMMIT

ASM_ONE_REG_AB:
    STA $0256
    CALL ASM_PARSE_REG
    LDA $0241
    CMP A, #$01
    JNZ ASM_BAD
    LDA $0256
    LDB $0254
    ADD A, B
    JMP ASM_ONE

ASM_ONE_REG_STEP2:
    STA $0256
    CALL ASM_PARSE_REG
    LDA $0241
    CMP A, #$01
    JNZ ASM_BAD
    LDA $0254
    SHL A
    LDB $0256
    ADD A, B
    JMP ASM_ONE

ASM_BINARY:
    ; ASM_META0 = opcode registrador base; ASM_META1 = opcode imediato base.
    CALL ASM_PARSE_REG
    LDA $0241
    CMP A, #$01
    JNZ ASM_BAD
    LDA $0254
    STA $0255
    CALL ASM_EXPECT_COMMA
    LDA $0241
    CMP A, #$01
    JNZ ASM_BAD
    CALL SKIP_SPACES
    LDA [PTR]
    CMP A, #$23
    JZ ASM_BINARY_IMM
    CALL ASM_PARSE_REG
    LDA $0241
    CMP A, #$01
    JNZ ASM_BAD
    LDA $0255
    CMP A, #$00
    JZ ASM_BINARY_FIRST_A
    LDA $0254
    CMP A, #$00
    JNZ ASM_BAD
    LDA $0256
    ADD A, #$01
    JMP ASM_ONE
ASM_BINARY_FIRST_A:
    LDA $0254
    CMP A, #$01
    JNZ ASM_BAD
    LDA $0256
    JMP ASM_ONE
ASM_BINARY_IMM:
    CALL ASM_PARSE_HASH_U8
    LDA $0241
    CMP A, #$01
    JNZ ASM_BAD
    LDA $0242
    STA $0251
    LDA $0257
    LDB $0255
    ADD A, B
    STA $0250
    STI $024F, #$02
    JMP ASM_COMMIT

ASM_LOAD:
    ; TEMP0 = 0 para A, 1 para B.
    CALL SKIP_SPACES
    LDA [PTR]
    CMP A, #$23
    JZ ASM_LOAD_IMM
    CMP A, #$5B
    JZ ASM_LOAD_PTR
    LDA #$12
    LDB $0256
    ADD A, B
    STA $0250
    CALL PARSE_HEX16
    LDA $0241
    CMP A, #$01
    JNZ ASM_BAD
    LDA $0248
    STA $0251
    LDA $0247
    STA $0252
    STI $024F, #$03
    JMP ASM_COMMIT
ASM_LOAD_IMM:
    CALL ASM_PARSE_HASH_U8
    LDA $0241
    CMP A, #$01
    JNZ ASM_BAD
    LDA $0242
    STA $0251
    LDA #$10
    LDB $0256
    ADD A, B
    STA $0250
    STI $024F, #$02
    JMP ASM_COMMIT
ASM_LOAD_PTR:
    CALL ASM_PARSE_PTR_FORM
    LDA $0241
    CMP A, #$01
    JNZ ASM_BAD
    LDA $024A
    CMP A, #$00
    JNZ ASM_LOAD_PTR_INC
    LDA #$18
    LDB $0256
    ADD A, B
    JMP ASM_ONE
ASM_LOAD_PTR_INC:
    LDA #$23
    LDB $0256
    ADD A, B
    JMP ASM_ONE

ASM_STORE:
    ; TEMP0 = 0 para A, 1 para B.
    CALL SKIP_SPACES
    LDA [PTR]
    CMP A, #$5B
    JZ ASM_STORE_PTR
    LDA #$14
    LDB $0256
    ADD A, B
    STA $0250
    CALL PARSE_HEX16
    LDA $0241
    CMP A, #$01
    JNZ ASM_BAD
    LDA $0248
    STA $0251
    LDA $0247
    STA $0252
    STI $024F, #$03
    JMP ASM_COMMIT
ASM_STORE_PTR:
    CALL ASM_PARSE_PTR_FORM
    LDA $0241
    CMP A, #$01
    JNZ ASM_BAD
    LDA $024A
    CMP A, #$00
    JNZ ASM_STORE_PTR_INC
    LDA #$1A
    LDB $0256
    ADD A, B
    JMP ASM_ONE
ASM_STORE_PTR_INC:
    LDA #$25
    LDB $0256
    ADD A, B
    JMP ASM_ONE

ASM_NOP:
    DEC PTR
    LDA #$00
    JMP ASM_ONE
ASM_HLT:
    DEC PTR
    LDA #$01
    JMP ASM_ONE
ASM_RET:
    DEC PTR
    LDA #$5A
    JMP ASM_ONE

ASM_LDA:
    STI $0256, #$00
    JMP ASM_LOAD
ASM_LDB:
    STI $0256, #$01
    JMP ASM_LOAD
ASM_STA:
    STI $0256, #$00
    JMP ASM_STORE
ASM_STB:
    STI $0256, #$01
    JMP ASM_STORE

ASM_STI:
    STI $0250, #$27
    CALL PARSE_HEX16
    LDA $0241
    CMP A, #$01
    JNZ ASM_BAD
    LDA $0248
    STA $0251
    LDA $0247
    STA $0252
    CALL ASM_EXPECT_COMMA
    LDA $0241
    CMP A, #$01
    JNZ ASM_BAD
    CALL ASM_PARSE_HASH_U8
    LDA $0241
    CMP A, #$01
    JNZ ASM_BAD
    LDA $0242
    STA $0253
    STI $024F, #$04
    JMP ASM_COMMIT

ASM_MOV:
    CALL ASM_PARSE_REG
    LDA $0241
    CMP A, #$01
    JNZ ASM_BAD
    LDA $0254
    STA $0255
    CALL ASM_EXPECT_COMMA
    LDA $0241
    CMP A, #$01
    JNZ ASM_BAD
    CALL ASM_PARSE_REG
    LDA $0241
    CMP A, #$01
    JNZ ASM_BAD
    LDA $0255
    CMP A, #$00
    JZ ASM_MOV_A
    LDA $0254
    CMP A, #$00
    JNZ ASM_BAD
    LDA #$17
    JMP ASM_ONE
ASM_MOV_A:
    LDA $0254
    CMP A, #$01
    JNZ ASM_BAD
    LDA #$16
    JMP ASM_ONE

ASM_ADD:
    STI $0256, #$30
    STI $0257, #$60
    JMP ASM_BINARY
ASM_SUB:
    STI $0256, #$32
    STI $0257, #$62
    JMP ASM_BINARY
ASM_AND:
    STI $0256, #$34
    STI $0257, #$64
    JMP ASM_BINARY
ASM_OR:
    STI $0256, #$36
    STI $0257, #$66
    JMP ASM_BINARY
ASM_XOR:
    STI $0256, #$38
    STI $0257, #$68
    JMP ASM_BINARY
ASM_CMP:
    STI $0256, #$40
    STI $0257, #$6A
    JMP ASM_BINARY

ASM_TEST:
    CALL ASM_PARSE_REG
    LDA $0241
    CMP A, #$01
    JNZ ASM_BAD
    LDA $0254
    STA $0255
    CALL ASM_EXPECT_COMMA
    LDA $0241
    CMP A, #$01
    JNZ ASM_BAD
    CALL ASM_PARSE_HASH_U8
    LDA $0241
    CMP A, #$01
    JNZ ASM_BAD
    LDA $0242
    STA $0251
    LDA #$6C
    LDB $0255
    ADD A, B
    STA $0250
    STI $024F, #$02
    JMP ASM_COMMIT

ASM_NOT:
    LDA #$3A
    JMP ASM_ONE_REG_AB
ASM_SHL:
    LDA #$3C
    JMP ASM_ONE_REG_STEP2
ASM_SHR:
    LDA #$3D
    JMP ASM_ONE_REG_STEP2
ASM_CLR:
    LDA #$46
    JMP ASM_ONE_REG_AB
ASM_PUSH:
    LDA #$5B
    JMP ASM_ONE_REG_AB
ASM_POP:
    LDA #$5D
    JMP ASM_ONE_REG_AB

ASM_INC:
    CALL SKIP_SPACES
    LDA [PTR]
    CMP A, #$50
    JZ ASM_INC_PTR
    LDA #$42
    JMP ASM_ONE_REG_STEP2
ASM_INC_PTR:
    INC PTR
    LDA [PTR+]
    CMP A, #$54
    JNZ ASM_BAD
    LDA [PTR+]
    CMP A, #$52
    JNZ ASM_BAD
    LDA #$21
    JMP ASM_ONE

ASM_DEC:
    CALL SKIP_SPACES
    LDA [PTR]
    CMP A, #$50
    JZ ASM_DEC_PTR
    LDA #$43
    JMP ASM_ONE_REG_STEP2
ASM_DEC_PTR:
    INC PTR
    LDA [PTR+]
    CMP A, #$54
    JNZ ASM_BAD
    LDA [PTR+]
    CMP A, #$52
    JNZ ASM_BAD
    LDA #$22
    JMP ASM_ONE

ASM_PTR:
    LDA #$20
    JMP ASM_ADDR_OP
ASM_SP:
    LDA #$5F
    JMP ASM_ADDR_OP
ASM_JMP:
    LDA #$50
    JMP ASM_ADDR_OP
ASM_JZ:
    LDA #$51
    JMP ASM_ADDR_OP
ASM_JNZ:
    LDA #$52
    JMP ASM_ADDR_OP
ASM_JC:
    LDA #$53
    JMP ASM_ADDR_OP
ASM_JNC:
    LDA #$54
    JMP ASM_ADDR_OP
ASM_JN:
    LDA #$55
    JMP ASM_ADDR_OP
ASM_JP:
    LDA #$56
    JMP ASM_ADDR_OP
ASM_JV:
    LDA #$57
    JMP ASM_ADDR_OP
ASM_JNV:
    LDA #$58
    JMP ASM_ADDR_OP
ASM_CALL:
    LDA #$59
    JMP ASM_ADDR_OP

ASM_TRIE_ROOT:
    LDA [PTR+]
    CMP A, #$41
    JZ ASM_TRIE_A
    CMP A, #$43
    JZ ASM_TRIE_C
    CMP A, #$44
    JZ ASM_TRIE_D
    CMP A, #$48
    JZ ASM_TRIE_H
    CMP A, #$49
    JZ ASM_TRIE_I
    CMP A, #$4A
    JZ ASM_TRIE_J
    CMP A, #$4C
    JZ ASM_TRIE_L
    CMP A, #$4D
    JZ ASM_TRIE_M
    CMP A, #$4E
    JZ ASM_TRIE_N
    CMP A, #$4F
    JZ ASM_TRIE_O
    CMP A, #$50
    JZ ASM_TRIE_P
    CMP A, #$52
    JZ ASM_TRIE_R
    CMP A, #$53
    JZ ASM_TRIE_S
    CMP A, #$54
    JZ ASM_TRIE_T
    CMP A, #$58
    JZ ASM_TRIE_X
    JMP ASM_BAD
ASM_TRIE_A:
    LDA [PTR+]
    CMP A, #$44
    JZ ASM_TRIE_AD
    CMP A, #$4E
    JZ ASM_TRIE_AN
    JMP ASM_BAD
ASM_TRIE_AD:
    LDA [PTR+]
    CMP A, #$44
    JZ ASM_TRIE_ADD
    JMP ASM_BAD
ASM_TRIE_ADD:
    LDA [PTR+]
    CMP A, #$00
    JZ ASM_ADD
    CMP A, #$20
    JZ ASM_ADD
    JMP ASM_BAD
ASM_TRIE_AN:
    LDA [PTR+]
    CMP A, #$44
    JZ ASM_TRIE_AND
    JMP ASM_BAD
ASM_TRIE_AND:
    LDA [PTR+]
    CMP A, #$00
    JZ ASM_AND
    CMP A, #$20
    JZ ASM_AND
    JMP ASM_BAD
ASM_TRIE_C:
    LDA [PTR+]
    CMP A, #$41
    JZ ASM_TRIE_CA
    CMP A, #$4C
    JZ ASM_TRIE_CL
    CMP A, #$4D
    JZ ASM_TRIE_CM
    JMP ASM_BAD
ASM_TRIE_CA:
    LDA [PTR+]
    CMP A, #$4C
    JZ ASM_TRIE_CAL
    JMP ASM_BAD
ASM_TRIE_CAL:
    LDA [PTR+]
    CMP A, #$4C
    JZ ASM_TRIE_CALL
    JMP ASM_BAD
ASM_TRIE_CALL:
    LDA [PTR+]
    CMP A, #$00
    JZ ASM_CALL
    CMP A, #$20
    JZ ASM_CALL
    JMP ASM_BAD
ASM_TRIE_CL:
    LDA [PTR+]
    CMP A, #$52
    JZ ASM_TRIE_CLR
    JMP ASM_BAD
ASM_TRIE_CLR:
    LDA [PTR+]
    CMP A, #$00
    JZ ASM_CLR
    CMP A, #$20
    JZ ASM_CLR
    JMP ASM_BAD
ASM_TRIE_CM:
    LDA [PTR+]
    CMP A, #$50
    JZ ASM_TRIE_CMP
    JMP ASM_BAD
ASM_TRIE_CMP:
    LDA [PTR+]
    CMP A, #$00
    JZ ASM_CMP
    CMP A, #$20
    JZ ASM_CMP
    JMP ASM_BAD
ASM_TRIE_D:
    LDA [PTR+]
    CMP A, #$45
    JZ ASM_TRIE_DE
    JMP ASM_BAD
ASM_TRIE_DE:
    LDA [PTR+]
    CMP A, #$43
    JZ ASM_TRIE_DEC
    JMP ASM_BAD
ASM_TRIE_DEC:
    LDA [PTR+]
    CMP A, #$00
    JZ ASM_DEC
    CMP A, #$20
    JZ ASM_DEC
    JMP ASM_BAD
ASM_TRIE_H:
    LDA [PTR+]
    CMP A, #$4C
    JZ ASM_TRIE_HL
    JMP ASM_BAD
ASM_TRIE_HL:
    LDA [PTR+]
    CMP A, #$54
    JZ ASM_TRIE_HLT
    JMP ASM_BAD
ASM_TRIE_HLT:
    LDA [PTR+]
    CMP A, #$00
    JZ ASM_HLT
    CMP A, #$20
    JZ ASM_HLT
    JMP ASM_BAD
ASM_TRIE_I:
    LDA [PTR+]
    CMP A, #$4E
    JZ ASM_TRIE_IN
    JMP ASM_BAD
ASM_TRIE_IN:
    LDA [PTR+]
    CMP A, #$43
    JZ ASM_TRIE_INC
    JMP ASM_BAD
ASM_TRIE_INC:
    LDA [PTR+]
    CMP A, #$00
    JZ ASM_INC
    CMP A, #$20
    JZ ASM_INC
    JMP ASM_BAD
ASM_TRIE_J:
    LDA [PTR+]
    CMP A, #$43
    JZ ASM_TRIE_JC
    CMP A, #$4D
    JZ ASM_TRIE_JM
    CMP A, #$4E
    JZ ASM_TRIE_JN
    CMP A, #$50
    JZ ASM_TRIE_JP
    CMP A, #$56
    JZ ASM_TRIE_JV
    CMP A, #$5A
    JZ ASM_TRIE_JZ
    JMP ASM_BAD
ASM_TRIE_JC:
    LDA [PTR+]
    CMP A, #$00
    JZ ASM_JC
    CMP A, #$20
    JZ ASM_JC
    JMP ASM_BAD
ASM_TRIE_JM:
    LDA [PTR+]
    CMP A, #$50
    JZ ASM_TRIE_JMP
    JMP ASM_BAD
ASM_TRIE_JMP:
    LDA [PTR+]
    CMP A, #$00
    JZ ASM_JMP
    CMP A, #$20
    JZ ASM_JMP
    JMP ASM_BAD
ASM_TRIE_JN:
    LDA [PTR+]
    CMP A, #$00
    JZ ASM_JN
    CMP A, #$20
    JZ ASM_JN
    CMP A, #$43
    JZ ASM_TRIE_JNC
    CMP A, #$56
    JZ ASM_TRIE_JNV
    CMP A, #$5A
    JZ ASM_TRIE_JNZ
    JMP ASM_BAD
ASM_TRIE_JNC:
    LDA [PTR+]
    CMP A, #$00
    JZ ASM_JNC
    CMP A, #$20
    JZ ASM_JNC
    JMP ASM_BAD
ASM_TRIE_JNV:
    LDA [PTR+]
    CMP A, #$00
    JZ ASM_JNV
    CMP A, #$20
    JZ ASM_JNV
    JMP ASM_BAD
ASM_TRIE_JNZ:
    LDA [PTR+]
    CMP A, #$00
    JZ ASM_JNZ
    CMP A, #$20
    JZ ASM_JNZ
    JMP ASM_BAD
ASM_TRIE_JP:
    LDA [PTR+]
    CMP A, #$00
    JZ ASM_JP
    CMP A, #$20
    JZ ASM_JP
    JMP ASM_BAD
ASM_TRIE_JV:
    LDA [PTR+]
    CMP A, #$00
    JZ ASM_JV
    CMP A, #$20
    JZ ASM_JV
    JMP ASM_BAD
ASM_TRIE_JZ:
    LDA [PTR+]
    CMP A, #$00
    JZ ASM_JZ
    CMP A, #$20
    JZ ASM_JZ
    JMP ASM_BAD
ASM_TRIE_L:
    LDA [PTR+]
    CMP A, #$44
    JZ ASM_TRIE_LD
    JMP ASM_BAD
ASM_TRIE_LD:
    LDA [PTR+]
    CMP A, #$41
    JZ ASM_TRIE_LDA
    CMP A, #$42
    JZ ASM_TRIE_LDB
    JMP ASM_BAD
ASM_TRIE_LDA:
    LDA [PTR+]
    CMP A, #$00
    JZ ASM_LDA
    CMP A, #$20
    JZ ASM_LDA
    JMP ASM_BAD
ASM_TRIE_LDB:
    LDA [PTR+]
    CMP A, #$00
    JZ ASM_LDB
    CMP A, #$20
    JZ ASM_LDB
    JMP ASM_BAD
ASM_TRIE_M:
    LDA [PTR+]
    CMP A, #$4F
    JZ ASM_TRIE_MO
    JMP ASM_BAD
ASM_TRIE_MO:
    LDA [PTR+]
    CMP A, #$56
    JZ ASM_TRIE_MOV
    JMP ASM_BAD
ASM_TRIE_MOV:
    LDA [PTR+]
    CMP A, #$00
    JZ ASM_MOV
    CMP A, #$20
    JZ ASM_MOV
    JMP ASM_BAD
ASM_TRIE_N:
    LDA [PTR+]
    CMP A, #$4F
    JZ ASM_TRIE_NO
    JMP ASM_BAD
ASM_TRIE_NO:
    LDA [PTR+]
    CMP A, #$50
    JZ ASM_TRIE_NOP
    CMP A, #$54
    JZ ASM_TRIE_NOT
    JMP ASM_BAD
ASM_TRIE_NOP:
    LDA [PTR+]
    CMP A, #$00
    JZ ASM_NOP
    CMP A, #$20
    JZ ASM_NOP
    JMP ASM_BAD
ASM_TRIE_NOT:
    LDA [PTR+]
    CMP A, #$00
    JZ ASM_NOT
    CMP A, #$20
    JZ ASM_NOT
    JMP ASM_BAD
ASM_TRIE_O:
    LDA [PTR+]
    CMP A, #$52
    JZ ASM_TRIE_OR
    JMP ASM_BAD
ASM_TRIE_OR:
    LDA [PTR+]
    CMP A, #$00
    JZ ASM_OR
    CMP A, #$20
    JZ ASM_OR
    JMP ASM_BAD
ASM_TRIE_P:
    LDA [PTR+]
    CMP A, #$4F
    JZ ASM_TRIE_PO
    CMP A, #$54
    JZ ASM_TRIE_PT
    CMP A, #$55
    JZ ASM_TRIE_PU
    JMP ASM_BAD
ASM_TRIE_PO:
    LDA [PTR+]
    CMP A, #$50
    JZ ASM_TRIE_POP
    JMP ASM_BAD
ASM_TRIE_POP:
    LDA [PTR+]
    CMP A, #$00
    JZ ASM_POP
    CMP A, #$20
    JZ ASM_POP
    JMP ASM_BAD
ASM_TRIE_PT:
    LDA [PTR+]
    CMP A, #$52
    JZ ASM_TRIE_PTR
    JMP ASM_BAD
ASM_TRIE_PTR:
    LDA [PTR+]
    CMP A, #$00
    JZ ASM_PTR
    CMP A, #$20
    JZ ASM_PTR
    JMP ASM_BAD
ASM_TRIE_PU:
    LDA [PTR+]
    CMP A, #$53
    JZ ASM_TRIE_PUS
    JMP ASM_BAD
ASM_TRIE_PUS:
    LDA [PTR+]
    CMP A, #$48
    JZ ASM_TRIE_PUSH
    JMP ASM_BAD
ASM_TRIE_PUSH:
    LDA [PTR+]
    CMP A, #$00
    JZ ASM_PUSH
    CMP A, #$20
    JZ ASM_PUSH
    JMP ASM_BAD
ASM_TRIE_R:
    LDA [PTR+]
    CMP A, #$45
    JZ ASM_TRIE_RE
    JMP ASM_BAD
ASM_TRIE_RE:
    LDA [PTR+]
    CMP A, #$54
    JZ ASM_TRIE_RET
    JMP ASM_BAD
ASM_TRIE_RET:
    LDA [PTR+]
    CMP A, #$00
    JZ ASM_RET
    CMP A, #$20
    JZ ASM_RET
    JMP ASM_BAD
ASM_TRIE_S:
    LDA [PTR+]
    CMP A, #$48
    JZ ASM_TRIE_SH
    CMP A, #$50
    JZ ASM_TRIE_SP
    CMP A, #$54
    JZ ASM_TRIE_ST
    CMP A, #$55
    JZ ASM_TRIE_SU
    JMP ASM_BAD
ASM_TRIE_SH:
    LDA [PTR+]
    CMP A, #$4C
    JZ ASM_TRIE_SHL
    CMP A, #$52
    JZ ASM_TRIE_SHR
    JMP ASM_BAD
ASM_TRIE_SHL:
    LDA [PTR+]
    CMP A, #$00
    JZ ASM_SHL
    CMP A, #$20
    JZ ASM_SHL
    JMP ASM_BAD
ASM_TRIE_SHR:
    LDA [PTR+]
    CMP A, #$00
    JZ ASM_SHR
    CMP A, #$20
    JZ ASM_SHR
    JMP ASM_BAD
ASM_TRIE_SP:
    LDA [PTR+]
    CMP A, #$00
    JZ ASM_SP
    CMP A, #$20
    JZ ASM_SP
    JMP ASM_BAD
ASM_TRIE_ST:
    LDA [PTR+]
    CMP A, #$41
    JZ ASM_TRIE_STA
    CMP A, #$42
    JZ ASM_TRIE_STB
    CMP A, #$49
    JZ ASM_TRIE_STI
    JMP ASM_BAD
ASM_TRIE_STA:
    LDA [PTR+]
    CMP A, #$00
    JZ ASM_STA
    CMP A, #$20
    JZ ASM_STA
    JMP ASM_BAD
ASM_TRIE_STB:
    LDA [PTR+]
    CMP A, #$00
    JZ ASM_STB
    CMP A, #$20
    JZ ASM_STB
    JMP ASM_BAD
ASM_TRIE_STI:
    LDA [PTR+]
    CMP A, #$00
    JZ ASM_STI
    CMP A, #$20
    JZ ASM_STI
    JMP ASM_BAD
ASM_TRIE_SU:
    LDA [PTR+]
    CMP A, #$42
    JZ ASM_TRIE_SUB
    JMP ASM_BAD
ASM_TRIE_SUB:
    LDA [PTR+]
    CMP A, #$00
    JZ ASM_SUB
    CMP A, #$20
    JZ ASM_SUB
    JMP ASM_BAD
ASM_TRIE_T:
    LDA [PTR+]
    CMP A, #$45
    JZ ASM_TRIE_TE
    JMP ASM_BAD
ASM_TRIE_TE:
    LDA [PTR+]
    CMP A, #$53
    JZ ASM_TRIE_TES
    JMP ASM_BAD
ASM_TRIE_TES:
    LDA [PTR+]
    CMP A, #$54
    JZ ASM_TRIE_TEST
    JMP ASM_BAD
ASM_TRIE_TEST:
    LDA [PTR+]
    CMP A, #$00
    JZ ASM_TEST
    CMP A, #$20
    JZ ASM_TEST
    JMP ASM_BAD
ASM_TRIE_X:
    LDA [PTR+]
    CMP A, #$4F
    JZ ASM_TRIE_XO
    JMP ASM_BAD
ASM_TRIE_XO:
    LDA [PTR+]
    CMP A, #$52
    JZ ASM_TRIE_XOR
    JMP ASM_BAD
ASM_TRIE_XOR:
    LDA [PTR+]
    CMP A, #$00
    JZ ASM_XOR
    CMP A, #$20
    JZ ASM_XOR
    JMP ASM_BAD

CMD_REBOOT:
    PTR STR_REBOOT
    CALL PRINT_STRING
    ; REBOOT não retorna ao shell, então conclui a atualização pendente.
    CALL VIDEO_BATCH_FLUSH
    STI $F500, #$70    ; reativa overlay mantendo configuração de clock
    JMP RESET
STR_ASM_ENTER:
    #d8 0x4D, 0x69, 0x6E, 0x69, 0x20, 0x61, 0x73, 0x73, 0x65, 0x6D, 0x62, 0x6C, 0x65, 0x72, 0x20, 0x61
    #d8 0x74, 0x69, 0x76, 0x6F, 0x2E, 0x20, 0x4C, 0x69, 0x6E, 0x68, 0x61, 0x20, 0x76, 0x61, 0x7A, 0x69
    #d8 0x61, 0x20, 0x73, 0x61, 0x69, 0x2E, 0x0D, 0x0A, 0x00
STR_ASM_ERROR:
    #d8 0x49, 0x6E, 0x73, 0x74, 0x72, 0x75, 0x63, 0x61, 0x6F, 0x20, 0x6F, 0x75, 0x20, 0x6F, 0x70, 0x65
    #d8 0x72, 0x61, 0x6E, 0x64, 0x6F, 0x73, 0x20, 0x69, 0x6E, 0x76, 0x61, 0x6C, 0x69, 0x64, 0x6F, 0x73
    #d8 0x2E, 0x0D, 0x0A, 0x00
STR_ASM_EXIT:
    #d8 0x53, 0x61, 0x69, 0x6E, 0x64, 0x6F, 0x20, 0x64, 0x6F, 0x20, 0x6D, 0x69, 0x6E, 0x69, 0x20, 0x61
    #d8 0x73, 0x73, 0x65, 0x6D, 0x62, 0x6C, 0x65, 0x72, 0x2E, 0x0D, 0x0A, 0x00
STR_ASM_INLINE_OK:
    #d8 0x4D, 0x6F, 0x6E, 0x74, 0x61, 0x64, 0x6F, 0x2E, 0x20, 0x50, 0x72, 0x6F, 0x78, 0x69, 0x6D, 0x6F
    #d8 0x3D, 0x24, 0x00
STR_ASM_PROMPT:
    #d8 0x3E, 0x20, 0x00
STR_BANNER:
    #d8 0x0D, 0x0A, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x57, 0x61, 0x6C, 0x6C, 0x2D, 0x38, 0x20, 0x42
    #d8 0x49, 0x4F, 0x53, 0x20, 0x4D, 0x6F, 0x6E, 0x69, 0x74, 0x6F, 0x72, 0x20, 0x76, 0x34, 0x2E, 0x30
    #d8 0x0D, 0x0A, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20
    #d8 0x20, 0x20, 0x20, 0x62, 0x79, 0x3A, 0x56, 0x69, 0x6E, 0x69, 0x63, 0x69, 0x75, 0x73, 0x20, 0x44
    #d8 0x69, 0x61, 0x73, 0x0A, 0x48, 0x65, 0x6C, 0x70, 0x20, 0x7C, 0x20, 0x54, 0x61, 0x62, 0x20, 0x7C
    #d8 0x20, 0x55, 0x50, 0x2F, 0x44, 0x4F, 0x57, 0x4E, 0x0D, 0x20, 0x00
STR_BIT_1MS_0:
    #d8 0x31, 0x4D, 0x53, 0x3D, 0x30, 0x20, 0x00
STR_BIT_1MS_1:
    #d8 0x31, 0x4D, 0x53, 0x3D, 0x31, 0x20, 0x00
STR_BIT_500_0:
    #d8 0x35, 0x30, 0x30, 0x4D, 0x53, 0x3D, 0x30, 0x20, 0x00
STR_BIT_500_1:
    #d8 0x35, 0x30, 0x30, 0x4D, 0x53, 0x3D, 0x31, 0x20, 0x00
STR_BIT_KEY_0:
    #d8 0x4B, 0x45, 0x59, 0x3D, 0x30, 0x20, 0x00
STR_BIT_KEY_1:
    #d8 0x4B, 0x45, 0x59, 0x3D, 0x31, 0x20, 0x00
STR_CARD_OFF:
    #d8 0x43, 0x41, 0x52, 0x44, 0x3D, 0x4F, 0x46, 0x46, 0x20, 0x00
STR_CARD_ON:
    #d8 0x43, 0x41, 0x52, 0x44, 0x3D, 0x4F, 0x4E, 0x20, 0x00
STR_CARD_RETURN:
    #d8 0x43, 0x61, 0x72, 0x74, 0x75, 0x63, 0x68, 0x6F, 0x20, 0x72, 0x65, 0x74, 0x6F, 0x72, 0x6E, 0x6F
    #d8 0x75, 0x20, 0x70, 0x61, 0x72, 0x61, 0x20, 0x61, 0x20, 0x42, 0x49, 0x4F, 0x53, 0x2E, 0x0D, 0x0A
    #d8 0x00
STR_CMP_EQ:
    #d8 0x3D, 0x0D, 0x0A, 0x00
STR_CMP_GT:
    #d8 0x3E, 0x0D, 0x0A, 0x00
STR_CMP_LT:
    #d8 0x3C, 0x0D, 0x0A, 0x00
STR_DISPLAY_SET:
    #d8 0x44, 0x49, 0x53, 0x50, 0x4C, 0x41, 0x59, 0x20, 0x24, 0x46, 0x31, 0x30, 0x31, 0x3A, 0x24, 0x46
    #d8 0x31, 0x30, 0x30, 0x3D, 0x24, 0x00
STR_DIV_Q:
    #d8 0x51, 0x3D, 0x00
STR_DIV_R:
    #d8 0x20, 0x52, 0x3D, 0x00
STR_DIV_ZERO:
    #d8 0x44, 0x69, 0x76, 0x69, 0x73, 0x61, 0x6F, 0x20, 0x70, 0x6F, 0x72, 0x20, 0x7A, 0x65, 0x72, 0x6F
    #d8 0x2E, 0x0D, 0x0A, 0x00
STR_GO_ADDR:
    #d8 0x53, 0x61, 0x6C, 0x74, 0x61, 0x6E, 0x64, 0x6F, 0x20, 0x70, 0x61, 0x72, 0x61, 0x20, 0x24, 0x00
STR_HELP:
    #d8 0x43, 0x4D, 0x44, 0x3A, 0x0D, 0x0A
    #d8 0x20, 0x43, 0x4C, 0x53, 0x20, 0x7C, 0x20, 0x43, 0x4C, 0x45, 0x41, 0x52, 0x0D, 0x0A
    #d8 0x20, 0x49, 0x4E, 0x46, 0x4F, 0x20, 0x7C, 0x20, 0x56, 0x45, 0x52, 0x0D, 0x0A, 0x20, 0x53, 0x54
    #d8 0x41, 0x54, 0x55, 0x53, 0x0D, 0x0A, 0x20, 0x54, 0x49, 0x4D, 0x45, 0x52, 0x20, 0x5B, 0x43, 0x4C
    #d8 0x45, 0x41, 0x52, 0x5D, 0x0D, 0x0A, 0x20, 0x52, 0x45, 0x41, 0x44, 0x20, 0x24, 0x68, 0x68, 0x68
    #d8 0x68, 0x0D, 0x0A, 0x20, 0x57, 0x52, 0x49, 0x54, 0x45, 0x20, 0x24, 0x68, 0x68, 0x68, 0x68, 0x20
    #d8 0x76, 0x61, 0x6C, 0x6F, 0x72, 0x0D, 0x0A, 0x20, 0x43, 0x46, 0x47, 0x20, 0x24, 0x68, 0x68, 0x68
    #d8 0x68, 0x20, 0x76, 0x61, 0x6C, 0x6F, 0x72, 0x0D, 0x0A, 0x20, 0x53, 0x4F, 0x55, 0x4E, 0x44, 0x20
    #d8 0x76, 0x61, 0x6C, 0x6F, 0x72, 0x0D, 0x0A, 0x20, 0x44, 0x49, 0x53, 0x50, 0x20, 0x24, 0x68, 0x68
    #d8 0x68, 0x68, 0x0D, 0x0A, 0x20, 0x43, 0x41, 0x52, 0x44, 0x0D, 0x0A, 0x20, 0x52, 0x55, 0x4E, 0x20
    #d8 0x43, 0x41, 0x52, 0x44, 0x0D, 0x0A, 0x20, 0x41, 0x53, 0x4D, 0x20, 0x5B, 0x24, 0x68, 0x68, 0x68
    #d8 0x68, 0x5D, 0x0D, 0x0A, 0x20, 0x4F, 0x52, 0x47, 0x20, 0x24, 0x68, 0x68, 0x68, 0x68, 0x0D, 0x0A
    #d8 0x20, 0x52, 0x55, 0x4E, 0x20, 0x24, 0x68, 0x68, 0x68, 0x68, 0x0D, 0x0A, 0x20, 0x47, 0x4F, 0x20
    #d8 0x24, 0x68, 0x68, 0x68, 0x68, 0x0D, 0x0A, 0x20, 0x52, 0x45, 0x42, 0x4F, 0x4F, 0x54, 0x0D, 0x0A
    #d8 0x20, 0x41, 0x44, 0x44, 0x20, 0x61, 0x20, 0x62, 0x0D, 0x0A, 0x20, 0x53, 0x55, 0x42, 0x20, 0x61
    #d8 0x20, 0x62, 0x0D, 0x0A, 0x20, 0x4D, 0x55, 0x4C, 0x20, 0x61, 0x20, 0x62, 0x0D, 0x0A, 0x20, 0x44
    #d8 0x49, 0x56, 0x20, 0x61, 0x20, 0x62, 0x0D, 0x0A, 0x20, 0x41, 0x4E, 0x44, 0x20, 0x61, 0x20, 0x62
    #d8 0x0D, 0x0A, 0x20, 0x4F, 0x52, 0x20, 0x61, 0x20, 0x62, 0x0D, 0x0A, 0x20, 0x58, 0x4F, 0x52, 0x20
    #d8 0x61, 0x20, 0x62, 0x0D, 0x0A, 0x20, 0x43, 0x4D, 0x50, 0x20, 0x61, 0x20, 0x62, 0x0D, 0x0A, 0x20
    #d8 0x4E, 0x4F, 0x54, 0x20, 0x61, 0x0D, 0x0A, 0x20, 0x53, 0x48, 0x4C, 0x20, 0x61, 0x0D, 0x0A, 0x20
    #d8 0x53, 0x48, 0x52, 0x20, 0x61, 0x0D, 0x0A, 0x20, 0x49, 0x4E, 0x43, 0x20, 0x61, 0x0D, 0x0A, 0x20
    #d8 0x44, 0x45, 0x43, 0x20, 0x61, 0x0D, 0x0A
    #d8 0x20, 0x54, 0x41, 0x42, 0x3A, 0x20, 0x72, 0x65, 0x63, 0x61, 0x6C, 0x6C, 0x20, 0x7C, 0x20
    #d8 0x55, 0x50, 0x2F, 0x44, 0x4F, 0x57, 0x4E, 0x3A, 0x20, 0x73, 0x63, 0x72, 0x6F, 0x6C, 0x6C, 0x0D, 0x0A, 0x00
STR_INFO:
    #d8 0x57, 0x41, 0x4C, 0x4C, 0x2D, 0x38, 0x3A, 0x20, 0x44, 0x42, 0x55, 0x53, 0x20, 0x38, 0x2D, 0x62
    #d8 0x69, 0x74, 0x2C, 0x20, 0x45, 0x58, 0x42, 0x55, 0x53, 0x20, 0x31, 0x36, 0x2D, 0x62, 0x69, 0x74
    #d8 0x2C, 0x20, 0x66, 0x6C, 0x61, 0x67, 0x73, 0x20, 0x5A, 0x2F, 0x43, 0x2F, 0x4E, 0x2F, 0x56, 0x2E
    #d8 0x0D, 0x0A, 0x52, 0x41, 0x4D, 0x20, 0x24, 0x30, 0x30, 0x30, 0x30, 0x2D, 0x24, 0x37, 0x46, 0x46
    #d8 0x46, 0x20, 0x7C, 0x20, 0x42, 0x49, 0x4F, 0x53, 0x20, 0x24, 0x38, 0x30, 0x30, 0x30, 0x2D, 0x24
    #d8 0x39, 0x46, 0x46, 0x46, 0x20, 0x7C, 0x20, 0x43, 0x41, 0x52, 0x54, 0x20, 0x24, 0x41, 0x30, 0x30
    #d8 0x30, 0x2D, 0x24, 0x45, 0x46, 0x46, 0x46, 0x2E, 0x0D, 0x0A, 0x56, 0x69, 0x64, 0x65, 0x6F, 0x20
    #d8 0x36, 0x34, 0x30, 0x78, 0x34, 0x38, 0x30, 0x20, 0x34, 0x3A, 0x33, 0x3A, 0x20, 0x74, 0x65, 0x78
    #d8 0x74, 0x6F, 0x20, 0x38, 0x30, 0x78, 0x36, 0x30, 0x3B, 0x20, 0x6D, 0x6F, 0x6E, 0x6F, 0x20, 0x33
    #d8 0x32, 0x30, 0x78, 0x32, 0x34, 0x30, 0x3B, 0x20, 0x31, 0x36, 0x20, 0x63, 0x6F, 0x72, 0x65, 0x73
    #d8 0x20, 0x31, 0x36, 0x30, 0x78, 0x31, 0x32, 0x30, 0x2E, 0x0D, 0x0A, 0x46, 0x32, 0x30, 0x30, 0x20
    #d8 0x44, 0x41, 0x54, 0x41, 0x20, 0x7C, 0x20, 0x46, 0x32, 0x30, 0x31, 0x20, 0x43, 0x4D, 0x44, 0x2F
    #d8 0x4D, 0x4F, 0x44, 0x4F, 0x20, 0x7C, 0x20, 0x46, 0x32, 0x30, 0x32, 0x2F, 0x46, 0x32, 0x30, 0x33
    #d8 0x20, 0x43, 0x55, 0x52, 0x53, 0x4F, 0x52, 0x2F, 0x56, 0x52, 0x41, 0x4D, 0x2E, 0x0D, 0x0A, 0x00
STR_NO_CARD:
    #d8 0x4E, 0x65, 0x6E, 0x68, 0x75, 0x6D, 0x20, 0x63, 0x61, 0x72, 0x74, 0x75, 0x63, 0x68, 0x6F, 0x20
    #d8 0x64, 0x65, 0x74, 0x65, 0x63, 0x74, 0x61, 0x64, 0x6F, 0x2E, 0x0D, 0x0A, 0x00
STR_PROMPT:
    #d8 0x3E, 0x20, 0x00
STR_RANGE:
    #d8 0x56, 0x61, 0x6C, 0x6F, 0x72, 0x20, 0x66, 0x6F, 0x72, 0x61, 0x20, 0x64, 0x65, 0x20, 0x30, 0x2E
    #d8 0x2E, 0x32, 0x35, 0x35, 0x2E, 0x0D, 0x0A, 0x00
STR_READ_DEC:
    #d8 0x20, 0x64, 0x65, 0x63, 0x20, 0x00
STR_READ_MID:
    #d8 0x5D, 0x20, 0x3D, 0x20, 0x24, 0x00
STR_READ_OPEN:
    #d8 0x5B, 0x24, 0x00
STR_REBOOT:
    #d8 0x52, 0x65, 0x69, 0x6E, 0x69, 0x63, 0x69, 0x61, 0x6E, 0x64, 0x6F, 0x20, 0x57, 0x41, 0x4C, 0x4C
    #d8 0x2D, 0x38, 0x2E, 0x2E, 0x2E, 0x0D, 0x0A, 0x00
STR_RESULT_END:
    #d8 0x29, 0x0D, 0x0A, 0x00
STR_RESULT_HEX:
    #d8 0x20, 0x28, 0x24, 0x00
STR_RESULT_PREFIX:
    #d8 0x3D, 0x20, 0x00
STR_RUN_ADDR:
    #d8 0x43, 0x68, 0x61, 0x6D, 0x61, 0x6E, 0x64, 0x6F, 0x20, 0x70, 0x72, 0x6F, 0x67, 0x72, 0x61, 0x6D
    #d8 0x61, 0x20, 0x65, 0x6D, 0x20, 0x24, 0x00
STR_RUN_B:
    #d8 0x20, 0x42, 0x3D, 0x24, 0x00
STR_RUN_CARD:
    #d8 0x45, 0x78, 0x65, 0x63, 0x75, 0x74, 0x61, 0x6E, 0x64, 0x6F, 0x20, 0x63, 0x61, 0x72, 0x74, 0x75
    #d8 0x63, 0x68, 0x6F, 0x20, 0x65, 0x6D, 0x20, 0x24, 0x41, 0x30, 0x30, 0x30, 0x2E, 0x2E, 0x2E, 0x0D
    #d8 0x0A, 0x00
STR_RUN_RETURN:
    #d8 0x50, 0x72, 0x6F, 0x67, 0x72, 0x61, 0x6D, 0x61, 0x20, 0x72, 0x65, 0x74, 0x6F, 0x72, 0x6E, 0x6F
    #d8 0x75, 0x3A, 0x20, 0x41, 0x3D, 0x24, 0x00
STR_SOUND_SET:
    #d8 0x53, 0x4F, 0x55, 0x4E, 0x44, 0x20, 0x24, 0x46, 0x34, 0x30, 0x30, 0x3D, 0x24, 0x00
STR_STATUS_HEX:
    #d8 0x53, 0x54, 0x41, 0x54, 0x55, 0x53, 0x20, 0x24, 0x46, 0x33, 0x30, 0x30, 0x3D, 0x24, 0x00
STR_SYNTAX:
    #d8 0x53, 0x69, 0x6E, 0x74, 0x61, 0x78, 0x65, 0x20, 0x69, 0x6E, 0x76, 0x61, 0x6C, 0x69, 0x64, 0x61
    #d8 0x2E, 0x20, 0x44, 0x69, 0x67, 0x69, 0x74, 0x65, 0x20, 0x48, 0x45, 0x4C, 0x50, 0x2E, 0x0D, 0x0A
    #d8 0x00
STR_TIMER_CLEARED:
    #d8 0x54, 0x69, 0x6D, 0x65, 0x72, 0x73, 0x20, 0x6C, 0x69, 0x6D, 0x70, 0x6F, 0x73, 0x2E, 0x0D, 0x0A
    #d8 0x00
STR_VERSION:
    #d8 0x57, 0x41, 0x4C, 0x4C, 0x2D, 0x38, 0x20, 0x42, 0x49, 0x4F, 0x53, 0x20, 0x4D, 0x6F, 0x6E, 0x69
    #d8 0x74, 0x6F, 0x72, 0x20, 0x76, 0x33, 0x2E, 0x30, 0x0D, 0x0A, 0x00
STR_VIDEO_OFF:
    #d8 0x56, 0x49, 0x44, 0x45, 0x4F, 0x3D, 0x4F, 0x46, 0x46, 0x20, 0x00
STR_VIDEO_ON:
    #d8 0x56, 0x49, 0x44, 0x45, 0x4F, 0x3D, 0x4F, 0x4E, 0x20, 0x00
STR_WRITE_MID:
    #d8 0x5D, 0x20, 0x3C, 0x3D, 0x20, 0x24, 0x00
STR_WRITE_OPEN:
    #d8 0x4F, 0x4B, 0x20, 0x5B, 0x24, 0x00

#addr 0x9FFD
BIOS_END_VECTOR:
    JMP BIOS_MAIN
