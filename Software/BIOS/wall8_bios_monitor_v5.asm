#include "../wall8.cpu"

#bankdef bios {
    #addr 0x0000
    #size 0xA000
    #outp 0x0000
}

; ============================================================
; WALL-8 BIOS / Monitor v5.0
; Boot visual, terminal interativo, contexto de registradores e histórico da BIOS.
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
MON_A             = 0x024D       ; A carregado antes de RUN/GO/CARD
MON_B             = 0x024E       ; B carregado antes de RUN/GO/CARD
MON_PTR_HI        = 0x024F       ; PTR do contexto de execucao
MON_PTR_LO        = 0x0250
MON_SP_HI         = 0x0251       ; SP do contexto de execucao
MON_SP_LO         = 0x0252
RUN_KIND          = 0x0253       ; 0=RUN comum, 1=CARD
BOOT_FLAGS        = 0x02B2       ; bit0 RAM OK, bit1 VIDEO, bit2 CARD
BOOT_STATUS       = 0x02B3       ; snapshot de SYSTEM_STATUS no boot
DUMP_COUNT        = 0x02B4       ; bytes restantes em DUMP
DUMP_COL          = 0x02B5       ; colunas restantes na linha do DUMP
FILL_COUNT        = 0x02B6       ; bytes restantes em FILL

; ------------------------------------------------------------
; Memória de edição e histórico do terminal
; ------------------------------------------------------------
; LAST_CMD guarda até 76 caracteres do último comando confirmado
; com Enter. A tecla TAB copia essa linha de volta para CMD_BUFFER,
; deixando-a apenas editada na tela; a execução só acontece depois
; de um novo Enter.
LAST_CMD          = 0x0350       ; 79 bytes: 0350h..039Eh
LAST_LEN          = 0x02A0

; O histórico pertence ao WALL-8, não ao widget do emulador.
; A BIOS mantém 128 linhas de 80 caracteres a partir de 4C00h.
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
HIST_WRAP_PENDING = 0x02AD       ; linha avançou por completar 80 colunas
OUTPUT_CHAR       = 0x02AE       ; preserva o byte enquanto o histórico trabalha
VIDEO_BATCH          = 0x02AF       ; 0=saída imediata, 1=lote do comando em RAM
VIDEO_REDRAW_PENDING = 0x02B0       ; VIEW_TOP mudou e a tela precisa ser redesenhada
VIDEO_OLD_VIEW_TOP   = 0x02B1       ; valor anterior usado para detectar mudança da janela

HIST_BASE         = 0x4C00
HIST_CAPACITY     = 0x0080       ; 128 linhas
TEXT_WIDTH        = 0x0050       ; 80 caracteres
TEXT_HEIGHT       = 0x001E       ; 30 linhas = 640x480 com duplicacao vertical
CMD_MAX           = 0x004C       ; 76 + prompt W8> de 4 células = 80 colunas

#bank bios

#addr 0x0000
RESET:
    ; A metade baixa ainda aponta para a EPROM. Esta etapa não usa CALL nem
    ; PUSH: a pilha só passa a ser confiável depois do swap e da limpeza da RAM.
    SP $7FFF
    STI CPU_CFG, #$70       ; overlay de boot ativo, configuração base preservada
    STI SOUND_CFG, #$00     ; som desligado
    STI PERIPH_CFG, #$00    ; display em hexadecimal, LEDs no padrão
    STI DISPLAY_LOW, #$00
    STI DISPLAY_HIGH, #$00
    STI SYSTEM_STATUS, #$00 ; limpa os latches de 1 ms e 500 ms

    ; Prepara a GPU e desenha uma tela completa armazenada na região da EPROM
    ; que desaparecerá de 0000h..7FFFh depois do swap.
    STI VIDEO_CMD, #$11     ; texto 80x30, fonte 8x8, duplicação vertical
BOOT_MODE_WAIT:
    LDA VIDEO_STATUS
    TEST A, #$01
    JNZ BOOT_MODE_WAIT
    STI VIDEO_CMD, #$00     ; limpa os 2.400 caracteres da VRAM
BOOT_CLEAR_WAIT:
    LDA VIDEO_STATUS
    TEST A, #$01
    JNZ BOOT_CLEAR_WAIT
    STI VIDEO_X, #$00
    STI VIDEO_Y, #$00
    STI VIDEO_CMD, #$04     ; cursor invisível durante o splash

    PTR BOOT_SPLASH
BOOT_SPLASH_LOOP:
    LDA [PTR+]
    CMP A, #$00
    JZ BOOT_SPLASH_DONE
    MOV B, A
BOOT_SPLASH_WAIT:
    LDA VIDEO_STATUS
    TEST A, #$01
    JNZ BOOT_SPLASH_WAIT
    MOV A, B
    STA VIDEO_DATA
    JMP BOOT_SPLASH_LOOP

BOOT_SPLASH_DONE:
    ; A barra tem 48 células. As primeiras seis confirmam ROM e vídeo.
BOOT_SPLASH_LAST_WAIT:
    LDA VIDEO_STATUS
    TEST A, #$01
    JNZ BOOT_SPLASH_LAST_WAIT
    STI VIDEO_X, #$10       ; coluna 16: primeira célula dentro do '['
    STI VIDEO_Y, #$17       ; linha 23
    LDB #$06
BOOT_ROM_BAR_LOOP:
    LDA VIDEO_STATUS
    TEST A, #$01
    JNZ BOOT_ROM_BAR_LOOP
    LDA #$23                ; '#'
    STA VIDEO_DATA
    DEC B
    JNZ BOOT_ROM_BAR_LOOP

    ; Mantém o logotipo visível antes do trabalho rápido de inicialização.
    STI SYSTEM_STATUS, #$00
BOOT_SPLASH_HOLD:
    LDA SYSTEM_STATUS
    TEST A, #$02            ; latch de 500 ms
    JZ BOOT_SPLASH_HOLD
    JMP BIOS_MAIN

