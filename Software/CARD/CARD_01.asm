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
; D0/bit 0 = pixel mais a esquerda; D7/bit 7 = pixel mais a direita.
; ------------------------------------------------------------
CIRCLE_TABLE:
    #d8 $14, $48, $01    ; Y= 72, pixels X=160..167
    #d8 $12, $49, $40    ; Y= 73, pixels X=144..151
    #d8 $15, $49, $04    ; Y= 73, pixels X=168..175
    #d8 $12, $4A, $04    ; Y= 74, pixels X=144..151
    #d8 $15, $4A, $40    ; Y= 74, pixels X=168..175
    #d8 $11, $4B, $80    ; Y= 75, pixels X=136..143
    #d8 $16, $4B, $02    ; Y= 75, pixels X=176..183
    #d8 $11, $4C, $20    ; Y= 76, pixels X=136..143
    #d8 $16, $4C, $08    ; Y= 76, pixels X=176..183
    #d8 $11, $4D, $08    ; Y= 77, pixels X=136..143
    #d8 $16, $4D, $20    ; Y= 77, pixels X=176..183
    #d8 $11, $4E, $02    ; Y= 78, pixels X=136..143
    #d8 $16, $4E, $80    ; Y= 78, pixels X=176..183
    #d8 $10, $4F, $80    ; Y= 79, pixels X=128..135
    #d8 $17, $4F, $02    ; Y= 79, pixels X=184..191
    #d8 $10, $50, $20    ; Y= 80, pixels X=128..135
    #d8 $17, $50, $08    ; Y= 80, pixels X=184..191
    #d8 $10, $51, $10    ; Y= 81, pixels X=128..135
    #d8 $17, $51, $10    ; Y= 81, pixels X=184..191
    #d8 $10, $52, $08    ; Y= 82, pixels X=128..135
    #d8 $17, $52, $20    ; Y= 82, pixels X=184..191
    #d8 $10, $53, $02    ; Y= 83, pixels X=128..135
    #d8 $17, $53, $80    ; Y= 83, pixels X=184..191
    #d8 $10, $54, $01    ; Y= 84, pixels X=128..135
    #d8 $18, $54, $01    ; Y= 84, pixels X=192..199
    #d8 $0F, $55, $80    ; Y= 85, pixels X=120..127
    #d8 $18, $55, $02    ; Y= 85, pixels X=192..199
    #d8 $0F, $56, $40    ; Y= 86, pixels X=120..127
    #d8 $18, $56, $04    ; Y= 86, pixels X=192..199
    #d8 $0F, $57, $20    ; Y= 87, pixels X=120..127
    #d8 $18, $57, $08    ; Y= 87, pixels X=192..199
    #d8 $0F, $58, $10    ; Y= 88, pixels X=120..127
    #d8 $18, $58, $10    ; Y= 88, pixels X=192..199
    #d8 $0F, $59, $08    ; Y= 89, pixels X=120..127
    #d8 $18, $59, $20    ; Y= 89, pixels X=192..199
    #d8 $0F, $5A, $08    ; Y= 90, pixels X=120..127
    #d8 $18, $5A, $20    ; Y= 90, pixels X=192..199
    #d8 $0F, $5B, $04    ; Y= 91, pixels X=120..127
    #d8 $18, $5B, $40    ; Y= 91, pixels X=192..199
    #d8 $0F, $5C, $02    ; Y= 92, pixels X=120..127
    #d8 $18, $5C, $80    ; Y= 92, pixels X=192..199
    #d8 $0F, $5D, $01    ; Y= 93, pixels X=120..127
    #d8 $19, $5D, $01    ; Y= 93, pixels X=200..207
    #d8 $0F, $5E, $01    ; Y= 94, pixels X=120..127
    #d8 $19, $5E, $01    ; Y= 94, pixels X=200..207
    #d8 $0E, $5F, $80    ; Y= 95, pixels X=112..119
    #d8 $19, $5F, $02    ; Y= 95, pixels X=200..207
    #d8 $0E, $60, $40    ; Y= 96, pixels X=112..119
    #d8 $19, $60, $04    ; Y= 96, pixels X=200..207
    #d8 $0E, $61, $40    ; Y= 97, pixels X=112..119
    #d8 $19, $61, $04    ; Y= 97, pixels X=200..207
    #d8 $0E, $62, $20    ; Y= 98, pixels X=112..119
    #d8 $19, $62, $08    ; Y= 98, pixels X=200..207
    #d8 $0E, $63, $20    ; Y= 99, pixels X=112..119
    #d8 $19, $63, $08    ; Y= 99, pixels X=200..207
    #d8 $0E, $64, $10    ; Y=100, pixels X=112..119
    #d8 $19, $64, $10    ; Y=100, pixels X=200..207
    #d8 $0E, $65, $10    ; Y=101, pixels X=112..119
    #d8 $19, $65, $10    ; Y=101, pixels X=200..207
    #d8 $0E, $66, $10    ; Y=102, pixels X=112..119
    #d8 $19, $66, $10    ; Y=102, pixels X=200..207
    #d8 $0E, $67, $08    ; Y=103, pixels X=112..119
    #d8 $19, $67, $20    ; Y=103, pixels X=200..207
    #d8 $0E, $68, $08    ; Y=104, pixels X=112..119
    #d8 $19, $68, $20    ; Y=104, pixels X=200..207
    #d8 $0E, $69, $04    ; Y=105, pixels X=112..119
    #d8 $19, $69, $40    ; Y=105, pixels X=200..207
    #d8 $0E, $6A, $04    ; Y=106, pixels X=112..119
    #d8 $19, $6A, $40    ; Y=106, pixels X=200..207
    #d8 $0E, $6B, $04    ; Y=107, pixels X=112..119
    #d8 $19, $6B, $40    ; Y=107, pixels X=200..207
    #d8 $0E, $6C, $04    ; Y=108, pixels X=112..119
    #d8 $19, $6C, $40    ; Y=108, pixels X=200..207
    #d8 $0E, $6D, $02    ; Y=109, pixels X=112..119
    #d8 $19, $6D, $80    ; Y=109, pixels X=200..207
    #d8 $0E, $6E, $02    ; Y=110, pixels X=112..119
    #d8 $19, $6E, $80    ; Y=110, pixels X=200..207
    #d8 $0E, $6F, $02    ; Y=111, pixels X=112..119
    #d8 $19, $6F, $80    ; Y=111, pixels X=200..207
    #d8 $0E, $70, $02    ; Y=112, pixels X=112..119
    #d8 $19, $70, $80    ; Y=112, pixels X=200..207
    #d8 $0E, $71, $02    ; Y=113, pixels X=112..119
    #d8 $19, $71, $80    ; Y=113, pixels X=200..207
    #d8 $0E, $72, $01    ; Y=114, pixels X=112..119
    #d8 $1A, $72, $01    ; Y=114, pixels X=208..215
    #d8 $0E, $73, $01    ; Y=115, pixels X=112..119
    #d8 $1A, $73, $01    ; Y=115, pixels X=208..215
    #d8 $0E, $74, $01    ; Y=116, pixels X=112..119
    #d8 $1A, $74, $01    ; Y=116, pixels X=208..215
    #d8 $0E, $75, $01    ; Y=117, pixels X=112..119
    #d8 $1A, $75, $01    ; Y=117, pixels X=208..215
    #d8 $0E, $76, $01    ; Y=118, pixels X=112..119
    #d8 $1A, $76, $01    ; Y=118, pixels X=208..215
    #d8 $0E, $77, $01    ; Y=119, pixels X=112..119
    #d8 $1A, $77, $01    ; Y=119, pixels X=208..215
    #d8 $0E, $78, $01    ; Y=120, pixels X=112..119
    #d8 $1A, $78, $01    ; Y=120, pixels X=208..215
    #d8 $0E, $79, $01    ; Y=121, pixels X=112..119
    #d8 $1A, $79, $01    ; Y=121, pixels X=208..215
    #d8 $0E, $7A, $01    ; Y=122, pixels X=112..119
    #d8 $1A, $7A, $01    ; Y=122, pixels X=208..215
    #d8 $0E, $7B, $01    ; Y=123, pixels X=112..119
    #d8 $1A, $7B, $01    ; Y=123, pixels X=208..215
    #d8 $0E, $7C, $01    ; Y=124, pixels X=112..119
    #d8 $1A, $7C, $01    ; Y=124, pixels X=208..215
    #d8 $0E, $7D, $01    ; Y=125, pixels X=112..119
    #d8 $1A, $7D, $01    ; Y=125, pixels X=208..215
    #d8 $0E, $7E, $01    ; Y=126, pixels X=112..119
    #d8 $1A, $7E, $01    ; Y=126, pixels X=208..215
    #d8 $0E, $7F, $02    ; Y=127, pixels X=112..119
    #d8 $19, $7F, $80    ; Y=127, pixels X=200..207
    #d8 $0E, $80, $02    ; Y=128, pixels X=112..119
    #d8 $19, $80, $80    ; Y=128, pixels X=200..207
    #d8 $0E, $81, $02    ; Y=129, pixels X=112..119
    #d8 $19, $81, $80    ; Y=129, pixels X=200..207
    #d8 $0E, $82, $02    ; Y=130, pixels X=112..119
    #d8 $19, $82, $80    ; Y=130, pixels X=200..207
    #d8 $0E, $83, $02    ; Y=131, pixels X=112..119
    #d8 $19, $83, $80    ; Y=131, pixels X=200..207
    #d8 $0E, $84, $04    ; Y=132, pixels X=112..119
    #d8 $19, $84, $40    ; Y=132, pixels X=200..207
    #d8 $0E, $85, $04    ; Y=133, pixels X=112..119
    #d8 $19, $85, $40    ; Y=133, pixels X=200..207
    #d8 $0E, $86, $04    ; Y=134, pixels X=112..119
    #d8 $19, $86, $40    ; Y=134, pixels X=200..207
    #d8 $0E, $87, $04    ; Y=135, pixels X=112..119
    #d8 $19, $87, $40    ; Y=135, pixels X=200..207
    #d8 $0E, $88, $08    ; Y=136, pixels X=112..119
    #d8 $19, $88, $20    ; Y=136, pixels X=200..207
    #d8 $0E, $89, $08    ; Y=137, pixels X=112..119
    #d8 $19, $89, $20    ; Y=137, pixels X=200..207
    #d8 $0E, $8A, $10    ; Y=138, pixels X=112..119
    #d8 $19, $8A, $10    ; Y=138, pixels X=200..207
    #d8 $0E, $8B, $10    ; Y=139, pixels X=112..119
    #d8 $19, $8B, $10    ; Y=139, pixels X=200..207
    #d8 $0E, $8C, $10    ; Y=140, pixels X=112..119
    #d8 $19, $8C, $10    ; Y=140, pixels X=200..207
    #d8 $0E, $8D, $20    ; Y=141, pixels X=112..119
    #d8 $19, $8D, $08    ; Y=141, pixels X=200..207
    #d8 $0E, $8E, $20    ; Y=142, pixels X=112..119
    #d8 $19, $8E, $08    ; Y=142, pixels X=200..207
    #d8 $0E, $8F, $40    ; Y=143, pixels X=112..119
    #d8 $19, $8F, $04    ; Y=143, pixels X=200..207
    #d8 $0E, $90, $40    ; Y=144, pixels X=112..119
    #d8 $19, $90, $04    ; Y=144, pixels X=200..207
    #d8 $0E, $91, $80    ; Y=145, pixels X=112..119
    #d8 $19, $91, $02    ; Y=145, pixels X=200..207
    #d8 $0F, $92, $01    ; Y=146, pixels X=120..127
    #d8 $19, $92, $01    ; Y=146, pixels X=200..207
    #d8 $0F, $93, $01    ; Y=147, pixels X=120..127
    #d8 $19, $93, $01    ; Y=147, pixels X=200..207
    #d8 $0F, $94, $02    ; Y=148, pixels X=120..127
    #d8 $18, $94, $80    ; Y=148, pixels X=192..199
    #d8 $0F, $95, $04    ; Y=149, pixels X=120..127
    #d8 $18, $95, $40    ; Y=149, pixels X=192..199
    #d8 $0F, $96, $08    ; Y=150, pixels X=120..127
    #d8 $18, $96, $20    ; Y=150, pixels X=192..199
    #d8 $0F, $97, $08    ; Y=151, pixels X=120..127
    #d8 $18, $97, $20    ; Y=151, pixels X=192..199
    #d8 $0F, $98, $10    ; Y=152, pixels X=120..127
    #d8 $18, $98, $10    ; Y=152, pixels X=192..199
    #d8 $0F, $99, $20    ; Y=153, pixels X=120..127
    #d8 $18, $99, $08    ; Y=153, pixels X=192..199
    #d8 $0F, $9A, $40    ; Y=154, pixels X=120..127
    #d8 $18, $9A, $04    ; Y=154, pixels X=192..199
    #d8 $0F, $9B, $80    ; Y=155, pixels X=120..127
    #d8 $18, $9B, $02    ; Y=155, pixels X=192..199
    #d8 $10, $9C, $01    ; Y=156, pixels X=128..135
    #d8 $18, $9C, $01    ; Y=156, pixels X=192..199
    #d8 $10, $9D, $02    ; Y=157, pixels X=128..135
    #d8 $17, $9D, $80    ; Y=157, pixels X=184..191
    #d8 $10, $9E, $08    ; Y=158, pixels X=128..135
    #d8 $17, $9E, $20    ; Y=158, pixels X=184..191
    #d8 $10, $9F, $10    ; Y=159, pixels X=128..135
    #d8 $17, $9F, $10    ; Y=159, pixels X=184..191
    #d8 $10, $A0, $20    ; Y=160, pixels X=128..135
    #d8 $17, $A0, $08    ; Y=160, pixels X=184..191
    #d8 $10, $A1, $80    ; Y=161, pixels X=128..135
    #d8 $17, $A1, $02    ; Y=161, pixels X=184..191
    #d8 $11, $A2, $02    ; Y=162, pixels X=136..143
    #d8 $16, $A2, $80    ; Y=162, pixels X=176..183
    #d8 $11, $A3, $08    ; Y=163, pixels X=136..143
    #d8 $16, $A3, $20    ; Y=163, pixels X=176..183
    #d8 $11, $A4, $20    ; Y=164, pixels X=136..143
    #d8 $16, $A4, $08    ; Y=164, pixels X=176..183
    #d8 $11, $A5, $80    ; Y=165, pixels X=136..143
    #d8 $16, $A5, $02    ; Y=165, pixels X=176..183
    #d8 $12, $A6, $04    ; Y=166, pixels X=144..151
    #d8 $15, $A6, $40    ; Y=166, pixels X=168..175
    #d8 $12, $A7, $40    ; Y=167, pixels X=144..151
    #d8 $15, $A7, $04    ; Y=167, pixels X=168..175
    #d8 $14, $A8, $01    ; Y=168, pixels X=160..167
    #d8 $FF
