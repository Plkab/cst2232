# Bases du Graphisme Embarqué sur écran TFT ILI9488 et VGA

*Ir Paul S. Kabidu, M.Eng. <spaulkabidu@gmail.com>*
{: style="text-align: center;" }

---

[Accueil](../../#Accueil)

<br>
<br>



### **Introduction au graphisme embarqué**

Les interfaces homme-machine (IHM) sont omniprésentes dans les systèmes embarqués modernes : affichage de données, menus, graphiques, etc. Deux technologies courantes sont :

- **Les écrans TFT couleur** (par exemple ILI9488) pilotés via SPI ou parallèle, offrant une résolution et des couleurs riches.
- **La génération de signal VGA** permettant de connecter un écran d’ordinateur ou un moniteur, avec une résolution standard (640x480) et une palette limitée.

Dans ce chapitre, nous aborderons les concepts communs (framebuffer, résolution, codage couleur) puis nous détaillerons le pilotage de ces deux types d’affichage sur notre carte STM32F401 (Black Pill). Nous fournirons des pilotes simples et des exemples d’intégration avec FreeRTOS.

---
<br>



### **Concepts de base du graphisme**

**Pixel et résolution**

Un **pixel** est le plus petit élément adressable d’un écran. La **résolution** est le nombre de pixels en largeur et hauteur (ex: 320x240 pour un petit TFT, 640x480 pour VGA).

**Framebuffer**

Le **framebuffer** est une zone mémoire qui stocke l’image à afficher. Chaque pixel est représenté par un nombre de bits (couleur). Pour un écran couleur, on peut utiliser :

- 16 bits par pixel (RGB565) : 5 bits pour rouge, 6 pour vert, 5 pour bleu.
- 24 bits (RGB888) : 8 bits par composante.
- Palette indexée : chaque pixel est un index dans une table de couleurs.

Le framebuffer est mis à jour par le microcontrôleur, puis le contrôleur d’affichage (ou le programme) envoie les données à l’écran.

**Coordonnées**

L’origine (0,0) est généralement en haut à gauche. Les axes X (horizontal) et Y (vertical) permettent de positionner les pixels.

**Bibliothèques graphiques**

Des bibliothèques comme **LVGL**, **uGUI** ou **emWin** offrent des primitives de haut niveau (lignes, cercles, polices). Ici, nous nous concentrerons sur le pilotage bas niveau.

---
<br>



## **Partie 1 : Pilotage d’un écran TFT ILI9488**

Les écrans graphiques sont devenus incontournables dans les systèmes embarqués pour offrir une interface utilisateur riche. Contrairement aux afficheurs caractères, ils permettent de contrôler chaque pixel individuellement, autorisant l'affichage de graphiques, d'images et de textes variés. Ce chapitre se concentre sur l'écran TFT couleur **ILI9488**, un contrôleur très répandu pour les modules de 3,2 pouces (320×480 pixels) avec une profondeur de couleur 18 bits (262 144 couleurs). Nous verrons comment l'interfacer avec le STM32F401 via le bus SPI et comment programmer des fonctions graphiques de base.

**Résolution et pas de point**

La qualité d'un écran est principalement déterminée par sa **résolution** (nombre de pixels en largeur et hauteur) et son **pas de point** (distance entre deux pixels). Par exemple, un écran **320×480** possède 320 pixels par ligne et 480 lignes, soit **153 600 pixels**. Le pas de point, exprimé en millimètres, donne la taille physique de l'image.

**Profondeur de couleur (BPP)**

Le nombre de couleurs affichables dépend du nombre de **bits par pixel (BPP)** :
*   **1 BPP** : 2 couleurs (monochrome).
*   **16 BPP** : 65 536 couleurs.
*   **24 BPP** : 16 millions de couleurs.

L'**ILI9488** utilise 18 bits (6 bits par composante Rouge, Vert, Bleu), soit 262 144 couleurs. En pratique, on utilise souvent un codage **RGB565** (16 bits) où le rouge et le bleu sont sur 5 bits et le vert sur 6 bits. C'est un bon compromis entre qualité et occupation mémoire.

**Mémoire tampon (framebuffer)**

Pour stocker l'image affichée, on a besoin d'une mémoire tampon. Pour un écran **320×480** en **RGB565** (2 octets par pixel), la mémoire nécessaire est :

$$320 \times 480 \times 2 = 307\,200 \text{ octets} \approx 300 \text{ Ko}$$

Le **STM32F401** ne dispose pas de suffisamment de RAM interne (**64 Ko**) pour contenir un framebuffer complet. On devra donc :
*   Rafraîchir l'écran par **blocs**.
*   Utiliser une méthode de **dessin direct** (chaque pixel est envoyé immédiatement). 

Pour des applications simples, cela reste tout à fait possible.

**L'écran ILI9488**

- Résolution : 320 × 480 pixels
- Interface : parallèle (8/16/18 bits) ou série (SPI 4 fils)
- Profondeur de couleur : 18 bits (262 144 couleurs)
- Tension d'alimentation : 3,3 V
- Pilote intégré avec RAM graphique (GRAM) de 320×480×18 bits

Nous utiliserons le mode SPI 4 fils (SCLK, SDI (MOSI), CS, DC) qui nécessite moins de broches. La broche RESET est également requise.

**Brochage**

| Fonction | Broche STM32 |
|----------|--------------|
| SCK      | PA5 (SPI1_SCK) |
| MOSI     | PA7 (SPI1_MOSI) |
| CS       | PA4 (sortie GPIO) |
| DC       | PA3 (sortie GPIO) – Data/Command |
| RST      | PA2 (sortie GPIO) – Reset |
| BL       | PA1 (sortie GPIO) – Backlight (optionnel) |

```text
STM32F401          ILI9488 module
   PA5  ----------  SCLK
   PA7  ----------  SDI
   PA4  ----------  CS
   PA6  ----------  DC
   PB0  ----------  RESET
   3.3V ----------  VCC
   GND  ----------  GND
```

**Protocole SPI**

Le ILI9488 attend des commandes et des données via SPI. La broche DC indique si l’octet envoyé est une commande (DC=0) ou une donnée (DC=1). Les données sont généralement envoyées sur plusieurs octets (ex: 3 octets pour une couleur RGB666).

Le module SPI du STM32F401 doit être configuré en mode maître, avec une fréquence d'horloge typique de 10 à 40 MHz (selon les possibilités de l'écran). La plupart des modules ILI9488 acceptent jusqu'à 80 MHz. On utilisera le mode SPI CPOL=0, CPHA=0 (mode 0). Les données sont envoyées en premier bit de poids fort (MSB first). Les commandes et les données sont envoyées sur 8 bits. Pour les données de pixel en RGB565, on envoie deux octets consécutifs.