; ------------------------------------------------------------
; Imagem textual 80x30 do splash. Ela existe somente no overlay.
; CR avança uma linha na GPU; 00h encerra o fluxo.
; ------------------------------------------------------------
BOOT_SPLASH:
    #d8 0x0D, 0x0D, 0x20, 0x20, 0x20, 0x20, 0x20, 0x23, 0x23, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x23
    #d8 0x23, 0x20, 0x20, 0x20, 0x20, 0x23, 0x23, 0x23, 0x23, 0x23, 0x23, 0x20, 0x20, 0x20, 0x20, 0x23
    #d8 0x23, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x23, 0x23, 0x20, 0x20, 0x20
    #d8 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20
    #d8 0x20, 0x20, 0x20, 0x20, 0x20, 0x23, 0x23, 0x23, 0x23, 0x23, 0x23, 0x0D, 0x20, 0x20, 0x20, 0x20
    #d8 0x20, 0x23, 0x23, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x23, 0x23, 0x20, 0x20, 0x20, 0x20, 0x23
    #d8 0x23, 0x23, 0x23, 0x23, 0x23, 0x20, 0x20, 0x20, 0x20, 0x23, 0x23, 0x20, 0x20, 0x20, 0x20, 0x20
    #d8 0x20, 0x20, 0x20, 0x20, 0x20, 0x23, 0x23, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20
    #d8 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x23
    #d8 0x23, 0x23, 0x23, 0x23, 0x23, 0x0D, 0x20, 0x20, 0x20, 0x20, 0x20, 0x23, 0x23, 0x20, 0x20, 0x20
    #d8 0x20, 0x20, 0x20, 0x23, 0x23, 0x20, 0x20, 0x23, 0x23, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x23
    #d8 0x23, 0x20, 0x20, 0x23, 0x23, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x23
    #d8 0x23, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20
    #d8 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x23, 0x23, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x23
    #d8 0x23, 0x0D, 0x20, 0x20, 0x20, 0x20, 0x20, 0x23, 0x23, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x23
    #d8 0x23, 0x20, 0x20, 0x23, 0x23, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x23, 0x23, 0x20, 0x20, 0x23
    #d8 0x23, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x23, 0x23, 0x20, 0x20, 0x20
    #d8 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20
    #d8 0x20, 0x20, 0x20, 0x23, 0x23, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x23, 0x23, 0x0D, 0x20, 0x20
    #d8 0x20, 0x20, 0x20, 0x23, 0x23, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x23, 0x23, 0x20, 0x20, 0x23
    #d8 0x23, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x23, 0x23, 0x20, 0x20, 0x23, 0x23, 0x20, 0x20, 0x20
    #d8 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x23, 0x23, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20
    #d8 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x23
    #d8 0x23, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x23, 0x23, 0x0D, 0x20, 0x20, 0x20, 0x20, 0x20, 0x23
    #d8 0x23, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x23, 0x23, 0x20, 0x20, 0x23, 0x23, 0x20, 0x20, 0x20
    #d8 0x20, 0x20, 0x20, 0x23, 0x23, 0x20, 0x20, 0x23, 0x23, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20
    #d8 0x20, 0x20, 0x20, 0x23, 0x23, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20
    #d8 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x23, 0x23, 0x20, 0x20, 0x20
    #d8 0x20, 0x20, 0x20, 0x23, 0x23, 0x0D, 0x20, 0x20, 0x20, 0x20, 0x20, 0x23, 0x23, 0x20, 0x20, 0x23
    #d8 0x23, 0x20, 0x20, 0x23, 0x23, 0x20, 0x20, 0x23, 0x23, 0x23, 0x23, 0x23, 0x23, 0x23, 0x23, 0x23
    #d8 0x23, 0x20, 0x20, 0x23, 0x23, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x23
    #d8 0x23, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x23, 0x23, 0x23, 0x23, 0x23
    #d8 0x23, 0x23, 0x23, 0x23, 0x23, 0x20, 0x20, 0x20, 0x20, 0x23, 0x23, 0x23, 0x23, 0x23, 0x23, 0x0D
    #d8 0x20, 0x20, 0x20, 0x20, 0x20, 0x23, 0x23, 0x20, 0x20, 0x23, 0x23, 0x20, 0x20, 0x23, 0x23, 0x20
    #d8 0x20, 0x23, 0x23, 0x23, 0x23, 0x23, 0x23, 0x23, 0x23, 0x23, 0x23, 0x20, 0x20, 0x23, 0x23, 0x20
    #d8 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x23, 0x23, 0x20, 0x20, 0x20, 0x20, 0x20
    #d8 0x20, 0x20, 0x20, 0x20, 0x20, 0x23, 0x23, 0x23, 0x23, 0x23, 0x23, 0x23, 0x23, 0x23, 0x23, 0x20
    #d8 0x20, 0x20, 0x20, 0x23, 0x23, 0x23, 0x23, 0x23, 0x23, 0x0D, 0x20, 0x20, 0x20, 0x20, 0x20, 0x23
    #d8 0x23, 0x20, 0x20, 0x23, 0x23, 0x20, 0x20, 0x23, 0x23, 0x20, 0x20, 0x23, 0x23, 0x20, 0x20, 0x20
    #d8 0x20, 0x20, 0x20, 0x23, 0x23, 0x20, 0x20, 0x23, 0x23, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20
    #d8 0x20, 0x20, 0x20, 0x23, 0x23, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20
    #d8 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x23, 0x23, 0x20, 0x20, 0x20
    #d8 0x20, 0x20, 0x20, 0x23, 0x23, 0x0D, 0x20, 0x20, 0x20, 0x20, 0x20, 0x23, 0x23, 0x20, 0x20, 0x23
    #d8 0x23, 0x20, 0x20, 0x23, 0x23, 0x20, 0x20, 0x23, 0x23, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x23
    #d8 0x23, 0x20, 0x20, 0x23, 0x23, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x23
    #d8 0x23, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20
    #d8 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x23, 0x23, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x23
    #d8 0x23, 0x0D, 0x20, 0x20, 0x20, 0x20, 0x20, 0x23, 0x23, 0x23, 0x23, 0x20, 0x20, 0x23, 0x23, 0x23
    #d8 0x23, 0x20, 0x20, 0x23, 0x23, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x23, 0x23, 0x20, 0x20, 0x23
    #d8 0x23, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x23, 0x23, 0x20, 0x20, 0x20
    #d8 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20
    #d8 0x20, 0x20, 0x20, 0x23, 0x23, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x23, 0x23, 0x0D, 0x20, 0x20
    #d8 0x20, 0x20, 0x20, 0x23, 0x23, 0x23, 0x23, 0x20, 0x20, 0x23, 0x23, 0x23, 0x23, 0x20, 0x20, 0x23
    #d8 0x23, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x23, 0x23, 0x20, 0x20, 0x23, 0x23, 0x20, 0x20, 0x20
    #d8 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x23, 0x23, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20
    #d8 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x23
    #d8 0x23, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x23, 0x23, 0x0D, 0x20, 0x20, 0x20, 0x20, 0x20, 0x23
    #d8 0x23, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x23, 0x23, 0x20, 0x20, 0x23, 0x23, 0x20, 0x20, 0x20
    #d8 0x20, 0x20, 0x20, 0x23, 0x23, 0x20, 0x20, 0x23, 0x23, 0x23, 0x23, 0x23, 0x23, 0x23, 0x23, 0x23
    #d8 0x23, 0x20, 0x20, 0x23, 0x23, 0x23, 0x23, 0x23, 0x23, 0x23, 0x23, 0x23, 0x23, 0x20, 0x20, 0x20
    #d8 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x23, 0x23, 0x23
    #d8 0x23, 0x23, 0x23, 0x0D, 0x20, 0x20, 0x20, 0x20, 0x20, 0x23, 0x23, 0x20, 0x20, 0x20, 0x20, 0x20
    #d8 0x20, 0x23, 0x23, 0x20, 0x20, 0x23, 0x23, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x23, 0x23, 0x20
    #d8 0x20, 0x23, 0x23, 0x23, 0x23, 0x23, 0x23, 0x23, 0x23, 0x23, 0x23, 0x20, 0x20, 0x23, 0x23, 0x23
    #d8 0x23, 0x23, 0x23, 0x23, 0x23, 0x23, 0x23, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20
    #d8 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x23, 0x23, 0x23, 0x23, 0x23, 0x23, 0x0D, 0x0D, 0x20
    #d8 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20
    #d8 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x44, 0x49, 0x53, 0x43, 0x52
    #d8 0x45, 0x54, 0x45, 0x20, 0x38, 0x2D, 0x42, 0x49, 0x54, 0x20, 0x43, 0x4F, 0x4D, 0x50, 0x55, 0x54
    #d8 0x45, 0x52, 0x0D, 0x0D, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20
    #d8 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20
    #d8 0x57, 0x41, 0x4C, 0x4C, 0x2D, 0x38, 0x20, 0x42, 0x49, 0x4F, 0x53, 0x20, 0x4D, 0x4F, 0x4E, 0x49
    #d8 0x54, 0x4F, 0x52, 0x20, 0x76, 0x35, 0x2E, 0x30, 0x0D, 0x0D, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20
    #d8 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20
    #d8 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x49, 0x4E, 0x49, 0x54, 0x49, 0x41, 0x4C, 0x49, 0x5A
    #d8 0x49, 0x4E, 0x47, 0x20, 0x48, 0x41, 0x52, 0x44, 0x57, 0x41, 0x52, 0x45, 0x0D, 0x0D, 0x20, 0x20
    #d8 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x5B, 0x20, 0x20
    #d8 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20
    #d8 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20
    #d8 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x5D, 0x0D
    #d8 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20
    #d8 0x20, 0x20, 0x20, 0x52, 0x4F, 0x4D, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x56, 0x49
    #d8 0x44, 0x45, 0x4F, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x52, 0x41, 0x4D, 0x20, 0x20
    #d8 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x53, 0x59, 0x53, 0x54, 0x45, 0x4D, 0x0D, 0x20, 0x20, 0x20
    #d8 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20
    #d8 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x42, 0x79, 0x3A, 0x20, 0x56, 0x69
    #d8 0x6E, 0x69, 0x63, 0x69, 0x75, 0x73, 0x20, 0x4A, 0x65, 0x73, 0x75, 0x73, 0x00

#addr 0x8000
BIOS_MAIN:
    STI CPU_CFG, #$71       ; bit0=1: RAM em 0000h..7FFFh; BIOS fixa permanece

    ; Limpa fisicamente toda a SRAM antes de qualquer CALL. O contador de
    ; páginas mora em 0000h; por isso 0100h..7FFFh é limpo primeiro e a página
    ; 0000h..00FFh fica por último. Nenhum endereço da RAM é preservado.
    STI $0000, #$7F
    PTR $0100
BOOT_RAM_CLEAR_NEXT_PAGE:
    LDB #$00
BOOT_RAM_CLEAR_BYTE:
    CLR A
    STA [PTR+]
    DEC B
    JNZ BOOT_RAM_CLEAR_BYTE

    LDA $0000
    DEC A
    STA $0000
    JZ BOOT_RAM_CLEAR_LOW_PAGE
    TEST A, #$03
    JNZ BOOT_RAM_CLEAR_NEXT_PAGE

    ; Uma célula da barra a cada quatro páginas concluídas (31 células).
BOOT_RAM_MARK_WAIT:
    LDA VIDEO_STATUS
    TEST A, #$01
    JNZ BOOT_RAM_MARK_WAIT
    LDA #$23
    STA VIDEO_DATA
    JMP BOOT_RAM_CLEAR_NEXT_PAGE

BOOT_RAM_CLEAR_LOW_PAGE:
    PTR $0000
    LDB #$00
BOOT_RAM_CLEAR_LOW_BYTE:
    CLR A
    STA [PTR+]
    DEC B
    JNZ BOOT_RAM_CLEAR_LOW_BYTE

    ; Marca a página baixa: RAM completa, 32 células novas na barra.
