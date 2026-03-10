# Le Multitache avec FreeRTOS

*Ir Paul S. Kabidu, M.Eng. <spaulkabidu@gmail.com>*
{: style="text-align: center;" }

---

[Acceuil](../#Acceuil)
  
<br>
<br>



### **Introduction Pratique à FreeRTOS** {#introduction-a-freertos}

FreeRTOS est un RTOS open source largement utilisé dans les systèmes embarqués, supportant plus de 40 microcontrôleurs. Il a été initialement développé par Richard Barry autour de 2003, puis maintenu par sa société Real Time Engineers Ltd. en étroite collaboration avec les principaux fabricants de semi-conducteurs pendant plus d'une décennie. En 2017, la gestion du projet FreeRTOS a été confiée à Amazon Web Services (AWS). 

Il se présente sous la forme d'une API qui nous permet de mettre en œuvre des applications temps réel sur microcontrôleur. Nous allons apprendre à utiliser ses fonctions pré-écrites pour structurer nos projets de manière efficace.

FreeRTOS utilise un ordonnancement **préemptif à priorités fixes** par défaut. Cependant, pour les tâches de **même priorité**, plusieurs stratégies sont possibles :

- **Round-Robin avec time-slice** : les tâches de même priorité s'exécutent à tour de rôle pendant une durée fixe (le *time slice*, généralement 1 tick).
- **Coopératif** : les tâches de même priorité ne sont pas préemptées entre elles ; elles doivent explicitement céder la main (`taskYIELD()`) ou se bloquer volontairement.

Cette flexibilité permet d'adapter le comportement du système aux besoins de l'application.

On peut avoir sur le site web officiel le manuel de référence ecrit par [Richard Barry](https://www.freertos.org/media/2018/161204_Mastering_the_FreeRTOS_Real_Time_Kernel-A_Hands-On_Tutorial_Guide.pdf) et l'API est disponible : [freertos.](https://www.freertos.org/Documentation/02-Kernel/01-About-the-FreeRTOS-kernel/03-Download-freeRTOS/01-DownloadFreeRTOS)


**Organisation des fichiers**

FreeRTOS est fourni sous forme d'un ensemble de fichiers `.c` et `.h` qui sont compilés avec votre code applicatif. La distribution comprend également un [dossier demo](https://www.freertos.org/Documentation/02-Kernel/01-About-the-FreeRTOS-kernel/03-Download-freeRTOS/01-DownloadFreeRTOS) contenant des exemples de programmes qui aident les débutants à développer leurs propres applications.

```text
FreeRTOS/
├── Source/
│   ├── include/          # Fichiers d’en‑tête publics
│   ├── portable/         # Code spécifique aux compilateurs/architectures
│   │   ├── MemMang/      # Gestionnaires de mémoire (heap_1.c à heap_5.c)
│   │   └── RVDS/ARM_CM4F/  # Portage pour Cortex‑M4F (utilisé avec Keil)
│   ├── croutine.c
│   ├── event_groups.c
│   ├── list.c
│   ├── queue.c
│   ├── stream_buffer.c
│   ├── tasks.c
│   └── timers.c
└── Demo/                 # Exemples de projets (optionnel)
```

Le fichier de configuration FreeRTOSConfig.h est placé dans le dossier de votre projet. Il définit les paramètres du noyau (fréquence CPU, tick rate, inclusion des fonctions, etc.). Pour une description détaillée des macros de configuration, reportez‑vous à la [documentation](../../ressources/configRtosKiel.md).

---
<br>



### **Types de données FreeRTOS**

Deux types de données sont fréquemment utilisés :

- `TickType_t` : utilisé pour stocker le nombre de ticks. Sur un processeur 32 bits, c'est généralement un `uint32_t`. La macro `pdMS_TO_TICKS(ms)` convertit des millisecondes en ticks.
- `BaseType_t` : type dépendant de l'architecture (32 bits sur STM32). Utilisé pour les valeurs de retour simples (`pdTRUE/pdFALSE`, `pdPASS/pdFAIL`).

Conventions de nommage :
- `v` : retourne un void (ex: `vTaskDelay`).
- `x` : retourne un `BaseType_t` ou un type non standard (ex: `xTaskCreate`).
- `pv` : retourne un pointeur vers void (ex: `pvTimerGetTimerID`).



#### **Gestion des Tâches**

La tâche est l'élément fondamental dans un RTOS. Chaque fonction que vous souhaitez exécuter de manière autonome devient une tâche, avec sa propre priorité définie par le développeur.

Dans un programme classique (sans OS), tout le code se trouve dans la fonction main(). Dans FreeRTOS, le rôle de main() est simplement de créer les tâches nécessaires, puis de lancer l'ordonnanceur qui prend le contrôle.

Une tâche est typiquement une fonction qui ne doit jamais se terminer, elle s'exécute en boucle infinie et possède sa propre pile mémoire. Sa structure type est une boucle infinie :

```c
void maTache(void * pvParameters) {
    while(1) { // Une tâche est une boucle infinie
        // Ton code ici (ex: lire un capteur)
        Action();
        vTaskDelay(pdMS_TO_TICKS(100)); // On laisse respirer le CPU 100ms
    }
}
```

**Création d'une tâche dans le main avec `xTaskCreate`**

La fonction _`xTaskCreate()`_ est la porte d'entrée de FreeRTOS. Elle crée une nouvelle tâche et l'ajoute à l'ordonnanceur.

```c
BaseType_t xTaskCreate( 
    TaskFunction_t pvTaskCode,  // Pointeur vers la fonction de la tâche
    const char * const pcName,  // Nom descriptif (pour debug)
    uint16_t usStackDepth,      // Taille de la pile (en mots, pas en octets !)
    void *pvParameters,         // Paramètres passés à la tâche
    UBaseType_t uxPriority,     // Priorité (0 est la plus basse)
    TaskHandle_t *pxCreatedTask // Handle pour manipuler la tâche plus tard
);
```

```c
xTaskCreate(
    maTache,           // Nom de la fonction: Pointeur vers la fonction de la tâche
    "Nom_Tache",       // Nom de la tâche (pour le debug)
    2048,              // Taille de la pile (en mots, souvent 32 bits)
    NULL,              // Paramètres à passer à la tâche (optionnel)
    2,                 // PRIORITÉ (plus le chiffre est élevé, plus la tâche est prioritaire)
    NULL               // Handle pour manipuler la tâche plus tard
);
```

**Le lancement (`vTaskStartScheduler`)**

Après avoir créé les tâches, on appelle `vTaskStartScheduler()`. Cette fonction cède le contrôle du processeur à FreeRTOS. À partir de cet instant, le code situé après cette ligne dans main() ne sera plus jamais exécuté. Le système bascule alors de tâche en tâche selon les priorités définies.

```c
// Prototype de la tâche
void maTache(void * pvParameters);

void main(void) {
    // Création : Fonction, Nom, Taille pile, Paramètre, Priorité, Handle
    xTaskCreate(maTache, "Tache1", 1024, NULL, 5, NULL);
    
    // Lance l'ordonnanceur (le système prend le contrôle)
    vTaskStartScheduler();

    // Le code ici ne sera jamais atteint
    while(1); // Sécurité
}
```
---
<br>



### **Gestion du Temps (`vTaskDelay`) et (`vTaskDelayUntil`)**

Contrairement à une simple boucle d'attente active (comme `delay()`) qui bloque tout le processeur, `vTaskDelay` place la tâche dans l'état "Blocked" pendant un nombre de ticks spécifié. Pendant ce temps, le CPU est libéré et peut exécuter d'autres tâches prêtes, optimisant ainsi l'utilisation des ressources.

- `vTaskDelay(xTicksToDelay)` → délai relatif.

```c
void vTaskMoteur(void * pvParameters) {
    for(;;) { // Boucle infinie obligatoire
        ControleVitesse();
        // Attend 20ms de manière déterministe
        vTaskDelay(pdMS_TO_TICKS(20)); // Bloque la tâche pendant 20ms
    }
}
```
Pour cette fonction nous avons une limitation, si le code de traitement prend 10ms, et que l'on utilise _`vTaskDelay(90ms)`_, la période réelle sera de 100ms + temps de traitement, provoquant une dérive temporelle.


Exemple de Clignotement d'une LED (une seule tâche) toutes les secondes.

```c
#include "FreeRTOS.h"
#include "task.h"
#include "stm32f4xx.h"

// Fonction de la tâche
void vTaskLed(void *pvParameters) {
    (void)pvParameters;

    // Configuration de PC13 en sortie
    RCC->AHB1ENR |= RCC_AHB1ENR_GPIOCEN;
    GPIOC->MODER |= (1 << (13*2));

    for (;;) {
        GPIOC->ODR ^= (1 << 13);          // Toggle LED
        vTaskDelay(pdMS_TO_TICKS(1000));
    }
}

int main(void) {
    // Création de la tâche
    xTaskCreate(vTaskLed, "LED", 128, NULL, 1, NULL);

    // Lancement de l'ordonnanceur
    vTaskStartScheduler();

    // Ne doit jamais arriver
    while (1);
}
```

Exemple : Deux LEDs avec des fréquences différentes
Deux tâches : l'une clignote toutes les secondes (PC13), l'autre toutes les 200 ms (PA5 si disponible, ou on peut utiliser une LED externe).

```c
#include "FreeRTOS.h"
#include "task.h"
#include "stm32f4xx.h"

void vTaskLed1(void *pvParameters) {
    RCC->AHB1ENR |= RCC_AHB1ENR_GPIOCEN;
    GPIOC->MODER |= (1 << (13*2));
    for (;;) {
        GPIOC->ODR ^= (1 << 13);
        vTaskDelay(pdMS_TO_TICKS(1000));
    }
}

void vTaskLed2(void *pvParameters) {
    RCC->AHB1ENR |= RCC_AHB1ENR_GPIOAEN;
    GPIOA->MODER |= (1 << (5*2));   // PA5 en sortie
    for (;;) {
        GPIOA->ODR ^= (1 << 5);
        vTaskDelay(pdMS_TO_TICKS(200));
    }
}

int main(void) {
    xTaskCreate(vTaskLed1, "LED1", 128, NULL, 1, NULL);
    xTaskCreate(vTaskLed2, "LED2", 128, NULL, 1, NULL);

    vTaskStartScheduler();

    while(1);
}
```

Prenons un autre exemple qui fait du temps réel périodique précis: 

- `vTaskDelayUntil(&xLastWakeTime, xPeriod)` → délai absolu, périodicité fixe.
- `xTaskGetTickCount()` → retourne le nombre de ticks depuis le démarrage du scheduler.

```c
void Task_Stabilisation(void *pvParameters) {
 
     // Variable pour stocker l'instant du prochain réveil
    TickType_t xLastWakeTime = xTaskGetTickCount();
    
    // Période souhaitée : 20 ms (50 Hz)
    const TickType_t xPeriod = pdMS_TO_TICKS(20);

    for (;;) { // Boucle infinie de la tâche
        // --- DEBUT DU TRAITEMENT ---
        // 1. Lire les capteurs (ex: Accéléromètre)
        // 2. Calculer l'algorithme (ex: PID de stabilisation)
        // 3. Appliquer la correction aux moteurs
        
        // --- SYNCHRONISATION ---
        // On attend "jusqu'à" la prochaine échéance fixe
        vTaskDelayUntil(&xLastWakeTime, xPeriod);
    }
}
```

Cette fonction garantit que la tâche _Stabilisation()_ s'exécutera exactement toutes les 20ms, sans dérive, même si le code de traitement varie (tant qu'il reste inférieur à la période)

**Pourquoi utiliser vTaskDelayUntil plutôt que `vTaskDelay` ?**

- **`vTaskDelay`** : spécifie un délai relatif à partir de l'appel. Si le code à l'intérieur de la tâche prend du temps, la prochaine exécution sera décalée (dérive temporelle).

- **`vTaskDelayUntil`** : spécifie un instant absolu de réveil. Il garantit que la tâche s'exécute à une fréquence fixe, sans dérive, quelle que soit la durée du traitement (tant qu'il reste inférieur à la période). Il permet d'éviter la dérive temporelle.