**Initialisation de l'écran**

L'initialisation de l'ILI9488 nécessite l'envoi d'une séquence de commandes spécifique, fournie dans la datasheet. Voici une séquence typique (valable pour de nombreux modules). Les commandes sont envoyées sur 8 bits avec DC = 0, puis les éventuelles données (paramètres) avec DC = 1.

L’initialisation consiste à envoyer une séquence de commandes pour configurer le contrôleur (orientation, polarité, etc.). Voici une séquence typique (simplifiée) :

```c
#include "stm32f4xx.h"
#include <stdint.h>

// Définitions des broches
#define CS_LOW()   GPIOA->ODR &= ~(1 << 4)
#define CS_HIGH()  GPIOA->ODR |=  (1 << 4)
#define DC_CMD()   GPIOA->ODR &= ~(1 << 6)   // commande
#define DC_DATA()  GPIOA->ODR |=  (1 << 6)   // donnée
#define RESET_LOW()   GPIOB->ODR &= ~(1 << 0)
#define RESET_HIGH()  GPIOB->ODR |=  (1 << 0)

// Fonctions SPI
void SPI1_Init(void) {
    RCC->AHB1ENR |= RCC_AHB1ENR_GPIOAEN | RCC_AHB1ENR_GPIOBEN;
    RCC->APB2ENR |= RCC_APB2ENR_SPI1EN;

    // PA5 (SCK), PA7 (MOSI) en AF5
    GPIOA->MODER |= (2 << (5*2)) | (2 << (7*2));
    GPIOA->AFR[0] |= (5 << (5*4)) | (5 << (7*4));

    // PA4 (CS) et PA6 (DC) en sortie GPIO
    GPIOA->MODER |= (1 << (4*2)) | (1 << (6*2));
    GPIOA->ODR |= (1 << 4);   // CS = 1 par défaut
    GPIOA->ODR |= (1 << 6);   // DC = 1 (donnée)

    // PB0 (RESET) en sortie
    GPIOB->MODER |= (1 << (0*2));
    GPIOB->ODR |= (1 << 0);   // RESET = 1

    // Configuration SPI : maître, 8 bits, CPOL=0, CPHA=0, fréquence ~ 5 MHz
    SPI1->CR1 = SPI_CR1_MSTR | SPI_CR1_BR_2 | SPI_CR1_BR_1; // BR = 011 => fPCLK/16 (84/16=5.25 MHz)
    SPI1->CR1 |= SPI_CR1_SPE;
}

void SPI1_WriteByte(uint8_t data) {
    while (!(SPI1->SR & SPI_SR_TXE));
    SPI1->DR = data;
    while (!(SPI1->SR & SPI_SR_RXNE));
    (void)SPI1->DR; // vider le buffer
}

void LCD_WriteCmd(uint8_t cmd) {
    DC_CMD();
    CS_LOW();
    SPI1_WriteByte(cmd);
    CS_HIGH();
}

void LCD_WriteData(uint8_t data) {
    DC_DATA();
    CS_LOW();
    SPI1_WriteByte(data);
    CS_HIGH();
}

void LCD_WriteData16(uint16_t data) {
    DC_DATA();
    CS_LOW();
    SPI1_WriteByte(data >> 8);   // octet haut
    SPI1_WriteByte(data & 0xFF); // octet bas
    CS_HIGH();
}

void LCD_Init(void) {
    // Reset matériel
    RESET_LOW();
    for (int i = 0; i < 10000; i++);
    RESET_HIGH();
    for (int i = 0; i < 10000; i++);

    // Séquence d'initialisation (adaptée à ILI9488)
    LCD_WriteCmd(0x01); // Software reset
    for (int i = 0; i < 100000; i++);

    LCD_WriteCmd(0x11); // Sleep out
    for (int i = 0; i < 100000; i++);

    LCD_WriteCmd(0x36); // Memory Access Control
    LCD_WriteData(0x48); // BGR, orientation

    LCD_WriteCmd(0x3A); // Interface Pixel Format
    LCD_WriteData(0x55); // 16 bits par pixel (RGB565)

    // Paramètres de la gamme de couleurs (optionnels, selon la datasheet)
    LCD_WriteCmd(0xC2); // Display Control
    LCD_WriteData(0x44);
    LCD_WriteCmd(0xC5); // VCOM Control
    LCD_WriteData(0x00);
    LCD_WriteData(0x00);
    LCD_WriteData(0x00);
    LCD_WriteCmd(0xE0); // Positive Gamma Control
    LCD_WriteData(0x0F);
    LCD_WriteData(0x1F);
    LCD_WriteData(0x1C);
    LCD_WriteData(0x0C);
    LCD_WriteData(0x0F);
    LCD_WriteData(0x08);
    LCD_WriteData(0x48);
    LCD_WriteData(0x98);
    LCD_WriteData(0x37);
    LCD_WriteData(0x0A);
    LCD_WriteData(0x13);
    LCD_WriteData(0x04);
    LCD_WriteData(0x11);
    LCD_WriteData(0x0D);
    LCD_WriteData(0x00);

    LCD_WriteCmd(0xE1); // Negative Gamma Control
    LCD_WriteData(0x0F);
    LCD_WriteData(0x32);
    LCD_WriteData(0x2E);
    LCD_WriteData(0x0B);
    LCD_WriteData(0x0D);
    LCD_WriteData(0x05);
    LCD_WriteData(0x47);
    LCD_WriteData(0x75);
    LCD_WriteData(0x37);
    LCD_WriteData(0x06);
    LCD_WriteData(0x10);
    LCD_WriteData(0x03);
    LCD_WriteData(0x24);
    LCD_WriteData(0x20);
    LCD_WriteData(0x00);

    LCD_WriteCmd(0x29); // Display ON
}


void ILI9488_WriteCmd(uint8_t cmd) {
    GPIOA->ODR &= ~(1 << 3); // DC bas
    SPI1_CS_Low();
    SPI1_Transmit8(cmd);
    SPI1_CS_High();
}

void ILI9488_WriteData(uint8_t data) {
    GPIOA->ODR |= (1 << 3); // DC haut
    SPI1_CS_Low();
    SPI1_Transmit8(data);
    SPI1_CS_High();
}

void ILI9488_Init(void) {
    // Reset
    GPIOA->ODR &= ~(1 << 2); // RST bas
    delay_ms(10);
    GPIOA->ODR |= (1 << 2); // RST haut
    delay_ms(120);

    // Séquence d'initialisation (issue de la datasheet)
    ILI9488_WriteCmd(0x11); // Sleep out
    delay_ms(120);
    ILI9488_WriteCmd(0x36); // Memory Access Control
    ILI9488_WriteData(0x48); // BGR, orientation
    ILI9488_WriteCmd(0x3A); // Interface Pixel Format
    ILI9488_WriteData(0x66); // 18 bits (RGB666) par pixel
    ILI9488_WriteCmd(0xC2); // Display Control
    ILI9488_WriteData(0x44);
    ILI9488_WriteCmd(0xC5); // VCOM Control
    ILI9488_WriteData(0x00);
    ILI9488_WriteData(0x00);
    ILI9488_WriteData(0x00);
    ILI9488_WriteCmd(0xE0); // Positive Gamma
    // ... (séquence gamma, omise pour brièveté)
    ILI9488_WriteCmd(0xE1); // Negative Gamma
    // ... (séquence gamma)
    ILI9488_WriteCmd(0x29); // Display ON
}
```