BOOT_RAM_LAST_MARK_WAIT:
    LDA VIDEO_STATUS
    TEST A, #$01
    JNZ BOOT_RAM_LAST_MARK_WAIT
    LDA #$23
    STA VIDEO_DATA
    SP $7FFF

    ; Teste destrutivo curto nas extremidades da área livre. A limpeza completa
    ; já exercitou todas as células com zero; os padrões verificam escrita/leitura.
    STI BOOT_FLAGS, #$01
    STI $0400, #$A5
    LDA $0400
    CMP A, #$A5
    JNZ BOOT_RAM_TEST_FAIL
    STI $7EFE, #$5A
    LDA $7EFE
    CMP A, #$5A
    JZ BOOT_RAM_TEST_DONE
BOOT_RAM_TEST_FAIL:
    STI BOOT_FLAGS, #$00
BOOT_RAM_TEST_DONE:
    STI $0400, #$00
    STI $7EFE, #$00
    CALL BOOT_BAR_FILL2

    ; Trampolins em RAM para acesso por endereço variável.
    ; 0100: STA $xxxx / RET
    ; 010B: LDA $xxxx / RET
    STI $0100, #$14
    STI $0101, #$00
    STI $0102, #$00
    STI $0103, #$5A
    STI $010B, #$12
    STI $010C, #$00
    STI $010D, #$00
    STI $010E, #$5A

    ; 0110: PTR $xxxx / RET; 0114: STA $xxxx / RET.
    STI $0110, #$20
    STI $0111, #$00
    STI $0112, #$00
    STI $0113, #$5A
    STI $0114, #$14
    STI $0115, #$00
    STI $0116, #$00
    STI $0117, #$5A

    ; Trampolim de execução com contexto configurável pelo monitor.
    ; 0120: LDA #aa / LDB #bb / PTR $pppp / SP $ssss
    ; 012A: CALL ou JMP $xxxx; 012D: restaura SP e volta à BIOS.
    STI $0120, #$10
    STI $0122, #$11
    STI $0124, #$20
    STI $0127, #$5F
    STI $012A, #$59
    STI $012D, #$5F
    STI $012E, #$FF
    STI $012F, #$7F
    STI $0130, #$50
    STI $0131, #RUN_CONTEXT_RETURN[7:0]
    STI $0132, #RUN_CONTEXT_RETURN[15:8]
    CALL BOOT_BAR_FILL2

    ; Contexto e buffers do monitor começam sempre em estado determinístico.
    STI MON_A, #$00
    STI MON_B, #$00
    STI MON_PTR_HI, #$04
    STI MON_PTR_LO, #$00
    STI MON_SP_HI, #$7F
    STI MON_SP_LO, #$FF
    STI RUN_KIND, #$00
    STI CMD_LEN, #$00
    STI PARSE_OK, #$00
    STI LAST_LEN, #$00
    CALL BOOT_BAR_FILL2

    ; Registra os periféricos presentes no instante do boot. CARD_DETECT e
    ; VIDEO_DETECT são ativos em zero em SYSTEM_STATUS.
    LDA SYSTEM_STATUS
    STA BOOT_STATUS
    TEST A, #$20
    JNZ BOOT_DEVICE_VIDEO_DONE
    LDA BOOT_FLAGS
    OR A, #$02
    STA BOOT_FLAGS
BOOT_DEVICE_VIDEO_DONE:
    LDA BOOT_STATUS
    TEST A, #$10
    JNZ BOOT_DEVICE_CARD_DONE
    LDA BOOT_FLAGS
    OR A, #$04
    STA BOOT_FLAGS
BOOT_DEVICE_CARD_DONE:
    STI SYSTEM_STATUS, #$00
    STI SOUND_CFG, #$00
    STI PERIPH_CFG, #$00
    STI DISPLAY_LOW, #$00
    STI DISPLAY_HIGH, #$00
    CALL BOOT_BAR_FILL2

    ; Última fase: conclui as 48 células da barra.
    CALL BOOT_BAR_FILL2

    ; Assinatura sonora curta de inicialização, depois de RAM e periféricos OK.
    CALL SOUND_STARTUP

    ; A barra completa fica visível por mais meio segundo antes do terminal.
    STI SYSTEM_STATUS, #$00
BOOT_READY_HOLD:
    LDA SYSTEM_STATUS
    TEST A, #$02
    JZ BOOT_READY_HOLD

    ; Inicializa a tela 80x30 e o histórico depois que o splash terminou.
    CALL HISTORY_RESET

    PTR STR_BANNER
    CALL PRINT_STRING
    CALL PRINT_BOOT_SUMMARY
    PTR STR_PROMPT
    CALL PRINT_STRING
    JMP SHELL_LOOP


; Preenche duas células da barra. Só é chamada depois da limpeza da RAM.
BOOT_BAR_FILL2:
    LDB #$02
BOOT_BAR_FILL2_LOOP:
    CALL VIDEO_WAIT
    LDA #$23
    STA VIDEO_DATA
    DEC B
    JNZ BOOT_BAR_FILL2_LOOP
    RET

; ============================================================
; Assinaturas sonoras do sistema
; ============================================================
; $F400: bits 4..2=TONE, bit1=TONE_EN, bit0=NOISE_EN.
; Os dois sons usam somente TONE. SOUND_PLAY_NOTE recebe o valor em A
; e a duração em B, medida pelo latch de aproximadamente 1 ms de $F300.

SOUND_DELAY_B:
    STI SYSTEM_STATUS, #$00
SOUND_DELAY_B_WAIT:
    LDA SYSTEM_STATUS
    TEST A, #$01
    JZ SOUND_DELAY_B_WAIT
    DEC B
    JNZ SOUND_DELAY_B
    RET

SOUND_PLAY_NOTE:
    STA SOUND_CFG
    CALL SOUND_DELAY_B
    STI SOUND_CFG, #$00
    LDB #$06                ; intervalo de aproximadamente 12 ms
    CALL SOUND_DELAY_B
    RET

; Inicialização ascendente: D4, G4, B4 e C5.
SOUND_STARTUP:
    LDA #$1A
    LDB #$30                ; 48 ms
    CALL SOUND_PLAY_NOTE
    LDA #$0E
    LDB #$38                ; 56 ms
    CALL SOUND_PLAY_NOTE
    LDA #$06
    LDB #$38                ; 56 ms
    CALL SOUND_PLAY_NOTE
    LDA #$02
    LDB #$60                ; 96 ms
    CALL SOUND_PLAY_NOTE
    RET

; Desligamento descendente: C5, A4, F4 e C4.
SOUND_SHUTDOWN:
    LDA #$02
    LDB #$28                ; 40 ms
    CALL SOUND_PLAY_NOTE
    LDA #$0A
    LDB #$30                ; 48 ms
    CALL SOUND_PLAY_NOTE
    LDA #$12
    LDB #$38                ; 56 ms
    CALL SOUND_PLAY_NOTE
    LDA #$1E
    LDB #$58                ; 88 ms
    CALL SOUND_PLAY_NOTE
    STI SOUND_CFG, #$00
    RET

; Linha de diagnóstico exibida no início de cada sessão do monitor.
PRINT_BOOT_SUMMARY:
    PTR STR_BOOT_PREFIX
    CALL PRINT_STRING
    LDA BOOT_FLAGS
    TEST A, #$01
    JZ PRINT_BOOT_RAM_FAIL
    PTR STR_BOOT_RAM_OK
    CALL PRINT_STRING
    JMP PRINT_BOOT_VIDEO
PRINT_BOOT_RAM_FAIL:
    PTR STR_BOOT_RAM_FAIL
    CALL PRINT_STRING
PRINT_BOOT_VIDEO:
    LDA BOOT_FLAGS
    TEST A, #$02
    JZ PRINT_BOOT_VIDEO_OFF
    PTR STR_VIDEO_ON
    CALL PRINT_STRING
    JMP PRINT_BOOT_CARD
PRINT_BOOT_VIDEO_OFF:
    PTR STR_VIDEO_OFF
    CALL PRINT_STRING
PRINT_BOOT_CARD:
    LDA BOOT_FLAGS
    TEST A, #$04
    JZ PRINT_BOOT_CARD_OFF
    PTR STR_CARD_ON
    CALL PRINT_STRING
    JMP PRINT_BOOT_DONE
PRINT_BOOT_CARD_OFF:
    PTR STR_CARD_OFF
    CALL PRINT_STRING
PRINT_BOOT_DONE:
    CALL PRINT_NEWLINE
    RET

SHELL_LOOP:
    CALL READ_LINE
    CALL DISPATCH

SHELL_COMMAND_DONE:
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
; O buffer aceita 76 caracteres: com o prompt "W8> " ocupa as 80 colunas.
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
    CMP B, #$4C
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
    ; Segundo terminador: o despachante consome o primeiro byte 00 ao
    ; reconhecer um comando sem argumentos. Assim o parser seguinte ainda
    ; encontra fim de linha, nunca lixo deixado por um comando anterior.
    INC PTR
    STA [PTR]
    DEC PTR

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
; Texto 80x30 / fonte 8x8 / duplicação vertical / VGA 640x480
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

    ; Ao concluir a coluna 79, a GPU incrementa X/Y antes de baixar BUSY.
    ; A flag mantém a política de CR/LF da BIOS alinhada com esse avanço.
    STI HIST_WRAP_PENDING, #$00
    LDA OUTPUT_CHAR
    CALL HISTORY_WRITE_RAW

    LDA HIST_COL
    INC A
    STA HIST_COL
    CMP A, #$50
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
    ; CR executa a quebra. Se a linha acabou exatamente na coluna 79,
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
;   4C00h + linha*80 + coluna
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
    STI VIDEO_CMD, #$11          ; garante modo texto 80x30
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

