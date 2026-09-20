# WALL-8 — Especificação da Placa de Vídeo

## 1. Objetivo

A placa de vídeo do WALL-8 é um periférico independente responsável por gerar continuamente a imagem enviada ao monitor.

A CPU não gera os pulsos de sincronismo e não envia cada pixel diretamente ao monitor. Ela apenas:

- seleciona o modo de vídeo;
- envia caracteres ou bytes gráficos;
- escolhe a posição de escrita e leitura;
- consulta o estado da placa;
- solicita comandos como limpar a tela e controlar o cursor.

A própria placa de vídeo mantém a imagem na VRAM, lê essa memória continuamente e gera a saída física de vídeo.

A arquitetura inicial possui três modos:

1. texto `80 × 30` com fonte armazenada em `8 × 8` e duplicação somente vertical;
2. gráfico `320 × 240` monocromático;
3. gráfico `160 × 120` monocromático.

Todos os modos são exibidos em uma saída física de `640 × 480`, proporção `4:3`.

---

## 2. Resumo dos modos

| Comando | Modo | Resolução lógica | Escala para 640 × 480 | Memória utilizada |
|---:|---|---:|---:|---:|
| `$11` | Texto | 80 × 30 caracteres com fonte 8 × 8 | 1× horizontal e 2× vertical; célula física 8 × 16 | 2.400 bytes |
| `$12` | Gráfico monocromático | 320 × 240 pixels | Cada pixel vira 2 × 2 pixels físicos | 9.600 bytes |
| `$13` | Gráfico monocromático | 160 × 120 pixels | Cada pixel vira 4 × 4 pixels físicos | 2.400 bytes |

A mesma VRAM é reutilizada pelos três modos. A interpretação do conteúdo muda conforme o modo ativo.

---

## 3. Blocos internos da placa

A placa pode ser dividida em três caminhos principais:

1. **interface da CPU**, formada pelos registradores visíveis em `$F200..$F204`;
2. **controlador de VRAM**, que decide quando a varredura ou uma operação da CPU utiliza a SRAM;
3. **gerador de vídeo**, que lê a VRAM e, conforme o modo, transforma o byte gráfico em pixels ou usa o código de caractere para consultar a ROM de fonte.

```text
                         Barramento do WALL-8
                                  │
                                  ▼
                   ┌──────────────────────────┐
                   │ Decodificador $F200..204 │
                   └──────────────┬───────────┘
                                  │
        ┌─────────────────────────▼─────────────────────────┐
        │              Registradores da CPU                │
        │ VIDEO_DATA | VIDEO_CMD | VIDEO_X | VIDEO_Y       │
        │                    + BUSY                        │
        └─────────────────────────┬─────────────────────────┘
                                  │ operação pendente
                                  ▼
                   ┌──────────────────────────┐
                   │ Controle e arbitragem   │
                   │ de acesso à VRAM        │
                   └───────────┬───────┬──────┘
                               │       │
                    endereço   │       │ endereço de
                    da CPU     │       │ varredura
                               ▼       ▼
                         ┌─────────────────┐
                         │ MUX de endereço │
                         └────────┬────────┘
                                  ▼
                            ┌──────────┐
                            │   VRAM   │
                            │  62256   │
                            └────┬─────┘
                                 │ byte lido pela varredura
                                 ▼
                   ┌──────────────────────────┐
                   │ Registro temporário do  │
                   │ byte lido da VRAM       │
                   └────────────┬─────────────┘
                                │
             ┌──────────────────┴──────────────────┐
             │                                     │
             ▼                                     ▼
    ┌──────────────────┐                  ┌──────────────────┐
    │ Caminho de texto │                  │ Caminho gráfico  │
    │ ROM + shift reg. │                  │ com shift reg.   │
    └─────────┬────────┘                  └─────────┬────────┘
              └──────────────────┬──────────────────┘
                                 ▼
                      ┌────────────────────────────┐
                      │ Formatação do modo ativo e │
                      │ sincronismo 640×480        │
                      └────────────────────────────┘
```

Os registradores mapeados em `$F200..$F204` formam a interface entre a CPU e a placa de vídeo. Eles armazenam a posição, o dado e o comando de cada operação até que o controlador de VRAM possa executá-la sem interromper a varredura.

Durante a varredura, cada byte lido da VRAM é retido pelo caminho do modo ativo. Nos modos gráficos, ele alimenta diretamente o shift register de pixels. No modo texto, ele é o código usado para endereçar a ROM de fonte; o byte retornado pela ROM é então carregado no shift register. Enquanto os bits são emitidos, a VRAM pode atender uma operação pendente da CPU.

Os principais blocos físicos são:

- interface com o barramento de dados da CPU;
- decodificador dos endereços `$F200` a `$F204`;
- latches `VIDEO_DATA`, `VIDEO_CMD`, `VIDEO_X` e `VIDEO_Y`;
- flip-flop de operação pendente e sinal `BUSY`;
- registrador de modo de vídeo;
- contador de endereço da varredura;
- formador do endereço solicitado pela CPU;
- multiplexador entre endereço de varredura e endereço da CPU;
- buffers tri-state do barramento de dados da VRAM;
- VRAM;
- ROM de caracteres;
- registrador temporário ou shift register de pixels;
- contadores horizontal e vertical;
- circuito de escala 2× e 4× para os modos gráficos;
- duplicação vertical das linhas da fonte no modo texto;
- lógica do cursor;
- máquina de estados de arbitragem;
- gerador de sincronismo do monitor.

## 4. Saída física de vídeo e sincronismo VGA

A placa utiliza uma saída física VGA de `640 × 480` pixels, proporção `4:3`, com atualização próxima de `60 Hz` em todos os modos de operação.

```text
Resolução enviada ao monitor: 640 × 480
Proporção:                     4:3
Atualização:                   aproximadamente 60 Hz
Pixel clock:                   25,175 MHz nominal
```

Os modos de texto, gráfico `320 × 240` e gráfico `160 × 120` não alteram o sinal reconhecido pelo monitor. Eles alteram somente a interpretação da VRAM e a forma como os dados são expandidos para preencher a área ativa.

```text
Modo texto 80 × 30:  fonte 8 × 8 forma 640 × 240 e cada linha é repetida 2× na vertical
Gráfico 320 × 240:   cada pixel lógico é exibido em um bloco 2 × 2
Gráfico 160 × 120:   cada pixel lógico é exibido em um bloco 4 × 4
```

Dessa forma, o monitor sempre recebe o mesmo formato de vídeo. A troca de modo não altera `HSYNC`, `VSYNC`, a frequência horizontal, a frequência vertical nem a quantidade total de clocks por quadro.

### 4.1. Por que a saída física permanece em 640 × 480

Uma resolução lógica de `320 × 240` poderia ser usada para organizar a VRAM e reduzir o trabalho da CPU, mas não é utilizada como temporização física enviada diretamente ao monitor.

Nem todo monitor VGA reconhece uma temporização direta de `320 × 240`. Dependendo do monitor, conversor ou placa de captura, uma temporização não padronizada pode causar:

- ausência de imagem;
- mensagem de sinal fora de faixa;
- centralização incorreta;
- escala irregular;
- proporção incorreta;
- sincronismo instável.

A temporização clássica de `640 × 480` é amplamente reconhecida por monitores VGA. Por isso, a placa gera sempre esse sinal e realiza a ampliação dos pixels internamente.

A resolução lógica e a resolução física são conceitos separados:

```text
Resolução lógica:
quantidade de pixels ou caracteres armazenados e manipulados pelo WALL-8.

Resolução física:
quantidade de posições de pixel transmitidas ao monitor em cada quadro.
```

No modo gráfico `320 × 240`, por exemplo, a VRAM armazena `320 × 240` pixels monocromáticos, mas o gerador de vídeo transmite `640 × 480` pixels físicos. Cada pixel lógico é repetido duas vezes na horizontal e duas vezes na vertical.

### 4.2. Temporização horizontal

Cada linha completa possui `800` clocks de pixel:

| Região horizontal | Quantidade de clocks | Faixa do contador |
|---|---:|---:|
| Área visível | 640 | 0 a 639 |
| Front porch | 16 | 640 a 655 |
| Pulso de `HSYNC` | 96 | 656 a 751 |
| Back porch | 48 | 752 a 799 |
| **Total** | **800** | **0 a 799** |

O contador horizontal, chamado neste documento de `H_COUNTER`, conta de `0` até `799`.

```text
H_COUNTER = 0..639    → pixels visíveis
H_COUNTER = 640..655  → front porch
H_COUNTER = 656..751  → HSYNC ativo
H_COUNTER = 752..799  → back porch
```

O pulso de sincronismo horizontal é ativo em nível baixo:

```text
HSYNC = 0 quando H_COUNTER está entre 656 e 751
HSYNC = 1 no restante da linha
```

Quando `H_COUNTER` chega a `799`:

```text
H_COUNTER volta para 0
V_COUNTER é incrementado
```

### 4.3. Temporização vertical

Cada quadro completo possui `525` linhas:

| Região vertical | Quantidade de linhas | Faixa do contador |
|---|---:|---:|
| Área visível | 480 | 0 a 479 |
| Front porch | 10 | 480 a 489 |
| Pulso de `VSYNC` | 2 | 490 a 491 |
| Back porch | 33 | 492 a 524 |
| **Total** | **525** | **0 a 524** |

O contador vertical, chamado neste documento de `V_COUNTER`, conta de `0` até `524`.

```text
V_COUNTER = 0..479    → linhas visíveis
V_COUNTER = 480..489  → front porch
V_COUNTER = 490..491  → VSYNC ativo
V_COUNTER = 492..524  → back porch
```

O pulso de sincronismo vertical também é ativo em nível baixo:

```text
VSYNC = 0 quando V_COUNTER está entre 490 e 491
VSYNC = 1 no restante do quadro
```

