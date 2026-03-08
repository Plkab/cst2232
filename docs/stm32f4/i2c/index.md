# Communication Série I2C

*Ir Paul S. Kabidu, M.Eng. <spaulkabidu@gmail.com>*
{: style="text-align: center;" }

---

[Accueil](../../#Accueil)
  
<br>
<br>


### **Introduction au bus I2C**

Le **bus I2C (Inter-Integrated Circuit)** est un protocole de communication série **synchrone** très répandu pour connecter des périphériques à **faible vitesse** (capteurs, mémoires EEPROM, écrans OLED, etc.) à un microcontrôleur.

Il ne nécessite que **deux fils** :

- **SCL** : ligne d’horloge  
- **SDA** : ligne de données  

Le protocole permet de connecter **plusieurs périphériques esclaves sur le même bus**, chacun possédant une **adresse unique**.

Le **STM32F401** intègre plusieurs interfaces **I2C matérielles**, ce qui facilite la communication avec des capteurs et modules externes.

Dans ce chapitre, nous apprendrons à :

- Comprendre le **protocole I2C** (trames, adressage, conditions START/STOP).
- Configurer l’**I2C en mode maître** pour communiquer avec des périphériques.
- Utiliser les **interruptions** pour une communication **non bloquante**.
- Intégrer l’I2C dans un environnement **FreeRTOS** avec des **files de messages**.
- Réaliser un **projet pratique** de lecture d’un **capteur de température** (type LM75 ou DS1621) et afficher la valeur sur **UART**.

---
<br>



### **Principe du bus I2C**

Le bus I2C est un **bus multi-maître** (plusieurs maîtres possibles), mais dans la plupart des applications embarquées on utilise un **seul maître**.

Les deux lignes du bus (SDA et SCL) sont tirées au **niveau logique** haut par des **résistances de tirage (pull-up)**. Les dispositifs connectés au bus utilisent des sorties **open-drain**, ce qui signifie qu'ils peuvent tirer la **ligne à 0**, mais jamais la forcer à 1. C'est ce qui permet d'éviter les courts-circuits lorsque plusieurs périphériques tentent de communiquer simultanément.

Toutes les communications sont **initiées par le maître**.

**Trame élémentaire I2C**

Une communication I2C se déroule selon une séquence bien définie.

1. **Condition START**

La communication commence lorsque **SDA passe de 1 à 0** alors que **SCL est à 1**. Cela indique aux périphériques qu'une nouvelle transaction commence. Cela indique aux périphériques qu'une **nouvelle transaction** commence.

2. **Envoi de l’adresse**

Le maître envoie 7 bits d'adresse + 1 bit R/W :

- **0** : écriture vers l’esclave  
- **1** : lecture depuis l’esclave  

3. **Bit d’acquittement (ACK)**

Après chaque octet transmis, le récepteur tire la ligne SDA à 0 pour confirmer la bonne réception. Si SDA reste à 1, cela signifie NACK (absence d'acquittement).

4. **Transfert de données**

Les données sont envoyées 8 bits, MSB en premier. Chaque octet est suivi d'un bit ACK.

En **écriture :** Maître → Esclave
En **lecture :** Esclave → Maître

5. **Condition STOP**

La communication se termine lorsque SDA passe de 0 à 1 alors que SCL est à 1. Cela libère le bus pour une autre communication.

---
<br>


### **Registres importants de l’I2C sur STM32F4**

| Registre | Rôle |
|---------|------|
| **I2C_CR1** | Registre de contrôle (activation I2C, génération START/STOP, interruptions) |
| **I2C_CR2** | Configuration de la fréquence du bus et gestion des interruptions |
| **I2C_OAR1** | Adresse propre du microcontrôleur en mode esclave |
| **I2C_DR** | Registre de données (lecture / écriture) |
| **I2C_SR1** | Registre de statut (SB, ADDR, BTF, RxNE, TxE…) |
| **I2C_SR2** | Informations supplémentaires (bus busy, rôle maître/esclave) |
| **I2C_CCR** | Configuration de la vitesse I2C (100 kHz ou 400 kHz) |
| **I2C_TRISE** | Temps de montée du signal sur le bus |

**Vitesses standard du bus I2C**

Les vitesses les plus utilisées sont :

- **Standard mode : 100 kHz**
- **Fast mode : 400 kHz**
- **Fast mode plus : 1 MHz** (selon les périphériques)

Le bus I2C est particulièrement adapté pour :

- les capteurs (température, pression, humidité) ;
- les mémoires EEPROM ;
- les afficheurs (OLED, LCD) ;
- les convertisseurs ADC/DAC ;
- les modules RTC (Real-Time Clock).

---
<br>


### **Configuration simple (mode polling)**

L’exemple suivant configure l’I2C1 en mode maître à 100 kHz sur les broches PB6 (SCL) et PB7 (SDA). On effectue une lecture d’un registre sur un périphérique esclave (par exemple un capteur de température).

```c
#include "stm32f4xx.h"

void I2C1_Init(void) {
    // 1. Activer les horloges GPIOB et I2C1
    RCC->AHB1ENR |= RCC_AHB1ENR_GPIOBEN;
    RCC->APB1ENR |= RCC_APB1ENR_I2C1EN;

    // 2. Configurer PB6 (SCL) et PB7 (SDA) en alternate function AF4
    GPIOB->MODER &= ~((3U << (6*2)) | (3U << (7*2)));
    GPIOB->MODER |=  ((2U << (6*2)) | (2U << (7*2))); // AF
    GPIOB->AFR[0] &= ~((0xF << (6*4)) | (0xF << (7*4)));
    GPIOB->AFR[0] |=  ((4 << (6*4)) | (4 << (7*4)));  // AF4 pour I2C1

    // 3. Réinitialiser et configurer I2C1
    I2C1->CR1 = I2C_CR1_SWRST;  // Reset
    I2C1->CR1 = 0;
    I2C1->CR2 = 16;              // Fréquence APB1 = 16 MHz (à adapter selon votre horloge)
    I2C1->CCR = 80;              // 100 kHz (standard) : CCR = 16 MHz / (2*100 kHz) = 80
    I2C1->TRISE = 17;            // 1000 ns / (1/16 MHz) = 16 + 1 = 17
    I2C1->CR1 |= I2C_CR1_PE;     // Activer le périphérique
}

// Écriture d'un octet dans un registre d'un esclave (sans donnée)
void I2C1_WriteByte(uint8_t slaveAddr, uint8_t reg) {
    // Attendre que le bus soit libre
    while (I2C1->SR2 & I2C_SR2_BUSY);

    // Générer un START
    I2C1->CR1 |= I2C_CR1_START;
    while (!(I2C1->SR1 & I2C_SR1_SB));  // Attendre START généré

    // Envoyer l'adresse de l'esclave en écriture
    I2C1->DR = slaveAddr << 1;  // bit 0 = 0 pour écriture
    while (!(I2C1->SR1 & I2C_SR1_ADDR));  // Attendre adresse reconnue
    (void)I2C1->SR2;  // Lire SR2 pour effacer le flag ADDR

    // Envoyer le registre
    while (!(I2C1->SR1 & I2C_SR1_TXE));
    I2C1->DR = reg;
    while (!(I2C1->SR1 & I2C_SR1_BTF));  // Attendre fin de transmission

    // STOP
    I2C1->CR1 |= I2C_CR1_STOP;
}

// Lecture d'un octet depuis un registre
uint8_t I2C1_ReadByte(uint8_t slaveAddr, uint8_t reg) {
    uint8_t data;

    // Écriture de l'adresse du registre
    I2C1_WriteByte(slaveAddr, reg);  // Cette fonction envoie un STOP à la fin

    // Attendre bus libre
    while (I2C1->SR2 & I2C_SR2_BUSY);

    // START + adresse en lecture
    I2C1->CR1 |= I2C_CR1_START;
    while (!(I2C1->SR1 & I2C_SR1_SB));
    I2C1->DR = (slaveAddr << 1) | 1;  // bit 0 = 1 pour lecture
    while (!(I2C1->SR1 & I2C_SR1_ADDR));
    (void)I2C1->SR2;

    // Réception de la donnée
    I2C1->CR1 &= ~I2C_CR1_ACK;  // Pas d'acquittement (on va lire un seul octet)
    while (!(I2C1->SR1 & I2C_SR1_RXNE));
    data = I2C1->DR;

    // STOP
    I2C1->CR1 |= I2C_CR1_STOP;

    return data;
}
```

Limitation : ces fonctions sont bloquantes et utilisent des boucles d’attente actives. Dans un système temps réel, on préférera les interruptions.

---
<br>



### **Utilisation avec FreeRTOS**

Pour ne pas bloquer les tâches, on peut configurer l'I2C en mode interruption. L'idée est de lancer une transaction (START + adresse + données) et de laisser l'I2C générer des interruptions à chaque étape. Une machine d'états simple dans l'ISR gère la progression de la transaction et réveille une tâche à la fin via un sémaphore.

Exemple simplifié : lecture d’un registre avec interruptions.

```c
#include "FreeRTOS.h"
#include "task.h"
#include "semphr.h"

SemaphoreHandle_t xI2CSemaphore;

// États de la machine I2C
typedef enum {
    I2C_IDLE,
    I2C_START,
    I2C_ADDR,
    I2C_REG,
    I2C_RESTART,
    I2C_DATA,
    I2C_STOP
} I2C_State_t;

volatile I2C_State_t i2cState = I2C_IDLE;
volatile uint8_t i2cSlaveAddr, i2cReg, i2cData;
volatile uint8_t i2cError;

void I2C1_EV_IRQHandler(void) {
    BaseType_t xWoken = pdFALSE;
    uint32_t sr1 = I2C1->SR1;

    // Gestion des événements selon l'état
    switch (i2cState) {
        case I2C_START:
            if (sr1 & I2C_SR1_SB) {
                // Envoyer adresse
                I2C1->DR = i2cSlaveAddr << 1;
                i2cState = I2C_ADDR;
            }
            break;

        case I2C_ADDR:
            if (sr1 & I2C_SR1_ADDR) {
                (void)I2C1->SR2;  // Clear ADDR
                if (i2cSlaveAddr & 1) {
                    // Lecture : passer directement à la réception de données
                    i2cState = I2C_DATA;
                } else {
                    // Écriture : envoyer le registre
                    I2C1->DR = i2cReg;
                    i2cState = I2C_REG;
                }
            }
            break;

        case I2C_REG:
            if (sr1 & I2C_SR1_TXE) {
                // Registre envoyé, on peut soit STOP soit RESTART pour lecture
                i2cState = I2C_RESTART;
            }
            break;

        case I2C_RESTART:
            // Générer un RESTART
            I2C1->CR1 |= I2C_CR1_START;
            i2cState = I2C_START;
            i2cSlaveAddr |= 1;  // Adresse en lecture
            break;

        case I2C_DATA:
            if (sr1 & I2C_SR1_RXNE) {
                i2cData = I2C1->DR;
                i2cState = I2C_STOP;
                I2C1->CR1 |= I2C_CR1_STOP;
                // Réveiller la tâche
                xSemaphoreGiveFromISR(xI2CSemaphore, &xWoken);
            }
            break;

        default:
            break;
    }

    portYIELD_FROM_ISR(xWoken);
}

void I2C1_ER_IRQHandler(void) {
    // Gestion des erreurs
    i2cError = I2C1->SR1;
    // Réveiller la tâche pour signaler l'erreur
    xSemaphoreGiveFromISR(xI2CSemaphore, NULL);
}

// Fonction de lecture asynchrone
uint8_t I2C1_ReadRegister(uint8_t slaveAddr, uint8_t reg) {
    i2cSlaveAddr = slaveAddr;
    i2cReg = reg;
    i2cError = 0;
    i2cState = I2C_START;

    // Générer un START (l'ISR prendra la suite)
    I2C1->CR1 |= I2C_CR1_START | I2C_CR1_ACK;

    // Attendre le sémaphore (timeout de 100 ms)
    if (xSemaphoreTake(xI2CSemaphore, pdMS_TO_TICKS(100)) == pdTRUE) {
        if (i2cError) {
            // Gérer erreur
            return 0;
        }
        return i2cData;
    } else {
        // Timeout
        return 0;
    }
}
```

Remarque : Ce code est une illustration simplifiée. En pratique, il faut gérer correctement tous les flags, les timeouts, et la configuration des interruptions (priorité, activation).



### **Lecture d’un capteur LM75 avec FreeRTOS**

Le LM75 est un capteur de température numérique avec interface I2C. Son adresse par défaut est `0x48` (7 bits). Le registre de température (`0x00`) fournit la température en degrés Celsius (format 9 bits, 0,5°C par LSB).

**Montage**

- SDA → PB7, SCL → PB6 (avec résistances pull-up de 4,7 kΩ)
- VCC → 3,3 V, GND → masse

**Exemple de tâche FreeRTOS lecture température**

```c
#include "FreeRTOS.h"
#include "task.h"
#include "semphr.h"
#include "stm32f4xx.h"
#include <stdio.h>

// Déclarations des fonctions I2C et UART
uint8_t I2C1_ReadRegister(uint8_t slaveAddr, uint8_t reg);
void USART2_SendString(char *str);
SemaphoreHandle_t xI2CSemaphore;

// Tâche de lecture de température
void vTaskTempSensor(void *pvParameters) {
    uint8_t raw;
    float temp;

    for (;;) {
        raw = I2C1_ReadRegister(0x48, 0x00);  // Lecture du registre température
        temp = raw * 0.5f;                     // Conversion (1 LSB = 0,5 °C)

        char buffer[32];
        sprintf(buffer, "Température : %.1f °C\r\n", temp);
        USART2_SendString(buffer);

        vTaskDelay(pdMS_TO_TICKS(1000));
    }
}

int main(void) {
    // Initialisations
    I2C1_Init();           // Initialisation I2C (mode polling ou interruptions)
    USART2_Init(115200);   // Initialisation USART2 pour affichage

    // Création du sémaphore si on utilise les interruptions
    xI2CSemaphore = xSemaphoreCreateBinary();

    if (xI2CSemaphore != NULL) {
        xTaskCreate(vTaskTempSensor, "Temp", 256, NULL, 2, NULL);
        vTaskStartScheduler();
    }

    while(1);
}
```

**Remarque** : Pour simplifier, on peut utiliser la version polling de `I2C1_ReadRegister` si la tâche n’a pas d’autres contraintes temps réel critiques.


**Utilisation de l’I2C avec FreeRTOS et mutex**
  

Pour un accès sécurisé à l'I2C depuis plusieurs tâches, il est impératif de protéger les transactions avec un mutex. Cela évite qu'une tâche n'interrompe une transaction I2C commencée par une autre.

```c
SemaphoreHandle_t xI2CMutex;

void vTaskTempSensor(void *pvParameters) {
    uint8_t raw;
    float temp;

    for (;;) {
        if (xSemaphoreTake(xI2CMutex, portMAX_DELAY) == pdTRUE) {
            raw = I2C1_ReadRegister(0x48, 0x00);
            xSemaphoreGive(xI2CMutex);
        }
        temp = raw * 0.5f;
        printf("Temp: %.1f\n", temp);
        vTaskDelay(pdMS_TO_TICKS(1000));
    }
}
```

Cette approche garantit que le bus I2C est utilisé par une seule tâche à la fois et évite les conflits sur le bus partagé.

---
<br>



### Liens connexe


- [GPIO et Interruptions](../gpio/index.md)
- [Timer et Interruption](../timer/index.md)
- [Machine d’État Fini (FSM)](../../technique-algos/fsm/index.md)
- [Introduction pratique à freeRTOS](../../rtos/#introduction-a-freertos)