; Limpa os 80 bytes da linha apontada por HIST_PTR, mas restaura o
; ponteiro ao início. Isso garante que posições ainda não escritas sejam
; espaços mesmo em uma SRAM física que ligue com conteúdo indefinido.
HISTORY_CLEAR_CURRENT_LINE:
    LDA HIST_PTR_HI
    STA HIST_WORK_HI
    LDA HIST_PTR_LO
    STA HIST_WORK_LO
    STI HIST_COUNT, #$50
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
    ADD A, #$50
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

; Nova linha explícita antes da coluna 80: pula as células restantes
; para que o próximo texto comece no início da linha seguinte.
HISTORY_NEWLINE:
    LDA #$50
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
    STI HIST_COL, #$50
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

; Calcula HIST_BASE + VIEW_TOP*80 por adições sucessivas. A rotina é
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
    ADD A, #$50
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

; Redesenha exclusivamente as 30 linhas visíveis.
; o conteúdo mostrado é exatamente o selecionado
; por VIEW_TOP dentro da RAM do WALL-8.
HISTORY_REDRAW:
    ; O redraw usa somente a RAM de histórico como fonte. VIDEO_X e VIDEO_Y
    ; são definidos uma única vez; as 2.400 escritas seguintes usam o
    ; incremento automático da GPU.
    STI VIDEO_REDRAW_PENDING, #$00
    CALL VIDEO_WAIT
    STI VIDEO_CMD, #$04          ; esconde cursor durante a cópia
    STI VIDEO_X, #$00            ; também limpa CURSOR_END
    STI VIDEO_Y, #$00

    CALL HISTORY_CALC_VIEW_ADDRESS
    STI HIST_ROW, #$00

HISTORY_REDRAW_ROW_LOOP:
    STI HIST_COUNT, #$50

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

    ; A última escrita pode ter ativado CURSOR_END em (79,29). Espera sua
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
; PARSE_U8 usa hexadecimal por padrao: 50, $50 e 0x50 valem 50h.
; O prefixo # seleciona decimal: #50 vale 32h. PARSE_HEX16 recebe
; enderecos de quatro digitos. As rotinas usam PARSE_OK para nao
; depender das flags depois de chamadas auxiliares.
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
    CMP A, #$23
    JZ PARSE_U8_DEC_PREFIX
    CMP A, #$24
    JZ PARSE_U8_HEX_PREFIX
    CMP A, #$42
    JZ PARSE_U8_BIN_PREFIX
    CMP A, #$30
    JNZ PARSE_U8_HEX_LOOP
    INC PTR
    LDA [PTR]
    CMP A, #$58
    JZ PARSE_U8_0X
    CMP A, #$42
    JZ PARSE_U8_0B
    LDA #$01
    STA $0244
    JMP PARSE_U8_HEX_LOOP
PARSE_U8_0X:
    INC PTR
    JMP PARSE_U8_HEX_LOOP
PARSE_U8_0B:
    INC PTR
    JMP PARSE_U8_BIN_LOOP
PARSE_U8_HEX_PREFIX:
    INC PTR
    JMP PARSE_U8_HEX_LOOP
PARSE_U8_BIN_PREFIX:
    INC PTR
    JMP PARSE_U8_BIN_LOOP
PARSE_U8_DEC_PREFIX:
    INC PTR
    JMP PARSE_U8_DEC_LOOP
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

; Binário aceita Bxxxxxxxx e 0Bxxxxxxxx. READ_LINE converte b para B.
; São permitidos de 1 a 8 bits; qualquer outro caractere ou o 9º bit falha.
PARSE_U8_BIN_LOOP:
    LDA [PTR]
    CMP A, #$00
    JZ PARSE_U8_FINISH
    CMP A, #$20
    JZ PARSE_U8_FINISH
    CMP A, #$30
    JZ PARSE_U8_BIN_DIGIT
    CMP A, #$31
    JNZ PARSE_U8_FAIL
PARSE_U8_BIN_DIGIT:
    SUB A, #$30
    STA $0243
    LDA $0244
    CMP A, #$08
    JC PARSE_U8_FAIL
    LDA $0242
    SHL A
    LDB $0243
    OR A, B
    STA $0242
    INC PTR
    LDA $0244
    INC A
    STA $0244
    JMP PARSE_U8_BIN_LOOP
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

; Confirma que, depois do ultimo argumento, restam somente espacos.
; Mantem a politica do monitor deterministica e rejeita texto excedente.
PARSE_REQUIRE_END:
    CALL SKIP_SPACES
    LDA [PTR]
    CMP A, #$00
    JZ PARSE_REQUIRE_END_OK
    STI PARSE_OK, #$00
    RET
PARSE_REQUIRE_END_OK:
    STI PARSE_OK, #$01
    RET

PARSE_ONE_U8:
    CALL PARSE_U8
    LDB $0241
    CMP B, #$01
    JNZ PARSE_ONE_DONE
    STA $0245
    CALL PARSE_REQUIRE_END
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
    CALL PARSE_REQUIRE_END
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
    ; ARG1 e exclusivo da operacao neste ponto. TEMP2 nao pode guardar o
    ; resultado porque PUT_CHAR/HISTORY_POKE o usa para cada caractere.
    STA ARG1
    PTR STR_RESULT_PREFIX
    CALL PRINT_STRING
    LDA ARG1
    CALL PRINT_U8_DEC
    PTR STR_RESULT_HEX
    CALL PRINT_STRING
    LDA ARG1
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
    CMP A, #$00
    JZ CMD_EMPTY
    CMP A, #$41
    JZ TRIE_ROOT_A
    CMP A, #$43
    JZ TRIE_ROOT_C
    CMP A, #$44
    JZ TRIE_ROOT_D
    CMP A, #$46
    JZ TRIE_ROOT_F
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
    CMP A, #$44
    JZ TRIE_ROOT_A_D
    CMP A, #$4E
    JZ TRIE_ROOT_A_N
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
    CMP A, #$55
    JZ TRIE_ROOT_D_U
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
TRIE_ROOT_D_U:
    LDA [PTR+]
    CMP A, #$4D
    JNZ CMD_UNKNOWN
    LDA [PTR+]
    CMP A, #$50
    JNZ CMD_UNKNOWN
    LDA [PTR+]
    CMP A, #$00
    JZ CMD_DUMP
    CMP A, #$20
    JZ CMD_DUMP
    JMP CMD_UNKNOWN
TRIE_ROOT_F:
    LDA [PTR+]
    CMP A, #$49
    JNZ CMD_UNKNOWN
    LDA [PTR+]
    CMP A, #$4C
    JNZ CMD_UNKNOWN
    LDA [PTR+]
    CMP A, #$4C
    JNZ CMD_UNKNOWN
    LDA [PTR+]
    CMP A, #$00
    JZ CMD_FILL
    CMP A, #$20
    JZ CMD_FILL
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
    CMP A, #$41
    JZ TRIE_ROOT_M_A
    CMP A, #$55
    JZ TRIE_ROOT_M_U
    JMP CMD_UNKNOWN
TRIE_ROOT_M_A:
    LDA [PTR+]
    CMP A, #$50
    JNZ CMD_UNKNOWN
    LDA [PTR+]
    CMP A, #$00
    JZ CMD_MAP
    CMP A, #$20
    JZ CMD_MAP
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
    CMP A, #$47
    JZ TRIE_ROOT_R_E_G
    CMP A, #$53
    JZ TRIE_ROOT_R_E_S
    JMP CMD_UNKNOWN
TRIE_ROOT_R_E_S:
    LDA [PTR+]
    CMP A, #$45
    JNZ CMD_UNKNOWN
    LDA [PTR+]
    CMP A, #$54
    JNZ CMD_UNKNOWN
    LDA [PTR+]
    CMP A, #$00
    JZ CMD_REBOOT
    CMP A, #$20
    JZ CMD_REBOOT
    JMP CMD_UNKNOWN
TRIE_ROOT_R_E_G:
    LDA [PTR+]
    CMP A, #$00
    JZ CMD_REG
    CMP A, #$20
    JZ CMD_REG
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
    CMP A, #$55
    JZ TRIE_ROOT_S_H_U
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
TRIE_ROOT_S_H_U:
    LDA [PTR+]
    CMP A, #$54
    JNZ CMD_UNKNOWN
    LDA [PTR+]
    CMP A, #$44
    JNZ CMD_UNKNOWN
    LDA [PTR+]
    CMP A, #$4F
    JNZ CMD_UNKNOWN
    LDA [PTR+]
    CMP A, #$57
    JNZ CMD_UNKNOWN
    LDA [PTR+]
    CMP A, #$4E
    JNZ CMD_UNKNOWN
    LDA [PTR+]
    CMP A, #$00
    JZ CMD_SHUTDOWN
    CMP A, #$20
    JZ CMD_SHUTDOWN
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
    PTR STR_UNKNOWN
    CALL PRINT_STRING
    RET
