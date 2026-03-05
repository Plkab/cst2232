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

**Les Interruptions Externes (EXTI)**

L'interruption est le moyen le plus efficace pour réagir à un événement asynchrone (appui bouton, capteur). Sur STM32F4, elle nécessite :
- L'activation de l'horloge `SYSCFG`.
- Le multiplexage de la ligne EXTI vers le port souhaité.
- La configuration du front (montant/descendant).
- L'activation dans le `NVIC`.

**Synchronisation ISR vers Tâche (Sémaphore)**

C'est le concept le plus important est que l'interruption ne doit pas traiter la donnée, elle doit simplement "réveiller" une tâche de traitement. On utilise un **[Sémaphore Binaire](../rtos/#Semaphores)**.

A. Le Handler d'Interruption (ISR)
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

B. La Tâche de Traitement
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

5. Règles d'Or des Interruptions sous FreeRTOS









---
<br>

### Lien connexe

- [Timer et Interruption](stm32f4/timer/index.md)