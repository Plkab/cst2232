# Contrôle Numérique avec PID  

*Ir Paul S. Kabidu, M.Eng. <spaulkabidu@gmail.com>*
{: style="text-align: center;" }

---

[Accueil](../../#Accueil)
  
<br>
<br>


### **Introduction**

Le régulateur **PID** (*Proportionnel-Intégral-Dérivé*) est l'algorithme de contrôle le plus répandu dans l'industrie. Il permet d’asservir une grandeur physique (température, vitesse, position, etc.) à une consigne en agissant sur un actionneur. Sa simplicité de mise en œuvre et ses bonnes performances en font un outil incontournable pour les systèmes embarqués temps réel.

Dans ce chapitre, nous allons :

- comprendre le principe du PID et ses paramètres ;
- discrétiser l’équation pour une implémentation sur microcontrôleur ;
- coder un PID en C, avec anti‑windup et passage de l’échelle ;
- l’intégrer dans une tâche FreeRTOS pour une régulation périodique ;
- réaliser un projet pratique (régulation de température ou de vitesse).



---
<br>


### **Principe du régulateur PID**

Le correcteur PID calcule une commande \(u(t)\) à partir de l’erreur :

\[
e(t) = y_{cons}(t) - y(t)
\]

où \(y(t)\) est la **mesure** et \(y_{cons}(t)\) la **consigne**.  
L’équation continue du PID est :

\[
u(t) =
K_p e(t)
+
K_i \int_{0}^{t} e(\tau) d\tau
+
K_d \frac{de(t)}{dt}
\]

**Terme proportionnel (P)** : réagit à l’erreur courante.  
Un gain \(K_p\) élevé accélère la réponse mais peut provoquer des oscillations.

**Terme intégral (I)** : élimine l’erreur statique en sommant les erreurs passées.  
Attention au phénomène de **windup** (saturation de l’intégrale).

**Terme dérivé (D)** : anticipe les variations futures et améliore la stabilité.  
Ce terme est cependant **sensible au bruit**.


**Discrétisation**

Pour une implémentation sur microcontrôleur, on échantillonne le système avec une période \(T_e\)  
(par exemple **10 ms**).

Une forme discrète courante est la **forme parallèle** :

\[
u_k =
K_p e_k
+
K_i T_e \sum_{j=0}^{k} e_j
+
\frac{K_d}{T_e}(e_k - e_{k-1})
\]

Cependant, cette forme explicite peut provoquer des **à-coups** si la consigne change brutalement.

On préfère souvent la **forme incrémentale (velocity form)**, qui calcule la variation de la commande :

\[
\Delta u_k =
K_p (e_k - e_{k-1})
+
K_i T_e e_k
+
\frac{K_d}{T_e}(e_k - 2e_{k-1} + e_{k-2})
\]

La commande est alors mise à jour par :

\[
u_k = u_{k-1} + \Delta u_k
\]

Cette forme facilite :

- l’**anti-windup**
- la **gestion des saturations**
- l’implémentation efficace sur **microcontrôleur**.



---
<br>



### **Implémentation en C**

Nous allons implémenter un **PID incrémental** avec **saturation de la commande** et **anti-windup** (on gèle l’intégration lorsque la commande sature).  
La structure de données contient les **paramètres du régulateur** et les **états internes**.

```c
#include <stdint.h>

// Structure PID (forme incrémentale avec anti-windup simple)
typedef struct {
    float Kp, Ki, Kd;      // Gains (à régler)
    float Te;              // Période d'échantillonnage (secondes)

    float umin, umax;      // Limites de la commande

    float integral;        // Terme intégral (pour anti-windup)

    float e_prev;          // e(k-1)
    float e_prev2;         // e(k-2)

    float u_prev;          // commande précédente
} PIDController;
```

**Initialisation du PID**

```c
void PID_Init(PIDController *pid,
              float Kp, float Ki, float Kd,
              float Te,
              float umin, float umax)
{

    pid->Kp = Kp;
    pid->Ki = Ki;
    pid->Kd = Kd;

    pid->Te = Te;

    pid->umin = umin;
    pid->umax = umax;

    pid->integral = 0.0f;

    pid->e_prev  = 0.0f;
    pid->e_prev2 = 0.0f;

    pid->u_prev = 0.0f;
}
```

**Mise à jour du PID**

```c
float PID_Update(PIDController *pid,
                 float setpoint,
                 float measurement)
{
    float error = setpoint - measurement;

    // Calcul de la variation (forme incrémentale)
    float delta_u =
        pid->Kp * (error - pid->e_prev)
        // proportionnel
      + pid->Ki * pid->Te * error
      // intégral
      + pid->Kd / pid->Te * (error - 2 * pid->e_prev 
      + pid->e_prev2);  // dérivé

    // Nouvelle commande
    float u = pid->u_prev + delta_u;

    // Saturation + anti-windup simple
    if (u > pid->umax) {
        u = pid->umax;
        // On n'accumule pas l'intégrale
    }
    else if (u < pid->umin) {
        u = pid->umin;
    }
    else {
        // Mise à jour de l’intégrale seulement si pas saturé
        // Dans la forme incrémentale l’intégrale est implicite
    }

    // Mise à jour des états
    pid->e_prev2 = pid->e_prev;
    pid->e_prev  = error;
    pid->u_prev  = u;

    return u;
}
```

**Remarques**

- La **période d’échantillonnage `Te` doit être constante**.  
  Elle est généralement assurée par une **tâche FreeRTOS périodique**.

- L’**anti-windup** est géré ici en **bloquant l’accumulation lorsque la commande sature**.

- Dans la **forme incrémentale**, l’intégrale n’est pas stockée explicitement,  
  ce qui simplifie l’implémentation.

- Pour un **anti-windup plus robuste**, une méthode courante consiste à :
  
  - recalculer l’intégrale à partir de la **commande saturée**
  - ou utiliser une **rétroaction de saturation (back-calculation)**.

---
<br>


### **Intégration matérielle**

Pour réaliser un **asservissement**, il faut généralement deux éléments principaux :

- **Un capteur** fournissant la mesure du système :
  - ADC pour un **potentiomètre**
  - **encodeur** pour mesurer une vitesse ou une position
  - **thermistance** pour mesurer une température

- **Un actionneur** commandé par la sortie du PID :
  - **PWM** pour piloter un moteur
  - commande d’un **chauffage**
  - commande d’un **servomoteur** ou d’une **valve**

Le **PID s’exécute dans une tâche périodique** avec une fréquence fixe  
(par exemple **100 Hz**, soit une période d’échantillonnage de **10 ms**).

Les **valeurs de consigne** peuvent provenir d’une **interface homme-machine**, par exemple :

- un **potentiomètre** (lecture ADC)
- une **communication UART**
- un **bouton** ou une interface série
- une **application externe** (PC, smartphone, etc.)


---
<br>


### **Projet : Régulation de vitesse d’un moteur DC** {#projet-pid-moteur}

Nous allons réaliser un **asservissement de vitesse d’un moteur DC** à l’aide d’un **encodeur incrémental**.

**Matériel**

- **Moteur DC avec encodeur** (type JGA25-370)
- **Driver moteur** (L298N ou module à pont en H)
- **Carte STM32F401**
- **Alimentation adaptée**

**Principe**

- L’**encodeur** fournit des **impulsions**.
- On mesure la **vitesse** en calculant la **fréquence des impulsions**  
  (via un **timer en mode capture** ou une **interruption externe**).

- La **consigne de vitesse** est donnée par :
  - un **potentiomètre** (lecture ADC)
  - ou une **commande série (UART)**.

- Le **PID** calcule la **commande PWM** à appliquer au moteur.

- La **tâche de contrôle** s’exécute à une **fréquence fixe**  
  (par exemple **50 Hz**, soit une période de **20 ms**).


**Code partiel**

```c
// Structure PID
PIDController pid;

// Variables globales
volatile float current_speed = 0.0f;   // vitesse mesurée (rad/s ou tours/s)
float setpoint_speed = 0.0f;
```

**Tâche de contrôle**

```c
void vTaskControl(void *pvParameters)
{
    TickType_t xLastWakeTime = xTaskGetTickCount();
    const TickType_t xPeriod = pdMS_TO_TICKS(20); // 50 Hz

    for (;;)
    {
        vTaskDelayUntil(&xLastWakeTime, xPeriod);

        // Lire la consigne (par exemple depuis un potentiomètre)
        setpoint_speed = ADC_GetSpeedSetpoint();

        // Mise à jour du PID
        float control = PID_Update(&pid, setpoint_speed, current_speed);

        // Appliquer la commande au moteur (PWM)
        Motor_SetSpeed(control);
    }
}
```

**Interruption de l’encodeur**

```c
void TIMx_IRQHandler(void)
{
    static uint32_t lastCapture = 0;
    uint32_t capture = TIMx->CCR1;
    uint32_t period = capture - lastCapture;
    lastCapture = capture;

    // Calcul de la vitesse (à adapter selon la résolution de l'encodeur)
    // Par exemple : vitesse = (f_timer / period) * facteur
    current_speed = (float)(84000000 / 84) / period; // si timer à 1 MHz
    // Noter que ce calcul peut être effectué dans la tâche pour éviter des calculs flottants en ISR.
}
```

**Fonctions matérielles à implémenter**

```c
// Lecture de la consigne via ADC (0-4095) -> conversion en plage de vitesse
float ADC_GetSpeedSetpoint(void)
{
    uint16_t raw = ADC_Read();   // fonction de lecture ADC
    return (float)raw * 1000.0f / 4095.0f;  // exemple: consigne 0-1000 tr/min
}

// Application de la commande PWM (0-100%)
void Motor_SetSpeed(float percent)
{
    if (percent < 0) percent = 0;
    if (percent > 100) percent = 100;
    uint32_t duty = (uint32_t)(percent * (TIM2->ARR + 1) / 100.0f);
    TIM2->CCR1 = duty;
}
```

**Réglage des gains**

Le réglage des gains **\(K_p\)**, **\(K_i\)** et **\(K_d\)** peut se faire :

- **empiriquement** (méthode de **Ziegler-Nichols**)
- par **modélisation et simulation**

Pour un **moteur DC**, une méthode simple consiste à :

1. Commencer avec \(Ki = 0\) et \(Kd = 0\)
2. Augmenter progressivement **\(K_p\)** jusqu’à observer une **oscillation stable**.
3. Ajuster ensuite :

- **\(K_i\)** pour éliminer l’erreur statique
- **\(K_d\)** pour améliorer l’amortissement et la stabilité.


**Applications**

Ce type de régulation est utilisé dans :

- **robots mobiles**
- **contrôle de vitesse de moteurs DC**
- **systèmes mécatroniques**
- **automatisation industrielle**
- **robots auto-équilibrés**

---
<br>



### Liens connexes

- [GPIO et Interruptions](../gpio/index.md)
- [Timer et Interruption](../timer/index.md)
- [Communication Série USART](../usart/index.md)
- [Acquisition Analogique via ADC](../adc/index.md)
- [Génération des signaux PWM](../pwm/index.md)
- [Communication Série USART](../usart/index.md)
- [Machine d’État Fini (FSM)](../../technique-algos/fsm/index.md)
- [Optimisation de Transfert des Données avec DMA](../dma/index.md)
- [Introduction pratique à freeRTOS](../../rtos/#introduction-a-freertos)