CMD_EMPTY:
    RET
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
    JZ CMD_SYNTAX
    CMP A, #$42
    JZ CMD_SYNTAX
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
    JZ CMD_SYNTAX
    CMP A, #$42
    JZ CMD_SYNTAX
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
    JZ CMD_SYNTAX
    CMP A, #$42
    JZ CMD_SYNTAX
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
    JZ CMD_SYNTAX
    CMP A, #$42
    JZ CMD_SYNTAX
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
    JZ CMD_SYNTAX
    CMP A, #$42
    JZ CMD_SYNTAX
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
    JZ CMD_SYNTAX
    CMP A, #$42
    JZ CMD_SYNTAX
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
    JZ CMD_SYNTAX
    CMP A, #$42
    JZ CMD_SYNTAX
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
    JZ CMD_SYNTAX
    CMP A, #$42
    JZ CMD_SYNTAX
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
    JZ CMD_SYNTAX
    CMP A, #$42
    JZ CMD_SYNTAX
    CMP A, #$50
    JZ CMD_SYNTAX
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
    JZ CMD_SYNTAX
    CMP A, #$42
    JZ CMD_SYNTAX
    CMP A, #$50
    JZ CMD_SYNTAX
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
    JZ CMD_SYNTAX
    CMP A, #$42
    JZ CMD_SYNTAX
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
    ; ARG1 vira o resto. TEMP2 seria corrompido ao imprimir Q= e R=.
CMD_DIV_LOOP:
    LDA ARG1
    LDB $0246
    CMP A, B
    JNC CMD_DIV_DONE
    SUB A, B
    STA ARG1
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
    LDA ARG1
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
    LDA [PTR+]
    CMP A, #$00
    JZ CMD_STATUS
    CMP A, #$43
    JNZ CMD_SYNTAX
    LDA [PTR+]
    CMP A, #$4C
    JNZ CMD_SYNTAX
    LDA [PTR+]
    CMP A, #$45
    JNZ CMD_SYNTAX
    LDA [PTR+]
    CMP A, #$41
    JNZ CMD_SYNTAX
    LDA [PTR+]
    CMP A, #$52
    JNZ CMD_SYNTAX
    CALL PARSE_REQUIRE_END
    LDA PARSE_OK
    CMP A, #$01
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
    CALL PARSE_REQUIRE_END
    LDA PARSE_OK
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

; REG mostra ou altera o contexto entregue a RUN, GO e CARD.
; Formas: REG | REG A [u8] | REG B [u8] | REG PTR [$hhhh] | REG SP [$hhhh]
CMD_REG:
    CALL SKIP_SPACES
    LDA [PTR+]
    CMP A, #$00
    JZ REG_PRINT_ALL
    CMP A, #$41
    JZ REG_SELECT_A
    CMP A, #$42
    JZ REG_SELECT_B
    CMP A, #$50
    JZ REG_SELECT_PTR_P
    CMP A, #$53
    JZ REG_SELECT_SP_S
    JMP CMD_SYNTAX

REG_SELECT_A:
    LDA [PTR]
    CMP A, #$00
    JZ REG_PRINT_A
    CMP A, #$20
    JNZ CMD_SYNTAX
    CALL PARSE_ONE_U8
    LDA PARSE_OK
    CMP A, #$01
    JNZ CMD_SYNTAX
    LDA ARG1
    STA MON_A
    JMP REG_PRINT_A

REG_SELECT_B:
    LDA [PTR]
    CMP A, #$00
    JZ REG_PRINT_B
    CMP A, #$20
    JNZ CMD_SYNTAX
    CALL PARSE_ONE_U8
    LDA PARSE_OK
    CMP A, #$01
    JNZ CMD_SYNTAX
    LDA ARG1
    STA MON_B
    JMP REG_PRINT_B

REG_SELECT_PTR_P:
    LDA [PTR+]
    CMP A, #$54
    JNZ CMD_SYNTAX
    LDA [PTR+]
    CMP A, #$52
    JNZ CMD_SYNTAX
    LDA [PTR]
    CMP A, #$00
    JZ REG_PRINT_PTR
    CMP A, #$20
    JNZ CMD_SYNTAX
    CALL PARSE_HEX16
    LDA PARSE_OK
    CMP A, #$01
    JNZ CMD_SYNTAX
    CALL PARSE_REQUIRE_END
    LDA PARSE_OK
    CMP A, #$01
    JNZ CMD_SYNTAX
    LDA ADDR_HI
    STA MON_PTR_HI
    LDA ADDR_LO
    STA MON_PTR_LO
    JMP REG_PRINT_PTR

REG_SELECT_SP_S:
    LDA [PTR+]
    CMP A, #$50
    JNZ CMD_SYNTAX
    LDA [PTR]
    CMP A, #$00
    JZ REG_PRINT_SP
    CMP A, #$20
    JNZ CMD_SYNTAX
    CALL PARSE_HEX16
    LDA PARSE_OK
    CMP A, #$01
    JNZ CMD_SYNTAX
    CALL PARSE_REQUIRE_END
    LDA PARSE_OK
    CMP A, #$01
    JNZ CMD_SYNTAX
    LDA ADDR_HI
    STA MON_SP_HI
    LDA ADDR_LO
    STA MON_SP_LO
    JMP REG_PRINT_SP

REG_PRINT_ALL:
    CALL REG_PRINT_A_INLINE
    CALL REG_PRINT_B_INLINE
    CALL REG_PRINT_PTR_INLINE
    CALL REG_PRINT_SP_INLINE
    CALL PRINT_NEWLINE
    RET
REG_PRINT_A:
    CALL REG_PRINT_A_INLINE
    CALL PRINT_NEWLINE
    RET
REG_PRINT_B:
    CALL REG_PRINT_B_INLINE
    CALL PRINT_NEWLINE
    RET
REG_PRINT_PTR:
    CALL REG_PRINT_PTR_INLINE
    CALL PRINT_NEWLINE
    RET
REG_PRINT_SP:
    CALL REG_PRINT_SP_INLINE
    CALL PRINT_NEWLINE
    RET

REG_PRINT_A_INLINE:
    PTR STR_REG_A
    CALL PRINT_STRING
    LDA MON_A
    CALL PRINT_HEX8
    RET
REG_PRINT_B_INLINE:
    PTR STR_REG_B
    CALL PRINT_STRING
    LDA MON_B
    CALL PRINT_HEX8
    RET
REG_PRINT_PTR_INLINE:
    PTR STR_REG_PTR
    CALL PRINT_STRING
    LDA MON_PTR_HI
    CALL PRINT_HEX8
    LDA MON_PTR_LO
    CALL PRINT_HEX8
    RET
REG_PRINT_SP_INLINE:
    PTR STR_REG_SP
    CALL PRINT_STRING
    LDA MON_SP_HI
    CALL PRINT_HEX8
    LDA MON_SP_LO
    CALL PRINT_HEX8
    RET


CMD_MAP:
    CALL PARSE_REQUIRE_END
    LDA PARSE_OK
    CMP A, #$01
    JNZ CMD_SYNTAX
    PTR STR_MAP
    CALL PRINT_STRING
    RET

; DUMP $hhhh [count] - hexadecimal, 16 bytes per linha.
CMD_DUMP:
    CALL PARSE_HEX16
    LDA PARSE_OK
    CMP A, #$01
    JNZ CMD_SYNTAX
    CALL SKIP_SPACES
    LDA [PTR]
    CMP A, #$00
    JZ CMD_DUMP_DEFAULT_COUNT
    CALL PARSE_U8
    LDB PARSE_OK
    CMP B, #$01
    JNZ CMD_SYNTAX
    STA DUMP_COUNT
    CALL PARSE_REQUIRE_END
    LDA PARSE_OK
    CMP A, #$01
    JNZ CMD_SYNTAX
    LDA DUMP_COUNT
    CMP A, #$00
    JZ CMD_RANGE_ERROR
    JMP CMD_DUMP_LINE
CMD_DUMP_DEFAULT_COUNT:
    STI DUMP_COUNT, #$10

CMD_DUMP_LINE:
    LDA DUMP_COUNT
    CMP A, #$00
    JZ CMD_DUMP_DONE
    LDA #$24
    CALL PUT_CHAR
    LDA ADDR_HI
    CALL PRINT_HEX8
    LDA ADDR_LO
    CALL PRINT_HEX8
    PTR STR_DUMP_SEP
    CALL PRINT_STRING
    STI DUMP_COL, #$10

CMD_DUMP_BYTE:
    CALL DYN_READ
    CALL PRINT_HEX8
    LDA #$20
    CALL PUT_CHAR
    CALL ADDR_INC
    LDA DUMP_COUNT
    DEC A
    STA DUMP_COUNT
    LDB DUMP_COL
    DEC B
    STB DUMP_COL
    CMP A, #$00
    JZ CMD_DUMP_LINE_END
    CMP B, #$00
    JNZ CMD_DUMP_BYTE
CMD_DUMP_LINE_END:
    CALL PRINT_NEWLINE
    JMP CMD_DUMP_LINE
