# GPIO et Interruptions

*Ir Paul S. Kabidu, M.Eng. <spaulkabidu@gmail.com>*
{: style="text-align: center;" }

---

[Accueil](../../#Accueil)
  
<br>
<br>


### **GPIO**

Les GPIO (General Purpose Input-Output) est un phreipherique d'entree - sortie numerique. le STM32F4 possede 7 ports nommees (GPIOA, GPIOB, etc.). Chaque GPIOx possede ses propres registres de configuration. on a :

- **MODER** : Définit la direction (00: Entrée, 01: Sortie).
- **IDR / ODR** : Lecture (Input) et Écriture (Output).
- **BSRR** : Modification atomique (Set/Reset) sans lire le registre au préalable (plus sûr en multitâche). C'est une écriture directe au niveau matériel. On ne peut pas corrompre les autres bits du port. C'est une garantie de sécurité logicielle.

Ces registres sont de 32 bits.

---
<br>

### **Configuration d'une Sortie (LED sur PC13)**

Pour faire clignoter une LED, nous devons suivre trois étapes logiques dans les registres :

- Activer l'horloge du port (RCC) : Sans énergie, le périphérique ne répond pas. Exemple : RCC_AHB1ENR
- Configurer le mode (MODER) : Déclarer la broche en "Sortie".
- Piloter l'état (BSRR/ODR) : Envoyer 0V ou 3.3V.

Exemple Pratique : Faire clignoter la LED (PC13)

```c
// Code Bare Metal pur (Sans RTOS)
void main(void) {
    // 1. Activer l'horloge du Port C (Bit 2 à 1)
    RCC->AHB1ENR |= RCC_AHB1ENR_GPIOCEN;       // 1. Horloge ON
    // 2. PC13 en sortie (Bits 26-27 à 01)
    GPIOC->MODER |= (1 << (13 * 2));            // 2. PC13 en Sortie

    while(1) {
        GPIOC->BSRR = (1 << 29);                // LED ON (Reset bit 13)
        for(int i=0; i<500000; i++);            // Attente logicielle (Bloque le CPU)
        GPIOC->BSRR = (1 << 13);                // LED OFF (Set bit 13)
        for(int i=0; i<500000; i++);
    }
}
```

Usage du registre ODR :
```c
// Code Bare Metal pur (Sans RTOS)
void main(void) {
    // 1. Activer l'horloge du Port C (Bit 2 à 1)
    RCC->AHB1ENR |= RCC_AHB1ENR_GPIOCEN;       // 1. Horloge ON
    // 2. PC13 en sortie (Bits 26-27 à 01)
    GPIOC->MODER |= (1 << (13 * 2));            // 2. PC13 en Sortie

    while(1) {
        GPIOC->ODR ^= (1 << 13); // Inverser l'état
        for(int i=0; i<1000000; i++); // ATTENTE INUTILE : Le CPU "compte ses doigts"
    }
}
```

Problème ici est que : Pendant le temps de la boucle `for`, le processeur ne peut rien faire d'autre. Si vous appuyez sur un bouton pendant le `for`, le processeur est trop occupé à compter. Il vous ignore.

---
<br>

### **Gestion des Entrées/Sorties dans une Tâche**

Contrairement au Bare Metal classique où l'on utilise des boucles delay(), FreeRTOS permet de libérer le CPU pendant l'attente d'un clignotement ou d'un rafraîchissement.

Avec FreeRTOS, la tâche dit : "Je dors pendant 500ms, réveille la tâche suivante !". C'est le vTaskDelay(). On remplace for(delay) par vTaskDelay().

```c
void vTaskBlink(void *pvParameters) {
    // Configuration de PC13
    RCC->AHB1ENR |= RCC_AHB1ENR_GPIOCEN;
    GPIOC->MODER |= (1 << (13 * 2));

    for (;;) {
        GPIOC->ODR ^= (1 << 13);           // Toggle LED
        vTaskDelay(pdMS_TO_TICKS(500));    // Délai non-bloquant de 500ms
    }
}
```


---
<br>

### **L'Approche Interruptions Externes (EXTI) : GPIO + Interruption + FreeRTOS**

Pour ne plus ignorer le bouton, on utilise l'Interruption (EXTI). L'interruption est le moyen le plus efficace pour réagir à un événement asynchrone (appui bouton, capteur). Quand une interruption survient le matériel "stoppe" le programme principal pour exécuter une fonction spécifique : le Handler ou ISR. C'est comme une sonnette : peu importe ce que fait le processeur, il s'arrête, répond à la porte, puis reprend son travail.


Sur STM32F4, elle nécessite :

- L'activation de l'horloge `SYSCFG`. Pour dire "Écoute la pin PA0".
- Le multiplexage de la ligne EXTI vers le port souhaité.
- La configuration du front (montant/descendant).
- L'activation dans le `NVIC`. Ce dernier est le surveillant général qui autorise le processeur à être interrompu.



---
<br>

### **Synchronisation ISR vers Tâche (Sémaphore)**

Le concept le plus important est que l'interruption ne doit pas traiter la donnée, elle doit simplement "réveiller" une tâche de traitement. On utilise un [Sémaphore Binaire](../../rtos/#Semaphores). L'interruption (ISR) donne un signal (Sémaphore) à une tâche qui attendait patiemment.

Exemple : Un bouton (PA0) réveille une tâche via une interruption.

**A. Le Handler d'Interruption (ISR)**

```c
// 1. L'Interruption (Courte et rapide)
void EXTI0_IRQHandler(void) {
    BaseType_t xWoken = pdFALSE;

    if (EXTI->PR & EXTI_PR_PR0) {    // Vérifie le flag EXTI0
        EXTI->PR = EXTI_PR_PR0;      // // Effacer le flag // Acquitte l'interruption

        // Dire à FreeRTOS : "Le bouton a été pressé, libère le sémaphore !"
        xSemaphoreGiveFromISR(xSemBouton, &xWoken);     // Débloque la tâche associée
        
        // Force le changement de contexte immédiat
        portYIELD_FROM_ISR(xWoken);
    }
}
```

**B. La Tâche de Traitement**

```c
// 2. La Tâche (Tranquille et organisée)
void vTaskBouton(void *pvParameters) {
    for (;;) {
        // 1. Attend l'alerte de l'interruption
        // Attend le sémaphore indéfiniment (0% CPU en attente)
        if (xSemaphoreTake(xSemBouton, portMAX_DELAY) == pdPASS) {
            // Traitement lourd ici (ex: envoyer un message UART)
            Action_Apres_Appui();
        }
    }
}
```

Pratiquement une ISR doit être extrêmement courte. Sur STM32F4, la priorité d'une interruption utilisant FreeRTOS doit être numériquement supérieure ou égale à configMAX_SYSCALL_INTERRUPT_PRIORITY (généralement entre 5 et 15). Une priorité de 0 (trop haute) fera planter le noyau.


---
<br>


### [Système de Contrôle de LED avec Anti-rebond et File de Messages]{#projet-gpio-interrupt-freertos}

  
Concevoir un système robuste de pilotage d'une LED (PC13) à l'aide d'un bouton-poussoir (PA0) sur une carte Black Pill STM32F401. Le projet doit démontrer la capacité à mélanger la manipulation directe des registres et les mécanismes de synchronisation temps réel.

**Cahier des Charges**

1. Détection Matérielle (Réactivité) :

    - L'appui sur le bouton PA0 doit être détecté par une interruption externe (EXTI) pour garantir une réaction immédiate, même si le processeur exécute d'autres calculs.
    - Le processeur ne doit rester dans l'interruption que le temps strictement nécessaire pour signaler l'événement.

2. Traitement du Signal (Fiabilité) :

    - Une tâche dédiée (vTaskBouton) doit attendre le signal de l'interruption via un Sémaphore Binaire.
    - Pour éviter les déclenchements intempestifs dus aux rebonds mécaniques du bouton, implémenter un anti-rebond (Debounce) logiciel de 20ms en utilisant les fonctions de délai non-bloquantes de FreeRTOS.
    - Après le délai, effectuer une lecture directe du registre IDR pour confirmer que le bouton est toujours pressé.

3. Communication Inter-tâches (Modularité) :

    - Une fois l'appui confirmé, la tâche de lecture doit envoyer un ordre de changement d'état ("Toggle") dans une File de messages (Queue).
    - Une tâche de sortie (vTaskLED) doit surveiller cette file. Dès qu'un message arrive, elle doit inverser l'état de la LED PC13 en manipulant le registre ODR.

4. Optimisation Énergétique :

    - Le système doit être conçu de manière à ce qu'aucune tâche ne consomme de cycles CPU lorsqu'il n'y a pas d'activité sur le bouton (utilisation de portMAX_DELAY).

5. Contraintes Techniques (Bare Metal):

    - RCC : Activer les horloges des GPIOA et GPIOC.
    - GPIO : Configurer PC13 en sortie et PA0 en entrée avec résistance de Pull-up.
    - SYSCFG / EXTI : Mapper la ligne EXTI0 sur le port A.
    - NVIC : Configurer la priorité de l'interruption (supérieure ou égale à 5) pour être compatible avec l'API FreeRTOS.


```c
#include "stm32f401xx.h"
#include "FreeRTOS.h"
#include "task.h"
#include "semphr.h"
#include "queue.h"

// Ressources FreeRTOS 
SemaphoreHandle_t xSemBouton;  // Signal d'interruption
QueueHandle_t xQueueLED;       // File de commandes (0 = Off, 1 = On, 2 = Toggle)

// Configuration des Sorties (LED)
void Init_LED_PC13(void) {
    // 1. Activer l'horloge du Port C
    RCC->AHB1ENR |= RCC_AHB1ENR_GPIOCEN;
    // 2. Configurer PC13 en sortie (01)
    GPIOC->MODER &= ~(3U << (13 * 2));
    GPIOC->MODER |=  (1U << (13 * 2));
}

//Configuration des Entrées (Bouton)
void Init_Bouton_PA0(void) {
    // 1. Activer l'horloge du Port A
    RCC->AHB1ENR |= RCC_AHB1ENR_GPIOAEN;
    // 2. PA0 en entrée (00) avec Pull-up (01) pour éviter les signaux flottants
    GPIOA->MODER &= ~(3U << (0 * 2));
    GPIOA->PUPDR |=  (1U << (0 * 2));
}

// Configuration de l'Interruption (EXTI)
void Init_Interruption_EXTI0(void) {
    // 1. Activer l'horloge système pour la configuration des interruptions
    RCC->APB2ENR |= RCC_APB2ENR_SYSCFGEN;
    // 2. Lier la ligne EXTI0 au Port A
    SYSCFG->EXTICR[0] &= ~SYSCFG_EXTICR1_EXTI0;     // Mapper PA0 sur EXTI0
    // 3. Démasquer l'interruption et choisir le front descendant (appui)
    EXTI->IMR |= (1 << 0);      // Démasquer la ligne 0
    EXTI->FTSR |= (1 << 0);     // Détection Front Descendant
    // 4. Autoriser dans le NVIC avec une priorité compatible RTOS (>= 5)
    NVIC_SetPriority(EXTI0_IRQn, 5);
    NVIC_EnableIRQ(EXTI0_IRQn);
}

// Interruption (ISR)
void EXTI0_IRQHandler(void) {
    BaseType_t xWoken = pdFALSE;
    if (EXTI->PR & (1 << 0)) {
        EXTI->PR = (1 << 0); // Acquitter le flag matériel

        // Libérer le sémaphore pour réveiller la tâche de lecture
        xSemaphoreGiveFromISR(xSemBouton, &xWoken);
        portYIELD_FROM_ISR(xWoken);
    }
}

// Tâche bouton et debounce 
void vTaskBouton(void *pvParameters) {
    uint8_t commande = 2; // Code pour "Toggle"
    for (;;) {
        // Attend le signal de l'ISR
        if (xSemaphoreTake(xSemBouton, portMAX_DELAY) == pdPASS) {
            vTaskDelay(pdMS_TO_TICKS(20)); // Anti-rebond (Debounce)

            // Vérifier si le bouton est toujours pressé
            if (!(GPIOA->IDR & (1 << 0))) {     // Si bouton toujours pressé
                // Envoi de la commande à la LED via la QUEUE
                xQueueSend(xQueueLED, &commande, 0);
            }
        }
    }
}

// Tâche pour le pilotage de la LED 
void vTaskLED(void *pvParameters) {
    uint8_t cmdRecue;
    for (;;) {
        // Attend une commande de la queue (Bloquant, 0% CPU)
        if (xQueueReceive(xQueueLED, &cmdRecue, portMAX_DELAY) == pdPASS) {
            // Inverser PC13
            if (cmdRecue == 2) {
                GPIOC->ODR ^= (1 << 13);    // Écriture ODR
            }
        }
    }
}

int main(void) {
    Init_LED_PC13();
    Init_Bouton_PA0();
    Init_Interruption_EXTI0();

    // Création des objets RTOS
    xSemBouton = xSemaphoreCreateBinary();
    xQueueLED  = xQueueCreate(5, sizeof(uint8_t));

    if (xSemBouton != NULL && xQueueLED != NULL) {
        xTaskCreate(vTaskBouton, "BTN", 128, NULL, 2, NULL);
        xTaskCreate(vTaskLED,    "LED", 128, NULL, 1, NULL);

        vTaskStartScheduler(); // Lancement de l'orchestre
    }

    while(1);
}
```

**La Phase d'Initialisation (L'Installation de l'usine)**
Dans la fonction Prv_SetupHardware, nous préparons le terrain en Bare Metal.
- Les Horloges (RCC) : On active l'électricité pour les ports A et C. Sans cela, les registres restent "morts".
- Le Mode (MODER) : On dit à la broche PC13 d'être une sortie (pour la LED) et à PA0 d'être une entrée (pour le bouton).
- L'Interruption (EXTI & NVIC) : On configure le matériel pour qu'il surveille tout seul la pin PA0. Le NVIC est le "vigile" qui autorise cette interruption à stopper le processeur.

**L'Interruption : Le "Signal de Réveil"**
La fonction EXTI0_IRQHandler est déclenchée instantanément par le matériel dès que vous appuyez sur le bouton.
- Pourquoi est-elle courte ? Elle ne fait qu'une chose : "donner un jeton" au sémaphore (xSemaphoreGiveFromISR).
- Le passage de témoin : Elle réveille la tâche vTaskBouton qui dormait, puis s'arrête. Le processeur n'est resté bloqué dans l'interruption que quelques microsecondes.

**La Tâche "Lecteur" : Le Filtrage Intelligent**
C'est ici que la magie de FreeRTOS opère.
- L'attente efficace : xSemaphoreTake met la tâche en sommeil profond (0% CPU) tant que le bouton n'est pas touché.
- Le Debounce (Anti-rebond) : Quand elle se réveille, elle attend 20ms avec vTaskDelay. Pendant ce temps, FreeRTOS peut faire autre chose !
- La Lecture réelle (IDR) : Après le délai, on vérifie via le registre IDR si le bouton est toujours pressé. Cela permet d'ignorer les parasites électriques (étincelles de contact).
- Le Message : Si l'appui est confirmé, elle envoie un "ordre" dans la file (xQueueSend).

**La Tâche "Actionneur" : L'Exécution**
Cette tâche gère uniquement la LED.
- Séparation des rôles : Elle ne sait pas qu'il y a un bouton. Elle attend simplement un message dans sa boîte aux lettres (xQueueReceive).
- L'Écriture (ODR) : Dès qu'elle reçoit un message, elle utilise l'opérateur XOR (^) sur le registre ODR pour inverser l'état de la LED (Toggle).

---
<br>

### Liens connexe

- [Timer et Interruption](stm32f4/timer/index.md)