# Timers, Interruptions Matérielles et FreeRTOS

*Ir Paul S. Kabidu, M.Eng. <spaulkabidu@gmail.com>*
{: style="text-align: center;" }

---

[Accueil](../../#Accueil)
  
<br>
<br>



### **Un Timer**

Un **timer** est un compteur matériel de précision, indépendant du CPU. Contrairement à une boucle `for`, il ne s'arrête jamais, même si le processeur exécute d'autres tâches. Il permet de générer des événements, des délais, et une synchronisation temporelle lorsque certaines valeurs sont atteintes.

Le STM32F401 possède plusieurs blocs de temporisation : des timers généralistes 16/32 bits (TIM2, TIM3, TIM4, TIM5), des timers avancés (TIM1, TIM8) pour des fonctions complexes (PWM, capture/compare), et des timers de base (TIM6, TIM7) dédiés au déclenchement du DAC. Dans ce chapitre, nous nous concentrerons sur les timers généralistes en mode **débordement (update event)** , qui est la base de toute utilisation.

Le timer possède un compteur qui s'incrémente à chaque impulsion d'une horloge. Le mécanisme repose sur trois registres principaux :

- **Prescaler (PSC)** : divise la fréquence de l'horloge interne (souvent plusieurs MHz) pour ralentir le compteur.
- **Auto-Reload Register (ARR)** : définit la valeur maximale du compteur. Quand le compteur `CNT` atteint `ARR`, un événement de mise à jour (update) est généré, et `CNT` est remis à zéro (en mode *upcounting*). C'est le **débordement**.
- **Compteur (CNT)** : valeur actuelle du compteur (s'incrémente à chaque coup d'horloge).

#### Registres principaux

| Registre   | Nom                    | Fonction                                                         |
|------------|------------------------|------------------------------------------------------------------|
| `TIMx_PSC` | Prescaler              | Divise la fréquence d'entrée : `f_timer = f_ck / (PSC + 1)`      |
| `TIMx_ARR` | Auto-Reload Register   | Définit la période du timer (la "cible")                         |
| `TIMx_DIER`| DMA/Interrupt Enable   | Permet d'activer l'interruption lors d'un débordement (bit `UIE`)|
| `TIMx_CR1` | Control Register 1     | Utilisé notamment pour démarrer le timer (bit `CEN`)              |
| `TIMx_SR`  | Status Register        | Contient le flag (`UIF`) qui indique si le temps est écoulé      |

Tous ces registres sont décrits en détail dans le [Reference Manual (RM0368)](https://www.st.com/resource/en/reference_manual/rm0368-stm32f401xbc-and-stm32f401xde-advanced-armbased-32bit-mcus-stmicroelectronics.pdf) détaille tous les registres..

---
<br>




### **Configuration d’un timer en mode débordement (Update Event)**

L'utilisation la plus simple d'un timer consiste à le faire compter jusqu'à une valeur (`ARR`) et à générer une interruption à chaque débordement. Cela permet de créer une base de temps régulière (par exemple 1 ms) sans occuper le CPU.

**Étapes de configuration (bare metal, sans RTOS)**

1. **Activer l'horloge du timer** (via `RCC_APB1ENR` ou `RCC_APB2ENR` selon le timer).
2. **Configurer le prescaler (`PSC`)** et la valeur de reload (`ARR`) pour obtenir la fréquence souhaitée.
3. **Activer l'interruption de mise à jour** dans le registre `DIER`.
4. **Configurer et activer l'interruption dans le NVIC** (priorité, activation).
5. **Démarrer le timer** en positionnant le bit `CEN` (Counter Enable) dans `CR1`.


**Exemple : Chronomètre précis (polling) : Génération d'un délai avec un timer**

On peut aussi utiliser un timer pour générer un délai en attendant le flag UIF. L'avantage est de pouvoir utiliser des timers 32 bits pour de très longs délais.

```c
#include "stm32f4xx.h"

// Attente active mais précise (polling)
void delaySec(uint32_t sec) {
    // 1. Activer l'horloge du Timer 2 (sur APB1)
    RCC->APB1ENR |= RCC_APB1ENR_TIM2EN;

    // 2. Configurer PSC et ARR pour 1 seconde
    //    f_timer = 84 MHz / 8400 = 10 kHz (0,100 ms par tick)
    //    ARR = 9999 -> période de 1 s (10000 ticks)
    TIM2->PSC = 8400 - 1;
    TIM2->ARR = 10000 * sec - 1;    // // 10 kHz * sec

    // 3. Lancer le timer
    TIM2->CR1 |= TIM_CR1_CEN;

    TIM2->CNT = 0;                          // Reset compteur
    while(!(TIM2->SR & TIM_SR_UIF));        // Attendre le flag Update
    TIM2->SR &= ~TIM_SR_UIF;                 // Effacer le flag
}
```

Remarque : Le calcul de la fréquence est :
f_update = f_timer / (ARR + 1) = (f_ck / (PSC + 1)) / (ARR + 1).

Dans l'exemple, avec f_ck = 84 MHz, PSC = 83999, ARR = 999, on obtient :
f_update = 84e6 / 84000 / 1000 = 1 Hz.


Exemple : Faire clignoter une LED sur PC13 à 1 Hz en utilisant TIM2 (32 bits) avec une horloge à 84 MHz.

```c
#include "stm32f4xx.h"

// Attente active mais précise (polling)
void delaySec(uint32_t sec) {
    // 1. Activer l'horloge du Timer 2 (sur APB1)
    RCC->APB1ENR |= RCC_APB1ENR_TIM2EN;

    // 2. Configurer PSC et ARR pour 1 seconde
    //    f_timer = 84 MHz / 8400 = 10 kHz (0,100 ms par tick)
    //    ARR = 9999 -> période de 1 s (10000 ticks)
    TIM2->PSC = 8400 - 1;
    TIM2->ARR = 10000 * sec - 1;    // // 10 kHz * sec

    // 3. Lancer le timer
    TIM2->CR1 |= TIM_CR1_CEN;

    TIM2->CNT = 0;                          // Reset compteur
    while(!(TIM2->SR & TIM_SR_UIF));        // Attendre le flag Update
    TIM2->SR &= ~TIM_SR_UIF;                 // Effacer le flag
}

int main(void) {
    // Configuration de la LED
    RCC->AHB1ENR |= RCC_AHB1ENR_GPIOCEN;
    GPIOC->MODER |= (1 << (13*2));
    GPIOC->ODR &= ~(1 << 13);

    while (1) {
        GPIOC->ODR ^= (1 << 13); // bascule la LED
        delaySec(1);
    }
}
```
---
<br>



### **Mode comparaison (output compare)**

Le mode comparaison permet de générer un signal sur une broche lorsqu'un événement de comparaison se produit. Le timer compare en permanence la valeur du compteur avec un ou plusieurs registres `CCRx`. En cas d'égalité, une action prédéfinie peut être effectuée sur la broche correspondante (mise à 1, mise à 0, basculement). Cela permet de générer des signaux périodiques sans intervention du processeur.

**Configuration**

Pour utiliser la comparaison, il faut :

- Configurer la broche en mode alternate function correspondant au timer (ex: PA5 pour TIM2_CH1).
- Activer l'horloge du timer.
- Régler `PSC` et `ARR` pour la période souhaitée.
- Configurer `CCMRx` pour le mode de sortie (par exemple, basculement).
- Positionner `CCRx` à la valeur de comparaison.
- Activer la sortie dans `CCER`.
- Lancer le compteur.

Exemple : Générer un signal carré de 1 Hz sur PA5 (TIM2_CH1). On choisit PSC = 8399 (→ 10 kHz), ARR = 4999 (période de 5000 ticks, soit 0,5 s). En basculant la sortie à chaque fois que le compteur atteint CCR1, on obtiendra une période de 1 s. On fixe CCR1 = 0 pour que le basculement ait lieu à chaque début de cycle.

```c
#include "stm32f4xx.h"

int main(void) {
    // Configuration de PA5 en alternate function AF1 pour TIM2_CH1
    RCC->AHB1ENR |= RCC_AHB1ENR_GPIOAEN;
    GPIOA->MODER &= ~(3U << (5*2));
    GPIOA->MODER |=  (2U << (5*2));   // alternate function
    GPIOA->AFR[0] &= ~(0xF << (5*4));
    GPIOA->AFR[0] |=  (1 << (5*4));   // AF1

    // Activation de TIM2
    RCC->APB1ENR |= RCC_APB1ENR_TIM2EN;

    // Configuration pour 1 Hz
    TIM2->PSC = 8399;          // 84 MHz / 8400 = 10 kHz
    TIM2->ARR = 4999;          // période 5000 ticks → 0,5 s
    // Mode toggle sur match (OC1M = 011)
    TIM2->CCMR1 |= (0x3 << 4); // bits 4:2 = 011
    TIM2->CCR1 = 0;             // compare à 0
    TIM2->CCER |= TIM_CCER_CC1E; // activer la sortie sur CH1
    TIM2->CNT = 0;
    TIM2->CR1 |= TIM_CR1_CEN;    // démarrer

    while (1) {
        // Rien à faire, le signal est généré automatiquement
    }
}
```

Remarque : Le mode toggle fait basculer la broche à chaque match. Avec `CCR1 = 0`, le match a lieu lorsque `CNT` passe de 0 à 1 (au début du cycle). Ainsi, la broche bascule tous les 5000 ticks, soit 2 fois par période, ce qui donne une fréquence de 1 Hz.

---
<br>



### **Mode capture (input capture)**

Le mode capture permet de mesurer la fréquence ou la largeur d'impulsion d'un signal externe. Lorsqu'un événement (front montant/descendant) se produit sur la broche d'entrée, la valeur courante du compteur est copiée dans le registre `CCRx`, et un flag est levé.

**Configuration**

Pour utiliser la capture, il faut :

- Configurer la broche en mode alternate function.
- Activer l'horloge du timer.
- Régler le prescaler du timer (pour ajuster la résolution).
- Configurer CCMRx pour sélectionner le mode capture (`CCxS = 01` ou `10` selon la source).
- Choisir le front déclencheur dans `CCER` (bits CCxP et CCxNP).
- Activer la capture dans `CCER` (CCxE = 1).
- Lancer le compteur.

Exemple : Mesurer la fréquence d'un signal sur PA6 (TIM3_CH1). On utilise TIM3, 16 bits, avec une horloge de 10 kHz (PSC = 8399) pour obtenir une résolution de 0,1 ms. On capture les fronts montants. La période en millisecondes est donnée par la différence entre deux captures consécutives.

```c
#include "stm32f4xx.h"

volatile uint16_t lastCapture = 0;
volatile uint16_t period = 0;
volatile uint8_t captureDone = 0;

void TIM3_IRQHandler(void) {
    if (TIM3->SR & TIM_SR_CC1IF) {
        TIM3->SR &= ~TIM_SR_CC1IF;
        uint16_t capture = TIM3->CCR1;
        period = capture - lastCapture;
        lastCapture = capture;
        captureDone = 1;
    }
}

int main(void) {
    // Configuration de PA6 en alternate function AF2 pour TIM3_CH1
    RCC->AHB1ENR |= RCC_AHB1ENR_GPIOAEN;
    GPIOA->MODER &= ~(3U << (6*2));
    GPIOA->MODER |=  (2U << (6*2));
    GPIOA->AFR[0] &= ~(0xF << (6*4));
    GPIOA->AFR[0] |=  (2 << (6*4));   // AF2

    // Activation de TIM3
    RCC->APB1ENR |= RCC_APB1ENR_TIM3EN;

    // Configuration : PSC = 8399 → 10 kHz
    TIM3->PSC = 8399;
    TIM3->ARR = 0xFFFF;        // valeur max (16 bits)
    TIM3->CCMR1 = TIM_CCMR1_CC1S_0; // CC1 channel as input, IC1 mapped on TI1
    TIM3->CCER |= TIM_CCER_CC1E;     // capture sur front montant (par défaut)
    TIM3->DIER |= TIM_DIER_CC1IE;    // interruption sur capture
    NVIC_EnableIRQ(TIM3_IRQn);
    NVIC_SetPriority(TIM3_IRQn, 5);
    TIM3->CR1 |= TIM_CR1_CEN;         // démarrer

    while (1) {
        if (captureDone) {
            captureDone = 0;
            // Calcul de la fréquence : f = 10 kHz / period (si period est en ticks)
            // Attention au débordement du compteur 16 bits pour les périodes longues.
        }
    }
}
```

Remarque : Il faut gérer les débordements du compteur 16 bits pour des périodes longues. On peut utiliser l'interruption de débordement (UIF) ou utiliser un timer 32 bits comme TIM2.

---
<br>



### **Compteur d'événements (external clock)**

Les timers peuvent également être cadencés par une source externe (broche ETR). Cela permet de compter le nombre d'impulsions sur une broche. Par exemple, pour compter des objets sur un tapis roulant.

Exemple : Utiliser TIM2 avec l'entrée ETR sur PA0 (AF1). Chaque front montant sur PA0 incrémente le compteur.

```c
#include "stm32f4xx.h"

int main(void) {
    // Configuration de PA0 en alternate function AF1 pour TIM2_ETR
    RCC->AHB1ENR |= RCC_AHB1ENR_GPIOAEN;
    GPIOA->MODER &= ~(3U << (0*2));
    GPIOA->MODER |=  (2U << (0*2));
    GPIOA->AFR[0] &= ~(0xF << (0*4));
    GPIOA->AFR[0] |=  (1 << (0*4));   // AF1

    // Activation de TIM2
    RCC->APB1ENR |= RCC_APB1ENR_TIM2EN;

    // Configuration en mode esclave avec ETR comme source d'horloge
    TIM2->SMCR = TIM_SMCR_ECE; // bit ECE = 1, external clock enable
    // Optionnel : on peut aussi configurer un prescaler sur l'entrée ETR via ETPS
    TIM2->CNT = 0;
    TIM2->CR1 |= TIM_CR1_CEN;

    // Boucle principale : lecture du compteur
    while (1) {
        uint32_t count = TIM2->CNT;
        // Afficher ou utiliser count...
    }
}
```

Remarque : Le mode ETR utilise le signal comme horloge du compteur. Si on veut compter des fronts, il faut configurer le prescaler ETR (bits ETPS) et la polarité (ETP) dans `SMCR`.

---
<br>



### **Interruption du Timer**

Le timer peut générer une interruption de mise à jour (UIF) lorsqu'il déborde. Le bit `UIE` dans `TIMx_DIER` active cette interruption.

Au lieu de surveiller le registre `SR` (polling) comme precedement, on laisse le matériel prévenir le CPU, le Timer prévient le processeur dès que le temps est écoulé via une ISR (Interrupt Service Routine). C'est l'usage du **NVIC** combiné au Timer.

- On active l'interruption dans le timer : `TIM2->DIER |= TIM_DIER_UIE;`.
- On active la ligne dans le gestionnaire d'interruptions : `NVIC_EnableIRQ(TIM2_IRQn);`.

**Exemple : Générer une interruption toutes les 100 ms avec TIM2.**

Sur la carte Black Pill, l'horloge système est généralement à 84 MHz. Le timer TIM2 est sur le bus APB1 dont la fréquence est aussi 84 MHz (car le prescaler de bus est à 1). Pour obtenir une interruption toutes les 100 ms, on peut choisir une résolution de 1 ms (1000 Hz) et un débordement après 100 ticks.

Calcul :

- On veut une période d'interruption de 100 ms = 0,1 s, soit une fréquence de 10 Hz.
- Si on choisit PSC = 8399 (soit 8400 - 1), alors f_timer = 84 MHz / 8400 = 10 kHz.
- Avec ARR = 999 (1000 - 1), on obtient une fréquence d'update de 10 kHz / 1000 = 10 Hz, soit une période de 100 ms.

Ou plus simplement, on peut choisir PSC = 8399 et ARR = 999.

Exemple : clignotement LED avec TIM2 à 1 Hz

```c
#include "stm32f4xx.h"

void Timer2_Init(void) {
    // 1. Activer l'horloge du Timer 2 (sur APB1)
    RCC->APB1ENR |= RCC_APB1ENR_TIM2EN; 
    
    // 2. Configurer PSC et ARR pour 100 ms
    //    f_timer = 84 MHz / (8399+1) = 10 kHz
    //    TIM2 à 1 Hz (84 MHz / 8400 / 10000 = 1 Hz)
    //    ARR = 9999 -> update toutes les 10000 ticks = 0.1 s
    TIM2->PSC = 8400 - 1;       // Prescaler
    TIM2->ARR = 10000 - 1;      // Auto-reload

    // 3. Activer l'interruption de mise à jour (update)
    TIM2->DIER |= TIM_DIER_UIE;

    // 4. Configurer et activer l'interruption dans le NVIC
    NVIC_SetPriority(TIM2_IRQn, 2);       // Priorité (ajustable)
    NVIC_EnableIRQ(TIM2_IRQn);

    // 5. Démarrer le timer
    TIM2->CR1 |= TIM_CR1_CEN;
}

// Handler d'interruption de TIM2
void TIM2_IRQHandler(void) {
    if (TIM2->SR & TIM_SR_UIF) {          // Vérifier le flag de mise à jour
        TIM2->SR &= ~TIM_SR_UIF;           // Acquitter le flag (écrire 0)

        // Action à effectuer toutes les 100 ms
        // Exemple : basculer une LED sur PC13
        GPIOC->ODR ^= (1 << 13);
    }
}

int main(void) {
    // LED PC13
    RCC->AHB1ENR |= RCC_AHB1ENR_GPIOCEN;
    GPIOC->MODER |= (1 << (13*2));
    GPIOC->ODR |= (1 << 13);

    Timer2_Init();

    while (1);
}
```

---
<br>



### **Timer avec FreeRTOS : Créer une Tâche Périodique Précise**

Dans un environnement RTOS, on peut utiliser un timer matériel pour réveiller périodiquement une tâche, de manière plus précise et indépendante du tick système que `vTaskDelayUntil()` (qui dépend de la résolution du tick). On combine alors l'interruption timer avec un **sémaphore** ou une **notification de tâche**.

**Principe :**

- L'interruption timer donne un sémaphore (ou envoie une notification) à une tâche.
- La tâche attend ce sémaphore et exécute son code à chaque réveil.
- Ainsi, la tâche s'exécute exactement à la fréquence du timer, avec une gigue minimale.

**Exemple : Tâche exécutée toutes les 100 ms via TIM2 (sémaphore)**

```c
#include "FreeRTOS.h"
#include "task.h"
#include "semphr.h"

SemaphoreHandle_t xSemTimer;

void TIM2_IRQHandler(void) {
    BaseType_t xWoken = pdFALSE;

    if (TIM2->SR & TIM_SR_UIF) {
        TIM2->SR &= ~TIM_SR_UIF;

        // Donner le sémaphore depuis l'ISR
        xSemaphoreGiveFromISR(xSemTimer, &xWoken);
        portYIELD_FROM_ISR(xWoken);
    }
}

void vTaskPeriodic(void *pvParameters) {
    for (;;) {
        // Attendre le sémaphore (bloquant)
        xSemaphoreTake(xSemTimer, portMAX_DELAY);

        // Code exécuté toutes les 100 ms
        // Par exemple : basculer une LED
        GPIOC->ODR ^= (1 << 13);

        // Ou toute autre action périodique
    }
}

int main(void) {
    // Initialisation de la LED PC13
    RCC->AHB1ENR |= RCC_AHB1ENR_GPIOCEN;
    GPIOC->MODER |= (1 << (13 * 2));

    // Initialisation du timer (comme ci-dessus, sans l'action dans l'ISR)
    Timer_Init();  // on réutilise la fonction précédente, mais en enlevant le basculement dans l'ISR

    // Création du sémaphore
    xSemTimer = xSemaphoreCreateBinary();

    if (xSemTimer != NULL) {
        // Création de la tâche périodique
        xTaskCreate(vTaskPeriodic, "Periodic", 128, NULL, 2, NULL);

        // Lancement de l'ordonnanceur
        vTaskStartScheduler();
    }

    while(1);
}
```

Cette architecture est très efficace : la tâche dort (0% CPU) entre les réveils, et l'ISR est ultra-courte.

---
<br>




### **Les Timers Logiciels (Software Timers)**

Contrairement aux timers matériels, les **Software Timers** sont gérés entièrement par le noyau FreeRTOS. Ils permettent de déclencher des fonctions (callbacks) définie par l'utilisateur sans mobiliser de périphériques matériels supplémentaires. Ils utilisent le timer SysTick, le même que celui du noyau. Un seul timer matériel (le SysTick) peut ainsi gérer des dizaines de timers logiciels.

**Attention** : La fonction callback exécutée à l'expiration ne doit jamais contenir de code bloquant (pas de `vTaskDelay` ou de sémaphore bloquant).

Les timers logiciels sont optionnels dans FreeRTOS. Pour utiliser ces timers, les constantes suivantes doivent être définies dans `FreeRTOSConfig.h` :

```c
#define configUSE_TIMERS             1
#define configTIMER_TASK_PRIORITY    (configMAX_PRIORITIES - 1)
#define configTIMER_QUEUE_LENGTH     10
#define configTIMER_TASK_STACK_DEPTH 
```

**Exemple Pratique : Timer "One-Shot" vs "Auto-Reload"**

Deux types de timers sont disponibles :

- One-shot : le timer s'exécute une seule fois après un délai, puis s'arrête.
- Auto-reload : le timer se réinitialise automatiquement à chaque expiration, provoquant une exécution périodique de la fonction de rappel.

**Création d'un timer**
La fonction `xTimerCreate()` crée un timer et retourne un handle permettant de le manipuler.

```c
TimerHandle_t xTimerCreate(
    const char * const pcTimerName, // nom du timer (pour le débogage).
    const TickType_t xTimerPeriodInTicks,   // période en ticks (utilisez pdMS_TO_TICKS(ms) pour convertir)
    const UBaseType_t uxAutoReload,     // pdTRUE pour un auto-reload, pdFALSE pour one-shot.
    void * const pvTimerID,     // identifiant utilisateur (peut être utilisé dans la callback pour distinguer plusieurs timers partageant la même fonction).
    TimerCallbackFunction_t pxCallbackFunction  // pointeur vers la fonction de rappel (prototype : void vCallback(TimerHandle_t xTimer)).
);
```
Retourne `NULL` si la mémoire est insuffisante, sinon un handle.

**Démarrer, arrêter, réinitialiser un timer**

Les fonctions suivantes envoient des commandes à la tâche de service via une file d'attente interne (timer command queue). Le paramètre `xTicksToWait` indique le temps d'attente maximal si la file est pleine.

```c
BaseType_t xTimerStart(TimerHandle_t xTimer, TickType_t xTicksToWait);
BaseType_t xTimerStop(TimerHandle_t xTimer, TickType_t xTicksToWait);
BaseType_t xTimerReset(TimerHandle_t xTimer, TickType_t xTicksToWait);
BaseType_t xTimerDelete(TimerHandle_t xTimer, TickType_t xTicksToWait);
```
Toutes retournent pdPASS si la commande a été envoyée, pdFAIL sinon.

**Changer la période**

```c
BaseType_t xTimerChangePeriod(TimerHandle_t xTimer, TickType_t xNewPeriod, TickType_t xTicksToWait);
```
Si le timer est actif, la nouvelle période s'applique immédiatement et le temps d'expiration est recalculé à partir de l'appel. S'il est inactif, il démarre avec la nouvelle période.

```c
TimerHandle_t xAutoTimer;

// La fonction de rappel (Callback)
void vTimerCallback(TimerHandle_t xTimer) {
    // Action à effectuer à chaque expiration
    GPIOC->ODR ^= (1 << 13); 
}

void main_rtos(void) {
    // Création d'un timer périodique de 500ms
    xAutoTimer = xTimerCreate(
        "AutoTimer",            // Nom
        pdMS_TO_TICKS(500),     // Période
        pdTRUE,                 // pdTRUE = Auto-Reload, pdFALSE = One-Shot
        (void *) 0,             // ID du timer
        vTimerCallback          // Fonction à appeler
    );

    if (xAutoTimer != NULL) {
        xTimerStart(xAutoTimer, 0); // Lancement du timer
    }
    
    vTaskStartScheduler();
}
```

Le choix du timer dépend de la précision requise. Le timer matériel (TIMx) offre une précision nanoseconde / microseconde idéale pour le contrôle moteur, la PWM et l'échantillonnage ADC malgré une haute complexité de mise en œuvre. Tandisque le timer logiciel (FreeRTOS), basé sur le tick système, est préférable pour des usages moins sensibles au temps réel comme les timeouts de communication, le debouncing et la gestion d'écran IHM, grâce à sa faible complexité. 

Plus d'informations sur ce sujet sont disponibles en consultant la documentation de l'API FreeRTOS et les fiches techniques du MCU.

---
<br>



### **Compteur de fréquence (ou d'événements)**

Ce projet utilise un timer auto-reload pour compter le nombre d'impulsions sur une broche (PA6) pendant une seconde. Le résultat est affiché via UART.

```c
#include "FreeRTOS.h"
#include "task.h"
#include "timers.h"
#include "stm32f4xx.h"
#include <stdio.h>

volatile uint32_t pulseCount = 0;
TimerHandle_t xTimer;

void GPIO_Init(void) {
    RCC->AHB1ENR |= RCC_AHB1ENR_GPIOAEN;
    GPIOA->MODER &= ~(3U << (6*2)); // PA6 en entrée
    GPIOA->PUPDR &= ~(3U << (6*2)); // pas de pull-up/pull-down
}

void EXTI9_5_IRQHandler(void) {
    if (EXTI->PR & (1 << 6)) {
        EXTI->PR = (1 << 6);
        pulseCount++;
    }
}

void EXTI_Init(void) {
    RCC->APB2ENR |= RCC_APB2ENR_SYSCFGEN;
    SYSCFG->EXTICR[1] &= ~SYSCFG_EXTICR2_EXTI6;
    SYSCFG->EXTICR[1] |= SYSCFG_EXTICR2_EXTI6_PA; // PA6 sur EXTI6
    EXTI->IMR |= (1 << 6);
    EXTI->RTSR |= (1 << 6); // front montant
    NVIC_SetPriority(EXTI9_5_IRQn, 5);
    NVIC_EnableIRQ(EXTI9_5_IRQn);
}

void vTimerCallback(TimerHandle_t xTimer) {
    static uint32_t lastCount = 0;
    uint32_t freq = pulseCount - lastCount;
    lastCount = pulseCount;
    char buffer[32];
    sprintf(buffer, "Frequence : %lu Hz\r\n", freq);
    USART2_SendString(buffer);
}

int main(void) {
    GPIO_Init();
    EXTI_Init();
    USART2_Init(115200);

    xTimer = xTimerCreate("Freq", pdMS_TO_TICKS(1000), pdTRUE, 0, vTimerCallback);
    if (xTimer != NULL) {
        xTimerStart(xTimer, 0);
    }
    vTaskStartScheduler();
    while(1);
}
```

---
<br>

### **Réveil périodique précis pour acquisition de données**

Nous allons maintenant construire un système complet qui utilise un timer matériel pour générer une base de temps précise (1 seconde), et deux tâches FreeRTOS : l'une pour traiter l'événement (afficher un compteur sur UART), l'autre pour faire clignoter une LED indépendamment, afin de montrer le multitâche.

**Cahier des charges**

- **Timer matériel** : configuré pour générer une interruption toutes les 1 seconde (PSC=8399, ARR=9999).
- **ISR** : incrémente un compteur partagé et donne un sémaphore (ou envoie une notification) à une tâche d'affichage. L'ISR est courte : elle incrémente seconds et donne le sémaphore.
- **Tâche `vTaskDisplay`** : attend le sémaphore et affiche la valeur du compteur via UART. La tâche `vTaskDisplay` est bloquée sur `xSemaphoreTake` ; elle se réveille exactement à chaque seconde, sans consommer de CPU entre-temps.
- **Tâche `vTaskBlink`** : fait clignoter la LED PC13 à une fréquence de 2 Hz indépendamment (utilise `vTaskDelay`). On observe que les deux tâches coexistent parfaitement.
- **UART** : configuré en sortie pour printf (exemple avec USART2). Configuré pour printf. Chaque seconde, le compteur s'affiche sur le terminal série.

Ce projet illustre l'utilisation conjointe d'un timer matériel, d'une ISR respectant les règles FreeRTOS, d'un sémaphore pour la synchronisation, et d'une tâche périodique gérée par le RTOS.

```c
#include "stm32f4xx.h"
#include "FreeRTOS.h"
#include "task.h"
#include "semphr.h"
#include <stdio.h>

// Sémaphore pour signaler la seconde
SemaphoreHandle_t xSemSecond;

// Compteur de secondes (partagé, doit être volatile)
volatile uint32_t seconds = 0;

// Initialisation du timer pour 1 seconde
void Timer_Init_1s(void) {
    RCC->APB1ENR |= RCC_APB1ENR_TIM2EN;

    // f_timer = 84 MHz / 8400 = 10 kHz
    TIM2->PSC = 8399;
    // ARR = 9999 => 10 kHz / 10000 = 1 Hz
    TIM2->ARR = 9999;

    TIM2->DIER |= TIM_DIER_UIE;           // Interruption sur update

    NVIC_SetPriority(TIM2_IRQn, 5);        // Priorité compatible FreeRTOS
    NVIC_EnableIRQ(TIM2_IRQn);

    TIM2->CR1 |= TIM_CR1_CEN;               // Démarrer
}

// ISR du timer
void TIM2_IRQHandler(void) {
    BaseType_t xWoken = pdFALSE;

    if (TIM2->SR & TIM_SR_UIF) {
        TIM2->SR &= ~TIM_SR_UIF;

        seconds++;                           // Incrémenter le compteur

        // Donner le sémaphore
        xSemaphoreGiveFromISR(xSemSecond, &xWoken);
        portYIELD_FROM_ISR(xWoken);
    }
}

// Tâche d'affichage sur UART
void vTaskDisplay(void *pvParameters) {
    for (;;) {
        xSemaphoreTake(xSemSecond, portMAX_DELAY);
        printf("Seconde : %lu\n", seconds);
    }
}

// Tâche de clignotement LED (2 Hz)
void vTaskBlink(void *pvParameters) {
    RCC->AHB1ENR |= RCC_AHB1ENR_GPIOCEN;
    GPIOC->MODER |= (1 << (13 * 2));

    for (;;) {
        GPIOC->ODR ^= (1 << 13);
        vTaskDelay(pdMS_TO_TICKS(250));      // 250 ms -> 2 Hz
    }
}

// Initialisation UART (USART2 sur PA2)
void UART_Init(uint32_t baud) {
    RCC->AHB1ENR |= RCC_AHB1ENR_GPIOAEN;
    RCC->APB1ENR |= RCC_APB1ENR_USART2EN;

    // PA2 en alternate function AF7 (USART2_TX)
    GPIOA->MODER |= (2 << (2*2));
    GPIOA->AFR[0] |= (7 << (2*4));

    USART2->BRR = 84000000 / baud;         // 115200 bauds
    USART2->CR1 = USART_CR1_TE | USART_CR1_UE;
}

// Réimplémentation de _write pour printf (via UART)
int _write(int file, char *ptr, int len) {
    for (int i = 0; i < len; i++) {
        while (!(USART2->SR & USART_SR_TXE));
        USART2->DR = ptr[i];
    }
    return len;
}

int main(void) {
    UART_Init(115200);
    Timer_Init_1s();

    xSemSecond = xSemaphoreCreateBinary();

    if (xSemSecond != NULL) {
        xTaskCreate(vTaskDisplay, "Display", 256, NULL, 1, NULL);
        xTaskCreate(vTaskBlink,   "Blink",   128, NULL, 1, NULL);
        vTaskStartScheduler();
    }

    while(1);
}
```
---
<br>



### Liens connexes

- [GPIO et Interruptions](../gpio/index.md)
- [Machine d’État Fini (FSM)](../../technique-algos/fsm/index.md)
- [Introduction pratique à freeRTOS](../../rtos/freertos.md)
- [Acquisition Analogique via ADC](../adc/index.md)
- [Machine d’État Fini (FSM)](../../technique-algos/fsm/index.md)
- [Présentation architecturale du Microcontrôleur STM32F4](../stm32f4/mcu_intro/index.md)