CMD_DUMP_DONE:
    RET

; FILL $hhhh value count - grava até 255 bytes consecutivos.
CMD_FILL:
    CALL PARSE_HEX16
    LDA PARSE_OK
    CMP A, #$01
    JNZ CMD_SYNTAX
    CALL PARSE_U8
    LDB PARSE_OK
    CMP B, #$01
    JNZ CMD_SYNTAX
    STA ARG1
    CALL PARSE_U8
    LDB PARSE_OK
    CMP B, #$01
    JNZ CMD_SYNTAX
    STA FILL_COUNT
    STA ARG2
    CALL PARSE_REQUIRE_END
    LDA PARSE_OK
    CMP A, #$01
    JNZ CMD_SYNTAX
    LDA FILL_COUNT
    CMP A, #$00
    JZ CMD_RANGE_ERROR
CMD_FILL_LOOP:
    LDA ARG1
    CALL DYN_WRITE
    CALL ADDR_INC
    LDA FILL_COUNT
    DEC A
    STA FILL_COUNT
    JNZ CMD_FILL_LOOP
    PTR STR_FILL_OK
    CALL PRINT_STRING
    LDA ARG2
    CALL PRINT_U8_DEC
    PTR STR_FILL_END
    CALL PRINT_STRING
    RET

ADDR_INC:
    LDA ADDR_LO
    INC A
    STA ADDR_LO
    CMP A, #$00
    JNZ ADDR_INC_DONE
    LDA ADDR_HI
    INC A
    STA ADDR_HI
ADDR_INC_DONE:
    RET

CMD_READ:
    CALL PARSE_HEX16
    LDA $0241
    CMP A, #$01
    JNZ CMD_SYNTAX
    CALL PARSE_REQUIRE_END
    LDA PARSE_OK
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
    CALL PARSE_REQUIRE_END
    LDA PARSE_OK
    CMP A, #$01
    JNZ CMD_SYNTAX
    LDA ARG1
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
    CALL SKIP_SPACES
    LDA [PTR]
    CMP A, #$00
    JNZ CMD_SYNTAX
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
    CALL PARSE_REQUIRE_END
    LDA PARSE_OK
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
    STI RUN_KIND, #$00
    STI $012A, #$59              ; CALL destino e retorna ao monitor
    JMP DYN_LAUNCH
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
    CALL PARSE_REQUIRE_END
    LDA PARSE_OK
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
    STI $012A, #$50              ; JMP destino, sem retorno
    JMP DYN_LAUNCH

RUN_CARD_IMPL:
    LDA $F300
    TEST A, #$10
    JNZ RUN_CARD_NONE
    PTR STR_RUN_CARD
    CALL PRINT_STRING

    ; O cartucho pode ser interativo. Sincroniza a tela e libera a saída
    ; imediata enquanto o código externo estiver executando.
    STI ADDR_HI, #$A0
    STI ADDR_LO, #$00
    STI RUN_KIND, #$01
    CALL VIDEO_BATCH_FLUSH
    STI $012A, #$59
    JMP DYN_LAUNCH
RUN_CARD_NONE:
    PTR STR_NO_CARD
    CALL PRINT_STRING
    RET

; ============================================================
; Escrita/leitura dinamica e transferencia com contexto de registradores.
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

DYN_LAUNCH:
    LDA MON_A
    STA $0121
    LDA MON_B
    STA $0123
    LDA MON_PTR_LO
    STA $0125
    LDA MON_PTR_HI
    STA $0126
    LDA MON_SP_LO
    STA $0128
    LDA MON_SP_HI
    STA $0129
    LDA ADDR_LO
    STA $012B
    LDA ADDR_HI
    STA $012C
    JMP $0120

; O programa chamado retornou por RET. A e B passam a ser o novo contexto.
; PTR e SP permanecem com os valores configurados porque a ISA nao permite
; ler esses registradores de volta para a BIOS.
RUN_CONTEXT_RETURN:
    STA MON_A
    STB MON_B
    STI VIDEO_BATCH, #$01
    LDA RUN_KIND
    CMP A, #$01
    JZ RUN_CONTEXT_CARD_RETURN
    PTR STR_RUN_RETURN
    CALL PRINT_STRING
    LDA MON_A
    CALL PRINT_HEX8
    PTR STR_RUN_B
    CALL PRINT_STRING
    LDA MON_B
    CALL PRINT_HEX8
    CALL PRINT_NEWLINE
    JMP SHELL_COMMAND_DONE
RUN_CONTEXT_CARD_RETURN:
    PTR STR_CARD_RETURN
    CALL PRINT_STRING
    JMP SHELL_COMMAND_DONE

CMD_SHUTDOWN:
    ; Não aceita argumentos. Depois de HLT não existe caminho de retorno:
    ; somente um novo ciclo de alimentação executará RESET novamente.
    CALL PARSE_REQUIRE_END
    LDA PARSE_OK
    CMP A, #$01
    JNZ CMD_SYNTAX

    CALL SOUND_SHUTDOWN
    STI SOUND_CFG, #$00

    ; Desliga as saídas de indicação acessíveis por software.
    STI DISPLAY_LOW, #$00
    STI DISPLAY_HIGH, #$00
    STI PERIPH_CFG, #$00

    ; Limpa toda a superfície de vídeo e mantém o cursor invisível.
    CALL VIDEO_WAIT
    STI VIDEO_CMD, #$00
    CALL VIDEO_WAIT
    STI VIDEO_X, #$00
    STI VIDEO_Y, #$00
    STI VIDEO_CMD, #$04

    STI SYSTEM_STATUS, #$00
    CLR A
    CLR B
    HLT

CMD_REBOOT:
    PTR STR_REBOOT
    CALL PRINT_STRING
    ; REBOOT não retorna ao shell, então conclui a atualização pendente.
    CALL VIDEO_BATCH_FLUSH
    STI $F500, #$70    ; reativa overlay mantendo configuração de clock
    JMP RESET
