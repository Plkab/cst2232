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

Dans ce chapitre, nous verrons comment configurer l’ADC en mode polling, avec interruption. Nous intégrerons ensuite ces mécanismes dans un environnement FreeRTOS pour des acquisitions temps réel non bloquantes.

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

```text
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

**Exemple : Mesure la tension d'un capteur branché sur la broche PA0 (ADC1_IN0) avec affichage UART**

La mesure d’une tension analogique appliquée sur l’entrée PA0 est convertit en valeur numérique via le convertisseur analogique-numérique ADC1, son traitement pour obtenir la tension physique en volts, et enfin son affichage sur un terminal série via la communication USART2. Sur le plan matériel, l’expérience repose sur une carte black pill alimentée via USB, un capteur analogique ou potentiomètre connecté à l’entrée PA1, ainsi qu’un terminal série sur PC (tel que `PuTTY` ou `TeraTerm`) configuré en 9600 bauds. Le brochage de la carte STM32 prévoit l’utilisation du port PA1 en mode analogique, associé au canal ADC1_IN1, et les broches PA2/PA3 pour la communication série via USART2 (transmission et réception respectivement). Le signal mesuré est donc une tension comprise entre 0 V et 3.3 V, qui constitue la référence de l’ADC.

Le programme développé débute par l’initialisation de l’horloge HSI, des GPIO nécessaires et de l’ADC1. Le GPIOA est activé via le registre RCC, et la broche PA1 est configurée en mode analogique sans pull-up/down pour permettre une mesure fiable. Le périphérique ADC1 est ensuite activé et calibré, avec un temps d’échantillonnage configuré à 480 cycles ADC afin d’optimiser la stabilité de la conversion. L’entrée utilisée est normalement PA1, correspondant au canal 1 du multiplexeur ADC interne. 

La fonction ADC1_Read lance une conversion unique (mode `SWSTART`), attend la fin de conversion (bit `EOC`) et lit la valeur numérique sur 12 bits (0 à 4095). Cette valeur est ensuite utilisée dans la fonction principale main() pour calculer la tension équivalente en volts par la formule classique : `tension = (adc_value * 3.3) / 4095.0`. Le résultat est ensuite affiché via USART2, à l’aide de fonctions utilitaires personnalisées comme `USART2_PrintFloat` ou `USART2_PrintText`, afin d’envoyer des chaînes de caractères `ASCII` vers le terminal connecté au PC.


```c
#include "stm32f4xx.h"

// Lire la valeur de l'ADC et l'envoyer sur l'USART
uint16_t adc_value;

// Initialisation ADC1
void ADC1_Init(void) {
    // 1. Activation des horloges pour GPIOA, GPIOB et ADC1
    RCC->AHB1ENR |= (1 << 0) | (1 << 1); // GPIOA + GPIOB
    RCC->APB2ENR |= (1 << 8);            // ADC1EN

    // 2. Configuration de l'ADC de base
    ADC1->CR2 = 0;              // Reset de l'ADC avant config
    ADC1->CR2 &= ~(1 << 0);     // Désactiver l'ADC (ADON = 0)
    
    // 3. Temps d'échantillonnage pour tous les canaux : 480 cycles (valeur maximale)
    ADC1->SMPR1 = 0xFFFFFFFF;   // Canaux 10-18 (temps d'échantillonnage de 480 cycles)
    ADC1->SMPR2 = 0xFFFFFFFF;   // Canaux 0-9 (temps d'échantillonnage de 480 cycles)
    
    // 4. Configuration de la séquence de conversion : 1 seule conversion
    ADC1->SQR1 = 0;             // Une seule conversion dans la séquence

    // 5. Activer l'ADC
    ADC1->CR2 |= (1 << 0);      // Activer le convertisseur AD (ADON = 1)
}

