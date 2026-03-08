# Communication Série USB

*Ir Paul S. Kabidu, M.Eng. <spaulkabidu@gmail.com>*
{: style="text-align: center;" }

---

[Accueil](../../#Accueil)
  
<br>
<br>


### **Introduction à la communication USB**

L'USB (Universal Serial Bus) est devenu le standard de communication le plus répandu pour connecter des périphériques à un ordinateur. Sur les microcontrôleurs STM32F4, l'USB offre des avantages considérables par rapport à l'UART classique :

- **Vitesse élevée** : jusqu'à 12 Mbit/s (Full Speed) voire 480 Mbit/s (High Speed avec PHY externe).
- **Alimentation intégrée** : le périphérique peut être alimenté directement par le bus USB.
- **Plug-and-play** : détection automatique par l'OS, pas de configuration de débit.
- **Multiples classes** : Communication Device Class (CDC) pour la communication série virtuelle, Human Interface Device (HID) pour les souris/claviers, Mass Storage Class (MSC) pour les clés USB, etc.
- **Robustesse** : protocole avec acquittements, CRC, et gestion d'erreurs intégrée.

Le **STM32F401** intègre un contrôleur USB OTG (On-The-Go) Full Speed. Dans ce chapitre, nous apprendrons à :

- Comprendre l'architecture USB (périphérique, hôte, OTG).
- Configurer le contrôleur USB en mode **périphérique CDC** pour créer un port série virtuel (VCP).
- Utiliser la bibliothèque USB de ST (STM32 USB Device Library).
- Intégrer l'USB dans un environnement **FreeRTOS** pour une communication non bloquante.
- Réaliser un projet pratique de terminal interactif (comme avec l'UART) mais via USB.

---
<br>

### **Principe du bus USB**

**Architecture**

Le bus USB utilise une topologie en étoile avec un **hôte** (PC) qui contrôle la communication et des **périphériques** (périphériques). Les communications sont initiées uniquement par l'hôte.

Le STM32F401 peut fonctionner dans trois modes :

- **Périphérique** : connecté à un hôte (PC).
- **Hôte** : contrôle d'autres périphériques (clavier, souris, clé USB).
- **OTG** : peut changer de rôle dynamiquement.

**Terminologie**

- **Endpoint** : point d'entrée/sortie logique sur le périphérique, identifié par une adresse (1-15) et une direction (IN/OUT).
- **Pipe** : connexion logique entre l'hôte et un endpoint.
- **Interface** : regroupement d'endpoints pour une fonction (ex: interface CDC).
- **Configuration** : ensemble d'interfaces actives.

**Types de transfert**

| Type | Caractéristiques | Utilisation |
|------|------------------|-------------|
| **Contrôle** | Fiable, utilisé pour la configuration | Configuration du périphérique |
| **Bulk** | Fiable, pas de garantie de latence | Transfert de données (MSC, CDC) |
| **Interrupt** | Latence garantie, faible volume | Souris, clavier |
| **Isochrone** | Pas de garantie de livraison, temps réel | Audio, vidéo |

---
<br>



### **La classe CDC (Communication Device Class)**

La classe **CDC** permet de faire apparaître notre microcontrôleur comme un **port série virtuel** (Virtual COM Port - VCP) sur l'ordinateur. Aucun pilote spécifique n'est nécessaire sous Windows (utilise usbser.sys) et Linux (cdc_acm).

Pour implémenter un périphérique CDC, il faut configurer :

- **1 endpoint de contrôle** (endpoint 0) obligatoire.
- **1 endpoint de données OUT** (pour la réception de l'hôte).
- **1 endpoint de données IN** (pour l'émission vers l'hôte).
- **1 endpoint de notification** (optionnel, pour les événements série).

---
<br>


### **La bibliothèque USB de ST**

ST fournit une bibliothèque USB complète dans le cadre du STM32CubeF4. Elle est conçue avec une architecture en couches :

Application (User)
│
├── Class Driver (CDC, HID, MSC...)
│
├── Core (USB Device Core)
│
└── HAL (Hardware Abstraction Layer)

Cette bibliothèque gère tous les détails du protocole USB. Pour l'utilisateur, il suffit de :

1. Configurer les endpoints dans un tableau.
2. Implémenter quelques callbacks (réception, déconnexion, etc.).
3. Appeler les fonctions de la classe CDC pour envoyer/recevoir des données.

**Fichiers principaux**

- `usbd_core.c` : noyau USB.
- `usbd_cdc.c` : implémentation de la classe CDC.
- `usbd_cdc_if.c` : interface utilisateur (à personnaliser).
- `usbd_desc.c` : descripteurs USB (VID, PID, chaînes).

---
<br>



### **Configuration d'un projet USB avec STM32CubeMX**

Bien que nous programmions en "bare metal" sans HAL, la génération du code USB est complexe. Nous utiliserons STM32CubeMX pour générer l'initialisation USB, puis nous intégrerons ce code dans notre projet FreeRTOS.

#### **Étapes sous CubeMX**

1. Sélectionner le microcontrôleur STM32F401CCUx.
2. Activer **USB_OTG_FS** en mode **Device_Only**.
3. Dans "Middleware", sélectionner **USB_DEVICE** et choisir la classe **Communication Device Class (Virtual Port Com)**.
4. Configurer l'horloge pour avoir une horloge USB à 48 MHz (ex: PLL avec HSE 8 MHz, diviser par 7, multiplier par 84, puis diviser par 2 pour obtenir 48 MHz).
5. Générer le code (avec ou sans HAL).

**Fichiers générés**

Le code généré contient les fichiers suivants :

USB_DEVICE/
├── App/
│ ├── usb_device.c # Initialisation USB
│ ├── usbd_desc.c # Descripteurs (VID, PID, etc.)
│ └── usbd_cdc_if.c # Interface CDC (callbacks utilisateur)
├── Target/
│ └── usbd_conf.c # Configuration bas niveau (HAL)
└── USB_HOST/ # (non utilisé)

---
<br>



### **Intégration dans un projet bare metal / FreeRTOS**

Pour intégrer le stack USB dans un projet sans HAL complet, nous devons fournir quelques fonctions de base que la bibliothèque attend (gestion du timing, accès aux registres). Voici comment procéder.

**Structure du projet**

Projet/
├── Core/
│ ├── main.c
│ └── FreeRTOSConfig.h
├── USB_DEVICE/
│ ├── usbd_cdc_if.c
│ ├── usbd_desc.c
│ └── usbd_conf.c
└── Drivers/
└── CMSIS/

**Fichier `usbd_conf.c` adapté**

Ce fichier contient les callbacks HAL nécessaires. Version simplifiée :

```c
#include "stm32f4xx.h"
#include "usbd_core.h"

// Gestion du timing (nécessaire pour les timeouts USB)
void HAL_Delay(uint32_t Delay) {
    uint32_t tickstart = HAL_GetTick();
    while ((HAL_GetTick() - tickstart) < Delay);
}

uint32_t HAL_GetTick(void) {
    // Si FreeRTOS est lancé, utiliser osKernelGetTickCount()
    if (xTaskGetSchedulerState() != taskSCHEDULER_NOT_STARTED) {
        return (uint32_t)xTaskGetTickCount();
    }
    // Sinon, compter nous-mêmes (à implémenter avec SysTick)
    static uint32_t tick = 0;
    return tick; // simplifié
}

// Fonctions de gestion des registres USB (fournies par CubeMX)
void HAL_PCD_MspInit(PCD_HandleTypeDef* hpcd) {
    // Activation des horloges, GPIO, NVIC
    // ...
}
```

**Fichier usbd_cdc_if.c - Interface utilisateur**

C'est ici que nous connectons la réception USB avec FreeRTOS.

```c
#include "FreeRTOS.h"
#include "queue.h"
#include "usbd_cdc_if.h"

extern QueueHandle_t xUSB_RxQueue; // File pour les données reçues

// Buffer de réception (fourni par le stack)
static int8_t CDC_Receive_FS(uint8_t* Buf, uint32_t *Len) {
    BaseType_t xWoken = pdFALSE;

    // Envoyer les données dans la file (depuis l'ISR)
    for (uint32_t i = 0; i < *Len; i++) {
        xQueueSendFromISR(xUSB_RxQueue, &Buf[i], &xWoken);
    }
    portYIELD_FROM_ISR(xWoken);

    // Prêt pour une nouvelle réception
    USBD_CDC_ReceivePacket(&hUsbDeviceFS);
    return (USBD_OK);
}

// Fonction d'émission (appelable depuis une tâche)
uint8_t CDC_Transmit_FS(uint8_t* Buf, uint16_t Len) {
    // Cette fonction est bloquante si le buffer est plein
    return USBD_CDC_TransmitPacket(&hUsbDeviceFS, Buf, Len);
}
```

---
<br>



### **Intégration avec FreeRTOS**

L'USB peut maintenant être utilisé comme un périphérique de communication, avec les mêmes patterns que pour l'UART.

**Configuration des files**

```c
QueueHandle_t xUSB_RxQueue;  // File pour les caractères reçus

#define RX_QUEUE_LENGTH 256
#define TX_QUEUE_LENGTH 128

void USB_Init_Queues(void) {
    xUSB_RxQueue = xQueueCreate(RX_QUEUE_LENGTH, sizeof(uint8_t));
}
Tâche de traitement de la réception
c
void vTaskUSBProcessor(void *pvParameters) {
    uint8_t c;
    char line[64];
    int idx = 0;

    for (;;) {
        if (xQueueReceive(xUSB_RxQueue, &c, portMAX_DELAY) == pdPASS) {
            // Afficher en écho
            CDC_Transmit_FS(&c, 1);

            // Fin de ligne ?
            if (c == '\n' || c == '\r') {
                line[idx] = '\0';
                if (idx > 0) {
                    // Traitement de la commande (comme avec l'UART)
                    if (strcmp(line, "help") == 0) {
                        char *helpMsg = "Commandes: help, on, off\r\n";
                        CDC_Transmit_FS((uint8_t*)helpMsg, strlen(helpMsg));
                    } else if (strcmp(line, "on") == 0) {
                        GPIOC->ODR |= (1 << 13);
                        char *msg = "LED ON\r\n";
                        CDC_Transmit_FS((uint8_t*)msg, strlen(msg));
                    } else if (strcmp(line, "off") == 0) {
                        GPIOC->ODR &= ~(1 << 13);
                        char *msg = "LED OFF\r\n";
                        CDC_Transmit_FS((uint8_t*)msg, strlen(msg));
                    }
                }
                idx = 0;
            } else if (idx < 63) {
                line[idx++] = c;
            }
        }
    }
}
```

**Tâche d'émission périodique**

```c
void vTaskPeriodicSend(void *pvParameters) {
    TickType_t xLastWakeTime = xTaskGetTickCount();
    const TickType_t xPeriod = pdMS_TO_TICKS(1000);
    uint32_t counter = 0;
    char buffer[32];

    for (;;) {
        vTaskDelayUntil(&xLastWakeTime, xPeriod);
        sprintf(buffer, "Compteur: %lu\r\n", counter++);
        CDC_Transmit_FS((uint8_t*)buffer, strlen(buffer));
    }
}
```

---
<br>




### **Projet : Terminal interactif USB {#projet-usb-terminal}
Réalisons un système complet qui émule un terminal série via USB, avec les mêmes fonctionnalités que le projet UART mais en utilisant l'USB Virtual COM Port.

**Matériel**

- Carte STM32F401 (Black Pill)
- Câble USB (connecté directement au microcontrôleur via USB OTG FS)
- Fonctionnalités
- Affichage d'un prompt.
- Commandes : `help`, `led on`, `led off`, `adc`.
- Écho des caractères tapés.
- Gestion de l'historique (optionnel).

**Code principal**

```c
#include "FreeRTOS.h"
#include "task.h"
#include "queue.h"
#include "string.h"
#include "stm32f4xx.h"

// Déclarations des fonctions USB (générées par CubeMX)
void MX_USB_DEVICE_Init(void);
uint8_t CDC_Transmit_FS(uint8_t* Buf, uint16_t Len);
extern USBD_HandleTypeDef hUsbDeviceFS;

// Files
QueueHandle_t xUSB_RxQueue;

// Tâches
void vTaskUSBProcessor(void *pvParameters);
void vTaskPeriodicSend(void *pvParameters);

// Fonctions matérielles simplifiées
void LED_Init(void) {
    RCC->AHB1ENR |= RCC_AHB1ENR_GPIOCEN;
    GPIOC->MODER |= (1 << (13*2));
    GPIOC->ODR &= ~(1 << 13);
}

uint16_t ADC_Read(void) {
    // Simulé pour l'exemple
    return 2048;
}

// Programme principal
int main(void) {
    // Initialisations matérielles
    HAL_Init();
    SystemClock_Config(); // à définir (48 MHz pour USB)
    LED_Init();

    // Initialisation USB (générée par CubeMX)
    MX_USB_DEVICE_Init();

    // Création des files
    xUSB_RxQueue = xQueueCreate(256, sizeof(uint8_t));

    if (xUSB_RxQueue != NULL) {
        xTaskCreate(vTaskUSBProcessor, "USBProc", 512, NULL, 2, NULL);
        xTaskCreate(vTaskPeriodicSend, "Periodic", 256, NULL, 1, NULL);
        vTaskStartScheduler();
    }

    while(1);
}

// Implémentation des tâches (voir sections précédentes)
// ...
```

---
<br>


### **Redirection de printf() vers USB**

Comme avec l'UART, nous pouvons rediriger printf() vers l'USB pour faciliter le débogage.

```c
#include <stdio.h>

int _write(int file, char *ptr, int len) {
    CDC_Transmit_FS((uint8_t*)ptr, len);
    return len;
}
```

**Autres classes USB**

Le STM32F4 peut implémenter d'autres classes USB :

|Classe	|Description	|Application typique|
|-------|---------------|-------------------|
|HID	|Human Interface Device	|Souris, clavier, joystick| 
|MSC	|Mass Storage Class |Clé USB, lecteur de cartes| 
|DFU	|Device Firmware Update	|Mise à jour du firmware par USB|
|AUDIO	|Périphérique audio	|Microphone, haut-parleur USB|


---
<br>



### Liens connexe


- [GPIO et Interruptions](../gpio/index.md)
- [Timer et Interruption](../timer/index.md)
- [Machine d’État Fini (FSM)](../../technique-algos/fsm/index.md)
- [Introduction pratique à freeRTOS](../../rtos/#introduction-a-freertos)
