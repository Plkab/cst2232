# Configuration FreeRTOS pour STM32F4 sous Keil

*Ir Paul S. Kabidu, M.Eng. <spaulkabidu@gmail.com>*
{: style="text-align: center;" }

---

[Accueil](../../#Accueil)
  
<br>
<br>


Voici un guide pas-à-pas pour intégrer manuellement FreeRTOS dans un projet Keil pour le STM32F401CCU6.

### **Téléchargement et organisation des sources**

- Télécharge la dernière version de FreeRTOS depuis le [site officiel](https://www.freertos.org/).
- Crée dans le projet Keil un dossier FreeRTOS/ à la racine.
- Copie les dossiers suivants depuis l'archive téléchargée vers FreeRTOS/ :
    - Source/include (tous les en-têtes)
    - Source/portable (uniquement les sous-dossiers MemMang et RVDS/ARM_CM4F) 
    - Source/*.c (tous les fichiers .c de la racine de Source/)

---
<br>

### **Configuration de l'environnement Keil**

- Ajoute les fichiers au projet :
    - Crée deux nouveaux groupes : FreeRTOS_CORE et FreeRTOS_PORT.
    - Dans FreeRTOS_CORE, ajoute tous les fichiers .c de FreeRTOS/Source/ (sauf ceux dans portable/).
    
    - Dans FreeRTOS_PORT, ajoute :
        - FreeRTOS/Source/portable/MemMang/heap_4.c (le gestionnaire de mémoire recommandé).
        - FreeRTOS/Source/portable/RVDS/ARM_CM4F/port.c (la couche de portage pour votre processeur avec FPU) .

- Ajoute les chemins d'inclusion :
    - Dans les options du projet, allez dans C/C++ > Include Paths
    - Ajoute les chemins suivants  :
        - .\FreeRTOS\Source\include
        - .\FreeRTOS\Source\portable\RVDS\ARM_CM4F
        - Le dossier où on a place FreeRTOSConfig.h (ex: .\User\Config)

---
<br>

### **Le fichier de configuration FreeRTOSConfig.h**

C'est le fichier le plus important. Il définit le comportement du RTOS. On peut partir d'un exemple fourni dans les démos FreeRTOS, par exemple dans FreeRTOS/Demo/CORTEX_M4F_STM32F407ZG-SK/.

Crée ce fichier dans un dossier Config/ du projet avec le contenu adapté à F401. Voici une version épurée et commentée avec les paramètres essentiels :

```c
#ifndef FREERTOS_CONFIG_H
#define FREERTOS_CONFIG_H

/*-----------------------------------------------------------
 * Application spécifique
 *----------------------------------------------------------*/
#define configUSE_PREEMPTION                    1               // 1 = Préemptif, 0 = Coopératif [citation:4][citation:9]
#define configUSE_PORT_OPTIMISED_TASK_SELECTION 1               // 1 = Sélection optimisée (utilise l'instruction CLZ du Cortex-M4) [citation:4]
#define configCPU_CLOCK_HZ                      84000000        // Fréquence du CPU (84 MHz pour le F401) [citation:4]
#define configTICK_RATE_HZ                       1000            // Tick à 1kHz (1ms) pour HAL_IncTick() [citation:4][citation:8]
#define configMAX_PRIORITIES                     32              // Nombre maximum de priorités [citation:4]
#define configMINIMAL_STACK_SIZE                 128             // Taille de pile minimale (en mots) [citation:4]
#define configTOTAL_HEAP_SIZE                    (15 * 1024)     // Taille totale du heap pour malloc (15 Ko pour un F401 avec 64 Ko de RAM) [citation:4]
#define configMAX_TASK_NAME_LEN                   16             // Longueur max du nom des tâches [citation:4]
#define configUSE_16_BIT_TICKS                     0             // 0 = tick sur 32 bits, 1 = sur 16 bits [citation:4]
#define configIDLE_SHOULD_YIELD                     1             // L'idle laisse la main aux tâches de même priorité [citation:4]
#define configUSE_MUTEXES                           1             // Activer les Mutex [citation:4]
#define configUSE_RECURSIVE_MUTEXES                 1             // Activer les Mutex récursifs [citation:4]
#define configUSE_COUNTING_SEMAPHORES               1             // Activer les sémaphores compteurs [citation:4]
#define configUSE_QUEUE_SETS                        1             // Activer les Queue Sets [citation:4]
#define configUSE_TASK_NOTIFICATIONS                 1             // Activer les notifications de tâches [citation:4]
#define configSUPPORT_DYNAMIC_ALLOCATION             1             // 1 = Allocation dynamique activée [citation:4]
#define configSUPPORT_STATIC_ALLOCATION              0             // 0 = Allocation statique désactivée (pour simplifier)
#define configUSE_IDLE_HOOK                          0             // Désactiver les hooks inutilisés [citation:3][citation:4][citation:9]
#define configUSE_TICK_HOOK                          0
#define configCHECK_FOR_STACK_OVERFLOW               0
#define configUSE_MALLOC_FAILED_HOOK                 0
#define configUSE_TRACE_FACILITY                     1             // Nécessaire pour certaines fonctions de stats
#define configUSE_STATS_FORMATTING_FUNCTIONS         1             // Pour vTaskList() et vTaskGetRunTimeStats()
#define configGENERATE_RUN_TIME_STATS                0             // Génération de stats (nécessite un timer)
#define configUSE_CO_ROUTINES                         0             // Pas de coroutines
#define configUSE_TIMERS                             1             // Activer les timers logiciels [citation:4]
#define configTIMER_TASK_PRIORITY          (configMAX_PRIORITIES-1) // Priorité max pour la tâche des timers
#define configTIMER_QUEUE_LENGTH                     10
#define configTIMER_TASK_STACK_DEPTH         (configMINIMAL_STACK_SIZE * 2)

/*-----------------------------------------------------------
 * Inclusions des fonctions API optionnelles
 *----------------------------------------------------------*/
#define INCLUDE_vTaskPrioritySet                1
#define INCLUDE_uxTaskPriorityGet                1
#define INCLUDE_vTaskDelete                     1
#define INCLUDE_vTaskSuspend                     1
#define INCLUDE_xTaskGetSchedulerState           1
#define INCLUDE_vTaskDelayUntil                   1
#define INCLUDE_vTaskDelay                        1
#define INCLUDE_eTaskGetState                     1
#define INCLUDE_xTimerPendFunctionCall            1

/*-----------------------------------------------------------
 * Définitions liées aux interruptions (crucial pour le bare metal)
 *----------------------------------------------------------*/
#ifdef __NVIC_PRIO_BITS
    #define configPRIO_BITS       __NVIC_PRIO_BITS
#else
    #define configPRIO_BITS       4                   // 4 bits de priorité pour le STM32F4 [citation:4]
#endif

#define configLIBRARY_LOWEST_INTERRUPT_PRIORITY         15          // Priorité la plus basse
#define configLIBRARY_MAX_SYSCALL_INTERRUPT_PRIORITY    5           // Priorité max autorisée pour les appels depuis une ISR [citation:4]

#define configKERNEL_INTERRUPT_PRIORITY         ( configLIBRARY_LOWEST_INTERRUPT_PRIORITY << (8 - configPRIO_BITS) )
#define configMAX_SYSCALL_INTERRUPT_PRIORITY    ( configLIBRARY_MAX_SYSCALL_INTERRUPT_PRIORITY << (8 - configPRIO_BITS) )

/*-----------------------------------------------------------
 * Aliases pour les handlers d'interruptions (Keil/ARMCC)
 *----------------------------------------------------------*/
#define xPortPendSVHandler  PendSV_Handler
#define vPortSVCHandler     SVC_Handler
#define xPortSysTickHandler SysTick_Handler

#endif /* FREERTOS_CONFIG_H */
```
---
<br>

### **Modification des fichiers système**

FreeRTOS doit etre intégre au gestion de temps et d'interruptions.

- Dans le startup_stm32f401xx.s : assure-toi que les handlers SVC_Handler, PendSV_Handler et SysTick_Handler sont bien présents dans la table des vecteurs. Ils seront redéfinis par FreeRTOS via les alias de FreeRTOSConfig.h.
- Dans votre fichier principal (ex: main.c) :
    - Inclue "FreeRTOS.h" et "task.h".
    - Écrive les tâches.
    - Lance le scheduler avec _vTaskStartScheduler()_.

```c
#include "FreeRTOS.h"
#include "task.h"

// Prototypes des tâches
void vTask1(void *pvParameters);
void vTask2(void *pvParameters);

int main(void)
{
    // Configuration matérielle basique (horloges, GPIO, etc.)
    // ... (le code bare metal)

    // Création des tâches
    xTaskCreate(vTask1, "Task 1", configMINIMAL_STACK_SIZE, NULL, 1, NULL);
    xTaskCreate(vTask2, "Task 2", configMINIMAL_STACK_SIZE, NULL, 2, NULL);

    // Lancement du scheduler
    vTaskStartScheduler();

    // Ne devrait jamais arriver
    while(1);
}

void vTask1(void *pvParameters)
{
    for(;;) {
        // Code de la tâche 1
        vTaskDelay(pdMS_TO_TICKS(1000)); // Attend 1 seconde
    }
}

void vTask2(void *pvParameters)
{
    for(;;) {
        // Code de la tâche 2
        vTaskDelay(pdMS_TO_TICKS(500));
    }
}
```

---
<br>

## **Gestion du tick (SysTick_Handler)** :

On doit écrire notre propre handler SysTick_Handler qui appelle la fonction de tick de FreeRTOS, et éventuellement notre propre incrémenteur de tick si on en a besoin.

```c
#include "FreeRTOS.h"
#include "task.h"

extern void xPortSysTickHandler(void);

void SysTick_Handler(void)
{
    if (xTaskGetSchedulerState() != taskSCHEDULER_NOT_STARTED) {
        xPortSysTickHandler(); // Donne le tick à FreeRTOS
    }
    // 
}
```

---
<br>

## **Gestion des autres interruptions :**

Si on utilise des périphériques avec interruptions, écrit les handlers normalement. Si une interruption doit réveiller une tâche, utilisez les fonctions FromISR de FreeRTOS (comme _xSemaphoreGiveFromISR()_) en respectant les priorités définies dans FreeRTOSConfig.h .

---
<br>

## **Résolution des problèmes courants**

- **Erreur "FreeRTOSConfig.h not found"** : Vérifie tes chemins d'inclusion.
- **Erreurs de liens "multiple definition"** : Commente ou supprime les handlers SVC_Handler, PendSV_Handler et SysTick_Handler de ton fichier startup_*.s ou de tout autre fichier où ils seraient définis. FreeRTOS fournit les siens via les alias dans FreeRTOSConfig.h .
- **Le système ne démarre pas, ou une seule tâche s'exécute :**
    - Vérifiez que SysTick_Handler est correctement implémenté et appelle xPortSysTickHandler().
    - Assures-toi que la fonction vApplicationIdleHook() n'est pas requise (si configUSE_IDLE_HOOK est à 0).
    - Vérifie que tu n'avais pas d'interruption de plus haute priorité qui bloque le tick .
- **Problèmes de mémoire** : Ajuste la taille du configTOTAL_HEAP_SIZE. Pour un F401 avec 64 Ko de RAM, commence avec 15-20 Ko et ajuste selon tes besoins.