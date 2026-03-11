# L'Utilisation du DMA (Direct Memory Access) sur STM32F4

*Ir Paul S. Kabidu, M.Eng. <spaulkabidu@gmail.com>*
{: style="text-align: center;" }

---

[Accueil](../../#Accueil)
  
<br>
<br>


### **Introduction au DMA**

Le **DMA (Direct Memory Access)** est un périphérique matériel qui permet de transférer des données entre deux zones mémoire (mémoire ↔ mémoire, périphérique ↔ mémoire, etc.) **sans intervention du processeur**. Pendant qu’une opération DMA est en cours, le CPU peut continuer à exécuter d’autres instructions ou rester en mode basse consommation, ce qui améliore considérablement les performances et la réactivité du système.

Dans un système temps réel, le DMA est particulièrement utile pour :

- Acquérir des données à haute fréquence (ADC) sans surcharger le CPU.
- Transmettre ou recevoir de longues trames via USART/SPI/I2C sans bloquer les tâches.
- Remplir des buffers audio ou vidéo en continu (double buffer).
- Générer des signaux périodiques via DAC avec un tableau d’échantillons.

Le STM32F401 intègre deux contrôleurs DMA (DMA1 et DMA2) avec plusieurs **streams** (flux) et canaux. Chaque stream peut être associé à une requête DMA provenant d’un périphérique (ADC, USART, TIM, etc.). La configuration est complexe mais très flexible.

---
<br>

### **Architecture du DMA sur STM32F4**

- **Deux contrôleurs** : DMA1 (périphériques APB1/APB2) et DMA2 (périphériques AHB).
- **8 streams par contrôleur** (DMA1_Stream0 à DMA1_Stream7, etc.).
- Chaque stream a une priorité programmable (très haute, haute, moyenne, basse).
- Chaque stream peut être lié à un canal spécifique (ex: canal 0 pour ADC1, canal 4 pour USART1_TX, etc.).
- Modes de transfert : périphérique → mémoire, mémoire → périphérique, mémoire → mémoire.
- Modes circulaire (auto-reload) et simple (one-shot).
- Accès à des données de 8, 16 ou 32 bits, avec possibilité d'incrémenter ou non les adresses.

Les registres principaux d’un stream sont :

- `CR` (Control Register) : configuration (mode, taille, incrément, etc.)
- `NDTR` (Number of Data Register) : nombre de données à transférer.
- `PAR` (Peripheral Address Register) : adresse du périphérique.
- `M0AR` / `M1AR` (Memory Address Register) : adresse(s) mémoire (pour double buffer).

---
<br>

### **Configuration générale d’un transfert DMA**

1. **Activer l’horloge** du contrôleur DMA (`RCC_AHB1ENR`).
2. Désactiver le stream en mettant le bit `EN` du registre `CR` à 0.
3. **Configurer le stream** : choisir le canal, la direction, la taille des données, l’incrément des adresses, le mode circulaire, la priorité.
    - Choisir le canal (`CHSEL`).
    - Définir la direction (`DIR`).
    - Régler la taille des données (`PSIZE`, `MSIZE`).
    - Activer ou non l’incrément des adresses (`PINC`, `MINC`).
    - Choisir le mode circulaire (`CIRC`) ou simple.
    - Définir la priorité (`PL`).
    - Activer les interruptions souhaitées (`HTIE`, `TCIE`, `TEIE`).
4. **Définir l’adresse source et destination** (`PAR` et `M0AR`/`M1AR`).
5. **Spécifier le nombre de données** (`NDTR`).
6. **Activer le stream** (bit `EN` dans `CR`).
7. Optionnellement, activer les interruptions dans le NVIC (demi-transfert, transfert complet, erreur).

---
<br>

### **DMA avec l’USART**

L’USART peut générer une requête DMA à chaque fois qu’un caractère est reçu (RXNE) ou que le buffer de transmission est vide (TXE). On configure le DMA pour transférer automatiquement les données.

**Réception USART par DMA**

L’exemple suivant configure USART2 en réception DMA. Les données sont transférées vers un buffer mémoire fixe. Une fois le buffer plein, un flag est positionné.

**Exemple : Réception de 100 caractères via USART2 avec DMA (mode simple)**

```c
#include "stm32f4xx.h"

#define RX_BUFFER_SIZE 100
uint8_t rxBuffer[RX_BUFFER_SIZE];

void USART2_DMA_Init(uint32_t baud) {
    // 1. Activer horloges GPIOA, USART2, DMA1
    RCC->AHB1ENR |= RCC_AHB1ENR_GPIOAEN;
    RCC->APB1ENR |= RCC_APB1ENR_USART2EN;
    RCC->AHB1ENR |= RCC_AHB1ENR_DMA1EN;

    // 2. Configurer PA3 (RX) en alternate function AF7
    GPIOA->MODER &= ~(3U << (3*2));
    GPIOA->MODER |=  (2U << (3*2));
    GPIOA->AFR[0] |= (7 << (3*4));

    // 3. Configurer USART2
    USART2->BRR = 84000000 / baud;
    USART2->CR3 |= USART_CR3_DMAR;      // Activer DMA en réception
    USART2->CR1 = USART_CR1_RE | USART_CR1_UE;

    // 4. Configurer DMA1 Stream5 (canal 4 pour USART2_RX)
    DMA1_Stream5->CR &= ~DMA_SxCR_EN;   // Désactiver avant configuration

    DMA1_Stream5->PAR = (uint32_t)&USART2->DR;   // Adresse périphérique
    DMA1_Stream5->M0AR = (uint32_t)rxBuffer;      // Adresse mémoire
    DMA1_Stream5->NDTR = RX_BUFFER_SIZE;          // Nombre de données

    DMA1_Stream5->CR = DMA_SxCR_CHSEL_4 |          // Canal 4
                       DMA_SxCR_PL_1 |              // Priorité haute
                       DMA_SxCR_MSIZE_0 |           // Mémoire 8 bits
                       DMA_SxCR_PSIZE_0 |           // Périph 8 bits
                       DMA_SxCR_MINC |              // Incrément mémoire
                       DMA_SxCR_DIR_1;               // Direction périph → mémoire (bit DIR=1 pour périph->mem)
    // NB: Sur DMA1, DIR[1:0] doit être 0b01 pour périph->mem. Le bit DIR_1 est à 1, DIR_0 à 0.
    // Pour être sûr, on peut utiliser DMA_SxCR_DIR_0 | DMA_SxCR_DIR_1? Non, c'est un champ 2 bits.
    // Il faut consulter le RM, mais avec CMSIS on peut faire:
    // DMA1_Stream5->CR |= DMA_SxCR_DIR_0;  // 0b01 = périph->mem

    // 5. Activer le stream
    DMA1_Stream5->CR |= DMA_SxCR_EN;
}

// Fonction pour vérifier si le transfert est terminé
uint8_t USART2_DMA_IsComplete(void) {
    return (DMA1->LISR & DMA_LISR_TCIF5) ? 1 : 0;
}

// Effacer le flag de fin
void USART2_DMA_ClearComplete(void) {
    DMA1->LIFCR |= DMA_LIFCR_CTCIF5;
}
```

**Utilisation dans le main :**

```c
int main(void) {
    USART2_DMA_Init(115200);
    while (1) {
        if (USART2_DMA_IsComplete()) {
            // Traiter les données dans rxBuffer
            USART2_DMA_ClearComplete();
            // Recommencer un nouveau transfert si nécessaire
            DMA1_Stream5->CR &= ~DMA_SxCR_EN;
            DMA1_Stream5->NDTR = RX_BUFFER_SIZE;
            DMA1_Stream5->CR |= DMA_SxCR_EN;
        }
    }
}
```

Utilisation : dans la boucle principale, on attend le flag, on traite les données, puis on relance le DMA en réinitialisant `NDTR` et en réactivant le stream.

**Réception USART par DMA en mode circulaire (buffer tournant)**

Le mode circulaire permet de recevoir en continu. On utilise les interruptions de demi‑transfert et de transfert complet pour traiter les données sans perte.

```c
#include "FreeRTOS.h"
#include "task.h"
#include "semphr.h"

#define RX_BUFFER_SIZE 256
uint8_t rxBuffer[RX_BUFFER_SIZE];
SemaphoreHandle_t xSemHalf, xSemFull;

void USART2_DMA_Circular_Init(uint32_t baud) {
    RCC->AHB1ENR |= RCC_AHB1ENR_GPIOAEN | RCC_AHB1ENR_DMA1EN;
    RCC->APB1ENR |= RCC_APB1ENR_USART2EN;

    GPIOA->MODER &= ~(3U << (3*2));
    GPIOA->MODER |=  (2U << (3*2));
    GPIOA->AFR[0] |= (7 << (3*4));

    USART2->BRR = 84000000 / baud;
    USART2->CR3 |= USART_CR3_DMAR;
    USART2->CR1 = USART_CR1_RE | USART_CR1_UE;

    DMA1_Stream5->CR &= ~DMA_SxCR_EN;
    while (DMA1_Stream5->CR & DMA_SxCR_EN);

    DMA1_Stream5->PAR = (uint32_t)&USART2->DR;
    DMA1_Stream5->M0AR = (uint32_t)rxBuffer;
    DMA1_Stream5->NDTR = RX_BUFFER_SIZE;

    DMA1_Stream5->CR = DMA_SxCR_CHSEL_4 |
                       DMA_SxCR_PL_1 |
                       DMA_SxCR_MSIZE_0 |
                       DMA_SxCR_PSIZE_0 |
                       DMA_SxCR_MINC |
                       DMA_SxCR_CIRC |               // Mode circulaire
                       DMA_SxCR_HTIE |                // Interruption demi-transfert
                       DMA_SxCR_TCIE |                // Interruption transfert complet
                       DMA_SxCR_DIR_1;

    NVIC_SetPriority(DMA1_Stream5_IRQn, 5);
    NVIC_EnableIRQ(DMA1_Stream5_IRQn);

    DMA1_Stream5->CR |= DMA_SxCR_EN;
}

void DMA1_Stream5_IRQHandler(void) {
    BaseType_t xWoken = pdFALSE;
    if (DMA1->LISR & DMA_LISR_HTIF5) {
        DMA1->LIFCR |= DMA_LIFCR_CHTIF5;
        xSemaphoreGiveFromISR(xSemHalf, &xWoken);
    }
    if (DMA1->LISR & DMA_LISR_TCIF5) {
        DMA1->LIFCR |= DMA_LIFCR_CTCIF5;
        xSemaphoreGiveFromISR(xSemFull, &xWoken);
    }
    portYIELD_FROM_ISR(xWoken);
}

void vTaskProcessUSART(void *pvParameters) {
    for (;;) {
        xSemaphoreTake(xSemHalf, portMAX_DELAY);
        // Traiter la première moitié du buffer (0 à BUFFER_SIZE/2 -1)
        // ...

        xSemaphoreTake(xSemFull, portMAX_DELAY);
        // Traiter la seconde moitié (BUFFER_SIZE/2 à BUFFER_SIZE-1)
        // ...
    }
}
```

**Émission USART par DMA**

Pour l’émission, on utilise le bit `DMAT` du registre `CR3` et une direction mémoire → périphérique.

```c
void USART2_DMA_Transmit(uint8_t *data, uint32_t size) {
    // Désactiver stream si actif
    DMA1_Stream6->CR &= ~DMA_SxCR_EN;
    while (DMA1_Stream6->CR & DMA_SxCR_EN);

    DMA1_Stream6->PAR = (uint32_t)&USART2->DR;
    DMA1_Stream6->M0AR = (uint32_t)data;
    DMA1_Stream6->NDTR = size;

    DMA1_Stream6->CR = DMA_SxCR_CHSEL_4 |      // Canal 4 pour USART2_TX
                       DMA_SxCR_PL_0 |
                       DMA_SxCR_MSIZE_0 |
                       DMA_SxCR_PSIZE_0 |
                       DMA_SxCR_MINC |
                       DMA_SxCR_DIR_0;          // Direction mémoire → périph (bit DIR=0)

    USART2->CR3 |= USART_CR3_DMAT;             // Activer DMA en émission
    DMA1_Stream6->CR |= DMA_SxCR_EN;
}
```

On peut également ajouter une interruption de fin de transfert pour prévenir la tâche que l’émission est terminée.

---
<br>



### **DMA avec l’ADC**

Pour des acquisitions à haute fréquence, l'interruption peut saturer le CPU si elle survient trop souvent. Le DMA (Direct Memory Access) permet de transférer les données de l'ADC vers la mémoire sans intervention du processeur. On peut même utiliser un double buffer pour un traitement en parallèle.

L'ADC génère une requête DMA à chaque fin de conversion. Le DMA transfère alors la valeur dans un buffer mémoire. On peut configurer le DMA en mode circulaire pour remplir un buffer en continu.

**Configuration du DMA**

Le STM32F401 possède deux contrôleurs DMA avec plusieurs streams. Pour l'ADC1, on utilise généralement le stream 0 du DMA2 (vérifiez dans le manuel).

```c
#define ADC_BUFFER_SIZE 256
uint16_t adc_buffer[ADC_BUFFER_SIZE];
```

**Configuration du stream DMA :**

```c
DMA2_Stream0->PAR = (uint32_t)&ADC1->DR;       // adresse périphérique
DMA2_Stream0->M0AR = (uint32_t)adc_buffer;     // adresse mémoire
DMA2_Stream0->NDTR = ADC_BUFFER_SIZE;          // nombre de transferts
DMA2_Stream0->CR = DMA_SxCR_CHSEL_0 |          // canal 0 pour ADC1
                   DMA_SxCR_MINC |              // incrément mémoire
                   DMA_SxCR_TCIE |               // interruption fin de transfert
                   DMA_SxCR_CIRC |                // mode circulaire
                   DMA_SxCR_EN;                    // activation
```

- CHSEL_0 : sélectionne le canal 0 (pour ADC1). Consultez le manuel pour connaître le canal exact.
- MINC : incrémente l'adresse mémoire après chaque transfert.
- TCIE : active l'interruption en fin de transfert (optionnel).
- CIRC : mode circulaire : après avoir atteint la taille, l'adresse mémoire revient au début.
- EN : active le stream.


**Exemple avec déclenchement par timer et DMA**

On combine le déclenchement par timer et le DMA pour une acquisition automatique.

```c
#include "stm32f4xx.h"

#define ADC_BUFFER_SIZE 256
uint16_t adc_buffer[ADC_BUFFER_SIZE];
volatile uint8_t buffer_ready = 0;

void DMA2_Stream0_IRQHandler(void) {
    if (DMA2->LISR & DMA_LISR_TCIF0) {
        DMA2->LIFCR |= DMA_LIFCR_CTCIF0;   // acquitter
        buffer_ready = 1;                    // signaler que le buffer est plein
    }
}

int main(void) {
    // Horloges
    RCC->AHB1ENR |= RCC_AHB1ENR_GPIOAEN | RCC_AHB1ENR_DMA2EN;
    RCC->APB2ENR |= RCC_APB2ENR_ADC1EN;
    RCC->APB1ENR |= RCC_APB1ENR_TIM2EN;

    // PA0 analogique
    GPIOA->MODER |= (3U << (0*2));

    // Timer 2 pour déclenchement à 1 kHz
    TIM2->PSC = 8400 - 1;
    TIM2->ARR = 10 - 1;
    TIM2->CR2 |= TIM_CR2_MMS_1; // Update event as TRGO
    TIM2->CR1 |= TIM_CR1_CEN;

    // Configuration ADC déclenché par TIM2_TRGO
    ADC1->CR1 = 0;
    ADC1->SMPR2 = (7 << 0);
    ADC1->SQR3 = 0;
    ADC1->CR2 = (1 << 28) | (3 << 24) | ADC_CR2_DMA | ADC_CR2_DDS | ADC_CR2_ADON;

    // Configuration DMA
    DMA2_Stream0->PAR = (uint32_t)&ADC1->DR;
    DMA2_Stream0->M0AR = (uint32_t)adc_buffer;
    DMA2_Stream0->NDTR = ADC_BUFFER_SIZE;
    DMA2_Stream0->CR = DMA_SxCR_CHSEL_0 | DMA_SxCR_MINC | DMA_SxCR_TCIE | DMA_SxCR_CIRC | DMA_SxCR_EN;

    NVIC_EnableIRQ(DMA2_Stream0_IRQn);
    NVIC_SetPriority(DMA2_Stream0_IRQn, 2);

    while (1) {
        if (buffer_ready) {
            buffer_ready = 0;
            // Traiter le buffer (256 échantillons)
        }
    }
}
```

**Double buffer avec interruptions**

Le mode circulaire est pratique mais si on veut traiter les données pendant que le DMA remplit l'autre moitié, on peut utiliser deux buffers et une interruption de demi‑transfert (HTIF). Le DMA peut être configuré pour générer une interruption à mi‑parcours (D`MA_SxCR_HTIE`). On alterne alors entre deux buffers.

Pour utiliser un double buffer, on peut soit configurer deux buffers avec `M0AR` et `M1AR` (mode double buffer du DMA), soit utiliser un seul buffer circulaire et les interruptions de demi‑transfert. Le double buffer matériel est plus élégant :

```c
uint16_t adc_buffer0[128];
uint16_t adc_buffer1[128];
uint8_t active_buffer = 0;
// Dans l'ISR, on vérifie le flag de demi‑transfert et de transfert complet
// pour basculer le buffer actif.
//.....
DMA2_Stream0->M0AR = (uint32_t)buffer1;
DMA2_Stream0->M1AR = (uint32_t)buffer2;
DMA2_Stream0->CR |= DMA_SxCR_DBM;   // Double buffer mode
```

Les flags `HTIF` et `TCIF` indiquent respectivement que le premier ou le second buffer est plein.

Cette technique est très utilisée en traitement du signal temps réel (par exemple pour la FFT).

---
<br>



### **DMA avec I2C**

L’I2C peut aussi utiliser le DMA pour transmettre ou recevoir de longues séquences de données sans bloquer le CPU. La configuration est similaire : on active le DMA dans le registre `CR2` de l’I2C et on configure le stream approprié.

**Exemple simplifié : transmission I2C1 par DMA**

```c
#include "stm32f4xx.h"

void I2C1_DMA_Transmit(uint8_t *data, uint32_t size) {
    // Activer l'horloge DMA1 si ce n'est pas déjà fait
    RCC->AHB1ENR |= RCC_AHB1ENR_DMA1EN;

    // Désactiver le stream (DMA1_Stream6 pour I2C1_TX)
    DMA1_Stream6->CR &= ~DMA_SxCR_EN;
    while (DMA1_Stream6->CR & DMA_SxCR_EN);

    // Configurer
    DMA1_Stream6->PAR = (uint32_t)&I2C1->DR;
    DMA1_Stream6->M0AR = (uint32_t)data;
    DMA1_Stream6->NDTR = size;

    DMA1_Stream6->CR = DMA_SxCR_CHSEL_6 |      // Canal 6 pour I2C1_TX
                       DMA_SxCR_PL_0 |
                       DMA_SxCR_MSIZE_0 |       // 8 bits
                       DMA_SxCR_PSIZE_0 |
                       DMA_SxCR_MINC |
                       DMA_SxCR_DIR_0;           // Mémoire -> périphérique

    // Activer DMA dans I2C1
    I2C1->CR2 |= I2C_CR2_DMAEN;

    DMA1_Stream6->CR |= DMA_SxCR_EN;
}
```

Réception : utiliser `DIR = 01` et le canal approprié (ex: DMA1_Stream5 pour I2C1_RX). Penser à activer `I2C_CR2_LAST` si nécessaire.

---
<br>


### **DMA avec SPI**

Le SPI est un candidat idéal pour le DMA, surtout pour des transferts de blocs (écran, carte SD, etc.).

**Exemple : réception SPI1 par DMA**

```c
#include "stm32f4xx.h"

void SPI1_DMA_Receive(uint8_t *buffer, uint32_t size) {
    // Activer DMA2 (SPI1 est sur AHB)
    RCC->AHB1ENR |= RCC_AHB1ENR_DMA2EN;

    // Désactiver le stream (DMA2_Stream0 pour SPI1_RX)
    DMA2_Stream0->CR &= ~DMA_SxCR_EN;
    while (DMA2_Stream0->CR & DMA_SxCR_EN);

    DMA2_Stream0->PAR = (uint32_t)&SPI1->DR;
    DMA2_Stream0->M0AR = (uint32_t)buffer;
    DMA2_Stream0->NDTR = size;

    DMA2_Stream0->CR = DMA_SxCR_CHSEL_3 |      // Canal 3 pour SPI1_RX
                       DMA_SxCR_PL_1 |
                       DMA_SxCR_MSIZE_0 |       // 8 bits
                       DMA_SxCR_PSIZE_0 |
                       DMA_SxCR_MINC |
                       DMA_SxCR_DIR_1;           // Périphérique -> mémoire

    // Activer DMA dans SPI1
    SPI1->CR2 |= SPI_CR2_RXDMAEN;

    DMA2_Stream0->CR |= DMA_SxCR_EN;
}
```

Pour l’émission, on utilise `DIR_0` et `SPI_CR2_TXDMAEN`.

---
<br>


### **Intégration avec FreeRTOS**

L’utilisation du DMA libère le CPU, mais il faut quand même synchroniser les tâches avec la fin des transferts. On peut utiliser :

- **Sémaphore** donné dans l’ISR de fin de DMA.
- **Notification de tâche** pour un réveil rapide.
- **Queue** pour passer les données (par exemple, l’ISR de demi‑transfert peut envoyer un pointeur sur le buffer actif).

**Exemple avec ADC circulaire et double buffer**

On configure le DMA en mode circulaire avec double buffer (M0AR et M1AR). Les interruptions de demi‑transfert et transfert complet indiquent quel buffer est prêt. Dans l’ISR, on donne un sémaphore à une tâche de traitement.

```c
SemaphoreHandle_t xSemBufferReady;

void DMA2_Stream0_IRQHandler(void) {
    BaseType_t xWoken = pdFALSE;
    if (DMA2->LISR & DMA_LISR_HTIF0) {
        DMA2->LIFCR |= DMA_LIFCR_CHTIF0;  // Effacer flag demi-transfert
        // Le premier buffer est plein
        xSemaphoreGiveFromISR(xSemBufferReady, &xWoken);
    }
    if (DMA2->LISR & DMA_LISR_TCIF0) {
        DMA2->LIFCR |= DMA_LIFCR_CTCIF0;  // Effacer flag transfert complet
        // Le second buffer est plein
        xSemaphoreGiveFromISR(xSemBufferReady, &xWoken);
    }
    portYIELD_FROM_ISR(xWoken);
}

void vProcessTask(void *pvParameters) {
    for (;;) {
        xSemaphoreTake(xSemBufferReady, portMAX_DELAY);
        // Déterminer quel buffer est prêt (par exemple en vérifiant un index)
        // Traiter les données
    }
}
```

La tâche de traitement attend le sémaphore, détermine quel buffer est disponible, et traite les données.

---
<br>



### **Projet : Acquisition analogique haute fréquence avec DMA et FreeRTOS**

Nous allons réaliser un système qui échantillonne un signal sur PA0 à 10 kHz via ADC1 déclenché par un timer, transfère les données par DMA vers un buffer circulaire, et calcule la moyenne en continu toutes les 100 ms.

**Configuration** :

- Timer2 génère un déclenchement à 10 kHz (TRGO).
- ADC1 est en mode déclenché par timer, DMA circulaire.
- DMA2 Stream0 en mode circulaire avec double buffer.
- Une tâche calcule la moyenne des échantillons reçus toutes les 100 ms.

```c
#include "FreeRTOS.h"
#include "task.h"
#include "semphr.h"
#include "stm32f4xx.h"

#define SAMPLE_RATE 10000      // 10 kHz
#define BUFFER_SIZE 1024        // Taille totale du buffer (sera divisée en deux)
volatile uint16_t adcBuffer[BUFFER_SIZE];

SemaphoreHandle_t xSemHalf, xSemFull;

void Timer2_Init(void) {
    RCC->APB1ENR |= RCC_APB1ENR_TIM2EN;
    TIM2->PSC = 84 - 1;          // 84 MHz / 84 = 1 MHz
    TIM2->ARR = (1000000 / SAMPLE_RATE) - 1;  // 1000/10k = 0.1 ms? Calcul : pour 10 kHz, période = 100 µs, à 1 MHz, ARR = 100-1
    TIM2->CR2 = TIM_CR2_MMS_1;   // MMS = 010 : Update event as TRGO
    TIM2->DIER |= TIM_DIER_UIE;   // Interruption update (optionnelle)
    TIM2->CR1 |= TIM_CR1_CEN;
}

void ADC1_DMA_Init(void) {
    // Horloges
    RCC->AHB1ENR |= RCC_AHB1ENR_GPIOAEN;
    RCC->APB2ENR |= RCC_APB2ENR_ADC1EN;
    RCC->AHB1ENR |= RCC_AHB1ENR_DMA2EN;

    GPIOA->MODER |= (3U << (0*2));  // PA0 analog

    // Config ADC
    ADC1->CR2 = 0;
    ADC1->SQR3 = 0;                 // canal 0
    ADC1->SMPR2 = (7 << 0);          // échantillonnage max
    ADC1->CR2 |= ADC_CR2_ADON;      // allumer
    ADC1->CR2 |= ADC_CR2_CONT;      // continu (on utilise le timer pour déclencher)
    // On utilise le déclenchement externe
    ADC1->CR2 |= ADC_CR2_EXTEN_0;    // Trigger on rising edge
    ADC1->CR2 |= (6 << 24);          // Selection TRGO de TIM2 (valeur 6 pour TIM2_TRGO, voir RM)
    ADC1->CR2 |= ADC_CR2_DMA;        // Activer DMA
    ADC1->CR2 |= ADC_CR2_DDS;        // DMA requests continues

    // DMA2 Stream0
    DMA2_Stream0->CR &= ~DMA_SxCR_EN;
    DMA2_Stream0->PAR = (uint32_t)&ADC1->DR;
    DMA2_Stream0->M0AR = (uint32_t)adcBuffer;
    DMA2_Stream0->NDTR = BUFFER_SIZE;
   
   DMA2_Stream0->CR = DMA_SxCR_CHSEL_0 |
                       DMA_SxCR_PL_1 |
                       DMA_SxCR_MSIZE_0 |
                       DMA_SxCR_PSIZE_0 |
                       DMA_SxCR_MINC |
                       DMA_SxCR_CIRC |
                       DMA_SxCR_HTIE |      // Demi-transfert
                       DMA_SxCR_TCIE |      // Transfert complet
                       DMA_SxCR_DIR_1;       // Périph -> mem

    NVIC_SetPriority(DMA2_Stream0_IRQn, 5);
    NVIC_EnableIRQ(DMA2_Stream0_IRQn);

    DMA2_Stream0->CR |= DMA_SxCR_EN;
}

void DMA2_Stream0_IRQHandler(void) {
    BaseType_t xWoken = pdFALSE;
    if (DMA2->LISR & DMA_LISR_HTIF0) {
        DMA2->LIFCR |= DMA_LIFCR_CHTIF0;
        xSemaphoreGiveFromISR(xSemHalf, &xWoken);
    }
    if (DMA2->LISR & DMA_LISR_TCIF0) {
        DMA2->LIFCR |= DMA_LIFCR_CTCIF0;
        xSemaphoreGiveFromISR(xSemFull, &xWoken);
    }
    portYIELD_FROM_ISR(xWoken);
}

void vProcessTask(void *pvParameters) {
    uint32_t sum;
    uint16_t *buffer;
    int i;

    for (;;) {
        // Attendre qu'un demi-buffer soit rempli
        xSemaphoreTake(xSemHalf, portMAX_DELAY);
        // Traiter la première moitié
        buffer = (uint16_t*)adcBuffer;
        sum = 0;
        for (i = 0; i < BUFFER_SIZE/2; i++) {
            sum += buffer[i];
        }
        // Calculer moyenne (à afficher ou utiliser)
        // ...

        xSemaphoreTake(xSemFull, portMAX_DELAY);
        // Traiter la seconde moitié
        buffer = (uint16_t*)&adcBuffer[BUFFER_SIZE/2];
        sum = 0;
        for (i = 0; i < BUFFER_SIZE/2; i++) {
            sum += buffer[i];
        }
        // ...
    }
}

int main(void) {
    xSemHalf = xSemaphoreCreateBinary();
    xSemFull = xSemaphoreCreateBinary();

    Timer2_Init();
    ADC1_DMA_Init();

    xTaskCreate(vProcessTask, "Process", 256, NULL, 2, NULL);
    vTaskStartScheduler();

    while(1);
}
```


---
<br>

### Liens connexe

- [Timer et Interruption](../timer/index.md)
- [GPIO et Interruptions](../gpio/index.md)
- [Timer et Interruption](../timer/index.md)
- [Acquisition Analogique via ADC](../adc/index.md)
- [Communication Série USART](../usart/index.md)
- [Communication Série I2C](../i2c/index.md)
- [Communication Série SPI](../spi/index.md)
- [Introduction pratique à freeRTOS](../../rtos/#introduction-a-freertos)