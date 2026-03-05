# Présentation architecturale du Microcontrôleur STM32F4

*Ir Paul S. Kabidu, M.Eng. <spaulkabidu@gmail.com>*
{: style="text-align: center;" }

---

[Accueil](../#Accueil)
  
<br>
<br>

### **Architecture du microcontrôleur**
  
Un **microcontrôleur (MCU)** est un circuit intégré qui rassemble sur une seule puce tous les éléments nécessaires au fonctionnement d'un système autonome :

- Un **processeur (cœur)** pour exécuter les instructions
- De la mémoire (**RAM et Flash/ROM**) pour stocker le code et les données
- Des **périphériques d'entrée-sortie** pour interagir avec le monde extérieur

On parle de **système sur puce (SoC, System-on-Chip)**. Le microcontrôleur est conçu pour contrôler un système spécifique en temps réel, avec un minimum de composants externes.

**Les trois éléments clés** :

- **Mémoire Flash (ROM)** : stocke le code programme (firmware) de manière non volatile. C'est ici que résident votre application et le noyau FreeRTOS.
- **Mémoire SRAM (RAM)** : stocke les variables, la pile et les données temporaires pendant l'exécution. Elle est volatile.
- **Processeur** : lit les instructions en Flash, déplace et traite les données en RAM, et contrôle les périphériques.

Tous ces éléments communiquent via un **bus** (ici un bus 32 bits). Le fonctionnement du microcontrôleur est cadencé par une horloge (clock), comme tout système digital synchrone.

Actuellement, les microcontrôleurs les plus populaires sont basés sur l'architecture **32 bits ARM Cortex-M**, un standard de l'industrie offrant un excellent rapport performance/consommation.


  
---
<br>

### **STM32F401**

Le **STM32F4** est une famille de microcontrôleurs fabriqués par STMicroelectronics. Il intègre un processeur **ARM Cortex-M4 32 bits**, une architecture moderne capable d'effectuer des calculs DSP (Digital Signal Processing) grâce à son unité à virgule flottante (**FPU, Floating Point Unit**). Celle-ci permet de traiter des nombres décimaux (type float en C) en un seul cycle d'horloge, ce qui est essentiel pour les algorithmes de contrôle (PID, Filtres, FFT), elle accélère considérablement ces algorithmes.

Le manuel de référence pour le [STM32F401x](https://www.st.com/resource/en/datasheet/stm32f401re.pdf).

**Caractéristiques principales** :

- **Fréquence** : généralement cadencé à 84 MHz, peut être overclocké via un multiplicateur de fréquence (PLL) jusqu'à 100 MHz. Cette puissance permet de faire tourner un noyau FreeRTOS avec plusieurs tâches concurrentes.
- **Bus** : communication avec les périphériques via une matrice de bus (Bus Matrix) AHB/APB.
- **Mémoire** : le modèle STM32F401CCU6 (celui de la carte Black Pill) dispose de :

    - 256 Ko de mémoire Flash
    - 64 Ko de RAM
 
  
---
<br>

### **Organisation Mémoire**

Le STM32F4 utilise une architecture de type **Harvard** (bus séparés pour les instructions et les données), mais organisée sur une carte mémoire unifiée de 4 Go (adressage 32 bits). Chaque élément (Flash, RAM, périphériques) possède une adresse fixe et unique dans cet espace mémoire. Cela permet au processeur, grâce aux bus séparés, de lire une instruction en Flash tout en accédant simultanément à une donnée en RAM, améliorant ainsi les performances.

Chaque registre de configuration d'un périphérique est accessible via une adresse spécifique. Par exemple :

- GPIOA commence à l'adresse 0x40020000
- USART2 à 0x40004400
- TIM2 à 0x40000000

Le reference manual ([RM0368 pour le F401](https://www.st.com/resource/en/reference_manual/rm0368-stm32f401xbc-and-stm32f401xde-advanced-armbased-32bit-mcus-stmicroelectronics.pdf)) fournit des tableaux détaillés. En programmation bas niveau, on utilise des structures C pour représenter ces registres, comme le font les [CMSIS](https://arm-software.github.io/CMSIS_6/latest/Core/modules.html) (Cortex Microcontroller Software Interface Standard).

Exemple de structure pour GPIO :

```c
typedef struct {
    volatile uint32_t MODER;   // Offset 0x00
    volatile uint32_t OTYPER;  // Offset 0x04
    volatile uint32_t OSPEEDR; // Offset 0x08
    // ...
} GPIO_TypeDef;

#define GPIOA ((GPIO_TypeDef *) 0x40020000)
```

Quand on programme en bas niveau il est conseillé de toujours lire le [Reference Manual](https://www.st.com/resource/en/reference_manual/rm0368-stm32f401xbc-and-stm32f401xde-advanced-armbased-32bit-mcus-stmicroelectronics.pdf) (pas la datasheet) pour les détails des registres. La datasheet donne les caractéristiques électriques, le manuel de référence explique la programmation. Egalement vérifier les enable clocks avant d'accéder à un périphérique. Pour les variables partagées utiliser _volatile_ entre une ISR et le code principal.

---
<br>


### **Gestion des horloges (RCC)**

Le système d'horloge est le cœur battant du microcontrôleur. Il détermine la vitesse d'exécution et la consommation. Le STM32F4 dispose de plusieurs sources d'horloge :

- **HSI (High Speed Internal)** : oscillateur RC interne 16 MHz, moins précis mais toujours disponible.
- **HSE (High Speed External)** : oscillateur à quartz externe de 25 MHz plus précis.
- **PLL (Phase-Locked Loop)** : multiplie la fréquence d'entrée pour atteindre des fréquences élevées (jusqu'à 100 MHz sur le F401).

**Bus principaux** :

- **SYSCLK** : horloge système, alimente le CPU et la mémoire.
- **AHB (Advanced High-performance Bus)** : bus principal vers la mémoire et les périphériques rapides.
- **APB (Advanced Peripheral Bus)** : bus pour les périphériques plus lents (APB1 et APB2), avec des fréquences souvent divisées.

Un bon équilibre entre performance et consommation passe par un choix judicieux des fréquences et l'activation sélective des horloges des périphériques via le registre RCC_AHB1ENR, RCC_APB1ENR, etc. Oublier d'activer l'horloge d'un périphérique est une erreur classique : le périphérique ne répondra pas.

---
<br>

### **Le Gestionnaire d'Interruption NVIC (Nested Vectored Interrupt Controller)**

Le NVIC est le gestionnaire d'interruptions du Cortex-M. Il permet de :

- Activer/désactiver les sources d'interruptions.
- Définir les priorités (de 0 à 15, 0 étant la plus haute).
- Gérer la préemption : une interruption de haute priorité peut interrompre le traitement d'une interruption de basse priorité.

Pour un système temps réel, la gestion des priorités est cruciale. Les interruptions associées à des tâches critiques (arrêt d'urgence, timer de contrôle) doivent avoir une priorité élevée. Les fonctions FreeRTOS comme xSemaphoreGiveFromISR nécessitent que la priorité de l'interruption soit inférieure ou égale à la priorité maximale configurée pour le noyau (généralement configLIBRARY_MAX_SYSCALL_INTERRUPT_PRIORITY).


---
<br>

### **DMA (Direct Memory Access)**

Le DMA permet de transférer des données entre périphériques et mémoire sans intervention du CPU, libérant ainsi le processeur pour d'autres tâches. C'est un outil essentiel pour :

- Acquérir des données ADC à haute fréquence (ex: 1 kHz) sans surcharger le CPU.
- Transmettre des trames UART en arrière-plan.
- Remplir un buffer audio en double buffer (ping-pong).

Le STM32F4 dispose de deux contrôleurs DMA avec plusieurs streams et canaux. Chaque stream peut être configuré avec une priorité, une direction (mémoire → périphérique, périphérique → mémoire, mémoire → mémoire), et des modes circulaires.

Exemple d'utilisation avec ADC :

```c
// Configuration du DMA pour l'ADC1
DMA_Stream0->PAR = (uint32_t)&ADC1->DR;      // Périphérique
DMA_Stream0->M0AR = (uint32_t)adc_buffer;    // Mémoire
DMA_Stream0->NDTR = buffer_size;              // Taille
DMA_Stream0->CR = DMA_SxCR_CHSEL_0 | ... ;    // Configuration
```

---
<br>


### **Présentation de la carte de développement utilisée**

La carte utilisée dans ce cours est la Black Pill (STM32F401CCU6), une carte peu coûteuse ([environ 10$](https://www.faranux.com/product/stm32f401ccu6-stm32f4-black-pill-brd44/)) et très répandue dans le monde de l'embarqué.

Pour programmer et déboguer la carte, nous utiliserons un programmateur ST-LINK/V2 ([environ 6$](https://www.faranux.com/product/st-link-v2-simulator-douwnload-programmer-com41/)). Il communique avec la carte via le protocole SWD (Serial Wire Debug) et permet de flasher le firmware ainsi que de déboguer en direct depuis l'ordinateur.


---
<br>

### Lien connexe

[GPIO et Interruptions](../stm32f4/gpio/index.md)