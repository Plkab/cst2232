# Projet : Filtrage des données et Fusion capteur de l'IMU 6050 via Filtre de Kalman

*Ir Paul S. Kabidu, M.Eng. <spaulkabidu@gmail.com>*
{: style="text-align: center;" }

---

[Accueil](../../#Accueil)

<br>
<br>


### **Introduction**

Ce projet a pour objectif de mettre en pratique les notions d’estimation d’état et de fusion de capteurs abordées dans le chapitre précédent. Nous allons interfacer un **module MPU6050** (accéléromètre + gyroscope) avec notre carte STM32F401, lire les mesures brutes, appliquer un **filtre de Kalman** pour estimer l’angle d’inclinaison (par exemple autour de l’axe X), et envoyer cette estimation en temps réel à un PC via la liaison série (USB). Côté PC, une interface graphique Python affichera l’angle estimé et tracera son évolution.

Ce projet illustre l’intégration d’un capteur I2C, le traitement numérique du signal en temps réel, et la communication avec un ordinateur pour la visualisation.

---
<br>



### **Cahier des charges**

- **Acquisition des données IMU** :
    - Le MPU6050 est connecté au bus I2C du STM32 (par exemple I2C1 sur PB6/PB7).
    - L’accéléromètre et le gyroscope sont lus à une fréquence fixe (par exemple 100 Hz).

- **Traitement temps réel** :
    - Une tâche FreeRTOS lit périodiquement les capteurs et applique un filtre de Kalman (modèle à deux états : angle et biais du gyroscope).
    - L’angle estimé est mis à disposition pour l’envoi vers le PC.

- **Communication avec le PC** :
    - Une tâche dédiée envoie l’angle estimé (et éventuellement les données brutes) sur l’USART2 (connecté au port USB de la carte) vers le PC, à une fréquence plus basse (par exemple 10 Hz).
    - Le format d’envoi peut être CSV ou JSON simple.

- **Interface Python** :
    - Un script Python lit les données sur le port série et les affiche dans une fenêtre graphique.
    - L’interface montre l’angle courant (sous forme numérique) et un graphique en temps réel de l’évolution de l’angle (courbe glissante).

- **Contraintes techniques** :
    - Utilisation de FreeRTOS pour gérer les tâches (priorités adaptées).
    - Les lectures I2C peuvent être bloquantes, mais on peut utiliser des files pour découpler l’acquisition du traitement (optionnel).
    - Le filtre de Kalman doit être implémenté en virgule flottante (float).
    - La tâche d’envoi sur USART utilise un buffer circulaire ou une file pour ne pas bloquer.

---
<br>



### **Matériel nécessaire**

- Carte STM32F401 (Black Pill)
- Module MPU6050 (GY‑521)
- Connexions I2C :
    - SCL → PB6 (I2C1_SCL)
    - SDA → PB7 (I2C1_SDA)
    - VCC → 3,3 V
    - GND → GND
- Câble USB pour la programmation et la communication série avec le PC

---
<br>



### **Code STM32 (FreeRTOS)**

Le code complet est organisé comme suit :

- **I2C** : initialisation et fonctions de lecture (mode polling, mais on pourrait les remplacer par des interruptions).
- **MPU6050** : initialisation (sortie du sommeil, configuration des plages) et lecture des accélérations et vitesses angulaires.
- **Filtre de Kalman** : structure et fonctions de mise à jour (modèle 2D).
- **Files** : pour transmettre les angles estimés de la tâche de filtrage à la tâche d’envoi.
- **Tâches FreeRTOS** :
    - `vTaskIMUReader` : lit les données à 100 Hz et applique le filtre.
    - `vTaskUARTTransmitter` : récupère l’angle et l’envoie sur UART à 10 Hz.

```c
/*****************************************************************************
 * Projet IMU Kalman avec FreeRTOS sur STM32F401
 * Lecture du MPU6050 via I2C, filtrage de Kalman, envoi sur UART
 *****************************************************************************/

#include "FreeRTOS.h"
#include "task.h"
#include "queue.h"
#include "semphr.h"
#include "stm32f4xx.h"
#include <math.h>
#include <stdio.h>

// ======================== Définitions =========================

#define I2C_TIMEOUT         1000
#define MPU6050_ADDR        0x68      // AD0 = 0 (si AD0 à VCC, utiliser 0x69)

// Plages de mesure
#define ACCEL_SCALE         16384.0f   // pour ±2g
#define GYRO_SCALE          131.0f     // pour ±250°/s

// Fréquences
#define IMU_READ_FREQ       100        // Hz
#define IMU_READ_PERIOD_MS  (1000 / IMU_READ_FREQ)   // 10 ms
#define UART_SEND_FREQ      10         // Hz
#define UART_SEND_PERIOD_MS (1000 / UART_SEND_FREQ)  // 100 ms

// Taille des files
#define ANGLE_QUEUE_SIZE    5

// ======================== Structures =========================

// Structure pour le filtre de Kalman (modèle angle + biais)
typedef struct {
    float angle;          // angle estimé (rad ou deg)
    float bias;           // biais estimé du gyroscope
    float P[2][2];        // matrice de covariance
    float Q_angle;        // variance du bruit sur l'angle (process)
    float Q_bias;         // variance du bruit sur le biais
    float R_measure;      // variance du bruit de mesure (accéléromètre)
} KalmanFilter_t;

// ======================== Handles FreeRTOS ===================

QueueHandle_t xAngleQueue;      // File pour transmettre l'angle estimé

// ======================== Prototypes =========================

void I2C1_Init(void);
void MPU6050_Init(void);
uint8_t MPU6050_ReadAccelGyro(float *ax, float *ay, float *az, float *gx, float *gy, float *gz);
void Kalman_Init(KalmanFilter_t *kf);
float Kalman_Update(KalmanFilter_t *kf, float gyroRate, float accAngle, float dt);
void USART2_Init(uint32_t baud);
void USART2_SendString(char *str);
int _write(int file, char *ptr, int len);   // pour printf

// ======================== Initialisation I2C1 ================

/**
 * @brief Initialise I2C1 sur PB6 (SCL) et PB7 (SDA) à 100 kHz.
 */
void I2C1_Init(void) {
    // Activer horloges GPIOB et I2C1
    RCC->AHB1ENR |= RCC_AHB1ENR_GPIOBEN;
    RCC->APB1ENR |= RCC_APB1ENR_I2C1EN;

    // PB6, PB7 en alternate function AF4
    GPIOB->MODER &= ~((3U << (6*2)) | (3U << (7*2)));
    GPIOB->MODER |=  ((2U << (6*2)) | (2U << (7*2)));
    GPIOB->AFR[0] &= ~((0xF << (6*4)) | (0xF << (7*4)));
    GPIOB->AFR[0] |=  ((4 << (6*4)) | (4 << (7*4)));

    // Reset I2C
    I2C1->CR1 = I2C_CR1_SWRST;
    I2C1->CR1 = 0;

    // Configuration : 100 kHz, APB1 = 42 MHz? Non, sur F401, APB1 peut être à 42 MHz ou 84 MHz selon config.
    // Nous supposons ici APB1 = 84 MHz (vérifiez votre horloge)
    I2C1->CR2 = 42;                 // Fréquence APB1 en MHz (à ajuster si 42 ou 84)
    I2C1->CCR = 210;                 // 42 MHz / (2*100 kHz) = 210 (mode standard)
    I2C1->TRISE = 43;                // 1000 ns / (1/42 MHz) = 42 + 1 = 43
    I2C1->CR1 |= I2C_CR1_PE;
}

// ======================== Fonctions I2C bas niveau ===========

/**
 * @brief Écrit un octet dans un registre du MPU6050.
 */
uint8_t I2C_WriteReg(uint8_t devAddr, uint8_t regAddr, uint8_t data) {
    // Attendre que le bus soit libre
    while (I2C1->SR2 & I2C_SR2_BUSY);

    // START
    I2C1->CR1 |= I2C_CR1_START;
    while (!(I2C1->SR1 & I2C_SR1_SB));

    // Adresse + écriture
    I2C1->DR = devAddr << 1;
    while (!(I2C1->SR1 & I2C_SR1_ADDR));
    (void)I2C1->SR2;

    // Registre
    while (!(I2C1->SR1 & I2C_SR1_TXE));
    I2C1->DR = regAddr;
    while (!(I2C1->SR1 & I2C_SR1_BTF));

    // Donnée
    I2C1->DR = data;
    while (!(I2C1->SR1 & I2C_SR1_BTF));

    // STOP
    I2C1->CR1 |= I2C_CR1_STOP;
    return 1;
}

/**
 * @brief Lit plusieurs octets séquentiellement à partir d'un registre.
 */
uint8_t I2C_ReadRegs(uint8_t devAddr, uint8_t regAddr, uint8_t *buf, uint16_t len) {
    while (I2C1->SR2 & I2C_SR2_BUSY);

    // START
    I2C1->CR1 |= I2C_CR1_START;
    while (!(I2C1->SR1 & I2C_SR1_SB));

    // Adresse + écriture
    I2C1->DR = devAddr << 1;
    while (!(I2C1->SR1 & I2C_SR1_ADDR));
    (void)I2C1->SR2;

    // Registre
    while (!(I2C1->SR1 & I2C_SR1_TXE));
    I2C1->DR = regAddr;
    while (!(I2C1->SR1 & I2C_SR1_BTF));

    // RESTART pour la lecture
    I2C1->CR1 |= I2C_CR1_START;
    while (!(I2C1->SR1 & I2C_SR1_SB));

    // Adresse + lecture
    I2C1->DR = (devAddr << 1) | 1;
    while (!(I2C1->SR1 & I2C_SR1_ADDR));
    (void)I2C1->SR2;

    // Réception
    for (uint16_t i = 0; i < len; i++) {
        if (i == len - 1) {
            // Désactiver ACK avant le dernier octet
            I2C1->CR1 &= ~I2C_CR1_ACK;
        }
        while (!(I2C1->SR1 & I2C_SR1_RXNE));
        buf[i] = I2C1->DR;
    }

    // STOP
    I2C1->CR1 |= I2C_CR1_STOP;
    // Réactiver ACK pour les prochaines transactions
    I2C1->CR1 |= I2C_CR1_ACK;
    return 1;
}

// ======================== Initialisation MPU6050 =============

/**
 * @brief Configure le MPU6050 : sortie du sommeil, plages par défaut.
 */
void MPU6050_Init(void) {
    // Sortir du sommeil (register PWR_MGMT_1, bit 6 = 0)
    I2C_WriteReg(MPU6050_ADDR, 0x6B, 0x00);
    // Configurer la plage de l'accéléromètre à ±2g (registre ACCEL_CONFIG, bits 4:3 = 00)
    I2C_WriteReg(MPU6050_ADDR, 0x1C, 0x00);
    // Configurer la plage du gyroscope à ±250°/s (registre GYRO_CONFIG, bits 4:3 = 00)
    I2C_WriteReg(MPU6050_ADDR, 0x1B, 0x00);
    // Optionnel : configurer le filtre passe-bas (registre CONFIG)
    // I2C_WriteReg(MPU6050_ADDR, 0x1A, 0x03); // filtre 44 Hz
}

// ======================== Lecture MPU6050 ====================

/**
 * @brief Lit les accélérations et vitesses angulaires du MPU6050.
 * @return 1 si succès, 0 sinon.
 */
uint8_t MPU6050_ReadAccelGyro(float *ax, float *ay, float *az, float *gx, float *gy, float *gz) {
    uint8_t buffer[14];
    if (!I2C_ReadRegs(MPU6050_ADDR, 0x3B, buffer, 14)) return 0;

    int16_t raw_ax = (buffer[0] << 8) | buffer[1];
    int16_t raw_ay = (buffer[2] << 8) | buffer[3];
    int16_t raw_az = (buffer[4] << 8) | buffer[5];
    int16_t raw_gx = (buffer[8] << 8) | buffer[9];
    int16_t raw_gy = (buffer[10] << 8) | buffer[11];
    int16_t raw_gz = (buffer[12] << 8) | buffer[13];

    *ax = (float)raw_ax / ACCEL_SCALE;
    *ay = (float)raw_ay / ACCEL_SCALE;
    *az = (float)raw_az / ACCEL_SCALE;
    *gx = (float)raw_gx / GYRO_SCALE;
    *gy = (float)raw_gy / GYRO_SCALE;
    *gz = (float)raw_gz / GYRO_SCALE;

    return 1;
}

// ======================== Filtre de Kalman ===================

/**
 * @brief Initialise le filtre de Kalman.
 */
void Kalman_Init(KalmanFilter_t *kf) {
    kf->angle = 0.0f;
    kf->bias = 0.0f;
    kf->P[0][0] = 0.0f;
    kf->P[0][1] = 0.0f;
    kf->P[1][0] = 0.0f;
    kf->P[1][1] = 0.0f;
    // À régler expérimentalement
    kf->Q_angle = 0.001f;
    kf->Q_bias = 0.003f;
    kf->R_measure = 0.03f;
}

/**
 * @brief Met à jour le filtre avec une nouvelle mesure gyro et accéléromètre.
 * @param gyroRate Vitesse angulaire mesurée (en °/s)
 * @param accAngle Angle calculé à partir de l'accéléromètre (en degrés)
 * @param dt Intervalle de temps depuis la dernière mise à jour (en secondes)
 * @return Angle estimé (en degrés)
 */
float Kalman_Update(KalmanFilter_t *kf, float gyroRate, float accAngle, float dt) {
    // ---- Prédiction (time update) ----
    // L'angle est prédit par intégration du gyro (corrigé du biais)
    kf->angle += dt * (gyroRate - kf->bias);

    // Mise à jour de la covariance a priori
    kf->P[0][0] += dt * (dt*kf->P[1][1] - kf->P[0][1] - kf->P[1][0] + kf->Q_angle);
    kf->P[0][1] -= dt * kf->P[1][1];
    kf->P[1][0] -= dt * kf->P[1][1];
    kf->P[1][1] += kf->Q_bias * dt;

    // ---- Mise à jour avec la mesure (measurement update) ----
    float y = accAngle - kf->angle;               // innovation
    float S = kf->P[0][0] + kf->R_measure;        // covariance de l'innovation
    float K[2];                                    // gain de Kalman
    K[0] = kf->P[0][0] / S;
    K[1] = kf->P[1][0] / S;

    // Correction de l'état
    kf->angle += K[0] * y;
    kf->bias  += K[1] * y;

    // Mise à jour de la covariance (forme standard)
    float P00_temp = kf->P[0][0];
    float P01_temp = kf->P[0][1];
    kf->P[0][0] -= K[0] * P00_temp;
    kf->P[0][1] -= K[0] * P01_temp;
    kf->P[1][0] -= K[1] * P00_temp;
    kf->P[1][1] -= K[1] * P01_temp;

    return kf->angle;
}

// ======================== Initialisation USART2 ===============

void USART2_Init(uint32_t baud) {
    RCC->AHB1ENR |= RCC_AHB1ENR_GPIOAEN;
    RCC->APB1ENR |= RCC_APB1ENR_USART2EN;

    // PA2 TX, PA3 RX en AF7
    GPIOA->MODER &= ~((3U << (2*2)) | (3U << (3*2)));
    GPIOA->MODER |=  ((2U << (2*2)) | (2U << (3*2)));
    GPIOA->AFR[0] |= (7 << (2*4)) | (7 << (3*4));

    USART2->BRR = 84000000 / baud;
    USART2->CR1 = USART_CR1_TE | USART_CR1_UE; // transmission seule
}

void USART2_SendChar(char c) {
    while (!(USART2->SR & USART_SR_TXE));
    USART2->DR = c;
}

void USART2_SendString(char *str) {
    while (*str) {
        USART2_SendChar(*str++);
    }
}

// Pour printf
int _write(int file, char *ptr, int len) {
    for (int i = 0; i < len; i++) {
        USART2_SendChar(ptr[i]);
    }
    return len;
}

// ======================== Tâches FreeRTOS =====================

// Handle de la file (externe)
extern QueueHandle_t xAngleQueue;

/**
 * @brief Tâche de lecture de l'IMU et filtrage de Kalman.
 *        S'exécute à 100 Hz.
 */
void vTaskIMUReader(void *pvParameters) {
    TickType_t xLastWakeTime = xTaskGetTickCount();
    const TickType_t xPeriod = pdMS_TO_TICKS(IMU_READ_PERIOD_MS);
    float ax, ay, az, gx, gy, gz;
    float accAngle, gyroRate;
    float dt = IMU_READ_PERIOD_MS / 1000.0f;  // 0.01 s
    KalmanFilter_t kf;

    Kalman_Init(&kf);

    for (;;) {
        vTaskDelayUntil(&xLastWakeTime, xPeriod);

        if (MPU6050_ReadAccelGyro(&ax, &ay, &az, &gx, &gy, &gz)) {
            // Calcul de l'angle à partir de l'accéléromètre (autour de X)
            // On utilise atan2(ay, az) pour obtenir l'angle d'inclinaison.
            // Si le capteur est orienté autrement, adapter.
            accAngle = atan2f(ay, az) * 180.0f / 3.14159f;

            // Vitesse angulaire selon l'axe X (en °/s)
            gyroRate = gx;

            // Mise à jour du filtre
            float angle = Kalman_Update(&kf, gyroRate, accAngle, dt);

            // Envoyer l'angle dans la file (pour la tâche d'envoi UART)
            xQueueSend(xAngleQueue, &angle, 0);
        }
    }
}

/**
 * @brief Tâche d'envoi des données sur UART (10 Hz).
 *        Lit l'angle depuis la file et l'envoie formaté.
 */
void vTaskUARTTransmitter(void *pvParameters) {
    TickType_t xLastWakeTime = xTaskGetTickCount();
    const TickType_t xPeriod = pdMS_TO_TICKS(UART_SEND_PERIOD_MS);
    float angle;
    char buffer[32];

    for (;;) {
        vTaskDelayUntil(&xLastWakeTime, xPeriod);

        // Récupérer le dernier angle (non bloquant)
        if (xQueueReceive(xAngleQueue, &angle, 0) == pdPASS) {
            sprintf(buffer, "%.2f\r\n", angle);
            USART2_SendString(buffer);
        }
    }
}

// ======================== Programme principal =================

QueueHandle_t xAngleQueue;

int main(void) {
    // Initialisations matérielles
    HAL_Init();                 // si vous utilisez HAL pour le Systick (optionnel)
    SystemClock_Config();       // à adapter (doit fournir 84 MHz)
    I2C1_Init();
    MPU6050_Init();
    USART2_Init(115200);

    // Création de la file
    xAngleQueue = xQueueCreate(ANGLE_QUEUE_SIZE, sizeof(float));

    if (xAngleQueue != NULL) {
        xTaskCreate(vTaskIMUReader, "IMUReader", 256, NULL, 2, NULL);
        xTaskCreate(vTaskUARTTransmitter, "UARTTx", 128, NULL, 1, NULL);
        vTaskStartScheduler();
    }

    while(1);
}
```

**Remarques :**

Le calcul de l’angle à partir de l’accéléromètre dépend de l’orientation du capteur. Ici on suppose que l’axe X est l’axe de roulis.

Les paramètres du filtre (`Q_angle`, `Q_bias`, `R_measure`) sont à ajuster expérimentalement pour obtenir un bon compromis entre réactivité et lissage.

La tâche d’envoi UART lit la file sans attendre (`timeout = 0`) et envoie l’angle s’il est disponible. On pourrait aussi utiliser une file avec `portMAX_DELAY` pour une cadence régulière.

---
<br>



### **Interface Python**

Côté PC, le script Python lit les données série et affiche l’angle sous forme numérique ainsi qu’un graphique en temps réel.

```py
#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import tkinter as tk
from tkinter import ttk
import serial
import threading
import time
import matplotlib.pyplot as plt
from matplotlib.backends.backend_tkagg import FigureCanvasTkAgg
from matplotlib.figure import Figure
import numpy as np

class IMUApp:
    def __init__(self, master):
        self.master = master
        master.title("Filtre de Kalman - MPU6050")
        master.geometry("800x600")
        master.resizable(False, False)

        # Variable pour l'angle courant
        self.current_angle = tk.StringVar(value="0.00")

        # Historique pour le graphique
        self.time_data = []
        self.angle_data = []
        self.max_points = 200  # nombre de points affichés

        # Configuration du port série
        self.serial_port = None
        try:
            self.serial_port = serial.Serial('COM3', 115200, timeout=1)  # à adapter
        except Exception as e:
            self.current_angle.set(f"Erreur: {e}")
            return

        # Création de l'interface
        self.create_widgets()

        self.running = True
        self.thread = threading.Thread(target=self.read_serial, daemon=True)
        self.thread.start()

        # Mise à jour périodique du graphique (toutes les 100 ms)
        self.update_graph()

    def create_widgets(self):
        # Cadre supérieur pour l'affichage numérique
        top_frame = ttk.Frame(self.master)
        top_frame.pack(side=tk.TOP, fill=tk.X, padx=10, pady=10)

        ttk.Label(top_frame, text="Angle estimé (°) :", font=("Arial", 14)).pack(side=tk.LEFT, padx=5)
        ttk.Label(top_frame, textvariable=self.current_angle, font=("Arial", 14, "bold"),
                  foreground="blue").pack(side=tk.LEFT, padx=5)

        # Cadre pour le graphique
        graph_frame = ttk.Frame(self.master)
        graph_frame.pack(side=tk.BOTTOM, fill=tk.BOTH, expand=True, padx=10, pady=10)

        # Création de la figure matplotlib
        self.fig = Figure(figsize=(8, 4), dpi=100)
        self.ax = self.fig.add_subplot(111)
        self.ax.set_title("Évolution de l'angle estimé")
        self.ax.set_xlabel("Temps (s)")
        self.ax.set_ylabel("Angle (°)")
        self.ax.grid(True)

        self.canvas = FigureCanvasTkAgg(self.fig, master=graph_frame)
        self.canvas.get_tk_widget().pack(fill=tk.BOTH, expand=True)

    def read_serial(self):
        """Lit les données série et met à jour l'angle courant."""
        while self.running:
            try:
                line = self.serial_port.readline().decode().strip()
                if line:
                    # On s'attend à un flottant suivi de retour chariot
                    angle = float(line)
                    self.current_angle.set(f"{angle:.2f}")
                    # Ajouter au graphe
                    self.time_data.append(time.time())
                    self.angle_data.append(angle)
                    if len(self.time_data) > self.max_points:
                        self.time_data.pop(0)
                        self.angle_data.pop(0)
            except Exception as e:
                print("Erreur de lecture:", e)
                break

    def update_graph(self):
        """Met à jour le graphique toutes les 100 ms."""
        if self.running:
            self.ax.clear()
            self.ax.set_title("Évolution de l'angle estimé")
            self.ax.set_xlabel("Temps (s)")
            self.ax.set_ylabel("Angle (°)")
            self.ax.grid(True)

            if self.time_data:
                # Convertir les temps en secondes relatives pour l'affichage
                t0 = self.time_data[0]
                t_rel = [t - t0 for t in self.time_data]
                self.ax.plot(t_rel, self.angle_data, 'b-')
                self.ax.set_xlim(max(0, t_rel[-1] - 10), t_rel[-1] + 1)  # affiche les 10 dernières secondes

            self.canvas.draw()
            self.master.after(100, self.update_graph)

    def on_closing(self):
        self.running = False
        if self.serial_port:
            self.serial_port.close()
        self.master.destroy()

if __name__ == "__main__":
    root = tk.Tk()
    app = IMUApp(root)
    root.protocol("WM_DELETE_WINDOW", app.on_closing)
    root.mainloop()
```

**Explication :**

- Le script utilise matplotlib intégré dans Tkinter pour afficher un graphe dynamique.
- Un thread lit les données série en arrière‑plan et met à jour une variable Tkinter ainsi que les listes de points pour le graphique.
- La fonction update_graph est appelée toutes les 100 ms pour redessiner la courbe.


---
<br>

### **Liens connexes**

- [GPIO et Interruptions](../../stm32f4/gpio/index.md)
- [Timer et Interruption](../../stm32f4/timer/index.md)
- [Communication Série USART](../../stm32f4/usart/index.md)
- [Communication Série I2C](../../stm32f4/i2c/index.md)
- [Génération des signaux PWM](../../stm32f4/pwm/index.md)
- [Machine d’État Fini (FSM)](../../technique-algos/fsm/index.md)
- [Estimation d’État et Fusion Capteurs](../technique-algos/estimation/index.md)
- [Introduction pratique à freeRTOS](../../rtos/#introduction-a-freertos)