// Lire la valeur ADC sur un canal spécifique
uint16_t ADC1_Read(uint8_t channel) {
    // Configuration du GPIO en mode analogique
    if (channel <= 7) {               // PA0-PA7
        GPIOA->MODER |= 3UL << (2 * channel);  // Mode analogique sur PA0 à PA7
    } 
    else if (channel <= 9) {          // PB0-PB1
        GPIOB->MODER |= 3UL << (2 * (channel - 8)); // Mode analogique sur PB0 et PB1
    }
    else {
        return 0; // Canal non supporté
    }

    // Sélectionner le canal dans la séquence de conversion
    ADC1->SQR3 = channel & 0x1F;     // 5 bits pour choisir le canal ADC

    for (volatile int i = 0; i < 1000; i++); // Délai après SQR3

    // Démarrer la conversion (bit SWSTART)
    ADC1->CR2 |= (1 << 30);          // Démarrer la conversion (bit SWSTART)
    
    // Attendre que la conversion soit terminée (EOC = End Of Conversion)
    while (!(ADC1->SR & (1 << 1)));  // Attendre le bit EOC (End Of Conversion)
    
    // Lire la valeur convertie (12 bits)
    return ADC1->DR & 0x0FFF;        // Masquer les 12 bits de données converties
}

void USART2_Init(uint32_t baudrate) {
    // 1. Activer l’horloge de GPIOA et USART2 (PA2 = TX, PA3 = RX)
    RCC->AHB1ENR |= RCC_AHB1ENR_GPIOAEN;
    RCC->APB1ENR |= RCC_APB1ENR_USART2EN;

		// 2. Configurer PA2 (TX) et PA3 (RX) en Alternate Function AF7
    GPIOA->MODER &= ~((3 << (2 * 2)) | (3 << (3 * 2)));	// Clear MODER2 and MODER3
    GPIOA->MODER |=  (2 << (2 * 2)) | (2 << (3 * 2));		// MODER2/3 = 10 (AF)
    GPIOA->AFR[0] |= (7 << (4 * 2)) | (7 << (4 * 3)); // AFRL2/3 = AF7 (USART2)

    // 3. Configurer baudrate : BRR = fclk / baudrate
		USART2->BRR = (84000000/baudrate);

    // 4. Activer le mode Transmit et Receive, puis activer l’USART
    USART2->CR1 |= USART_CR1_TE | USART_CR1_RE | USART_CR1_UE;

		// (Optionnel) attendre la stabilisation
    //while (!(USART2->SR & USART_SR_TC));  // Transmission complete
}

void USART2_PrintChar(char c) {
    while (!(USART2->SR & USART_SR_TXE)); // Attente que le registre soit vide
    USART2->DR = c;
}

void USART2_PrintText(char *str) {
    while (*str) {
        USART2_PrintChar(*str++);
    }
}

void USART2_NewLine(void) { // Fonction pour envoyer un retour à la ligne compatible avec les terminaux
      USART2_PrintChar('\n');		// Saut de ligne (Line Feed)
      USART2_PrintChar('\r');		// Retour chariot (Carriage Return)
}

// Fonction pour envoyer un entier signé sous forme ASCII
void USART2_PrintInt(int32_t val) {
    char buffer[12];  // Assez grand pour -2147483648\0
    int i = 0;

    if (val == 0) {		// Cas particulier du zéro
        USART2_PrintChar('0');
        return;
    }

    if (val < 0) {		// Si négatif, afficher le signe puis inverser
        USART2_PrintChar('-');
        val = -val;
    }

    while (val > 0) {		// Convertir en chiffres ASCII inversés
        buffer[i++] = (val % 10) + '0';
        val /= 10;
    }

    // Afficher les chiffres en ordre inverse
    while (--i >= 0) {
        USART2_PrintChar(buffer[i]);
    }
}

