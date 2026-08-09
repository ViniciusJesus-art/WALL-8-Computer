#include "../wall8.cpu"

; O arquivo do cartucho e carregado pelo sistema em $A000.  A origem
; logica precisa coincidir com esse endereco para que CALL, JMP e PTR
; apontem para dentro do proprio cartucho.  #outp 0 mantem o .bin
; compacto: o primeiro byte do arquivo corresponde a $A000.
#bankdef cart {
    #addr 0xA000
    #size 0x5000
    #outp 0x0000
}

#bank cart
#addr 0xA000

; ============================================================
; WALL-8 - Cartucho de teste grafico
; Desenha um circulo centralizado em (160,120)
; Modo: 320x240 monocromatico
; Raio aproximado: 48 pixels
;
; Cada entrada da tabela possui:
;   VIDEO_X (coluna de byte), VIDEO_Y, mascara de 8 pixels
;
; O programa pressupoe que a BIOS chama o cartucho com CALL $A000.
; Ao terminar, permanece exibindo o circulo. Para retornar a BIOS,
; substitua o loop FINAL por RET.
; ============================================================

VIDEO_DATA   = $F200
VIDEO_CMD    = $F201
VIDEO_X      = $F202
VIDEO_Y      = $F203
VIDEO_STATUS = $F204

; RAM temporaria
CIRCLE_X     = $0200
CIRCLE_Y     = $0201
CIRCLE_DATA  = $0202

INICIO:

    ; Nao reinicializa SP: a BIOS entrou aqui com CALL $A000, e as
    ; subrotinas abaixo usam a mesma pilha ja preparada pelo sistema.

    ; Espera a interface ficar livre.
    CALL VIDEO_WAIT

    ; Seleciona grafico monocromatico 320x240.
    STI VIDEO_CMD, #$12
    CALL VIDEO_WAIT

    ; Limpa os 9.600 bytes usados pelo modo grafico.
    STI VIDEO_CMD, #$00
    CALL VIDEO_WAIT

    ; Percorre a tabela do circulo.
    PTR CIRCLE_TABLE

CIRCLE_LOOP:

    ; Primeiro byte: coluna de byte X.
    LDA [PTR+]
    CMP A, #$FF
    JZ CIRCLE_DONE
    STA CIRCLE_X

    ; Segundo byte: linha Y.
    LDA [PTR+]
    STA CIRCLE_Y

    ; Terceiro byte: mascara dos oito pixels.
    LDA [PTR+]
    STA CIRCLE_DATA

    ; Antes de alterar X, Y ou DATA, espera BUSY = 0.
    CALL VIDEO_WAIT

    LDA CIRCLE_X
    STA VIDEO_X

    LDA CIRCLE_Y
    STA VIDEO_Y

    ; A tela foi limpa antes, portanto nao e necessario
    ; fazer leitura/modificacao/escrita do byte.
    LDA CIRCLE_DATA
    STA VIDEO_DATA

    JMP CIRCLE_LOOP

CIRCLE_DONE:

    ; Garante que a ultima escrita terminou.
    CALL VIDEO_WAIT

FINAL:
    JMP FINAL

; Para retornar ao monitor da BIOS, use isto no lugar do loop:
;    RET

; ------------------------------------------------------------
; Espera oficial da interface de video.
; VIDEO_STATUS bit 0 = BUSY.
; ------------------------------------------------------------
VIDEO_WAIT:
    LDA VIDEO_STATUS
    TEST A, #$01
    JNZ VIDEO_WAIT
    RET

