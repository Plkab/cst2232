# Génération des signaux PWM

*Ir Paul S. Kabidu, M.Eng. <spaulkabidu@gmail.com>*
{: style="text-align: center;" }

---

[Accueil](../../#Accueil)
  
<br>
<br>


### **Introduction**

La modulation de largeur d’impulsion (**PWM** – *Pulse Width Modulation*) est une technique largement utilisée en électronique pour contrôler la puissance délivrée à une charge analogique à l’aide d’un signal numérique, notamment les moteurs à courant continu (DC). En faisant varier le rapport cyclique (*duty cycle*) d’un signal périodique, on peut par exemple :

- régler la luminosité d’une LED ;
- commander la vitesse d’un moteur à courant continu ;
- positionner un servomoteur ;
- générer un signal analogique après filtrage (convertisseur numérique‑analogique rudimentaire).

Le STM32F401 dispose de plusieurs timers capables de générer des signaux PWM sur différentes broches. Dans ce chapitre, nous apprendrons à configurer un timer en mode PWM, à modifier le rapport cyclique en temps réel, et à intégrer cette fonctionnalité dans un projet FreeRTOS.

---
<br>



### **Principe de la PWM**

Un signal **PWM** (Pulse Width Modulation) est caractérisé par sa période $T$ (ou sa fréquence $f = 1/T$) et son rapport cyclique $\alpha = t_{on} / T$. La valeur moyenne du signal est proportionnelle à $\alpha$.

Dans un microcontrôleur, la PWM est générée par un **timer**. Le compteur (**CNT**) s’incrémente à chaque coup d’horloge jusqu’à la valeur de reload (**ARR**). La sortie est commutée lorsque la valeur du compteur atteint une valeur de comparaison stockée dans le registre **CCR**. 

Le mode **PWM1** (le plus courant) fonctionne ainsi :
*   Tant que **CNT < CCR**, la sortie est active (par exemple à 1) ;
*   Quand **CNT ≥ CCR**, la sortie devient inactive (0) ;
*   À **CNT = ARR**, le compteur est remis à zéro et le cycle recommence.

Formules clés :

La fréquence de la PWM est donnée par :
$$f_{PWM} = \frac{f_{timer}}{ARR + 1}$$

Avec la fréquence du timer définie par :
$$f_{timer} = \frac{f_{ck}}{PSC + 1}$$

Où :
*   $f_{ck}$ : Fréquence de l’horloge source du timer.
*   **PSC** : Valeur du prédiviseur (Prescaler).
*   **ARR** : Valeur de l'auto-reload (période).
*   **CCR** : Valeur de comparaison (définit le rapport cyclique).


La **valeur moyenne du signal** est proportionnelle au rapport cyclique.  
Par exemple, pour une LED, la luminosité perçue varie avec la valeur moyenne de la tension appliquée.

---
<br>




### **Génération de la PWM dans un microcontrôleur**

Dans un microcontrôleur, la PWM est généralement générée par un **timer**.

Le **compteur** (`CNT`) s’incrémente à chaque coup d’horloge jusqu’à la valeur de **reload** (`ARR`).  
Une sortie est commutée lorsque la valeur du compteur atteint une valeur de **comparaison** stockée dans un registre `CCR`.

**Mode PWM1 (le plus courant)**

Le fonctionnement est le suivant :

- tant que `CNT < CCR`, la sortie est **active** (par exemple à `1`) ;
- quand `CNT ≥ CCR`, la sortie devient **inactive** (`0`) ;
- lorsque `CNT = ARR`, le compteur est **remis à zéro** et un nouveau cycle commence.

**Fréquence de la PWM**

La fréquence du signal PWM est donnée par :

\[
f_{PWM} = \frac{f_{timer}}{ARR + 1}
\]

avec :

\[
f_{timer} = \frac{f_{ck}}{PSC + 1}
\]

où :

- \(f_{ck}\) : fréquence de l’horloge du timer ;
- `PSC` : **prescaler** ;
- `ARR` : **Auto Reload Register**.

**Résolution du rapport cyclique**

La **résolution du rapport cyclique** (nombre de valeurs possibles) est égale à :

\[
\text{Résolution} = ARR + 1
\]

Plus la valeur de `ARR` est grande, plus la **résolution de la PWM est fine**, ce qui permet un contrôle plus précis (par exemple pour la luminosité d’une LED ou la vitesse d’un moteur).

---
<br>



### **Registres impliqués dans la génération de PWM**

Le STM32F401 possède plusieurs timers : TIM1, TIM2, TIM3, TIM4, TIM5, TIM9, etc. Les timers généralistes (TIM2, TIM3, TIM4, TIM5) peuvent être utilisés en PWM. TIM2 est un timer 32 bits, les autres sont 16 bits. Les registres importants sont 

| Registre | Rôle |
|--------|------|
| `TIMx_CR1` | Contrôle du timer (activation, sens de comptage, alignement) |
| `TIMx_PSC` | Prescaler (divise l’horloge d’entrée) |
| `TIMx_ARR` | Auto-reload (définit la période) |
| `TIMx_CCRx` | Capture/compare (définit le rapport cyclique) |
| `TIMx_CCMRx` | Configure le mode du canal (PWM1, PWM2, etc.) |
| `TIMx_CCER` | Active la sortie et choisit la polarité |
| `TIMx_BDTR` | (pour timers avancés) contrôle de la sortie complémentaire et du break |

---
<br>



### **Configuration simple d’une PWM sur PA5 (TIM2_CH1)**

Pour une PWM simple, on utilise généralement le mode PWM1 avec comptage ascendant (edge‑aligned). La configuration se fait en plusieurs étapes :

- Activer l'horloge du timer (via RCC_APB1ENR ou RCC_APB2ENR).
- Configurer la broche en mode alternate function pour la sortie du timer.
- Régler le prescaler et la période (ARR).
- Configurer le mode PWM dans CCMRx (bits OCxM = 110 pour PWM1, et OCxPE = 1 pour préchargement).
- Activer la sortie dans CCER (bit CCxE).
- Démarrer le timer (bit CEN dans CR1).



L’exemple suivant génère un signal **PWM à 1 kHz** sur la broche **PA5**  
(qui peut être utilisée comme **TIM2_CH1** sur certains boîtiers).

Sur la carte **Black Pill**, PA5 est souvent connectée à la **LED utilisateur**, mais il est conseillé de **vérifier le brochage dans le datasheet**.

Exemple : PWM sur PA5 avec TIM2_CH1

PA5 peut être utilisée comme TIM2_CH1 (AF1). Nous allons générer une PWM à 1 kHz avec un rapport cyclique de 50 %.

```c
#include "stm32f4xx.h"

void PWM_Init(void){
    // 1. Activer les horloges
    RCC->AHB1ENR |= RCC_AHB1ENR_GPIOAEN;   // Horloge du port A
    RCC->APB1ENR |= RCC_APB1ENR_TIM2EN;    // Horloge du timer TIM2

    // 2. Configurer PA5 en Alternate Function AF1 (TIM2_CH1)
    GPIOA->MODER &= ~(3U << (5*2));
    GPIOA->MODER |=  (2U << (5*2));        // 10 = Alternate function

    GPIOA->AFR[0] &= ~(0xF << (5*4));
    GPIOA->AFR[0] |=  (1 << (5*4));        // AF1 pour TIM2

    // 3. Configurer le timer
    // f_timer = 84 MHz / 84 = 1 MHz
    TIM2->PSC = 84 - 1;                    // Prescaler

    // Période PWM : 1000 ticks → 1 kHz
    TIM2->ARR = 1000 - 1;

    // Rapport cyclique 50 %
    TIM2->CCR1 = 500 - 1;

    // 4. Mode PWM1 : CNT < CCR => sortie active
    TIM2->CCMR1 = TIM_CCMR1_OC1M_1 | TIM_CCMR1_OC1M_2; // 110 = PWM Mode 1
    TIM2->CCMR1 |= TIM_CCMR1_OC1PE;                    // Précharge CCR

    TIM2->CCER |= TIM_CCER_CC1E;                       // Activer CH1

    // 5. Activer le timer
    TIM2->CR1 |= TIM_CR1_CEN;
}

int main(void) {
    PWM_Init();

    while (1) {
        // La PWM est générée automatiquement
    }
}
```

Le calcul de la période avec ARR = 999 donne une fréquence de 1 kHz si f_timer = 1 MHz. La résolution du rapport cyclique est de 1000 niveaux.

**Modification du rapport cyclique**

Pour modifier le **rapport cyclique pendant l'exécution**, il suffit d’écrire une nouvelle valeur dans le registre :

```c
TIM2->CCR1 = nouvelle_valeur;
```
La valeur doit être comprise entre 0 et ARR.

Exemple :

```c
TIM2->CCR1 = 250;   // 25 %
TIM2->CCR1 = 750;   // 75 %
```

La valeur doit respecter la condition :

```
0 ≤ CCR1 ≤ ARR
```

**Exemple de calcul**

Si :

- `PSC = 83`
- `ARR = 999`
- horloge du timer `f_ck = 84 MHz`

Alors :

```
f_timer = 84 MHz / 84 = 1 MHz
f_PWM   = 1 MHz / 1000 = 1 kHz
```

La **résolution du rapport cyclique** est :

```
ARR + 1 = 1000 niveaux
```

---
<br>



### **Variation du rapport cyclique avec un potentiomètre**

Nous reprenons l’exemple du **chapitre ADC** pour faire varier la **luminosité d’une LED** connectée sur **PA5**  
(ou une LED externe avec résistance).

La valeur lue sur le **potentiomètre** varie entre :

```
0 → 4095   (résolution ADC 12 bits)
```

Cette valeur est **mise à l’échelle** sur la plage du registre `ARR` du timer :

```
0 → 999
```

La valeur obtenue est ensuite écrite dans le registre `CCR1`, ce qui modifie le **rapport cyclique du signal PWM**.

**Exemple simple (polling)**

```c
uint16_t adcValue = ADC_Read();  // lecture ADC (méthode polling)

uint32_t duty = (adcValue * 1000) / 4096;

TIM2->CCR1 = duty;
```

Ainsi :

- potentiomètre au minimum → LED éteinte  
- potentiomètre au maximum → LED à pleine luminosité  
- valeurs intermédiaires → luminosité proportionnelle

---
<br>




### **Utilisation avec FreeRTOS**

Pour un **contrôle plus structuré et non bloquant**, on peut utiliser **FreeRTOS**.

Le principe consiste à :

1. Lire périodiquement l’ADC dans une tâche dédiée.
2. Envoyer la valeur lue dans une **file (queue)**.
3. Une tâche de contrôle PWM reçoit la valeur et ajuste le **rapport cyclique**.

Cela permet :

- de **séparer l’acquisition** (ADC)
- de **séparer le contrôle** (PWM)
- d’éviter le **blocage des tâches**

**Exemple : tâche de contrôle PWM**

```c
void vTaskPWMControl(void *pvParameters){
    uint16_t adcValue;

    for (;;)
    {
        if (xQueueReceive(xADCQueue, &adcValue, portMAX_DELAY) == pdPASS)
        {
            uint32_t duty = (adcValue * (TIM2->ARR + 1)) / 4096;

            TIM2->CCR1 = duty;
        }
    }
}
```

Dans cet exemple :

- `xADCQueue` contient les valeurs lues par l’ADC
- `xQueueReceive()` bloque la tâche jusqu’à réception d’une nouvelle valeur
- le rapport cyclique est recalculé dynamiquement

**Tâche d’acquisition ADC**

Une autre tâche peut se charger de **lire périodiquement l’ADC** et d’envoyer les valeurs dans la file.

Exemple simplifié :

```c
void vTaskADC(void *pvParameters){
    uint16_t adcValue;

    for (;;)
    {
        adcValue = ADC_Read();

        xQueueSend(xADCQueue, &adcValue, 0);

        vTaskDelay(pdMS_TO_TICKS(100));
    }
}
```

La lecture est ici réalisée toutes les **100 ms**, mais cette période peut être adaptée selon l’application.

---
<br>



### **Avantages de cette architecture**

- **Découplage des fonctions** (acquisition / contrôle)
- **Système non bloquant**
- **Facilement extensible** (par exemple contrôle moteur, variateur LED, etc.)
- **Architecture typique des systèmes embarqués temps réel**

**Application typique**

Cette technique est utilisée dans :

- variateurs de **luminosité LED**
- contrôle de **vitesse moteur DC**
- génération de **signaux analogiques simulés**
- interfaces **homme-machine avec potentiomètre**

---
<br>




### **Intégration avec FreeRTOS**

Pour une architecture temps réel, on peut créer une tâche qui lit les valeurs de l’ADC via une file d’attente. L’ISR (fin de conversion ou DMA) envoie la valeur dans la file, et la tâche les traite (affichage, calcul, etc.).

**Exemple avec déclenchement par interruption**

```c
QueueHandle_t xADCQueue;

void ADC_IRQHandler(void) {
    BaseType_t xWoken = pdFALSE;
    if (ADC1->SR & ADC_SR_EOC) {
        uint16_t value = ADC1->DR;
        xQueueSendFromISR(xADCQueue, &value, &xWoken);
    }
    portYIELD_FROM_ISR(xWoken);
}

void vTaskADCProcessor(void *pvParameters) {
    uint16_t val;
    for (;;) {
        if (xQueueReceive(xADCQueue, &val, portMAX_DELAY) == pdPASS) {
            // Utiliser la valeur (ex: calculer une moyenne, envoyer sur UART, etc.)
        }
    }
}
```

**Exemple avec DMA et double buffer**

On peut utiliser deux buffers et alterner leur remplissage. Une fois qu’un buffer est plein, l’ISR DMA notifie la tâche de traitement.


---
<br>



### **Projet : Commande d’un servomoteur** {#projet-pwm-servo}

Un **servomoteur standard** (par exemple le **SG90**) se commande à l’aide d’un **signal PWM spécifique** :

- une **période de 20 ms** (fréquence de **50 Hz**) ;
- une **impulsion de commande comprise entre 1 ms et 2 ms**.

La **position du bras du servomoteur** est proportionnelle à la **largeur de l’impulsion** :

| Largeur d'impulsion | Position approximative |
|---|---|
| 1 ms | 0° |
| 1.5 ms | 90° |
| 2 ms | 180° |

**Configuration du timer**

Pour obtenir une **résolution de 1 µs**, on configure le timer à :

```
f_timer = 1 MHz
```

Ainsi :

```
1 tick = 1 µs
```

La période de 20 ms correspond donc à :

```
20 ms = 20000 µs
```

On configure alors :

```
ARR = 20000 - 1
```

---

**Configuration PWM pour servomoteur (TIM2_CH1 sur PA5)**

```c
void Servo_Init(void){
    // Même initialisation GPIO et horloge que précédemment

    // Configuration du timer
    TIM2->PSC = 84 - 1;       // Timer à 1 MHz (1 µs par tick)
    TIM2->ARR = 20000 - 1;    // Période 20 ms (50 Hz)

    // Position initiale : 1 ms
    TIM2->CCR1 = 1000;

    // Mode PWM1
    TIM2->CCMR1 = TIM_CCMR1_OC1M_1 | TIM_CCMR1_OC1M_2;
    TIM2->CCMR1 |= TIM_CCMR1_OC1PE;

    // Activer la sortie
    TIM2->CCER |= TIM_CCER_CC1E;

    // Démarrer le timer
    TIM2->CR1 |= TIM_CR1_CEN;
}
```

**Fonction de positionnement du servomoteur**

On peut contrôler la position du servomoteur avec un angle compris entre **0° et 180°**.

La largeur d’impulsion correspondante est :

```
largeur = 1000 + (angle / 180) × 1000
```

ce qui donne une largeur comprise entre :

```
1000 µs → 2000 µs
```

**Implémentation**

```c
void Servo_SetPosition(float angle){
    // Conversion angle -> largeur impulsion

    uint32_t width = 1000 + (uint32_t)(angle * 1000 / 180);

    if (width < 1000)
        width = 1000;

    if (width > 2000)
        width = 2000;

    TIM2->CCR1 = width;
}
```

---
<br>



### **Utilisation dans une application**

On peut appeler cette fonction depuis :

- une **tâche FreeRTOS**
- une **lecture ADC (potentiomètre)**
- une **commande UART**
- un **algorithme de contrôle**

Exemple :

```c
float angle = 90.0;

Servo_SetPosition(angle);
```

**Exemple avec potentiomètre**

Si l’on lit une valeur ADC sur **12 bits** :

```
0 → 4095
```

on peut la convertir en angle :

```c
float angle = (adcValue * 180.0f) / 4095.0f;

Servo_SetPosition(angle);
```

---
<br>




### **Applications typiques**

Cette commande PWM de servomoteur est utilisée dans :

- **robotique**
- **bras manipulateurs**
- **gimbals et stabilisation**
- **systèmes mécatroniques**
- **projets pédagogiques de contrôle embarqué**

---
<br>




### Liens connexe

- [GPIO et Interruptions](../gpio/index.md)
- [Timer et Interruption](../timer/index.md)
- [Communication Série USART](../usart/index.md)
- [Acquisition Analogique via ADC](../adc/index.md)
- [Machine d’État Fini (FSM)](../../technique-algos/fsm/index.md)
- [Optimisation de Transfert des Données avec DMA](../dma/index.md)
- [Introduction pratique à freeRTOS](../../rtos/#introduction-a-freertos)