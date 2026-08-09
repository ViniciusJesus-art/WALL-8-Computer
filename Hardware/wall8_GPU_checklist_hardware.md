# WALL-8 — Checklist de implementação da GPU

Este documento é um checklist prático para projetar, montar e validar o hardware da placa de vídeo do WALL-8.

O objetivo é confirmar que a GPU física implemente o protocolo definido para a CPU e produza os três modos de vídeo esperados sem depender da BIOS para gerar sincronismo, ampliar pixels ou controlar diretamente a VRAM.

> Marque um item somente depois de ele ter sido implementado e testado. Itens marcados como **críticos** podem impedir completamente a geração da imagem ou causar contenção elétrica.

---

## 1. Comportamento oficial dos modos

| Comando | Modo | Organização lógica | `VIDEO_X` | `VIDEO_Y` | Bytes por linha | VRAM usada | Expansão física |
|---:|---|---|---:|---:|---:|---:|---|
| `$11` | Texto | 80 × 30 caracteres, fonte 8 × 8 | 0..79 | 0..29 | 80 | 2.400 bytes | 1× horizontal e 2× vertical |
| `$12` | Gráfico | 320 × 240, 1 bit por pixel | 0..39 | 0..239 | 40 | 9.600 bytes | 2× horizontal e 2× vertical |
| `$13` | Gráfico | 160 × 120, 1 bit por pixel | 0..19 | 0..119 | 20 | 2.400 bytes | 4× horizontal e 4× vertical |

Em todos os modos, o monitor recebe uma temporização física de `640 × 480` próxima de `60 Hz`.

- [ ] A troca de modo altera somente a interpretação da VRAM e a expansão dos pixels.
- [ ] A troca de modo não altera os totais de `HSYNC`, `VSYNC`, linhas ou pixels físicos.
- [ ] O modo selecionado fica armazenado em um latch interno.
- [ ] Os comandos `$11`, `$12` e `$13` selecionam apenas um modo por vez.
- [ ] A troca de modo coloca `VIDEO_X = 0` e `VIDEO_Y = 0`.
- [ ] A troca de modo limpa `CURSOR_END`.

---

## 2. Blocos obrigatórios da placa

- [ ] Oscilador de vídeo de `25,175 MHz` ou `25,2 MHz`.
- [ ] Buffer dedicado para distribuir o pixel clock.
- [ ] Contador horizontal `H_COUNTER` de pelo menos 10 bits.
- [ ] Contador vertical `V_COUNTER` de pelo menos 10 bits.
- [ ] Decodificação de área visível, porches, `HSYNC` e `VSYNC`.
- [ ] Latch do modo de vídeo atual.
- [ ] Decodificador dos registradores `$F200..$F204`.
- [ ] Latches CPU-visíveis `VIDEO_DATA`, `VIDEO_X` e `VIDEO_Y`.
- [ ] Decodificador de comandos de `VIDEO_CMD`.
- [ ] Registro ou lógica de `VIDEO_STATUS`.
- [ ] Flip-flops `WRITE_PENDING`, `READ_PENDING` e estado de limpeza, ou máquina de estados equivalente.
- [ ] Lógica de `BUSY`.
- [ ] Gerador do endereço solicitado pela CPU.
- [ ] Gerador do endereço usado pela varredura.
- [ ] Contador interno de endereço para `VIDEO_CLEAR`.
- [ ] Multiplexador dos endereços da VRAM.
- [ ] Transceptor ou buffers tri-state do barramento de dados da VRAM.
- [ ] SRAM `62256` de 32 KiB.
- [ ] Latch para o byte lido da VRAM.
- [ ] EPROM de caracteres, como a `27C512`.
- [ ] Shift register para emissão dos pixels.
- [ ] Contador de repetição horizontal conforme o modo.
- [ ] Seleção da linha lógica conforme a repetição vertical.
- [ ] Lógica de cursor textual visível/oculto.
- [ ] Circuito de saída VGA para RGB, `HSYNC` e `VSYNC`.
- [ ] Sinal físico `/VIDEO_DETECT`.

---

## 3. Dois sistemas de coordenadas separados

Esta separação é obrigatória:

```text
VIDEO_X / VIDEO_Y
    Coordenada preparada pela CPU para ler ou escrever a VRAM.

H_COUNTER / V_COUNTER
    Posição física que a GPU está enviando ao monitor naquele instante.
```

- [ ] `VIDEO_X` e `VIDEO_Y` possuem latches próprios.
- [ ] `H_COUNTER` e `V_COUNTER` possuem contadores próprios.
- [ ] Alterar `VIDEO_X` ou `VIDEO_Y` não desloca a varredura VGA.
- [ ] A varredura VGA continua funcionando mesmo quando a CPU está parada.
- [ ] O endereço da CPU e o endereço de varredura entram em um MUX antes da VRAM.
- [ ] Somente uma origem controla o barramento de endereço da VRAM em cada instante.

---

## 4. Pixel clock e sincronismo VGA

### 4.1. Contador horizontal

- [ ] `H_COUNTER` conta de `0` até `799`.
- [ ] Depois de `799`, `H_COUNTER` retorna para `0`.
- [ ] O retorno horizontal incrementa `V_COUNTER` uma única vez.
- [ ] A área horizontal visível corresponde a `0..639`.
- [ ] O front porch corresponde a `640..655`.
- [ ] `HSYNC` fica em nível baixo entre `656..751`.
- [ ] O back porch corresponde a `752..799`.
- [ ] `HBLANK = 1` durante `640..799`.

