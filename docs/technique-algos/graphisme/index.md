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

Le **ILI9488** est un contrôleur d’écran TFT très répandu, capable d’afficher 262 000 couleurs (RGB666) avec une résolution typique de 320x480. Il peut être piloté en mode SPI (série) ou parallèle. Nous utiliserons le mode SPI pour économiser les broches.

**Brochage**

| Fonction | Broche STM32 |
|----------|--------------|
| SCK      | PA5 (SPI1_SCK) |
| MOSI     | PA7 (SPI1_MOSI) |
| CS       | PA4 (sortie GPIO) |
| DC       | PA3 (sortie GPIO) – Data/Command |
| RST      | PA2 (sortie GPIO) – Reset |
| BL       | PA1 (sortie GPIO) – Backlight (optionnel) |

**Protocole SPI**

Le ILI9488 attend des commandes et des données via SPI. La broche DC indique si l’octet envoyé est une commande (DC=0) ou une donnée (DC=1). Les données sont généralement envoyées sur plusieurs octets (ex: 3 octets pour une couleur RGB666).

**Initialisation**

L’initialisation consiste à envoyer une séquence de commandes pour configurer le contrôleur (orientation, polarité, etc.). Voici une séquence typique (simplifiée) :

```c
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

Pour dessiner un pixel en RGB666 (18 bits), on doit envoyer 3 octets par pixel. On définit d’abord une fenêtre (zone) puis on envoie les données.

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

