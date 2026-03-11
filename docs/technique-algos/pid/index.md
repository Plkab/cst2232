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

- **Terme proportionnel (P)** : réagit à l’erreur courante.  
Un gain \(K_p\) élevé accélère la réponse mais peut provoquer des oscillations.
- **Terme intégral (I)** : élimine l’erreur statique en sommant les erreurs passées.  
Attention au phénomène de **windup** (saturation de l’intégrale).
- **Terme dérivé (D)** : anticipe les variations futures et améliore la stabilité.  
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





### **Contrôle d’un moteur DC**

**Pont en H (L298N)**

Un moteur DC peut tourner dans les deux sens en inversant la polarity de l’alimentation. Un **pont en H** est un circuit constitué de quatre interrupteurs (transistors ou relais) qui permet de contrôler le sens et la vitesse. Le circuit intégré **L298N** est un double pont en H capable de piloter deux moteurs DC ou un moteur pas‑à‑pas.

**Brochage typique du L298N pour un moteur :**

*   **IN1, IN2** : commandes de sens (logique)
*   **ENA** : enable PWM (permet de moduler la vitesse)
*   **OUT1, OUT2** : vers le moteur
*   **VS** : alimentation moteur (jusqu’à 12 V)
*   **VSS** : alimentation logique (5 V)

**Table de vérité (sens) :**


| IN1 | IN2 | ENA | Moteur |
| :--- | :--- | :--- | :--- |
| 0 | 0 | 1 | Frein (roue bloquée) |
| 0 | 1 | 1 | Tourne dans un sens |
| 1 | 0 | 1 | Tourne dans l’autre sens |
| 1 | 1 | 1 | Frein |
| x | x | 0 | Arrêt (roue libre) |

La broche **ENA** peut recevoir un signal PWM pour moduler la vitesse. Les broches **IN1** et **IN2** sont des sorties logiques (0 ou 1).

**Connexion à la Black Pill**

On utilisera par exemple :
*   **PA5** pour la PWM (TIM2_CH1) connectée à **ENA**
*   **PA6** et **PA7** pour les commandes de sens (**IN1, IN2**)
*   Alimentation moteur séparée (attention à ne pas dépasser les courants supportés par le L298N et à utiliser une alimentation externe).

**Schéma de câblage :**

```text
Black Pill      L298N
   PA5  ----->  ENA
   PA6  ----->  IN1
   PA7  ----->  IN2
   GND  ----->  GND commun (alimentation logique)
```

```c
#include "stm32f4xx.h"

void PWM_Init(void) {
    // même code que précédemment pour PA5 en PWM
}

void GPIO_Init(void) {
    // PA6, PA7 en sortie
    RCC->AHB1ENR |= RCC_AHB1ENR_GPIOAEN;
    GPIOA->MODER |= (1 << (6*2)) | (1 << (7*2));
    GPIOA->OTYPER &= ~((1 << 6) | (1 << 7)); // push-pull
    // initialiser à 0 (moteur arrêté)
    GPIOA->ODR &= ~((1 << 6) | (1 << 7));
}

void Motor_SetSpeed(int8_t speed) {
    // speed compris entre -100 et +100 (signe = sens)
    uint16_t duty;
    if (speed == 0) {
        // arrêt : les deux IN à 0, ENA = 0
        GPIOA->ODR &= ~((1 << 6) | (1 << 7));
        TIM2->CCR1 = 0;
    } else if (speed > 0) {
        // sens 1 : IN1=1, IN2=0
        GPIOA->ODR |= (1 << 6);
        GPIOA->ODR &= ~(1 << 7);
        duty = (uint16_t)((uint32_t)speed * TIM2->ARR / 100);
        TIM2->CCR1 = duty;
    } else { // speed < 0
        // sens inverse : IN1=0, IN2=1
        GPIOA->ODR &= ~(1 << 6);
        GPIOA->ODR |= (1 << 7);
        duty = (uint16_t)((uint32_t)(-speed) * TIM2->ARR / 100);
        TIM2->CCR1 = duty;
    }
}

int main(void) {
    PWM_Init();
    GPIO_Init();

    while (1) {
        // exemple : faire tourner à 50 % dans un sens pendant 2 s, puis à 75 % dans l'autre
        Motor_SetSpeed(50);
        for (int i = 0; i < 2000000; i++); // attente simple
        Motor_SetSpeed(-75);
        for (int i = 0; i < 2000000; i++);
        Motor_SetSpeed(0);
        for (int i = 0; i < 1000000; i++);
    }
}

```

---
<br>



### **Projet intégrateur : contrôle de vitesse par potentiomètre**

Nous allons lire la valeur d’un potentiomètre sur PA0 (ADC), la convertir en rapport cyclique, et commander le moteur en conséquence. La vitesse sera affichée sur UART.

**Matériel**

- Potentiomètre 10 kΩ connecté entre 3,3 V et GND, avec le curseur sur PA0.
- Moteur DC (par exemple 6 V) avec driver L298N.
- Alimentation externe pour le moteur.