Quando `V_COUNTER` chega a `524`, ele volta para `0` e um novo quadro começa.

### 4.4. Frequências resultantes

Um quadro completo contém:

```text
800 clocks por linha × 525 linhas = 420.000 clocks por quadro
```

Com pixel clock nominal de `25,175 MHz`:

```text
Frequência horizontal ≈ 25.175.000 ÷ 800
                      ≈ 31,47 kHz

Frequência vertical   ≈ 25.175.000 ÷ 420.000
                      ≈ 59,94 Hz
```

Um oscilador de `25,2 MHz` também pode ser utilizado. Com os mesmos totais de `800 × 525`, ele produz aproximadamente `60 Hz` exatos e permanece muito próximo da temporização nominal.

Um clock de `25 MHz` pode funcionar em muitos monitores, mas produz aproximadamente `59,52 Hz`. Para aumentar a compatibilidade, a implementação deve preferir `25,175 MHz` ou `25,2 MHz`.

A placa utiliza um oscilador próprio para vídeo. O pixel clock não é derivado diretamente do clock de `16 MHz` da CPU, porque as duas frequências não possuem uma relação inteira simples e pertencem a funções independentes.

### 4.5. Região visível e blanking

Os sinais RGB somente representam pixels da imagem quando ambos os contadores estão dentro da região visível:

```text
VIDEO_ACTIVE = 1 quando:
H_COUNTER < 640
e
V_COUNTER < 480
```

Fora dessa região:

```text
VIDEO_ACTIVE = 0
saída de vídeo = preto
```

As regiões de front porch, sincronismo e back porch formam o blanking horizontal e vertical. Durante o blanking, a placa continua gerando `HSYNC` e `VSYNC`, mas não envia pixels visíveis.

O período vertical fora das linhas visíveis é informado pelo bit `VBLANK` de `VIDEO_STATUS`. O software pode esperar esse período antes de atualizar grandes regiões da VRAM para reduzir rasgos de imagem.

### 4.6. Escala do modo gráfico 320 × 240

No modo `320 × 240`, cada pixel lógico é repetido duas vezes em cada eixo:

```text
X_lógico = H_COUNTER ÷ 2
Y_lógico = V_COUNTER ÷ 2
```

Em hardware discreto, a divisão por dois é obtida ignorando o bit menos significativo dos contadores:

```text
X_lógico recebe os bits de H_COUNTER a partir de H1
Y_lógico recebe os bits de V_COUNTER a partir de V1
```

Exemplos horizontais:

```text
H = 0 e 1   → X lógico 0
H = 2 e 3   → X lógico 1
H = 4 e 5   → X lógico 2
```

Exemplos verticais:

```text
V = 0 e 1   → Y lógico 0
V = 2 e 3   → Y lógico 1
V = 4 e 5   → Y lógico 2
```

Cada byte gráfico contém oito pixels lógicos. Como cada pixel é repetido duas vezes horizontalmente, um byte alimenta `16` clocks de pixel físico:

```text
8 pixels lógicos × 2 = 16 pixels físicos
```

A sequência horizontal é:

```text
bit 0 → dois clocks
bit 1 → dois clocks
bit 2 → dois clocks
...
bit 7 → dois clocks
```

Depois dos 16 clocks, a GPU carrega o próximo byte da VRAM no registrador temporário de pixels.

Cada linha lógica também é exibida duas vezes. Portanto, as linhas físicas `0` e `1` utilizam a linha lógica `0`, as linhas físicas `2` e `3` utilizam a linha lógica `1`, e assim sucessivamente.

### 4.7. Escala do modo gráfico 160 × 120

No modo `160 × 120`, cada pixel lógico é repetido quatro vezes em cada eixo:

```text
X_lógico = H_COUNTER ÷ 4
Y_lógico = V_COUNTER ÷ 4
```

A divisão por quatro é obtida ignorando os dois bits menos significativos dos contadores:

```text
X_lógico recebe os bits de H_COUNTER a partir de H2
Y_lógico recebe os bits de V_COUNTER a partir de V2
```

Exemplos horizontais:

```text
H = 0..3    → X lógico 0
H = 4..7    → X lógico 1
H = 8..11   → X lógico 2
```

Cada byte gráfico contém oito pixels lógicos e alimenta `32` clocks físicos:

```text
8 pixels lógicos × 4 = 32 pixels físicos
```

Cada linha lógica é repetida quatro vezes:

```text
V = 0..3    → linha lógica 0
V = 4..7    → linha lógica 1
V = 8..11   → linha lógica 2
```

### 4.8. Escala do modo texto 80 × 30

O modo texto possui `80` colunas e `30` linhas. Cada caractere continua armazenado na ROM como uma matriz de `8 × 8` pixels:

```text
80 × 8 = 640 pixels horizontais
30 × 8 = 240 linhas lógicas
```

Não existe duplicação horizontal no modo texto. Os oito bits de cada linha da fonte ocupam diretamente oito clocks do pixel clock VGA. Para alcançar as `480` linhas físicas, cada linha da fonte é exibida em duas linhas consecutivas do monitor:

```text
linha 0 da fonte → linhas físicas 0 e 1 da célula
linha 1 da fonte → linhas físicas 2 e 3 da célula
...
linha 7 da fonte → linhas físicas 14 e 15 da célula
```

Assim, o caractere permanece armazenado como `8 × 8`, mas ocupa fisicamente uma célula de:

```text
8 pixels de largura × 16 pixels de altura
```

A célula textual visível é obtida por:

```text
coluna de texto = H_COUNTER ÷ 8
linha de texto  = V_COUNTER ÷ 16
```

A posição interna na fonte é obtida por:

```text
coluna da fonte = H_COUNTER AND 7
linha da fonte  = (V_COUNTER ÷ 2) AND 7
```

Em termos dos bits dos contadores:

```text
H0..H2 → posição horizontal 0..7 dentro do caractere
H3..H9 → coluna textual 0..79

V0     → seleciona a primeira ou a segunda repetição da mesma linha
V1..V3 → linha 0..7 da ROM de fonte
V4..V8 → linha textual 0..29
```

O código do caractere é lido da VRAM. Em seguida, a ROM fornece os oito pixels da linha correspondente. Esse byte entra no shift register e seus bits são enviados uma única vez na horizontal, um por clock físico. Na linha física seguinte, a mesma linha da fonte é lida novamente.

### 4.9. Contadores e sinais principais

A geração do sinal utiliza, no mínimo:

- contador horizontal de 10 bits, capaz de representar `0..799`;
- contador vertical de 10 bits, capaz de representar `0..524`;
- comparadores ou lógica de decodificação para os limites de área visível;
- lógica para gerar `HSYNC` ativo entre `656..751`;
- lógica para gerar `VSYNC` ativo entre `490..491`;
- sinal `VIDEO_ACTIVE`;
- formatação e seleção de escala conforme o modo ativo;
- contador ou seletor do bit atual do registrador de pixels.

Fluxo geral:

```text
Pixel clock
    │
    ▼
H_COUNTER 0..799
    │ fim da linha
    ▼
V_COUNTER 0..524
    │
    ├── gera HSYNC
    ├── gera VSYNC
    ├── gera VIDEO_ACTIVE
    ├── define a coordenada lógica
    └── controla a leitura e repetição dos pixels
```

A saída monocromática inicial utiliza:

```text
bit 0 = pixel apagado
bit 1 = pixel aceso
```

Na implementação inicial:

```text
0 = preto
1 = branco
```

A cor elétrica do pixel aceso pode ser alterada futuramente sem modificar a organização da VRAM nem as temporizações de sincronismo.

## 5. Interface com o WALL-8

A placa é um periférico mapeado em memória dentro da página de vídeo:

```text
$F200 até $F2FF
```

A implementação inicial utiliza somente os cinco primeiros endereços:

| Endereço | Nome | Acesso | Função |
|---:|---|---|---|
| `$F200` | `VIDEO_DATA` | leitura e escrita | Na escrita, retém o byte enviado pela CPU e dispara uma gravação pendente na VRAM. Na leitura, retorna o resultado da última leitura de VRAM concluída |
| `$F201` | `VIDEO_CMD` | escrita | Executa comandos, seleciona o modo e solicita operações internas, como limpar a tela ou ler uma posição da VRAM |
| `$F202` | `VIDEO_X` | leitura e escrita | Latch da posição horizontal solicitada pela CPU |
| `$F203` | `VIDEO_Y` | leitura e escrita | Latch da posição vertical solicitada pela CPU |
| `$F204` | `VIDEO_STATUS` | leitura | Informa `BUSY`, blanking, referência de quadro e a condição `CURSOR_END` |

Definições no Assembly:

```asm
VIDEO_DATA   = $F200
VIDEO_CMD    = $F201
VIDEO_X      = $F202
VIDEO_Y      = $F203
VIDEO_STATUS = $F204
```

A CPU acessa a VRAM por meio dos registradores da interface. O controlador combina `VIDEO_X` e `VIDEO_Y`, forma o endereço interno correspondente e executa a leitura ou escrita no próximo intervalo disponível entre as leituras da varredura.

A regra central da interface é:

```text
BUSY = 0 → os registradores da interface estão livres para uma nova operação
BUSY = 1 → X, Y, DATA e a operação atual estão reservados pelo controlador
```

Enquanto `BUSY = 1`, o software pode continuar lendo `VIDEO_STATUS`, mas não deve alterar `VIDEO_X`, `VIDEO_Y`, `VIDEO_DATA` nem iniciar outro comando que use a VRAM. Em qualquer modo, `VIDEO_STATUS.CURSOR_END` permanece retido quando o cursor automático de escrita alcança a última posição válida da área utilizada.

## 6. Detecção da placa

A presença física da placa é informada pelo registrador geral de status do WALL-8:

```text
$F300 bit 5 = /VIDEO_DETECT
```

O sinal é ativo em nível baixo:

```text
bit 5 = 0 → placa de vídeo presente
bit 5 = 1 → placa de vídeo ausente
```

