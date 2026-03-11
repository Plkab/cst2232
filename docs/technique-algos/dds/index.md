# Synthèse Numérique Directe (DDS) avec DAC externe MCP4822

*Ir Paul S. Kabidu, M.Eng. <spaulkabidu@gmail.com>*
{: style="text-align: center;" }

---

[Accueil](../../#Accueil)

<br>
<br>



### **Introduction**

La **synthèse numérique directe (DDS)** est une technique de génération de signaux analogiques (sinus, triangle, carré, etc.) à partir d’une horloge de référence et d’une table d’onde. Elle permet de produire des fréquences très précises et facilement ajustables avec une grande résolution. On la trouve dans les générateurs de signaux, les synthétiseurs de fréquence, les instruments de mesure, etc.

Le STM32F401 ne dispose pas de convertisseur numérique-analogique (DAC) interne. Pour générer un signal analogique (sinus, rampe, tension variable), nous utiliserons un **DAC externe** communiquant via le bus SPI. Le **MCP4822** de Microchip est un DAC double canal 12 bits avec interface SPI, très simple d’utilisation. Il permet de générer des tensions analogiques de 0 à Vref (référence interne 2,048 V ou externe jusqu'à 5 V).

Dans ce chapitre, nous allons :

- Comprendre le principe de la DDS.
- Configurer le MCP4822 pour recevoir des données via SPI.
- Implémenter un générateur de signaux sinusoïdaux avec contrôle de fréquence.
- Intégrer le tout dans une tâche FreeRTOS pour une génération en temps réel.

---
<br>



### **Le DAC MCP4822**

**Caractéristiques générales**

- **Double canal** (A et B) indépendants  
- **Résolution 12 bits** (0 à 4095)  
- **Tension de référence interne** : 2,048 V (précision ±2 %)  
- Possibilité d'utiliser une **référence externe** (jusqu'à 5 V)  
- **Sortie rail-to-rail**  
- **Interface SPI** (mode 0,0 – CPOL = 0, CPHA = 0)  
- **Tension d'alimentation** : 2,7 V à 5,5 V  
- Sur la **Black Pill**, on utilise généralement **3,3 V**  
- **Faible consommation**

**Brochage**

| Broche | Nom   | Description |
|------|------|-------------|
| 1 | VDD | Alimentation (2,7-5,5 V) |
| 2 | CS | Chip Select (actif bas) |
| 3 | SCK | Horloge SPI |
| 4 | SDI | Data In (MOSI) |
| 5 | VOUTA | Sortie analogique canal A |
| 6 | VOUTB | Sortie analogique canal B |
| 7 | VREF | Tension de référence (si référence externe) |
| 8 | GND | Masse |

Sur la **Black Pill**, on connectera :

- **VDD → 3,3 V**  
- **GND → GND**  
- **CS → PA4** (GPIO utilisé pour la sélection logicielle)  
- **SCK → PA5** (SPI1_SCK)  
- **SDI → PA7** (SPI1_MOSI)  
- **VOUTA / VOUTB →** oscilloscope ou circuit cible  

La broche **VREF** peut être laissée **flottante** pour utiliser la **référence interne (2,048 V)**.

Si l’on souhaite une **pleine échelle différente**, on peut appliquer une **tension de référence externe** (maximum **5 V**).

**Principe de fonctionnement**

Le **MCP4822** reçoit une **trame SPI de 16 bits**.

Structure de la trame :

- **Bit 15** : sélection du canal  
  - `0` = canal **A**  
  - `1` = canal **B**

- **Bit 14** : gain  
  - `0` = gain **1** (Vref)  
  - `1` = gain **2** (2 × Vref)

  On met souvent ce bit à **1** pour utiliser la pleine échelle **4,096 V** avec la référence interne.

- **Bit 13** : shutdown  
  - `1` = sortie active  
  - `0` = sortie haute impédance

- **Bits 12-1** : valeur numérique **12 bits**

  Les données sont **justifiées à gauche** :
  
  - bits **12-1 de la trame**
  - correspondent aux bits **11-0 de la donnée**

- **Bit 0** : ignoré (toujours `0`)

**Construction du mot SPI**

En pratique, on construit un mot **uint16_t** avec :

- les **bits de contrôle**
- la **valeur décalée de 4 bits vers la gauche**

car les **bits 12-1 de la trame correspondent aux bits 15-4 du mot**.

Formule :

```c
word = (canal << 15) | (gain << 14) | (shutdown << 13) | ((value & 0xFFF) << 4)
```

Exemple Configuration :

- canal **A**
- **gain = 2** (bit14 = 1)
- **shutdown = 1**
- valeur **2048** (mi-échelle)

Calcul :

```c
word = (0<<15) | (1<<14) | (1<<13) | (2048<<4)
```
2048 << 4 = 32768 = 0x8000
```c
word = 0x6000 | 0x8000
```
```c
word = 0xE000
```
Le mot SPI transmis est donc : 0xE000

**Tension de sortie**

Avec la **référence interne 2,048 V** :

- **gain = 1** → pleine échelle = **2,048 V**
- **gain = 2** → pleine échelle = **4,096 V**

Si l’alimentation est **3,3 V**, la sortie ne pourra pas dépasser **3,3 V**.

Dans beaucoup d'applications avec la **Black Pill**, on utilise **gain = 1** pour rester dans les limites d'alimentation.

**Relation numérique → tension**

La tension de sortie est donnée par :
```markdown
\[
V_{out} =
V_{ref} \times gain \times \frac{D}{4096}
\]

avec :

- \(D\) : valeur numérique (**0 à 4095**)
- \(V_{ref}\) : tension de référence
- **gain** : facteur d'amplification interne
```

---
<br>



### **Configuration du SPI sur STM32F401**

Le module **SPI1** du **STM32F401** sera utilisé en **mode maître**, avec une fréquence d'horloge adaptée (par exemple **1 MHz**).

Les broches utilisées sont :

- **PA5** → SCK  
- **PA7** → MOSI  
- **PA4** → CS (géré en GPIO)

**Initialisation du SPI1**

```c
#include "stm32f4xx.h"

void SPI1_Init(void) {
    // 1. Activer les horloges GPIOA et SPI1
    RCC->AHB1ENR |= RCC_AHB1ENR_GPIOAEN;
    RCC->APB2ENR |= RCC_APB2ENR_SPI1EN;

    // 2. Configurer PA5 (SCK) et PA7 (MOSI) en alternate function AF5
    GPIOA->MODER &= ~((3U << (5*2)) | (3U << (7*2)));
    GPIOA->MODER |=  ((2U << (5*2)) | (2U << (7*2))); // 10 = Alternate function

    GPIOA->AFR[0] &= ~((0xF << (5*4)) | (0xF << (7*4)));
    GPIOA->AFR[0] |=  ((5 << (5*4)) | (5 << (7*4)));  // AF5 pour SPI1

    // 3. Configurer PA4 en sortie GPIO pour CS
    GPIOA->MODER |= (1U << (4*2));   // sortie
    GPIOA->ODR |= (1 << 4);          // CS = 1 par défaut (inactif)

    // 4. Configuration SPI1 : maître, 8 bits, CPOL=0, CPHA=0
    // fPCLK / 16 (≈ 1 MHz si APB2 = 84 MHz)

    SPI1->CR1 = SPI_CR1_MSTR | SPI_CR1_BR_2 | SPI_CR1_BR_1; // BR = 011 -> division par 16
    SPI1->CR1 |= SPI_CR1_SSM | SPI_CR1_SSI;                 // gestion logicielle du CS
    SPI1->CR1 |= SPI_CR1_SPE;                               // activation SPI
}
```

Explication

Les bits BR_2 et BR_1 donnent : 𝐵𝑅 = 011 soit une division par 16.
Avec APB2 = 84 MHz, la fréquence SPI est :

`fSCK​ = 84MHz​/16=5.25MHz`

Cette fréquence est acceptable pour le MCP4822, qui supporte jusqu’à 20 MHz.

On peut cependant choisir une division plus grande si l'on souhaite ralentir la communication.

Le mode SSM (Software Slave Management) avec SSI permet de désactiver la gestion matérielle du CS.
La broche PA4 sera donc pilotée manuellement par logiciel.

**Fonction d'émission 16 bits**

Le MCP4822 attend une trame de 16 bits.

Deux solutions existent :

- configurer le SPI en mode 16 bits
- rester en mode 8 bits et envoyer deux octets successifs

Nous choisissons ici le mode 8 bits, plus simple et compatible.

```c
void SPI1_Write16(uint16_t data) {

    while (!(SPI1->SR & SPI_SR_TXE));   // attendre buffer vide
    SPI1->DR = (data >> 8) & 0xFF;      // envoi octet poids fort

    while (!(SPI1->SR & SPI_SR_TXE));   // attendre buffer vide
    SPI1->DR = data & 0xFF;             // envoi octet poids faible

    while (SPI1->SR & SPI_SR_BSY);      // attendre fin transmission
}
```

Remarque

On peut aussi configurer le SPI en mode 16 bits (bit DFF dans CR1) et envoyer directement un uint16_t.

Le MCP4822 accepte les trames 16 bits, mais l'approche 8 bits est plus universelle et compatible avec davantage de périphériques SPI.

---
<br>



### **Fonction d'écriture sur le DAC**

```c
void MCP4822_Write(uint8_t channel, uint16_t value) {

    // Construire la trame
    uint16_t word = 0;

    word |= (channel << 15);        // canal 0 ou 1
    word |= (1 << 14);              // gain = 2
    word |= (1 << 13);              // shutdown = 1 (sortie active)
    word |= ((value & 0xFFF) << 4); // valeur 12 bits

    // Activer CS
    GPIOA->ODR &= ~(1 << 4);

    // Envoyer la trame SPI
    SPI1_Write16(word);

    // Désactiver CS
    GPIOA->ODR |= (1 << 4);
}
```

Remarque sur le gain

Avec la référence interne du MCP4822 : 𝑉𝑟𝑒𝑓=2.048
Si : gain = 2 la pleine échelle devient : 𝑉𝑜𝑢𝑡,𝑚𝑎𝑥=4.096
 
Cependant, si le circuit est alimenté en 3.3 V, la sortie ne pourra pas dépasser : 𝑉𝐷𝐷=3.3V

Dans beaucoup d'applications avec la Black Pill, on choisit donc : gain = 1 ce qui donne une pleine échelle : 𝑉𝑜𝑢𝑡,𝑚𝑎𝑥=2.048
 Le choix dépend donc de la plage de tension souhaitée.

---
<br>




### **Génération de signaux analogiques**

**Rampe (sawtooth)**

Le programme suivant génère une rampe de 0 à 4095 sur le canal A.

```c
#include "stm32f4xx.h"

void SPI1_Init(void);
void MCP4822_Write(uint8_t channel, uint16_t value);
void delayUs(uint32_t us);

int main(void) {
    uint16_t i = 0;
    SPI1_Init();

    while (1) {
        MCP4822_Write(0, i);   // canal A
        i++;
        delayUs(10);            // ajuste la fréquence de la rampe
    }
}
```

Remarque : La fonction delayUs peut être réalisée avec une boucle approximative, ou mieux avec un timer (SysTick). On donne ici une version simple :

```c
void delayUs(uint32_t us) {
    for (uint32_t i = 0; i < us * 16; i++) {} // approximation grossière
}
```

**Sinusoïde**

On utilise une table pré‑calculée de valeurs (par exemple 256 points). On génère la table à l'aide de mathématiques.

```c
#include <math.h>

#define TABLE_SIZE 256
uint16_t sineTable[TABLE_SIZE];

void buildSineTable(void) {
    for (int i = 0; i < TABLE_SIZE; i++) {
        double angle = 2 * M_PI * i / TABLE_SIZE;
        // Valeur centrée entre 0 et 4095 (offset 2048, amplitude 2048)
        sineTable[i] = (uint16_t)(2048 + 2047 * sin(angle));
    }
}
```

Dans la boucle principale, on envoie les valeurs successivement avec un délai pour régler la fréquence.

```c
int main(void) {
    int i = 0;
    SPI1_Init();
    buildSineTable();

    while (1) {
        MCP4822_Write(0, sineTable[i]);
        i++;
        if (i >= TABLE_SIZE) i = 0;
        delayUs(50); // ajuste la fréquence
    }
}
```

**Contrôle de la fréquence**

La fréquence du signal est donnée par f = 1 / (période × nombre de points). On peut utiliser un timer pour générer un déclenchement précis à la place de la boucle d'attente.

**Utilisation des deux canaux**

Pour utiliser le canal B, il suffit de passer channel = 1 dans MCP4822_Write. On peut générer deux signaux indépendants.

Exemple : rampe sur A et sinusoïde sur B.

```c
int main(void) {
    uint16_t ramp = 0;
    int sineIdx = 0;
    SPI1_Init();
    buildSineTable();

    while (1) {
        MCP4822_Write(0, ramp);
        MCP4822_Write(1, sineTable[sineIdx]);

        ramp++;
        sineIdx++;
        if (sineIdx >= TABLE_SIZE) sineIdx = 0;

        delayUs(20);
    }
}
```

Remarque : Les deux écritures se succèdent ; le CS est activé/désactivé pour chaque transaction. Le temps total pour les deux écritures doit être inférieur à la période d'échantillonnage pour ne pas déformer les signaux.

**Améliorations**

- Utilisation d'un timer pour le déclenchement : on peut configurer un timer (par exemple TIM2) pour générer une interruption périodique, et dans l'ISR mettre à jour la valeur du DAC. Cela libère le CPU.
- DMA : pour des formes d'onde complexes, on peut utiliser le DMA pour envoyer les données du tableau vers le SPI sans intervention du CPU.
- Filtrage : la sortie du DAC peut nécessiter un filtre passe‑bas pour lisser le signal (surtout pour les formes d'onde échantillonnées).

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