---
<br>




### **Fonction de dessin d’un pixel**

**Définir une fenêtre (zone d'affichage)**

Pour dessiner un pixel en RGB666 (18 bits), on doit envoyer 3 octets par pixel. On définit d’abord une fenêtre (zone) puis on envoie les données.

Pour envoyer des pixels, on doit d'abord définir la zone de l'écran concernée via les commandes CASET (colonne) et PASET (page/ligne).

```c
void ILI9488_SetWindow(uint16_t x1, uint16_t y1, uint16_t x2, uint16_t y2) {
    ILI9488_WriteCmd(0x2A); // Column address set
    ILI9488_WriteData(x1 >> 8); ILI9488_WriteData(x1 & 0xFF);
    ILI9488_WriteData(x2 >> 8); ILI9488_WriteData(x2 & 0xFF);
    ILI9488_WriteCmd(0x2B); // Row address set
    ILI9488_WriteData(y1 >> 8); ILI9488_WriteData(y1 & 0xFF);
    ILI9488_WriteData(y2 >> 8); ILI9488_WriteData(y2 & 0xFF);
    ILI9488_WriteCmd(0x2C); // Memory write
}

void ILI9488_DrawPixel(uint16_t x, uint16_t y, uint16_t color565) {
    // color565 en RGB565, on convertit en RGB666 approximatif
    uint8_t r = (color565 >> 11) & 0x1F; // 5 bits
    uint8_t g = (color565 >> 5) & 0x3F; // 6 bits
    uint8_t b = color565 & 0x1F; // 5 bits
    // Conversion en 6 bits par duplication
    r = (r << 1) | (r >> 4);
    b = (b << 1) | (b >> 4);
    ILI9488_SetWindow(x, y, x, y);
    ILI9488_WriteData(r); // rouge 6 bits
    ILI9488_WriteData(g); // vert 6 bits
    ILI9488_WriteData(b); // bleu 6 bits
}
```

**Remplissage d’écran**

Pour remplir rapidement, on peut envoyer une longue série de données sans repositionner la fenêtre.

```c
void ILI9488_FillScreen(uint16_t color565) {
    uint8_t r = (color565 >> 11) & 0x1F;
    uint8_t g = (color565 >> 5) & 0x3F;
    uint8_t b = color565 & 0x1F;
    r = (r << 1) | (r >> 4);
    b = (b << 1) | (b >> 4);
    ILI9488_SetWindow(0, 0, 319, 479);
    for (uint32_t i = 0; i < 320*480; i++) {
        ILI9488_WriteData(r);
        ILI9488_WriteData(g);
        ILI9488_WriteData(b);
    }
}
```

**Dessiner une ligne horizontale ou verticale**

```c
void LCD_DrawHLine(uint16_t x1, uint16_t x2, uint16_t y, uint16_t color) {
    LCD_FillArea(x1, y, x2, y, color);
}

void LCD_DrawVLine(uint16_t x, uint16_t y1, uint16_t y2, uint16_t color) {
    LCD_FillArea(x, y1, x, y2, color);
}
```

**Affichage de texte**

Pour afficher des caractères, on utilise une table de caractères (font) sous forme de bitmap. Une police simple 8×12 (8 colonnes, 12 lignes) convient. Chaque caractère est représenté par 12 octets (chaque octet codant 8 pixels horizontaux). On peut stocker ces tables dans la mémoire Flash du STM32.


---
<br>





### Partie 2 : Génération de signal VGA

Le **VGA** est un standard analogique avec 5 signaux : Rouge, Vert, Bleu (analogiques 0-0.7V), synchronisation horizontale (**HSYNC**) et verticale (**VSYNC**). Les timings sont très stricts : pour une résolution 640x480 à 60 Hz, il faut générer des impulsions à des intervalles précis.

Sur un microcontrôleur sans DAC vidéo, on peut générer :

- les signaux de synchronisation par des **timers**,
- les couleurs par des **GPIO rapides** (R-2R ou sorties numériques avec résistances).

La palette sera limitée (par exemple **8 couleurs** avec 3 bits).


**Timings VGA 640x480 @ 60 Hz**

| Zone            | Durée (µs) | Pixels (à 25.175 MHz) |
|-----------------|------------|-----------------------|
| Visible (ligne) | 25.42      | 640                   |
| Front porch (H) | 0.64       | 16                    |
| HSYNC pulse     | 3.81       | 96                    |
| Back porch (H)  | 1.91       | 48                    |
| Total ligne     | 31.78      | 800                   |

Pour le vertical, une trame comporte **525 lignes** (dont 480 visibles).

**Principe de génération**

- Un **timer** génère une interruption au début de chaque ligne.
- Dans l’ISR, on gère **HSYNC** et **VSYNC**, et on envoie les pixels ligne par ligne (via un framebuffer).
- Pour 640 pixels par ligne à 25 MHz, le CPU ne peut pas envoyer chaque pixel en temps réel. On utilise généralement un **DMA** ou un **timer PWM** pour les couleurs.
- Approche simplifiée : résolution plus basse (ex. 160x120) et duplication des pixels.

**Matériel**

- Signaux R, G, B : sorties GPIO (ex. PA0, PA1, PA2) avec résistances pour DAC 3 bits.
- HSYNC : PA3
- VSYNC : PA4

**Framebuffer**

```c
#define VGA_WIDTH 160
#define VGA_HEIGHT 120
uint8_t framebuffer[VGA_HEIGHT][VGA_WIDTH]; // chaque octet contient 3 bits couleur
```

**Configuration des timers**

- Timer fréquence ligne (~31.7 µs) : interruption toutes les 32 µs.
- Timer comptage lignes : incrémenter `vga_line` dans l’ISR et gérer VSYNC selon le numéro de ligne.

```c
volatile uint16_t vga_line = 0;
volatile uint8_t vga_vsync = 0;

void TIM2_IRQHandler(void) {
    if (TIM2->SR & TIM_SR_UIF) {
        TIM2->SR &= ~TIM_SR_UIF;

        // Gestion HSYNC
        if (vga_line < VGA_HEIGHT) {
            // Zone visible : HSYNC haut et gestion pixels
        } else {
            // Blanking : générer impulsions
        }

        // Gestion VSYNC (525 lignes)
        vga_line++;
        if (vga_line == 480) {
            vga_vsync = 1; // début blanking vertical
        } else if (vga_line == 490) {
            GPIOA->ODR &= ~(1 << 4); // impulsion VSYNC bas
        } else if (vga_line == 492) {
            GPIOA->ODR |= (1 << 4);  // fin impulsion VSYNC
        } else if (vga_line >= 525) {
            vga_line = 0;
            vga_vsync = 0;
        }

        // Zone visible : envoyer ligne de pixels
        if (vga_line < VGA_HEIGHT) {
            for (int x = 0; x < VGA_WIDTH; x++) {
                uint8_t color = framebuffer[vga_line][x];
                GPIOA->ODR = (GPIOA->ODR & ~0x07) | (color & 0x07); // PA0-2
                delay_cycles(20); // simuler durée pixel
            }
        }
    }
}
```

Ce code est très simplifié et ne respecte pas les timings exacts. Pour une implémentation réaliste, il faudrait utiliser un timer matériel pour générer les signaux HSYNC et VSYNC, et un DMA pour envoyer les pixels. On pourrait aussi utiliser un module DSI ou LTDC, mais le STM32F401 n’en a pas.


---
<br>



### **Intégration avec FreeRTOS

On peut créer une tâche qui met à jour le framebuffer (par exemple dessiner une forme) tandis que l’affichage est géré par des interruptions (pour le VGA) ou par une tâche périodique (pour le TFT).

**Exemple pour le TFT : tâche d’affichage**

```c
void vTaskDisplay(void *pvParameters) {
    int x = 0, y = 0, dx = 1, dy = 1;
    uint16_t color = 0xF800; // rouge

    for (;;) {
        ILI9488_FillScreen(0x0000); // effacer
        // Dessiner un rectangle mobile
        for (int i = 0; i < 50; i++) {
            for (int j = 0; j < 50; j++) {
                ILI9488_DrawPixel(x+i, y+j, color);
            }
        }
        x += dx;
        y += dy;
        if (x >= 320-50) dx = -1;
        if (x <= 0) dx = 1;
        if (y >= 480-50) dy = -1;
        if (y <= 0) dy = 1;
        vTaskDelay(pdMS_TO_TICKS(50));
    }
}
```

**Exemple pour le VGA : mise à jour du framebuffer**

La tâche dessine dans le framebuffer, l’ISR lit ce buffer.

```c
void vTaskDraw(void *pvParameters) {
    int angle = 0;
    while (1) {
        // Dessiner une ligne qui tourne
        for (int x = 0; x < VGA_WIDTH; x++) {
            int y = VGA_HEIGHT/2 + (int)(50 * sinf(angle + x * 0.1f));
            if (y >= 0 && y < VGA_HEIGHT) {
                framebuffer[y][x] = 0x07; // blanc
            }
        }
        angle++;
        vTaskDelay(pdMS_TO_TICKS(50));
    }
}
```

**Projet simple : Afficher un message et une forme**

Sur TFT

On peut afficher un texte (en utilisant une petite police bitmap) et un cercle. L’implémentation de la police dépasse le cadre, mais on peut utiliser une bibliothèque comme u8g2 ou Adafruit GFX adaptée.

Sur VGA

On peut afficher un damier ou une mire de couleurs.











---
<br>


### **Liens connexes**


- [GPIO et Interruptions](../../stm32f4/gpio/index.md)
- [Timer et Interruption](../../stm32f4/timer/index.md)
- [Communication Série SPI](../../stm32f4/spi/index.md)
- [Machine d’État Fini (FSM)](../../technique-algos/fsm/index.md)
- [Optimisation de Transfert des Données avec DMA](../../stm32f4/dma/index.md)
- [Introduction pratique à freeRTOS](../../rtos/#introduction-a-freertos)

