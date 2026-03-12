# Serveur Web embarqué avec ESP-01 : Instrument de laboratoire spectromètre

*Ir Paul S. Kabidu, M.Eng. <spaulkabidu@gmail.com>*
{: style="text-align: center;" }

---

[Accueil](../../#Accueil)
  
<br>
<br>


### **Introduction**

Réaliser un serveur web minimaliste sur STM32F401 (Black Pill) qui xxxxxx et l'affiche en temps réel sur une page web accessible depuis un navigateur. Le projet utilise un module Wi-Fi ESP-01 pour la connectivité et FreeRTOS pour la gestion multitâche.

---
<br>

### **Cahier des charges**

- Lecture périodique de la valeur capteur
- Serveur HTTP sur le port 80
- Page web avec auto‑rafraîchissement AJAX affichant la valeur capteurs
- Configuration automatique de l'ESP-01 via une machine d'états
- Communication non bloquante grâce à FreeRTOS

---
<br>


### **Matériel nécessaire**

- Carte STM32F401 (Black Pill)
- Module Wi-Fi ESP-01
- Capteurs

- Connexions :

    - Connexions : ESP-01 sur PC10 (TX) et PC11 (RX) (USART3)

---
<br>


### **Code STM32 (FreeRTOS)**

Voici le code complet pour le microcontrôleur. Il utilise deux USART :



```c
/*
 * Projet : Serveur Web embarqué avec STM32F401 et ESP-01
 * Description : Lit une valeur analogique sur PA0 et l'envoie à un client web
 *              via un module ESP-01 en utilisant FreeRTOS.
 * Auteur : [Votre nom]
 * Date : 2025
 */

#include "FreeRTOS.h"
#include "task.h"
#include "queue.h"
#include "stm32f4xx.h"
#include <stdio.h>
#include <string.h>

/* Définitions*/
#define WIFI_UART        USART3              /* USART3 connecté à l'ESP-01 */
#define RX_BUFFER_SIZE   128                 /* Taille du buffer circulaire de réception */
#define ADC_QUEUE_SIZE   10                   /* Taille de la file pour les valeurs ADC */
#define CMD_TIMEOUT_MS   1000                 /* Timeout pour les commandes AT (ms) */

/* Variables globales*/
/* Buffer circulaire pour la réception UART (ISR -> tâche) */
static volatile uint8_t rxBuffer[RX_BUFFER_SIZE];
static volatile uint8_t rxHead = 0;           /* Indice d'écriture */
static volatile uint8_t rxTail = 0;           /* Indice de lecture */

/* Handle de la tâche WiFi pour les notifications */
TaskHandle_t xWifiTaskHandle = NULL;

/* File pour les valeurs ADC (producteur : tâche ADC, consommateur : tâche WiFi) */
QueueHandle_t xAdcQueue = NULL;

/* Prototypes des fonctions */
void USART3_Init(void);
void USART3_SendChar(char c);
void USART3_SendString(const char *s);
void ADC1_Init(void);
uint16_t ADC1_Read(void);
static void vTaskAdcReader(void *pvParameters);
static void vTaskWifiManager(void *pvParameters);
static int getCharFromBuffer(void);
static int getLine(char *line, int maxLen, TickType_t timeout);
static void sendWebPage(uint16_t adcValue);

/* Initialisation USART3 (ESP-01) */
void USART3_Init(void)
{
    /* Activer l'horloge du port C et de USART3 */
    RCC->AHB1ENR |= RCC_AHB1ENR_GPIOCEN;   /* GPIOC clock enable */
    RCC->APB1ENR |= RCC_APB1ENR_USART3EN;  /* USART3 clock enable (sur APB1) */

    /* Configurer PC10 (TX) et PC11 (RX) en mode Alternate Function */
    GPIOC->MODER &= ~( (3 << 20) | (3 << 22) ); /* Effacer les bits de mode */
    GPIOC->MODER |=   (2 << 20) | (2 << 22);    /* 10 = Alternate function */

    /* Sélectionner AF7 pour USART3 (voir tableau des fonctions alternatives) */
    GPIOC->AFR[1] &= ~( (0xF << 8) | (0xF << 12) ); /* Effacer AF pour PC10 (bits 8-11) et PC11 (12-15) */
    GPIOC->AFR[1] |=   (7 << 8) | (7 << 12);         /* AF7 pour USART3 */

    /* Configurer le baudrate à 115200 (avec HSI 16 MHz) */
    /* BRR = 16MHz / 115200 = 138.9 ≈ 139 -> 0x8B */
    USART3->BRR = 0x8B;      /* 115200 bauds @16 MHz */

    /* Activer la transmission, la réception et l'interruption sur réception */
    USART3->CR1 = USART_CR1_TE | USART_CR1_RE | USART_CR1_RXNEIE; /* TX, RX, RXNE interrupt enable */
    USART3->CR1 |= USART_CR1_UE;                                   /* Activer USART3 */

    /* Configurer la priorité de l'interruption et l'activer dans le NVIC */
    NVIC_SetPriority(USART3_IRQn, 5);        /* Priorité 5 (0 = plus haute) */
    NVIC_EnableIRQ(USART3_IRQn);              /* Activer l'interruption USART3 */
}

/* Fonctions d'émission UART */
void USART3_SendChar(char c)
{
    /* Attendre que le buffer de transmission soit vide */
    while (!(USART3->SR & USART_SR_TXE));
    USART3->DR = c;
}

void USART3_SendString(const char *s)
{
    while (*s) {
        USART3_SendChar(*s++);
    }
}

/* Gestionnaire d'interruption USART3 */
void USART3_IRQHandler(void)
{
    BaseType_t xWoken = pdFALSE;

    /* Vérifier si une donnée a été reçue */
    if (USART3->SR & USART_SR_RXNE) {
        uint8_t data = USART3->DR;           /* Lire la donnée (efface le flag) */

        /* Stocker dans le buffer circulaire */
        uint8_t nextHead = (rxHead + 1) % RX_BUFFER_SIZE;
        if (nextHead != rxTail) {             /* Si le buffer n'est pas plein */
            rxBuffer[rxHead] = data;
            rxHead = nextHead;
        }

        /* Notifier la tâche WiFi qu'un caractère est disponible */
        if (xWifiTaskHandle != NULL) {
            vTaskNotifyGiveFromISR(xWifiTaskHandle, &xWoken);
        }
    }
    /* Si une notification a réveillé une tâche de plus haute priorité, demander un changement de contexte */
    portYIELD_FROM_ISR(xWoken);
}

/* Fonctions de réception UART (pour la tâche)*/
/* Lecture non bloquante d'un caractère depuis le buffer circulaire */
static int getCharFromBuffer(void)
{
    if (rxTail == rxHead) return -1;          /* Buffer vide */
    uint8_t c = rxBuffer[rxTail];
    rxTail = (rxTail + 1) % RX_BUFFER_SIZE;
    return c;
}

/* Fonction pour attendre une ligne (jusqu'à '\n') avec timeout */
static int getLine(char *line, int maxLen, TickType_t timeout)
{
    int idx = 0;
    TickType_t start = xTaskGetTickCount();
    while ( (xTaskGetTickCount() - start) < timeout ) {
        int c = getCharFromBuffer();
        if (c >= 0) {
            if (c == '\n') {
                line[idx] = '\0';
                return idx;                     /* Retourne la longueur de la ligne */
            }
            if (idx < maxLen - 1) {
                line[idx++] = c;
            }
        } else {
            vTaskDelay(pdMS_TO_TICKS(10));     /* Attendre un peu */
        }
    }
    return -1;                                   /* Timeout */
}

/* Initialisation ADC1 */
void ADC1_Init(void)
{
    /* Activer l'horloge de l'ADC1 et du GPIOA */
    RCC->APB2ENR |= RCC_APB2ENR_ADC1EN;
    RCC->AHB1ENR |= RCC_AHB1ENR_GPIOAEN;

    /* PA0 en mode analogique */
    GPIOA->MODER |= (3 << 0);                   /* 11 = analogique */

    /* Configuration simple de l'ADC : canal 0, pas de trigger, résolution 12 bits */
    ADC1->SQR3 = 0;                             /* Premier canal de la séquence = canal 0 */
    ADC1->SMPR2 |= (7 << 0);                    /* Temps d'échantillonnage max (480 cycles) */
    ADC1->CR2 |= ADC_CR2_ADON;                   /* Activer l'ADC */
}

uint16_t ADC1_Read(void)
{
    /* Démarrer une conversion */
    ADC1->CR2 |= ADC_CR2_SWSTART;
    /* Attendre la fin de conversion */
    while (!(ADC1->SR & ADC_SR_EOC));
    return (uint16_t)ADC1->DR;                   /* Lire le résultat */
}

/* Génération de la page web */
void sendWebPage(uint16_t adcValue)
{
    char buffer[512];
    char cmd[64];

    /* Construire la page HTML avec auto‑rafraîchissement AJAX */
    snprintf(buffer, sizeof(buffer),
        "HTTP/1.1 200 OK\r\n"
        "Content-Type: text/html\r\n\r\n"
        "<!DOCTYPE html>"
        "<html>"
        "<head>"
        "<title>STM32 ADC Monitor</title>"
        "<script>"
        "function refreshADC(){"
        "  var xhr = new XMLHttpRequest();"
        "  xhr.onreadystatechange=function(){"
        "    if(xhr.readyState==4 && xhr.status==200){"
        "      document.getElementById('adc').innerHTML=xhr.responseText;"
        "    }"
        "  };"
        "  xhr.open('GET','/adc',true);"
        "  xhr.send();"
        "}"
        "setInterval(refreshADC,500);"
        "</script>"
        "</head>"
        "<body>"
        "<h1>STM32 ADC Monitor</h1>"
        "<p>ADC Value: <span id='adc'>%u</span></p>"
        "</body>"
        "</html>", adcValue);

    /* Commande CIPSEND pour envoyer les données via la liaison 0 */
    snprintf(cmd, sizeof(cmd), "AT+CIPSEND=0,%d\r\n", (int)strlen(buffer));
    USART3_SendString(cmd);

    /* Attendre le prompt '>' (timeout 500 ms) */
    vTaskDelay(pdMS_TO_TICKS(100));

    /* Envoyer la page */
    USART3_SendString(buffer);
}

/* Tâche de lecture ADC  */
static void vTaskAdcReader(void *pvParameters)
{
    TickType_t xLastWakeTime = xTaskGetTickCount();
    const TickType_t xPeriod = pdMS_TO_TICKS(100);   /* Période de 100 ms */

    for (;;) {
        vTaskDelayUntil(&xLastWakeTime, xPeriod);    /* Attente périodique précise */

        uint16_t val = ADC1_Read();                    /* Lire l'ADC */
        xQueueSend(xAdcQueue, &val, 0);                 /* Envoyer la valeur dans la file */
    }
}

/* Tâche de gestion du Wi-Fi (machine d'états) */
static void vTaskWifiManager(void *pvParameters)
{
    enum {
        STATE_INIT,           /* Envoi de AT */
        STATE_AT_OK,          /* Attente OK après AT */
        STATE_CWMODE,         /* Configuration du mode */
        STATE_CWJAP,          /* Connexion au réseau */
        STATE_CIPMUX,         /* Activation du multi-connexion */
        STATE_CIPSERVER,      /* Démarrage du serveur */
        STATE_RUN             /* Serveur actif */
    } state = STATE_INIT;

    char line[64];
    int ret;
    uint16_t adcValue = 0;
    uint32_t notif;

    /* Initialisation de l'ESP : on commence par envoyer AT */
    USART3_SendString("AT\r\n");
    state = STATE_AT_OK;
    TickType_t startTime = xTaskGetTickCount();

    for (;;) {
        /* Attendre une notification de l'ISR (caractère reçu) ou timeout */
        notif = ulTaskNotifyTake(pdTRUE, pdMS_TO_TICKS(100));

        /* Traiter les caractères reçus pour construire des lignes */
        while (1) {
            ret = getLine(line, sizeof(line), 0);   /* Non bloquant */
            if (ret < 0) break;                     /* Plus de données */

            /* Analyser la ligne selon l'état courant */
            switch (state) {
                case STATE_AT_OK:
                    if (strstr(line, "OK")) {
                        /* AT réussi, passer à la configuration du mode */
                        USART3_SendString("AT+CWMODE=1\r\n");   /* Mode station */
                        state = STATE_CWMODE;
                    }
                    break;

                case STATE_CWMODE:
                    if (strstr(line, "OK")) {
                        /* Mode configuré, se connecter au Wi-Fi */
                        /* Remplacez "SSID" et "PASSWORD" par vos identifiants */
                        USART3_SendString("AT+CWJAP=\"SSID\",\"PASSWORD\"\r\n");
                        state = STATE_CWJAP;
                    }
                    break;

                case STATE_CWJAP:
                    if (strstr(line, "OK")) {
                        /* Connexion réussie, activer les connexions multiples */
                        USART3_SendString("AT+CIPMUX=1\r\n");
                        state = STATE_CIPMUX;
                    } else if (strstr(line, "FAIL")) {
                        /* Échec, on pourrait réessayer */
                        /* Pour simplifier, on reste dans le même état */
                    }
                    break;

                case STATE_CIPMUX:
                    if (strstr(line, "OK")) {
                        /* Démarrer le serveur TCP sur le port 80 */
                        USART3_SendString("AT+CIPSERVER=1,80\r\n");
                        state = STATE_CIPSERVER;
                    }
                    break;

                case STATE_CIPSERVER:
                    if (strstr(line, "OK")) {
                        state = STATE_RUN;
                    }
                    break;

                case STATE_RUN:
                    /* Ici on pourrait détecter une requête HTTP (+IPD) */
                    if (strstr(line, "+IPD")) {
                        /* Une requête a été reçue, on peut envoyer la page avec la dernière valeur ADC */
                        /* Récupérer la dernière valeur ADC de la file */
                        xQueueReceive(xAdcQueue, &adcValue, 0);
                        sendWebPage(adcValue);
                    }
                    break;

                default:
                    break;
            }
        }

        /* Gestion des timeouts (optionnel) */
        /* Si on n'a pas reçu OK après un certain temps, on pourrait recommencer */
        /* (non implémenté pour simplifier) */
    }
}

/* Fonction principale*/
int main(void)
{
    /* Initialisations matérielles */
    USART3_Init();
    ADC1_Init();

    /* Création de la file pour les valeurs ADC */
    xAdcQueue = xQueueCreate(ADC_QUEUE_SIZE, sizeof(uint16_t));

    if (xAdcQueue == NULL) {
        /* Erreur, on reste dans une boucle infinie */
        while (1);
    }

    /* Création des tâches FreeRTOS */
    xTaskCreate(vTaskAdcReader,      /* Fonction de la tâche */
                "ADC Reader",        /* Nom */
                128,                 /* Taille de pile (mots) */
                NULL,                /* Paramètres */
                2,                   /* Priorité (plus haut = plus prioritaire) */
                NULL);               /* Handle (optionnel) */

    xTaskCreate(vTaskWifiManager,
                "WiFi Manager",
                256,
                NULL,
                1,
                &xWifiTaskHandle);   /* Handle stocké pour notifications */

    /* Lancement de l'ordonnanceur */
    vTaskStartScheduler();

    /* Ne devrait jamais arriver */
    while (1);
}
```

---
<br>



### Liens connexe

- [GPIO et Interruptions](../gpio/index.md)
- [Timer et Interruption](../timer/index.md)
- [Machine d’État Fini (FSM)](../../technique-algos/fsm/index.md)
- [Introduction pratique à freeRTOS](../../rtos/#introduction-a-freertos)