Exemplo:

```asm
LDA $F300
TEST A, #$20
JNZ SEM_VIDEO
```

---

# Parte I — Registradores

## 7. `VIDEO_DATA` — `$F200`

`VIDEO_DATA` é a porta de transferência de dados entre a CPU e a VRAM. Na escrita, o valor é mantido em um latch até que o controlador realize a gravação física na SRAM.

Na escrita, `$F200` funciona como um latch de 8 bits. O byte permanece guardado enquanto a máquina de estados espera um intervalo livre da VRAM.

### Sequência de uma escrita

Supondo:

```asm
STI VIDEO_X, #$05
STI VIDEO_Y, #$20
STI VIDEO_DATA, #$A5
```

A sequência interna é:

```text
1. VIDEO_X recebe $05.
2. VIDEO_Y recebe $20.
3. VIDEO_DATA recebe $A5.
4. A escrita em VIDEO_DATA ativa WRITE_PENDING.
5. VIDEO_STATUS.BUSY passa para 1.
6. X, Y e DATA ficam reservados para essa operação.
7. A GPU termina a leitura necessária para a varredura atual.
8. O multiplexador seleciona o endereço formado por X e Y.
9. VIDEO_DATA dirige o barramento da VRAM.
10. O controlador gera o pulso de /WE.
11. O endereço volta para a varredura.
12. X e Y são incrementados conforme o modo.
13. WRITE_PENDING é limpo.
14. BUSY volta para 0.
```

O endereço da SRAM é formado internamente a partir de `VIDEO_X` e `VIDEO_Y`, conforme o modo ativo:

```text
Texto 80×30:      endereço = VIDEO_Y × 80 + VIDEO_X
Gráfico 320×240:  endereço = VIDEO_Y × 40 + VIDEO_X
Gráfico 160×120:  endereço = VIDEO_Y × 20 + VIDEO_X
```

O resultado dessa conversão alimenta as entradas de endereço da SRAM `62256`.

### Gatilho da operação

Escrever somente `VIDEO_X` ou `VIDEO_Y` não acessa a VRAM. Essas escritas apenas preparam a posição.

A operação é disparada quando a CPU escreve em:

```asm
STA VIDEO_DATA
```

Nesse instante, o byte fica retido e `BUSY` é ativado.

### Significado no modo texto

Uma escrita representa um código de caractere:

```asm
STI VIDEO_DATA, #$41    ; letra A
```

A gravação na VRAM textual acontece no próximo slot livre. Depois da conclusão, a posição é incrementada automaticamente.

### Significado nos modos gráficos

Uma escrita representa oito pixels horizontais:

```asm
STI VIDEO_DATA, #$81
```

O byte `$81` corresponde a:

```text
10000001
```

Assim, o primeiro e o oitavo pixels do grupo ficam acesos.

### Ordem dos bits

A ordem oficial é:

```text
bit 0 = pixel mais à esquerda
bit 1 = segundo pixel
bit 2 = terceiro pixel
bit 3 = quarto pixel
bit 4 = quinto pixel
bit 5 = sexto pixel
bit 6 = sétimo pixel
bit 7 = pixel mais à direita
```

| Valor | Pixels |
|---:|---|
| `$00` | todos apagados |
| `$01` | somente o primeiro aceso |
| `$80` | somente o último aceso |
| `$FF` | todos acesos |
| `$AA` | padrão alternado `10101010` |
| `$55` | padrão alternado `01010101` |

### Leitura de VRAM

Uma leitura física da VRAM não deve depender de o dado ficar pronto dentro do mesmo ciclo de `LDA $F200`, pois a SRAM pode estar ocupada pela varredura naquele instante.

A leitura é feita em duas etapas:

```asm
; X e Y já foram configurados
STI VIDEO_CMD, #$20    ; solicita leitura da VRAM
CALL VIDEO_WAIT        ; espera a GPU concluir
LDA VIDEO_DATA         ; recebe o resultado
```

O comando `$20` ativa `BUSY`. No próximo slot livre, a GPU lê a posição indicada e guarda o resultado em um latch interno de leitura. Quando o byte estiver pronto, `BUSY` volta a zero e `LDA VIDEO_DATA` retorna esse valor.

Na implementação física, a placa pode utilizar um latch para dados de escrita e outro para o resultado de leitura. Ambos são acessados pela CPU pelo endereço lógico `VIDEO_DATA` (`$F200`).

A leitura não incrementa automaticamente `VIDEO_X` ou `VIDEO_Y`.

## 8. `VIDEO_CMD` — `$F201`

`VIDEO_CMD` recebe comandos completos. Ele não é um registrador de configuração por bits; cada valor escrito representa uma ação.

Cada valor escrito em `VIDEO_CMD` representa uma operação definida pelo protocolo da placa.

### Tabela inicial de comandos

| Valor | Nome | Função |
|---:|---|---|
| `$00` | `VIDEO_CLEAR` | Limpa a área de memória utilizada pelo modo atual |
| `$04` | `CURSOR_HIDE` | Esconde o cursor do modo texto |
| `$05` | `CURSOR_SHOW` | Mostra o cursor do modo texto |
| `$11` | `MODE_TEXT_80X30` | Seleciona texto 80 × 30 com fonte armazenada em 8 × 8 e duplicação 2× somente na vertical |
| `$12` | `MODE_GFX_320X240` | Seleciona gráfico 320 × 240 monocromático e escala 2× |
| `$13` | `MODE_GFX_160X120` | Seleciona gráfico 160 × 120 monocromático e escala 4× |
| `$20` | `VRAM_READ` | Solicita a leitura da posição indicada por `VIDEO_X` e `VIDEO_Y` |

Os demais valores permanecem reservados para expansões futuras.

Antes de enviar um comando que use a VRAM, o software deve garantir que `BUSY = 0`.

### Selecionar texto

```asm
CALL VIDEO_WAIT
STI VIDEO_CMD, #$11
```

### Selecionar gráfico 320 × 240

```asm
CALL VIDEO_WAIT
STI VIDEO_CMD, #$12
```

### Selecionar gráfico 160 × 120

```asm
CALL VIDEO_WAIT
STI VIDEO_CMD, #$13
```

### Limpar a tela

```asm
CALL VIDEO_WAIT
STI VIDEO_CMD, #$00
CALL VIDEO_WAIT
```

O comando de limpeza apaga somente a quantidade de VRAM utilizada pelo modo atual:

```text
Texto 80×30:      2.400 bytes preenchidos com $20
Gráfico 320×240:  9.600 bytes preenchidos com $00
Gráfico 160×120:  2.400 bytes preenchidos com $00
```

No modo texto, a tela é preenchida com espaço (`$20`). Nos modos gráficos, a área é preenchida com zero.

Durante a limpeza, um contador interno percorre a faixa correspondente e escreve um byte por vez nos slots livres da VRAM. A varredura continua tendo prioridade para que a imagem e os sincronismos não parem.

Enquanto a limpeza estiver ativa:

```text
VIDEO_STATUS.BUSY = 1
```

Ao final:

```text
VIDEO_X = 0
VIDEO_Y = 0
VIDEO_STATUS.CURSOR_END = 0
VIDEO_STATUS.BUSY = 0
```

### Solicitar uma leitura

```asm
CALL VIDEO_WAIT
STI VIDEO_X, #$05
STI VIDEO_Y, #$20
STI VIDEO_CMD, #$20
CALL VIDEO_WAIT
LDA VIDEO_DATA
```

O comando `$20` não incrementa a posição.

## 9. `VIDEO_X` — `$F202`

`VIDEO_X` é um latch de 8 bits que retém a posição horizontal solicitada pela CPU.

Ele não acessa a VRAM sozinho. A posição só é usada quando a CPU grava em `VIDEO_DATA` ou envia um comando que utiliza a memória.

O software deve alterar `VIDEO_X` somente quando:

```text
VIDEO_STATUS.BUSY = 0
```

Enquanto `BUSY = 1`, o controlador está usando o valor atual para concluir uma operação.

### Texto 80 × 30

```text
VIDEO_X = coluna de caractere
Faixa válida: 0 até 79
```

### Gráfico 320 × 240

```text
VIDEO_X = coluna de byte gráfico
Faixa válida: 0 até 39
```

Cada posição representa oito pixels lógicos:

```text
VIDEO_X 0  → pixels 0 até 7
VIDEO_X 1  → pixels 8 até 15
...
VIDEO_X 39 → pixels 312 até 319
```

### Gráfico 160 × 120

```text
VIDEO_X = coluna de byte gráfico
Faixa válida: 0 até 19
```

```text
VIDEO_X 0  → pixels 0 até 7
VIDEO_X 1  → pixels 8 até 15
...
VIDEO_X 19 → pixels 152 até 159
```

Depois de uma **escrita concluída** em `VIDEO_DATA`, a GPU incrementa `VIDEO_X` automaticamente. O incremento ocorre no final da operação, imediatamente antes de `BUSY` voltar a zero.

Uma escrita explícita da CPU em `VIDEO_X` limpa automaticamente a flag `CURSOR_END`. Essa escrita reposiciona o cursor de acesso e indica que o software iniciou uma nova sequência ou tratou a condição de fim da área.

## 10. `VIDEO_Y` — `$F203`

`VIDEO_Y` é um latch de 8 bits que retém a posição vertical solicitada pela CPU.

Assim como `VIDEO_X`, ele deve ser alterado somente com `BUSY = 0`.

Qualquer escrita explícita da CPU em `VIDEO_Y` limpa automaticamente a flag `CURSOR_END`.

### Texto 80 × 30

```text
VIDEO_Y = linha de caractere
Faixa válida: 0 até 29
```

### Gráfico 320 × 240

```text
VIDEO_Y = linha de pixel lógico
Faixa válida: 0 até 239
```

### Gráfico 160 × 120