STR_BANNER:
    #d8 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20
    #d8 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x57, 0x41, 0x4C, 0x4C, 0x2D
    #d8 0x38, 0x20, 0x42, 0x49, 0x4F, 0x53, 0x20, 0x4D, 0x6F, 0x6E, 0x69, 0x74, 0x6F, 0x72, 0x20, 0x76
    #d8 0x35, 0x2E, 0x30, 0x0D, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20
    #d8 0x20, 0x20, 0x20, 0x20, 0x20, 0x44, 0x69, 0x73, 0x63, 0x72, 0x65, 0x74, 0x65, 0x20, 0x38, 0x2D
    #d8 0x62, 0x69, 0x74, 0x20, 0x63, 0x6F, 0x6D, 0x70, 0x75, 0x74, 0x65, 0x72, 0x20, 0x7C, 0x20, 0x38
    #d8 0x30, 0x78, 0x33, 0x30, 0x20, 0x74, 0x65, 0x78, 0x74, 0x20, 0x63, 0x6F, 0x6E, 0x73, 0x6F, 0x6C
    #d8 0x65, 0x0D, 0x54, 0x79, 0x70, 0x65, 0x20, 0x48, 0x45, 0x4C, 0x50, 0x20, 0x66, 0x6F, 0x72, 0x20
    #d8 0x63, 0x6F, 0x6D, 0x6D, 0x61, 0x6E, 0x64, 0x73, 0x2E, 0x20, 0x54, 0x41, 0x42, 0x3D, 0x72, 0x65
    #d8 0x63, 0x61, 0x6C, 0x6C, 0x2C, 0x20, 0x55, 0x50, 0x2F, 0x44, 0x4F, 0x57, 0x4E, 0x3D, 0x73, 0x63
    #d8 0x72, 0x6F, 0x6C, 0x6C, 0x2E, 0x0D, 0x00
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
    #d8 0x57, 0x41, 0x4C, 0x4C, 0x2D, 0x38, 0x20, 0x4D, 0x4F, 0x4E, 0x49, 0x54, 0x4F, 0x52, 0x20, 0x43
    #d8 0x4F, 0x4D, 0x4D, 0x41, 0x4E, 0x44, 0x53, 0x0D, 0x0A, 0x20, 0x4D, 0x45, 0x4D, 0x4F, 0x52, 0x59
    #d8 0x0D, 0x0A, 0x20, 0x20, 0x52, 0x45, 0x41, 0x44, 0x20, 0x24, 0x68, 0x68, 0x68, 0x68, 0x20, 0x20
    #d8 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x72, 0x65, 0x61, 0x64, 0x20
    #d8 0x6F, 0x6E, 0x65, 0x20, 0x62, 0x79, 0x74, 0x65, 0x0D, 0x0A, 0x20, 0x20, 0x57, 0x52, 0x49, 0x54
    #d8 0x45, 0x20, 0x24, 0x68, 0x68, 0x68, 0x68, 0x20, 0x76, 0x61, 0x6C, 0x75, 0x65, 0x20, 0x20, 0x20
    #d8 0x20, 0x20, 0x20, 0x77, 0x72, 0x69, 0x74, 0x65, 0x20, 0x6F, 0x6E, 0x65, 0x20, 0x62, 0x79, 0x74
    #d8 0x65, 0x0D, 0x0A, 0x20, 0x20, 0x44, 0x55, 0x4D, 0x50, 0x20, 0x24, 0x68, 0x68, 0x68, 0x68, 0x20
    #d8 0x5B, 0x63, 0x6F, 0x75, 0x6E, 0x74, 0x5D, 0x20, 0x20, 0x20, 0x20, 0x20, 0x68, 0x65, 0x78, 0x20
    #d8 0x64, 0x75, 0x6D, 0x70, 0x20, 0x28, 0x64, 0x65, 0x66, 0x61, 0x75, 0x6C, 0x74, 0x20, 0x31, 0x30
    #d8 0x68, 0x29, 0x0D, 0x0A, 0x20, 0x20, 0x46, 0x49, 0x4C, 0x4C, 0x20, 0x24, 0x68, 0x68, 0x68, 0x68
    #d8 0x20, 0x76, 0x61, 0x6C, 0x75, 0x65, 0x20, 0x63, 0x6F, 0x75, 0x6E, 0x74, 0x20, 0x66, 0x69, 0x6C
    #d8 0x6C, 0x20, 0x31, 0x2E, 0x2E, 0x32, 0x35, 0x35, 0x20, 0x62, 0x79, 0x74, 0x65, 0x73, 0x0D, 0x0A
    #d8 0x20, 0x20, 0x4D, 0x41, 0x50, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20
    #d8 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x6D, 0x65, 0x6D, 0x6F, 0x72, 0x79, 0x20
    #d8 0x6D, 0x61, 0x70, 0x0D, 0x0A, 0x20, 0x45, 0x58, 0x45, 0x43, 0x55, 0x54, 0x49, 0x4F, 0x4E, 0x0D
    #d8 0x0A, 0x20, 0x20, 0x52, 0x45, 0x47, 0x20, 0x5B, 0x41, 0x7C, 0x42, 0x7C, 0x50, 0x54, 0x52, 0x7C
    #d8 0x53, 0x50, 0x5D, 0x20, 0x5B, 0x76, 0x61, 0x6C, 0x75, 0x65, 0x5D, 0x0D, 0x0A, 0x20, 0x20, 0x52
    #d8 0x55, 0x4E, 0x20, 0x24, 0x68, 0x68, 0x68, 0x68, 0x20, 0x7C, 0x20, 0x43, 0x41, 0x52, 0x44, 0x20
    #d8 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x43, 0x41, 0x4C, 0x4C, 0x20, 0x61, 0x6E, 0x64, 0x20, 0x72
    #d8 0x65, 0x74, 0x75, 0x72, 0x6E, 0x0D, 0x0A, 0x20, 0x20, 0x47, 0x4F, 0x20, 0x24, 0x68, 0x68, 0x68
    #d8 0x68, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20
    #d8 0x4A, 0x4D, 0x50, 0x20, 0x77, 0x69, 0x74, 0x68, 0x6F, 0x75, 0x74, 0x20, 0x72, 0x65, 0x74, 0x75
    #d8 0x72, 0x6E, 0x0D, 0x0A, 0x20, 0x48, 0x41, 0x52, 0x44, 0x57, 0x41, 0x52, 0x45, 0x0D, 0x0A, 0x20
    #d8 0x20, 0x53, 0x54, 0x41, 0x54, 0x55, 0x53, 0x20, 0x7C, 0x20, 0x54, 0x49, 0x4D, 0x45, 0x52, 0x20
    #d8 0x5B, 0x43, 0x4C, 0x45, 0x41, 0x52, 0x5D, 0x0D, 0x0A, 0x20, 0x20, 0x53, 0x4F, 0x55, 0x4E, 0x44
    #d8 0x20, 0x76, 0x61, 0x6C, 0x75, 0x65, 0x20, 0x7C, 0x20, 0x44, 0x49, 0x53, 0x50, 0x20, 0x24, 0x68
    #d8 0x68, 0x68, 0x68, 0x0D, 0x0A, 0x20, 0x53, 0x59, 0x53, 0x54, 0x45, 0x4D, 0x0D, 0x0A, 0x20, 0x20
    #d8 0x49, 0x4E, 0x46, 0x4F, 0x20, 0x7C, 0x20, 0x56, 0x45, 0x52, 0x20, 0x7C, 0x20, 0x43, 0x4C, 0x53
    #d8 0x20, 0x7C, 0x20, 0x52, 0x45, 0x42, 0x4F, 0x4F, 0x54, 0x20, 0x7C, 0x20, 0x52, 0x45, 0x53, 0x45
    #d8 0x54, 0x0D, 0x0A, 0x20, 0x4D, 0x41, 0x54, 0x48, 0x0D, 0x0A, 0x20, 0x20, 0x41, 0x44, 0x44, 0x2F
    #d8 0x53, 0x55, 0x42, 0x2F, 0x4D, 0x55, 0x4C, 0x2F, 0x44, 0x49, 0x56, 0x2F, 0x41, 0x4E, 0x44, 0x2F
    #d8 0x4F, 0x52, 0x2F, 0x58, 0x4F, 0x52, 0x2F, 0x43, 0x4D, 0x50, 0x20, 0x61, 0x20, 0x62, 0x0D, 0x0A
    #d8 0x20, 0x20, 0x4E, 0x4F, 0x54, 0x2F, 0x53, 0x48, 0x4C, 0x2F, 0x53, 0x48, 0x52, 0x2F, 0x49, 0x4E
    #d8 0x43, 0x2F, 0x44, 0x45, 0x43, 0x20, 0x61, 0x0D, 0x0A, 0x20, 0x4E, 0x55, 0x4D, 0x42, 0x45, 0x52
    #d8 0x53, 0x3A, 0x20, 0x35, 0x30, 0x2C, 0x20, 0x24, 0x35, 0x30, 0x2C, 0x20, 0x30, 0x78, 0x35, 0x30
    #d8 0x3D, 0x68, 0x65, 0x78, 0x20, 0x7C, 0x20, 0x23, 0x35, 0x30, 0x3D, 0x64, 0x65, 0x63, 0x69, 0x6D
    #d8 0x61, 0x6C, 0x0D, 0x0A, 0x20, 0x54, 0x41, 0x42, 0x20, 0x72, 0x65, 0x63, 0x61, 0x6C, 0x6C, 0x73
    #d8 0x20, 0x6C, 0x61, 0x73, 0x74, 0x20, 0x63, 0x6F, 0x6D, 0x6D, 0x61, 0x6E, 0x64, 0x3B, 0x20, 0x55
    #d8 0x50, 0x2F, 0x44, 0x4F, 0x57, 0x4E, 0x20, 0x73, 0x63, 0x72, 0x6F, 0x6C, 0x6C, 0x20, 0x6F, 0x75
    #d8 0x74, 0x70, 0x75, 0x74, 0x2E, 0x0D, 0x0A
    #d8 0x20, 0x42, 0x30, 0x30, 0x31, 0x31, 0x30, 0x30, 0x30, 0x31, 0x3D, 0x62, 0x69, 0x6E, 0x61, 0x72
    #d8 0x79, 0x20, 0x7C, 0x20, 0x53, 0x48, 0x55, 0x54, 0x44, 0x4F, 0x57, 0x4E, 0x3D, 0x70, 0x6F, 0x77
    #d8 0x65, 0x72, 0x20, 0x68, 0x61, 0x6C, 0x74, 0x0D, 0x0A, 0x00
STR_INFO:
    #d8 0x57, 0x41, 0x4C, 0x4C, 0x2D, 0x38, 0x3A, 0x20, 0x44, 0x42, 0x55, 0x53, 0x20, 0x38, 0x2D, 0x62
    #d8 0x69, 0x74, 0x2C, 0x20, 0x41, 0x44, 0x44, 0x52, 0x20, 0x31, 0x36, 0x2D, 0x62, 0x69, 0x74, 0x2C
    #d8 0x20, 0x66, 0x6C, 0x61, 0x67, 0x73, 0x20, 0x5A, 0x2F, 0x43, 0x2F, 0x4E, 0x2F, 0x56, 0x2E, 0x0D
    #d8 0x0A, 0x52, 0x41, 0x4D, 0x20, 0x24, 0x30, 0x30, 0x30, 0x30, 0x2D, 0x24, 0x37, 0x46, 0x46, 0x46
    #d8 0x20, 0x7C, 0x20, 0x42, 0x49, 0x4F, 0x53, 0x20, 0x24, 0x38, 0x30, 0x30, 0x30, 0x2D, 0x24, 0x39
    #d8 0x46, 0x46, 0x46, 0x20, 0x7C, 0x20, 0x43, 0x41, 0x52, 0x54, 0x20, 0x24, 0x41, 0x30, 0x30, 0x30
    #d8 0x2D, 0x24, 0x45, 0x46, 0x46, 0x46, 0x2E, 0x0D, 0x0A, 0x56, 0x47, 0x41, 0x20, 0x36, 0x34, 0x30
    #d8 0x78, 0x34, 0x38, 0x30, 0x20, 0x34, 0x3A, 0x33, 0x3A, 0x20, 0x74, 0x65, 0x78, 0x74, 0x20, 0x38
    #d8 0x30, 0x78, 0x33, 0x30, 0x3B, 0x20, 0x6D, 0x6F, 0x6E, 0x6F, 0x20, 0x33, 0x32, 0x30, 0x78, 0x32
    #d8 0x34, 0x30, 0x3B, 0x20, 0x6D, 0x6F, 0x6E, 0x6F, 0x20, 0x31, 0x36, 0x30, 0x78, 0x31, 0x32, 0x30
    #d8 0x2E, 0x0D, 0x0A, 0x56, 0x49, 0x44, 0x45, 0x4F, 0x3A, 0x20, 0x46, 0x32, 0x30, 0x30, 0x20, 0x44
    #d8 0x41, 0x54, 0x41, 0x20, 0x7C, 0x20, 0x46, 0x32, 0x30, 0x31, 0x20, 0x43, 0x4D, 0x44, 0x2F, 0x4D
    #d8 0x4F, 0x44, 0x45, 0x20, 0x7C, 0x20, 0x46, 0x32, 0x30, 0x32, 0x20, 0x58, 0x20, 0x7C, 0x20, 0x46
    #d8 0x32, 0x30, 0x33, 0x20, 0x59, 0x20, 0x7C, 0x20, 0x46, 0x32, 0x30, 0x34, 0x20, 0x53, 0x54, 0x41
    #d8 0x54, 0x55, 0x53, 0x2E, 0x0D, 0x0A, 0x00
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
STR_REG_A:
    #d8 0x41, 0x3D, 0x24, 0x00