// Envoyer un nombre flottant avec 2 décimales
void USART2_PrintFloat1(float num) {
    int32_t int_part = (int32_t) num;		// Partie entière
    int32_t frac_part = (int32_t)((num - int_part) * 100);  // Partie fractionnaire à 2 chiffres après virgule

    if (num < 0 && int_part == 0) USART2_PrintChar('-');		// Cas -0.x

    USART2_PrintInt(int_part);		// Afficher partie entière
    USART2_PrintChar('.');		// Afficher séparateur décimal
    if (frac_part < 0) frac_part = -frac_part;	// Corriger si négatif
    if (frac_part < 10) USART2_PrintChar('0'); 	// Ajoute 0 devant les valeurs < 10 (ex: 3.04)
    USART2_PrintInt(frac_part);		// Afficher partie fractionnaire
}

void USART2_PrintFloat(float num) {
    if (num < 0) {
        USART2_PrintChar('-');
        num = -num;
    }

    int int_part = (int)num;
    int frac_part = (int)((num - int_part) * 100 + 0.5f);  // Arrondi correct

    USART2_PrintInt(int_part);
    USART2_PrintChar('.');
    if (frac_part < 10) USART2_PrintChar('0'); // Ajoute un zéro devant si nécessaire
    USART2_PrintInt(frac_part);
}

int main(void) {
    // Initialiser l'USART2 pour la communication série
    USART2_Init(9600);

    // Initialiser ADC1 pour lire depuis le canal 1 (PA1)
    ADC1_Init();

    // Afficher un message de démarrage
    USART2_PrintText("Demarrage ADC..."); 
    USART2_NewLine();
   
    uint16_t adc_val;
    float tension;
   
    while (1) {
        // Lire la valeur ADC sur le canal 1 (PA1)
        adc_val = ADC1_Read(1);
	tension = (adc_val * 3.3f) / 4095.0f; // Convertir en tension

        // Préparer et envoyer la chaîne avec la valeur de l'ADC
        USART2_PrintText("Valeur ADC: ");
        USART2_PrintInt(adc_val);
       
	USART2_PrintText("\t | Tension [V] : ");
	USART2_PrintFloat(tension);
	USART2_PrintText(" V");
	USART2_NewLine();

        // Attendre un peu avant de lire à nouveau (exemple simple de délai)
        for (volatile int i = 0; i < 1000000; i++);
    }
}
```

---
<br>



### **Utilisation avec interruption**

L'ADC peut générer une interruption à la fin de chaque conversion. Cela permet au CPU d'effectuer d'autres tâches pendant la conversion et de traiter le résultat dès qu'il est disponible. Lorsque l’ADC termine sa conversion, il génère un signal matériel d’interruption qui déclenche automatiquement une fonction spécifique appelée ISR (Interrupt Service Routine). 

Le processus typique se déroule en plusieurs étapes. Tout d’abord, l’ADC est configuré pour générer une interruption à la fin de chaque conversion en activant le bit `EOCIE` dans le registre CR1 (`ADCx->CR1 |= ADC_CR1_EOCIE`). Ensuite, l’interruption de l’ADC est activée au niveau du NVIC (`NVIC_EnableIRQ(ADC_IRQn)`) afin que le processeur puisse réagir aux événements de l’ADC. La conversion est alors lancée via le registre CR2 (`ADC1->CR2 |= ADC_CR2_SWSTART`). Lorsque la conversion est terminée, l’ADC déclenche automatiquement la routine `ADC_IRQHandler()`. Dans cette ISR, le programme lit la valeur convertie à partir du registre `ADCx->DR`, ce qui permet de récupérer immédiatement la donnée sans bloquer le CPU.

**Configuration avec interruption**

Les étapes sont similaires à la configuration de base, mais on ajoute :

- L'activation de l'interruption de fin de conversion (`EOC`) dans ADC_CR1 (bit `EOCIE`).
- La configuration et l'activation de l'interruption dans le NVIC.

**Exemple : Mesure la température du capteur LM35 branché sur la broche PA1 (ADC1_IN1) avec interruption**

Le capteur LM35 délivre une tension proportionnelle à la température ambiante, à raison de 10 mV par degré Celsius. Le système est conçu de manière à ce que l’ADC génère une interruption à la fin de chaque conversion. La routine d’interruption `ADC_IRQHandler()` lit automatiquement la valeur convertie, calcule la tension correspondante puis la transforme en température. Cette température est ensuite transmise au PC via l’USART2. L’utilisation des interruptions permet ainsi de récupérer les données immédiatement après conversion sans bloquer le processeur, améliorant la réactivité et l’efficacité du système.

La configuration matérielle commence par l’initialisation de l’ADC1, en activant les horloges nécessaires pour GPIOA et ADC1. Le GPIO associé au canal ADC est mis en mode analogique pour garantir une lecture correcte du signal. L’ADC est configuré pour une seule conversion à la fois et le bit EOCIE est activé pour générer une interruption à la fin de la conversion. 

L’USART2 est configuré à 9600 bauds pour permettre l’envoi des mesures vers un PC, avec des fonctions de transmission de caractères, chaînes, entiers et nombres flottants pour un affichage clair et formaté. Dans la boucle principale, le microcontrôleur lance en continu la conversion ADC. Lorsqu’une conversion est terminée, le flag conversion_done est levé et le programme envoie la valeur mesurée sur l’USART. Cette approche montre un flux de données simple mais efficace : acquisition, traitement et communication des mesures, le tout en utilisant les interruptions pour éviter le blocage du CPU. Le programme illustre également comment structurer un code modulaire et facilement extensible à d’autres capteurs analogiques.

```c
#include "stm32f4xx.h" // Inclusion des définitions pour STM32F4