```text
VIDEO_Y = linha de pixel lógico
Faixa válida: 0 até 119
```

Quando uma escrita em `VIDEO_DATA` conclui e `VIDEO_X` alcança o limite da linha, a GPU volta `VIDEO_X` para zero e incrementa `VIDEO_Y`, desde que ainda exista uma linha seguinte no modo ativo.

Ao concluir uma escrita na última posição válida, o cursor automático não retorna ao início. `VIDEO_X` e `VIDEO_Y` permanecem travados na última posição do modo e a flag `CURSOR_END` é ativada.

| Modo | Última posição válida |
|---|---:|
| Texto 80 × 30 | `X = 79`, `Y = 29` |
| Gráfico 320 × 240 | `X = 39`, `Y = 239` |
| Gráfico 160 × 120 | `X = 19`, `Y = 119` |

A GPU não apaga a tela, não executa scroll e não altera outras posições da VRAM. A CPU decide como continuar e reposiciona `VIDEO_X` ou `VIDEO_Y`, o que também limpa automaticamente `CURSOR_END`.

## 11. `VIDEO_STATUS` — `$F204`

`VIDEO_STATUS` informa o estado da interface e da varredura.

### Mapa inicial

| Bit | Nome | Significado |
|---:|---|---|
| 0 | `BUSY` | Os registradores da interface estão reservados por uma escrita, leitura ou comando em andamento |
| 1 | `VBLANK` | A saída está no intervalo vertical de apagamento |
| 2 | `HBLANK` | A saída está no intervalo horizontal de apagamento |
| 3 | `FRAME` | Alterna a cada quadro completo |
| 4 | `CURSOR_END` | Indica que uma escrita foi concluída na última posição válida do modo ativo e que o cursor automático permaneceu travado nessa posição |
| 5 | reservado | Deve retornar zero |
| 6 | reservado | Deve retornar zero |
| 7 | reservado | Deve retornar zero |


### Flag `CURSOR_END`

`CURSOR_END` é uma flag retida que informa que o cursor automático de escrita alcançou a última posição válida do modo ativo.

O nome “cursor” se refere aos registradores `VIDEO_X` e `VIDEO_Y`, que indicam a posição da próxima operação de escrita. No modo texto, eles selecionam uma célula de caractere. Nos modos gráficos, selecionam um byte horizontal do framebuffer e uma linha de pixels.

A condição de ativação depende do modo:

| Modo | Condição que ativa `CURSOR_END` |
|---|---|
| Texto 80 × 30 | Escrita concluída em `X = 79`, `Y = 29` |
| Gráfico 320 × 240 | Escrita concluída em `X = 39`, `Y = 239` |
| Gráfico 160 × 120 | Escrita concluída em `X = 19`, `Y = 119` |

Depois da gravação final:

```text
VIDEO_X permanece no último X válido
VIDEO_Y permanece no último Y válido
CURSOR_END = 1
BUSY = 0
```

A interface não retorna automaticamente para `(0,0)`. Caso o software continue escrevendo em `VIDEO_DATA` sem reposicionar o cursor, somente a última posição do modo será sobrescrita repetidamente.

A flag é limpa automaticamente sempre que a CPU escreve em qualquer registrador de posição:

```text
escrita em VIDEO_X → CURSOR_END = 0
escrita em VIDEO_Y → CURSOR_END = 0
```

O simples reposicionamento confirma que o software iniciou uma nova sequência. Não é necessário reservar um comando separado para limpar a flag.

A troca de modo e a conclusão do comando `VIDEO_CLEAR` também reposicionam o cursor em `(0,0)` e limpam `CURSOR_END`.

A GPU não interpreta o significado do conteúdo. No modo texto, a BIOS pode usar `CURSOR_END` para executar scroll, redesenhar o histórico ou limpar a tela. Nos modos gráficos, um programa pode usá-la para detectar que terminou de preencher todo o framebuffer.

Exemplo de consulta:

```asm
LDA VIDEO_STATUS
TEST A, #$10
JNZ CURSOR_REACHED_END
```

No modo texto, após tratar o fim da área, a BIOS pode reposicionar a escrita:

```asm
STI VIDEO_X, #$00      ; limpa CURSOR_END
STI VIDEO_Y, #$1D      ; linha 29
```

No modo gráfico, um preenchimento completo pode começar em `(0,0)` e terminar quando `CURSOR_END` for ativada. A CPU deve verificar a flag somente depois de `BUSY` retornar a zero, pois a posição e a flag são atualizadas quando a gravação física na VRAM termina.

### O que `BUSY` realmente significa

`BUSY` não tenta informar os poucos nanossegundos exatos em que a SRAM está fisicamente livre. A CPU seria lenta demais para observar e reagir diretamente a essa janela.

O significado correto é:

```text
BUSY = 0
A interface pode aceitar uma nova operação da CPU.

BUSY = 1
VIDEO_X, VIDEO_Y, VIDEO_DATA e a operação atual estão reservados.
A GPU ainda precisa executar ou finalizar a transferência na VRAM.
```

`BUSY` sobe quando:

- a CPU escreve em `VIDEO_DATA`;
- a CPU solicita uma leitura com o comando `$20`;
- a CPU inicia um comando demorado, como limpar a tela.

`BUSY` desce quando:

- a escrita foi realmente gravada na VRAM;
- a leitura foi concluída e o resultado foi guardado;
- o comando interno terminou.

### Polling

A CPU consulta `BUSY` por polling:

```asm
VIDEO_WAIT:
    LDA VIDEO_STATUS
    TEST A, #$01
    JNZ VIDEO_WAIT
    RET
```

A leitura repetida de `VIDEO_STATUS` é segura. Enquanto o laço de polling estiver ativo, a CPU permanece ocupada aguardando a conclusão da operação. Em transferências simples, o intervalo de espera tende a ser curto.

A rotina deve ser usada antes de:

- alterar `VIDEO_X` ou `VIDEO_Y`;
- escrever outro byte em `VIDEO_DATA`;
- iniciar um comando que use a VRAM;
- ler o resultado solicitado por `$20`.

### Escrita preservando o acumulador

Como a consulta do status altera `A`, uma rotina que recebe o byte em `A` deve preservá-lo:

```asm
VIDEO_TEMP = $02AF

VIDEO_WRITE_A:
    STA VIDEO_TEMP

VIDEO_WRITE_WAIT:
    LDA VIDEO_STATUS
    TEST A, #$01
    JNZ VIDEO_WRITE_WAIT

    LDA VIDEO_TEMP
    STA VIDEO_DATA
    RET
```

A rotina retorna assim que o byte foi aceito pelo latch e `BUSY` foi ativado. A próxima chamada espera a operação anterior terminar.

### `VBLANK`

`VBLANK` fica ativo quando a placa terminou a área visível de um quadro e está no intervalo antes do próximo quadro.

A CPU pode usar esse período para sincronizar atualizações e reduzir rasgos visuais:

```asm
WAIT_VBLANK:
    LDA VIDEO_STATUS
    TEST A, #$02
    JZ WAIT_VBLANK
    RET
```

### `FRAME`

O bit `FRAME` alterna entre zero e um a cada quadro. Ele fornece uma referência simples de atualização para jogos e animações.

# Parte II — Modo texto

## 12. Modo texto 80 × 30

O modo texto é selecionado por:

```asm
STI VIDEO_CMD, #$11
```

Ao selecionar o modo texto, o controlador inicializa a posição e a flag de limite:

```text
VIDEO_X = 0
VIDEO_Y = 0
CURSOR_END = 0
```

Essa inicialização evita que uma condição de fim da área do uso anterior permaneça ativa após uma troca de modo.

Características:

```text
Colunas:            80
Linhas:             30
Caracteres na tela: 2.400
Fonte armazenada:   8 × 8 pixels
Escala:             1× horizontal e 2× vertical
Área lógica gerada: 640 × 240 pixels
Saída física:       640 × 480 pixels
```

Cada célula utiliza os `8 × 8` pixels armazenados na fonte sem repetição horizontal. Cada linha da fonte é repetida em duas linhas físicas consecutivas.

Assim, cada caractere ocupa fisicamente:

```text
8 × 16 pixels
```

Cálculo:

```text
80 × 8  = 640 pixels horizontais
30 × 16 = 480 pixels verticais
```

---

## 13. Organização da VRAM no modo texto

Cada posição utiliza um byte contendo o código do caractere.

```text
1 caractere = 1 byte
80 × 30 = 2.400 bytes
```

Faixa utilizada:

```text
VRAM $0000 até $095F
```

O endereço de uma célula é:

```text
endereço = VIDEO_Y × 80 + VIDEO_X
```

Exemplo:

```text
coluna = 5
linha  = 3

endereço = 3 × 80 + 5
endereço = 245 decimal
endereço = $00F5
```

Organização:

```text
VRAM $0000..$004F → linha 0
VRAM $0050..$009F → linha 1
VRAM $00A0..$00EF → linha 2
...
```

---

## 14. ROM de caracteres

A placa possui uma ROM separada com os desenhos dos caracteres.

Cada caractere usa oito bytes:

```text
8 linhas × 1 byte por linha = 8 bytes
```

Cada bit representa um pixel da linha. Na ordem visual da esquerda para a
direita, a ROM fornece `D0, D1, ... D7`.

Exemplo da letra `A`:

```text
00111100
01100110
01100110
01111110
01100110
01100110
01100110
00000000
```

Em hexadecimal:

```text
$3C
$66
$66
$7E
$66
$66
$66
$00
```

Uma fonte com 256 caracteres ocupa:

```text
256 × 8 = 2.048 bytes
```

Uma EPROM `27C512` possui 65.536 bytes. Com `A11..A13` em GND e `A14..A15`
selecionáveis, o circuito atual acessa quatro bancos de 256 caracteres. Na
primeira versão, somente o banco `A15:A14=00` precisa ser utilizado.

### Endereço da ROM de fonte