STR_REG_B:
    #d8 0x20, 0x42, 0x3D, 0x24, 0x00
STR_REG_PTR:
    #d8 0x20, 0x50, 0x54, 0x52, 0x3D, 0x24, 0x00
STR_REG_SP:
    #d8 0x20, 0x53, 0x50, 0x3D, 0x24, 0x00
STR_UNKNOWN:
    #d8 0x63, 0x6F, 0x6D, 0x6D, 0x61, 0x6E, 0x64, 0x20, 0x6E, 0x6F, 0x74, 0x20
    #d8 0x66, 0x6F, 0x75, 0x6E, 0x64, 0x2E, 0x20, 0x54, 0x79, 0x70, 0x65, 0x20, 0x48, 0x45, 0x4C, 0x50
    #d8 0x2E, 0x0D, 0x0A, 0x00
STR_SOUND_SET:
    #d8 0x53, 0x4F, 0x55, 0x4E, 0x44, 0x20, 0x24, 0x46, 0x34, 0x30, 0x30, 0x3D, 0x24, 0x00
STR_STATUS_HEX:
    #d8 0x53, 0x54, 0x41, 0x54, 0x55, 0x53, 0x20, 0x24, 0x46, 0x33, 0x30, 0x30, 0x3D, 0x24, 0x00
STR_SYNTAX:
    #d8 0x69, 0x6E, 0x76, 0x61, 0x6C, 0x69, 0x64, 0x20, 0x73, 0x79, 0x6E, 0x74
    #d8 0x61, 0x78, 0x2E, 0x20, 0x54, 0x79, 0x70, 0x65, 0x20, 0x48, 0x45, 0x4C, 0x50, 0x2E, 0x0D, 0x0A
    #d8 0x00
STR_TIMER_CLEARED:
    #d8 0x54, 0x69, 0x6D, 0x65, 0x72, 0x73, 0x20, 0x6C, 0x69, 0x6D, 0x70, 0x6F, 0x73, 0x2E, 0x0D, 0x0A
    #d8 0x00
STR_VERSION:
    #d8 0x57, 0x41, 0x4C, 0x4C, 0x2D, 0x38, 0x20, 0x42, 0x49, 0x4F, 0x53, 0x20, 0x4D, 0x6F, 0x6E, 0x69
    #d8 0x74, 0x6F, 0x72, 0x20, 0x76, 0x35, 0x2E, 0x30, 0x20, 0x2D, 0x20, 0x62, 0x6F, 0x6F, 0x74, 0x2F
    #d8 0x74, 0x65, 0x72, 0x6D, 0x69, 0x6E, 0x61, 0x6C, 0x20, 0x65, 0x64, 0x69, 0x74, 0x69, 0x6F, 0x6E
    #d8 0x0D, 0x0A, 0x00
STR_VIDEO_OFF:
    #d8 0x56, 0x49, 0x44, 0x45, 0x4F, 0x3D, 0x4F, 0x46, 0x46, 0x20, 0x00
STR_VIDEO_ON:
    #d8 0x56, 0x49, 0x44, 0x45, 0x4F, 0x3D, 0x4F, 0x4E, 0x20, 0x00
STR_WRITE_MID:
    #d8 0x5D, 0x20, 0x3C, 0x3D, 0x20, 0x24, 0x00
STR_WRITE_OPEN:
    #d8 0x4F, 0x4B, 0x20, 0x5B, 0x24, 0x00

STR_BOOT_PREFIX:
    #d8 0x42, 0x4F, 0x4F, 0x54, 0x3A, 0x20, 0x00
STR_BOOT_RAM_OK:
    #d8 0x52, 0x41, 0x4D, 0x3D, 0x4F, 0x4B, 0x20, 0x00
STR_BOOT_RAM_FAIL:
    #d8 0x52, 0x41, 0x4D, 0x3D, 0x46, 0x41, 0x49, 0x4C, 0x20, 0x00
STR_DUMP_SEP:
    #d8 0x3A, 0x20, 0x00
STR_FILL_OK:
    #d8 0x4F, 0x4B, 0x3A, 0x20, 0x00
STR_FILL_END:
    #d8 0x20, 0x62, 0x79, 0x74, 0x65, 0x73, 0x20, 0x66, 0x69, 0x6C, 0x6C, 0x65, 0x64, 0x2E, 0x0D, 0x0A
    #d8 0x00
STR_MAP:
    #d8 0x57, 0x41, 0x4C, 0x4C, 0x2D, 0x38, 0x20, 0x4D, 0x45, 0x4D, 0x4F, 0x52, 0x59, 0x20, 0x4D, 0x41
    #d8 0x50, 0x0D, 0x0A, 0x20, 0x24, 0x30, 0x30, 0x30, 0x30, 0x2D, 0x24, 0x37, 0x46, 0x46, 0x46, 0x20
    #d8 0x20, 0x52, 0x41, 0x4D, 0x20, 0x33, 0x32, 0x20, 0x4B, 0x69, 0x42, 0x0D, 0x0A, 0x20, 0x24, 0x38
    #d8 0x30, 0x30, 0x30, 0x2D, 0x24, 0x39, 0x46, 0x46, 0x46, 0x20, 0x20, 0x42, 0x49, 0x4F, 0x53, 0x20
    #d8 0x38, 0x20, 0x4B, 0x69, 0x42, 0x0D, 0x0A, 0x20, 0x24, 0x41, 0x30, 0x30, 0x30, 0x2D, 0x24, 0x45
    #d8 0x46, 0x46, 0x46, 0x20, 0x20, 0x43, 0x41, 0x52, 0x54, 0x20, 0x32, 0x30, 0x20, 0x4B, 0x69, 0x42
    #d8 0x0D, 0x0A, 0x20, 0x24, 0x46, 0x30, 0x30, 0x30, 0x2D, 0x24, 0x46, 0x46, 0x46, 0x46, 0x20, 0x20
    #d8 0x49, 0x2F, 0x4F, 0x20, 0x34, 0x20, 0x4B, 0x69, 0x42, 0x0D, 0x0A, 0x20, 0x20, 0x46, 0x30, 0x30
    #d8 0x30, 0x20, 0x4B, 0x45, 0x59, 0x20, 0x7C, 0x20, 0x46, 0x31, 0x30, 0x30, 0x20, 0x44, 0x49, 0x53
    #d8 0x50, 0x4C, 0x41, 0x59, 0x20, 0x7C, 0x20, 0x46, 0x32, 0x30, 0x30, 0x20, 0x56, 0x49, 0x44, 0x45
    #d8 0x4F, 0x20, 0x7C, 0x20, 0x46, 0x33, 0x30, 0x30, 0x20, 0x53, 0x54, 0x41, 0x54, 0x55, 0x53, 0x0D
    #d8 0x0A, 0x20, 0x20, 0x46, 0x34, 0x30, 0x30, 0x20, 0x53, 0x4F, 0x55, 0x4E, 0x44, 0x20, 0x7C, 0x20
    #d8 0x46, 0x35, 0x30, 0x30, 0x20, 0x53, 0x59, 0x53, 0x54, 0x45, 0x4D, 0x20, 0x7C, 0x20, 0x46, 0x36
    #d8 0x30, 0x30, 0x20, 0x43, 0x41, 0x52, 0x54, 0x20, 0x49, 0x2F, 0x4F, 0x20, 0x7C, 0x20, 0x46, 0x37
    #d8 0x30, 0x30, 0x20, 0x45, 0x58, 0x50, 0x0D, 0x0A, 0x00

#addr 0x9FFD
BIOS_END_VECTOR:
    JMP BIOS_MAIN