// Variable pour stocker la valeur ADC brute
uint16_t adc_value;
// Variable pour stocker la température calculée (en °C)
volatile float temperature = 0.0;
// Canal ADC sélectionné (0=PA0, 1=PA1, etc.)
volatile uint8_t adc_channel = 0;
// Flag pour indiquer qu’une conversion ADC est terminée
volatile uint8_t conversion_done = 0;

// Initialisation de l’ADC1
void ADC1_Init(void) {
    // Activer l’horloge pour GPIOA et GPIOB (broches analogiques)
    RCC->AHB1ENR |= (1 << 0) | (1 << 1); // GPIOA + GPIOB

    // Activer l’horloge pour ADC1
    RCC->APB2ENR |= (1 << 8); // ADC1

    // Reset de l’ADC : CR2 = 0
    ADC1->CR2 = 0;

    // Désactiver ADC avant configuration
    ADC1->CR2 &= ~(1 << 0); // ADON = 0

    // Temps d’échantillonnage maximum (480 cycles) pour tous les canaux
    ADC1->SMPR1 = 0xFFFFFFFF; // Canaux 10-18
    ADC1->SMPR2 = 0xFFFFFFFF; // Canaux 0-9

    // Séquence de conversion : une seule conversion
    ADC1->SQR1 = 0; // 1 conversion

    // Activer interruption EOC (End Of Conversion)
    ADC1->CR1 |= ADC_CR1_EOCIE;

    // Activer ADC
    ADC1->CR2 |= (1 << 0); // ADON = 1

    // Activer l’interruption ADC dans le NVIC
    NVIC_EnableIRQ(ADC_IRQn);
}

// Sélection du canal ADC à mesurer
void ADC1_Select_Channel(uint8_t channel) {
    // Configurer le GPIO en mode analogique
    if (channel <= 7) { // PA0 à PA7
        GPIOA->MODER &= ~(3UL << (2 * channel)); // Clear bits
        GPIOA->MODER |= 3UL << (2 * channel);    // Mode analogique
    }
    else if (channel <= 9) { // PB0-PB1
        GPIOB->MODER &= ~(3UL << (2 * (channel - 8))); // Clear
        GPIOB->MODER |= 3UL << (2 * (channel - 8));    // Mode analogique
    }
    else {
        return; // Canal invalide
    }

    adc_channel = channel;        // Stocker le canal sélectionné
    ADC1->SQR3 = channel;         // Sélectionner le canal pour la conversion
}

// Lancer une conversion ADC
void ADC1_StartConversion(void) {
    // Démarrer la conversion par logiciel
    ADC1->CR2 |= ADC_CR2_SWSTART;
}

