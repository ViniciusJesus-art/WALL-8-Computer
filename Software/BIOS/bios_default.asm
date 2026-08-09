#include "../wall8.cpu"

#bankdef bios {
    #addr 0x0000
    #size 0xA000
    #outp 0x0000
}


; =========================
; Endereços de I/O
; =========================

IO_BASE       = 0xF000

KEY_BASE      = 0xF000
DISPLAY_BASE  = 0xF100
VIDEO_BASE    = 0xF200
TIMER_BASE    = 0xF300
SERIAL_BASE   = 0xF400
GPIO_BASE     = 0xF500
CART_IO_BASE  = 0xF600
EXP_BASE      = 0xF700

DISPLAY_LOW   = 0xF100
DISPLAY_HIGH  = 0xF101






#bank bios

ON:                         ; Configuração inicial do sistema tudo que conseguir colocar aqui, não ocupa os 8kb 
    SP $7FFF

    JMP SWAP_MEMORY


#addr 0x8000                ; Apartir daqui , Tudo fica em 0x8000


SWAP_MEMORY:
    STI $F500, #0b01110001   ; Larga a BIOS do endereço 0x0000 ficando apenas a fixa em 0x8000



;               ################## CÓDIGO INICIAL ########################
INICIO:


LOOP:

    JMP LOOP




#addr 0x9FFD
JMP INICIO