**Remarques importantes**

- Initialisation : `xLastWakeTime` doit être initialisée avec l'heure courante avant la première utilisation.
- Premier appel : `vTaskDelayUntil` attendra que `xLastWakeTime + xPeriod` soit atteint. La première exécution effective aura donc lieu après une période complète.
- Traitement plus long que la période : Si le code à l'intérieur de la boucle dépasse la période, le prochain réveil sera immédiat et vous perdrez le déterminisme. Il faut donc s'assurer que le pire temps d'exécution est inférieur à la période.

---
<br>



### **Synchronisation par Sémaphores (xSemaphore)** {#Semaphores}

Les sémaphores sont indispensables pour protéger l'accès à des ressources partagées (par exemple un bus I2C, un périphérique UART, variable globale) ou pour synchroniser une tâche avec une interruption matérielle. Ces ressources ne peuvent être utilisées que par une seule tâche à la fois. 

**Le Mutex (Le type de sémaphore pour les ressources partagées)**

Imaginons que deux tâches doivent écrire sur le même port série (UART). Si elles écrivent simultanément, les messages seront mélangés et illisibles. Un mutex (MUTual EXclusion) agit comme un jeton, une tâche doit obtenir ce jeton avant d'utiliser la ressource, et le rend ensuite.

Déclaration et création :

