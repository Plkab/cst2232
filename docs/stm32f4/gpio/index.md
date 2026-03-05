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
- **BSRR** : Modification atomique (Set/Reset) sans lire le registre au préalable (plus sûr en multitâche).

**A. Configuration d'une Sortie (LED sur PC13)**

Pour faire clignoter une LED, nous devons suivre trois étapes logiques dans les registres :

- Activer l'horloge du port (RCC) : Sans énergie, le périphérique ne répond pas.
- Configurer le mode (MODER) : Déclarer la broche en "Sortie".
- Piloter l'état (BSRR/ODR) : Envoyer 0V ou 3.3V.

```c
// Code Bare Metal pur (Sans RTOS)
void Blink_Simple(void) {
    RCC->AHB1ENR |= RCC_AHB1ENR_GPIOCEN;       // 1. Horloge ON
    GPIOC->MODER |= (1 << (13 * 2));            // 2. PC13 en Sortie

    while(1) {
        GPIOC->BSRR = (1 << 29);                // LED ON (Reset bit 13)
        for(int i=0; i<500000; i++);            // Attente logicielle (Bloque le CPU)
        GPIOC->BSRR = (1 << 13);                // LED OFF (Set bit 13)
        for(int i=0; i<500000; i++);
    }
}
```

Problème ici est que : Pendant le temps de la boucle `for`, le processeur ne peut rien faire d'autre. Si un bouton est pressé, il sera ignoré.

### **Gestion des Entrées/Sorties dans une Tâche**

Contrairement au Bare Metal classique où l'on utilise des boucles delay(), FreeRTOS permet de libérer le CPU pendant l'attente d'un clignotement ou d'un rafraîchissement.

```c
void vTaskBlink(void *pvParameters) {
    // Configuration Bare Metal de PC13
    RCC->AHB1ENR |= RCC_AHB1ENR_GPIOCEN;
    GPIOC->MODER |= (1 << (13 * 2));

    for (;;) {
        GPIOC->ODR ^= (1 << 13);           // Toggle LED
        vTaskDelay(pdMS_TO_TICKS(500));    // Délai non-bloquant de 500ms
    }
}
```

**L'Approche Interruptions Externes (EXTI)**

L'interruption est le moyen le plus efficace pour réagir à un événement asynchrone (appui bouton, capteur). Quand une interruption survient le matériel "stoppe" le programme principal pour exécuter une fonction spécifique : le Handler ou ISR.


Sur STM32F4, elle nécessite :

- L'activation de l'horloge `SYSCFG`.
- Le multiplexage de la ligne EXTI vers le port souhaité.
- La configuration du front (montant/descendant).
- L'activation dans le `NVIC`.




**Synchronisation ISR vers Tâche (Sémaphore)**

C'est le concept le plus important est que l'interruption ne doit pas traiter la donnée, elle doit simplement "réveiller" une tâche de traitement. On utilise un [Sémaphore Binaire](rtos/#Semaphores).

**A. Le Handler d'Interruption (ISR)**

```c
void EXTI0_IRQHandler(void) {
    BaseType_t xWoken = pdFALSE;

    if (EXTI->PR & EXTI_PR_PR0) {    // Vérifie le flag EXTI0
        EXTI->PR = EXTI_PR_PR0;      // Acquitte l'interruption

        // Débloque la tâche associée
        xSemaphoreGiveFromISR(xSemBouton, &xWoken);
        
        // Force le changement de contexte immédiat
        portYIELD_FROM_ISR(xWoken);
    }
}
```

**B. La Tâche de Traitement**

```c
void vTaskBouton(void *pvParameters) {
    for (;;) {
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

### Lien connexe

- [Timer et Interruption](stm32f4/timer/index.md)