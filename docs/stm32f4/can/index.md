# Communication Série CAN

*Ir Paul S. Kabidu, M.Eng. <spaulkabidu@gmail.com>*
{: style="text-align: center;" }

---

[Accueil](../../#Accueil)
  
<br>
<br>



### ***Introduction au bus CAN**

Le bus **CAN** (Controller Area Network) est un protocole de communication série développé par Bosch dans les années 1980 pour l’automobile. Il est conçu pour permettre à plusieurs microcontrôleurs de communiquer entre eux sans ordinateur hôte, dans des environnements sévères (perturbations électromagnétiques, températures extrêmes). Aujourd’hui, il est largement utilisé dans l’industrie, la robotique, les équipements médicaux et bien sûr l’automobile.

**Caractéristiques principales :**

- Transmission différentielle sur deux fils (CAN_H et CAN_L), ce qui le rend robuste au bruit.
- Jusqu’à 1 Mbit/s (selon la longueur du bus).
- Multi-maître : tout nœud peut initier une communication.
- Arbitrage non destructif basé sur l’identifiant : les messages prioritaires passent sans collision.
- Détection d’erreurs et retransmission automatique.

Le **STM32F401** intègre un contrôleur CAN (bxCAN) compatible avec les protocoles 2.0A et 2.0B (standard et étendu). Dans ce chapitre, nous apprendrons à :

- Comprendre la **structure d’une trame CAN**.
- Configurer le contrôleur CAN en mode **normal**.
- Gérer l’envoi et la réception de messages.
- Utiliser les **filtres** pour sélectionner les messages entrants.
- Intégrer le CAN dans un environnement **FreeRTOS** avec des **files**.
- Réaliser un projet pratique d’échange de données entre deux cartes.

---
<br>



### **Principe du bus CAN**

**Niveaux logiques**

Le bus utilise deux lignes différentielles :

- **CAN_H** et **CAN_L**.
- État **dominant** (logique 0) : CAN_H = 3,5 V, CAN_L = 1,5 V.
- État **récessif** (logique 1) : CAN_H = 2,5 V, CAN_L = 2,5 V.
- En cas de conflit, l’état dominant l’emporte (c’est le principe d’arbitrage).

**Trame de données (format standard)**

Une trame CAN se compose des champs suivants :

1. **SOF** (Start of Frame) : 1 bit dominant.
2. **Identifiant** (11 bits en standard, 29 en étendu) : détermine la priorité (plus la valeur est petite, plus la priorité est haute).
3. **RTR** (Remote Transmission Request) : distingue trame de données et trame de requête.
4. **IDE** (Identifier Extension) : 0 pour standard, 1 pour étendu.
5. **DLC** (Data Length Code) : nombre d’octets de données (0 à 8).
6. **Champ de données** : 0 à 8 octets.
7. **CRC** (15 bits + délimiteur) : contrôle d’intégrité.
8. **ACK** : acquittement.
9. **EOF** (End of Frame) : 7 bits récessifs.

Le contrôleur CAN gère automatiquement tout le protocole : pour l’utilisateur, il suffit de préparer l’identifiant et les données, et de lire les messages reçus.

---
<br>



### **Le contrôleur CAN du STM32F4 (bxCAN)**

Le STM32F401 dispose d’un contrôleur CAN avec les caractéristiques suivantes :

- 3 boîtes d’émission (mailboxes).
- 2 FIFO de réception (3 messages chacune).
- 28 filtres configurables (par masque ou par liste) sur 32 bits.
- Modes : normal, silence, bouclage (loopback).

**Registres principaux**

| Registre | Rôle |
|----------|------|
| `CAN_MCR` | Registre de contrôle maître (initialisation, modes de test, etc.) |
| `CAN_MSR` | Statut maître (mode d’initialisation, erreurs) |
| `CAN_TSR` | Statut des boîtes d’émission |
| `CAN_RFR` | Statut des FIFO de réception |
| `CAN_TIxR` | Registre d’identifiant pour la boîte d’émission x |
| `CAN_TDTxR` | Registre de DLC pour la boîte x |
| `CAN_TDLxR` | Registre de données (bas) pour la boîte x |
| `CAN_TDHxR` | Registre de données (haut) pour la boîte x |
| `CAN_RIxR` | Identifiant reçu (FIFO x) |
| `CAN_RDTxR` | DLC reçu |
| `CAN_RDLxR` | Données reçues (bas) |
| `CAN_RDHxR` | Données reçues (haut) |
| `CAN_FMR` | Registre de configuration des filtres |
| `CAN_FM1R` | Mode des filtres (liste/masque) |
| `CAN_FS1R` | Taille des filtres (16/32 bits) |
| `CAN_FFA1R` | Affectation des filtres aux FIFO |
| `CAN_FA1R` | Activation des filtres |
| `CAN_FiR` | Registres de filtre i (2 x 32 bits) |

---
<br>



### **Configuration simple (mode polling)**

**Initialisation des broches**

On utilise par exemple PB8 (CAN_RX) et PB9 (CAN_TX) avec l’alternate function AF9.

```c
#include "stm32f4xx.h"

void CAN_GPIO_Init(void) {
    // Activer horloge GPIOB
    RCC->AHB1ENR |= RCC_AHB1ENR_GPIOBEN;

    // PB8 (RX), PB9 (TX) en alternate function AF9
    GPIOB->MODER &= ~((3U << (8*2)) | (3U << (9*2)));
    GPIOB->MODER |=  ((2U << (8*2)) | (2U << (9*2))); // AF
    GPIOB->AFR[1] &= ~((0xF << (0*4)) | (0xF << (1*4))); // (PB8 = AFRH[0], PB9 = AFRH[1])
    GPIOB->AFR[1] |=  ((9 << (0*4)) | (9 << (1*4))); // AF9 pour CAN
}
```

**Configuration du bit timing**

La vitesse est définie par le prescaler (BRP) et les segments de temps (BS1, BS2, SJW). Le temps de bit est :
t_bit = t_quanta * (1 + BS1 + BS2) avec t_quanta = (BRP+1) / f_APB.

Pour 125 kbit/s avec APB1 = 42 MHz (par exemple), on peut prendre BRP=41, BS1=6, BS2=7.

```c
void CAN_Init(void) {
    // 1. Activer horloge CAN
    RCC->APB1ENR |= RCC_APB1ENR_CAN1EN;

    // 2. Demander le mode initialisation
    CAN1->MCR |= CAN_MCR_INRQ;
    while (!(CAN1->MSR & CAN_MSR_INAK));

    // 3. Configurer le bit timing
    CAN1->BTR = (41 << CAN_BTR_BRP_Pos) |   // BRP = 41
                (CAN_BTR_TS1_6) |            // BS1 = 6 tq
                (CAN_BTR_TS2_7) |            // BS2 = 7 tq
                (0 << CAN_BTR_SJW_Pos);      // SJW = 1 tq

    // 4. Sortir du mode initialisation
    CAN1->MCR &= ~CAN_MCR_INRQ;
    while (CAN1->MSR & CAN_MSR_INAK);
}
```

**Envoi d’un message (polling)**

On cherche une boîte d’émission libre (TME = 1), on charge les registres, puis on demande la transmission.

```c
uint8_t CAN_SendMessage(uint32_t id, uint8_t *data, uint8_t len) {
    uint32_t mailbox;
    // Attendre une boîte libre
    while (!(CAN1->TSR & (CAN_TSR_TME0 | CAN_TSR_TME1 | CAN_TSR_TME2)));

    if (CAN1->TSR & CAN_TSR_TME0) mailbox = 0;
    else if (CAN1->TSR & CAN_TSR_TME1) mailbox = 1;
    else mailbox = 2;

    // Format standard (11 bits) – on suppose id < 0x800
    CAN1->sTxMailBox[mailbox].TIR = (id << 21) | CAN_TI0R_TXRQ; // TXRQ pour démarrer
    CAN1->sTxMailBox[mailbox].TDTR = len & 0xF;
    CAN1->sTxMailBox[mailbox].TDLR = data[0] | (data[1] << 8) | (data[2] << 16) | (data[3] << 24);
    CAN1->sTxMailBox[mailbox].TDHR = data[4] | (data[5] << 8) | (data[6] << 16) | (data[7] << 24);

    // La transmission est lancée par TXRQ (déjà mis)
    return 1;
}
```

**Réception d’un message (polling)**

On vérifie si une FIFO a reçu un message (FMP non nul), puis on lit.

```c
uint8_t CAN_ReceiveMessage(uint32_t *id, uint8_t *data) {
    if ((CAN1->RF0R & CAN_RF0R_FMP0) == 0) return 0; // pas de message

    // Lire depuis FIFO0 (on pourrait aussi FIFO1)
    *id = (CAN1->sFIFOMailBox[0].RIR >> 21) & 0x7FF; // 11 bits
    uint8_t len = CAN1->sFIFOMailBox[0].RDTR & 0xF;
    uint32_t low = CAN1->sFIFOMailBox[0].RDLR;
    uint32_t high = CAN1->sFIFOMailBox[0].RDHR;

    for (int i = 0; i < 4 && i < len; i++) data[i] = (low >> (i*8)) & 0xFF;
    for (int i = 4; i < 8 && i < len; i++) data[i] = (high >> ((i-4)*8)) & 0xFF;

    // Libérer la FIFO
    CAN1->RF0R |= CAN_RF0R_RFOM0;
    return len;
}
```

Limitation : ces fonctions sont bloquantes et ne sont pas adaptées à un système temps réel multitâche.

---
<br>



### **Utilisation avec FreeRTOS**

Pour ne pas bloquer les tâches, on peut utiliser les interruptions de réception et éventuellement de transmission. Une tâche dédiée gère les messages reçus via une file (queue).

**Configuration des interruptions**

```c
void CAN_Interrupt_Init(void) {
    NVIC_SetPriority(CAN1_RX0_IRQn, 5);
    NVIC_EnableIRQ(CAN1_RX0_IRQn);

    // Activer l'interruption sur réception FIFO0 (message en attente)
    CAN1->IER |= CAN_IER_FMPIE0;
}
```

**Gestionnaire d’interruption**

```c
QueueHandle_t xCANRxQueue;

void CAN1_RX0_IRQHandler(void) {
    BaseType_t xWoken = pdFALSE;
    uint8_t data[8];
    uint32_t id;

    // Lire le message depuis FIFO0
    id = (CAN1->sFIFOMailBox[0].RIR >> 21) & 0x7FF;
    uint8_t len = CAN1->sFIFOMailBox[0].RDTR & 0xF;
    uint32_t low = CAN1->sFIFOMailBox[0].RDLR;
    uint32_t high = CAN1->sFIFOMailBox[0].RDHR;

    for (int i = 0; i < 4 && i < len; i++) data[i] = (low >> (i*8)) & 0xFF;
    for (int i = 4; i < 8 && i < len; i++) data[i] = (high >> ((i-4)*8)) & 0xFF;

    // Libérer la FIFO
    CAN1->RF0R |= CAN_RF0R_RFOM0;

    // Envoyer dans la queue (copie de l'ID et des données)
    xQueueSendFromISR(xCANRxQueue, data, &xWoken);
    portYIELD_FROM_ISR(xWoken);
}
```

**Tâche de traitement des messages reçus**

```c
void vTaskCANReceiver(void *pvParameters) {
    uint8_t rxData[8];

    for (;;) {
        if (xQueueReceive(xCANRxQueue, rxData, portMAX_DELAY) == pdPASS) {
            // Traiter le message (afficher, agir selon l'ID...)
            // L'ID n'est pas passé ici, on pourrait structurer les données.
        }
    }
}
```

Pour l’émission, on peut aussi utiliser une file pour que diverses tâches puissent envoyer des messages sans se soucier de la synchronisation. Une tâche dédiée à l’émission vide la file et appelle la fonction d’envoi (avec protection si nécessaire).

---
<br>




### **Projet : LÉchange de données entre deux cartes STM32 {#projet-can-echange}**

Réalisons un système simple où :

- La carte A lit un potentiomètre sur ADC (PA0) et envoie périodiquement la valeur (16 bits) sur le bus CAN avec l’ID 0x100.
- La carte B reçoit les messages avec l’ID 0x100 et affiche la valeur sur UART (PC). Un filtre est configuré pour ne recevoir que cet ID.

**Configuration des filtres (carte B)**

```c
void CAN_Filter_Init(void) {
    // Mode initialisation des filtres
    CAN1->FMR |= CAN_FMR_FINIT;

    // Filtre 0 : mode masque (32 bits)
    CAN1->FM1R &= ~(1 << 0); // 0 = masque, 1 = liste
    CAN1->FS1R |= (1 << 0);   // 32 bits

    // Registre de filtre 0 : masque (les bits à 1 sont pertinents)
    CAN1->sFilterRegister[0].FR1 = 0x7FF << 21; // masque sur l'ID 11 bits
    CAN1->sFilterRegister[0].FR2 = (0x100 << 21); // valeur attendue

    // Affecter à FIFO0
    CAN1->FFA1R &= ~(1 << 0); // FIFO0

    // Activer le filtre
    CAN1->FA1R |= (1 << 0);

    // Sortir du mode initialisation
    CAN1->FMR &= ~CAN_FMR_FINIT;
}
```

**Tâche d’acquisition et d’envoi (carte A)**

```c
void vTaskSensorSender(void *pvParameters) {
    uint8_t data[8];
    uint16_t adcVal;

    for (;;) {
        adcVal = ADC_Read(); // lecture ADC (0-4095)
        data[0] = adcVal & 0xFF;
        data[1] = (adcVal >> 8) & 0xFF;

        CAN_SendMessage(0x100, data, 2);
        vTaskDelay(pdMS_TO_TICKS(100));
    }
}
```

**Tâche de réception et affichage (carte B)**

```c
void vTaskCANDisplay(void *pvParameters) {
    uint8_t rxData[8];
    uint16_t value;

    for (;;) {
        if (xQueueReceive(xCANRxQueue, rxData, portMAX_DELAY) == pdPASS) {
            value = rxData[0] | (rxData[1] << 8);
            printf("Valeur ADC: %u\r\n", value);
        }
    }
}
```

**Programme principal (carte B)**

```c
int main(void) {
    USART2_Init(115200);
    CAN_GPIO_Init();
    CAN_Init();
    CAN_Filter_Init();
    CAN_Interrupt_Init();

    xCANRxQueue = xQueueCreate(10, 8); // queue de 10 messages de 8 octets

    if (xCANRxQueue != NULL) {
        xTaskCreate(vTaskCANDisplay, "CAN Disp", 256, NULL, 2, NULL);
        vTaskStartScheduler();
    }

    while(1);
}
```

---
<br>




### Liens connexe


- [GPIO et Interruptions](../gpio/index.md)
- [Timer et Interruption](../timer/index.md)
- [Machine d’État Fini (FSM)](../../technique-algos/fsm/index.md)
- [Introduction pratique à freeRTOS](../../rtos/#introduction-a-freertos)
