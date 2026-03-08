# Projet intégrateur : Régulation de vitesse d’un moteur DC avec PID

*Ir Paul S. Kabidu, M.Eng. <spaulkabidu@gmail.com>*
{: style="text-align: center;" }

---

[Accueil](../../#Accueil)
  
<br>
<br>



### **Objectif du projet**

Ce projet a pour but de réaliser un **asservissement de vitesse d’un moteur à courant continu** à l’aide d’un **régulateur PID implémenté sur STM32F401 sous FreeRTOS**.

La **vitesse du moteur** est mesurée par un **encodeur incrémental**, la **consigne** est donnée par un **potentiomètre** (lecture ADC), et la **commande** est appliquée via un **signal PWM** au moteur à travers un **driver de puissance**.

Ce projet synthétise plusieurs notions importantes :

- Configuration des **GPIO**, **timers**, **PWM**, **ADC** et **interruptions**
- Utilisation de **FreeRTOS** (tâches périodiques, synchronisation)
- Implémentation d’un **algorithme de contrôle en temps réel**

---
<br>


### **Matériel nécessaire**

- Carte **STM32F401 (Black Pill)**
- **Moteur DC avec encodeur incrémental** (ex : JGA25-370, 6V ou 12V)
- **Driver moteur** (L298N ou module à pont en H comme TB6612)
- **Potentiomètre linéaire 10 kΩ** (pour la consigne)
- **Alimentation adaptée** au moteur (par exemple 12V)
- **Breadboard et câbles de connexion**
- *(Optionnel)* Module **USB-UART** pour le monitoring

**Connexions**

- **Potentiomètre** → sortie sur **PA0 (ADC)**
- **Moteur** → commande PWM sur **PA5 (TIM2_CH1)**
- **Encodeur**
  - sortie A → **PA6 (TIM3_CH1 en capture)**
  - sortie B → **PA7** (optionnelle pour déterminer le sens)

---
<br>



### **Principe de fonctionnement**

Le système fonctionne en **boucle fermée**.

1. La **consigne de vitesse** est lue périodiquement sur le **potentiomètre via l’ADC**.
2. La **vitesse réelle** est mesurée par l’**encodeur incrémental**.
3. Le **PID** calcule l’erreur entre **consigne et mesure**.
4. La **commande PWM** est appliquée au moteur via **TIM2**.
5. L’ensemble est géré par **FreeRTOS** avec une **tâche périodique de contrôle**.

La fréquence de la tâche PID est typiquement :

```
50 Hz  → période = 20 ms
```

La **mesure de vitesse** est mise à jour dans une **interruption de timer**.

---
<br>



### **Code complet**

**Fichier `pid.h` — Interface du PID**

```c
#ifndef PID_H
#define PID_H

#include <stdint.h>

typedef struct {
    float Kp, Ki, Kd;
    float Te;

    float umin, umax;

    float e_prev;
    float e_prev2;

    float u_prev;
} PIDController;

void PID_Init(PIDController *pid,
              float Kp,
              float Ki,
              float Kd,
              float Te,
              float umin,
              float umax);

float PID_Update(PIDController *pid,
                 float setpoint,
                 float measurement);

#endif
```

---

**Fichier `pid.c` — Implémentation**

```c
#include "pid.h"

void PID_Init(PIDController *pid,
              float Kp,
              float Ki,
              float Kd,
              float Te,
              float umin,
              float umax)
{
    pid->Kp = Kp;
    pid->Ki = Ki;
    pid->Kd = Kd;

    pid->Te = Te;

    pid->umin = umin;
    pid->umax = umax;

    pid->e_prev = 0.0f;
    pid->e_prev2 = 0.0f;
    pid->u_prev = 0.0f;
}

float PID_Update(PIDController *pid,
                 float setpoint,
                 float measurement)
{
    float error = setpoint - measurement;

    float delta_u =
        pid->Kp * (error - pid->e_prev)
      + pid->Ki * pid->Te * error
      + pid->Kd / pid->Te * (error - 2*pid->e_prev + pid->e_prev2);

    float u = pid->u_prev + delta_u;

    if (u > pid->umax) u = pid->umax;
    else if (u < pid->umin) u = pid->umin;

    pid->e_prev2 = pid->e_prev;
    pid->e_prev = error;
    pid->u_prev = u;

    return u;
}
```

---
<br>



### **Explications détaillées**

**Mesure de vitesse par encodeur**

Un **encodeur incrémental** produit un **nombre fixe d’impulsions par tour**.

La vitesse peut être calculée en mesurant la **période entre deux impulsions** :

```
vitesse (tours/s) =
f_timer / (période × résolution)
```

où :

- `f_timer` : fréquence du timer de capture
- `période` : temps entre deux impulsions
- `résolution` : nombre d’impulsions par tour

---

**Génération de la consigne**

La consigne est lue via **ADC**.

La valeur brute :

```
0 → 4095
```

est convertie en vitesse :

```
0 → 10 tours/s
```

selon :

```c
speed = raw * 10 / 4095
```

---
<br>



### **Régulateur PID**

Le régulateur utilise la **forme incrémentale**.

Avantages :

- calcul plus stable
- réduction du **windup**
- adapté aux systèmes embarqués

La mise à jour se fait **toutes les 20 ms**.

**Sécurité et saturation**

La commande est limitée :

```
0 %  ≤ PWM ≤ 100 %
```

Cela protège :

- le moteur
- le driver
- le système de contrôle

---
<br>



### **Utilisation de FreeRTOS**

Deux tâches peuvent être utilisées :

| Tâche | Rôle |
|------|------|
| PID Control | Calcul de la commande |
| Monitoring | Affichage UART |

La tâche PID utilise :

```
vTaskDelayUntil()
```

afin de garantir une **période d’échantillonnage constante**.

---
<br>



### **Réglage des gains PID**

Une méthode classique est **Ziegler-Nichols**.

**Étape 1**

```
Ki = 0
Kd = 0
```

**Étape 2**

Augmenter `Kp` jusqu’à obtenir une **oscillation stable**.

Noter :

```
Ku = gain critique
Tu = période d’oscillation
```

**Étape 3 — Formules PID**

```
Kp = 0.6 Ku
Ki = 2 Kp / Tu
Kd = Kp Tu / 8
```

Ensuite, **affiner empiriquement** les paramètres.


**Code complet : **

```c
/*****************************************************************************
 * pid.h - Interface du régulateur PID (forme incrémentale)
 *****************************************************************************/

#ifndef PID_H
#define PID_H

#include <stdint.h>

/**
 * Structure PID contenant les paramètres et les états internes.
 */
typedef struct {
    float Kp, Ki, Kd;      // Gains du régulateur
    float Te;              // Période d'échantillonnage (en secondes)
    float umin, umax;      // Limites de la commande (saturation)

    // États pour la forme incrémentale
    float e_prev;          // erreur précédente e(k-1)
    float e_prev2;         // erreur e(k-2)
    float u_prev;          // commande précédente u(k-1)
} PIDController;

/**
 * Initialise la structure PID.
 * @param pid   Pointeur vers la structure
 * @param Kp    Gain proportionnel
 * @param Ki    Gain intégral
 * @param Kd    Gain dérivé
 * @param Te    Période d'échantillonnage (s)
 * @param umin  Commande minimale
 * @param umax  Commande maximale
 */
void PID_Init(PIDController *pid,
              float Kp,
              float Ki,
              float Kd,
              float Te,
              float umin,
              float umax);

/**
 * Met à jour le PID à chaque période d'échantillonnage.
 * @param pid         Pointeur vers la structure
 * @param setpoint    Consigne (valeur désirée)
 * @param measurement Mesure actuelle (valeur réelle)
 * @return Commande calculée (saturée entre umin et umax)
 */
float PID_Update(PIDController *pid,
                 float setpoint,
                 float measurement);

#endif /* PID_H */
```



```c
/*****************************************************************************
 * pid.c - Implémentation du PID (forme incrémentale)
 *****************************************************************************/

#include "pid.h"

void PID_Init(PIDController *pid,
              float Kp,
              float Ki,
              float Kd,
              float Te,
              float umin,
              float umax)
{
    pid->Kp = Kp;
    pid->Ki = Ki;
    pid->Kd = Kd;
    pid->Te = Te;
    pid->umin = umin;
    pid->umax = umax;
    pid->e_prev  = 0.0f;
    pid->e_prev2 = 0.0f;
    pid->u_prev  = 0.0f;
}

float PID_Update(PIDController *pid,
                 float setpoint,
                 float measurement)
{
    float error = setpoint - measurement;

    // Variation de commande (velocity form)
    float delta_u =
        pid->Kp * (error - pid->e_prev)
      + pid->Ki * pid->Te * error
      + pid->Kd / pid->Te * (error - 2.0f * pid->e_prev + pid->e_prev2);

    float u = pid->u_prev + delta_u;

    // Saturation de la commande
    if (u > pid->umax)
        u = pid->umax;
    else if (u < pid->umin)
        u = pid->umin;

    // Mise à jour des états pour le prochain appel
    pid->e_prev2 = pid->e_prev;
    pid->e_prev  = error;
    pid->u_prev  = u;

    return u;
}
```



```c
/*****************************************************************************
 * main.c - Régulation de vitesse d'un moteur DC avec PID et FreeRTOS
 *          Cible : STM32F401 (Black Pill)
 *****************************************************************************/

#include "FreeRTOS.h"
#include "task.h"
#include "queue.h"
#include "semphr.h"
#include "stm32f4xx.h"
#include "pid.h"

/* ========================= Définitions ========================= */

#define PID_PERIOD_MS       20                 // Période du PID (50 Hz)
#define PID_TE              (PID_PERIOD_MS / 1000.0f)  // en secondes

#define PWM_MIN             0.0f                // Commande minimale (0%)
#define PWM_MAX             100.0f              // Commande maximale (100%)

// Gains du PID (à ajuster expérimentalement)
#define KP                  0.5f
#define KI                  0.2f
#define KD                  0.02f

// Paramètres de l'encodeur
#define ENC_RESOLUTION      20                  // Nombre d'impulsions par tour
#define TIM3_FREQ           1000000U            // Fréquence du timer de capture (1 MHz)

/* ====================== Structures globales ==================== */

PIDController pid;                             // Régulateur PID
volatile float current_speed = 0.0f;           // Vitesse mesurée (tours/s)
float setpoint_speed = 0.0f;                   // Consigne (tours/s)

// Sémaphore pour protéger l'accès à current_speed (optionnel)
SemaphoreHandle_t xSpeedSemaphore;

/* ==================== Prototypes des fonctions ================= */

void Hardware_Init(void);
void PWM_Init(void);
void ENCODER_Init(void);
void ADC_Init(void);
uint16_t ADC_Read(void);
float ADC_GetSpeedSetpoint(void);
void Motor_SetSpeed(float percent);

void vTaskPIDControl(void *pvParameters);
void vTaskMonitor(void *pvParameters);

/* ==================== Implémentation matérielle ================= */

/**
 * Initialise la PWM sur PA5 (TIM2_CH1) à 1 kHz.
 */
void PWM_Init(void)
{
    // Activer les horloges
    RCC->AHB1ENR |= RCC_AHB1ENR_GPIOAEN;
    RCC->APB1ENR |= RCC_APB1ENR_TIM2EN;

    // PA5 en alternate function AF1 (TIM2_CH1)
    GPIOA->MODER &= ~(3U << (5*2));
    GPIOA->MODER |=  (2U << (5*2));
    GPIOA->AFR[0] &= ~(0xF << (5*4));
    GPIOA->AFR[0] |=  (1 << (5*4));

    // Configuration de TIM2 pour générer une PWM à 1 kHz
    TIM2->PSC = 84 - 1;                 // 84 MHz / 84 = 1 MHz
    TIM2->ARR = 1000 - 1;               // Période = 1000 ticks → 1 kHz
    TIM2->CCR1 = 0;                     // Rapport cyclique initial 0%

    TIM2->CCMR1 = TIM_CCMR1_OC1M_1 | TIM_CCMR1_OC1M_2 | TIM_CCMR1_OC1PE; // PWM mode 1
    TIM2->CCER |= TIM_CCER_CC1E;        // Activer la sortie sur CH1
    TIM2->CR1  |= TIM_CR1_CEN;          // Démarrer le timer
}

/**
 * Initialise le timer 3 en mode capture sur PA6 (TIM3_CH1).
 * La fréquence du timer est 1 MHz.
 */
void ENCODER_Init(void)
{
    RCC->AHB1ENR |= RCC_AHB1ENR_GPIOAEN;
    RCC->APB1ENR |= RCC_APB1ENR_TIM3EN;

    // PA6 en alternate function AF2 (TIM3_CH1)
    GPIOA->MODER &= ~(3U << (6*2));
    GPIOA->MODER |=  (2U << (6*2));
    GPIOA->AFR[0] &= ~(0xF << (6*4));
    GPIOA->AFR[0] |=  (2 << (6*4));

    // TIM3 à 1 MHz
    TIM3->PSC = 84 - 1;
    TIM3->ARR = 0xFFFF;                 // Compteur 16 bits

    // Capture sur front montant (entrée TI1)
    TIM3->CCMR1 = TIM_CCMR1_CC1S_0;     // 01 : entrée sur TI1
    TIM3->CCER |= TIM_CCER_CC1E;        // Activer la capture

    // Activer l'interruption sur capture
    TIM3->DIER |= TIM_DIER_CC1IE;

    NVIC_SetPriority(TIM3_IRQn, 5);
    NVIC_EnableIRQ(TIM3_IRQn);

    TIM3->CR1 |= TIM_CR1_CEN;           // Démarrer le timer
}

/**
 * Initialise l'ADC sur PA0 (canal 0).
 */
void ADC_Init(void)
{
    RCC->AHB1ENR |= RCC_AHB1ENR_GPIOAEN;
    RCC->APB2ENR |= RCC_APB2ENR_ADC1EN;

    // PA0 en mode analogique
    GPIOA->MODER |= (3U << (0*2));

    // Configuration de base de l'ADC
    ADC1->CR2 = 0;
    ADC1->SQR3 = 0;                     // Premier canal de la séquence : canal 0
    ADC1->SMPR2 = (7 << 0);             // Temps d'échantillonnage maximal
    ADC1->CR2 |= ADC_CR2_ADON;          // Activer l'ADC
}

/**
 * Lit une valeur de l'ADC (mode polling, bloquant).
 * @return Valeur 12 bits (0-4095)
 */
uint16_t ADC_Read(void)
{
    ADC1->CR2 |= ADC_CR2_SWSTART;       // Démarrer la conversion
    while (!(ADC1->SR & ADC_SR_EOC));   // Attendre la fin
    return (uint16_t)ADC1->DR;
}

/**
 * Lit la consigne sur le potentiomètre et la convertit en tours/s.
 * Plage : 0-10 tours/s (à adapter selon le besoin).
 */
float ADC_GetSpeedSetpoint(void)
{
    uint16_t raw = ADC_Read();
    return (float)raw * 10.0f / 4095.0f;
}

/**
 * Applique la commande au moteur via PWM (0% à 100%).
 * @param percent Pourcentage de la pleine échelle (0..100)
 */
void Motor_SetSpeed(float percent)
{
    if (percent < 0)   percent = 0;
    if (percent > 100) percent = 100;
    uint32_t duty = (uint32_t)(percent * (TIM2->ARR + 1) / 100.0f);
    TIM2->CCR1 = duty;
}

/**
 * Initialisation matérielle globale.
 */
void Hardware_Init(void)
{
    PWM_Init();
    ENCODER_Init();
    ADC_Init();
}

/* ==================== Interruption de l'encodeur ================= */

/**
 * ISR du TIM3 : capture la valeur du compteur à chaque impulsion de l'encodeur.
 * Calcule la vitesse instantanée et la stocke dans current_speed.
 */
void TIM3_IRQHandler(void)
{
    static uint32_t lastCapture = 0;
    uint32_t capture;
    float speed;

    if (TIM3->SR & TIM_SR_CC1IF)
    {
        capture = TIM3->CCR1;
        TIM3->SR &= ~TIM_SR_CC1IF;       // Acquitter l'interruption

        uint32_t period = capture - lastCapture;
        lastCapture = capture;

        // Éviter les mesures aberrantes (période trop grande = arrêt)
        if (period > 0 && period < 10000)
        {
            // vitesse = (f_timer / période) / résolution
            speed = (float)TIM3_FREQ / (float)period / ENC_RESOLUTION;
        }
        else
        {
            speed = 0.0f;
        }

        // Mise à jour de la variable partagée (si sémaphore utilisé, on pourrait le prendre)
        current_speed = speed;

        // (Optionnel) donner un sémaphore pour notifier une tâche
    }
}

/* ==================== Tâches FreeRTOS ================= */

/**
 * Tâche de contrôle PID, exécutée périodiquement toutes les 20 ms.
 */
void vTaskPIDControl(void *pvParameters)
{
    TickType_t xLastWakeTime = xTaskGetTickCount();
    const TickType_t xPeriod = pdMS_TO_TICKS(PID_PERIOD_MS);

    // Initialiser le PID
    PID_Init(&pid, KP, KI, KD, PID_TE, PWM_MIN, PWM_MAX);

    for (;;)
    {
        vTaskDelayUntil(&xLastWakeTime, xPeriod);

        // Lire la consigne
        setpoint_speed = ADC_GetSpeedSetpoint();

        // Lire la vitesse mesurée (si sémaphore, on pourrait prendre)
        float meas = current_speed;

        // Calculer la commande PID
        float command = PID_Update(&pid, setpoint_speed, meas);

        // Appliquer au moteur
        Motor_SetSpeed(command);

        // (Optionnel) envoi UART pour monitoring
        // printf("%.2f,%.2f,%.2f\r\n", setpoint_speed, meas, command);
    }
}

/**
 * Tâche optionnelle de monitoring (affichage UART toutes les 500 ms).
 */
void vTaskMonitor(void *pvParameters)
{
    for (;;)
    {
        vTaskDelay(pdMS_TO_TICKS(500));
        // À implémenter si une UART est configurée
        // Exemple : afficher consigne, mesure, commande
    }
}

/* ============================== Main ============================= */

int main(void)
{
    // Initialisation du matériel
    Hardware_Init();

    // Création du sémaphore (optionnel)
    // xSpeedSemaphore = xSemaphoreCreateMutex();

    // Création des tâches
    xTaskCreate(vTaskPIDControl, "PID", 256, NULL, 3, NULL);
    // xTaskCreate(vTaskMonitor, "Monitor", 128, NULL, 1, NULL);

    // Lancement de l'ordonnanceur FreeRTOS
    vTaskStartScheduler();

    // Ne devrait jamais atteindre cette ligne
    while (1);
}
```

**Notes complémentaires :**

- Les fonctions `printf` ne sont pas incluses ; si vous souhaitez du monitoring, configurez l'UART et utilisez `printf` ou une fonction personnalisée.
- Le sémaphore `xSpeedSemaphore` est déclaré mais non utilisé dans le code ; vous pouvez l'intégrer si vous voulez protéger l'accès à `current_speed` entre l'ISR et la tâche. Par exemple, prenez le sémaphore dans l'ISR (avec `xSemaphoreGiveFromISR`) et attendez-le dans la tâche avant de lire la variable.
- Les valeurs de gains PID sont données à titre d'exemple ; elles doivent être réglées expérimentalement pour votre moteur.
- La détection du sens de rotation n'est pas implémentée ici ; si vous utilisez les deux voies de l'encodeur, vous pouvez déterminer le sens et ajuster le signe de la vitesse.


---
<br>


### **Liens Connexes**


- [GPIO et Interruptions](../../../stm32f4/gpio/index.md)
- [Timer et Interruption](../../stm32f4/timer/index.md)
- [Acquisition Analogique via ADC](../../stm32f4/adc/index.md)
- [Génération des signaux PWM](../../stm32f4/pwm/index.md)
- [Communication Série USART](../../stm32f4/usart/index.md)
- [Machine d’État Fini (FSM)](../../technique-algos/fsm/index.md)
- [Optimisation de Transfert des Données avec DMA](../../stm32f4/dma/index.md)
- [Introduction pratique à freeRTOS](../../rtos/#introduction-a-freertos)