```text
endereço_fonte = (banco << 14) | (linha_interna << 8) | código_do_caractere
```

Onde:

```text
código_do_caractere = byte lido da VRAM
linha_interna       = 0 até 7
banco               = A15:A14, de 0 até 3

A0..A7   = código_do_caractere
A8..A10  = linha_interna
A11..A13 = 000, ligados ao GND
A14..A15 = banco
```

---

## 15. Geração de um caractere

Para cada posição visível, a placa realiza:

1. calcula a coluna e a linha de texto;
2. lê o código do caractere na VRAM;
3. calcula a linha interna da fonte;
4. lê um byte na ROM de caracteres;
5. seleciona cada bit desse byte;
6. envia os oito pixels sem repetição horizontal e repete a mesma linha da fonte na próxima linha física;
7. envia o resultado à saída física.

Para um pixel físico `(PX, PY)`:

```text
coluna_texto = PX >> 3
linha_texto  = PY >> 4

pixel_fonte_x = PX AND 7
pixel_fonte_y = (PY >> 1) AND 7
```

O deslocamento horizontal de três bits divide por oito. O deslocamento vertical de quatro bits divide por 16, pois cada linha da fonte é repetida duas vezes.

---

## 16. Escrita sequencial de caracteres

Ao escrever um caractere imprimível em `VIDEO_DATA`:

1. o caractere é retido no latch `VIDEO_DATA`;
2. `BUSY` passa para um;
3. a GPU grava o código na posição indicada por `VIDEO_X` e `VIDEO_Y` no próximo slot livre;
4. `VIDEO_X` é incrementado;
5. ao passar da coluna 79, `VIDEO_X` volta a zero e `VIDEO_Y` é incrementado;
6. se a escrita ocorreu em `X = 79` e `Y = 29`, a posição permanece em `79,29` e `CURSOR_END` passa para um;
7. `BUSY` volta para zero.

Uma linha textual completa exige 80 escritas, uma para cada código de caractere. A CPU não escreve os oito pixels da fonte nem a repetição vertical; essas duas tarefas pertencem ao circuito de vídeo.

A escrita oficial deve respeitar `BUSY`. Uma rotina genérica é:

```asm
VIDEO_TEMP = $02AF

VIDEO_WRITE_A:
    STA VIDEO_TEMP
VIDEO_WRITE_A_WAIT:
    LDA VIDEO_STATUS
    TEST A, #$01
    JNZ VIDEO_WRITE_A_WAIT
    LDA VIDEO_TEMP
    STA VIDEO_DATA
    RET
```

Uso:

```asm
LDA #$57             ; W
CALL VIDEO_WRITE_A
LDA #$41             ; A
CALL VIDEO_WRITE_A
LDA #$4C             ; L
CALL VIDEO_WRITE_A
LDA #$4C             ; L
CALL VIDEO_WRITE_A
LDA #$2D             ; -
CALL VIDEO_WRITE_A
LDA #$38             ; 8
CALL VIDEO_WRITE_A
```

O avanço automático no modo texto segue exatamente esta lógica:

```text
Se X < 79:
    X = X + 1

Se X = 79 e Y < 29:
    X = 0
    Y = Y + 1

Se X = 79 e Y = 29:
    X permanece 79
    Y permanece 29
    CURSOR_END = 1
```

A GPU limita apenas a posição automática. O scroll continua sendo responsabilidade da BIOS, que pode usar o histórico armazenado na RAM principal e redesenhar a janela visível.

O teste de `BUSY` garante que cada transferência seja concluída antes da próxima, independentemente da frequência da CPU, do tempo de acesso da SRAM e da implementação do controlador de vídeo.

Na BIOS, a espera pode ser concentrada em `VIDEO_RAW_CHAR`, de modo que as rotinas de terminal utilizem uma única interface de escrita.

## 17. Controles de terminal

No modo texto, alguns códigos possuem função de controle.

| Código | Nome | Ação |
|---:|---|---|
| `$08` | Backspace | Volta uma célula, apaga com espaço e reposiciona o cursor |
| `$0A` | Line Feed | Inicia uma nova linha |
| `$0D` | Carriage Return/Newline | Inicia uma nova linha |
| `$20..$FF` | Caractere | Grava o código na VRAM e avança o cursor |

No protocolo atual, `$0A` e `$0D` são tratados como comandos independentes de nova linha.

Consequentemente, enviar a sequência `$0D`, `$0A` gera duas mudanças de linha. O software deve enviar somente um dos dois quando desejar uma única nova linha.

---

## 18. Cursor

O cursor pertence somente ao modo texto.

Comandos:

```asm
STI VIDEO_CMD, #$04    ; esconde
STI VIDEO_CMD, #$05    ; mostra
```

A posição do cursor é determinada por:

```text
VIDEO_X = coluna
VIDEO_Y = linha
```

O cursor pode ser exibido como um bloco invertido ou como um sublinhado dentro da célula atual.

O piscar pode ser gerado por um divisor de frequência interno da placa, sem participação da CPU.

Nos modos gráficos, os comandos de cursor não possuem efeito.

---

## Cursor automático nos modos gráficos

Nos modos gráficos, `VIDEO_X` representa uma coluna de byte, e não um pixel individual. Cada escrita em `VIDEO_DATA` grava oito pixels horizontais e, depois da conclusão física da escrita, avança o cursor automaticamente.

### Gráfico 320 × 240

```text
VIDEO_X: 0 até 39
VIDEO_Y: 0 até 239
```

O avanço segue:

```text
Se X < 39:
    X = X + 1

Se X = 39 e Y < 239:
    X = 0
    Y = Y + 1

Se X = 39 e Y = 239:
    X permanece 39
    Y permanece 239
    CURSOR_END = 1
```

### Gráfico 160 × 120

```text
VIDEO_X: 0 até 19
VIDEO_Y: 0 até 119
```

O avanço segue:

```text
Se X < 19:
    X = X + 1

Se X = 19 e Y < 119:
    X = 0
    Y = Y + 1

Se X = 19 e Y = 119:
    X permanece 19
    Y permanece 119
    CURSOR_END = 1
```

Esse comportamento permite que a CPU envie um framebuffer inteiro em sequência sem calcular manualmente cada endereço. Também impede que uma escrita além do fim volte silenciosamente para o início e sobrescreva a parte superior da imagem.

Para iniciar outra transferência, a CPU escreve um novo valor em `VIDEO_X` ou `VIDEO_Y`. Qualquer uma dessas escritas limpa `CURSOR_END`.

---

# Parte III — Gráfico 320 × 240

## 19. Seleção do modo

```asm
STI VIDEO_CMD, #$12
```

Características:

```text
Resolução lógica: 320 × 240
Profundidade:     1 bit por pixel
Escala física:    2 × 2
Saída:            640 × 480
Bytes por linha:  40
VRAM utilizada:   9.600 bytes
```

Faixa utilizada:

```text
VRAM $0000 até $257F
```

---

## 20. Organização da VRAM em 320 × 240

Cada byte representa oito pixels horizontais.

```text
320 ÷ 8 = 40 bytes por linha
40 × 240 = 9.600 bytes
```

O endereço é:

```text
endereço = VIDEO_Y × 40 + VIDEO_X
```

Onde:

```text
VIDEO_X = 0 até 39
VIDEO_Y = 0 até 239
```

Organização:

```text
VRAM $0000..$0027 → linha lógica 0
VRAM $0028..$004F → linha lógica 1
VRAM $0050..$0077 → linha lógica 2
...
```

---

## 21. Escala 2×

Cada pixel lógico é mostrado como um bloco de quatro pixels físicos:

```text
1 pixel lógico → 2 pixels horizontais × 2 linhas físicas
```

Conversão:

```text
X_lógico = X_físico >> 1
Y_lógico = Y_físico >> 1
```

No hardware, isso não exige divisores. Basta ignorar o bit menos significativo dos contadores horizontal e vertical.

---

## 22. Escrita de bytes gráficos

Antes de alterar X e Y, a interface deve estar livre:

```asm
CALL VIDEO_WAIT
STI VIDEO_X, #$00
STI VIDEO_Y, #$00

LDA #$FF
CALL VIDEO_WRITE_A
```

Isso acende os oito primeiros pixels lógicos da linha zero.

Fisicamente, a faixa terá:

```text
8 × 2 = 16 pixels de largura
2 pixels de altura
```

Outro exemplo, posicionando diretamente o grupo de pixels 8 até 15:

```asm
CALL VIDEO_WAIT
STI VIDEO_X, #$01
STI VIDEO_Y, #$00

LDA #$81
CALL VIDEO_WRITE_A
```

`VIDEO_WRITE_A` espera qualquer operação anterior, guarda o novo byte em `VIDEO_DATA` e deixa a GPU concluir a escrita no próximo slot livre.

---

## 23. Incremento automático em 320 × 240

Depois que a escrita pendente foi realmente concluída na VRAM:

```text
VIDEO_X = VIDEO_X + 1
```

Ao passar de 39:

```text
VIDEO_X = 0
VIDEO_Y = VIDEO_Y + 1
```

Ao passar de 239:

```text
VIDEO_Y = 0
```

O incremento ocorre antes de `BUSY` voltar a zero. Portanto, quando o software observa `BUSY = 0`, `VIDEO_X` e `VIDEO_Y` já apontam para a próxima posição.

Exemplo de fluxo sequencial:

```asm
CALL VIDEO_WAIT
STI VIDEO_X, #$00
STI VIDEO_Y, #$00

LDA #$AA
CALL VIDEO_WRITE_A
LDA #$55
CALL VIDEO_WRITE_A
LDA #$FF
CALL VIDEO_WRITE_A
```

Não é necessário reescrever X e Y para cada byte.

# Parte IV — Gráfico 160 × 120

## 24. Seleção do modo

```asm
STI VIDEO_CMD, #$13
```

Características:

```text
Resolução lógica: 160 × 120
Profundidade:     1 bit por pixel
Escala física:    4 × 4
Saída:            640 × 480
Bytes por linha:  20
VRAM utilizada:   2.400 bytes
```

Faixa utilizada:

```text
VRAM $0000 até $095F
```

---

## 25. Organização da VRAM em 160 × 120

Cada byte representa oito pixels horizontais.

```text
160 ÷ 8 = 20 bytes por linha
20 × 120 = 2.400 bytes
```

O endereço é:

```text
endereço = VIDEO_Y × 20 + VIDEO_X
```

Onde:

```text
VIDEO_X = 0 até 19
VIDEO_Y = 0 até 119
```

Organização:

```text
VRAM $0000..$0013 → linha lógica 0
VRAM $0014..$0027 → linha lógica 1
VRAM $0028..$003B → linha lógica 2
...
```

---

## 26. Escala 4×

Cada pixel lógico é mostrado como:

```text
4 pixels horizontais × 4 linhas físicas
```

Conversão:

```text
X_lógico = X_físico >> 2
Y_lógico = Y_físico >> 2
```

No hardware, basta ignorar os dois bits menos significativos dos contadores horizontal e vertical.

Esse modo utiliza quatro vezes menos memória e exige quatro vezes menos escritas para atualizar uma tela completa do que o modo 320 × 240.

Comparação:

```text
320 × 240 → 9.600 bytes
160 × 120 → 2.400 bytes
```

---

## 27. Incremento automático em 160 × 120

Depois que a escrita pendente foi concluída:

```text
VIDEO_X = VIDEO_X + 1
```

Ao passar de 19:

```text
VIDEO_X = 0
VIDEO_Y = VIDEO_Y + 1
```

Ao passar de 119:

```text
VIDEO_Y = 0
```

Assim como no modo 320 × 240, o incremento ocorre antes de `BUSY` ser limpo.

# Parte V — Operações gráficas

## 28. Localização e alteração de um pixel

Para um pixel lógico `(X, Y)`:

```text
X_BYTE = X >> 3
BIT     = 7 - (X AND 7)
VIDEO_Y = Y
```

A máscara é:

```text
máscara = $80 >> (X AND 7)
```

Exemplo para o pixel `(13, 20)`:

```text
X_BYTE = 13 >> 3 = 1
resto  = 13 AND 7 = 5
bit    = 7 - 5 = 2
máscara = $04
```

Como o byte precisa ser lido antes de alterar somente um bit, usa-se o comando assíncrono de leitura:

```asm
PIXEL_TEMP = $02B0

; Aguarda a interface e configura a posição.
CALL VIDEO_WAIT
STI VIDEO_X, #$01
STI VIDEO_Y, #$14

; Solicita leitura da VRAM.
STI VIDEO_CMD, #$20
CALL VIDEO_WAIT

; VIDEO_DATA agora contém o byte lido.
LDA VIDEO_DATA
OR A, #$04
STA PIXEL_TEMP

; A escrita em VIDEO_DATA dispara uma nova operação pendente.
CALL VIDEO_WAIT
LDA PIXEL_TEMP
STA VIDEO_DATA
```

Para apagar o mesmo pixel:

```asm
CALL VIDEO_WAIT
STI VIDEO_X, #$01
STI VIDEO_Y, #$14
STI VIDEO_CMD, #$20
CALL VIDEO_WAIT

LDA VIDEO_DATA
AND A, #$FB
STA PIXEL_TEMP

CALL VIDEO_WAIT
LDA PIXEL_TEMP
STA VIDEO_DATA
```

Essa lógica é igual nos dois modos gráficos. O que muda são os limites de X e Y e a escala física.

## 29. Sprites alinhados a bytes

Um sprite monocromático de `8 × 8` ocupa oito bytes.

```asm
SPRITE_NAVE:
    #d8 $18
    #d8 $3C
    #d8 $7E
    #d8 $DB
    #d8 $FF
    #d8 $24
    #d8 $24
    #d8 $66
```

Representação:

```text
00011000
00111100
01111110
11011011
11111111
00100100
00100100
01100110
```

Sprites alinhados a limites de oito pixels são mais simples e rápidos, pois cada linha do sprite corresponde exatamente a uma escrita em `VIDEO_DATA`.

Sprites não alinhados exigem combinar partes de dois bytes da VRAM.

---

## 30. Retângulos e linhas alinhadas

Uma linha horizontal de 32 pixels pode ser desenhada com quatro escritas sequenciais:

```asm
CALL VIDEO_WAIT
STI VIDEO_X, #$0A
STI VIDEO_Y, #$32

LDA #$FF
CALL VIDEO_WRITE_A
LDA #$FF
CALL VIDEO_WRITE_A
LDA #$FF
CALL VIDEO_WRITE_A
LDA #$FF
CALL VIDEO_WRITE_A
```

Como cada byte representa oito pixels:

```text
4 × 8 = 32 pixels
```

O incremento automático avança `VIDEO_X` depois de cada transferência concluída. Para criar um retângulo, o programa reposiciona X e Y no início de cada linha, sempre depois de esperar `BUSY = 0`.

---

# Parte VI — Compartilhamento e arbitragem da VRAM

## 31. Por que CPU e varredura não podem acessar juntas

A `62256` é uma SRAM de porta única. Em cada instante, ela pode ter apenas:

- um endereço válido em seus pinos;
- uma direção de dados;
- uma operação de leitura ou escrita.

A varredura precisa ler a memória continuamente para gerar a imagem. A CPU também precisa escrever caracteres, pixels e comandos. Se os dois lados dirigissem os pinos ao mesmo tempo, haveria endereços diferentes no mesmo barramento e possível contenção elétrica no barramento de dados.

Por isso, a CPU não controla diretamente os pinos da VRAM. O controlador da placa é o único dono físico da SRAM e alterna entre:

```text
1. acesso de varredura da GPU;
2. operação pendente da CPU;
3. operação interna, como limpeza.
```

A prioridade de acesso à VRAM é:

```text
1º varredura, para não perder pixels;
2º operação pendente da CPU;
3º passo de comando interno, como CLEAR.
```

Durante um comando interno, novas operações da CPU ficam bloqueadas por `BUSY`.

---

## 32. Como a GPU cria uma janela livre

O clock de aproximadamente 25 MHz é um **clock de pixel físico**, não um clock de acesso obrigatório à VRAM.

A GPU lê um byte e guarda esse byte em um registrador temporário ou shift register. Depois, passa vários clocks produzindo pixels a partir do valor já guardado.

### Gráfico 320 × 240

Um byte contém oito pixels lógicos. Cada pixel lógico é repetido duas vezes horizontalmente:

```text
8 pixels lógicos × 2 = 16 pixels físicos por byte lido
```

Com um pixel clock próximo de `25,175 MHz`, cada pixel físico dura aproximadamente `39,7 ns`. Portanto, um byte permanece útil por aproximadamente:

```text
16 × 39,7 ns ≈ 635 ns
```

A GPU precisa buscar o próximo byte somente perto do fim dessa janela.

### Gráfico 160 × 120

Cada pixel lógico é repetido quatro vezes:

```text
8 × 4 = 32 pixels físicos por byte lido
```

Tempo aproximado por byte:

```text
32 × 39,7 ns ≈ 1,27 µs
```

Esse modo oferece uma janela ainda maior para operações da CPU.

### Modo texto

A VRAM fornece um código de caractere a cada célula horizontal. Uma célula ocupa oito pixels físicos de largura, portanto a leitura do código ocorre aproximadamente uma vez a cada oito clocks de pixel:

```text
8 × 39,7 ns ≈ 318 ns
```

A linha do desenho do caractere vem de uma ROM de fonte separada. A leitura dessa EPROM não ocupa a VRAM. O byte da fonte é carregado no shift register e seus oito bits são emitidos em oito clocks consecutivos. A repetição ocorre somente no eixo vertical: a mesma linha da fonte é utilizada novamente na próxima linha física.

### Velocidade da SRAM

O tempo real de leitura e escrita depende da versão escolhida da `62256` e dos atrasos dos multiplexadores, buffers e decodificadores. Uma SRAM com acesso de dezenas de nanossegundos normalmente deixa margem dentro das janelas de centenas de nanossegundos acima, mas o circuito final deve ter seu orçamento de temporização verificado com o datasheet exato dos componentes.

### Por que a CPU a 16 MHz não satura automaticamente a VRAM

`16 MHz` é o clock máximo pretendido da CPU, não uma taxa de 16 milhões de escritas de vídeo por segundo.

Uma instrução de escrita precisa de vários microsteps para:

- buscar o opcode;
- buscar operandos;
- carregar o endereço;
- mover o dado;
- executar o ciclo de I/O.

Assim, a taxa real de solicitações à GPU é muito menor que o clock bruto da CPU. Além disso, a CPU escreve primeiro nos latches da interface; a transferência física para a SRAM ocorre de forma independente no clock da GPU.

---

## 33. Transação completa de escrita da CPU

### Estado inicial

```text
BUSY = 0
VIDEO_X, VIDEO_Y e VIDEO_DATA disponíveis
```

A CPU prepara a posição:

```asm
STI VIDEO_X, #$05
STI VIDEO_Y, #$20
```

Essas escritas apenas carregam os latches. Nenhum acesso à VRAM acontece ainda.

### Disparo

```asm
STI VIDEO_DATA, #$A5
```

O decodificador de `$F200` gera um pulso que:

```text
VIDEO_DATA    ← DBUS
WRITE_PENDING ← 1
BUSY          ← 1
```

A partir desse momento, X, Y e DATA ficam reservados. O software não deve alterá-los.

### Espera pelo slot

Enquanto o registrador de pixels está emitindo os bits do byte já lido, a máquina de estados aguarda o ponto programado para uma operação de CPU.

Representação simplificada no modo 320 × 240:

```text
Tempo ─────────────────────────────────────────────────────►

pixels:  [ byte atual sendo emitido por 16 clocks físicos ]
VRAM:    [SCAN READ]      [CPU WRITE]          [SCAN READ]
BUSY:    0 ──────── 1 ─────────────────────────────── 0
```

### Escrita física

No slot da CPU, o controlador executa:

```text
1. desativa /OE da SRAM;
2. seleciona no MUX o endereço formado por VIDEO_X e VIDEO_Y;
3. habilita o buffer que liga VIDEO_DATA ao barramento da VRAM;
4. respeita o tempo de estabelecimento de endereço e dados;
5. gera um pulso em /WE;
6. mantém os dados pelo tempo mínimo exigido;
7. desabilita o buffer de escrita;
8. retorna o MUX para o endereço da varredura.
```

Durante a escrita:

```text
/OE = 1
/WE recebe o pulso ativo
buffer CPU→VRAM habilitado
```

Durante uma leitura de varredura:

```text
/WE = 1
buffer CPU→VRAM em alta impedância
/OE = 0
```

Isso impede que a SRAM e o latch de dados dirijam o barramento ao mesmo tempo.

### Conclusão

Depois da escrita:

```text
1. VIDEO_X/VIDEO_Y são incrementados automaticamente;
2. WRITE_PENDING é limpo;
3. BUSY volta para 0;
4. a interface pode aceitar o próximo byte.
```

### Não é necessário duplicar X, Y e DATA

Para uma fila de apenas uma operação, os próprios registradores visíveis são o buffer:

```text
VIDEO_X    guarda a posição horizontal
VIDEO_Y    guarda a posição vertical
VIDEO_DATA guarda o byte
BUSY       informa que esses valores estão em uso
```

Não é necessário outro conjunto idêntico de latches para a escrita.

Uma implementação futura com FIFO exigiria registros adicionais, mas eles seriam internos e não mudariam necessariamente o mapa `$F200..$F204`.

### Escrita enquanto `BUSY = 1`

A primeira versão não deve substituir silenciosamente uma operação pendente. O contrato de software é:

```text
não escrever X, Y, DATA ou um novo comando enquanto BUSY = 1
```

Sem um pino `WAIT` na CPU, a segurança vem do polling. Uma escrita que viole essa regra é inválida e não deve ser usada por BIOS, cartuchos ou programas.

---

## 34. Leituras, comandos longos e sincronização

### Leitura solicitada pela CPU

Uma leitura direta no mesmo ciclo de `LDA VIDEO_DATA` seria difícil, pois a VRAM pode estar atendendo a varredura. Por isso, a leitura usa o comando `$20`.

Fluxo:

```text
1. CPU espera BUSY = 0.
2. CPU escreve VIDEO_X e VIDEO_Y.
3. CPU escreve $20 em VIDEO_CMD.
4. READ_PENDING = 1 e BUSY = 1.
5. No próximo slot livre, a GPU lê a VRAM.
6. O byte é guardado em um latch interno de resultado.
7. READ_PENDING é limpo e BUSY volta para 0.
8. CPU lê VIDEO_DATA e recebe o resultado.
```

Código:

```asm
CALL VIDEO_WAIT
STI VIDEO_X, #$05
STI VIDEO_Y, #$20
STI VIDEO_CMD, #$20
CALL VIDEO_WAIT
LDA VIDEO_DATA
```

A leitura não incrementa X ou Y.

### Comando de limpeza

`VIDEO_CLEAR` utiliza um contador interno de endereço e o valor de preenchimento adequado ao modo:

```text
texto:    $20
imagem:   $00
```

Durante toda a operação:

```text
BUSY = 1
```

A máquina de estados intercala:

```text
SCAN READ → CLEAR WRITE → SCAN READ → CLEAR WRITE → ...
```

A saída de vídeo continua ativa. A tela pode ser vista sendo apagada progressivamente, dependendo da velocidade do controlador. Ao final, X e Y voltam a zero e `BUSY` é limpo.

### Polling não acompanha a janela microscópica

O software não tenta descobrir o exato clock em que a SRAM ficou livre. Ele apenas pergunta se a operação anterior já terminou:

```asm
VIDEO_WAIT:
    LDA VIDEO_STATUS
    TEST A, #$01
    JNZ VIDEO_WAIT
    RET
```

A máquina de estados da GPU é quem enxerga os slots de nanossegundos.

### Custo do polling

Ler `BUSY` repetidamente não danifica nenhum componente. A desvantagem é somente ocupar a CPU enquanto espera.

Para escritas normais, o controlador tende a concluir a transferência antes de a CPU completar outra sequência de instruções. Em comandos longos, como limpar 9.600 bytes, a CPU pode ficar parada por mais tempo. Isso é aceitável na primeira versão e pode ser melhorado futuramente com interrupção, FIFO ou sinal `WAIT`.

### Rasgo de imagem

Mesmo com arbitragem correta, a CPU pode modificar uma região depois que a parte superior do quadro já foi exibida e antes que a parte inferior seja varrida. Isso pode produzir tearing, mas não causa conflito elétrico.

Para reduzir o efeito, o software pode esperar `VBLANK` antes de atualizar grandes áreas:

```asm
WAIT_VBLANK:
    LDA VIDEO_STATUS
    TEST A, #$02
    JZ WAIT_VBLANK
    RET
```

Uma futura dupla página de framebuffer pode eliminar esse problema, mas não é necessária na primeira versão.

# Parte VII — Geração do endereço de vídeo

## 35. Caminho de texto

No modo texto:

```text
endereço da VRAM = linha_de_texto × 80 + coluna_de_texto
```

O byte lido é o código do caractere.

Depois:

```text
endereço da fonte = (banco << 14) | (linha_interna << 8) | código
```

O byte da fonte entra em um shift register e seus bits geram os pixels.

---

## 36. Caminho gráfico 320 × 240

No modo 320 × 240:

```text
endereço da VRAM = Y_lógico × 40 + X_byte
```

Cada byte é carregado em um shift register. Cada bit permanece na saída por dois clocks de pixel físico e cada linha lógica é repetida duas vezes.

---

## 37. Caminho gráfico 160 × 120

No modo 160 × 120:

```text
endereço da VRAM = Y_lógico × 20 + X_byte
```

Cada bit permanece na saída por quatro clocks físicos e cada linha lógica é repetida quatro vezes.

---

## 38. Geração sequencial sem multiplicador

A GPU não precisa possuir um multiplicador para calcular `Y × 80`, `Y × 40` ou `Y × 20` durante cada pixel.

Durante a exibição, ela pode manter um endereço-base para a linha lógica e um contador sequencial dentro dessa linha:

```text
início do quadro                  → endereço-base $0000
próximo byte da mesma linha       → endereço + 1
nova linha física, mesma lógica   → recarrega o endereço-base atual
primeira linha física da próxima
linha lógica                      → endereço-base + bytes por linha
fim do quadro                     → endereço-base $0000
```

Os limites mudam conforme o modo:

```text
Texto:      80 bytes por linha e 30 linhas
320×240:    40 bytes por linha e 240 linhas
160×120:    20 bytes por linha e 120 linhas
```

No texto, cada linha de 80 códigos é relida durante as 16 linhas físicas que formam uma linha textual. O endereço-base da próxima linha textual somente avança em 80 bytes quando `V_COUNTER` passa para a próxima célula vertical. Dentro da célula, `V0` faz cada linha da fonte durar duas linhas físicas e `V1..V3` selecionam uma das oito linhas armazenadas.

Isso reduz muito a complexidade do hardware discreto.

---

# Parte VIII — Inicialização e exemplos

## 39. Rotinas básicas de interface

```asm
VIDEO_DATA   = $F200
VIDEO_CMD    = $F201
VIDEO_X      = $F202
VIDEO_Y      = $F203
VIDEO_STATUS = $F204

VIDEO_TEMP   = $02AF

VIDEO_WAIT:
    LDA VIDEO_STATUS
    TEST A, #$01
    JNZ VIDEO_WAIT
    RET

; Entrada: A = byte que deve ser escrito.
; A rotina espera a operação anterior, carrega o latch e retorna.
VIDEO_WRITE_A:
    STA VIDEO_TEMP
VIDEO_WRITE_A_WAIT:
    LDA VIDEO_STATUS
    TEST A, #$01
    JNZ VIDEO_WRITE_A_WAIT
    LDA VIDEO_TEMP
    STA VIDEO_DATA
    RET

; Entrada: VIDEO_X e VIDEO_Y já configurados.
; Saída: A = byte lido da VRAM.
VIDEO_READ_A:
    CALL VIDEO_WAIT
    STI VIDEO_CMD, #$20
    CALL VIDEO_WAIT
    LDA VIDEO_DATA
    RET
```

---

## 40. Inicialização do modo texto

```asm
CALL VIDEO_WAIT
STI VIDEO_CMD, #$11

CALL VIDEO_WAIT
STI VIDEO_CMD, #$00
CALL VIDEO_WAIT

STI VIDEO_X, #$00
STI VIDEO_Y, #$00
STI VIDEO_CMD, #$05
```

---

## 41. Escrever texto

```asm
LDA #$57             ; W
CALL VIDEO_WRITE_A
LDA #$41             ; A
CALL VIDEO_WRITE_A
LDA #$4C             ; L
CALL VIDEO_WRITE_A
LDA #$4C             ; L
CALL VIDEO_WRITE_A
LDA #$2D             ; -
CALL VIDEO_WRITE_A
LDA #$38             ; 8
CALL VIDEO_WRITE_A
LDA #$0D             ; nova linha
CALL VIDEO_WRITE_A
```

---

## 42. Inicialização gráfica 320 × 240

```asm
CALL VIDEO_WAIT
STI VIDEO_CMD, #$12

CALL VIDEO_WAIT
STI VIDEO_CMD, #$00
CALL VIDEO_WAIT

STI VIDEO_X, #$00
STI VIDEO_Y, #$00
```

---

