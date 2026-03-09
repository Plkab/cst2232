# Filtres Numériques

*Ir Paul S. Kabidu, M.Eng. <spaulkabidu@gmail.com>*
{: style="text-align: center;" }

---

[Accueil](../../#Accueil)

<br>
<br>


### **Introduction aux filtres numériques**

Dans les systèmes embarqués, les signaux issus de capteurs sont souvent bruités. Le bruit peut provenir de l’environnement (perturbations électromagnétiques), du capteur lui-même (bruit thermique) ou de la numérisation (bruit de quantification). Pour extraire l’information utile, on utilise des **filtres numériques**.

Un filtre numérique est un algorithme qui transforme un signal d’entrée (une séquence d’échantillons) en un signal de sortie selon une règle mathématique. Contrairement aux filtres analogiques (circuits RLC), les filtres numériques sont :

- **Programmables** : on peut changer leurs caractéristiques par logiciel.
- **Stables** : pas de dérive due aux composants.
- **Reproductibles** : identiques d’un système à l’autre.
- **Capables de réalisations complexes** (phase linéaire, réponse impulsionnelle finie).

Dans ce chapitre, nous verrons les deux grandes familles de filtres numériques :

- Les filtres à réponse impulsionnelle finie (**FIR** – Finite Impulse Response)
- Les filtres à réponse impulsionnelle infinie (**IIR** – Infinite Impulse Response)

Nous apprendrons à les implémenter en C sur STM32, à les intégrer dans une tâche FreeRTOS pour un traitement temps réel, et nous réaliserons un projet de lissage d’un signal analogique (ADC) avec affichage sur UART ou écran.

---
<br>



### **Rappels sur l’échantillonnage**

Avant d’aborder les filtres, rappelons quelques notions fondamentales.

- **Échantillonnage** : conversion d’un signal continu en une suite de valeurs discrètes à intervalles réguliers \(T_e\) (période d’échantillonnage). La fréquence d’échantillonnage \(f_e = 1/T_e\) doit respecter le théorème de Shannon-Nyquist : \(f_e > 2 f_{max}\) pour éviter le repliement de spectre (aliasing).

- **Quantification** : chaque échantillon est représenté par un nombre binaire sur N bits (ex: 12 bits pour l’ADC du STM32F4). Cela introduit une erreur de quantification.

- **Traitement numérique** : les échantillons sont traités par des algorithmes (filtres, FFT, etc.) pour extraire l’information désirée.

Dans la suite, nous considérerons un signal d’entrée \(x[n]\) et un signal de sortie \(y[n]\), où \(n\) est l’indice d’échantillonnage.

---
<br>



### **Filtres à réponse impulsionnelle finie (FIR)**

Un filtre FIR est caractérisé par une équation aux différences de la forme :

\[
y[n] = \sum_{k=0}^{M} b_k \, x[n-k]
\]

où les \(b_k\) sont les coefficients du filtre et \(M\) est l’ordre du filtre (nombre de coefficients moins 1). La sortie est une combinaison linéaire des \(M+1\) derniers échantillons d’entrée.

**Propriétés importantes :**

- La réponse impulsionnelle est finie (après \(M+1\) échantillons, elle s’annule).
- Toujours stables (pas de pôles).
- Peuvent avoir une phase linéaire (si les coefficients sont symétriques), ce qui est important pour éviter la distorsion de phase dans certains traitements (audio, biomédical).

**Exemple : moyenne glissante (filtre passe-bas simple)**

Un filtre moyenneur sur \(N\) échantillons est un FIR d’ordre \(N-1\) avec tous les coefficients égaux à \(1/N\) :

\[
y[n] = \frac{1}{N} \sum_{k=0}^{N-1} x[n-k]
\]

Implémentation en C :

```c
#define N 16
float buffer[N];
uint8_t index = 0;
float sum = 0;

float moving_average(float new_sample) {
    sum -= buffer[index];        // enlever l'ancien échantillon
    buffer[index] = new_sample;  // stocker le nouveau
    sum += new_sample;            // ajouter au total
    index = (index + 1) % N;      // avancer l'index
    return sum / N;
}
```

---
<br>



### **Implémentation générique d’un FIR**

Pour un filtre FIR d’ordre M avec coefficients quelconques, on peut utiliser un buffer circulaire pour les échantillons et un produit scalaire.

```c
typedef struct {
    float *coeffs;       // tableau des coefficients (taille M+1)
    float *buffer;       // buffer circulaire pour les échantillons
    uint16_t order;      // ordre M
    uint16_t index;      // position courante dans le buffer
} FIRFilter;

void FIR_Init(FIRFilter *fir, float *coeffs, uint16_t order) {
    fir->coeffs = coeffs;
    fir->order = order;
    fir->buffer = (float*)calloc(order+1, sizeof(float)); // à adapter (allocation statique possible)
    fir->index = 0;
}

float FIR_Update(FIRFilter *fir, float input) {
    uint16_t i, idx;
    float output = 0;

    // Stocker le nouvel échantillon
    fir->buffer[fir->index] = input;

    // Calcul du produit scalaire (convoluer)
    for (i = 0; i <= fir->order; i++) {
        idx = (fir->index - i + fir->order + 1) % (fir->order + 1); // accès circulaire
        output += fir->coeffs[i] * fir->buffer[idx];
    }

    // Avancer l'index
    fir->index = (fir->index + 1) % (fir->order + 1);

    return output;
}
```


---
<br>



### Filtres à réponse impulsionnelle infinie (IIR)

Les filtres IIR sont caractérisés par une équation aux différences avec récursion :

y[n] = Σ(k=0→M) b_k x[n−k] − Σ(k=1→N) a_k y[n−k]


La sortie dépend à la fois des **entrées passées** et des **sorties passées**.  
Cela permet d’obtenir une **réponse impulsionnelle infinie** avec **moins de coefficients qu’un filtre FIR** pour des performances similaires.

Cependant, les filtres IIR peuvent devenir **instables** si les **pôles sortent du cercle unité** dans le plan Z.

**Exemple : filtre passe-bas du premier ordre (type RC)**

L’équation analogique :

τ dy/dt + y = x

peut être discrétisée (par la méthode d’Euler ou la transformée bilinéaire) pour donner :

y[n] = α x[n] + (1 − α) y[n−1]

avec :

α = Te / (τ + Te)

(si on utilise l’approximation d’Euler).

C’est un **filtre IIR d’ordre 1**.

**Implémentation en C**

```c
typedef struct {
    float alpha;
    float y_prev;
} LowPassFilter;

void LPF_Init(LowPassFilter *lpf, float tau, float Te) {
    lpf->alpha = Te / (tau + Te);
    lpf->y_prev = 0;
}

float LPF_Update(LowPassFilter *lpf, float input) {
    float output = lpf->alpha * input + (1 - lpf->alpha) * lpf->y_prev;
    lpf->y_prev = output;
    return output;
}
```

---
<br>



### Filtre biquad (section du second ordre)

Les filtres IIR d’ordre supérieur sont souvent implémentés comme une **cascade de cellules du second ordre** (*biquads*) afin d’améliorer la **stabilité numérique** et la **précision des calculs**.

Une cellule biquad est décrite par l’équation aux différences suivante :

y[n] = b0 x[n] + b1 x[n−1] + b2 x[n−2] − a1 y[n−1] − a2 y[n−2]

où :

- `x[n]` est l’entrée du filtre,
- `y[n]` est la sortie du filtre,
- `b0, b1, b2` sont les coefficients de la partie **numérateur**,
- `a1, a2` sont les coefficients de la partie **dénominateur**.

Les filtres d’ordre élevé sont souvent réalisés en **mettant plusieurs biquads en cascade**, ce qui permet :

- une meilleure **stabilité numérique**,
- une **implémentation plus robuste** en calcul flottant ou fixe,
- une **réduction des erreurs d’arrondi**.

Les coefficients peuvent être calculés pour différents types de filtres classiques :

- **Butterworth**
- **Chebyshev**
- **Elliptique**
- **Bessel**

Ces coefficients sont généralement obtenus à l’aide d’outils de calcul comme :

- **Matlab**
- **Python (SciPy / NumPy)**
- générateurs de filtres numériques en ligne
- tables de coefficients pré-calculées.


---
<br>



### Intégration avec FreeRTOS

Dans un système temps réel, le filtrage est souvent effectué dans une **tâche périodique** qui lit les échantillons (par exemple depuis l’ADC) et applique le filtre. Les résultats peuvent être envoyés sur **UART**, affichés, ou utilisés dans une **boucle de contrôle**.

**Structure typique**

Une architecture classique avec **FreeRTOS** est la suivante :

- Une tâche **vTaskADCReader** déclenchée par un timer (ou via une file) lit l’ADC et place les échantillons dans une file.
- Une tâche **vTaskFilter** récupère les échantillons, applique le filtre, et met le résultat à disposition (variable globale ou autre file).
- Une tâche **vTaskDisplay** lit périodiquement le résultat et l’affiche (UART, écran).

**Exemple simple : lissage d’un signal ADC avec filtre moyenneur**

```c
QueueHandle_t xADCQueue;
QueueHandle_t xFilteredQueue;

void vTaskADCReader(void *pvParameters) {
    TickType_t xLastWakeTime = xTaskGetTickCount();
    const TickType_t xPeriod = pdMS_TO_TICKS(10); // 100 Hz

    for (;;) {
        vTaskDelayUntil(&xLastWakeTime, xPeriod);
        uint16_t adc = ADC_Read();  // lecture directe
        xQueueSend(xADCQueue, &adc, 0);
    }
}

void vTaskFilter(void *pvParameters) {
    uint16_t adc;
    float filtered;

    // Filtre moyenneur sur 16 points
    #define FILTER_ORDER 16
    float buffer[FILTER_ORDER] = {0};
    uint8_t index = 0;
    float sum = 0;

    for (;;) {
        if (xQueueReceive(xADCQueue, &adc, portMAX_DELAY) == pdPASS) {
            sum -= buffer[index];
            buffer[index] = (float)adc;
            sum += buffer[index];

            index = (index + 1) % FILTER_ORDER;

            filtered = sum / FILTER_ORDER;

            xQueueSend(xFilteredQueue, &filtered, 0);
        }
    }
}

void vTaskDisplay(void *pvParameters) {
    float filtered;
    char buffer[32];

    for (;;) {
        if (xQueueReceive(xFilteredQueue, &filtered, portMAX_DELAY) == pdPASS) {
            sprintf(buffer, "%.2f\r\n", filtered);
            USART2_SendString(buffer);
        }
    }
}
```

**Principe de fonctionnement**

- Lecture ADC : La tâche `vTaskADCReader` lit la valeur de l’ADC toutes les 10 ms (100 Hz).
- Filtrage : La tâche `vTaskFilter` applique un filtre moyenneur glissant sur 16 échantillons.
- Affichage : La tâche `vTaskDisplay` récupère la valeur filtrée et l’envoie via UART (USART2).

Cette architecture permet de séparer clairement les responsabilités acquisition, traitement, affichage et améliore la modularité et la maintenabilité du système.

---
<br>



### **Projet : Lissage d’un signal ADC avec filtre passe-bas IIR** {#projet-filtre-iir}

**Objectif :** Lire un potentiomètre sur **PA0 (ADC)**, appliquer un **filtre passe-bas du premier ordre (type RC numérique)**, et afficher la **valeur filtrée** sur **UART** (ou sur un écran **OLED**).  
On pourra comparer la **valeur brute** et la **valeur filtrée** pour visualiser l’effet du filtre.

**Matériel**

- Carte **STM32F401 (Black Pill)**
- **Potentiomètre 10 kΩ** sur **PA0**
- *(Optionnel)* **écran OLED I2C**

**Code principal**

```c
#include "FreeRTOS.h"
#include "task.h"
#include "queue.h"
#include "stm32f4xx.h"
#include <stdio.h>

// Fonctions ADC et UART (à implémenter)
void ADC_Init(void);
uint16_t ADC_Read(void);
void USART2_Init(uint32_t baud);
void USART2_SendString(char *str);
int _write(int file, char *ptr, int len);

// Filtre passe-bas premier ordre
typedef struct {
    float alpha;
    float y_prev;
} LPF;

void LPF_Init(LPF *lpf, float tau, float Te) {
    lpf->alpha = Te / (tau + Te);
    lpf->y_prev = 0;
}

float LPF_Update(LPF *lpf, float input) {
    float output = lpf->alpha * input + (1 - lpf->alpha) * lpf->y_prev;
    lpf->y_prev = output;
    return output;
}

// Handles
QueueHandle_t xRawQueue;
QueueHandle_t xFilteredQueue;

// Tâches
void vTaskADCReader(void *pvParameters) {
    TickType_t xLastWakeTime = xTaskGetTickCount();
    const TickType_t xPeriod = pdMS_TO_TICKS(10); // 100 Hz
    uint16_t raw;

    for (;;) {
        vTaskDelayUntil(&xLastWakeTime, xPeriod);
        raw = ADC_Read();
        xQueueSend(xRawQueue, &raw, 0);
    }
}

void vTaskFilter(void *pvParameters) {
    uint16_t raw;
    float filtered;
    LPF lpf;
    LPF_Init(&lpf, 0.1f, 0.01f); // tau = 0.1 s, Te = 0.01 s

    for (;;) {
        if (xQueueReceive(xRawQueue, &raw, portMAX_DELAY) == pdPASS) {
            filtered = LPF_Update(&lpf, (float)raw);
            xQueueSend(xFilteredQueue, &filtered, 0);
        }
    }
}

void vTaskDisplay(void *pvParameters) {
    float filtered;
    char buffer[32];

    for (;;) {
        if (xQueueReceive(xFilteredQueue, &filtered, portMAX_DELAY) == pdPASS) {
            sprintf(buffer, "%.2f\r\n", filtered);
            USART2_SendString(buffer);
        }
    }
}

int main(void) {
    HAL_Init();            // si vous utilisez HAL pour le Systick
    SystemClock_Config();  // à adapter
    ADC_Init();
    USART2_Init(115200);

    xRawQueue = xQueueCreate(5, sizeof(uint16_t));
    xFilteredQueue = xQueueCreate(5, sizeof(float));

    if (xRawQueue != NULL && xFilteredQueue != NULL) {
        xTaskCreate(vTaskADCReader, "ADCReader", 128, NULL, 2, NULL);
        xTaskCreate(vTaskFilter,    "Filter",    128, NULL, 2, NULL);
        xTaskCreate(vTaskDisplay,   "Display",   128, NULL, 1, NULL);
        vTaskStartScheduler();
    }

    while(1);
}
```

**Explication**

- La tâche `vTaskADCReader` lit l’ADC à 100 Hz et place les valeurs brutes dans xRawQueue.
- La tâche `vTaskFilter` récupère les valeurs brutes, applique le filtre passe-bas, et place le résultat dans `xFilteredQueue`.
- La tâche `vTaskDisplay` récupère les valeurs filtrées et les affiche sur UART (par exemple dans le terminal série du PC).

**Réglage du filtre**

On peut modifier le paramètre : tau

- pour ajuster la fréquence de coupure du filtre.
- τ petit → filtre rapide (peu de lissage)
- τ grand → filtrage plus fort (réponse plus lente)

Ce paramètre contrôle donc le compromis entre rapidité et filtrage du bruit.


---
<br>


### **Liens connexes**


- [GPIO et Interruptions](../../stm32f4/gpio/index.md)
- [Timer et Interruption](../../stm32f4/timer/index.md)
- [Acquisition Analogique via ADC](../../stm32f4/adc/index.md)
- [Génération des signaux PWM](../../stm32f4/pwm/index.md)
- [Communication Série USART](../../stm32f4/usart/index.md)
- [Communication Série I2C](../../stm32f4/i2c/index.md)
- [Machine d’État Fini (FSM)](../../technique-algos/fsm/index.md)
- [Optimisation de Transfert des Données avec DMA](../../stm32f4/dma/index.md)
- [Estimation d’État et Fusion Capteurs](../../technique-algos/estimation/index.md)
- [Introduction pratique à freeRTOS](../../rtos/#introduction-a-freertos)


