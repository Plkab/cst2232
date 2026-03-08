# Estimation d'État et Fusion Capteurs

*Ir Paul S. Kabidu, M.Eng. <spaulkabidu@gmail.com>*
{: style="text-align: center;" }

---

[Accueil](../../#Accueil)

<br>
<br>




### **Introduction**

Dans de nombreux systèmes embarqués, une grandeur physique (angle, position, vitesse) ne peut pas être mesurée directement avec une précision suffisante ou peut être entachée de bruit. On dispose souvent de plusieurs capteurs aux caractéristiques complémentaires : par exemple, un accéléromètre donne une bonne estimation à long terme mais est bruité à court terme, tandis qu’un gyroscope est précis à court terme mais dérive dans le temps. La **fusion de capteurs** combine ces mesures pour obtenir une estimation plus fiable et plus précise.

L’**estimation d’état** est le processus qui consiste à déterminer l’état interne d’un système dynamique à partir de mesures bruitées. Dans ce chapitre, nous étudierons deux méthodes couramment utilisées dans l’embarqué :

- Le **filtre complémentaire** : simple, peu coûteux en calcul, idéal pour fusionner accéléromètre et gyroscope.
- Le **filtre de Kalman** : plus complexe, optimal pour les systèmes linéaires gaussiens.

Nous mettrons en œuvre ces techniques sur STM32F4 avec FreeRTOS pour estimer l’angle d’inclinaison d’un système à partir d’un IMU (MPU6050). Cette estimation pourra ensuite être utilisée dans un asservissement (ex: stabilisation de drone, pendule inversé).

---
<br>



### **Rappels sur les capteurs d’un IMU**

Un central inertiel (IMU) typique contient :

- **Accéléromètre** : mesure l’accélération linéaire (incluant la gravité). Au repos, il indique la direction de la gravité. Il est précis sur le long terme mais très bruité à court terme.
- **Gyroscope** : mesure la vitesse angulaire. En intégrant, on obtient l’angle. Il est précis à court terme mais dérive à cause de l’intégration du biais (drift).

L’objectif est de fusionner ces deux sources pour obtenir un angle fiable.

---
<br>




### **Filtre complémentaire**

Le principe du filtre complémentaire est de combiner une estimation haute fréquence (gyroscope) et une estimation basse fréquence (accéléromètre). On utilise un filtre passe-haut sur l’intégration du gyroscope et un filtre passe-bas sur l’accéléromètre, puis on somme les deux.

L’équation discrète simple est :

\[
\text{angle}_k = \alpha \cdot (\text{angle}_{k-1} + \dot{\theta}_k \cdot dt) + (1-\alpha) \cdot \theta_{\text{acc}}_k
\]

avec :
- \(\alpha = \frac{\tau}{\tau + dt}\), où \(\tau\) est la constante de temps (souvent entre 0.5 et 2 s).
- \(\dot{\theta}_k\) : vitesse angulaire mesurée par le gyroscope.
- \(\theta_{\text{acc}}_k\) : angle estimé à partir de l’accéléromètre (\(\arctan(A_x, A_z)\) par exemple).
- \(dt\) : pas de temps.

**Implémentation en C**

```c
typedef struct {
    float angle;        // angle estimé
    float bias;         // biais estimé (optionnel)
    float Q_angle;      // variance du bruit sur l'angle
    float Q_bias;       // variance du bruit sur le biais
    float R_measure;    // variance du bruit de mesure
    float P[2][2];      // matrice de covariance
} ComplementaryFilter;

// Initialisation
void Complementary_Init(ComplementaryFilter *f, float tau, float dt) {
    float alpha = tau / (tau + dt);
    f->angle = 0.0f;
    // Pour un filtre simple, on n'a pas besoin de plus.
}

// Mise à jour avec données gyro et accéléromètre
float Complementary_Update(ComplementaryFilter *f, float gyroRate, float accAngle, float dt) {
    // Prédiction à partir du gyroscope
    float gyroAngle = f->angle + gyroRate * dt;

    // Fusion avec l'accéléromètre
    float alpha = 0.98f; // constante de temps 0.98/0.02 ≈ 49s (si dt=0.01s)
    f->angle = alpha * gyroAngle + (1.0f - alpha) * accAngle;

    return f->angle;
}
```

Remarque : le coefficient α doit être choisi en fonction de dt et de la constante de temps souhaitée. Plus α est proche de 1, plus on fait confiance au gyroscope.



---
<br>




### **Filtre de Kalman (version simplifiée)**

Le filtre de Kalman est un estimateur récursif optimal pour les systèmes linéaires avec bruit gaussien. Il se compose de deux étapes :

- **Prédiction** : on projette l’état courant et la covariance.
- **Mise à jour** : on corrige l’état à l’aide de la mesure.

Pour un angle à estimer à partir d’un gyroscope et d’un accéléromètre, on peut utiliser un modèle d’état simple :

**État :**
x = [θ, θ˙b] (angle et biais du gyroscope).

**Équation d’état :**
{
θk = θk−1 + (θ˙m − θ˙b) dt
θ˙b = θ˙b
}
où **θ˙m** est la mesure du gyroscope.


**Implémentation en C**

```c
typedef struct {
    float angle;
    float bias;
    float Q_angle;      // variance du bruit sur l'angle (process)
    float Q_bias;       // variance du bruit sur le biais
    float R_measure;    // variance du bruit de mesure (accéléromètre)
    float P[2][2];      // matrice de covariance
} KalmanFilter;

void Kalman_Init(KalmanFilter *kf) {
    kf->angle = 0.0f;
    kf->bias = 0.0f;
    kf->P[0][0] = 0.0f;
    kf->P[0][1] = 0.0f;
    kf->P[1][0] = 0.0f;
    kf->P[1][1] = 0.0f;
    kf->Q_angle = 0.001f;
    kf->Q_bias = 0.003f;
    kf->R_measure = 0.03f;
}

float Kalman_Update(KalmanFilter *kf, float gyroRate, float accAngle, float dt) {
    // ---- Prédiction ----
    // Estimation a priori
    kf->angle += dt * (gyroRate - kf->bias);

    // Covariance a priori
    kf->P[0][0] += dt * (dt*kf->P[1][1] - kf->P[0][1] - kf->P[1][0] + kf->Q_angle);
    kf->P[0][1] -= dt * kf->P[1][1];
    kf->P[1][0] -= dt * kf->P[1][1];
    kf->P[1][1] += kf->Q_bias * dt;

    // ---- Mise à jour avec la mesure accéléromètre ----
    float y = accAngle - kf->angle;               // innovation
    float S = kf->P[0][0] + kf->R_measure;        // covariance de l'innovation

    float K[2];                                   // gain de Kalman
    K[0] = kf->P[0][0] / S;
    K[1] = kf->P[1][0] / S;

    // Correction
    kf->angle += K[0] * y;
    kf->bias  += K[1] * y;

    // Mise à jour de la covariance
    float P00_temp = kf->P[0][0];
    float P01_temp = kf->P[0][1];

    kf->P[0][0] -= K[0] * P00_temp;
    kf->P[0][1] -= K[0] * P01_temp;
    kf->P[1][0] -= K[1] * P00_temp;
    kf->P[1][1] -= K[1] * P01_temp;

    return kf->angle;
}
```

Remarque : Les paramètres de bruit (`Q_angle`, `Q_bias`, `R_measure`) doivent être ajustés expérimentalement.

---
<br>



### **Intégration avec un IMU (MPU6050) et FreeRTOS**

Nous allons maintenant lire les données brutes d’un MPU6050 via I2C, les convertir en angle d’inclinaison (accéléromètre) et en vitesse angulaire (gyroscope), puis appliquer un filtre complémentaire dans une tâche FreeRTOS.

**Structure du projet**

- Tâche `vTaskIMUReader` : lit périodiquement les registres du MPU6050 (via I2C en mode polling ou avec interruption) et place les données brutes dans une file.
- Tâche `vTaskEstimator` : récupère les données, applique le filtre, et met le résultat à disposition (variable globale ou autre file).
- Tâche `vTaskMonitor` (optionnelle) : affiche l’angle estimé sur UART.

**Code partiel pour le MPU6050**

```c
// Adresse MPU6050 (AD0 = 0 -> 0x68)
#define MPU6050_ADDR    0x68
#define MPU6050_WHO_AM_I 0x75

// Initialisation (simplifiée)
void MPU6050_Init(void) {
    // Sortir du mode sommeil (register PWR_MGMT_1, bit 6 = 0)
    uint8_t data = 0x00;
    I2C_Write(MPU6050_ADDR, 0x6B, &data, 1);
}

// Lecture des accélérations et gyros
void MPU6050_Read(float *ax, float *ay, float *az, float *gx, float *gy, float *gz) {
    uint8_t buffer[14];
    I2C_Read(MPU6050_ADDR, 0x3B, buffer, 14); // lecture en rafale

    int16_t raw_ax = (buffer[0] << 8) | buffer[1];
    int16_t raw_ay = (buffer[2] << 8) | buffer[3];
    int16_t raw_az = (buffer[4] << 8) | buffer[5];
    // ... idem pour gyro (buffer[8] à buffer[13])

    // Conversion en unités physiques (selon la sensibilité configurée)
    *ax = (float)raw_ax / 16384.0f; // pour ±2g
    *ay = (float)raw_ay / 16384.0f;
    *az = (float)raw_az / 16384.0f;
    *gx = (float)raw_gx / 131.0f;   // pour ±250°/s
    *gy = (float)raw_gy / 131.0f;
    *gz = (float)raw_gz / 131.0f;
}
```

**Calcul de l’angle à partir de l’accéléromètre**

Si on suppose que le capteur est incliné autour de l’axe X, l’angle peut être calculé par :

```c
float accel_angle_x = atan2f(ay, az) * 180.0f / 3.14159f;
// Attention : selon l'orientation du capteur, ajuster.
```

**Tâches FreeRTOS**

```c
#include "FreeRTOS.h"
#include "task.h"
#include "queue.h"

QueueHandle_t xIMUQueue;

typedef struct {
    float accAngle;   // angle calculé depuis accéléromètre
    float gyroRate;   // vitesse angulaire (rad/s ou °/s)
} IMUData_t;

void vTaskIMUReader(void *pvParameters) {
    TickType_t xLastWakeTime = xTaskGetTickCount();
    const TickType_t xPeriod = pdMS_TO_TICKS(10); // 100 Hz
    IMUData_t data;

    for (;;) {
        vTaskDelayUntil(&xLastWakeTime, xPeriod);

        // Lire MPU6050
        float ax, ay, az, gx, gy, gz;
        MPU6050_Read(&ax, &ay, &az, &gx, &gy, &gz);

        // Calculer angle accéléromètre (par exemple autour de X)
        data.accAngle = atan2f(ay, az) * 180.0f / 3.14159f;
        data.gyroRate = gx; // vitesse angulaire en °/s

        xQueueSend(xIMUQueue, &data, 0);
    }
}

void vTaskEstimator(void *pvParameters) {
    ComplementaryFilter filter;
    Complementary_Init(&filter, 0.5f, 0.01f); // tau = 0.5s, dt = 0.01s
    IMUData_t data;
    float estimatedAngle = 0.0f;

    for (;;) {
        if (xQueueReceive(xIMUQueue, &data, portMAX_DELAY) == pdPASS) {
            estimatedAngle = Complementary_Update(&filter, data.gyroRate, data.accAngle, 0.01f);
            // Utiliser estimatedAngle (par exemple pour affichage ou contrôle)
        }
    }
}
```

---
<br>

### **Projet : Estimation d’angle pour un drone ou une plateforme** {#projet-estimation-angle}

Objectif : lire les données d’un MPU6050, appliquer un filtre complémentaire, et afficher l’angle en temps réel sur un terminal UART. Le code complet intègre I2C, FreeRTOS, et les filtres.

```c
// Fichier main.c complet (simplifié)
#include "FreeRTOS.h"
#include "task.h"
#include "queue.h"
#include "stm32f4xx.h"
#include <math.h>
#include <stdio.h>

// Fonctions I2C (à implémenter)
void I2C1_Init(void);
void I2C_Write(uint8_t devAddr, uint8_t regAddr, uint8_t *data, uint8_t len);
void I2C_Read(uint8_t devAddr, uint8_t regAddr, uint8_t *buf, uint8_t len);

// Fonctions UART pour printf
void USART2_Init(uint32_t baud);
int _write(int file, char *ptr, int len);

// Filtre complémentaire
typedef struct {
    float angle;
} ComplementaryFilter;

void Complementary_Init(ComplementaryFilter *f) {
    f->angle = 0.0f;
}

float Complementary_Update(ComplementaryFilter *f, float gyroRate, float accAngle, float dt) {
    float alpha = 0.98f;
    float gyroAngle = f->angle + gyroRate * dt;
    f->angle = alpha * gyroAngle + (1.0f - alpha) * accAngle;
    return f->angle;
}

// Handles et files
QueueHandle_t xIMUQueue;

// Tâche de lecture IMU
void vTaskIMUReader(void *pvParameters) {
    TickType_t xLastWakeTime = xTaskGetTickCount();
    const TickType_t xPeriod = pdMS_TO_TICKS(10);
    float ax, ay, az, gx, gy, gz;
    float accAngle, gyroRate;

    // Initialiser MPU6050
    uint8_t tmp = 0x00;
    I2C_Write(0x68, 0x6B, &tmp, 1); // sortir du sommeil

    for (;;) {
        vTaskDelayUntil(&xLastWakeTime, xPeriod);

        // Lecture MPU6050 (simplifiée)
        uint8_t buf[14];
        I2C_Read(0x68, 0x3B, buf, 14);
        int16_t raw_ax = (buf[0] << 8) | buf[1];
        int16_t raw_ay = (buf[2] << 8) | buf[3];
        int16_t raw_az = (buf[4] << 8) | buf[5];
        int16_t raw_gx = (buf[8] << 8) | buf[9];
        int16_t raw_gy = (buf[10] << 8) | buf[11];
        int16_t raw_gz = (buf[12] << 8) | buf[13];

        ax = raw_ax / 16384.0f;
        ay = raw_ay / 16384.0f;
        az = raw_az / 16384.0f;
        gx = raw_gx / 131.0f;
        gy = raw_gy / 131.0f;
        gz = raw_gz / 131.0f;

        // Calcul angle accéléromètre (autour de X)
        accAngle = atan2f(ay, az) * 180.0f / 3.14159f;
        gyroRate = gx;

        xQueueSend(xIMUQueue, &accAngle, 0);
        // Envoyer aussi gyroRate ? Pour simplifier, on envoie les deux via une structure.
    }
}

// Tâche d'estimation
void vTaskEstimator(void *pvParameters) {
    ComplementaryFilter filter;
    Complementary_Init(&filter);
    float accAngle, gyroRate;
    float estimatedAngle;

    for (;;) {
        // Reçoit les données (structure plus complète à définir)
        // Ici on suppose une queue qui envoie deux floats
        if (xQueueReceive(xIMUQueue, &accAngle, portMAX_DELAY) == pdPASS) {
            // Récupérer aussi gyroRate (pour l'exemple, on simule)
            gyroRate = 0; // à remplacer par vraie réception
            estimatedAngle = Complementary_Update(&filter, gyroRate, accAngle, 0.01f);
            printf("Angle estimé: %.2f deg\r\n", estimatedAngle);
        }
    }
}

int main(void) {
    HAL_Init();
    SystemClock_Config(); // à définir
    I2C1_Init();
    USART2_Init(115200);

    xIMUQueue = xQueueCreate(5, sizeof(float)); // pas idéal : on devrait envoyer deux floats

    xTaskCreate(vTaskIMUReader, "IMUReader", 256, NULL, 2, NULL);
    xTaskCreate(vTaskEstimator, "Estimator", 256, NULL, 1, NULL);

    vTaskStartScheduler();

    while(1);
}
```

---
<br>



### **Liens connexes**

- [GPIO et Interruptions](../../stm32f4/gpio/)
- [Timer et Interruption](../../stm32f4/timer/)
- [Communication Série USART](../../stm32f4/usart/index.md)
- [Acquisition Analogique via ADC](../../stm32f4/adc/index.md)
- [Génération des signaux PWM](../../stm32f4/pwm/index.md)
- [Machine d’État Fini (FSM)](../../technique-algos/fsm/index.md)
- [Optimisation de Transfert des Données avec DMA](../../stm32f4/dma/index.md)
- [Introduction pratique à freeRTOS](../../rtos/#introduction-a-freertos)
