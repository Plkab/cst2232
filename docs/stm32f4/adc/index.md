# Acquisition Analogique via ADC

*Ir Paul S. Kabidu, M.Eng. <spaulkabidu@gmail.com>*
{: style="text-align: center;" }

---

[Accueil](../../#Accueil)
  
<br>
<br>



### **Introduction**

Le monde réel est analogique, mais les microcontrôleurs sont numériques. Pour acquérir des grandeurs physiques (température, pression, luminosité, etc.), on utilise des **capteurs** qui convertissent ces grandeurs en signaux électriques (tension, courant). Un **convertisseur analogique-numérique (ADC)** transforme ces tensions en valeurs binaires exploitables par le processeur.

Le convertisseur analogique-numérique (ADC) est un périphérique essentiel pour interfacer un microcontrôleur avec le monde analogique. Il permet de mesurer des grandeurs physiques continues (température, pression, luminosité, position d’un potentiomètre, etc.) et de les transformer en valeurs numériques exploitables par le logiciel.

Le STM32F401 intègre un **ADC 12 bits** avec jusqu’à 16 voies externes (PA0‑PA7, PB0‑PB1, PC0‑PC5) et quelques sources internes (température, Vrefint, VBAT). Ses principales caractéristiques sont :

- Résolution configurable (6, 8, 10 ou 12 bits).
- Plusieurs modes de conversion : unique, continue, scan, injected.
- Déclenchement possible par logiciel, timer externe, ou PWM.
- Gestion du temps d’échantillonnage paramétrable.
- Possibilité d’utiliser le **DMA** pour transférer automatiquement les résultats en mémoire.

Dans ce chapitre, nous verrons comment configurer l’ADC en mode polling, avec interruption, et avec DMA. Nous intégrerons ensuite ces mécanismes dans un environnement FreeRTOS pour des acquisitions temps réel non bloquantes.

---
<br>



### **Registres principaux de l’ADC**

|Registre	|Rôle|
|-----------|----|
|`ADC_SR` |Status register (indique la fin de conversion, etc.)|
| `ADC_CR1` |Configuration du mode (résolution, scan, interruption)|
| `ADC_CR2` |Activation, démarrage de conversion, déclenchement DMA|
| `ADC_SMPR1/2` |Temps d’échantillonnage pour chaque canal|
| `ADC_SQR1/2/3` |Séquence des canaux à convertir (ordre et longueur)|
| `ADC_DR` |Registre de données (résultat de la conversion)|
| `ADC_CCR` |Configuration commune aux ADC (mode dual, horloge)|

Tous ces registres sont détaillés dans le Reference Manual (RM0368).

---
<br>



### **Configuration simple (mode polling)**

L’exemple le plus simple consiste à lancer une conversion sur un canal unique et à attendre le résultat. Cette méthode est bloquante mais facile à mettre en œuvre.

Étapes :

- Activer l'horloge de l'ADC (RCC_APB2ENR).
- Configurer la broche d'entrée en mode analogique (GPIOx_MODER = 11).
- Régler la résolution (ADC_CR1).
- Choisir le temps d'échantillonnage (ADC_SMPRx).
- Définir la séquence de conversion (ordre et longueur) dans ADC_SQRx.
- Optionnel : choisir le déclenchement (logiciel, timer) dans ADC_CR2.
- Activer l'ADC (ADON = 1 dans ADC_CR2).
- Lancer une conversion (SWSTART = 1).
- Attendre le flag EOC dans ADC_SR.
- Lire le résultat dans ADC_DR.

**Exemple : Lecture du potentiomètre sur PA0 (canal 0)**

```c
#include "stm32f4xx.h"

void ADC_Init(void) {
    // 1. Activer les horloges GPIOA et ADC1
    RCC->AHB1ENR |= RCC_AHB1ENR_GPIOAEN;
    RCC->APB2ENR |= RCC_APB2ENR_ADC1EN;

    // 2. Configurer PA0 en mode analogique
    GPIOA->MODER |= (3U << (0*2));  // 11 = Analog

    // 3. Configuration de base de l'ADC
    ADC1->CR1 = 0;                             // résolution 12 bits (défaut)
    ADC1->CR2 = 0;                            // Désactiver l'ADC avant config
    ADC1->SQR3 = 0;                            // Premier canal dans la séquence = canal 0
    ADC1->SMPR2 = (7 << 0);                    // Temps d'échantillonnage max (480 cycles)
    ADC1->CR2 |= ADC_CR2_ADON;                  // Activer l'ADC
}

uint16_t ADC_Read(void) {
    // 4. Démarrer la conversion (logiciel)// 4. Démarrer la conversion (logiciel)
    ADC1->CR2 |= ADC_CR2_SWSTART;               // Démarrer conversion

    // 5. Attendre la fin de conversion
    while (!(ADC1->SR & ADC_SR_EOC));           // Attendre fin conversion

    // 6. Lire le résultat
    return (uint16_t)ADC1->DR;                   // Lire résultat (efface EOC)
}
```

Limitation : la fonction `ADC_Read()` bloque le CPU tant que la conversion n’est pas terminée. Dans un système temps réel, on préfère utiliser les interruptions ou le DMA.


**Exemple 2 : conversion continue sur PA0**

```c
#include "stm32f4xx.h"

void ADC_Init(void) {
    // 1. Activer les horloges GPIOA et ADC1
    RCC->AHB1ENR |= RCC_AHB1ENR_GPIOAEN;
    RCC->APB2ENR |= RCC_APB2ENR_ADC1EN;

    // 2. Configurer PA0 en mode analogique
    GPIOA->MODER |= (3U << (0*2));  // 11 = Analog

    // 3. Configuration de base de l'ADC
    ADC1->CR1 = 0;                             // résolution 12 bits (défaut)
    ADC1->CR2 = 0;                            // Désactiver l'ADC avant config
    ADC1->SQR3 = 0;                            // Premier canal dans la séquence = canal 0
    ADC1->SMPR2 = (7 << 0);                    // Temps d'échantillonnage max (480 cycles)
    ADC1->CR2 = ADC_CR2_ADON | ADC_CR2_CONT;    // mode continu                  // Activer l'ADC
}

uint16_t ADC_Read(void) {
    // 4. Démarrer la conversion (logiciel)// 4. Démarrer la conversion (logiciel)
    ADC1->CR2 |= ADC_CR2_SWSTART;               // Démarrer conversion

    // 5. Attendre la fin de conversion
    while (!(ADC1->SR & ADC_SR_EOC));           // Attendre fin conversion

    // 6. Lire le résultat
    return (uint16_t)ADC1->DR;                   // Lire résultat (efface EOC)
}
```


---
<br>



### **Capteurs de température LM35**

**Caractéristiques**

- **LM35** : \(10 \text{ mV}/^\circ\text{C}\) (Celsius)   

Plage typique :

- LM35 : \(-55^\circ C\) à \(+150^\circ C\)  

Ces capteurs fournissent une **sortie analogique linéaire**, déjà **étalonnée en usine**.

**Interfaçage avec la Black Pill**

Le capteur se connecte directement sur une **entrée analogique** du microcontrôleur (par exemple **PA0, PA1, PC0...**).

Aucun conditionnement supplémentaire n'est nécessaire si la tension de sortie reste inférieure à :

\[
V_{ref+}
\]

soit **3,3 V** sur la Black Pill.

Pour le **LM35** :

- à **100°C** → sortie ≈ **1,0 V**  
- à **150°C** → sortie ≈ **1,5 V**

Ces valeurs restent largement **compatibles avec l'ADC du STM32**.

**Schéma de principe**

```text
LM35 (broche Vout) ──┬── PA0 (ADC)
                     └─── 100 nF (optionnel, pour filtrage)
```
Le condensateur 100 nF sert à réduire le bruit haute fréquence.

**Calcul de la température**

```markdown
Pour une conversion **ADC 12 bits** avec :

\[
V_{ref+} = 3.3\,V
\]

La tension d'entrée vaut :

\[
V_{in} = ADC_{value} \times \frac{3.3}{4096}
\]

Comme le **LM35 fournit 10 mV/°C**, la température est :

\[
T(^\circ C) = \frac{V_{in}}{10\,mV}
\]

En remplaçant \(V_{in}\) :

\[
T(^\circ C) =
\frac{ADC_{value} \times 3.3}{4096 \times 0.01}
\]

On obtient une forme simplifiée :

\[
T(^\circ C) =
\frac{ADC_{value} \times 330}{4096}
\]

Exemple de calcul

Si :
\[
ADC_{value} = 0x03FE = 1022
\]

Alors :
\[
T =
\frac{1022 \times 330}{4096}
\]

\[
T \approx 82.4^\circ C
\]
```

**Exemple : lecture LM35 sur PA0 avec affichage UART**

```c
#include "stm32f4xx.h"
#include <stdio.h>

void USART2_Init(uint32_t);
void USART2_SendChar(char c);
int fputc(int ch, FILE *f);

int main(void) {
    uint16_t adc_value;
    float temperature;

    // Initialisation UART
    USART2_Init(115200);

    // Configuration ADC sur PA0
    RCC->APB2ENR |= RCC_APB2ENR_ADC1EN;
    RCC->AHB1ENR |= RCC_AHB1ENR_GPIOAEN;
    GPIOA->MODER |= (3U << (0*2));

    ADC1->CR1 = 0;
    ADC1->SMPR2 = (7 << 0);
    ADC1->SQR3 = 0;
    ADC1->CR2 = ADC_CR2_ADON;

    printf("LM35 Temperature Sensor\r\n");

    while (1) {
        ADC1->CR2 |= ADC_CR2_SWSTART;
        while (!(ADC1->SR & ADC_SR_EOC));
        adc_value = ADC1->DR;

        temperature = (float)adc_value * 330.0f / 4096.0f;
        printf("ADC = %4u, Temp = %.2f °C\r\n", adc_value, temperature);

        for (int i = 0; i < 1000000; i++); // attente simple
    }
}

void USART2_Init(uint32_t baud) {
    RCC->AHB1ENR |= RCC_AHB1ENR_GPIOAEN;
    RCC->APB1ENR |= RCC_APB1ENR_USART2EN;

    GPIOA->MODER |= (2 << (2*2)) | (2 << (3*2));
    GPIOA->AFR[0] |= (7 << (2*4)) | (7 << (3*4));

    USART2->BRR = 84000000 / baud; // si APB1 = 84 MHz
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

---
<br>



### **Utilisation avec interruption**

On configure l’ADC pour générer une interruption en fin de conversion. L’ISR peut alors réveiller une tâche ou stocker la valeur.

**Configuration avec interruption**

```c
void ADC_Init_IT(void) {
    // Même initialisation que précédemment, mais on ajoute :
    ADC1->CR1 |= ADC_CR1_EOCIE;                  // Activer interruption fin de conversion
    NVIC_SetPriority(ADC_IRQn, 5);
    NVIC_EnableIRQ(ADC_IRQn);
}
```

ISR de l’ADC

```c
void ADC_IRQHandler(void) {
    if (ADC1->SR & ADC_SR_EOC) {
        uint16_t value = ADC1->DR;               // Lecture (efface le flag)
        // Stocker la valeur dans un buffer ou envoyer à une tâche
        // (par exemple via xQueueSendFromISR)
    }
}
```

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



### **Projet : Contrôle de LED par potentiomètre** {#projet-adc-pwm}

Réalisons un système simple : un potentiomètre connecté sur PA0 (canal 0) commande la luminosité d’une LED sur PA5 (PWM généré par TIM2). La valeur ADC est lue périodiquement (par exemple toutes les 100 ms) via une tâche, et le rapport cyclique du PWM est ajusté en conséquence.

```c
#include "FreeRTOS.h"
#include "task.h"
#include "queue.h"
#include "stm32f4xx.h"

// Queue pour les valeurs ADC
QueueHandle_t xADCQueue;

// Prototypes
void ADC_Init_IT(void);
void PWM_Init(void);
void vTaskADCReader(void *pvParameters);
void vTaskPWMController(void *pvParameters);

// ISR ADC
void ADC_IRQHandler(void) {
    BaseType_t xWoken = pdFALSE;
    if (ADC1->SR & ADC_SR_EOC) {
        uint16_t value = ADC1->DR;
        xQueueSendFromISR(xADCQueue, &value, &xWoken);
    }
    portYIELD_FROM_ISR(xWoken);
}

// Tâche de lecture (déclenche les conversions périodiquement)
void vTaskADCReader(void *pvParameters) {
    TickType_t xLastWakeTime = xTaskGetTickCount();
    for (;;) {
        vTaskDelayUntil(&xLastWakeTime, pdMS_TO_TICKS(100));
        ADC1->CR2 |= ADC_CR2_SWSTART;           // Démarrer conversion
    }
}

// Tâche de contrôle PWM
void vTaskPWMController(void *pvParameters) {
    uint16_t adcValue;
    for (;;) {
        if (xQueueReceive(xADCQueue, &adcValue, portMAX_DELAY) == pdPASS) {
            // Mapper 0-4095 sur 0-999 pour le CCR (ARR = 999)
            uint32_t duty = (adcValue * 1000) / 4096;
            TIM2->CCR1 = duty;
        }
    }
}

int main(void) {
    ADC_Init_IT();
    PWM_Init();

    xADCQueue = xQueueCreate(5, sizeof(uint16_t));

    if (xADCQueue != NULL) {
        xTaskCreate(vTaskADCReader, "ADCRead", 128, NULL, 2, NULL);
        xTaskCreate(vTaskPWMController, "PWM Ctrl", 128, NULL, 1, NULL);
        vTaskStartScheduler();
    }

    while(1);
}
```

**Explications** :

- La tâche vTaskADCReader se réveille toutes les 100 ms et lance une conversion.
- L’ISR place la valeur dans la queue.
- La tâche vTaskPWMController attend une valeur et ajuste le rapport cyclique.
- La LED sur PA5 (PWM) voit sa luminosité varier avec le potentiomètre.

---
<br>




### Liens connexe

- [GPIO et Interruptions](../gpio/index.md)
- [Timer et Interruption](../timer/index.md)
- [Communication Série USART](../usart/index.md)
- [Machine d’État Fini (FSM)](../../technique-algos/fsm/index.md)
- [Optimisation de Transfert des Données avec DMA](../dma/index.md)
- [Introduction pratique à freeRTOS](../../rtos/#introduction-a-freertos)