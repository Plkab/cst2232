# La Machine d'Etats Finis (FSM - Finite State Machine) 

*Ir Paul S. Kabidu, M.Eng. <spaulkabidu@gmail.com>*
{: style="text-align: center;" }

---

[Accueil](../../#Accueil)
  
<br>
<br>


### **La Machine d'Etats Finis**

En ingénierie, on ne code pas une logique complexe par "essais et erreurs" avec des séries de `if/else` imbriqués (souvent appelés "code spaghetti"). On utilise la FSM pour garantir que le système est **déterministe** et **prévisible**, on utilise les **machines à états finis (FSM)**.

Lorsque les systèmes deviennent complexes (comme un distributeur automatique, un digicode, ou un protocole de communication), il devient vite difficile de gérer toute la logique avec des `if...else` éparpillés. C'est là qu'interviennent les **machines à états finis (FSM)**.

Une FSM est un modèle mathématique utilisé pour concevoir des systèmes séquentiels. Elle permet de représenter le comportement d'un système par un nombre fini d'**états**, de **transitions** entre ces états, et d'**actions** associées. Les FSM sont omniprésentes en ingénierie embarquée : contrôle de moteurs, protocoles de communication (UART, I2C), interfaces homme-machine, etc.

L'objectif de ce chapitre est de vous montrer comment modéliser et implémenter une FSM en C, en l'intégrant dans un environnement temps réel avec FreeRTOS, tout en réutilisant les concepts déjà acquis (GPIO, interruptions, timers).

---
<br>


### **Concepts de Base d'une FSM**

Une machine à états finis est définie par cinq entités :

- **États symboliques** : situations dans lesquelles le système peut se trouver (ex: `IDLE`, `WAITING`, `ACTIVE`).
- **Signaux d'entrée** : événements ou conditions qui déclenchent des transitions.
- **Signaux de sortie** : actions produites par la machine.
- **Fonction de prochain état** : détermine le prochain état en fonction de l'état courant et des entrées.
- **Fonction de sortie** : détermine les sorties en fonction de l'état courant (et éventuellement des entrées).

On distingue deux types de FSM selon la fonction de sortie :

- **Machine de Moore** : les sorties dépendent **uniquement de l'état courant**. Elles sont stables pendant tout le temps où l'état est actif.
- **Machine de Mealy** : les sorties dépendent **de l'état courant et des entrées**. Elles peuvent changer immédiatement en réponse à une entrée, même sans changement d'état.

En pratique, on utilise souvent un mixte des deux.


**Démarche de conception**

1. **Modélisation (formalisme)** : avant de coder, l'ingénieur dessine un **diagramme d'états** ou un **diagramme ASM** (Algorithmic State Machine). Chaque état représente un comportement stable, et chaque flèche représente une transition déclenchée par un événement.

2. **Robustesse** : la FSM permet de définir exactement ce qui se passe si un événement imprévu survient. C'est la base des systèmes critiques (médical, aéronautique).

3. **Implémentation propre** : en C, on utilise généralement une structure `switch(state)` à l'intérieur d'une tâche FreeRTOS, ou un tableau de pointeurs de fonctions pour les systèmes plus vastes.

---
<br>



### **Représentation graphique d'une FSM**

#### **Diagramme d'états**

Un diagramme d'états se compose de **nœuds** (cercles) représentant les états et de **flèches** représentant les transitions. Chaque flèche est étiquetée avec la condition qui déclenche la transition (expression logique des entrées). Les sorties Moore sont inscrites à l'intérieur du cercle, les sorties Mealy sont placées sur les flèches à côté de la condition.

**Exemple simple : un détecteur de front montant**

Machine de Mealy (2 états) :



Machine de Moore (3 états) :





#### **Diagramme ASM (Algorithmic State Machine)**

Un diagramme ASM est une représentation plus détaillée, proche d'un organigramme. Il est constitué de **blocs ASM**, chacun correspondant à un état. Un bloc ASM contient :

- Une **boîte d'état** (rectangle) avec le nom de l'état et les sorties Moore.
- Des **boîtes de décision** (losanges) pour tester les entrées.
- Des **boîtes de sortie conditionnelle** (ovales) pour les sorties Mealy.

Les diagrammes ASM sont très utiles pour décrire des séquences complexes et se traduisent facilement en code. Voici un exemple de bloc ASM pour un état `S0` :




---
<br>



### **Fonctionnement temporel d'une FSM synchrone**

Dans une FSM synchrone (la plus courante en logique programmable), les transitions d'état sont cadencées par une horloge. Le comportement temporel est le suivant :

- Au front montant de l'horloge, le registre d'état charge le prochain état.
- Pendant la période d'horloge, la machine évalue les entrées et prépare le prochain état.
- Les sorties Moore sont stables pendant toute la période (elles ne changent qu'après le front d'horloge).
- Les sorties Mealy peuvent changer immédiatement en réponse à une entrée (dans le même cycle).

Les principaux paramètres temporels sont :

- **Tcq** : délai de sortie du registre d'état.
- **Tnext** : délai de la logique combinatoire de prochain état.
- **Tsetup, Thold** : temps de préparation et de maintien du registre.

La période d'horloge minimale est : `Tmin = Tcq + Tnext(max) + Tsetup`.

Ces notions sont cruciales pour la conception de systèmes temps réel où les délais de réponse doivent être maîtrisés.

---
<br>




### **Comparaison entre machine de Moore et machine de Mealy**

| Critère | Machine de Moore | Machine de Mealy |
|---------|------------------|------------------|
| **Nombre d'états** | Plus d'états (les sorties sont liées aux états) | Moins d'états (les sorties peuvent varier dans un même état) |
| **Rapidité de réponse** | Réponse au cycle suivant (sortie après front d'horloge) | Réponse immédiate (dans le même cycle) |
| **Largeur des impulsions** | Largeur égale à une période d'horloge | Largeur variable, peut être très courte |
| **Immunité au bruit** | Bonne (sorties stables) | Sensible aux glitchs sur les entrées |

#### **Exemple : Détecteur de front montant**

On souhaite générer une impulsion courte à chaque fois que l'entrée `strobe` passe de 0 à 1.

**Version Mealy (2 états)**

État ZERO : si strobe = 1 → sortie = 1, aller à UN
État UN : si strobe = 0 → aller à ZERO

La sortie est active seulement pendant la transition, dans le même cycle.

**Version Moore (3 états)**

État ZERO : si strobe = 1 → aller à EDGE
État EDGE : sortie = 1 ; si strobe = 1 → aller à UN, sinon ZERO
État UN : si strobe = 0 → aller à ZERO

La sortie est active pendant tout l'état EDGE (un cycle d'horloge).

Le choix dépend de l'application : une sortie Mealy est plus rapide, une sortie Moore plus robuste.

---
<br>



### **Implémentation d'une FSM en C**

Plusieurs méthodes existent pour implémenter une FSM en C. Nous allons voir les deux plus courantes : le `switch-case` et la **table de transitions**.

1.**Implémentation par switch-case**

C'est la méthode la plus simple et la plus lisible pour des machines de taille modeste.

```c
typedef enum {
    STATE_IDLE,
    STATE_WAIT,
    STATE_RUN
} State_t;

State_t currentState = STATE_IDLE;

void FSM_Process(Event_t event) {
    switch (currentState) {
        case STATE_IDLE:
            if (event == EV_START) {
                currentState = STATE_WAIT;
                // Action de transition
            }
            break;

        case STATE_WAIT:
            if (event == EV_TIMEOUT) {
                currentState = STATE_RUN;
            } else if (event == EV_STOP) {
                currentState = STATE_IDLE;
            }
            break;

        case STATE_RUN:
            if (event == EV_STOP) {
                currentState = STATE_IDLE;
            }
            break;
    }
}
```

2.**Implémentation par table de transitions**

Pour des machines plus complexes ou pour faciliter la maintenance, on peut utiliser une table qui associe à chaque couple (état, événement) l'état suivant et une action.

```c
typedef struct {
    State_t  currentState;
    Event_t  event;
    State_t  nextState;
    void (*action)(void);  // pointeur de fonction pour l'action
} Transition_t;

Transition_t transitionTable[] = {
    {STATE_IDLE, EV_START, STATE_WAIT, actionStart},
    {STATE_WAIT, EV_TIMEOUT, STATE_RUN, actionRun},
    {STATE_WAIT, EV_STOP, STATE_IDLE, actionStop},
    {STATE_RUN, EV_STOP, STATE_IDLE, actionStop},
    // ...
};

void FSM_Process(Event_t event) {
    for (int i = 0; i < sizeof(transitionTable)/sizeof(Transition_t); i++) {
        if (transitionTable[i].currentState == currentState &&
            transitionTable[i].event == event) {
            currentState = transitionTable[i].nextState;
            if (transitionTable[i].action) {
                transitionTable[i].action();
            }
            break;
        }
    }
}
```

Cette approche rend la machine plus facile à modifier et à étendre.


---
<br>


### **Intégration avec FreeRTOS**

Dans un système temps réel, la FSM peut être implémentée comme une tâche dédiée. Les événements peuvent provenir :

- D'interruptions matérielles (via sémaphores/queues).
- De timers logiciels (pour des timeouts).
- D'autres tâches (via queues).

**Exemple de squelette de tâche FSM**

```c
void vTaskFSM(void *pvParameters) {
    Event_t event;

    for (;;) {
        // Attendre un événement (bloquant)
        if (xQueueReceive(xEventQueue, &event, portMAX_DELAY) == pdPASS) {
            // Traiter l'événement dans la FSM
            FSM_Process(event);
        }
    }
}
```

Les événements sont envoyés dans la queue par d'autres parties du système (ISR, tâches, timers logiciels). Cela garantit que la FSM est réactive et ne bloque pas.


---
<br>


### **Mise en Pratique : Le Mariage des Concepts**

Pour notre étude, l'idéal est de construire une application qui fusionne tout :

- **Les Interruptions (Entrées)** : Elles captent les événements extérieurs (bouton pressé, capteur activé) et envoient un signal à la FSM.
- **Le Timer (Le Temps)** : Il gère les délais de transition (ex: "rester dans l'état ALARM pendant 10 secondes").
- **Le GPIO (Sorties)** : La FSM pilote les actionneurs (LEDs, moteurs) en fonction de l'état courant.
- **FreeRTOS (L'Ordonnanceur)** : La FSM tourne dans sa propre tâche, isolée du reste du système, garantissant que la logique de contrôle est toujours prioritaire.

---
<br>




### **Système de Feux Tricolores avec Bouton Piéton et Détection de Véhicule**{#projet-fsm-timer-freertos}

 Nous allons concevoir une autre application classique de l'embarqué : un **système de feux tricolores** pour un carrefour routier, intégrant un bouton piéton et un capteur de détection de véhicule. Ce projet mettra en œuvre une machine à états finis (FSM) gérée par FreeRTOS, avec des temporisations précises (timers matériels ou logiciels), des entrées (bouton, capteur) et des sorties (LEDs). Il illustre la gestion d'événements asynchrones et la coordination de plusieurs tâches.

**Cahier des Charges**

**Fonctionnalités**

- **Feux pour véhicules** : trois LEDs (rouge, orange, vert) pour la circulation des voitures.
- **Feu piéton** : deux LEDs (rouge piéton, vert piéton) pour traverser.
- **Bouton piéton** : permet de demander la traversée. La demande n'est prise en compte que si le feu véhicule n'est pas déjà en cours de changement.
**Capteur de véhicule** (simulé par un bouton ou un interrupteur) : détecte la présence d'un véhicule pour prolonger le vert si nécessaire (optionnel, pour éviter les changements inutiles).

**Cycle normal** :
1. Vert véhicules pendant 10 secondes.
2. Orange véhicules pendant 3 secondes.
3. Rouge véhicules et vert piétons pendant 8 secondes.
4. Retour au vert véhicules.

- **Demande piéton** : si le bouton est pressé pendant le vert véhicules, on passe à l'orange après un délai minimum (ex: 5 secondes de vert) pour ne pas interrompre trop tôt. Si le bouton est pressé pendant le rouge véhicules, le vert piéton reste actif le temps normal.

**Contraintes Techniques**

- Utilisation de GPIO pour les LEDs et les entrées (bouton, capteur).
- Gestion des entrées par interruptions (pour réactivité) ou par polling (mais on privilégie les interruptions).
- Temporisations gérées par des timers matériels ou des timers logiciels FreeRTOS.
- Implémentation d'une FSM avec FreeRTOS (tâche dédiée, file d'événements).
- Priorités : la tâche FSM doit avoir une priorité moyenne, les ISR doivent être courtes.

  
**Modélisation de la Machine à États**

**États**

|État	|Description|
|-------|-----------|
|`VEHICLE_GREEN`	|Vert véhicules, rouge piétons.|
|`VEHICLE_YELLOW`	|Orange véhicules, rouge piétons.|
|`VEHICLE_RED`	|Rouge véhicules, vert piétons.|
|`PED_REQUEST`	|État temporaire pour gérer une demande piéton pendant le vert véhicules (on attend la fin du délai minimum avant de passer à l'orange).|

**Événements**

|Événement	|Source|
|-----------|------|
|`EV_TIMER_GREEN`	|Fin de la temporisation du vert véhicules.|
|`EV_TIMER_YELLOW`	|Fin de la temporisation de l'orange.|
|`EV_TIMER_RED`	|Fin de la temporisation du rouge véhicules.|
|`EV_TIMER_MIN_GREEN`	|Fin du délai minimum de vert avant de prendre en compte une demande piéton.|
|`EV_PED_BUTTON`	|Appui sur le bouton piéton.|
|`EV_VEHICLE_DETECT`	|Détection d'un véhicule (optionnel).|

**Diagramme de Transition**

[VEHICLE_GREEN] --(EV_TIMER_GREEN)--> [VEHICLE_YELLOW]
[VEHICLE_GREEN] --(EV_PED_BUTTON)--> [PED_REQUEST] (si pas déjà en demande)
[PED_REQUEST] --(EV_TIMER_MIN_GREEN)--> [VEHICLE_YELLOW]
[VEHICLE_YELLOW] --(EV_TIMER_YELLOW)--> [VEHICLE_RED]
[VEHICLE_RED] --(EV_TIMER_RED)--> [VEHICLE_GREEN]

On pourrait ajouter une transition de `VEHICLE_RED` vers `VEHICLE_GREEN` avec une condition de détection de véhicule pour passer au vert plus tôt, mais ici on reste simple.

  
**Implémentation avec FreeRTOS**

Le code complet est présenté ci‑dessous. Il suit la structure suivante :

- Initialisation matérielle (GPIO, interruptions).
- Création de la file d'événements et des timers logiciels.
- Tâche FSM qui attend les événements et exécute la logique à états.

```c
#include "FreeRTOS.h"
#include "task.h"
#include "queue.h"
#include "timers.h"
#include "stm32f4xx.h"

// Définition des événements
typedef enum {
    EV_TIMER_GREEN,
    EV_TIMER_YELLOW,
    EV_TIMER_RED,
    EV_TIMER_MIN_GREEN,
    EV_PED_BUTTON,
    EV_VEHICLE_DETECT
} Event_t;

// Queue pour les événements
QueueHandle_t xEventQueue;

// Handles des timers logiciels
TimerHandle_t xTimerGreen, xTimerYellow, xTimerRed, xTimerMinGreen;

// Callbacks des timers logiciels
void vTimerGreenCallback(TimerHandle_t xTimer) {
    Event_t ev = EV_TIMER_GREEN;
    xQueueSend(xEventQueue, &ev, 0);
}
void vTimerYellowCallback(TimerHandle_t xTimer) {
    Event_t ev = EV_TIMER_YELLOW;
    xQueueSend(xEventQueue, &ev, 0);
}
void vTimerRedCallback(TimerHandle_t xTimer) {
    Event_t ev = EV_TIMER_RED;
    xQueueSend(xEventQueue, &ev, 0);
}
void vTimerMinGreenCallback(TimerHandle_t xTimer) {
    Event_t ev = EV_TIMER_MIN_GREEN;
    xQueueSend(xEventQueue, &ev, 0);
}

// ISR pour le bouton piéton (EXTI)
void EXTI0_IRQHandler(void) {
    BaseType_t xWoken = pdFALSE;
    if (EXTI->PR & (1 << 0)) {
        EXTI->PR = (1 << 0);
        Event_t ev = EV_PED_BUTTON;
        xQueueSendFromISR(xEventQueue, &ev, &xWoken);
        portYIELD_FROM_ISR(xWoken);
    }
}

// ISR pour le capteur de véhicule (EXTI)
void EXTI1_IRQHandler(void) {
    BaseType_t xWoken = pdFALSE;
    if (EXTI->PR & (1 << 1)) {
        EXTI->PR = (1 << 1);
        Event_t ev = EV_VEHICLE_DETECT;
        xQueueSendFromISR(xEventQueue, &ev, &xWoken);
        portYIELD_FROM_ISR(xWoken);
    }
}

// Tâche FSM
void vTaskFSM(void *pvParameters) {
    enum { VEHICLE_GREEN, VEHICLE_YELLOW, VEHICLE_RED, PED_REQUEST } state = VEHICLE_GREEN;
    Event_t ev;

    // Démarrer le timer du vert initial
    xTimerStart(xTimerGreen, 0);

    for (;;) {
        xQueueReceive(xEventQueue, &ev, portMAX_DELAY);

        switch (state) {
            case VEHICLE_GREEN:
                if (ev == EV_TIMER_GREEN) {
                    state = VEHICLE_YELLOW;
                    GPIOA->ODR &= ~(1<<5);   // éteint vert
                    GPIOA->ODR |=  (1<<6);   // allume orange
                    xTimerStart(xTimerYellow, 0);
                }
                else if (ev == EV_PED_BUTTON) {
                    state = PED_REQUEST;
                    xTimerStart(xTimerMinGreen, 0); // délai minimum 5s
                }
                break;

            case PED_REQUEST:
                if (ev == EV_TIMER_MIN_GREEN) {
                    state = VEHICLE_YELLOW;
                    GPIOA->ODR &= ~(1<<5);
                    GPIOA->ODR |=  (1<<6);
                    xTimerStart(xTimerYellow, 0);
                }
                break;

            case VEHICLE_YELLOW:
                if (ev == EV_TIMER_YELLOW) {
                    state = VEHICLE_RED;
                    GPIOA->ODR &= ~(1<<6);
                    GPIOA->ODR |=  (1<<7);   // rouge véhicule
                    GPIOC->ODR |=  (1<<8);   // vert piéton
                    xTimerStart(xTimerRed, 0);
                }
                break;

            case VEHICLE_RED:
                if (ev == EV_TIMER_RED) {
                    state = VEHICLE_GREEN;
                    GPIOA->ODR &= ~((1<<5)|(1<<6)|(1<<7));
                    GPIOC->ODR &= ~((1<<8)|(1<<9));
                    GPIOA->ODR |=  (1<<5);   // vert véhicule
                    xTimerStart(xTimerGreen, 0);
                }
                break;
        }
    }
}

// Initialisation matérielle (GPIO, interruptions)
void Hardware_Init(void) {
    RCC->AHB1ENR |= RCC_AHB1ENR_GPIOAEN | RCC_AHB1ENR_GPIOCEN;

    // LEDs véhicules : PA5 vert, PA6 orange, PA7 rouge
    GPIOA->MODER |= (1 << (5*2)) | (1 << (6*2)) | (1 << (7*2));
    // LEDs piétons : PC8 vert, PC9 rouge
    GPIOC->MODER |= (1 << (8*2)) | (1 << (9*2));
    // Initialement éteint
    GPIOA->ODR &= ~((1<<5)|(1<<6)|(1<<7));
    GPIOC->ODR &= ~((1<<8)|(1<<9));

    // Bouton piéton sur PA0, capteur véhicule sur PA1 (entrées avec pull-up)
    GPIOA->MODER &= ~(3U << (0*2)) & ~(3U << (1*2));
    GPIOA->PUPDR |= (1 << (0*2)) | (1 << (1*2));

    // Activation de SYSCFG pour EXTI
    RCC->APB2ENR |= RCC_APB2ENR_SYSCFGEN;
    SYSCFG->EXTICR[0] &= ~(SYSCFG_EXTICR1_EXTI0 | SYSCFG_EXTICR1_EXTI1);
    // EXTI0 sur PA0, EXTI1 sur PA1
    EXTI->IMR |= (1 << 0) | (1 << 1);
    EXTI->FTSR |= (1 << 0) | (1 << 1);   // front descendant (appui)
    NVIC_SetPriority(EXTI0_IRQn, 5);
    NVIC_SetPriority(EXTI1_IRQn, 5);
    NVIC_EnableIRQ(EXTI0_IRQn);
    NVIC_EnableIRQ(EXTI1_IRQn);
}

int main(void) {
    Hardware_Init();

    xEventQueue = xQueueCreate(10, sizeof(Event_t));

    xTimerGreen    = xTimerCreate("Green",    pdMS_TO_TICKS(10000), pdFALSE, NULL, vTimerGreenCallback);
    xTimerYellow   = xTimerCreate("Yellow",   pdMS_TO_TICKS(3000),  pdFALSE, NULL, vTimerYellowCallback);
    xTimerRed      = xTimerCreate("Red",      pdMS_TO_TICKS(8000),  pdFALSE, NULL, vTimerRedCallback);
    xTimerMinGreen = xTimerCreate("MinGreen", pdMS_TO_TICKS(5000),  pdFALSE, NULL, vTimerMinGreenCallback);

    if (xEventQueue != NULL && xTimerGreen != NULL && xTimerYellow != NULL && xTimerRed != NULL && xTimerMinGreen != NULL) {
        xTaskCreate(vTaskFSM, "FSM", 256, NULL, 2, NULL);
        vTaskStartScheduler();
    }

    while(1);
}
```

**Explication**

- **File d'événements** : `xEventQueue` reçoit les événements des ISR et des callbacks de timers.
- **Timers logiciels** : utilisés pour les temporisations. Ils sont en mode "one-shot" (`pdFALSE`) car ils sont redémarrés à chaque cycle.
- **ISR** : très courtes, elles envoient juste l'événement dans la file.
- **Tâche FSM** : boucle infinie qui attend un événement, puis selon l'état courant, effectue les actions et change d'état.

---
<br>

### Liens connexes

- [GPIO et Interruptions](/stm32f4/gpio/)
- [Timer et Interruption](/stm32f4/timer/)