```c
SemaphoreHandle_t xMutexUART; // Variable représentant le jeton

void vTaskA(void *pvParameters) {
    for (;;) {
        if (xSemaphoreTake(xMutexUART, portMAX_DELAY) == pdPASS) {
            // Accès exclusif à l'UART
            printf("Tâche A écrit sur UART\n");
            xSemaphoreGive(xMutexUART);
        }
        vTaskDelay(pdMS_TO_TICKS(100));
    }
}

void vTaskB(void *pvParameters) {
    for (;;) {
        if (xSemaphoreTake(xMutexUART, portMAX_DELAY) == pdPASS) {
            printf("Tâche B écrit sur UART\n");
            xSemaphoreGive(xMutexUART);
        }
        vTaskDelay(pdMS_TO_TICKS(200));
    }
}

void main() {
    // Création du mutex
    xMutexUART = xSemaphoreCreateMutex();
    
    if(xMutexUART != NULL) {
        // Création des tâches seulement si le mutex est prêt
        xTaskCreate(vTaskA, "Tache A", 1000, NULL, 1, NULL);
        xTaskCreate(vTaskB, "Tache B", 1000, NULL, 1, NULL);
        vTaskStartScheduler();
    }
}
```

**Utilisation dans les tâches: `xSemaphoreTake` et `xSemaphoreGive`**