; ------------------------------------------------------------
; Tabela: X_byte, Y, mascara
; $FF encerra a tabela.
; Bit 7 = pixel mais a esquerda do byte.
; ------------------------------------------------------------
CIRCLE_TABLE:
    #d8 $14, $48, $80    ; Y= 72, pixels X=160..167
    #d8 $12, $49, $02    ; Y= 73, pixels X=144..151
    #d8 $15, $49, $20    ; Y= 73, pixels X=168..175
    #d8 $12, $4A, $20    ; Y= 74, pixels X=144..151
    #d8 $15, $4A, $02    ; Y= 74, pixels X=168..175
    #d8 $11, $4B, $01    ; Y= 75, pixels X=136..143
    #d8 $16, $4B, $40    ; Y= 75, pixels X=176..183
    #d8 $11, $4C, $04    ; Y= 76, pixels X=136..143
    #d8 $16, $4C, $10    ; Y= 76, pixels X=176..183
    #d8 $11, $4D, $10    ; Y= 77, pixels X=136..143
    #d8 $16, $4D, $04    ; Y= 77, pixels X=176..183
    #d8 $11, $4E, $40    ; Y= 78, pixels X=136..143
    #d8 $16, $4E, $01    ; Y= 78, pixels X=176..183
    #d8 $10, $4F, $01    ; Y= 79, pixels X=128..135
    #d8 $17, $4F, $40    ; Y= 79, pixels X=184..191
    #d8 $10, $50, $04    ; Y= 80, pixels X=128..135
    #d8 $17, $50, $10    ; Y= 80, pixels X=184..191
    #d8 $10, $51, $08    ; Y= 81, pixels X=128..135
    #d8 $17, $51, $08    ; Y= 81, pixels X=184..191
    #d8 $10, $52, $10    ; Y= 82, pixels X=128..135
    #d8 $17, $52, $04    ; Y= 82, pixels X=184..191
    #d8 $10, $53, $40    ; Y= 83, pixels X=128..135
    #d8 $17, $53, $01    ; Y= 83, pixels X=184..191
    #d8 $10, $54, $80    ; Y= 84, pixels X=128..135
    #d8 $18, $54, $80    ; Y= 84, pixels X=192..199
    #d8 $0F, $55, $01    ; Y= 85, pixels X=120..127
    #d8 $18, $55, $40    ; Y= 85, pixels X=192..199
    #d8 $0F, $56, $02    ; Y= 86, pixels X=120..127
    #d8 $18, $56, $20    ; Y= 86, pixels X=192..199
    #d8 $0F, $57, $04    ; Y= 87, pixels X=120..127
    #d8 $18, $57, $10    ; Y= 87, pixels X=192..199
    #d8 $0F, $58, $08    ; Y= 88, pixels X=120..127
    #d8 $18, $58, $08    ; Y= 88, pixels X=192..199
    #d8 $0F, $59, $10    ; Y= 89, pixels X=120..127
    #d8 $18, $59, $04    ; Y= 89, pixels X=192..199
    #d8 $0F, $5A, $10    ; Y= 90, pixels X=120..127
    #d8 $18, $5A, $04    ; Y= 90, pixels X=192..199
    #d8 $0F, $5B, $20    ; Y= 91, pixels X=120..127
    #d8 $18, $5B, $02    ; Y= 91, pixels X=192..199
    #d8 $0F, $5C, $40    ; Y= 92, pixels X=120..127
    #d8 $18, $5C, $01    ; Y= 92, pixels X=192..199
    #d8 $0F, $5D, $80    ; Y= 93, pixels X=120..127
    #d8 $19, $5D, $80    ; Y= 93, pixels X=200..207
    #d8 $0F, $5E, $80    ; Y= 94, pixels X=120..127
    #d8 $19, $5E, $80    ; Y= 94, pixels X=200..207
    #d8 $0E, $5F, $01    ; Y= 95, pixels X=112..119
    #d8 $19, $5F, $40    ; Y= 95, pixels X=200..207
    #d8 $0E, $60, $02    ; Y= 96, pixels X=112..119
    #d8 $19, $60, $20    ; Y= 96, pixels X=200..207
    #d8 $0E, $61, $02    ; Y= 97, pixels X=112..119
    #d8 $19, $61, $20    ; Y= 97, pixels X=200..207
    #d8 $0E, $62, $04    ; Y= 98, pixels X=112..119
    #d8 $19, $62, $10    ; Y= 98, pixels X=200..207
    #d8 $0E, $63, $04    ; Y= 99, pixels X=112..119
    #d8 $19, $63, $10    ; Y= 99, pixels X=200..207
    #d8 $0E, $64, $08    ; Y=100, pixels X=112..119
    #d8 $19, $64, $08    ; Y=100, pixels X=200..207
    #d8 $0E, $65, $08    ; Y=101, pixels X=112..119
    #d8 $19, $65, $08    ; Y=101, pixels X=200..207
    #d8 $0E, $66, $08    ; Y=102, pixels X=112..119
    #d8 $19, $66, $08    ; Y=102, pixels X=200..207
    #d8 $0E, $67, $10    ; Y=103, pixels X=112..119
    #d8 $19, $67, $04    ; Y=103, pixels X=200..207
    #d8 $0E, $68, $10    ; Y=104, pixels X=112..119
    #d8 $19, $68, $04    ; Y=104, pixels X=200..207
    #d8 $0E, $69, $20    ; Y=105, pixels X=112..119
    #d8 $19, $69, $02    ; Y=105, pixels X=200..207
    #d8 $0E, $6A, $20    ; Y=106, pixels X=112..119
    #d8 $19, $6A, $02    ; Y=106, pixels X=200..207
    #d8 $0E, $6B, $20    ; Y=107, pixels X=112..119
    #d8 $19, $6B, $02    ; Y=107, pixels X=200..207
    #d8 $0E, $6C, $20    ; Y=108, pixels X=112..119
    #d8 $19, $6C, $02    ; Y=108, pixels X=200..207
    #d8 $0E, $6D, $40    ; Y=109, pixels X=112..119
    #d8 $19, $6D, $01    ; Y=109, pixels X=200..207
    #d8 $0E, $6E, $40    ; Y=110, pixels X=112..119
    #d8 $19, $6E, $01    ; Y=110, pixels X=200..207
    #d8 $0E, $6F, $40    ; Y=111, pixels X=112..119
    #d8 $19, $6F, $01    ; Y=111, pixels X=200..207
    #d8 $0E, $70, $40    ; Y=112, pixels X=112..119
    #d8 $19, $70, $01    ; Y=112, pixels X=200..207
    #d8 $0E, $71, $40    ; Y=113, pixels X=112..119
    #d8 $19, $71, $01    ; Y=113, pixels X=200..207
    #d8 $0E, $72, $80    ; Y=114, pixels X=112..119
    #d8 $1A, $72, $80    ; Y=114, pixels X=208..215
    #d8 $0E, $73, $80    ; Y=115, pixels X=112..119
    #d8 $1A, $73, $80    ; Y=115, pixels X=208..215
    #d8 $0E, $74, $80    ; Y=116, pixels X=112..119
    #d8 $1A, $74, $80    ; Y=116, pixels X=208..215
    #d8 $0E, $75, $80    ; Y=117, pixels X=112..119
    #d8 $1A, $75, $80    ; Y=117, pixels X=208..215
    #d8 $0E, $76, $80    ; Y=118, pixels X=112..119
    #d8 $1A, $76, $80    ; Y=118, pixels X=208..215
    #d8 $0E, $77, $80    ; Y=119, pixels X=112..119
    #d8 $1A, $77, $80    ; Y=119, pixels X=208..215
    #d8 $0E, $78, $80    ; Y=120, pixels X=112..119
    #d8 $1A, $78, $80    ; Y=120, pixels X=208..215
    #d8 $0E, $79, $80    ; Y=121, pixels X=112..119
    #d8 $1A, $79, $80    ; Y=121, pixels X=208..215
    #d8 $0E, $7A, $80    ; Y=122, pixels X=112..119
    #d8 $1A, $7A, $80    ; Y=122, pixels X=208..215
    #d8 $0E, $7B, $80    ; Y=123, pixels X=112..119
    #d8 $1A, $7B, $80    ; Y=123, pixels X=208..215
    #d8 $0E, $7C, $80    ; Y=124, pixels X=112..119
    #d8 $1A, $7C, $80    ; Y=124, pixels X=208..215
    #d8 $0E, $7D, $80    ; Y=125, pixels X=112..119
    #d8 $1A, $7D, $80    ; Y=125, pixels X=208..215
    #d8 $0E, $7E, $80    ; Y=126, pixels X=112..119
    #d8 $1A, $7E, $80    ; Y=126, pixels X=208..215
    #d8 $0E, $7F, $40    ; Y=127, pixels X=112..119
    #d8 $19, $7F, $01    ; Y=127, pixels X=200..207
    #d8 $0E, $80, $40    ; Y=128, pixels X=112..119
    #d8 $19, $80, $01    ; Y=128, pixels X=200..207
    #d8 $0E, $81, $40    ; Y=129, pixels X=112..119
    #d8 $19, $81, $01    ; Y=129, pixels X=200..207
    #d8 $0E, $82, $40    ; Y=130, pixels X=112..119
    #d8 $19, $82, $01    ; Y=130, pixels X=200..207
    #d8 $0E, $83, $40    ; Y=131, pixels X=112..119
    #d8 $19, $83, $01    ; Y=131, pixels X=200..207
    #d8 $0E, $84, $20    ; Y=132, pixels X=112..119
    #d8 $19, $84, $02    ; Y=132, pixels X=200..207
    #d8 $0E, $85, $20    ; Y=133, pixels X=112..119
    #d8 $19, $85, $02    ; Y=133, pixels X=200..207
    #d8 $0E, $86, $20    ; Y=134, pixels X=112..119
    #d8 $19, $86, $02    ; Y=134, pixels X=200..207
    #d8 $0E, $87, $20    ; Y=135, pixels X=112..119
    #d8 $19, $87, $02    ; Y=135, pixels X=200..207
    #d8 $0E, $88, $10    ; Y=136, pixels X=112..119
    #d8 $19, $88, $04    ; Y=136, pixels X=200..207
    #d8 $0E, $89, $10    ; Y=137, pixels X=112..119
    #d8 $19, $89, $04    ; Y=137, pixels X=200..207
    #d8 $0E, $8A, $08    ; Y=138, pixels X=112..119
    #d8 $19, $8A, $08    ; Y=138, pixels X=200..207
    #d8 $0E, $8B, $08    ; Y=139, pixels X=112..119
    #d8 $19, $8B, $08    ; Y=139, pixels X=200..207
    #d8 $0E, $8C, $08    ; Y=140, pixels X=112..119
    #d8 $19, $8C, $08    ; Y=140, pixels X=200..207
    #d8 $0E, $8D, $04    ; Y=141, pixels X=112..119
    #d8 $19, $8D, $10    ; Y=141, pixels X=200..207
    #d8 $0E, $8E, $04    ; Y=142, pixels X=112..119
    #d8 $19, $8E, $10    ; Y=142, pixels X=200..207
    #d8 $0E, $8F, $02    ; Y=143, pixels X=112..119
    #d8 $19, $8F, $20    ; Y=143, pixels X=200..207
    #d8 $0E, $90, $02    ; Y=144, pixels X=112..119
    #d8 $19, $90, $20    ; Y=144, pixels X=200..207
    #d8 $0E, $91, $01    ; Y=145, pixels X=112..119
    #d8 $19, $91, $40    ; Y=145, pixels X=200..207
    #d8 $0F, $92, $80    ; Y=146, pixels X=120..127
    #d8 $19, $92, $80    ; Y=146, pixels X=200..207
    #d8 $0F, $93, $80    ; Y=147, pixels X=120..127
    #d8 $19, $93, $80    ; Y=147, pixels X=200..207
    #d8 $0F, $94, $40    ; Y=148, pixels X=120..127
    #d8 $18, $94, $01    ; Y=148, pixels X=192..199
    #d8 $0F, $95, $20    ; Y=149, pixels X=120..127
    #d8 $18, $95, $02    ; Y=149, pixels X=192..199
    #d8 $0F, $96, $10    ; Y=150, pixels X=120..127
    #d8 $18, $96, $04    ; Y=150, pixels X=192..199
    #d8 $0F, $97, $10    ; Y=151, pixels X=120..127
    #d8 $18, $97, $04    ; Y=151, pixels X=192..199
    #d8 $0F, $98, $08    ; Y=152, pixels X=120..127
    #d8 $18, $98, $08    ; Y=152, pixels X=192..199
    #d8 $0F, $99, $04    ; Y=153, pixels X=120..127
    #d8 $18, $99, $10    ; Y=153, pixels X=192..199
    #d8 $0F, $9A, $02    ; Y=154, pixels X=120..127
    #d8 $18, $9A, $20    ; Y=154, pixels X=192..199
    #d8 $0F, $9B, $01    ; Y=155, pixels X=120..127
    #d8 $18, $9B, $40    ; Y=155, pixels X=192..199
    #d8 $10, $9C, $80    ; Y=156, pixels X=128..135
    #d8 $18, $9C, $80    ; Y=156, pixels X=192..199
    #d8 $10, $9D, $40    ; Y=157, pixels X=128..135
    #d8 $17, $9D, $01    ; Y=157, pixels X=184..191
    #d8 $10, $9E, $10    ; Y=158, pixels X=128..135
    #d8 $17, $9E, $04    ; Y=158, pixels X=184..191
    #d8 $10, $9F, $08    ; Y=159, pixels X=128..135
    #d8 $17, $9F, $08    ; Y=159, pixels X=184..191
    #d8 $10, $A0, $04    ; Y=160, pixels X=128..135
    #d8 $17, $A0, $10    ; Y=160, pixels X=184..191
    #d8 $10, $A1, $01    ; Y=161, pixels X=128..135
    #d8 $17, $A1, $40    ; Y=161, pixels X=184..191
    #d8 $11, $A2, $40    ; Y=162, pixels X=136..143
    #d8 $16, $A2, $01    ; Y=162, pixels X=176..183
    #d8 $11, $A3, $10    ; Y=163, pixels X=136..143
    #d8 $16, $A3, $04    ; Y=163, pixels X=176..183
    #d8 $11, $A4, $04    ; Y=164, pixels X=136..143
    #d8 $16, $A4, $10    ; Y=164, pixels X=176..183
    #d8 $11, $A5, $01    ; Y=165, pixels X=136..143
    #d8 $16, $A5, $40    ; Y=165, pixels X=176..183
    #d8 $12, $A6, $20    ; Y=166, pixels X=144..151
    #d8 $15, $A6, $02    ; Y=166, pixels X=168..175
    #d8 $12, $A7, $02    ; Y=167, pixels X=144..151
    #d8 $15, $A7, $20    ; Y=167, pixels X=168..175
    #d8 $14, $A8, $80    ; Y=168, pixels X=160..167
    #d8 $FF