## 43. Inicialização gráfica 160 × 120

```asm
CALL VIDEO_WAIT
STI VIDEO_CMD, #$13

CALL VIDEO_WAIT
STI VIDEO_CMD, #$00
CALL VIDEO_WAIT

STI VIDEO_X, #$00
STI VIDEO_Y, #$00
```

---

## 44. Padrão gráfico simples

```asm
CALL VIDEO_WAIT
STI VIDEO_CMD, #$13
CALL VIDEO_WAIT
STI VIDEO_CMD, #$00
CALL VIDEO_WAIT

STI VIDEO_X, #$00
STI VIDEO_Y, #$00

LDA #$AA
CALL VIDEO_WRITE_A
LDA #$55
CALL VIDEO_WRITE_A
LDA #$AA
CALL VIDEO_WRITE_A
LDA #$55
CALL VIDEO_WRITE_A
```

---

## 45. Retorno de um cartucho gráfico

A BIOS chama o cartucho usando:

```asm
CALL $A000
```

O cartucho pode utilizar qualquer modo de vídeo e retornar com:

```asm
RET
```

A forma mais robusta é a BIOS restaurar o próprio terminal após o retorno do cartucho:

```asm
CALL $A000
CALL HISTORY_REDRAW
```

Assim, cada cartucho não precisa conhecer os detalhes internos do histórico da BIOS.

Caso o cartucho precise restaurar manualmente o modo texto:

```asm
CALL VIDEO_WAIT
STI VIDEO_CMD, #$11
CALL VIDEO_WAIT
STI VIDEO_CMD, #$00
CALL VIDEO_WAIT
RET
```

# Parte IX — Memória e componentes

## 46. VRAM

Uma SRAM `62256` possui:

```text
32 KiB = 32.768 bytes
```

Uso máximo atual:

```text
modo 320 × 240 = 9.600 bytes
```

Portanto, uma única `62256` é suficiente para todos os modos atuais.

Espaço restante no pior caso:

```text
32.768 - 9.600 = 23.168 bytes
```

Esse espaço pode futuramente ser utilizado para:

- segunda página gráfica;
- sprites armazenados na GPU;
- fontes carregáveis;
- buffers auxiliares;
- dupla página para reduzir tearing.

Essas funções não fazem parte da primeira versão.

---

## 47. ROM de fonte

A ROM de fonte pode utilizar uma `27C512`.

```text
Capacidade: 65.536 bytes
Fonte atual: 2.048 bytes
```

A primeira versão utiliza somente os endereços necessários para uma fonte de 256 caracteres.

Os bits superiores da EPROM podem permanecer fixos ou ser reservados para bancos futuros.

---

# Parte X — Regras oficiais de software

## 48. Regras gerais

1. O programa deve selecionar o modo antes de utilizar a placa.
2. A troca de modo não precisa preservar visualmente o conteúdo anterior.
3. O comando `$00` limpa somente a região usada pelo modo atual.
4. Antes de alterar `VIDEO_X`, `VIDEO_Y`, `VIDEO_DATA` ou iniciar um comando de VRAM, o software deve esperar `BUSY = 0`.
5. Escrever em `VIDEO_X` ou `VIDEO_Y` apenas prepara a posição; a escrita na VRAM é disparada por uma escrita em `VIDEO_DATA`.
6. Ao escrever em `VIDEO_DATA`, o byte, X e Y ficam retidos até a GPU encontrar um slot livre da VRAM.
7. Durante essa operação, `BUSY = 1` e os registradores não devem ser modificados pela CPU.
8. A GPU limpa `BUSY` somente depois que a operação foi realmente concluída.
9. Em texto, `VIDEO_X` é uma coluna de caractere.
10. Em gráfico, `VIDEO_X` é uma coluna de byte, não uma coordenada de pixel.
11. Uma escrita gráfica controla oito pixels horizontais.
12. O bit 0 representa o pixel mais à esquerda.
13. Escritas concluídas em `VIDEO_DATA` incrementam a posição automaticamente.
14. Leituras de VRAM são solicitadas com `VIDEO_CMD = $20` e não incrementam a posição.
15. `LDA VIDEO_DATA` retorna o resultado da última leitura concluída, não inicia sozinho um acesso assíncrono à SRAM.
16. O cursor existe somente no modo texto.
17. Os dois modos gráficos são monocromáticos.
18. A saída física permanece em 640 × 480 nos três modos.
19. O polling de `BUSY` é o mecanismo oficial de sincronização da primeira versão.
20. O cartucho deve retornar à BIOS com `RET` quando tiver sido chamado com `CALL $A000`.

## 49. Limites por modo

| Modo | X mínimo | X máximo | Y mínimo | Y máximo | Bytes por linha |
|---|---:|---:|---:|---:|---:|
| Texto 80 × 30 | 0 | 79 | 0 | 29 | 80 |
| Gráfico 320 × 240 | 0 | 39 | 0 | 239 | 40 |
| Gráfico 160 × 120 | 0 | 19 | 0 | 119 | 20 |

---

## 50. Mapa consolidado

### Registradores

```text
$F200  VIDEO_DATA    latch de escrita / resultado de leitura
$F201  VIDEO_CMD     comandos e solicitação de leitura
$F202  VIDEO_X       posição horizontal retida
$F203  VIDEO_Y       posição vertical retida
$F204  VIDEO_STATUS  estado da interface e da varredura
```

### Comandos

```text
$00  limpar tela do modo atual
$04  esconder cursor
$05  mostrar cursor
$11  texto 80 × 30, fonte 8 × 8 e duplicação vertical
$12  gráfico 320 × 240 monocromático
$13  gráfico 160 × 120 monocromático
$20  solicitar leitura de VRAM em X/Y
```

### Status

```text
bit 0  BUSY    interface reservada por escrita, leitura ou comando
bit 1  VBLANK  intervalo vertical
bit 2  HBLANK  intervalo horizontal
bit 3  FRAME   alterna a cada quadro
bits 4..7 reservados
```

### Detecção no sistema

```text
$F300 bit 5 = /VIDEO_DETECT
0 = placa presente
1 = placa ausente
```

### Fluxo de escrita resumido

```text
CPU configura X/Y
        ↓
CPU escreve DATA
        ↓
DATA fica retido e BUSY sobe
        ↓
GPU lê pixels para o registro temporário
        ↓
no intervalo livre, controlador grava DATA na VRAM
        ↓
X/Y incrementam e BUSY desce
```

# Parte XI — Escopo da primeira versão

## 51. Recursos incluídos

A primeira versão deve implementar:

- saída física 640 × 480;
- modo texto 80 × 30;
- fonte fixa 8 × 8;
- 256 códigos de caractere;
- cursor visível ou oculto;
- escrita sequencial de texto;
- modo gráfico 320 × 240 monocromático;
- modo gráfico 160 × 120 monocromático;
- registradores CPU-visíveis `DATA`, `CMD`, `X`, `Y` e `STATUS`;
- retenção de X, Y e DATA durante uma escrita pendente;
- flip-flops `WRITE_PENDING` e `READ_PENDING` ou máquina de estados equivalente;
- `BUSY` como handshake por polling;
- leitura assíncrona da VRAM pelo comando `$20`;
- incremento automático de posição depois da escrita concluída;
- comando de limpar tela;
- sinais `BUSY`, `VBLANK`, `HBLANK` e `FRAME`;
- detecção física da placa;
- arbitragem entre CPU, limpeza e geração de vídeo;
- multiplexação dos endereços da VRAM;
- buffers tri-state para impedir contenção no barramento de dados;
- registrador temporário ou shift register para manter o byte durante a emissão dos pixels.

## 52. Recursos deixados para versões futuras

Não são necessários na primeira versão:

- cores por pixel;
- atributos de cor por caractere;
- sprites por hardware;
- scroll gráfico por hardware;
- comandos de linha ou retângulo por hardware;
- fontes selecionáveis por software;
- paleta de cores;
- dupla página;
- transparência;
- camadas;
- interrupção de VBLANK;
- DMA.

---

# 53. Conclusão

A placa de vídeo do WALL-8 funciona como um controlador independente com VRAM própria.

A CPU controla todos os modos usando somente cinco endereços:

```text
VIDEO_DATA, VIDEO_CMD, VIDEO_X, VIDEO_Y e VIDEO_STATUS
```

`VIDEO_X`, `VIDEO_Y` e `VIDEO_DATA` também formam o buffer mínimo de uma operação de escrita. A CPU prepara X e Y e, ao escrever em DATA, dispara a transação. `BUSY` sobe para avisar que esses valores estão reservados. A máquina de estados espera a varredura carregar o próximo byte no registrador temporário, utiliza a janela livre para gravar na VRAM, incrementa a posição e só então limpa `BUSY`.

A GPU não precisa ler a SRAM a cada pixel físico. No modo texto, um código de caractere é lido a cada oito pixels físicos e a ROM de fonte fornece o byte efetivamente deslocado. No modo 320 × 240, um byte gráfico alimenta 16 pixels físicos; no modo 160 × 120, alimenta 32. Essa reutilização do byte cria tempo suficiente para intercalar acessos da CPU com uma SRAM de porta única, desde que o orçamento de temporização seja verificado no hardware final.

O modo texto prioriza terminal, BIOS e aventuras em texto. O modo gráfico `320 × 240` oferece maior definição, enquanto o modo `160 × 120` reduz significativamente o trabalho da CPU e é especialmente adequado para jogos simples.

Os três modos compartilham:

- a mesma saída física de 640 × 480;
- a mesma VRAM;
- o mesmo circuito de sincronismo;
- a mesma interface com a CPU;
- a mesma lógica de `BUSY`;
- o mesmo sistema de arbitragem;
- o mesmo registrador temporário de pixels;
- a mesma lógica básica de incremento automático.

A diferença entre eles está na interpretação da VRAM, na quantidade de bytes por linha e na escala aplicada aos pixels lógicos.
