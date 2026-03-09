# Analyse fréquentielle avec FFT

*Ir Paul S. Kabidu, M.Eng. <spaulkabidu@gmail.com>*
{: style="text-align: center;" }

---

[Accueil](../../#Accueil)

<br>
<br>



### **Introduction**

L’analyse fréquentielle consiste à étudier le contenu spectral d’un signal, c’est-à-dire à déterminer quelles fréquences le composent et avec quelle amplitude. C’est un outil fondamental en traitement du signal, utilisé dans de nombreux domaines :

- analyse vibratoire pour la maintenance prédictive ;
- traitement audio (égaliseurs, reconnaissance vocale) ;
- communications (analyse de spectre, filtrage) ;
- instrumentation scientifique.

La **Transformée de Fourier Rapide (FFT)** est un algorithme efficace pour calculer la transformée de Fourier discrète (DFT) d’un signal échantillonné. Dans ce chapitre, nous implémenterons une FFT en **bare metal C** (sans bibliothèque externe), nous l’intégrerons dans une tâche FreeRTOS, et nous réaliserons un projet d’analyse spectrale en temps réel d’un signal audio (via ADC) avec affichage sur UART ou écran.

---
<br>



### **Rappels sur la transformée de Fourier discrète (DFT)**

Pour un signal discret \(x[n]\) de longueur \(N\), la DFT est définie par :

\[
X[k] = \sum_{n=0}^{N-1} x[n] \, e^{-j \frac{2\pi}{N} k n}, \quad k = 0, 1, \dots, N-1
\]

Le calcul direct de la DFT nécessite \(O(N^2)\) opérations, ce qui est trop coûteux pour des signaux longs ou du temps réel. La FFT réduit cette complexité à \(O(N \log_2 N)\) en exploitant la symétrie et la périodicité des exponentielles complexes.

---
<br>



### **Principe de la FFT (radix-2)**

L’algorithme le plus connu est celui de **Cooley-Tukey** pour des tailles \(N\) puissance de deux (radix-2). Il décompose récursivement la DFT en deux DFT de taille \(N/2\) :

\[
X[k] = X_{\text{pair}}[k] + W_N^k \, X_{\text{impair}}[k]
\]
\[
X[k + N/2] = X_{\text{pair}}[k] - W_N^k \, X_{\text{impair}}[k]
\]

où \(W_N = e^{-j 2\pi/N}\) est le **twiddle factor**, et \(X_{\text{pair}}\) et \(X_{\text{impair}}\) sont les DFT des échantillons pairs et impairs.

Cette décomposition mène à une structure en **papillon** (butterfly) qui est l’unité de base de la FFT.

---
<br>



### **Implémentation en C (virgule flottante)**

Nous allons implémenter une FFT en C pour des nombres complexes (partie réelle et imaginaire). Nous utiliserons des tableaux de `float` pour représenter les parties réelles et imaginaires séparément.

**1. Inversion des bits (bit-reversal)**

Avant le calcul, il faut réordonner les échantillons d’entrée dans l’ordre binaire inversé. Par exemple, pour \(N=8\), l’indice 3 (binaire 011) devient 6 (binaire 110). On peut générer cette permutation par une fonction simple.

```c
// Réordonnancement par inversion de bits (in-place)
void bit_reverse(float *real, float *imag, int n) {
    int i, j, k;
    float tr, ti;
    for (i = 1, j = 0; i < n; i++) {
        int bit = n >> 1;
        for (; j & bit; bit >>= 1)
            j ^= bit;
        j ^= bit;
        if (i < j) {
            tr = real[i]; ti = imag[i];
            real[i] = real[j]; imag[i] = imag[j];
            real[j] = tr; imag[j] = ti;
        }
    }
}
```

**2. Calcul des twiddle factors**

Les **twiddle factors** sont les coefficients complexes utilisés dans l’algorithme **FFT (Fast Fourier Transform)**.

Ils sont définis par :

W_N^k = cos(2πk/N) − j sin(2πk/N)

où :

- `N` est la taille de la FFT,
- `k` est l’indice du coefficient,
- `j` est l’unité imaginaire (`j² = -1`).

Ces coefficients représentent les **racines N-ièmes de l’unité** dans le plan complexe.

Dans une implémentation embarquée (par exemple sur **STM32**), les twiddle factors sont généralement **pré-calculés** afin d’éviter de recalculer les fonctions trigonométriques pendant l’exécution.

**Exemple : pré-calcul en C**

```c
#include <math.h>

#define N 64

float W_real[N/2];
float W_imag[N/2];

void ComputeTwiddleFactors(void) {
    for (int k = 0; k < N/2; k++) {
        W_real[k] = cosf(2.0f * M_PI * k / N);
        W_imag[k] = -sinf(2.0f * M_PI * k / N);
    }
}
```

Dans cet exemple :

- `W_real[k]` contient la partie réelle `cos(2πk/N)`
- `W_imag[k]` contient la partie imaginaire `−sin(2πk/N)`

Ces valeurs sont ensuite utilisées dans les opérations papillon (butterfly) de la FFT.

```c
// Pré-calcul des twiddle factors pour une étape donnée
float cos_factor(int step, int n) {
    return cos(2 * M_PI * step / n);
}

float sin_factor(int step, int n) {
    return -sin(2 * M_PI * step / n);
}
```

**3. Boucle principale de la FFT**

L’algorithme procède par étapes, chaque étape fusionnant des DFT de tailles plus petites. La taille de la FFT doit être une puissance de deux.

```c
void fft(float *real, float *imag, int n) {
    int i, j, k, len, step;
    float tr, ti, wr, wi, tempr, tempi;

    // 1. Réordonnancement
    bit_reverse(real, imag, n);

    // 2. Boucle sur les étapes (len = taille des sous-DFT)
    for (len = 2; len <= n; len <<= 1) {
        step = n / len;  // pas entre les twiddle factors pour cette étape
        for (i = 0; i < n; i += len) {
            // Papillons pour cette sous-DFT
            for (j = 0; j < len / 2; j++) {
                // Indice du twiddle factor
                int tw = j * step;
                wr = cos_factor(tw, n);
                wi = sin_factor(tw, n);

                // Indice des échantillons
                int i1 = i + j;
                int i2 = i + j + len / 2;

                // Papillon
                tempr = real[i2] * wr - imag[i2] * wi;
                tempi = real[i2] * wi + imag[i2] * wr;

                real[i2] = real[i1] - tempr;
                imag[i2] = imag[i1] - tempi;
                real[i1] = real[i1] + tempr;
                imag[i1] = imag[i1] + tempi;
            }
        }
    }
}
```

**4. Calcul de l’amplitude**

Après la FFT, on obtient les parties réelle et imaginaire pour chaque fréquence. L’amplitude (module) est :

amp[k] = √(real[k]² + imag[k]²) / N (pour k = 0, N/2)

Pour les autres indices, on divise par N/2 pour obtenir l’amplitude réelle (si le signal est réel, les amplitudes sont symétriques). Souvent on ne s’intéresse qu’aux fréquences positives (de 0 à N/2).

```c
void compute_amplitude(float *real, float *imag, float *amp, int n) {
    for (int i = 0; i < n/2; i++) {
        amp[i] = 2.0f * sqrtf(real[i]*real[i] + imag[i]*imag[i]) / n;
    }
    amp[0] = sqrtf(real[0]*real[0] + imag[0]*imag[0]) / n; // composante continue
}
```

---
<br>



### **Optimisations pour l’embarqué**

Sur un microcontrôleur sans FPU (ou avec FPU mais limité), on peut :

- Utiliser la virgule fixe pour éviter les flottants lents. Mais la mise en œuvre est plus complexe.
- Pré-calculer tous les twiddle factors une fois pour toutes (gain de temps).
- Utiliser une taille de FFT fixe (ex: 256, 512) pour simplifier.

Notre code utilisera des flottants simples, ce qui est acceptable sur STM32F4 (avec FPU).

---
<br>




### **Intégration avec FreeRTOS**

Pour une analyse spectrale en temps réel, on peut :

- Acquérir un bloc d’échantillons via l’ADC (par exemple 256 échantillons à 1 kHz).
- Une fois le buffer rempli, lancer la FFT dans une tâche dédiée.
- Afficher les résultats (fréquence du pic, amplitude) sur UART ou écran.

**Structure du projet**

- Tâche `vTaskADC` : acquiert les échantillons dans un buffer circulaire ou un double buffer (avec DMA).
- Tâche `vTaskFFT` : attend qu’un buffer soit plein, effectue la FFT, extrait le pic principal, et envoie le résultat à une file.
- Tâche `vTaskDisplay` : reçoit les résultats et les affiche.

Exemple simplifié avec double buffer

```c
#define FFT_SIZE 256
float buffer1[FFT_SIZE];
float buffer2[FFT_SIZE];
volatile uint8_t activeBuffer = 0;
volatile uint8_t bufferReady = 0;

// Interruption ADC (fin de conversion) ou DMA
void ADC_IRQHandler(void) {
    static int count = 0;
    if (activeBuffer == 0) {
        buffer1[count++] = ADC_Read();
    } else {
        buffer2[count++] = ADC_Read();
    }
    if (count >= FFT_SIZE) {
        bufferReady = 1;
        count = 0;
        activeBuffer ^= 1; // basculer de buffer
        // Notifier la tâche FFT (par exemple via un sémaphore)
    }
}
```

**Tâche FFT**

```c
void vTaskFFT(void *pvParameters) {
    float real[FFT_SIZE], imag[FFT_SIZE];
    float amp[FFT_SIZE/2];

    for (;;) {
        // Attendre qu'un buffer soit prêt (par exemple sémaphore)
        ulTaskNotifyTake(pdTRUE, portMAX_DELAY);

        // Copier le buffer inactif (celui qui n'est plus en cours d'acquisition)
        int bufferToProcess = activeBuffer ^ 1;
        for (int i = 0; i < FFT_SIZE; i++) {
            if (bufferToProcess == 0)
                real[i] = buffer1[i];
            else
                real[i] = buffer2[i];
            imag[i] = 0.0f;
        }

        // Calcul FFT
        fft(real, imag, FFT_SIZE);
        compute_amplitude(real, imag, amp, FFT_SIZE);

        // Trouver le pic (hors composante continue)
        int peakIndex = 1;
        for (int i = 2; i < FFT_SIZE/2; i++) {
            if (amp[i] > amp[peakIndex]) peakIndex = i;
        }
        float freq = (float)peakIndex * SAMPLING_FREQ / FFT_SIZE;

        // Envoyer résultat à la tâche d'affichage (par file)
        xQueueSend(xResultQueue, &freq, 0);
    }
}
```

---
<br>



### **Projet : Analyse spectrale d’un signal audio** {#projet-fft-audio}

Objectif : Acquérir un signal audio via l’ADC (microphone ou entrée ligne), effectuer une FFT de 256 points à 1 kHz, et afficher la fréquence dominante sur UART (ou sur un écran OLED).

**Matériel :**

- Carte STM32F401 (Black Pill)
- Microphone avec sortie analogique (ou module comme MAX9814) connecté à PA0
- (Optionnel) écran OLED I2C

**Code principal**

```c
#include "FreeRTOS.h"
#include "task.h"
#include "queue.h"
#include "stm32f4xx.h"
#include <math.h>
#include <stdio.h>

#define FFT_SIZE 256
#define SAMPLING_FREQ 1000.0f  // 1 kHz

// Buffers
float buffer[2][FFT_SIZE];
volatile uint8_t activeBuffer = 0;
volatile uint8_t bufferCount = 0;
SemaphoreHandle_t xFFTSemaphore;
QueueHandle_t xResultQueue;

// Prototypes
void ADC_Init(void);
void USART2_Init(uint32_t baud);
void USART2_SendString(char *str);
int _write(int file, char *ptr, int len);

// Fonctions FFT
void bit_reverse(float *real, float *imag, int n);
void fft(float *real, float *imag, int n);
void compute_amplitude(float *real, float *imag, float *amp, int n);

// Interruption ADC (déclenchée par timer)
void TIM2_IRQHandler(void) {
    if (TIM2->SR & TIM_SR_UIF) {
        TIM2->SR &= ~TIM_SR_UIF;
        // Lancer conversion ADC
        ADC1->CR2 |= ADC_CR2_SWSTART;
    }
}

void ADC_IRQHandler(void) {
    if (ADC1->SR & ADC_SR_EOC) {
        uint16_t val = ADC1->DR;
        // Stocker dans le buffer actif
        buffer[activeBuffer][bufferCount++] = (float)val;
        if (bufferCount >= FFT_SIZE) {
            bufferCount = 0;
            activeBuffer ^= 1;  // basculer
            // Donner le sémaphore pour réveiller la tâche FFT
            BaseType_t xWoken = pdFALSE;
            xSemaphoreGiveFromISR(xFFTSemaphore, &xWoken);
            portYIELD_FROM_ISR(xWoken);
        }
    }
}

// Tâche FFT
void vTaskFFT(void *pvParameters) {
    float real[FFT_SIZE], imag[FFT_SIZE];
    float amp[FFT_SIZE/2];

    for (;;) {
        xSemaphoreTake(xFFTSemaphore, portMAX_DELAY);

        // Traiter le buffer inactif (celui qui vient d'être rempli)
        int bufferIdx = activeBuffer ^ 1;
        for (int i = 0; i < FFT_SIZE; i++) {
            real[i] = buffer[bufferIdx][i];
            imag[i] = 0.0f;
        }

        fft(real, imag, FFT_SIZE);
        compute_amplitude(real, imag, amp, FFT_SIZE);

        // Trouver le pic (hors DC)
        int peakIdx = 1;
        for (int i = 2; i < FFT_SIZE/2; i++) {
            if (amp[i] > amp[peakIdx]) peakIdx = i;
        }
        float freq = peakIdx * SAMPLING_FREQ / FFT_SIZE;

        xQueueSend(xResultQueue, &freq, 0);
    }
}

// Tâche d'affichage
void vTaskDisplay(void *pvParameters) {
    float freq;
    char buffer[32];

    for (;;) {
        if (xQueueReceive(xResultQueue, &freq, portMAX_DELAY) == pdPASS) {
            sprintf(buffer, "Freq max: %.1f Hz\r\n", freq);
            USART2_SendString(buffer);
        }
    }
}

int main(void) {
    HAL_Init();
    SystemClock_Config(); // doit fournir 84 MHz

    ADC_Init();
    USART2_Init(115200);

    // Timer 2 pour déclencher l'ADC à 1 kHz (période 1 ms)
    RCC->APB1ENR |= RCC_APB1ENR_TIM2EN;
    TIM2->PSC = 84 - 1;       // 1 MHz
    TIM2->ARR = 1000 - 1;     // 1 kHz
    TIM2->DIER |= TIM_DIER_UIE;
    NVIC_SetPriority(TIM2_IRQn, 5);
    NVIC_EnableIRQ(TIM2_IRQn);
    TIM2->CR1 |= TIM_CR1_CEN;

    xFFTSemaphore = xSemaphoreCreateBinary();
    xResultQueue = xQueueCreate(5, sizeof(float));

    xTaskCreate(vTaskFFT, "FFT", 512, NULL, 3, NULL);
    xTaskCreate(vTaskDisplay, "Display", 128, NULL, 1, NULL);

    vTaskStartScheduler();

    while(1);
}
```

**Explications**

Le timer **TIM2** génère une interruption toutes les **1 ms**. Dans son handler, on lance une conversion **ADC**.

La fin de conversion **ADC** déclenche une interruption qui stocke l’échantillon dans un **buffer circulaire double**.

Quand un buffer est plein (**256 échantillons**), on donne un **sémaphore** pour réveiller la **tâche FFT**.

La tâche **FFT** effectue la transformée et extrait la fréquence du pic (hors composante continue). Le résultat est envoyé à la **tâche d’affichage**.

La tâche d’affichage envoie la fréquence sur **UART** (via `printf` redirigé).

---
<br>



### Limitations et améliorations

La résolution fréquentielle est :
fe / N

Avec :
fe = 1 kHz
N = 256

la résolution est d’environ **3,9 Hz**.

Pour une meilleure résolution, il faut **augmenter N** ou **diminuer fe**.

Le calcul en **flottants** est assez rapide sur **STM32F4 (FPU)**, mais pour des FFT plus grandes, on peut utiliser la **bibliothèque CMSIS-DSP optimisée**.

Le **fenêtrage** (Hamming, Hann) n’est pas appliqué ici ; il réduit les **fuites spectrales**. On pourrait multiplier le signal d’entrée par une **fenêtre** avant la FFT.




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
- [Filtres Numériques](../../technique-algos/filtre/index.md)
- [Introduction pratique à freeRTOS](../../rtos/#introduction-a-freertos)

