# Projet : Générateur de signaux DDS piloté par interface Python

*Ir Paul S. Kabidu, M.Eng. <spaulkabidu@gmail.com>*
{: style="text-align: center;" }

---

[Accueil](../../#Accueil)

<br>
<br>



### **Introduction**

Ce projet a pour objectif de réaliser un **générateur de signaux** basé sur la technique de synthèse numérique directe (DDS) à l’aide d’un **DAC externe MCP4822** connecté à notre carte STM32F401. Le signal généré (sinus, triangle, carré, dent de scie) sera contrôlé en fréquence et en forme via une **interface graphique Python** sur PC. La communication entre le STM32 et le PC se fait par liaison série (UART).

Ce projet illustre l’intégration de plusieurs notions abordées précédemment :

- Synthèse DDS avec DAC externe (SPI)
- Communication UART avec FreeRTOS (files d’attente, tâches)
- Parsing de commandes simples
- Interface homme-machine en Python (Tkinter)

---
<br>


### **Cahier des charges**

- **Génération de signaux** :
  - Formes d’onde : sinus, triangle, carré, dent de scie.
  - Plage de fréquence : par exemple 1 Hz à 10 kHz (selon les limites du DAC et de la fréquence d’échantillonnage).
  - Résolution en fréquence : fine grâce à l’accumulateur 32 bits.

- **Contrôle depuis le PC** :
  - L’utilisateur entre la fréquence souhaitée et choisit la forme d’onde dans une interface Python.
  - Les commandes sont envoyées sur le port série (UART) au STM32.

- **Communication série** :
  - Format de commande simple, par exemple : `SIN 1000` pour un sinus à 1000 Hz, `TRI 500` pour un triangle à 500 Hz, etc.
  - Le STM32 accuse réception ou renvoie un message de confirmation.

- **Affichage sur PC** :
  - L’interface Python affiche la commande en cours et éventuellement un graphique en temps réel (optionnel).

- **Contraintes techniques** :
  - Utilisation de FreeRTOS pour gérer la réception UART et la génération DDS.
  - La tâche DDS est déclenchée par un timer matériel pour une fréquence d’échantillonnage stable (par exemple 100 kHz).
  - La réception UART utilise une file d’attente (queue) pour transmettre les commandes à une tâche de parsing.

---
<br>


### **Matériel nécessaire**

- Carte STM32F401 (Black Pill)
- DAC externe MCP4822 (ou MCP4922) + éventuellement un amplificateur pour adapter la tension de sortie
- Connexions SPI :
  - SCK → PA5
  - MOSI → PA7
  - CS → PA4 (pour sélectionner le MCP4822)
  - (MISO non utilisé)
- Alimentation 3.3V et GND
- Câble USB pour la communication série (via USART2 sur PA2/PA3)

---
<br>


### **Code STM32 (FreeRTOS)**

Le code est organisé en plusieurs parties :

- Initialisation SPI, timer, UART.
- Tables d’onde pré-calculées pour les différentes formes.
- Structure DDS et fonctions de mise à jour.
- Tâche de réception UART (avec file d’attente).
- Tâche de parsing des commandes.
- Tâche de génération DDS déclenchée par timer.

```c
/*
** Projet DDS piloté par PC avec FreeRTOS sur STM32F401
*/

#include "FreeRTOS.h"
#include "task.h"
#include "queue.h"
#include "semphr.h"
#include "stm32f4xx.h"
#include <math.h>
#include <string.h>
#include <stdio.h>

// Définitions 

#define LUT_SIZE 256          // taille de la table d'onde
#define SAMPLE_FREQ 100000    // 100 kHz
#define TIMER_PERIOD (84000000 / SAMPLE_FREQ) // PSC et ARR à configurer

// Commandes UART
#define CMD_BUFFER_SIZE 32

// Tables d'onde 

uint16_t sinLUT[LUT_SIZE];
uint16_t triLUT[LUT_SIZE];
uint16_t sqrLUT[LUT_SIZE];
uint16_t sawLUT[LUT_SIZE];

void generate_wave_tables(void) {
    for (int i = 0; i < LUT_SIZE; i++) {
        // Sinus (centré sur 2048, amplitude 2047)
        float rad = 2 * M_PI * i / LUT_SIZE;
        sinLUT[i] = (uint16_t)(2048 + 2047 * sinf(rad));

        // Triangle
        if (i < LUT_SIZE/2)
            triLUT[i] = (uint16_t)(2048 + 4095 * (i / (float)(LUT_SIZE/2) - 1));
        else
            triLUT[i] = (uint16_t)(2048 + 4095 * (1 - (i - LUT_SIZE/2) / (float)(LUT_SIZE/2)));

        // Carré
        sqrLUT[i] = (i < LUT_SIZE/2) ? 4095 : 0;

        // Dent de scie
        sawLUT[i] = (uint16_t)(i * 4095 / LUT_SIZE);
    }
}

// Structure DDS

typedef struct {
    uint32_t phase;            // accumulateur de phase
    uint32_t phase_increment;  // pas de phase (M)
    uint16_t *lut;             // pointeur vers la table active
} DDS_Generator;

DDS_Generator dds;

void DDS_Init(void) {
    dds.phase = 0;
    dds.phase_increment = 0;
    dds.lut = sinLUT; // par défaut
}

// Calcule le pas de phase pour une fréquence donnée
uint32_t compute_phase_increment(float freq) {
    return (uint32_t)(freq * (1ULL << 32) / SAMPLE_FREQ);
}

// Met à jour l'accumulateur et retourne l'échantillon
uint16_t DDS_Update(void) {
    dds.phase += dds.phase_increment;
    uint8_t index = dds.phase >> 24; // prend les 8 bits de poids fort
    return dds.lut[index];
}

// Change la forme d'onde
void DDS_SetWaveform(char wave) {
    switch (wave) {
        case 'S': dds.lut = sinLUT; break;
        case 'T': dds.lut = triLUT; break;
        case 'Q': dds.lut = sqrLUT; break;
        case 'W': dds.lut = sawLUT; break;
        default: dds.lut = sinLUT;
    }
}

// Change la fréquence
void DDS_SetFrequency(float freq) {
    if (freq < 1.0f) freq = 1.0f;
    if (freq > 10000.0f) freq = 10000.0f;
    dds.phase_increment = compute_phase_increment(freq);
}

// Interface SPI

void SPI1_Init(void) {
    RCC->AHB1ENR |= RCC_AHB1ENR_GPIOAEN;
    RCC->APB2ENR |= RCC_APB2ENR_SPI1EN;

    // PA5 (SCK), PA7 (MOSI) en AF5, PA4 (CS) en sortie GPIO
    GPIOA->MODER &= ~((3U << (5*2)) | (3U << (7*2)) | (3U << (4*2)));
    GPIOA->MODER |=  ((2U << (5*2)) | (2U << (7*2))); // AF pour SPI
    GPIOA->MODER |=  (1U << (4*2));  // PA4 sortie

    GPIOA->AFR[0] &= ~((0xF << (5*4)) | (0xF << (7*4)));
    GPIOA->AFR[0] |=  ((5 << (5*4)) | (5 << (7*4)));

    GPIOA->ODR |= (1 << 4); // CS haut

    // SPI1 : maître, 8 bits, CPOL=0, CPHA=0, fPCLK/8 = 10.5 MHz
    SPI1->CR1 = SPI_CR1_MSTR | SPI_CR1_BR_2 | SPI_CR1_BR_1; // BR = 110 -> /8
    SPI1->CR1 |= SPI_CR1_SSM | SPI_CR1_SSI;
    SPI1->CR1 |= SPI_CR1_SPE;
}

void SPI1_CS_Low(void) {
    GPIOA->ODR &= ~(1 << 4);
}

void SPI1_CS_High(void) {
    GPIOA->ODR |= (1 << 4);
}

void SPI1_Transmit16(uint16_t data) {
    while (!(SPI1->SR & SPI_SR_TXE));
    SPI1->DR = data;
    while (!(SPI1->SR & SPI_SR_RXNE));
    (void)SPI1->DR;
}

// Envoi au MCP4822 (canal A)
void MCP4822_Write(uint16_t value) {
    // value 12 bits (0-4095)
    uint16_t word = 0x6000 | ((value & 0xFFF) << 4); // canal A, GA=1, SHDN=1
    SPI1_CS_Low();
    SPI1_Transmit16(word);
    SPI1_CS_High();
}

// Timer pour DDS

SemaphoreHandle_t xDDS_Semaphore;

void TIM2_IRQHandler(void) {
    BaseType_t xWoken = pdFALSE;
    if (TIM2->SR & TIM_SR_UIF) {
        TIM2->SR &= ~TIM_SR_UIF;
        xSemaphoreGiveFromISR(xDDS_Semaphore, &xWoken);
        portYIELD_FROM_ISR(xWoken);
    }
}

void Timer_Init(void) {
    RCC->APB1ENR |= RCC_APB1ENR_TIM2EN;
    TIM2->PSC = 84 - 1;        // 1 MHz
    TIM2->ARR = 10 - 1;         // 100 kHz
    TIM2->DIER |= TIM_DIER_UIE;
    NVIC_SetPriority(TIM2_IRQn, 5);
    NVIC_EnableIRQ(TIM2_IRQn);
    TIM2->CR1 |= TIM_CR1_CEN;
}

// UART et files 

QueueHandle_t xUART_RxQueue;   // file pour les caractères reçus
QueueHandle_t xCommandQueue;    // file pour les commandes parsées

void USART2_Init(uint32_t baud) {
    RCC->AHB1ENR |= RCC_AHB1ENR_GPIOAEN;
    RCC->APB1ENR |= RCC_APB1ENR_USART2EN;

    GPIOA->MODER &= ~((3U << (2*2)) | (3U << (3*2)));
    GPIOA->MODER |=  ((2U << (2*2)) | (2U << (3*2)));
    GPIOA->AFR[0] |= (7 << (2*4)) | (7 << (3*4));

    USART2->BRR = 84000000 / baud;
    USART2->CR1 = USART_CR1_TE | USART_CR1_RE | USART_CR1_RXNEIE | USART_CR1_UE;
    NVIC_SetPriority(USART2_IRQn, 5);
    NVIC_EnableIRQ(USART2_IRQn);
}

void USART2_SendString(char *str) {
    while (*str) {
        while (!(USART2->SR & USART_SR_TXE));
        USART2->DR = *str++;
    }
}

// Interruption UART (réception)
void USART2_IRQHandler(void) {
    BaseType_t xWoken = pdFALSE;
    if (USART2->SR & USART_SR_RXNE) {
        uint8_t c = USART2->DR;
        xQueueSendFromISR(xUART_RxQueue, &c, &xWoken);
    }
    portYIELD_FROM_ISR(xWoken);
}

// Tâche de parsing des commandes
void vTaskCommandParser(void *pvParameters) {
    char line[CMD_BUFFER_SIZE];
    int idx = 0;
    char cmd[8];
    float freq;

    for (;;) {
        uint8_t c;
        if (xQueueReceive(xUART_RxQueue, &c, portMAX_DELAY) == pdPASS) {
            if (c == '\n' || c == '\r') {
                if (idx > 0) {
                    line[idx] = '\0';
                    // Format attendu : "SIN 1000" ou "TRI 500", etc.
                    if (sscanf(line, "%s %f", cmd, &freq) == 2) {
                        // Interpréter la commande
                        if (strcmp(cmd, "SIN") == 0) {
                            DDS_SetWaveform('S');
                            DDS_SetFrequency(freq);
                            USART2_SendString("OK Sinus\r\n");
                        } else if (strcmp(cmd, "TRI") == 0) {
                            DDS_SetWaveform('T');
                            DDS_SetFrequency(freq);
                            USART2_SendString("OK Triangle\r\n");
                        } else if (strcmp(cmd, "SQR") == 0) {
                            DDS_SetWaveform('Q');
                            DDS_SetFrequency(freq);
                            USART2_SendString("OK Carre\r\n");
                        } else if (strcmp(cmd, "SAW") == 0) {
                            DDS_SetWaveform('W');
                            DDS_SetFrequency(freq);
                            USART2_SendString("OK Dent de scie\r\n");
                        } else {
                            USART2_SendString("Commande inconnue\r\n");
                        }
                    } else {
                        USART2_SendString("Format: FORME FREQ\r\n");
                    }
                    idx = 0;
                }
            } else if (idx < CMD_BUFFER_SIZE - 1) {
                line[idx++] = c;
            }
        }
    }
}

// Tâche DDS (réveillée par le timer)
void vTaskDDS(void *pvParameters) {
    uint16_t sample;
    for (;;) {
        xSemaphoreTake(xDDS_Semaphore, portMAX_DELAY);
        sample = DDS_Update();
        MCP4822_Write(sample);
    }
}

// Programme principal

int main(void) {
    HAL_Init();                 // optionnel si vous utilisez HAL pour le Systick
    SystemClock_Config();       // à adapter (84 MHz)

    generate_wave_tables();
    DDS_Init();
    DDS_SetFrequency(1000.0f); // 1 kHz par défaut

    SPI1_Init();
    Timer_Init();
    USART2_Init(115200);

    xDDS_Semaphore = xSemaphoreCreateBinary();
    xUART_RxQueue = xQueueCreate(64, sizeof(uint8_t));

    xTaskCreate(vTaskCommandParser, "CmdParser", 256, NULL, 2, NULL);
    xTaskCreate(vTaskDDS, "DDS", 128, NULL, 3, NULL);

    vTaskStartScheduler();

    while(1);
}
```

---
<br>



### **Interface Python**

L’interface Python envoie des commandes au STM32 via le port série et affiche les réponses. Elle utilise Tkinter pour la saisie de la fréquence et la sélection de la forme d’onde.


```py
#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import tkinter as tk
from tkinter import ttk
import serial
import threading
import time

class DDSController:
    def __init__(self, master):
        self.master = master
        master.title("Contrôle du générateur DDS")
        master.geometry("400x200")
        master.resizable(False, False)

        # Variables
        self.freq = tk.StringVar(value="1000")
        self.waveform = tk.StringVar(value="SIN")
        self.status = tk.StringVar(value="Prêt")

        # Configuration du port série (à adapter)
        self.ser = None
        try:
            self.ser = serial.Serial('COM3', 115200, timeout=1)
        except Exception as e:
            self.status.set(f"Erreur: {e}")
            return

        # Création des widgets
        tk.Label(master, text="Fréquence (Hz):").grid(row=0, column=0, padx=5, pady=5, sticky="e")
        tk.Entry(master, textvariable=self.freq, width=10).grid(row=0, column=1, padx=5, pady=5)

        tk.Label(master, text="Forme d'onde:").grid(row=1, column=0, padx=5, pady=5, sticky="e")
        wave_combo = ttk.Combobox(master, textvariable=self.waveform,
                                   values=["SIN", "TRI", "SQR", "SAW"], state="readonly")
        wave_combo.grid(row=1, column=1, padx=5, pady=5)

        tk.Button(master, text="Envoyer", command=self.send_command).grid(row=2, column=0, columnspan=2, pady=10)

        tk.Label(master, text="Statut:").grid(row=3, column=0, padx=5, pady=5, sticky="e")
        tk.Label(master, textvariable=self.status, fg="blue").grid(row=3, column=1, padx=5, pady=5, sticky="w")

        # Thread de lecture des réponses
        self.running = True
        self.thread = threading.Thread(target=self.read_serial, daemon=True)
        self.thread.start()

    def send_command(self):
        """Envoie la commande au STM32."""
        if self.ser is None:
            self.status.set("Port série non ouvert")
            return
        freq = self.freq.get()
        wave = self.waveform.get()
        command = f"{wave} {freq}\r\n"
        try:
            self.ser.write(command.encode())
            self.status.set("Commande envoyée")
        except Exception as e:
            self.status.set(f"Erreur envoi: {e}")

    def read_serial(self):
        """Lit les réponses du STM32 et met à jour le statut."""
        while self.running:
            try:
                line = self.ser.readline().decode().strip()
                if line:
                    self.master.after(0, self.update_status, line)
            except:
                pass

    def update_status(self, msg):
        self.status.set(msg)

    def on_closing(self):
        self.running = False
        if self.ser:
            self.ser.close()
        self.master.destroy()

if __name__ == "__main__":
    root = tk.Tk()
    app = DDSController(root)
    root.protocol("WM_DELETE_WINDOW", app.on_closing)
    root.mainloop()
```

---
<br>


### **Liens connexes**


- [GPIO et Interruptions](../../stm32f4/gpio/index.md)
- [Timer et Interruption](../../stm32f4/timer/index.md)
- [Acquisition Analogique via ADC](../../stm32f4/adc/index.md)
- [Communication Série USART](../../stm32f4/usart/index.md)
- [Machine d’État Fini (FSM)](../../technique-algos/fsm/index.md)
- [Optimisation de Transfert des Données avec DMA](../../stm32f4/dma/index.md)
- [Filtres Numériques](../../technique-algos/filtre/index.md)
- [Synthèse Numérique Directe (DDS) avec DAC externe MCP4822](../../technique-algos/dds/index.md)
- [Introduction pratique à freeRTOS](../../rtos/#introduction-a-freertos)