- `xSemaphoreTake(xMutex, portMAX_DELAY)` : tente de prendre le jeton. Si le jeton est déjà pris, la tâche se bloque jusqu'à ce qu'il soit libéré (ou jusqu'à expiration du délai).
- `xSemaphoreGive(xMutex)` : libère le jeton pour les autres tâches.

```c
void vTaskA(void * pvParameters) {
    for(;;) {
        // 1. Tenter de prendre le jeton (attendre max 100 ms)
        if(xSemaphoreTake(xMutexUART, pdMS_TO_TICKS(100)) == pdPASS) {
            
            // 2. Jeton obtenu → accès exclusif à l'UART
            printf("Je suis la Tache A et je contrôle l'UART\n");
            
            // 3. Important : rendre le jeton
            xSemaphoreGive(xMutexUART);
        } else {
            // Échec : le jeton n'a pas pu être obtenu dans le délai imparti
            // On peut prendre une action corrective ou signaler une erreur
        }
        vTaskDelay(pdMS_TO_TICKS(500));
    }
}
```

**On a trois types de Sémaphores à connaître :**

- **Le Mutex** (`xSemaphoreCreateMutex`) : Utilisé pour protéger une ressource partagée (Écran, I2C, Moteur). Il intègre un mécanisme d'héritage de priorité qui évite qu'une tâche de priorité moyenne ne bloque indéfiniment une tâche haute priorité.

- **Le Sémaphore Binaire** (`xSemaphoreCreateBinary`) : utilisé pour la synchronisation simple. Par exemple, une interruption matérielle (appui sur un bouton) "donne" le sémaphore, et une tâche qui "attendait" se réveille instantanément.

- **Le Sémaphore à Comptage** (`xSemaphoreCreateCounting`) : utilisé lorsqu'on dispose de plusieurs instances d'une ressource (par exemple un parking avec 5 places libres).

**Exemple de synchronisation avec une ISR :**

```c
#include "FreeRTOS.h"
#include "semphr.h"

// Handle global pour le sémaphore
SemaphoreHandle_t xSemaphoreBouton;

// PROTOTYPES DE DÉMO (BARE METAL)
void LowLevel_Init(void);         // Config GPIO & EXTI via registres
void LowLevel_ClearIT(void);      // Acquitter le flag dans le registre PR
void LowLevel_ToggleLED(void);    // Inverser bit dans le registre ODR

// 1. Routine d'interruption (Vecteur EXTI0)
void EXTI0_IRQHandler(void) {
    BaseType_t xHigherPriorityTaskWoken = pdFALSE;

    // Action Bare Metal : Effacer le flag d'interruption (registre Pending)
    LowLevel_ClearIT();

    // Signal à la tâche : Débloque vTaskBouton
    xSemaphoreGiveFromISR(xSemaphoreBouton, &xHigherPriorityTaskWoken);

    // Demande un changement de contexte si nécessaire
    portYIELD_FROM_ISR(xHigherPriorityTaskWoken);
}

// 2. Tâche de gestion du bouton
void vTaskBouton(void *pvParameters) {
    for (;;) {
        // Attend indéfiniment le signal de l'interruption
        if (xSemaphoreTake(xSemaphoreBouton, portMAX_DELAY) == pdPASS) {
            // Action Bare Metal : Basculer l'état de la LED
            LowLevel_ToggleLED();
        }
    }
}

int main(void) {
    // Initialisation matérielle (Horloges, GPIO, NVIC)
    LowLevel_Init();

    // Création du sémaphore binaire
    xSemaphoreBouton = xSemaphoreCreateBinary();

    if (xSemaphoreBouton != NULL) {
        // Création de la tâche
        xTaskCreate(vTaskBouton, "BTN_TASK", 128, NULL, 2, NULL);
        
        // Lancement du système
        vTaskStartScheduler();
    }

    while(1);
}
```

---
<br>



### **Communication par files de messages : Queues (xQueue)**

C'est la méthode propre pour échanger des données entre tâches de manière propre. Les données sont copiées dans la file (passage par valeur), ce qui évite les problèmes de partage mémoire. Par exemple, une tâche "Capteur" lit une température et une tâche "Affichage" doit la montrer. Plutôt que d'utiliser une variable globale (risquée en environnement temps réel), on utilise une file (queue) – une boîte aux lettres sécurisée.

**Principe des files d'attente**

Une file d'attente est une structure de données de type FIFO *(First In, First Out*) qui permet d'envoyer des messages ou des données d'une tâche à une autre, ou entre une interruption et une tâche. Les données sont **copiées** dans la file (passage par valeur), ce qui évite les problèmes de partage mémoire.

```text
[ Entrée ] → [ 2 | 4 | 6 | 8 ] → [ Sortie ]
```
Les files peuvent contenir des éléments de taille fixe, définie à la création. On peut envoyer des entiers, des structures, ou même des pointeurs vers de gros buffers.

- **Créer la file** : `xQueueCreate(taille, taille_d'un_élément)`;
La fonction `xQueueCreate()` alloue et initialise une file.
```c
QueueHandle_t xQueueCreate(UBaseType_t uxQueueLength, UBaseType_t uxItemSize);
```
    - uxQueueLength : nombre maximal d'éléments que la file peut contenir.
    - uxItemSize : taille en octets de chaque élément.
    - Retour : handle de la file si réussite, `NULL` sinon.

- **Poster un message** : `xQueueSend(file, &donnee, delai)`;
```c
BaseType_t xQueueSend(QueueHandle_t xQueue, const void *pvItemToQueue, TickType_t xTicksToWait);
```
    Place un élément à la fin de la file. Si la file est pleine, la tâche peut attendre (paramètre xTicksToWait).

- **Lire un message** : `xQueueReceive(file, &reception, delai)`;
```c
BaseType_t xQueueReceive(QueueHandle_t xQueue, void *pvBuffer, TickType_t xTicksToWait);
```
    - Lit et retire l'élément en tête de file. Si la file est vide, la tâche attend.

Les deux fonctions retournent `pdPASS` en cas de succès, ou `errQUEUE_EMPTY`/`errQUEUE_FULL` selon le cas.

```c
#include "FreeRTOS.h"
#include "queue.h"

// 1. Handle global de la file
QueueHandle_t xQueueCapteur;

// Tâche Émettrice (Producteur)
void vTacheEmettrice(void *pvParameters) {
    uint32_t valeurADC = 0;
    
    for (;;) {
        valeurADC++; // Simulation d'une acquisition

        // 3. Envoyer la donnée ADC (Copie par valeur dans la file)
        // Paramètres : Handle, Adresse donnée, Temps d'attente max si file pleine
        if (xQueueSend(xQueueCapteur, &valeurADC, pdMS_TO_TICKS(10)) == pdPASS) {
            // Envoi réussi
        }

        vTaskDelay(pdMS_TO_TICKS(50)); // Fréquence d'émission
    }
}

// Tâche Réceptrice (Consommateur)
void vTacheReceptrice(void *pvParameters) {
    uint32_t donneeRecue;
    
    for (;;) {
        // 4. Recevoir la donnée (Bloquant jusqu'à réception ou timeout)
        // Paramètres : Handle, Adresse stockage, Temps d'attente max
        if (xQueueReceive(xQueueCapteur, &donneeRecue, pdMS_TO_TICKS(100)) == pdPASS) {
            // Traitement de la donnée reçue
            printf("Valeur ADC reçue : %lu\n", donneeRecue);
        } else {
            // Timeout : aucune donnée reçue après 100ms
        }
    }
}

int main(void) {
    // Initialisation du matériel (Générique)
    Hardware_Init();

    // 2. Création de la file : (Capacité, Taille d'un élément)
    xQueueCapteur = xQueueCreate(5, sizeof(uint32_t));

    if (xQueueCapteur != NULL) {
        xTaskCreate(vTacheEmettrice, "Emetteur", 128, NULL, 1, NULL);
        xTaskCreate(vTacheReceptrice, "Recepteur", 128, NULL, 1, NULL);

        vTaskStartScheduler();
    }

    for(;;);
}
```

---
<br>




### **Trois règles d'or a connaitre :**
  
- **Priorité** : Dans FreeRTOS, plus le chiffre associé à une tâche est élevé, plus sa priorité est haute (attention, certains OS font l'inverse).
- **Boucle infinie** : Une tâche ne doit jamais se terminer ni sortir de sa fonction sans être explicitement supprimée par _`vTaskDelete()`_.
- **Section Critique** : Pour des opérations ultra-sensibles (par exemple la modification d'une variable partagée entre une tâche et une ISR), on peut utiliser `taskENTER_CRITICAL()` et `taskEXIT_CRITICAL()` pour désactiver temporairement les interruptions et garantir l'exclusivité d'accès.

---
<br>
  


### **Liens connexes**

- [Présentation architecturale du Microcontrôleur STM32F4](../stm32f4/mcu_intro/index.md)
- [Introduction aux Systèmes Temps Réels](../rtos/index.md)
- [Création Projet sous Keil uVision](../ressources/demarrerKiel.md)
- [Configuration FreeRTOS sous Kiel pour STM32F4](../ressources/configRtosKiel.md)