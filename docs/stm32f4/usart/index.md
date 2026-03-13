# Communication Série USART

*Ir Paul S. Kabidu, M.Eng. <spaulkabidu@gmail.com>*
{: style="text-align: center;" }

---

[Accueil](../../#Accueil)
  
<br>
<br>


### **Introduction à la communication série**

La communication série asynchrone (UART/USART) est l’un des moyens les plus simples et les plus répandus pour faire dialoguer un microcontrôleur avec un PC, un autre microcontrôleur, ou des périphériques (GPS, modules Bluetooth, etc.). Elle ne nécessite que deux fils (TX et RX) et une masse commune.

Le STM32F4 intègre plusieurs **USART** (Universal Synchronous/Asynchronous Receiver Transmitter) capables de fonctionner en mode asynchrone (UART) ou synchrone. Dans ce chapitre, nous nous concentrerons sur le mode asynchrone, le plus utilisé. Nous utiliserons l'`USART2` qui, sur la carte Black Pill, est connecté aux broches `PA2 (TX)` et `PA3 (RX)` et également relié au programmateur ST‑Link, ce qui permet une communication directe avec le PC via le port USB sans matériel supplémentaire.

Les objectifs de ce chapitre sont :

- Comprendre le principe de la communication série (start bit, data bits, stop bit, baud rate).
- Configurer l’USART en mode polling (simple mais bloquant).
- Passer à un mode plus efficace : les interruptions.
- Intégrer l’USART dans un environnement FreeRTOS en utilisant des files de messages (queues) pour découpler réception et traitement.
- Réaliser un projet pratique d’échange de données avec un PC.

---
<br>



### **Principe de l’UART**

Une trame UART typique se compose de :

- Un bit de start (toujours à 0)
- 5 à 9 bits de données (souvent 8)
- Un bit de parité optionnel
- 1 ou 2 bits de stop (toujours à 1)

Le débit est défini par le **baud rate** (ex: 9600, 115200 bauds). Les deux extrémités doivent être configurées exactement de la même manière.

**Le module USART du STM32F401**

Le STM32F401 dispose de plusieurs USART. Nous utilisons USART2 car il est accessible via les broches PA2 (TX) et PA3 (RX) et connecté au ST‑Link, ce qui simplifie la communication avec le PC.

Chaque USART est contrôlé par un ensemble de registres. Sur le STM32F4, l’USART est configuré via des registres :

- `USART_BRR` : définit le baud rate à partir de l’horloge du périphérique.
- `USART_CR1` : active la transmission, la réception, les interruptions, etc.
- `USART_SR` : indique l’état (TXE – registre de transmission vide, RXNE – donnée reçue disponible, etc.).
- `USART_DR` : registre de données (lecture/écriture).

---
<br>



### **Génération du baud rate**

Le débit est déterminé par la valeur chargée dans le registre **USART_BRR**. La formule dépend du mode d’oversampling (surchantillonnage) choisi.

**Oversampling par 16 (OVER8 = 0 dans CR1)**

C’est le mode par défaut et le plus courant : baud = fCK / (16 × USARTDIV)
où **USARTDIV** est un nombre en virgule fixe codé dans **BRR** :

- Les **bits 15-4** contiennent la **partie entière** (mantisse).
- Les **bits 3-0** contiennent la **partie fractionnaire** (4 bits, chaque unité vaut 1/16).

**Oversampling par 8 (OVER8 = 1)**

baud = fCK / (8 × USARTDIV)

La partie fractionnaire n’utilise alors que **3 bits (bits 2-0)**.
Dans ce chapitre, nous utiliserons **l’oversampling par 16**.


La fréquence **fCK** est l’horloge fournie à l’USART. Pour **USART2**, elle provient du **bus APB1**.

Sur la **Black Pill**, nous configurons généralement le système pour fonctionner à **84 MHz**, et **APB1 est souvent à 42 MHz** (car divisé par 2). Cependant, si l’on souhaite utiliser **APB1 à 84 MHz**, il faut modifier le **prescaler dans RCC_CFGR**.

Pour simplifier, nous prendrons comme hypothèse que **l’horloge APB1 est à 84 MHz**.

Si vous utilisez la configuration par défaut de la **Black Pill (84 MHz, APB1 = 42 MHz)**, il faudra adapter les calculs.

Exemple : calcul de BRR pour 115200 bauds

Avec :
fCK = 84 000 000 Hz
oversampling = 16
USARTDIV = 84 000 000 / (16 × 115 200)
USARTDIV ≈ 45,5729

- **Partie entière** : 45 → `0x02D`
- **Partie fractionnaire** : `0,5729 × 16 ≈ 9,166 → 9 → 0x9`

Donc : BRR = 0x02D9 (soit `0x2D9`).

Exemple : calcul pour 9600 bauds

USARTDIV = 84 000 000 / (16 × 9 600)
USARTDIV ≈ 546,875

- **Partie entière** : 546 → `0x222`
- **Partie fractionnaire** : `0,875 × 16 = 14 → 0xE`

Donc : BRR = 0x222E

On peut utiliser ces **valeurs directement dans le code** pour configurer le registre **USART_BRR**.

---
<br>



### **Configuration simple (mode polling)**

**Initialisation de l’USART2 sur PA2 (TX) et PA3 (RX)**

```c
#include "stm32f4xx.h"

void USART2_Init(uint32_t baud) {
    // 1. Activer les horloges GPIOA et USART2
    RCC->AHB1ENR |= RCC_AHB1ENR_GPIOAEN;
    RCC->APB1ENR |= RCC_APB1ENR_USART2EN;

    // 2. Configurer PA2 et PA3 en alternate function AF7
    GPIOA->MODER &= ~((3U << (2*2)) | (3U << (3*2)));
    GPIOA->MODER |=  ((2U << (2*2)) | (2U << (3*2))); // 10 = Alternate function
    GPIOA->AFR[0] |= (7 << (2*4)) | (7 << (3*4));     // AF7 pour USART2

    // 3. Configurer l'USART : 8 bits, 1 stop, pas de parité, 115200 bauds
    USART2->BRR = 84000000 / baud;  // Horloge APB1 = 84 MHz    // 0x02D9;      // 45,57 → 45*16 + 9 = 0x2D9
    USART2->CR1 = USART_CR1_TE | USART_CR1_RE; // Activer TX et RX
    USART2->CR2 = 0;                  // 1 stop bit par défaut
    USART2->CR3 = 0;
    USART2->CR1 |= USART_CR1_UE;       // Activer l'USART
}

// Émission d'un caractère (polling)
/*On utilise le flag TXE (Transmit data register empty) du registre SR. Quand ce bit est à 1, le buffer de transmission est vide et on peut écrire un nouveau caractère dans DR.
*/
void USART2_PrintChar(char c) {
    while (!(USART2->SR & USART_SR_TXE)); // Attente que le registre soit vide
    USART2->DR = c;
}

// Émission d'une chaîne
void USART2_PrintText(char *str) {
    while (*str) {
        USART2_PrintChar(*str++);
    }
}

// Réception d'un caractère (polling, bloquant)
/* Le flag RXNE (Read data register not empty) indique qu’un caractère a été reçu et est disponible dans DR. On attend qu’il soit à 1, puis on lit.
*/
char USART2_ReadChar(void) {
    while (!(USART2->SR & USART_SR_RXNE)); // Attente d’un caractère reçu
    return USART2->DR;
}

```
Limitation : les fonctions d’émission/réception en polling bloquent le CPU jusqu’à ce que l’opération soit terminée. Dans un système temps réel, cela peut être problématique.


**Exemple complet : écho**

Ce programme attend un caractère, le renvoie immédiatement (écho) et le fait clignoter sur la LED selon son code ASCII.

```c
#include "stm32f4xx.h"

void USART2_Init(uint32_t baud);
void USART2_PrintChar(char c);
char USART2_ReadChar();  
void delay_ms(int);

int main(void) {
    USART2_Init(115200);

    // Configuration de PC13 en sortie (LED)
    RCC->AHB1ENR |= RCC_AHB1ENR_GPIOCEN;
    GPIOC->MODER |= (1 << (13*2));
    GPIOC->ODR &= ~(1 << 13); // éteinte

    while (1) {
        char ch = USART2_ReadChar();  
        USART2_PrintChar(ch);  // écho

        // Faire clignoter la LED selon la valeur reçue
        for (int i = 0; i < ch; i++) {
            GPIOC->ODR ^= (1 << 13);
            delay_ms(100);
        }
    }
}

void USART2_Init(uint32_t baud) {
    // 1. Activer les horloges GPIOA et USART2
    RCC->AHB1ENR |= RCC_AHB1ENR_GPIOAEN;
    RCC->APB1ENR |= RCC_APB1ENR_USART2EN;

    // 2. Configurer PA2 et PA3 en alternate function AF7
    GPIOA->MODER &= ~((3U << (2*2)) | (3U << (3*2)));
    GPIOA->MODER |=  ((2U << (2*2)) | (2U << (3*2))); // 10 = Alternate function
    GPIOA->AFR[0] |= (7 << (2*4)) | (7 << (3*4));     // AF7 pour USART2

    // 3. Configurer l'USART : 8 bits, 1 stop, pas de parité, 115200 bauds
    USART2->BRR = 84000000 / baud;  // Horloge APB1 = 84 MHz    // 0x02D9;      // 45,57 → 45*16 + 9 = 0x2D9
    USART2->CR1 = USART_CR1_TE | USART_CR1_RE; // Activer TX et RX
    USART2->CR2 = 0;                  // 1 stop bit par défaut
    USART2->CR3 = 0;
    USART2->CR1 |= USART_CR1_UE;       // Activer l'USART
}

void USART2_PrintChar(char c) {
    while (!(USART2->SR & USART_SR_TXE));
    USART2->DR = c;
}

char USART2_ReadChar(void) {
    while (!(USART2->SR & USART_SR_RXNE));
    return USART2->DR;
}

void delay_ms(int n) {
    for (int i = 0; i < n * 4000; i++) {}  // approximation
}
```

---
<br>



### **Fonctions utiles pour usage de USART**

Le but de cet exemple est de fournir une interface de communication série complète entre le microcontrôleur STM32F4 et un PC via UART (ici USART2). Ces fonctions vous permettront d’envoyer toute donnée utile dans vos applications embarquées, que ce soit pour afficher des mesures, transmettre des données, la trame de communication, ou pour tout échange texte-humain/texte-machine ou interagir avec un utilisateur via un terminal.

- `USART2_WriteChar(char c)` : Envoie un caractère `ASCII` à travers l’USART. La fonction attend que le buffer de transmission soit vide avant d’écrire le caractère dans `USART2->DR`. C’est la base de toutes les fonctions plus complexes.
- `USART2_WriteString(const char* str)` : Parcourt une chaîne terminée par `\0` (standard C) et envoie chaque caractère un à un. Elle permet d’afficher des messages lisibles directement sur un terminal série.
- `USART2_NewLine()` : Les terminaux série attendent généralement un retour à la ligne (`\n`) suivi d’un retour chariot (`\r`) pour sauter à la ligne suivante et revenir au début. Cette fonction encapsule cette convention.
- `USART2_WriteInt(int32_t val)` : Affiche un entier signé sous forme de texte. Elle convertit manuellement chaque chiffre de la base 10 (division / modulo) en caractère ASCII. La gestion du signe négatif est incluse.
- `USART2_WriteFloat(float num)` : Affiche un nombre flottant avec 2 chiffres après la virgule. Le nombre est séparé en partie entière et partie décimale, puis traité comme deux entiers. Elle est utile pour afficher des mesures physiques (tension, température, etc.).
 

```c
#include "stm32f4xx.h"

void USART2_Init(uint32_t baudrate) {
    // 1. Activer l’horloge de GPIOA et USART2 (PA2 = TX, PA3 = RX)
    RCC->AHB1ENR |= RCC_AHB1ENR_GPIOAEN;
    RCC->APB1ENR |= RCC_APB1ENR_USART2EN;

		// 2. Configurer PA2 (TX) et PA3 (RX) en Alternate Function AF7
    GPIOA->MODER &= ~((3 << (2 * 2)) | (3 << (3 * 2)));// Clear MODER2 and MODER3
    GPIOA->MODER |=  (2 << (2 * 2)) | (2 << (3 * 2));	// MODER2/3 = 10 (AF)
    GPIOA->AFR[0] |= (7 << (4 * 2)) | (7 << (4 * 3));// AFRL2/3 = AF7 (USART2)

    // 3. Configurer baudrate : BRR = fclk / baudrate
    // fclk = 84 MHz, baudrate = 9600 -> BRR = 8750 (0x)
		USART2->BRR = (84000000/baudrate);

    // 4. Activer le mode Transmit et Receive, puis activer l’USART
    USART2->CR1 |= USART_CR1_TE | USART_CR1_RE | USART_CR1_UE;

		// (Optionnel) attendre la stabilisation
    //while (!(USART2->SR & USART_SR_TC));  // Transmission complete
}

// Envoyer un caractère
void USART2_PrintChar(char c) {
    while (!(USART2->SR & USART_SR_TXE)); // Attente que le registre soit vide
    USART2->DR = c;
}
// Lecture d'un caractere
char USART2_ReadChar(void) {
    while (!(USART2->SR & USART_SR_RXNE)); // Attente d’un caractère reçu
    return USART2->DR;	// Charger le caractère dans le registre de données
}

// Envoyer une chaîne de caractères 
void USART2_PrintText(char *str) {
    while (*str) {	// Parcourir la chaîne jusqu’à '\0'
        USART2_PrintChar(*str++);		// Envoyer caractère par caractère
    }
}

// Fonction pour envoyer un retour à la ligne compatible avec les terminaux
void USART2_NewLine(void) {
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
void USART2_PrintFloat(float num) {
    int32_t int_part = (int32_t) num;		// Partie entière
    int32_t frac_part = (int32_t)((num - int_part) * 100);  // Partie fractionnaire à 2 chiffres après virgule

    if (num < 0 && int_part == 0) USART2_PrintChar('-');		// Cas -0.x

    USART2_PrintInt(int_part);		// Afficher partie entière
    USART2_PrintChar('.');		// Afficher séparateur décimal
    if (frac_part < 0) frac_part = -frac_part;	// Corriger si négatif
    if (frac_part < 10) USART2_PrintChar('0'); 	// Ajoute 0 devant les valeurs < 10 (ex: 3.04)
    USART2_PrintInt(frac_part);		// Afficher partie fractionnaire
}

int main(void) {
    USART2_Init(9600);
	
USART2_PrintText("Hello USART!");
    USART2_NewLine();

    USART2_PrintText("Caractere: ");
    USART2_PrintChar('A');
    USART2_NewLine();

    USART2_PrintText("Entier: ");
    USART2_PrintInt(-12345);
    USART2_NewLine();

    USART2_PrintText("Flottant: ");
    USART2_PrintFloat(-3.1416f);
    USART2_NewLine();
	
    while (1) {
     
}
}
```

---
<br>




### **Redirection de printf() vers l’UART**

Pour faciliter le débogage, on peut rediriger `printf()` vers l’USART. Sous Keil, il suffit de réimplémenter la fonction `fputc()` (ou `_write` selon la bibliothèque). En général, on utilise `fputc()` pour la console.

```c
#include <stdio.h>

int fputc(int ch, FILE *f) {
    USART2_PrintChar(ch);
    return ch;
}
```

oubien

```c
#include <stdio.h>

int _write(int file, char *ptr, int len) {
    for (int i = 0; i < len; i++) {
        USART2_PrintChar(ptr[i]);
    }
    return len;
}
```

Ainsi, un simple `printf("Valeur : %d\r\n", maVariable);` enverra la chaîne formatée sur le port série.

Attention : pour que cela fonctionne, il faut inclure stdio.h et s’assurer que la bibliothèque standard est utilisée.


L’exemple fourni montre une boucle principale où chaque caractère reçu est immédiatement renvoyé au PC, réalisant un test d’écho. L’intégration d’un traitement particulier pour le retour chariot (`\r`) permet de gérer correctement les nouvelles lignes dans l’affichage du terminal. Cette approche démontre l’intérêt pratique de la redirection des flux standards, elle facilite à la fois le débogage (affichage d’états internes du programme via printf) et l’interaction utilisateur (saisie de commandes, menus textuels). En outre, elle illustre comment un concept fondamental de la programmation en C de la gestion des flux peut être adapté au contexte embarqué, ouvrant la voie à des systèmes plus complexes tels que des interfaces console interactives ou des protocoles de communication textuels.

```c
#include "stm32f4xx.h"   
#include <stdio.h>       // Pour utiliser printf, fputc, fgetc
#include <stdint.h>      // Pour les types entiers standardisés (uint8_t, uint16_t, etc.)

// Prototypes des fonctions
void USART2_Init(uint32_t baudrate);         // Initialisation de l'USART2
void USART2_PrintChar(char data);    // Envoi d'un caractère via USART2
char USART2_ReadChar(void);      // Réception d'un caractère via USART2
int fputc(int ch, FILE *f);     // Redirection de fputc vers USART2
int fgetc(FILE *f);             // Redirection de fgetc vers USART2

// Déclaration des flux standard
FILE __stdout;  // Flux de sortie standard (stdout)
FILE __stdin;   // Flux d'entrée standard (stdin)

int main(void) {
    // Initialisation du périphérique USART2
    USART2_Init(9600);

    // Message initial envoyé sur le terminal série
    printf("Console I/O using USART2 at 9600 Baud\n");

    // Boucle principale
    while (1) {
        // Lire un caractère tapé par l'utilisateur dans le terminal
        char ch = fgetc(stdin);    

        // Renvoyer le même caractère sur le terminal (fonction echo)
        fputc(ch, stdout);        

        // Si l'utilisateur appuie sur "Entrée" (carriage return)
        if (ch == '\r') {         
            // On envoie aussi un saut de ligne (\n) pour formater correctement l'affichage
            fputc('\n', stdout);  
        }
    }
}

// Initialisation USART2 
void USART2_Init(uint32_t baudrate) {
    // 1. Activer l’horloge de GPIOA et USART2 (PA2 = TX, PA3 = RX)
    RCC->AHB1ENR |= RCC_AHB1ENR_GPIOAEN;   // Horloge pour GPIOA
    RCC->APB1ENR |= RCC_APB1ENR_USART2EN;  // Horloge pour USART2

    // 2. Configurer PA2 (TX) et PA3 (RX) en Alternate Function AF7
    // Effacer les bits MODER de PA2 et PA3 (remise à 00 = input)
    GPIOA->MODER &= ~((3 << (2 * 2)) | (3 << (3 * 2)));
    // Mettre PA2 et PA3 en Alternate Function mode (10)
    GPIOA->MODER |=  (2 << (2 * 2)) | (2 << (3 * 2));
    // Sélectionner l’AF7 (USART2) pour PA2 et PA3
    GPIOA->AFR[0] &= ~((0xF << (4 * 2)) | (0xF << (4 * 3))); // Nettoyage
    GPIOA->AFR[0] |=  (7 << (4 * 2)) | (7 << (4 * 3));       // AF7

    // 3. Configurer la vitesse de communication (baudrate)
    // BRR = fréquence horloge périphérique / baudrate
    USART2->BRR = (16000000 / baudrate); // fclk = 16 MHz

    // 4. Activer TX, RX et USART
    USART2->CR1 |= USART_CR1_TE | USART_CR1_RE; // Transmission + Réception
    USART2->CR1 |= USART_CR1_UE;                // Activation USART2
}

// Envoi via USART2 
void USART2_PrintChar(char c) {
    // Attendre que le registre de transmission soit vide
    while (!(USART2->SR & USART_SR_TXE));
    // Charger le caractère dans le registre d’envoi
    USART2->DR = c;
}

// Réception via USART2 
char USART2_ReadChar(void) {
    // Attendre qu’un caractère soit reçu (bit RXNE = 1)
    while (!(USART2->SR & USART_SR_RXNE));
    // Lire et retourner le caractère reçu
    return USART2->DR;
}

// Redirection printf vers USART2 
int fputc(int ch, FILE *f) {
    // Envoyer le caractère via USART2
    USART2_Send(ch);
    // Retourner le caractère envoyé
    return ch;
}

// Redirection scanf vers USART2 
int fgetc(FILE *f) {
    // Lire un caractère reçu via USART2
    char ch = USART2_Receive();
    // Réémettre le même caractère (echo)
    USART2_Send(ch);
    // Retourner le caractère pour utilisation dans le programme
    return ch;
}
```

---
<br>



### **Interruptions USART**

L'USART2 peut générer une interruption sur réception (RXNE) et/ou sur émission (TXE). Le bit `RXNEIE` dans `USART_CR1` active l'interruption de réception.

Le fonctionnement de la réception via interruption repose sur une architecture matérielle bien intégrée dans le STM32F4. Lorsque le périphérique USART reçoit un caractère, le flag `RXNE` (Receive Data Register Not Empty) est activé dans le registre de statut `USART_SR`. Si l’interruption `RXNE` est autorisée via le bit `RXNEIE` du registre de contrôle `USART_CR1`, le périphérique génère automatiquement une interruption matérielle. Le contrôleur d’interruption `NVIC` (Nested Vectored Interrupt Controller) bascule alors vers une routine d’interruption spécifique, comme `USART2_IRQHandler()` dans le cas de l’USART2. Cette fonction est appelée immédiatement par le matériel sans intervention logicielle, assurant ainsi un traitement rapide et automatique.

À l’intérieur de cette routine ISR `USART2_IRQHandler()`, il est impératif de lire sans délai le registre de données `USARTx->DR`, car cette lecture efface le flag `RXNE` et autorise la réception d’un nouveau caractère. Il est fondamental que cette routine reste très légère et rapide, car toute opération longue (comme un printf) pourrait ralentir le traitement et provoquer des pertes de données. Pour cette raison, il est vivement conseillé de transférer immédiatement le caractère reçu vers une zone mémoire tampon, appelée buffer circulaire, que le programme principal traitera ultérieurement. Ce découplage entre la réception et le traitement garantit que le microcontrôleur reste réactif, même en cas de trafic série dense ou irrégulier.

La mise en œuvre de la réception par interruption constitue un excellent exercice de laboratoire pour illustrer les mécanismes bas-niveau de gestion des interruptions et l’intégration avec le logiciel applicatif. Lors de ce laboratoire, on configure d’abord le périphérique USART avec le bon débit (baud rate), la taille des données (8 ou 9 bits), le nombre de bits de stop et la parité. Ensuite, on active l’interruption RXNE en positionnant le bit RXNEIE dans USART_CR1, puis on autorise l’interruption correspondante au niveau du NVIC avec la fonction NVIC_EnableIRQ(USART2_IRQn).

Une fois ces étapes effectuées, la routine d’interruption USART2_IRQHandler() sera exécutée automatiquement à chaque caractère reçu. Dans cette fonction, on lit USART2->DR pour transférer le caractère vers un buffer circulaire, sans perdre de temps. Pendant ce temps, le code principal peut exécuter d’autres tâches (affichage, calcul, gestion de capteurs, etc.), et accéder aux données reçues à son propre rythme. 

Lorsqu’on utilise la réception par interruption, les données peuvent arriver de manière asynchrone et imprévisible. Le problème : que faire de ces données si le code principal du microcontrôleur est occupé et ne peut les traiter immédiatement ? La réponse est l’utilisation d’un buffer circulaire (FIFO).

Le buffer circulaire est un mécanisme logiciel essentiel pour stocker temporairement les caractères reçus, surtout lorsque le traitement ne peut pas être immédiat. Il s’agit d’un tableau fixe en mémoire, associé à deux indices : head (tête d’écriture) et tail (tête de lecture). À chaque interruption, le caractère reçu est stocké dans le tableau à l’indice head, puis ce dernier est incrémenté de façon circulaire (avec un retour à zéro si la fin du tableau est atteinte). 

Lorsque le programme principal souhaite lire un caractère, il le fait à l’indice tail, qu’il incrémente également de manière circulaire. Si head == tail, cela signifie que le buffer est vide ; si head rattrape tail, le buffer est plein. Ce mécanisme permet de gérer proprement le flux de données asynchrones, tout en maintenant la cohérence et sans perdre d’octets (sauf débordement non géré). L’intérêt principal du buffer circulaire est de découpler la réception (via interruption) du traitement (dans le code principal). 

Le microcontrôleur peut ainsi absorber des rafales de données sans risque de perte, même s’il est temporairement occupé ailleurs. Il est néanmoins crucial de surveiller la taille du buffer et de traiter régulièrement les données, afin d’éviter un débordement. Il convient aussi de garder les interruptions courtes, en évitant toute opération lourde ou lente dans l’ISR.

Ce mécanisme est très utilisé dans les systèmes embarqués pour toutes les formes de communication asynchrone rapide : modules Bluetooth, GSM/GPRS, GNSS, PC via USB-UART, radios sans fil, etc. Il constitue également la base pour concevoir des interpréteurs de commandes série, des systèmes de logique interactive, ou des protocoles de communication temps réel. La combinaison d’un buffer circulaire et d’une réception par interruption constitue donc une solution puissante, efficace et robuste, incontournable dans le développement embarqué professionnel.

**Exemple : Réception par Interruption (écho)**

```c
#include "stm32f4xx.h"
#include <string.h>
#include <stdbool.h>
#include <stdlib.h>   // Pour atoi() et atof()

#define RX_BUFFER_SIZE 128

volatile char rx_buffer[RX_BUFFER_SIZE]; // Buffer de réception circulaire
volatile uint16_t rx_head = 0;           // Index d'écriture (rempli dans IRQ)
volatile uint16_t rx_tail = 0;       // Index de lecture (utilisé par le programme)

void USART2_Init(uint32_t baudrate) {
    // 1. Activer l’horloge de GPIOA et USART2 (PA2 = TX, PA3 = RX)
    RCC->AHB1ENR |= RCC_AHB1ENR_GPIOAEN;
    RCC->APB1ENR |= RCC_APB1ENR_USART2EN;

		// 2. Configurer PA2 (TX) et PA3 (RX) en Alternate Function AF7
    GPIOA->MODER &= ~((3 << (2 * 2)) | (3 << (3 * 2)));// Clear MODER2 and MODER3
    GPIOA->MODER |=  (2 << (2 * 2)) | (2 << (3 * 2));	// MODER2/3 = 10 (AF)
    GPIOA->AFR[0] |= (7 << (4 * 2)) | (7 << (4 * 3)); // AFRL2/3 = AF7 (USART2)

    // 3. Configurer baudrate : BRR = fclk / baudrate
    // fclk = 16 MHz, baudrate = 9600 -> BRR = 1667 (0x0683)
		USART2->BRR = (16000000/baudrate);

    // 4. Activer le mode Transmit et Receive, puis activer l’USART
    USART2->CR1 |= USART_CR1_RE | USART_CR1_TE | USART_CR1_RXNEIE; // RX, TX, IRQ
    USART2->CR1 |= USART_CR1_UE;                 // Activer l’USART
	
NVIC_EnableIRQ(USART2_IRQn);   // Activer interruption dans le NVIC
}

// Envoyer un caractère
void USART2_PrintChar(char c) {
    while (!(USART2->SR & USART_SR_TXE)); // Attente que le registre soit vide
    USART2->DR = c;
}

// Interruption RX USART2
void USART2_IRQHandler(void) {
    if (USART2->SR & USART_SR_RXNE) {            // Si un caractère est reçu
        char c = USART2->DR;                     // Lire le caractère reçu
        
				uint16_t next_head = (rx_head + 1) % RX_BUFFER_SIZE;

        if (next_head != rx_tail) {      // Éviter d’écraser les données non lues
            rx_buffer[rx_head] = c;
            rx_head = next_head;
        }
    }
		// Gestion d'erreur de débordement
    if (USART2->SR & USART_SR_ORE) {
        (void)USART2->SR;        // Lire SR pour effacer ORE
        (void)USART2->DR;        // Lire DR pour vider le buffer
    }
}

// si le caractere est disponible
int USART2_Available(void) {
    return (rx_head != rx_tail);
}

// Lire un caractère s’il est disponible
char USART2_ReadChar(void) {
    if (rx_head == rx_tail) return 0;            // Rien à lire
    char c = rx_buffer[rx_tail];
    rx_tail = (rx_tail + 1) % RX_BUFFER_SIZE;
    return c;
}

// Lire une chaîne jusqu’à un délimiteur (ex: '\n')
int USART2_ReadLine(char* buffer, int maxlen) {
    int i = 0;
    while (i < maxlen - 1) {
        while (!USART2_Available()); // Attendre des données
        char c = USART2_ReadChar();
        if (c == '\n' || c == '\r') {
            // Consommer le retour chariot supplémentaire si présent
            if (USART2_Available()) {
                char next_c = USART2_ReadChar();
            	if ((c == '\n' && next_c != '\r') || (c == '\r' && next_c != '\n')){
                // Remettre le caractère non consommé (simulé en ajustant le tail)
                    rx_tail = (rx_tail - 1) % RX_BUFFER_SIZE;
                }
            }
            break;
        }
        buffer[i++] = c;
    }
    buffer[i] = '\0';
    return i;
}

// Convertir une ligne en entier
int32_t USART2_ReadInt(void) {
    char buffer[16];
    USART2_ReadLine(buffer, sizeof(buffer));
    return atoi(buffer);                         // Conversion chaîne ? int
}

// Convertir une ligne en float
float USART2_ReadFloat(void) {
    char buffer[16];
    USART2_ReadLine(buffer, sizeof(buffer));
    return atof(buffer);                         // Conversion chaîne ? float
}

// flush du buffer RX
void USART2_FlushRx(void) {
    rx_head = 0;
    rx_tail = 0;
}

// Envoyer une chaîne de caractères 
void USART2_PrintText(char *str) {
    while (*str) {	// Parcourir la chaîne jusqu’à '\0'
        USART2_PrintChar(*str++);		// Envoyer caractère par caractère
    }
}

// Fonction pour envoyer un retour à la ligne compatible avec les terminaux
void USART2_NewLine(void) {
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
void USART2_PrintFloat(float num) {
    int32_t int_part = (int32_t) num;		// Partie entière
    int32_t frac_part = (int32_t)((num - int_part) * 100);  // Partie fractionnaire à 2 chiffres après virgule

    if (num < 0 && int_part == 0) USART2_PrintChar('-');		// Cas -0.x

    USART2_PrintInt(int_part);		// Afficher partie entière
    USART2_PrintChar('.');		// Afficher séparateur décimal
    if (frac_part < 0) frac_part = -frac_part;	// Corriger si négatif
    if (frac_part < 10) USART2_PrintChar('0');	// Ajoute 0 devant les valeurs < 10 (ex: 3.04)
    USART2_PrintInt(frac_part);		// Afficher partie fractionnaire
}

int main(void) {
    USART2_Init(9600);             // Initialise l’USART2 avec interruptions

    while (1){ // Boucle infinie
		USART2_FlushRx(); // Nettoyer le buffer avant chaque lecture
        
		USART2_PrintText("Entrez un entier : ");
		while (!USART2_Available()); // Attente non bloquante possible ici
		int32_t val = USART2_ReadInt();

		USART2_PrintText("Vous avez saisi : ");
		USART2_PrintInt(val);
		USART2_NewLine();

		USART2_FlushRx();
		USART2_PrintText("Entrez un float : ");
		float fval = USART2_ReadFloat();

		USART2_PrintText("Float : ");
		USART2_PrintFloat(fval);
		USART2_NewLine();
	}
}
```

---
<br>




### **Utilisation avec FreeRTOS**

Pour ne pas bloquer les tâches, on peut utiliser **les interruptions** et **les files de messages**.

**Principe**

- Une ISR de réception (RXNE) place le caractère reçu dans une file (`xQueueSendFromISR`).
- Une tâche consomme les caractères depuis la file (`xQueueReceive`) et les traite.
- L’émission peut aussi être gérée par une tâche qui écrit dans un buffer circulaire ou une file, mais l’exemple le plus simple est de conserver un émission directe (polling court) ou d’utiliser une file et une ISR de fin d’émission (TXE).

**Configuration avec interruption de réception**

```c
#include "FreeRTOS.h"
#include "queue.h"
#include "task.h"
#include "stm32f4xx.h"
#include <stdio.h>
#include <string.h>

QueueHandle_t xRxQueue;

void USART2_IRQHandler(void) {
    BaseType_t xWoken = pdFALSE;
    uint8_t data;

    if (USART2->SR & USART_SR_RXNE) {
        data = USART2->DR;                 // Lire la donnée (efface le flag)
        xQueueSendFromISR(xRxQueue, &data, &xWoken);
    }
    // Gérer d'autres flags si nécessaire (par exemple erreurs)
    portYIELD_FROM_ISR(xWoken);
}

void USART2_Init_Interrupt(uint32_t baud) {
    RCC->AHB1ENR |= RCC_AHB1ENR_GPIOAEN;
    RCC->APB1ENR |= RCC_APB1ENR_USART2EN;

    // PA2 TX, PA3 RX en AF7
    GPIOA->MODER &= ~((3U << (2*2)) | (3U << (3*2)));
    GPIOA->MODER |=  ((2U << (2*2)) | (2U << (3*2)));
    GPIOA->AFR[0] |= (7 << (2*4)) | (7 << (3*4));

    USART2->BRR = 84000000 / baud;
    USART2->CR1 = USART_CR1_TE | USART_CR1_RE | USART_CR1_RXNEIE | USART_CR1_UE;
    
    // Activer l'interruption sur réception
    USART2->CR1 |= USART_CR1_RXNEIE;
    
    // Configurer la priorité et activer dans le NVIC
    NVIC_SetPriority(USART2_IRQn, 5);
    NVIC_EnableIRQ(USART2_IRQn);
}

void USART2_SendChar(char c) {
    while (!(USART2->SR & USART_SR_TXE));
    USART2->DR = c;
}

// Tâche de traitement de la réception (écho simple)
void vTaskRxProcessor(void *pvParameters) {
    uint8_t c;
    for (;;) {
        if (xQueueReceive(xRxQueue, &c, portMAX_DELAY) == pdPASS) {
            // Traiter le caractère reçu (ex: l'accumuler dans une ligne, interpréter une commande...)
            // Pour l'instant, on le renvoie en écho
            USART2_SendChar(c);
        }
    }
}
```

**Émission avec file d’attente (optionnel)**

On peut aussi utiliser une file pour l’émission, avec une tâche dédiée qui vide la file et envoie les caractères (polling court mais sans bloquer les autres tâches).

```c
QueueHandle_t xTxQueue;

void vTaskTxProcessor(void *pvParameters) {
    uint8_t c;
    for (;;) {
        if (xQueueReceive(xTxQueue, &c, portMAX_DELAY) == pdPASS) {
            USART2_SendChar(c);  // Polling, mais on ne bloque que le temps d'envoyer un caractère
        }
    }
}

// Fonction pour envoyer une chaîne via la file (à appeler depuis n'importe quelle tâche)
void USART2_SendStringAsync(char *str) {
    while (*str) {
        xQueueSend(xTxQueue, str++, 0);
    }
}
```

---
<br>



### **Projet : Mini terminal interactif** {#projet-usart-terminal}

Réalisons un petit système qui reçoit des commandes via l’UART, les interprète, et exécute des actions (par exemple allumer/éteindre une LED, afficher l’état, etc.). Ce projet utilise :

- Une interruption de réception pour accumuler les caractères dans une file.
- Une tâche qui lit la file et construit une ligne jusqu’à recevoir un retour chariot (`\n` ou `\r`).
- Une machine à états simple pour interpréter la commande.

```c
#include "FreeRTOS.h"
#include "task.h"
#include "queue.h"
#include "string.h"
#include <stdio.h>
#include "stm32f4xx.h"

// Définition des handles de queue
QueueHandle_t xRxQueue;

// Buffer pour la ligne courante
#define LINE_BUFFER_SIZE 64
static char lineBuffer[LINE_BUFFER_SIZE];
static uint8_t lineIndex = 0;

// Prototypes
void USART2_Init_Interrupt(uint32_t baud);
void vTaskRxInterpreter(void *pvParameters);
void USART2_SendString(char *str);

// Handler d'interruption USART2
void USART2_IRQHandler(void) {
    BaseType_t xWoken = pdFALSE;
    if (USART2->SR & USART_SR_RXNE) {
        uint8_t data = USART2->DR;
        xQueueSendFromISR(xRxQueue, &data, &xWoken);
    }
    portYIELD_FROM_ISR(xWoken);
}

// Tâche d'interprétation des commandes
void vTaskRxInterpreter(void *pvParameters) {
    uint8_t c;
    for (;;) {
        if (xQueueReceive(xRxQueue, &c, portMAX_DELAY) == pdPASS) {
            // Afficher en écho (optionnel)
            USART2_SendChar(c);

            // Fin de ligne ?
            if (c == '\n' || c == '\r') {
                lineBuffer[lineIndex] = '\0'; // Terminer la chaîne
                if (lineIndex > 0) {
                    // Interpréter la commande
                    if (strcmp(lineBuffer, "on") == 0) {
                        GPIOC->ODR |= (1 << 13);   // Allumer LED
                        USART2_SendString("\r\nLED ON\r\n");
                    } else if (strcmp(lineBuffer, "off") == 0) {
                        GPIOC->ODR &= ~(1 << 13);  // Éteindre LED
                        USART2_SendString("\r\nLED OFF\r\n");
                    } else {
                        USART2_SendString("\r\nCommande inconnue\r\n");
                    }
                }
                lineIndex = 0; // Réinitialiser le buffer
            } else if (lineIndex < LINE_BUFFER_SIZE - 1) {
                lineBuffer[lineIndex++] = c;
            }
        }
    }
}

// Programme principal
int main(void) {
    // Initialisation LED PC13
    RCC->AHB1ENR |= RCC_AHB1ENR_GPIOCEN;
    GPIOC->MODER |= (1 << (13*2));
    GPIOC->ODR &= ~(1 << 13); // LED éteinte au départ

    // Initialisation USART à 115200 bauds
    USART2_Init_Interrupt(115200);

    // Création de la file pour les caractères reçus (taille 32)
    xRxQueue = xQueueCreate(32, sizeof(uint8_t));

    if (xRxQueue != NULL) {
        // Création de la tâche d'interprétation
        xTaskCreate(vTaskRxInterpreter, "RxInterp", 256, NULL, 2, NULL);
        
        // Lancement de l'ordonnanceur
        vTaskStartScheduler();
    }

    // Ne devrait jamais arriver
    while(1);
}
```

**Explications :**

- Les caractères reçus sont mis dans une file par l’ISR.
- La tâche `vTaskRxInterpreter` les récupère un par un, les accumule dans un buffer jusqu’à recevoir un retour chariot, puis compare la ligne avec des commandes prédéfinies.
- La LED est commandée via les commandes `on` et `off`.
- L’écho permet de voir ce qu’on tape (facultatif).

---
<br>



### **Projet : Protection d'un affichage UART**

Deux tâches souhaitent écrire sur le même UART. Un mutex protège l'accès.

```c
#include "FreeRTOS.h"
#include "task.h"
#include "semphr.h"
#include "stm32f4xx.h"
#include <stdio.h>

SemaphoreHandle_t xUARTMutex;

void USART2_Init(void);
void USART2_SendString(char *str);

void vTask1(void *pvParameters) {
    for (;;) {
        if (xSemaphoreTake(xUARTMutex, portMAX_DELAY) == pdTRUE) {
            USART2_SendString("Tache 1 : message\r\n");
            xSemaphoreGive(xUARTMutex);
        }
        vTaskDelay(pdMS_TO_TICKS(1000));
    }
}

void vTask2(void *pvParameters) {
    for (;;) {
        if (xSemaphoreTake(xUARTMutex, portMAX_DELAY) == pdTRUE) {
            USART2_SendString("Tache 2 : autre message\r\n");
            xSemaphoreGive(xUARTMutex);
        }
        vTaskDelay(pdMS_TO_TICKS(1500));
    }
}

int main(void) {
    USART2_Init(115200);
    xUARTMutex = xSemaphoreCreateMutex();

    if (xUARTMutex != NULL) {
        xTaskCreate(vTask1, "Task1", 128, NULL, 1, NULL);
        xTaskCreate(vTask2, "Task2", 128, NULL, 1, NULL);
        vTaskStartScheduler();
    }
    while(1);
}
```

---
<br>



### **Projet : Acquisition de deux capteurs avec affichage UART**

Deux tâches lisent périodiquement des valeurs analogiques (simulées) et envoient les résultats sur l'UART. Un mutex protège l'UART. De plus, une file est utilisée pour transmettre les données à une tâche d'affichage unique (découplage).

Matériel :

- Black Pill
- Deux potentiomètres sur PA0 et PA1 (simulant des capteurs)
- UART2 pour l'affichage sur PC

```c
#include "FreeRTOS.h"
#include "task.h"
#include "queue.h"
#include "semphr.h"
#include "stm32f4xx.h"
#include <stdio.h>

// Handles
SemaphoreHandle_t xUARTMutex;
QueueHandle_t xDataQueue;

// Structure de données
typedef struct {
    uint8_t capteur_id;
    uint16_t valeur;
} Mesure_t;

// Fonctions matérielles
void ADC_Init(void) {
    RCC->AHB1ENR |= RCC_AHB1ENR_GPIOAEN;
    RCC->APB2ENR |= RCC_APB2ENR_ADC1EN;
    GPIOA->MODER |= (3U << (0*2)) | (3U << (1*2)); // PA0, PA1 analogiques
    ADC1->CR2 = 0;
    ADC1->SQR3 = 0; // canal 0 (à changer dynamiquement)
    ADC1->SMPR2 = (7 << 0);
    ADC1->CR2 |= ADC_CR2_ADON;
}

uint16_t ADC_Read(uint8_t channel) {
    ADC1->SQR3 = channel;
    ADC1->CR2 |= ADC_CR2_SWSTART;
    while (!(ADC1->SR & ADC_SR_EOC));
    return (uint16_t)ADC1->DR;
}

void USART2_Init(uint32_t baud) {
    RCC->AHB1ENR |= RCC_AHB1ENR_GPIOAEN;
    RCC->APB1ENR |= RCC_APB1ENR_USART2EN;
    GPIOA->MODER |= (2 << (2*2)) | (2 << (3*2));
    GPIOA->AFR[0] |= (7 << (2*4)) | (7 << (3*4));
    USART2->BRR = 84000000 / baud;
    USART2->CR1 = USART_CR1_TE | USART_CR1_UE;
}

void USART2_SendString(char *str) {
    while (*str) {
        while (!(USART2->SR & USART_SR_TXE));
        USART2->DR = *str++;
    }
}

// Tâches
void vTaskCapteur1(void *pvParameters) {
    Mesure_t mesure;
    mesure.capteur_id = 1;
    for (;;) {
        mesure.valeur = ADC_Read(0);
        xQueueSend(xDataQueue, &mesure, 0);
        vTaskDelay(pdMS_TO_TICKS(500));
    }
}

void vTaskCapteur2(void *pvParameters) {
    Mesure_t mesure;
    mesure.capteur_id = 2;
    for (;;) {
        mesure.valeur = ADC_Read(1);
        xQueueSend(xDataQueue, &mesure, 0);
        vTaskDelay(pdMS_TO_TICKS(300));
    }
}

void vTaskAffichage(void *pvParameters) {
    Mesure_t mesure;
    char buffer[32];
    for (;;) {
        if (xQueueReceive(xDataQueue, &mesure, portMAX_DELAY) == pdPASS) {
            if (xSemaphoreTake(xUARTMutex, portMAX_DELAY) == pdTRUE) {
                sprintf(buffer, "Capteur %d : %u\r\n", mesure.capteur_id, mesure.valeur);
                USART2_SendString(buffer);
                xSemaphoreGive(xUARTMutex);
            }
        }
    }
}

int main(void) {
    ADC_Init();
    USART2_Init(115200);

    xUARTMutex = xSemaphoreCreateMutex();
    xDataQueue = xQueueCreate(10, sizeof(Mesure_t));

    if (xUARTMutex != NULL && xDataQueue != NULL) {
        xTaskCreate(vTaskCapteur1, "Capteur1", 128, NULL, 1, NULL);
        xTaskCreate(vTaskCapteur2, "Capteur2", 128, NULL, 1, NULL);
        xTaskCreate(vTaskAffichage, "Affichage", 256, NULL, 2, NULL);
        vTaskStartScheduler();
    }
    while(1);
}
```

- Deux tâches productrices lisent des capteurs et envoient les données dans une file.
- Une tâche consommatrice lit la file et affiche via UART, protégée par un mutex.
- La file découple l'acquisition de l'affichage et permet de gérer des cadences différentes.

---
<br>



### Liens connexe

- [GPIO et Interruptions](../gpio/index.md)
- [Timer et Interruption](../timer/index.md)
- [Machine d’État Fini (FSM)](../../technique-algos/fsm/index.md)
- [Introduction pratique à freeRTOS](../../rtos/freertos.md)