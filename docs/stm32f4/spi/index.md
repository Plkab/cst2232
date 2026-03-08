# Communication Série SPI

*Ir Paul S. Kabidu, M.Eng. <spaulkabidu@gmail.com>*
{: style="text-align: center;" }

---

[Accueil](../../#Accueil)
  
<br>
<br>



### **Introduction au bus SPI**

Le bus **SPI** (Serial Peripheral Interface) est un protocole de communication série **synchrone** très utilisé pour connecter des périphériques à **vitesse élevée** (écrans, cartes SD, mémoires Flash, capteurs rapides, etc.) à un microcontrôleur. Il fonctionne en **mode maître‑esclave** et utilise quatre fils (ou parfois trois) :

- **SCLK** : horloge série (générée par le maître)
- **MOSI** : Master Out Slave In (données du maître vers l'esclave)
- **MISO** : Master In Slave Out (données de l'esclave vers le maître)
- **SS** / **CS** : Slave Select (sélection de l’esclave, actif bas)

Le **STM32F401** intègre plusieurs interfaces SPI matérielles. Dans ce chapitre, nous apprendrons à :

- Comprendre le **fonctionnement du bus SPI** (mode de transmission, polarité et phase d’horloge).
- Configurer le **SPI en mode maître** pour échanger des données avec un périphérique.
- Utiliser les **interruptions** pour une communication **non bloquante**.
- Intégrer le SPI dans un environnement **FreeRTOS** avec des **files de messages** et des **mutex**.
- Réaliser un **projet pratique** de lecture/écriture d’une **mémoire Flash** (par exemple une Winbond W25Qxx) et afficher les données sur **UART**.

---
<br>



### **Principe du bus SPI**

Le bus SPI est un bus de type **maître‑esclave**. Un seul maître peut contrôler plusieurs esclaves, chacun étant sélectionné individuellement par une ligne **CS** (Chip Select).

**Signalisation**

- **SCLK** : signal d’horloge généré par le maître. La fréquence peut atteindre plusieurs dizaines de MHz.
- **MOSI** : ligne de données sortante du maître et entrante pour l’esclave.
- **MISO** : ligne de données entrante pour le maître et sortante de l’esclave.
- **CS** : ligne de sélection de l’esclave (active à l’état bas). Quand CS est bas, l’esclave est activé ; quand il est haut, il ignore les signaux sur MOSI et SCLK.

**Modes de transmission**

SPI définit quatre modes de fonctionnement selon la **polarité** (CPOL) et la **phase** (CPHA) de l’horloge :

| Mode | CPOL | CPHA | Description |
|------|------|------|-------------|
| 0    | 0    | 0    | Horloge inactive à 0, échantillonnage sur front montant |
| 1    | 0    | 1    | Horloge inactive à 0, échantillonnage sur front descendant |
| 2    | 1    | 0    | Horloge inactive à 1, échantillonnage sur front descendant |
| 3    | 1    | 1    | Horloge inactive à 1, échantillonnage sur front montant |

Le maître et l’esclave doivent être configurés dans le **même mode**. La documentation du périphérique esclave indique généralement quel mode utiliser.

**Trame élémentaire**

Une communication SPI est **full‑duplex** : à chaque coup d’horloge, un bit est échangé simultanément sur MOSI et MISO. La taille des données est souvent de 8 bits, mais peut être étendue jusqu’à 16 bits.

Pour lire des données sur un esclave, le maître envoie généralement une commande (un ou plusieurs octets) et continue à générer l’horloge pour recevoir la réponse.

---
<br>



### **Registres importants du SPI sur STM32F4**

| Registre | Rôle |
|----------|------|
| `SPI_CR1` | Registre de contrôle (configuration du mode, activation, ordre des bits, etc.) |
| `SPI_CR2` | Configuration des interruptions et du DMA |
| `SPI_SR`  | Registre de statut (TXE, RXNE, BSY, etc.) |
| `SPI_DR`  | Registre de données (lecture/écriture) |
| `SPI_CRCPR` | Registre pour le calcul CRC (optionnel) |

**Vitesses** : Le débit est défini par le diviseur de l’horloge du périphérique (souvent APB). On peut choisir des fréquences allant de `f_PCLK/2` à `f_PCLK/256`. Par exemple, avec APB2 à 84 MHz, une division par 64 donne environ 1,3 MHz.

---
<br>



### **Configuration simple (mode polling)**

L’exemple suivant configure **SPI1** en mode maître à 1 MHz sur les broches PA5 (SCLK), PA6 (MISO), PA7 (MOSI) et PA4 (CS). On effectue une lecture de l’identifiant d’une mémoire Flash (par exemple la commande `0x9F` pour le JEDEC ID).

```c
#include "stm32f4xx.h"

void SPI1_Init(void) {
    // 1. Activer les horloges GPIOA et SPI1
    RCC->AHB1ENR |= RCC_AHB1ENR_GPIOAEN;
    RCC->APB2ENR |= RCC_APB2ENR_SPI1EN;

    // 2. Configurer les broches en alternate function AF5
    // PA5 (SCLK), PA6 (MISO), PA7 (MOSI), PA4 (CS en sortie GPIO)
    GPIOA->MODER &= ~((3U << (5*2)) | (3U << (6*2)) | (3U << (7*2)) | (3U << (4*2)));
    GPIOA->MODER |=  ((2U << (5*2)) | (2U << (6*2)) | (2U << (7*2))); // AF pour SPI
    GPIOA->MODER |=  (1U << (4*2));  // PA4 en sortie (pour CS)

    GPIOA->AFR[0] &= ~((0xF << (5*4)) | (0xF << (6*4)) | (0xF << (7*4)));
    GPIOA->AFR[0] |=  ((5 << (5*4)) | (5 << (6*4)) | (5 << (7*4))); // AF5 pour SPI1

    // 3. Configurer SPI1
    SPI1->CR1 = SPI_CR1_SSM | SPI_CR1_SSI;   // Gestion logicielle du CS
    SPI1->CR1 |= SPI_CR1_MSTR;                // Mode maître
    SPI1->CR1 |= SPI_CR1_BR_2;                // Diviseur pour 1 MHz (si APB2 = 84 MHz, BR = 64 → 84/64 ≈ 1.3 MHz)
    SPI1->CR1 |= SPI_CR1_SPE;                  // Activer SPI
}

// Sélectionner l'esclave (CS bas)
void SPI1_CS_Low(void) {
    GPIOA->ODR &= ~(1 << 4);
}

// Désélectionner l'esclave (CS haut)
void SPI1_CS_High(void) {
    GPIOA->ODR |= (1 << 4);
}

// Échange d'un octet (full duplex)
uint8_t SPI1_Transfer(uint8_t data) {
    while (!(SPI1->SR & SPI_SR_TXE));         // Attendre que le buffer d'émission soit vide
    SPI1->DR = data;
    while (!(SPI1->SR & SPI_SR_RXNE));        // Attendre réception
    return SPI1->DR;
}

// Lecture du JEDEC ID d'une mémoire Flash (ex: W25Q16)
void SPI1_ReadJEDEC(void) {
    uint8_t id[3];

    SPI1_CS_Low();
    SPI1_Transfer(0x9F);   // Commande JEDEC ID
    id[0] = SPI1_Transfer(0x00);
    id[1] = SPI1_Transfer(0x00);
    id[2] = SPI1_Transfer(0x00);
    SPI1_CS_High();

    // id[0] = fabricant, id[1] = type, id[2] = capacité
}
```

Limitation : ces fonctions sont bloquantes et utilisent des boucles d’attente active. Dans un système temps réel, on préférera les interruptions ou le DMA pour libérer le CPU.


---
<br>



### **Utilisation avec FreeRTOS**

Pour ne pas bloquer les tâches, on peut configurer le SPI en mode interruption. L’idée est de lancer une transaction (sélection CS, envoi/réception de données) et de laisser le SPI générer des interruptions à chaque octet. Une machine d’états simple dans l’ISR gère la progression de la transaction et réveille une tâche à la fin via un sémaphore.

**Exemple simplifié : lecture de plusieurs octets avec interruptions**

```c
#include "FreeRTOS.h"
#include "task.h"
#include "semphr.h"

SemaphoreHandle_t xSPISemaphore;

// Variables pour la transaction en cours
volatile uint8_t *spiTxBuffer, *spiRxBuffer;
volatile uint16_t spiTransferCount, spiIndex;
volatile uint8_t spiBusy = 0;

void SPI1_IRQHandler(void) {
    BaseType_t xWoken = pdFALSE;

    // Interruption d'émission (TXE)
    if (SPI1->SR & SPI_SR_TXE) {
        if (spiIndex < spiTransferCount) {
            SPI1->DR = spiTxBuffer[spiIndex];
        } else {
            // Plus rien à envoyer, on désactive l'interruption TXE
            SPI1->CR2 &= ~SPI_CR2_TXEIE;
        }
    }

    // Interruption de réception (RXNE)
    if (SPI1->SR & SPI_SR_RXNE) {
        uint8_t received = SPI1->DR;
        if (spiIndex < spiTransferCount) {
            if (spiRxBuffer != NULL) {
                spiRxBuffer[spiIndex] = received;
            }
            spiIndex++;
        }
    }

    // Fin de la transaction ?
    if (spiIndex == spiTransferCount) {
        spiBusy = 0;
        xSemaphoreGiveFromISR(xSPISemaphore, &xWoken);
    }

    portYIELD_FROM_ISR(xWoken);
}

// Fonction asynchrone de transfert SPI
void SPI1_TransferAsync(uint8_t *tx, uint8_t *rx, uint16_t len) {
    spiTxBuffer = tx;
    spiRxBuffer = rx;
    spiTransferCount = len;
    spiIndex = 0;
    spiBusy = 1;

    // Activer les interruptions TXE et RXNE
    SPI1->CR2 |= SPI_CR2_TXEIE | SPI_CR2_RXNEIE;
    // Lancer la transmission du premier octet
    SPI1->DR = spiTxBuffer[0];
}

// Fonction synchrone avec timeout (utilisée par les tâches)
uint8_t SPI1_TransferSync(uint8_t *tx, uint8_t *rx, uint16_t len, TickType_t timeout) {
    if (spiBusy) return 0; // déjà occupé

    SPI1_CS_Low();
    SPI1_TransferAsync(tx, rx, len);
    if (xSemaphoreTake(xSPISemaphore, timeout) == pdTRUE) {
        SPI1_CS_High();
        return 1; // succès
    } else {
        // timeout : annuler la transaction
        spiBusy = 0;
        SPI1->CR2 &= ~(SPI_CR2_TXEIE | SPI_CR2_RXNEIE);
        SPI1_CS_High();
        return 0;
    }
}
```

Remarque : Ce code nécessite une initialisation du sémaphore (`xSPISemaphore = xSemaphoreCreateBinary()`) et une configuration correcte des priorités d’interruption (la priorité doit être compatible avec FreeRTOS, généralement ≥5).


---
<br>




### **Projet : Lecture d’une mémoire Flash via SPI {#projet-spi-flash}**

Prenons l’exemple d’une mémoire Flash W25Q16 (ou similaire). Elle communique en SPI et possède une commande de lecture d’identifiant JEDEC (0x9F) et une commande de lecture de données (0x03).

Montage :

- CS → PA4
- SCLK → PA5
- MISO → PA6
- MOSI → PA7

Tâche FreeRTOS : lire le JEDEC ID et afficher sur UART.

```c
#include "FreeRTOS.h"
#include "task.h"
#include "semphr.h"
#include "stm32f4xx.h"
#include <stdio.h>

// Déclaration du sémaphore (défini ailleurs)
extern SemaphoreHandle_t xSPISemaphore;

// Fonctions UART (à implémenter)
void USART2_Init(uint32_t baud);
void USART2_SendString(char *str);
int _write(int file, char *ptr, int len); // pour printf

void vTaskFlashReader(void *pvParameters) {
    uint8_t tx[5], rx[5];

    for (;;) {
        // Lecture JEDEC ID
        tx[0] = 0x9F;  // commande
        tx[1] = 0x00;
        tx[2] = 0x00;
        tx[3] = 0x00;

        if (SPI1_TransferSync(tx, rx, 4, pdMS_TO_TICKS(100))) {
            printf("Flash ID: 0x%02X 0x%02X 0x%02X\r\n", rx[1], rx[2], rx[3]);
        } else {
            printf("Erreur SPI (timeout)\r\n");
        }

        vTaskDelay(pdMS_TO_TICKS(2000));
    }
}

int main(void) {
    SPI1_Init();
    USART2_Init(115200);

    xSPISemaphore = xSemaphoreCreateBinary();

    if (xSPISemaphore != NULL) {
        xTaskCreate(vTaskFlashReader, "Flash", 256, NULL, 2, NULL);
        vTaskStartScheduler();
    }

    while(1);
}
```

---
<br>



### **Utilisation du DMA avec SPI**

Pour des transferts de gros volumes (par exemple charger une image dans un écran), l’utilisation du DMA est recommandée. Le DMA peut transférer automatiquement les données entre la mémoire et le registre SPI sans intervention du CPU, ce qui libère complètement le processeur.

Exemple de configuration DMA pour SPI1_TX :

```c
void SPI1_DMA_Init(void) {
    RCC->AHB1ENR |= RCC_AHB1ENR_DMA2EN;

    // Configuration du stream 3 pour SPI1_TX (vérifier le RM)
    DMA2_Stream3->PAR = (uint32_t)&SPI1->DR;        // Adresse périphérique
    DMA2_Stream3->M0AR = (uint32_t)txBuffer;        // Adresse mémoire
    DMA2_Stream3->NDTR = bufferSize;                 // Taille
    DMA2_Stream3->CR = DMA_SxCR_CHSEL_0 |            // Canal 0 pour SPI1_TX
                       DMA_SxCR_DIR_0 |               // Mémoire -> périphérique
                       DMA_SxCR_MINC |                // Incrément mémoire
                       DMA_SxCR_TCIE;                 // Interruption fin de transfert

    NVIC_EnableIRQ(DMA2_Stream3_IRQn);
}
```

Le DMA peut être combiné avec des sémaphores pour notifier la tâche de la fin du transfert. L’ISR du DMA donne alors le sémaphore.


---
<br>




### Liens connexe


- [GPIO et Interruptions](../gpio/index.md)
- [Timer et Interruption](../timer/index.md)
- [Machine d’État Fini (FSM)](../../technique-algos/fsm/index.md)
- [Introduction pratique à freeRTOS](../../rtos/#introduction-a-freertos)