// Initialisation USART2 pour communication série
void USART2_Init(uint32_t baudrate) {
    // Activer horloge GPIOA et USART2
    RCC->AHB1ENR |= RCC_AHB1ENR_GPIOAEN;
    RCC->APB1ENR |= RCC_APB1ENR_USART2EN;

    // Configurer PA2 (TX) et PA3 (RX) en AF7
    GPIOA->MODER &= ~((3 << (2 * 2)) | (3 << (3 * 2))); // Clear MODER2 et MODER3
    GPIOA->MODER |=  (2 << (2 * 2)) | (2 << (3 * 2));   // Mode AF
    GPIOA->AFR[0] |= (7 << (4 * 2)) | (7 << (4 * 3));   // AF7

    // Configurer le baudrate (BRR = fclk / baudrate)
    USART2->BRR = (84000000 / baudrate); 

    // Activer transmission, réception et USART
    USART2->CR1 |= USART_CR1_TE | USART_CR1_RE | USART_CR1_UE;
}

// Envoyer un caractère via USART2
void USART2_PrintChar(char c) {
    while (!(USART2->SR & USART_SR_TXE)); // Attendre registre vide
    USART2->DR = c;                       // Envoyer le caractère
}

// Envoyer une chaîne via USART2
void USART2_PrintText(char *str) {
    while (*str) {
        USART2_PrintChar(*str++);         // Envoyer caractère par caractère
    }
}

// Envoyer un retour à la ligne (LF + CR)
void USART2_NewLine(void) {
    USART2_PrintChar('\n'); // Line Feed
    USART2_PrintChar('\r'); // Carriage Return
}

// Envoyer un entier signé sous forme ASCII
void USART2_PrintInt(int32_t val) {
    char buffer[12]; // Suffisant pour -2147483648\0
    int i = 0;

    if (val == 0) {
        USART2_PrintChar('0');
        return;
    }

    if (val < 0) { // Si négatif
        USART2_PrintChar('-');
        val = -val;
    }

    // Conversion en chiffres ASCII
    while (val > 0) {
        buffer[i++] = (val % 10) + '0';
        val /= 10;
    }

    // Affichage des chiffres dans l’ordre correct
    while (--i >= 0) {
        USART2_PrintChar(buffer[i]);
    }
}

// Envoyer un flottant avec 2 décimales
void USART2_PrintFloat(float num) {
    if (num < 0) { 
        USART2_PrintChar('-');
        num = -num;
    }

    int int_part = (int)num; // Partie entière
    int frac_part = (int)((num - int_part) * 100 + 0.5f); // Partie fractionnaire arrondie

    USART2_PrintInt(int_part);
    USART2_PrintChar('.');
    if (frac_part < 10) USART2_PrintChar('0'); // Ajouter 0 devant si nécessaire
    USART2_PrintInt(frac_part);
}

// Gestionnaire d’interruption ADC
void ADC_IRQHandler(void) {
    if (ADC1->SR & ADC_SR_EOC) { // Fin de conversion
        adc_value = (uint16_t)(ADC1->DR); // Lire la valeur ADC
        // Conversion en tension puis en température (LM35)
        float voltage = (adc_value * 3.3f) / 4095.0f;
        temperature = voltage * 100.0f; // LM35 : 10 mV/°C

        conversion_done = 1; // Flag pour indiquer qu’une nouvelle donnée est prête
    }
}