### 4.2. Contador vertical

- [ ] `V_COUNTER` conta de `0` até `524`.
- [ ] Depois de `524`, `V_COUNTER` retorna para `0`.
- [ ] A área vertical visível corresponde a `0..479`.
- [ ] O front porch corresponde a `480..489`.
- [ ] `VSYNC` fica em nível baixo entre `490..491`.
- [ ] O back porch corresponde a `492..524`.
- [ ] `VBLANK = 1` durante `480..524`.
- [ ] `FRAME` alterna uma vez quando um novo quadro começa.

### 4.3. Saída visível

- [ ] `VIDEO_ACTIVE = 1` somente quando `H_COUNTER < 640` e `V_COUNTER < 480`.
- [ ] A saída RGB fica preta quando `VIDEO_ACTIVE = 0`.
- [ ] O blanking não interrompe os contadores nem os sinais de sincronismo.
- [ ] A frequência horizontal medida fica próxima de `31,47 kHz`.
- [ ] A frequência vertical medida fica próxima de `59,94 Hz` com `25,175 MHz`.
- [ ] O monitor reconhece continuamente o sinal como `640 × 480`.

### 4.4. Tabela completa da temporização final

Os tempos abaixo consideram o pixel clock nominal de `25,175 MHz`:

| Parâmetro geral | Valor |
|---|---:|
| Resolução física ativa | 640 × 480 |
| Tipo de varredura | Progressiva, não entrelaçada |
| Pixel clock | 25,175 MHz |
| Período de um pixel clock | 39,722 ns |
| Total horizontal | 800 clocks |
| Período de uma linha | 31,778 µs |
| Frequência horizontal | 31,469 kHz |
| Total vertical | 525 linhas |
| Período de um quadro | 16,683 ms |
| Frequência vertical | 59,940 Hz |
| Polaridade de `HSYNC` | Negativa, ativo em nível baixo |
| Polaridade de `VSYNC` | Negativa, ativo em nível baixo |

#### Temporização horizontal

| Região | Quantidade | Faixa inclusiva de `H_COUNTER` | Duração aproximada | `VIDEO_ACTIVE` | `HSYNC` |
|---|---:|---:|---:|:---:|:---:|
| Vídeo visível | 640 clocks | `0..639` | 25,422 µs | Depende também de V | 1 |
| Front porch | 16 clocks | `640..655` | 0,636 µs | 0 | 1 |
| Pulso de sincronismo | 96 clocks | `656..751` | 3,813 µs | 0 | **0** |
| Back porch | 48 clocks | `752..799` | 1,907 µs | 0 | 1 |
| **Total da linha** | **800 clocks** | **`0..799`** | **31,778 µs** | — | — |

Relações horizontais:

```text
640 + 16 + 96 + 48 = 800 clocks

H_VISIBLE = 1 quando H_COUNTER <= 639
HBLANK    = 1 quando H_COUNTER >= 640
HSYNC     = 0 quando 656 <= H_COUNTER <= 751
H_END     = 1 quando H_COUNTER = 799
```

#### Temporização vertical

| Região | Quantidade | Faixa inclusiva de `V_COUNTER` | Duração aproximada | `VIDEO_ACTIVE` | `VSYNC` |
|---|---:|---:|---:|:---:|:---:|
| Vídeo visível | 480 linhas | `0..479` | 15,253 ms | Depende também de H | 1 |
| Front porch | 10 linhas | `480..489` | 0,318 ms | 0 | 1 |
| Pulso de sincronismo | 2 linhas | `490..491` | 0,064 ms | 0 | **0** |
| Back porch | 33 linhas | `492..524` | 1,049 ms | 0 | 1 |
| **Total do quadro** | **525 linhas** | **`0..524`** | **16,683 ms** | — | — |

Relações verticais:

```text
480 + 10 + 2 + 33 = 525 linhas

V_VISIBLE = 1 quando V_COUNTER <= 479
VBLANK    = 1 quando V_COUNTER >= 480
VSYNC     = 0 quando 490 <= V_COUNTER <= 491
V_END     = 1 quando V_COUNTER = 524

VIDEO_ACTIVE = H_VISIBLE AND V_VISIBLE
```

#### Eventos dos contadores

| Condição atual | Ação na próxima borda do pixel clock |
|---|---|
| `H_COUNTER < 799` | `H_COUNTER = H_COUNTER + 1` |
| `H_COUNTER = 799` e `V_COUNTER < 524` | `H_COUNTER = 0`; `V_COUNTER = V_COUNTER + 1` |
| `H_COUNTER = 799` e `V_COUNTER = 524` | `H_COUNTER = 0`; `V_COUNTER = 0`; alterna `FRAME` |

- [ ] O contador horizontal utiliza pelo menos 10 bits, pois precisa representar `0..799`.
- [ ] O contador vertical utiliza pelo menos 10 bits, pois precisa representar `0..524`.
- [ ] A lógica de fim usa comparação com `799` e `524`, e não o overflow natural de 10 bits.
- [ ] `V_COUNTER` somente é incrementado quando `H_COUNTER` termina a linha.
- [ ] `FRAME` somente alterna na passagem de `(799,524)` para `(0,0)`.

#### Efeito de clocks alternativos

Mantendo os mesmos totais de `800 × 525`:

| Pixel clock | Frequência horizontal | Frequência vertical | Período do quadro | Uso |
|---:|---:|---:|---:|---|
| 25,175 MHz | 31,469 kHz | 59,940 Hz | 16,683 ms | Valor nominal clássico |
| 25,200 MHz | 31,500 kHz | 60,000 Hz | 16,667 ms | Alternativa muito próxima |
| 25,000 MHz | 31,250 kHz | 59,524 Hz | 16,800 ms | Pode funcionar, mas não é o valor preferido |

> **Convenção adotada pelo WALL-8:** usar vertical `480 + 10 + 2 + 33 = 525`. A página de referência também apresenta em uma tabela antiga a divisão `480 + 11 + 2 + 31`, mas ela não deve ser misturada com os limites `480, 490, 492 e 525` usados no projeto. A tabela padrão publicada pela IBM confirma `10` linhas de front porch, `2` de sincronismo e `33` de back porch.

Referências:

- [VGA Timings — Martin Hinner](https://martin.hinner.info/vga/timing.html)
- [IBM — Supported resolution timing charts](https://www.ibm.com/docs/TI0003M/p8egb/p8egb_supportedresolution.htm)

---

## 5. Interface com a CPU

### 5.1. Mapa de registradores

| Endereço | Nome | Escrita pela CPU | Leitura pela CPU |
|---:|---|---|---|
| `$F200` | `VIDEO_DATA` | Dispara escrita na VRAM | Resultado da última leitura concluída |
| `$F201` | `VIDEO_CMD` | Envia comando | Não necessário na primeira versão |
| `$F202` | `VIDEO_X` | Define posição horizontal | Opcionalmente retorna o latch atual |
| `$F203` | `VIDEO_Y` | Define posição vertical | Opcionalmente retorna o latch atual |
| `$F204` | `VIDEO_STATUS` | Não utilizado | Retorna o estado da GPU |

- [ ] A página de vídeo é selecionada no intervalo `$F200..$F2FF`.
- [ ] Os bits baixos do endereço distinguem `$F200..$F204`.
- [ ] Um latch somente aceita dados quando seu endereço e o strobe de escrita da CPU estão ativos simultaneamente.
- [ ] Um buffer de leitura somente é habilitado quando seu endereço e o strobe de leitura da CPU estão ativos simultaneamente.
- [ ] As polaridades de `/MEMORY_OE`, `/MEMORY_WE` e do seletor da página de vídeo foram conferidas.
- [ ] A placa não responde a outros endereços de I/O.
- [ ] O barramento de dados da CPU somente é dirigido pela GPU durante uma leitura válida selecionada.
- [ ] A saída para o barramento da CPU fica em alta impedância no restante do tempo.
- [ ] Escritas em `VIDEO_X` e `VIDEO_Y` apenas atualizam os latches; elas não acessam a VRAM.
- [ ] Uma escrita em `VIDEO_DATA` captura o byte e cria uma operação pendente.
- [ ] Uma leitura comum de `VIDEO_DATA` não inicia uma leitura física da VRAM.

### 5.2. Comandos

| Valor | Comando | Ação obrigatória |
|---:|---|---|
| `$00` | `VIDEO_CLEAR` | Limpa a área usada pelo modo ativo |
| `$04` | `CURSOR_HIDE` | Oculta o cursor no modo texto |
| `$05` | `CURSOR_SHOW` | Exibe o cursor no modo texto |
| `$11` | `MODE_TEXT_80X30` | Seleciona texto 80 × 30 |
| `$12` | `MODE_GFX_320X240` | Seleciona gráfico 320 × 240 |
| `$13` | `MODE_GFX_160X120` | Seleciona gráfico 160 × 120 |
| `$20` | `VRAM_READ` | Solicita leitura assíncrona da posição X/Y |

- [ ] Valores de comando não implementados não causam escrita acidental na VRAM.
- [ ] Os comandos de cursor não alteram a imagem nos modos gráficos.
- [ ] Os comandos de modo não alteram a temporização VGA física.

### 5.3. Detecção da placa

- [ ] A presença física da GPU força `/VIDEO_DETECT` para nível baixo.
- [ ] Com a GPU desconectada, o pull-up da placa principal mantém `/VIDEO_DETECT` em nível alto.
- [ ] A GPU não precisa dirigir nível alto nessa linha; ela somente informa presença em nível baixo.
- [ ] O estado chega ao bit 5 de `$F300`: `0 = presente`, `1 = ausente`.

---

## 6. `VIDEO_STATUS`

| Bit | Nome | Função |
|---:|---|---|
| 0 | `BUSY` | Interface reservada por escrita, leitura ou comando |
| 1 | `VBLANK` | Fora das 480 linhas visíveis |
| 2 | `HBLANK` | Fora dos 640 pixels horizontais visíveis |
| 3 | `FRAME` | Alterna a cada quadro completo |
| 4 | `CURSOR_END` | Última posição válida foi escrita e X/Y ficaram travados |
| 5..7 | Reservados | Devem retornar zero |

- [ ] A leitura de `VIDEO_STATUS` não altera nenhuma flag.
- [ ] `BUSY` permanece alto durante toda a operação, não somente durante o pulso de `/WE`.
- [ ] `CURSOR_END` é uma flag retida.
- [ ] `VBLANK` acompanha o contador vertical.
- [ ] `HBLANK` acompanha o contador horizontal.
- [ ] `FRAME` não gera pulsos estreitos; seu nível alternado pode ser lido pela CPU.
- [ ] Os bits reservados retornam zero.

---

## 7. `BUSY` e operações pendentes

### 7.1. Escrita da CPU

- [ ] Com `BUSY = 0`, uma escrita em `VIDEO_DATA` captura simultaneamente o dado e a posição já armazenada em X/Y.
- [ ] A escrita em `VIDEO_DATA` ativa `WRITE_PENDING`.
- [ ] `BUSY` sobe imediatamente quando a operação é aceita.
- [ ] X, Y e DATA permanecem estáveis até a conclusão da transferência.
- [ ] A máquina de estados aguarda um slot livre da VRAM.
- [ ] O endereço da CPU é selecionado no MUX somente durante o slot da operação.
- [ ] `/OE` da SRAM fica inativo antes de habilitar o buffer de escrita.
- [ ] Endereço e dados respeitam os tempos de setup do datasheet da SRAM.
- [ ] `/WE` recebe um único pulso válido.
- [ ] Os dados respeitam o tempo de hold depois de `/WE`.
- [ ] O buffer CPU→VRAM volta para alta impedância depois da escrita.
- [ ] O MUX retorna ao endereço de varredura.
- [ ] X/Y são incrementados somente depois da gravação física.
- [ ] `WRITE_PENDING` é limpo somente depois da gravação.
- [ ] `BUSY` volta a zero por último.

### 7.2. Leitura da CPU

- [ ] O comando `$20` captura a posição X/Y e ativa `READ_PENDING`.
- [ ] `BUSY` sobe quando `$20` é aceito.
- [ ] A leitura física acontece em um slot livre da VRAM.
- [ ] O byte lido é armazenado em um latch de resultado.
- [ ] `READ_PENDING` é limpo depois que o latch recebe o resultado.
- [ ] `BUSY` volta a zero somente quando o resultado já pode ser lido em `VIDEO_DATA`.
- [ ] A leitura não incrementa `VIDEO_X` nem `VIDEO_Y`.

### 7.3. Proteção da operação

- [ ] Uma operação pendente nunca é substituída silenciosamente por outra.
- [ ] A BIOS respeita o contrato de não alterar X, Y, DATA ou CMD enquanto `BUSY = 1`.
- [ ] Nenhuma combinação de estado habilita simultaneamente dois drivers no barramento de dados.
- [ ] Em reset, `WRITE_PENDING = 0`, `READ_PENDING = 0` e `BUSY = 0`.

---

## 8. Cruzamento entre os clocks da CPU e da GPU — crítico

A CPU trabalha em até `16 MHz`, enquanto a GPU usa aproximadamente `25,175 MHz`. Esses clocks são assíncronos entre si.

- [ ] O pulso de escrita vindo da CPU não depende de coincidir diretamente com uma borda do pixel clock.
- [ ] A solicitação pendente é armazenada em um flip-flop, latch ou handshake que permaneça ativo até ser reconhecido pela GPU.
- [ ] O pedido da CPU é sincronizado antes de entrar na máquina de estados do domínio de vídeo.
- [ ] X, Y e DATA ficam estáveis durante todo o handshake, permitindo transferência conjunta dos vários bits.
- [ ] O reconhecimento/conclusão retorna ao domínio da CPU sem produzir metastabilidade em `BUSY`.
- [ ] Sinais originados nos contadores de vídeo e lidos pela CPU (`VBLANK`, `HBLANK` e `FRAME`) são sincronizados ou implementados de forma segura para leitura assíncrona.
- [ ] O circuito foi testado com clocks sem relação de fase fixa.
- [ ] O circuito continua funcionando quando a CPU opera na frequência máxima de 16 MHz.

> Não use um pulso muito curto de um domínio como clock direto de vários flip-flops do outro domínio. Para a primeira versão, um pedido retido até confirmação é mais seguro que um pulso momentâneo.

---

## 9. VRAM e geração de endereços

### 9.1. Memória física

- [ ] A SRAM `62256` possui 15 linhas de endereço e 8 linhas de dados.
- [ ] Todos os pinos de endereço possuem nível definido em qualquer estado.
- [ ] `/CE`, `/OE` e `/WE` nunca ficam flutuando.
- [ ] `/WE` permanece inativo durante leituras de varredura.
- [ ] O buffer de escrita permanece em alta impedância durante leituras.
- [ ] A SRAM nunca dirige o barramento enquanto outro buffer também o dirige.

### 9.2. Endereço da operação da CPU

| Modo | Fórmula | Implementação por deslocamentos | Último endereço usado |
|---|---|---|---:|
| Texto | `Y × 80 + X` | `(Y << 6) + (Y << 4) + X` | `$095F` |
| Gráfico 320 × 240 | `Y × 40 + X` | `(Y << 5) + (Y << 3) + X` | `$257F` |
| Gráfico 160 × 120 | `Y × 20 + X` | `(Y << 4) + (Y << 2) + X` | `$095F` |

- [ ] O modo ativo seleciona a fórmula correta.
- [ ] A soma possui bits suficientes para chegar a `$257F` sem overflow.
- [ ] `VIDEO_X` gráfico representa uma coluna de byte, não um pixel individual.
- [ ] `VIDEO_Y` gráfico representa uma linha lógica de pixels.
- [ ] O bit 7 de `VIDEO_DATA` corresponde ao pixel mais à esquerda.

### 9.3. Endereço de varredura

- [ ] Existe um endereço-base para a linha lógica atual.
- [ ] Existe um contador de byte dentro da linha.
- [ ] No fim de cada linha física, o endereço volta ao início da linha lógica correspondente.
- [ ] O endereço-base somente avança quando começa uma nova linha lógica.
- [ ] No modo texto, o endereço-base avança 80 bytes a cada 16 linhas físicas.
- [ ] No modo 320 × 240, o endereço-base avança 40 bytes a cada 2 linhas físicas.
- [ ] No modo 160 × 120, o endereço-base avança 20 bytes a cada 4 linhas físicas.
- [ ] No início de cada quadro, o endereço-base retorna para `$0000`.

---

## 10. Modo texto 80 × 30

### 10.1. Coordenadas e VRAM

- [ ] `VIDEO_X` seleciona uma coluna de caractere entre `0..79`.
- [ ] `VIDEO_Y` seleciona uma linha de caractere entre `0..29`.
- [ ] Cada célula ocupa exatamente um byte na VRAM.
- [ ] O byte da VRAM é interpretado como código de caractere, não como pixels.
- [ ] Uma linha textual possui 80 bytes.
- [ ] A tela textual utiliza 2.400 bytes em `$0000..$095F`.

### 10.2. ROM de caracteres

- [ ] A fonte contém 256 caracteres.
- [ ] Cada caractere contém 8 linhas de 8 bits.
- [ ] A fonte inicial ocupa 2.048 bytes.
- [ ] O endereço da fonte segue `código × 8 + linha_da_fonte`.
- [ ] Na EPROM, `A0..A2` recebem a linha da fonte `0..7`.
- [ ] Na EPROM, `A3..A10` recebem o código de caractere `0..255`.
- [ ] Os bits superiores `A11..A15` da `27C512` ficam em nível definido no banco inicial.
- [ ] O bit 7 da linha da fonte aparece à esquerda da célula.

### 10.3. Formação da célula física

```text
H0..H2 → pixel 0..7 dentro do caractere
H3..H9 → coluna textual 0..79

V0     → repetição vertical 0 ou 1
V1..V3 → linha 0..7 da fonte
V4..V8 → linha textual 0..29
```

- [ ] Não existe duplicação horizontal no modo texto.
- [ ] Cada bit da fonte dura exatamente um pixel clock físico.
- [ ] Cada linha da fonte é exibida em duas linhas físicas consecutivas.
- [ ] A fonte continua armazenada como 8 × 8.
- [ ] A célula visível ocupa 8 × 16 pixels físicos.
- [ ] `80 × 8 = 640` pixels horizontais.
- [ ] `30 × 16 = 480` pixels verticais.
- [ ] A mesma linha da fonte é selecionada quando apenas `V0` muda.
- [ ] Depois de oito pixels, o próximo código de caractere é carregado.
- [ ] Depois de 80 caracteres, a linha visível termina exatamente em `H = 639`.

### 10.4. Caminho dos dados textuais

```text
VRAM → latch do código → endereço da ROM → byte da fonte → shift register → VGA
```

- [ ] O código lido da VRAM é retido enquanto a ROM de fonte responde.
- [ ] O byte retornado pela ROM é carregado no shift register antes do primeiro pixel da célula.
- [ ] O shift register emite os bits na ordem 7, 6, 5, 4, 3, 2, 1, 0.
- [ ] O tempo VRAM + latch + EPROM + lógica cabe na janela de oito clocks, aproximadamente `318 ns`.

---

## 11. Cursor do modo texto

- [ ] `CURSOR_SHOW` habilita a representação visual do cursor.
- [ ] `CURSOR_HIDE` desabilita a representação visual do cursor.
- [ ] O cursor aparece somente quando a célula varrida coincide com `VIDEO_X/VIDEO_Y`.
- [ ] O cursor não modifica o conteúdo armazenado na VRAM.
- [ ] O formato foi definido como sublinhado ou bloco invertido.
- [ ] Se houver pisca, ele é gerado por divisor interno e não pela CPU.
- [ ] O cursor não aparece nos modos gráficos.
- [ ] O cursor é suprimido durante o blanking.

---

## 12. Modo gráfico 320 × 240

- [ ] `VIDEO_X` representa uma coluna de byte entre `0..39`.
- [ ] `VIDEO_Y` representa uma linha lógica entre `0..239`.
- [ ] Cada byte representa oito pixels lógicos horizontais.
- [ ] Uma linha lógica possui 40 bytes.
- [ ] O framebuffer utiliza 9.600 bytes em `$0000..$257F`.
- [ ] O bit 7 é o primeiro pixel e o bit 0 é o oitavo pixel.
- [ ] Cada bit do byte permanece na saída durante dois pixels clocks.
- [ ] Cada linha lógica é exibida em duas linhas físicas.
- [ ] Cada pixel lógico forma um bloco físico de 2 × 2.
- [ ] Um byte alimenta 16 pixels físicos horizontais.
- [ ] Depois de 40 bytes, a linha termina exatamente em `H = 639`.
- [ ] `Y_lógico = V_COUNTER >> 1` durante a área visível.

---

## 13. Modo gráfico 160 × 120

- [ ] `VIDEO_X` representa uma coluna de byte entre `0..19`.
- [ ] `VIDEO_Y` representa uma linha lógica entre `0..119`.
- [ ] Cada byte representa oito pixels lógicos horizontais.
- [ ] Uma linha lógica possui 20 bytes.
- [ ] O framebuffer utiliza 2.400 bytes em `$0000..$095F`.
- [ ] O bit 7 é o primeiro pixel e o bit 0 é o oitavo pixel.
- [ ] Cada bit do byte permanece na saída durante quatro pixels clocks.
- [ ] Cada linha lógica é exibida em quatro linhas físicas.
- [ ] Cada pixel lógico forma um bloco físico de 4 × 4.
- [ ] Um byte alimenta 32 pixels físicos horizontais.
- [ ] Depois de 20 bytes, a linha termina exatamente em `H = 639`.
- [ ] `Y_lógico = V_COUNTER >> 2` durante a área visível.

---

## 14. Pré-carregamento e pipeline da varredura — crítico

A SRAM e a ROM não respondem instantaneamente. O byte necessário para `H = 0` precisa estar pronto antes do primeiro pixel visível.

- [ ] O primeiro byte de cada linha é buscado durante o blanking anterior ou por uma etapa equivalente de pré-carregamento.
- [ ] O shift register já contém o dado correto quando começa `H = 0`.
- [ ] O próximo byte é buscado enquanto o byte atual ainda está sendo exibido.
- [ ] O dado seguinte é retido separadamente até o instante correto de carregar o shift register.
- [ ] A leitura antecipada não avança duas vezes o endereço de varredura.
- [ ] A última célula ou byte da linha não invade o front porch.
- [ ] A primeira célula ou byte da linha não mostra dados da linha anterior.
- [ ] A mudança de linha da fonte no modo texto ocorre antes do primeiro caractere da nova linha física.
- [ ] A mudança de modo não produz contenção entre os caminhos textual e gráfico.

Janelas aproximadas disponíveis entre buscas da VRAM:

| Modo | Clocks físicos por byte | Janela aproximada |
|---|---:|---:|
| Texto | 8 | 318 ns |
| Gráfico 320 × 240 | 16 | 635 ns |
| Gráfico 160 × 120 | 32 | 1,27 µs |

O modo texto é o pior caso de temporização e deve ser usado como referência para validar SRAM, EPROM, MUX, latches e máquina de estados.

---

## 15. Arbitragem da VRAM — crítico

Prioridade oficial:

```text
1. Busca necessária para a varredura
2. Operação pendente da CPU
3. Passo do comando VIDEO_CLEAR
```

- [ ] A busca do próximo byte de vídeo nunca perde o prazo.
- [ ] Depois de carregar o byte de vídeo, a VRAM pode ser cedida para uma operação pendente.
- [ ] Uma operação da CPU não interrompe o shift register atual.
- [ ] `VIDEO_CLEAR` utiliza somente slots que não prejudiquem a varredura.
- [ ] A máquina de estados sempre retorna ao estado de varredura.
- [ ] Não existe estado em que `/OE = 0` e `/WE = 0` simultaneamente.
- [ ] Não existe estado em que SRAM e buffer de escrita dirijam o barramento ao mesmo tempo.
- [ ] O MUX de endereço somente troca quando `/WE` está inativo.
- [ ] A troca de endereço respeita o tempo de estabilização antes de `/OE` ou `/WE`.
- [ ] O pior caso foi testado no modo texto com a CPU escrevendo continuamente.

---

## 16. Incremento automático e `CURSOR_END`

| Modo | `X_MAX` | `Y_MAX` | Próxima linha | Última posição |
|---|---:|---:|---|---|
| Texto 80 × 30 | 79 | 29 | Depois de X=79, X→0 e Y+1 | `(79,29)` |
| Gráfico 320 × 240 | 39 | 239 | Depois de X=39, X→0 e Y+1 | `(39,239)` |
| Gráfico 160 × 120 | 19 | 119 | Depois de X=19, X→0 e Y+1 | `(19,119)` |

- [ ] Se `X < X_MAX`, uma escrita concluída produz `X = X + 1`.
- [ ] Se `X = X_MAX` e `Y < Y_MAX`, uma escrita concluída produz `X = 0` e `Y = Y + 1`.
- [ ] Se `X = X_MAX` e `Y = Y_MAX`, X e Y permanecem na última posição.
- [ ] Na última posição, `CURSOR_END` passa para 1.
- [ ] A posição não retorna automaticamente para `(0,0)` no fim da tela.
- [ ] Uma nova escrita sem reposicionamento sobrescreve somente a última posição.
- [ ] Escrever explicitamente em `VIDEO_X` limpa `CURSOR_END`.
- [ ] Escrever explicitamente em `VIDEO_Y` limpa `CURSOR_END`.
- [ ] Trocar o modo limpa `CURSOR_END`.
- [ ] Concluir `VIDEO_CLEAR` limpa `CURSOR_END`.
- [ ] X/Y são atualizados antes de `BUSY` voltar a zero.

---

## 17. Comando `VIDEO_CLEAR`

| Modo | Primeiro endereço | Último endereço | Quantidade | Valor escrito |
|---|---:|---:|---:|---:|
| Texto 80 × 30 | `$0000` | `$095F` | 2.400 | `$20` |
| Gráfico 320 × 240 | `$0000` | `$257F` | 9.600 | `$00` |
| Gráfico 160 × 120 | `$0000` | `$095F` | 2.400 | `$00` |

- [ ] O comando captura o modo ativo no início da operação.
- [ ] `BUSY` sobe quando a limpeza começa.
- [ ] Um contador interno percorre todos os endereços necessários.
- [ ] A limpeza não ultrapassa o último endereço do modo.
- [ ] A varredura continua gerando imagem e sincronismo durante a limpeza.
- [ ] O valor `$20` é usado no texto para representar espaço.
- [ ] O valor `$00` é usado nos modos gráficos.
- [ ] Ao terminar, `VIDEO_X = 0` e `VIDEO_Y = 0`.
- [ ] Ao terminar, `CURSOR_END = 0`.
- [ ] `BUSY` volta a zero somente depois da última escrita.

---

## 18. Reset e inicialização elétrica

- [ ] O reset coloca os contadores VGA em estados conhecidos.
- [ ] O reset desativa `/WE` da VRAM.
- [ ] O reset coloca todos os buffers tri-state em estado seguro.
- [ ] O reset limpa `WRITE_PENDING` e `READ_PENDING`.
- [ ] O reset limpa o estado de `VIDEO_CLEAR`.
- [ ] O reset coloca `BUSY = 0`.
- [ ] O reset coloca `CURSOR_END = 0`.
- [ ] O reset coloca `VIDEO_X = 0` e `VIDEO_Y = 0`.
- [ ] O modo inicial é definido ou a saída permanece preta até a BIOS selecionar um modo.
- [ ] A GPU gera sincronismo válido mesmo antes de a BIOS escrever qualquer caractere.
- [ ] Nenhuma entrada CMOS fica flutuando durante ou depois do reset.

---

## 19. Saída VGA

- [ ] O conector VGA possui todos os terras necessários conectados ao GND da placa.
- [ ] `HSYNC` e `VSYNC` possuem polaridade negativa.
- [ ] RGB permanece preto durante o blanking.
- [ ] O nível RGB é limitado por resistores adequados para a carga de 75 Ω do monitor.
- [ ] As entradas RGB do monitor não recebem 5 V diretamente.
- [ ] No modo monocromático, o bit de vídeo aciona a combinação definida de R, G e B.
- [ ] As trilhas de pixel clock, sincronismo e vídeo são curtas e possuem retorno de GND próximo.
- [ ] O conector e a pinagem foram conferidos antes de ligar um monitor real.

---

## 20. Temporização, família lógica e placa PTH

- [ ] Foi calculado o atraso total do caminho crítico, não apenas a frequência máxima isolada de cada CI.
- [ ] O caminho de 25,175 MHz utiliza componentes com margem suficiente para contadores, comparadores, MUX e shift registers.
- [ ] A família lógica escolhida é eletricamente compatível com SRAM, EPROM e barramentos do WALL-8.
- [ ] O fan-out de cada saída foi conferido.
- [ ] O pixel clock utiliza buffer próprio e não percorre uma cadeia longa de cargas.
- [ ] As trilhas rápidas são mantidas curtas mesmo usando componentes PTH.
- [ ] Existe capacitor de desacoplamento de 100 nF próximo de cada CI.
- [ ] Existem capacitores de reserva próximos da SRAM, EPROM e entrada de alimentação.
- [ ] O plano ou malha de GND fornece caminho de retorno contínuo para os sinais rápidos.
- [ ] Foram evitadas derivações longas no pixel clock.
- [ ] O circuito foi conferido nas condições de tensão e temperatura previstas.
- [ ] O tempo combinado da VRAM e da ROM de fonte foi validado especialmente no modo texto.

---

## 21. Pontos de teste recomendados

- [ ] `PIXEL_CLOCK`.
- [ ] Saídas de bits importantes de `H_COUNTER`.
- [ ] Pulso de fim da linha horizontal.
- [ ] Saídas de bits importantes de `V_COUNTER`.
- [ ] `HSYNC`.
- [ ] `VSYNC`.
- [ ] `VIDEO_ACTIVE`.
- [ ] `HBLANK`.
- [ ] `VBLANK`.
- [ ] `FRAME`.
- [ ] `BUSY`.
- [ ] `WRITE_PENDING`.
- [ ] `READ_PENDING`.
- [ ] Seleção do MUX de endereço da VRAM.
- [ ] `/CE`, `/OE` e `/WE` da SRAM.
- [ ] Clock/load do shift register.
- [ ] Saída serial de pixel antes do estágio VGA.
- [ ] `/VIDEO_DETECT`.

---

## 22. Sequência recomendada de implementação

### Etapa 1 — Sincronismo sem memória

- [ ] Montar pixel clock, contadores, `HSYNC`, `VSYNC` e blanking.
- [ ] Forçar a região visível para uma cor constante.
- [ ] Confirmar que o monitor reconhece `640 × 480`.
- [ ] Medir frequências e larguras dos pulsos com osciloscópio ou analisador lógico.

### Etapa 2 — Gerador de pixels conhecido

- [ ] Gerar barras, xadrez ou padrão alternado diretamente dos contadores.
- [ ] Confirmar que o primeiro pixel começa em H=0 e o último termina em H=639.
- [ ] Confirmar que não existe imagem durante o blanking.

### Etapa 3 — Caminho gráfico sem CPU

- [ ] Preencher a VRAM com um padrão conhecido.
- [ ] Testar a leitura sequencial e o shift register.
- [ ] Validar bit 7 à esquerda.
- [ ] Validar escala 2 × 2.
- [ ] Validar escala 4 × 4.

### Etapa 4 — Caminho de texto

- [ ] Gravar uma fonte de teste na EPROM.
- [ ] Preencher a VRAM com códigos conhecidos.
- [ ] Mostrar 80 colunas sem corte ou repetição horizontal.
- [ ] Mostrar 30 linhas com duplicação apenas vertical.
- [ ] Confirmar caracteres nas quatro bordas da tela.
- [ ] Confirmar que a linha da fonte muda a cada duas linhas físicas.

### Etapa 5 — Interface da CPU

- [ ] Testar a seleção individual dos cinco registradores.
- [ ] Testar escrita e leitura dos latches X/Y/DATA.
- [ ] Testar uma única escrita na VRAM.
- [ ] Testar escrita sequencial e incremento automático.
- [ ] Testar leitura assíncrona com `$20`.
- [ ] Testar `BUSY` com CPU e GPU em clocks independentes.

### Etapa 6 — Comandos e limites

- [ ] Testar os três comandos de modo.
- [ ] Testar mostrar e esconder o cursor.
- [ ] Testar `VIDEO_CLEAR` nos três modos.
- [ ] Testar os limites e `CURSOR_END` nos três modos.
- [ ] Testar reposicionamento depois de `CURSOR_END`.

### Etapa 7 — Teste de estresse

- [ ] Executar a CPU em 16 MHz.
- [ ] Escrever continuamente enquanto a tela é varrida.
- [ ] Executar limpezas repetidas e trocas de modo.
- [ ] Verificar que não surgem pixels aleatórios por contenção.
- [ ] Verificar que `BUSY` nunca fica travado permanentemente.
- [ ] Verificar que `HSYNC` e `VSYNC` nunca param durante operações da CPU.
- [ ] Manter a placa funcionando por um período prolongado e conferir temperatura e estabilidade.

---

## 23. Testes funcionais de aceitação

### 23.1. Padrões de bits gráficos

- [ ] `$00` produz oito pixels apagados.
- [ ] `$FF` produz oito pixels acesos.
- [ ] `$80` acende somente o pixel mais à esquerda do grupo.
- [ ] `$01` acende somente o pixel mais à direita do grupo.
- [ ] `$AA` produz o padrão `10101010`.
- [ ] `$55` produz o padrão `01010101`.

### 23.2. Limites de escrita

- [ ] Texto: escrever em `(78,29)` avança para `(79,29)` sem ativar o fim.
- [ ] Texto: concluir a escrita em `(79,29)` mantém `(79,29)` e ativa `CURSOR_END`.
- [ ] 320 × 240: concluir em `(39,239)` mantém a posição e ativa `CURSOR_END`.
- [ ] 160 × 120: concluir em `(19,119)` mantém a posição e ativa `CURSOR_END`.
- [ ] Uma nova escrita no fim sobrescreve somente o último byte.
- [ ] Escrever em X ou Y limpa a flag de fim.

### 23.3. Endereços conhecidos

- [ ] Texto `(0,0)` acessa `$0000`.
- [ ] Texto `(79,29)` acessa `$095F`.
- [ ] Gráfico 320 `(0,0)` acessa `$0000`.
- [ ] Gráfico 320 `(39,239)` acessa `$257F`.
- [ ] Gráfico 160 `(19,119)` acessa `$095F`.

### 23.4. Limpeza

- [ ] A limpeza textual deixa todas as 2.400 células com `$20`.
- [ ] A limpeza 320 × 240 deixa todos os 9.600 bytes com `$00`.
- [ ] A limpeza 160 × 120 deixa todos os 2.400 bytes com `$00`.
- [ ] Nenhum byte depois do limite do modo é alterado.

### 23.5. Sincronismo e imagem

- [ ] A borda esquerda não contém lixo do final da linha anterior.
- [ ] A borda direita não invade o front porch.
- [ ] A primeira linha não contém lixo do quadro anterior.
- [ ] A última linha termina antes do blanking vertical.
- [ ] A imagem permanece estável durante escrita, leitura e limpeza.

---

## 24. Decisões que devem ficar registradas no esquema

- [ ] Família lógica usada no caminho de 25,175 MHz.
- [ ] Velocidade exata da SRAM `62256`.
- [ ] Velocidade exata da EPROM de fonte.
- [ ] Forma de sincronização entre CPU e GPU.
- [ ] Ciclos exatos da máquina de estados de VRAM.
- [ ] Instante de pré-carregamento do primeiro byte da linha.
- [ ] Forma visual do cursor: sublinhado ou bloco invertido.
- [ ] Estado inicial do cursor após reset.
- [ ] Estado inicial do modo de vídeo após reset.
- [ ] Comportamento escolhido para coordenadas inválidas fornecidas pela CPU.
- [ ] Cor monocromática usada na saída RGB.
- [ ] Modelo e pinagem do conector VGA.

---

## 25. Definição de GPU concluída

A primeira versão da GPU pode ser considerada concluída somente quando:

- [ ] O monitor recebe `640 × 480` estável continuamente.
- [ ] O texto mostra 80 × 30 caracteres usando fonte 8 × 8 e célula física 8 × 16.
- [ ] O gráfico 320 × 240 amplia cada pixel em 2 × 2.
- [ ] O gráfico 160 × 120 amplia cada pixel em 4 × 4.
- [ ] A CPU consegue escrever e ler a VRAM usando `$F200..$F204`.
- [ ] `BUSY` protege todas as operações assíncronas.
- [ ] A arbitragem não causa contenção nem perda de pixels.
- [ ] O incremento automático respeita os limites de cada modo.
- [ ] A última posição não retorna a zero e ativa `CURSOR_END`.
- [ ] `VIDEO_CLEAR` utiliza o tamanho e o valor corretos em cada modo.
- [ ] Reset e troca de modo deixam a placa em estado conhecido.
- [ ] Todos os testes de aceitação relevantes acima foram concluídos.
