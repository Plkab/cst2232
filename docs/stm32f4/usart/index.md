# Communication Série USART

*Ir Paul S. Kabidu, M.Eng. <spaulkabidu@gmail.com>*
{: style="text-align: center;" }

---

[Accueil](../../#Accueil)
  
<br>
<br>


### **Introduction à la communication série**

La communication série asynchrone (UART/USART) est l’un des moyens les plus simples et les plus répandus pour faire dialoguer un microcontrôleur avec un PC, un autre microcontrôleur, ou des périphériques (GPS, modules Bluetooth, etc.). Elle ne nécessite que deux fils (TX et RX) et une masse commune.

Le STM32F4 intègre plusieurs **USART** (Universal Synchronous/Asynchronous Receiver Transmitter) capables de fonctionner en mode asynchrone (UART) ou synchrone. Dans ce chapitre, nous nous concentrerons sur le mode asynchrone, le plus utilisé.

Les objectifs de ce chapitre sont :

- Comprendre le principe de la communication série (start bit, data bits, stop bit, baud rate).
- Configurer l’USART en mode polling (simple mais bloquant).
- Passer à un mode plus efficace : les interruptions.
- Intégrer l’USART dans un environnement FreeRTOS en utilisant des files de messages (queues) pour découpler réception et traitement.
- Réaliser un projet pratique d’échange de données avec un PC.

---
<br>

### **Principe de l’UART**

Une trame UART typique se compose de :

- Un bit de start (toujours à 0)
- 5 à 9 bits de données (souvent 8)
- Un bit de parité optionnel
- 1 ou 2 bits de stop (toujours à 1)

Le débit est défini par le **baud rate** (ex: 9600, 115200 bauds). Les deux extrémités doivent être configurées exactement de la même manière.

Sur le STM32F4, l’USART est configuré via des registres :

- `USART_BRR` : définit le baud rate à partir de l’horloge du périphérique.
- `USART_CR1` : active la transmission, la réception, les interruptions, etc.
- `USART_SR` : indique l’état (TXE – registre de transmission vide, RXNE – donnée reçue disponible, etc.).
- `USART_DR` : registre de données (lecture/écriture).

---
<br>

### **Configuration simple (mode polling)**

**Initialisation de l’USART2 sur PA2 (TX) et PA3 (RX)**

```c
#include "stm32f4xx.h"

void USART2_Init(uint32_t baud) {
    // 1. Activer les horloges GPIOA et USART2
    RCC->AHB1ENR |= RCC_AHB1ENR_GPIOAEN;
    RCC->APB1ENR |= RCC_APB1ENR_USART2EN;

    // 2. Configurer PA2 et PA3 en alternate function AF7
    GPIOA->MODER &= ~((3U << (2*2)) | (3U << (3*2)));
    GPIOA->MODER |=  ((2U << (2*2)) | (2U << (3*2))); // 10 = Alternate function
    GPIOA->AFR[0] |= (7 << (2*4)) | (7 << (3*4));     // AF7 pour USART2

    // 3. Configurer l'USART : 8 bits, 1 stop, pas de parité, 115200 bauds
    USART2->BRR = 84000000 / baud;  // Horloge APB1 = 84 MHz
    USART2->CR1 = USART_CR1_TE | USART_CR1_RE; // Activer TX et RX
    USART2->CR2 = 0;                  // 1 stop bit par défaut
    USART2->CR3 = 0;
    USART2->CR1 |= USART_CR1_UE;       // Activer l'USART
}

// Émission d'un caractère (polling)
void USART2_SendChar(char c) {
    while (!(USART2->SR & USART_SR_TXE)); // Attendre que le buffer soit vide
    USART2->DR = c;
}

// Émission d'une chaîne
void USART2_SendString(char *str) {
    while (*str) {
        USART2_SendChar(*str++);
    }
}

// Réception d'un caractère (polling, bloquant)
char USART2_GetChar(void) {
    while (!(USART2->SR & USART_SR_RXNE)); // Attendre qu'une donnée soit reçue
    return USART2->DR;
}
```
Limitation : les fonctions d’émission/réception en polling bloquent le CPU jusqu’à ce que l’opération soit terminée. Dans un système temps réel, cela peut être problématique.

---
<br>

### **Utilisation avec FreeRTOS**

Pour ne pas bloquer les tâches, on peut utiliser **les interruptions** et **les files de messages**.

**Principe**

- Une ISR de réception (RXNE) place le caractère reçu dans une file (`xQueueSendFromISR`).
- Une tâche consomme les caractères depuis la file (`xQueueReceive`) et les traite.
- L’émission peut aussi être gérée par une tâche qui écrit dans un buffer circulaire ou une file, mais l’exemple le plus simple est de conserver un émission directe (polling court) ou d’utiliser une file et une ISR de fin d’émission (TXE).

**Configuration avec interruption de réception**

```c
#include "FreeRTOS.h"
#include "queue.h"

QueueHandle_t xRxQueue;

void USART2_IRQHandler(void) {
    BaseType_t xWoken = pdFALSE;
    uint8_t data;

    if (USART2->SR & USART_SR_RXNE) {
        data = USART2->DR;                 // Lire la donnée (efface le flag)
        xQueueSendFromISR(xRxQueue, &data, &xWoken);
    }
    // Gérer d'autres flags si nécessaire (par exemple erreurs)
    portYIELD_FROM_ISR(xWoken);
}

void USART2_Init_Interrupt(uint32_t baud) {
    // Réutiliser l'initialisation précédente
    USART2_Init(baud);
    
    // Activer l'interruption sur réception
    USART2->CR1 |= USART_CR1_RXNEIE;
    
    // Configurer la priorité et activer dans le NVIC
    NVIC_SetPriority(USART2_IRQn, 5);
    NVIC_EnableIRQ(USART2_IRQn);
}

// Tâche de traitement de la réception (écho simple)
void vTaskRxProcessor(void *pvParameters) {
    uint8_t c;
    for (;;) {
        if (xQueueReceive(xRxQueue, &c, portMAX_DELAY) == pdPASS) {
            // Traiter le caractère reçu (ex: l'accumuler dans une ligne, interpréter une commande...)
            // Pour l'instant, on le renvoie en écho
            USART2_SendChar(c);
        }
    }
}
```

**Émission avec file d’attente (optionnel)**

On peut aussi utiliser une file pour l’émission, avec une tâche dédiée qui vide la file et envoie les caractères (polling court mais sans bloquer les autres tâches).

```c
QueueHandle_t xTxQueue;

void vTaskTxProcessor(void *pvParameters) {
    uint8_t c;
    for (;;) {
        if (xQueueReceive(xTxQueue, &c, portMAX_DELAY) == pdPASS) {
            USART2_SendChar(c);  // Polling, mais on ne bloque que le temps d'envoyer un caractère
        }
    }
}

// Fonction pour envoyer une chaîne via la file (à appeler depuis n'importe quelle tâche)
void USART2_SendStringAsync(char *str) {
    while (*str) {
        xQueueSend(xTxQueue, str++, 0);
    }
}
```

---
<br>

### **Projet : Mini terminal interactif** {#projet-usart-terminal}

Réalisons un petit système qui reçoit des commandes via l’UART, les interprète, et exécute des actions (par exemple allumer/éteindre une LED, afficher l’état, etc.). Ce projet utilise :

- Une interruption de réception pour accumuler les caractères dans une file.
- Une tâche qui lit la file et construit une ligne jusqu’à recevoir un retour chariot (`\n` ou `\r`).
- Une machine à états simple pour interpréter la commande.

```c
#include "FreeRTOS.h"
#include "task.h"
#include "queue.h"
#include "string.h"
#include "stm32f4xx.h"

// Définition des handles de queue
QueueHandle_t xRxQueue;

// Buffer pour la ligne courante
#define LINE_BUFFER_SIZE 64
static char lineBuffer[LINE_BUFFER_SIZE];
static uint8_t lineIndex = 0;

// Prototypes
void USART2_Init_Interrupt(uint32_t baud);
void vTaskRxInterpreter(void *pvParameters);
void USART2_SendString(char *str);

// Handler d'interruption USART2
void USART2_IRQHandler(void) {
    BaseType_t xWoken = pdFALSE;
    if (USART2->SR & USART_SR_RXNE) {
        uint8_t data = USART2->DR;
        xQueueSendFromISR(xRxQueue, &data, &xWoken);
    }
    portYIELD_FROM_ISR(xWoken);
}

// Tâche d'interprétation des commandes
void vTaskRxInterpreter(void *pvParameters) {
    uint8_t c;
    for (;;) {
        if (xQueueReceive(xRxQueue, &c, portMAX_DELAY) == pdPASS) {
            // Afficher en écho (optionnel)
            USART2_SendChar(c);

            // Fin de ligne ?
            if (c == '\n' || c == '\r') {
                lineBuffer[lineIndex] = '\0'; // Terminer la chaîne
                if (lineIndex > 0) {
                    // Interpréter la commande
                    if (strcmp(lineBuffer, "on") == 0) {
                        GPIOC->ODR |= (1 << 13);   // Allumer LED
                        USART2_SendString("\r\nLED ON\r\n");
                    } else if (strcmp(lineBuffer, "off") == 0) {
                        GPIOC->ODR &= ~(1 << 13);  // Éteindre LED
                        USART2_SendString("\r\nLED OFF\r\n");
                    } else {
                        USART2_SendString("\r\nCommande inconnue\r\n");
                    }
                }
                lineIndex = 0; // Réinitialiser le buffer
            } else if (lineIndex < LINE_BUFFER_SIZE - 1) {
                lineBuffer[lineIndex++] = c;
            }
        }
    }
}

// Programme principal
int main(void) {
    // Initialisation LED PC13
    RCC->AHB1ENR |= RCC_AHB1ENR_GPIOCEN;
    GPIOC->MODER |= (1 << (13*2));
    GPIOC->ODR &= ~(1 << 13); // LED éteinte au départ

    // Initialisation USART à 115200 bauds
    USART2_Init_Interrupt(115200);

    // Création de la file pour les caractères reçus (taille 32)
    xRxQueue = xQueueCreate(32, sizeof(uint8_t));

    if (xRxQueue != NULL) {
        // Création de la tâche d'interprétation
        xTaskCreate(vTaskRxInterpreter, "RxInterp", 256, NULL, 2, NULL);
        
        // Lancement de l'ordonnanceur
        vTaskStartScheduler();
    }

    // Ne devrait jamais arriver
    while(1);
}
```

**Explications :**

- Les caractères reçus sont mis dans une file par l’ISR.
- La tâche `vTaskRxInterpreter` les récupère un par un, les accumule dans un buffer jusqu’à recevoir un retour chariot, puis compare la ligne avec des commandes prédéfinies.
- La LED est commandée via les commandes `on` et `off`.
- L’écho permet de voir ce qu’on tape (facultatif).

---
<br>



### *Utiliser printf() sur l'USART**

Pour faciliter le débogage, on peut rediriger `printf()` vers l’USART. Sous Keil, il suffit de réimplémenter la fonction `_write` :

```c
#include <stdio.h>

int _write(int file, char *ptr, int len) {
    for (int i = 0; i < len; i++) {
        USART2_SendChar(ptr[i]);
    }
    return len;
}
```

Ainsi, un simple `printf("Valeur : %d\r\n", maVariable);` enverra la chaîne formatée sur le port série.

---
<br>



### Liens connexe

- [GPIO et Interruptions](../gpio/index.md)
- [Timer et Interruption](../timer/index.md)
- [Machine d’État Fini (FSM)](../../technique-algos/fsm/index.md)
- [Introduction pratique à freeRTOS](../../rtos/#introduction-a-freertos)