// Fonction principale
int main(void) {
    USART2_Init(9600);      // Initialiser USART2 à 9600 bauds
    ADC1_Init();            // Initialiser ADC1
    ADC1_Select_Channel(1); // Choisir canal PA1 pour LM35

    USART2_PrintText("Demarrage ADC INT...");
    USART2_NewLine();

    while (1) {
        ADC1_StartConversion(); // Lancer une conversion ADC

        if (conversion_done) { // Si conversion terminée
            USART2_PrintText("Canal ADC Ch");
            USART2_PrintInt(adc_channel); // Afficher canal
            USART2_PrintText(" : ");
            USART2_PrintFloat(temperature); // Afficher température
            USART2_PrintChar('C');
            USART2_NewLine();

            conversion_done = 0; // Réinitialiser flag
        }

        // Petit délai pour éviter l'envoi trop rapide
        for (volatile int i = 0; i < 100000; i++);
    }
}
```

L'ISR doit être courte : elle lit simplement la valeur et la stocke dans une variable globale volatile.

La variable conversion_done peut être utilisée pour synchroniser la tâche principale (polling léger) ou on peut utiliser un sémaphore en environnement RTOS.

---
<br>



### **ADC déclenché par timer**

Pour un échantillonnage périodique précis, on utilise un timer pour lancer automatiquement les conversions. Cela évite la latence due au logiciel et garantit une cadence fixe.

Le timer génère un événement (par exemple une mise à jour ou une comparaison) qui est connecté à l'entrée de déclenchement externe de l'ADC. L'ADC démarre une conversion sur chaque front de ce signal.

**Configuration du timer (TRGO)**

On utilise le signal **TRGO** (Trigger Output) du timer. On configure le timer en mode "master" pour que son événement de mise à jour soit envoyé sur TRGO.

```c
// Configuration du timer pour générer un événement toutes les 1 ms
TIM2->PSC = 8400 - 1;   // 84 MHz / 8400 = 10 kHz
TIM2->ARR = 10 - 1;      // 10 kHz / 10 = 1 kHz (période 1 ms)
TIM2->CR2 |= TIM_CR2_MMS_1; // MMS = 010 : événement de mise à jour sur TRGO
TIM2->CR1 |= TIM_CR1_CEN;   // démarrage timer
```

**Configuration de l'ADC pour le déclenchement externe**

Dans ADC_CR2, on doit :

- Choisir la source du déclencheur via les bits `EXTSEL[3:0]`.
- Activer le déclenchement externe avec `EXTEN[1:0]` (par exemple, front montant).

```c
ADC1->CR2 |= (1 << 28);    // EXTEN = 01 (front montant)
ADC1->CR2 |= (3 << 24);    // EXTSEL = 3 (TIM2_TRGO)
```

Vérification : la valeur exacte de `EXTSEL` pour TIM2_TRGO dépend du microcontrôleur. Consultez le manuel de référence (RM0368) – pour TIM2_TRGO, c'est souvent `0111` (7) ou `0011` (3). L'exemple utilise 3 (bits 24-27 = 0011) ; testez les deux si nécessaire.


**Exemple avec lecture par interruption**

```c
#include "stm32f4xx.h"

volatile uint16_t adc_value;

void ADC_IRQHandler(void) {
    if (ADC1->SR & ADC_SR_EOC) {
        adc_value = ADC1->DR;
    }
}

int main(void) {
    // Horloges
    RCC->AHB1ENR |= RCC_AHB1ENR_GPIOAEN;
    RCC->APB2ENR |= RCC_APB2ENR_ADC1EN;
    RCC->APB1ENR |= RCC_APB1ENR_TIM2EN;

    // PA0 analogique
    GPIOA->MODER |= (3U << (0*2));

    // Timer 2 pour déclenchement (1 ms)
    TIM2->PSC = 8400 - 1;
    TIM2->ARR = 10 - 1;
    TIM2->CR2 |= TIM_CR2_MMS_1; // Update event as TRGO
    TIM2->CR1 |= TIM_CR1_CEN;

    // ADC
    ADC1->CR1 = ADC_CR1_EOCIE;          // interruption
    ADC1->SMPR2 = (7 << 0);
    ADC1->SQR3 = 0;
    ADC1->CR2 = (1 << 28) | (3 << 24) | ADC_CR2_ADON;

    NVIC_EnableIRQ(ADC_IRQn);
    NVIC_SetPriority(ADC_IRQn, 2);

    while (1) {
        // Le CPU peut faire autre chose
        // adc_value est mis à jour automatiquement toutes les 1 ms
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