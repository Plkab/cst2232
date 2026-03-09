# Synthèse Numérique Directe (DDS) avec DAC externe MCP4822

*Ir Paul S. Kabidu, M.Eng. <spaulkabidu@gmail.com>*
{: style="text-align: center;" }

---

[Accueil](../../#Accueil)

<br>
<br>



### **Introduction**

La **synthèse numérique directe (DDS)** est une technique de génération de signaux analogiques (sinus, triangle, carré, etc.) à partir d’une horloge de référence et d’une table d’onde. Elle permet de produire des fréquences très précises et facilement ajustables avec une grande résolution. On la trouve dans les générateurs de signaux, les synthétiseurs de fréquence, les instruments de mesure, etc.

Le STM32F401 ne dispose pas de convertisseur numérique-analogique (DAC) interne. Pour générer un signal analogique, nous utiliserons un **DAC externe** via le bus SPI. Le **MCP4822** de Microchip est un DAC double canal 12 bits avec interface SPI, très simple d’utilisation. Dans ce chapitre, nous allons :

- Comprendre le principe de la DDS.
- Configurer le MCP4822 pour recevoir des données via SPI.
- Implémenter un générateur de signaux sinusoïdaux avec contrôle de fréquence.
- Intégrer le tout dans une tâche FreeRTOS pour une génération en temps réel.

---
<br>



### **Principe de la DDS**

Un système DDS classique se compose de :

- Un **accumulateur de phase** (registre qui s’incrémente à chaque coup d’horloge).
- Une **table d’onde** (look-up table) contenant les échantillons d’une période du signal désiré.
- Un **convertisseur numérique-analogique** (DAC) qui transforme la valeur lue en tension.

La fréquence du signal de sortie est donnée par :

\[
f_{out} = \frac{M \cdot f_{clk}}{2^N}
\]

où :
- \(M\) est le pas d’incrémentation (mot de réglage de fréquence),
- \(f_{clk}\) est la fréquence d’horloge du système (cadence d’envoi au DAC),
- \(N\) est le nombre de bits de l’accumulateur de phase (ex: 32 bits).

En modifiant \(M\), on change la fréquence sans modifier la table d’onde. La résolution en fréquence est :

\[
\Delta f = \frac{f_{clk}}{2^N}
\]

---
<br>



### **Le DAC externe MCP4822**

Le **MCP4822** est un DAC double canal 12 bits avec sortie rail-to-rail. Il communique via SPI (mode 0,0) et nécessite une tension de référence (peut être interne ou externe). Caractéristiques :

- Résolution 12 bits (0 à 4095).
- Tension de sortie : 0 à \(V_{ref}\) (interne 2.048V ou externe jusqu’à 5V).
- Interface SPI simple : données sur 16 bits (bit de configuration + 12 bits de valeur).
- Temps d’établissement rapide (4.5 µs typ.).

**Trame SPI**

Les 16 bits sont formatés ainsi :

| Bit 15 | Bit 14 | Bit 13 | Bits 12-0 |
|--------|--------|--------|-----------|
| 0/1 (A/B) | 1 (GA) | 1 (SHDN) | Données 12 bits (justifiés à gauche) |

- **Bit 15** : sélection du canal (0 = canal A, 1 = canal B).
- **Bit 14** : GA = 1 pour utiliser la référence interne (x1), 0 pour x2.
- **Bit 13** : SHDN = 1 pour sortie active, 0 pour sortie haute impédance.
- **Bits 12-1** : valeur 12 bits (les bits 12-1 sont les bits de donnée, le bit 0 est ignoré car les données sont justifiées à gauche). En pratique, on envoie un uint16_t où les bits 15-4 sont la valeur 12 bits décalée de 4.

**Connexion au STM32**

On utilisera le SPI1 (par exemple) avec les broches :

- PA5 (SCLK)
- PA6 (MISO non utilisé ici)
- PA7 (MOSI)
- PA4 (CS) pour sélectionner le MCP4822.

---
<br>



### **Implémentation de la DDS**

Nous allons générer un signal sinusoïdal. Pour cela, nous créons une table d’onde contenant 256 échantillons d’une période de sinus (codés sur 12 bits). La résolution de phase est donc de 8 bits (2^8 = 256). L’accumulateur de phase sera sur 32 bits pour une bonne résolution en fréquence.

**Table d’onde (look-up table)**

```c
#define LUT_SIZE 256
uint16_t sinLUT[LUT_SIZE];

void generate_sin_lut(void) {
    for (int i = 0; i < LUT_SIZE; i++) {
        // Valeur entre 0 et 4095, centrée sur 2048 pour un sinus bipolaire
        // On génère un sinus entre 0 et 4095 (offset 2048)
        float val = sinf(2 * M_PI * i / LUT_SIZE);
        sinLUT[i] = (uint16_t)((val + 1.0f) * 2047.5f); // 0..4095
    }
}
```

**Structure DDS**

```c
typedef struct {
    uint32_t phase;         // accumulateur de phase courant
    uint32_t phase_increment; // pas de phase (M)
    uint16_t (*lut)[LUT_SIZE]; // pointeur vers la table
} DDS_Generator;
```

**Mise à jour de la phase et lecture de l’échantillon**

```c
uint16_t DDS_Update(DDS_Generator *dds) {
    dds->phase += dds->phase_increment;
    uint8_t index = (dds->phase >> 24) & 0xFF; // prend les 8 bits de poids fort
    return (*dds->lut)[index];
}
```

**Calcul du pas de phase**

Pour une fréquence d’échantillonnage  
fs (fréquence à laquelle on envoie les échantillons au DAC) et une fréquence de sortie désirée  
fout, avec un accumulateur sur 32 bits :

M = (fout × 2^32) / fs

En pratique, on utilise des **entiers 32 bits** pour éviter les flottants.

```c
// f_s = 100 kHz (période 10 µs) par exemple
uint32_t compute_phase_increment(float f_out, float f_s) {
    return (uint32_t)(f_out * (1LL << 32) / f_s);
}
```

---
<br>



### **Interface SPI avec le MCP4822**

**Initialisation SPI**

```c
void SPI1_Init(void) {
    RCC->AHB1ENR |= RCC_AHB1ENR_GPIOAEN;
    RCC->APB2ENR |= RCC_APB2ENR_SPI1EN;

    // PA5 (SCK), PA6 (MISO), PA7 (MOSI) en AF5
    GPIOA->MODER &= ~((3U << (5*2)) | (3U << (6*2)) | (3U << (7*2)));
    GPIOA->MODER |=  ((2U << (5*2)) | (2U << (6*2)) | (2U << (7*2)));
    GPIOA->AFR[0] &= ~((0xF << (5*4)) | (0xF << (6*4)) | (0xF << (7*4)));
    GPIOA->AFR[0] |=  ((5 << (5*4)) | (5 << (6*4)) | (5 << (7*4)));

    // PA4 en sortie GPIO pour CS
    GPIOA->MODER |= (1U << (4*2));
    GPIOA->ODR |= (1 << 4); // CS haut par défaut

    // Configuration SPI1 : maître, 8 bits, CPOL=0, CPHA=0, fPCLK/8 = 10.5 MHz (si 84 MHz)
    SPI1->CR1 = SPI_CR1_MSTR | SPI_CR1_BR_2 | SPI_CR1_BR_1; // BR = 110 -> /8
    SPI1->CR1 |= SPI_CR1_SSM | SPI_CR1_SSI; // gestion logicielle du CS
    SPI1->CR1 |= SPI_CR1_SPE;
}

void SPI1_CS_Low(void) {
    GPIOA->ODR &= ~(1 << 4);
}

void SPI1_CS_High(void) {
    GPIOA->ODR |= (1 << 4);
}

// Envoi d'un mot 16 bits
void SPI1_Transmit16(uint16_t data) {
    while (!(SPI1->SR & SPI_SR_TXE));
    SPI1->DR = data;
    while (!(SPI1->SR & SPI_SR_RXNE)); // attendre fin de transmission
    (void)SPI1->DR; // vide le buffer RX
}
```

**Envoi d’une valeur au DAC**

Pour le MCP4822, on construit le mot de 16 bits :

```c
void MCP4822_Write(uint8_t channel, uint16_t value) {
    // value doit être sur 12 bits (0-4095)
    uint16_t word = (channel ? 0x8000 : 0x0000) | // bit 15: canal
                    0x4000 |                       // bit 14: GA = 1 (référence interne x1)
                    0x2000 |                       // bit 13: SHDN = 1 (sortie active)
                    ((value & 0xFFF) << 4);        // valeur décalée de 4 bits

    SPI1_CS_Low();
    SPI1_Transmit16(word);
    SPI1_CS_High();
}
```

---
<br>



### **Intégration avec FreeRTOS**

Nous allons créer une tâche dédiée à la génération du signal. Pour une fréquence d’échantillonnage stable, on peut utiliser un timer matériel pour déclencher la tâche à intervalles réguliers, ou simplement utiliser `vTaskDelayUntil` si la fréquence n’est pas trop élevée.

**Option 1 : avec timer et sémaphore**

Un timer génère une interruption à la fréquence d’échantillonnage (par exemple 100 kHz). L’ISR donne un sémaphore à la tâche DDS.

```c
SemaphoreHandle_t xDDS_Semaphore;

void TIM2_IRQHandler(void) {
    BaseType_t xWoken = pdFALSE;
    if (TIM2->SR & TIM_SR_UIF) {
        TIM2->SR &= ~TIM_SR_UIF;
        xSemaphoreGiveFromISR(xDDS_Semaphore, &xWoken);
        portYIELD_FROM_ISR(xWoken);
    }
}
```

**Option 2 : avec vTaskDelayUntil**

Si la fréquence d’échantillonnage est modérée (par exemple 1 kHz), on peut utiliser `vTaskDelayUntil`. Pour 100 kHz, la période est 10 µs, trop petite pour FreeRTOS (le tick est généralement 1 ms). On utilisera donc un timer matériel.

**Tâche DDS**

```c
void vTaskDDS(void *pvParameters) {
    DDS_Generator dds;
    dds.phase = 0;
    dds.phase_increment = compute_phase_increment(1000.0f, 100000.0f); // 1 kHz
    dds.lut = &sinLUT;

    for (;;) {
        xSemaphoreTake(xDDS_Semaphore, portMAX_DELAY);
        uint16_t sample = DDS_Update(&dds);
        MCP4822_Write(0, sample); // canal A
    }
}
```

**Configuration du timer pour 100 kHz**

```c
void Timer_Init_100kHz(void) {
    RCC->APB1ENR |= RCC_APB1ENR_TIM2EN;
    TIM2->PSC = 84 - 1;        // 1 MHz (si APB1 = 84 MHz)
    TIM2->ARR = 10 - 1;         // 100 kHz (1 MHz / 10 = 100 kHz)
    TIM2->DIER |= TIM_DIER_UIE;
    NVIC_SetPriority(TIM2_IRQn, 5);
    NVIC_EnableIRQ(TIM2_IRQn);
    TIM2->CR1 |= TIM_CR1_CEN;
}
```

---
<br>




### **Projet : Générateur de sinus contrôlé par potentiomètre** {#projet-dds-pot}
Objectif : Lire un potentiomètre sur PA0 (ADC), en déduire une fréquence (par exemple de 100 Hz à 5 kHz), et générer un signal sinusoïdal correspondant via la DDS. Afficher la fréquence sur UART.

Matériel :

- STM32F401 (Black Pill)
- MCP4822 + ampli (éventuellement)
- Potentiomètre 10 kΩ
- Câble USB pour l’affichage série

Code additionnel (intégration avec les chapitres précédents)

```c
void vTaskADCReader(void *pvParameters) {
    TickType_t xLastWakeTime = xTaskGetTickCount();
    const TickType_t xPeriod = pdMS_TO_TICKS(100); // lecture toutes les 100 ms
    uint16_t adc;
    float freq;

    for (;;) {
        vTaskDelayUntil(&xLastWakeTime, xPeriod);
        adc = ADC_Read();
        // Conversion en fréquence (par exemple 100 Hz à 5000 Hz)
        freq = 100.0f + (adc * (5000.0f - 100.0f) / 4095.0f);
        // Calculer le nouveau pas de phase pour la tâche DDS
        // On pourrait utiliser une file pour communiquer avec la tâche DDS
    }
}
```

Pour communiquer la nouvelle fréquence à la tâche DDS, on peut utiliser une file ou une variable protégée par mutex. Dans la tâche DDS, on lirait la fréquence mise à jour périodiquement.


---
<br>


### **Liens connexes**


- [GPIO et Interruptions](../../stm32f4/gpio/index.md)
- [Timer et Interruption](../../stm32f4/timer/index.md)
- [Acquisition Analogique via ADC](../../stm32f4/adc/index.md)
- [Génération des signaux PWM](../../stm32f4/pwm/index.md)
- [Communication Série USART](../../stm32f4/usart/index.md)
- [Communication Série I2C](../../stm32f4/i2c/index.md)
- [Machine d’État Fini (FSM)](../../technique-algos/fsm/index.md)
- [Optimisation de Transfert des Données avec DMA](../../stm32f4/dma/index.md)
- [Filtres Numériques](../../technique-algos/filtre/index.md)
- [Introduction pratique à freeRTOS](../../rtos/#introduction-a-freertos)