```c
#include "stm32f4xx.h"
#include <stdio.h>

void USART2_Init(void);
void USART2_SendChar(char c);
int fputc(int ch, FILE *f);
void ADC_Init(void);
uint16_t ADC_Read(void);
void PWM_Init(void);
void GPIO_Init(void);
void Motor_SetSpeed(int8_t speed);

int main(void) {
    uint16_t adc_val;
    int8_t speed;

    USART2_Init();
    ADC_Init();
    PWM_Init();
    GPIO_Init();

    printf("Controle de moteur DC par potentiometre\r\n");

    while (1) {
        adc_val = ADC_Read();                 // 0..4095
        // Convertir en vitesse -100..+100 avec seuil mort
        if (adc_val < 1840) {                  // zone morte basse
            speed = (int8_t)((adc_val - 2048) / 18); // environ -100 à -1
            if (speed > -5) speed = -5;
        } else if (adc_val > 2256) {            // zone morte haute
            speed = (int8_t)((adc_val - 2048) / 18); // environ 1 à 100
            if (speed < 5) speed = 5;
        } else {
            speed = 0;                         // zone morte centrale
        }

        Motor_SetSpeed(speed);
        printf("ADC = %4u, speed = %4d\r\n", adc_val, speed);
        for (int i = 0; i < 500000; i++); // délai simple
    }
}

void ADC_Init(void) {
    RCC->APB2ENR |= RCC_APB2ENR_ADC1EN;
    RCC->AHB1ENR |= RCC_AHB1ENR_GPIOAEN;
    GPIOA->MODER |= (3U << (0*2));   // PA0 analogique
    ADC1->CR1 = 0;
    ADC1->SMPR2 = (7 << 0);          // temps d'échantillonnage max
    ADC1->SQR3 = 0;                   // canal 0
    ADC1->CR2 |= ADC_CR2_ADON;
}

uint16_t ADC_Read(void) {
    ADC1->CR2 |= ADC_CR2_SWSTART;
    while (!(ADC1->SR & ADC_SR_EOC));
    return ADC1->DR;
}

void PWM_Init(void) {
    RCC->AHB1ENR |= RCC_AHB1ENR_GPIOAEN;
    RCC->APB1ENR |= RCC_APB1ENR_TIM2EN;

    GPIOA->MODER &= ~(3U << (5*2));
    GPIOA->MODER |=  (2U << (5*2));
    GPIOA->AFR[0] &= ~(0xF << (5*4));
    GPIOA->AFR[0] |=  (1 << (5*4));

    TIM2->PSC = 84 - 1;          // 1 MHz
    TIM2->ARR = 1000 - 1;        // 1 kHz
    TIM2->CCMR1 = TIM_CCMR1_OC1M_1 | TIM_CCMR1_OC1M_2 | TIM_CCMR1_OC1PE;
    TIM2->CCER |= TIM_CCER_CC1E;
    TIM2->CR1 |= TIM_CR1_CEN;
}

void GPIO_Init(void) {
    // PA6, PA7 en sortie pour IN1, IN2
    GPIOA->MODER |= (1 << (6*2)) | (1 << (7*2));
    GPIOA->OTYPER &= ~((1 << 6) | (1 << 7));
    GPIOA->ODR &= ~((1 << 6) | (1 << 7));
}

void Motor_SetSpeed(int8_t speed) {
    uint16_t duty;
    if (speed == 0) {
        GPIOA->ODR &= ~((1 << 6) | (1 << 7));
        TIM2->CCR1 = 0;
    } else if (speed > 0) {
        GPIOA->ODR |= (1 << 6);
        GPIOA->ODR &= ~(1 << 7);
        duty = (uint16_t)((uint32_t)speed * TIM2->ARR / 100);
        TIM2->CCR1 = duty;
    } else {
        GPIOA->ODR &= ~(1 << 6);
        GPIOA->ODR |= (1 << 7);
        duty = (uint16_t)((uint32_t)(-speed) * TIM2->ARR / 100);
        TIM2->CCR1 = duty;
    }
}

void USART2_Init(void) {
    RCC->AHB1ENR |= RCC_AHB1ENR_GPIOAEN;
    RCC->APB1ENR |= RCC_APB1ENR_USART2EN;

    GPIOA->MODER |= (2 << (2*2)) | (2 << (3*2));
    GPIOA->AFR[0] |= (7 << (2*4)) | (7 << (3*4));

    USART2->BRR = 84000000 / 115200;
    USART2->CR1 = USART_CR1_TE | USART_CR1_UE;
}

void USART2_SendChar(char c) {
    while (!(USART2->SR & USART_SR_TXE));
    USART2->DR = c;
}

int fputc(int ch, FILE *f) {
    USART2_SendChar(ch);
    return ch;
}
```

Explication :

1. La valeur ADC est lue sur PA0. On définit une zone morte autour de 2048 (milieu de l’échelle) pour éviter des fluctuations à vitesse nulle.
2. La vitesse est convertie en signe et valeur absolue pour la commande du pont en H.
3. La PWM est générée sur PA5 (TIM2_CH1).
4. L’UART2 affiche les valeurs pour surveillance.

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

- [GPIO et Interruptions](../../gpio/index.md)
- [Timer et Interruption](../../timer/index.md)
- [Acquisition Analogique via ADC](../../adc/index.md)
- [Génération des signaux PWM](../../pwm/index.md)
- [Communication Série USART](../../usart/index.md)
- [Machine d’État Fini (FSM)](../../technique-algos/fsm/index.md)
- [Optimisation de Transfert des Données avec DMA](../../dma/index.md)
- [Introduction pratique à freeRTOS](../../rtos/#introduction-a-freertos)