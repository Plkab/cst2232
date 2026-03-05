# Introduction au Langage C embarqué

*Ir Paul S. Kabidu, M.Eng. <spaulkabidu@gmail.com>*
{: style="text-align: center;" }

---

[Accueil](../../#Accueil)
  
<br>
<br>


Le langage C embarqué est une extension du langage C adaptée aux contraintes des microcontrôleurs (ressources limitées, accès direct au matériel). Il reste aujourd'hui le langage de référence pour les systèmes embarqués et les noyaux de systèmes d'exploitation. Avec ce langage, on peut directement manipuler des adresses mémoire dans le but de configurer le matériel (GPIO, Timer, ADC, USART…).

---
<br>

### **Les Variables et Types de données**

Dans la programmation embarquée, la taille des variables est critique en raison des contraintes de mémoire. On a donc :

- **int (entier)** : souvent 32 bits (ex: 10, -5).
- **char (caractère)** : 8 bits (ex: 'A').
- **float / double** : nombres à virgule.

Les types standards (`int`, `short`, `long`) changent de taille selon le processeur (16 bits sur Arduino, 32 bits sur STM32). Pour éviter les bugs, on utilise les types à taille fixe (C99), regroupés dans la bibliothèque `<stdint.h>`. Cela garantit la portabilité dans l'embarqué :

- **`uint8_t`** : 8 bits non signé (0 à 255). Pratique pour les registres 8 bits, les drapeaux (flags).
- **`uint16_t`** : 16 bits non signé (0 à 65535). Utilisé pour les valeurs brutes d'un ADC 12 bits ou des timers.
- **`uint32_t`** : 32 bits non signé (0 à 4,2 milliards). C'est la taille native des registres du STM32F4. C'est le type utilisé pour toutes les adresses de registres.

| Type       | Taille (bits) | Plage           | Usage typique                  |
|------------|---------------|-----------------|--------------------------------|
| `uint8_t`  | 8             | 0 à 255         | Registre 8 bits, état de LED   |
| `int8_t`   | 8             | -128 à 127      | Température basse              |
| `uint16_t` | 16            | 0 à 65 535      | Valeur ADC (12 bits)           |
| `uint32_t` | 32            | 0 à 4,2 milliards | Adresse registre STM32       |

Dans la déclaration des variables, on peut utiliser certains mots-clés :

- **`volatile`** : Indispensable. Empêche le compilateur d'optimiser une variable qui peut changer hors du flux normal du programme (ex: un drapeau d'interruption ou un registre matériel, l'état d'un bouton). Sans `volatile`, le compilateur pourrait croire que la valeur n'a pas changé et ignorer l'appui sur le bouton.
- **`static`** : Limite la portée d'une variable à un fichier ou conserve sa valeur entre deux appels de fonction. La variable n'est visible que dans le fichier actuel (encapsulation).
- **`const`** : Indique que la variable ne changera jamais et la place en mémoire Flash (lecture seule) pour économiser la RAM. C'est vital pour économiser la précieuse RAM du STM32F4.

Quand on déclare une variable, on **réserve** un espace mémoire, un emplacement physique dans la RAM ou la Flash. Pour notre cas, la RAM est de 64 Ko, comparativement à plusieurs Go pour les PC.

Nous pouvons également donner un surnom à un type existant en utilisant le mot-clé **`typedef`** :

```c
typedef uint32_t registre_t; // "registre_t" est maintenant un synonyme de uint32_t
registre_t monGPIO;
```

Cela rend le code plus lisible et portable.

---
<br>

### **La structure**

Une **structure** permet de regrouper des variables de types différents sous un seul nom. C'est l'outil idéal pour représenter un objet complexe (un capteur, un moteur).

```c
struct Capteur {
    uint16_t valeur;      // 2 octets pour l'ADC
    uint8_t  id;          // 1 octet pour le numéro
    uint8_t  estActif;    // 1 octet (booléen)
}; // Taille totale = 4 octets

struct Capteur monCapteur;
monCapteur.valeur = 2048;
```
On peut créer des types personnalisés pour les états ou les configurations.

```c
typedef uint32_t registre_t; // "registre_t" est maintenant un synonyme de uint32_t
registre_t monGPIO;

// Très souvent utilisé avec les structures :
typedef struct {
    uint8_t r;
    uint8_t g;
    uint8_t b;
} Couleur_t;

Couleur_t maLED = {255, 0, 0}; // Plus besoin d'écrire "struct" devant
```

C'est très utile pour mapper exactement la structure d'un registre matériel STM32 tel que décrit dans la datasheet.

```c
typedef struct {
    volatile uint32_t MODER;    // Adresse 0x00
    volatile uint32_t OTYPER;   // Adresse 0x04
    volatile uint32_t OSPEEDR;  // Adresse 0x08
    // ...
} GPIO_Regs_t;

// On pointe directement sur l'adresse réelle du matériel
#define GPIOA ((GPIO_Regs_t *) 0x40020000)

GPIOA->MODER |= (1 << 0); // Manipulation élégante et lisible !
```

---
<br>

### **L'Union**

Une **union** permet de stocker des variables de types différents au même emplacement mémoire. La taille de l'union est celle de son plus grand élément.

```c
union Paquet {
    uint32_t motComplet;    // Accès aux 32 bits d'un coup
    uint8_t  octets[4];     // Accès octet par octet pour l'envoi
};

union Paquet monRegistre;
monRegistre.motComplet = 0x12345678;
// monRegistre.octets[0] vaudra 0x78 (sur STM32 Little Endian)
```

---
<br>

### **Les Opérateurs Arithmétiques, de Comparaison et Logiques**

**Opérateurs Arithmétiques**

|Opérateur	|Nom	Usage sur STM32|
|-----------|----------------------|
|+	|Addition	|Calcul d'offsets mémoire ou de compteurs.|
|-	|Soustraction	|Calcul d'écarts de temps (Ticks).|
|*	|Multiplication	|Mise à l'échelle de valeurs (ex: conversion ADC).|
|/	|Division	|Moyenne de mesures (Attention : Division entière).|
|%	|Modulo	|Reste d'une division. Très utile pour créer des boucles| circulaires ou faire une action tous les X cycles.|

**Opérateurs de Comparaison**

|Opérateur 	|Nom	Signification|
|-----------|--------------------|
|==	|Égal à	|Vrai si les deux valeurs sont identiques.|
|!=	|Différent de	|Vrai si les deux valeurs ne sont pas identiques.|
|>	|Supérieur à	|Vrai si la valeur de gauche est strictement plus grande.|
|<	|Inférieur à	|Vrai si la valeur de gauche est strictement plus petite.|
|>=	|Supérieur ou égal	|Vrai si la valeur est égale ou plus grande.|
|<=	|Inférieur ou égal	|Vrai si la valeur est égale ou plus petite.|

**Opérateurs Logiques**

En langage C, les **opérateurs logiques** servent à combiner plusieurs conditions entre elles (généralement dans un if, while ou for). Ils renvoient toujours un résultat booléen (Vrai ou Faux).
On a 3 opérateurs logiques && (ET), || (OU), ! (NON) :

| Opérateur | Nom      | Description                                         | Exemple                                      |
|-----------|----------|-----------------------------------------------------|----------------------------------------------|
| `&&`      | ET (AND) | Vrai si toutes les conditions sont vraies.          | `if (temp > 25 && ventilateur == OFF)`       |
| `\|\|`    | OU (OR)  | Vrai si au moins une condition est vraie.           | `if (bouton == PRESSED \|\| urgence == 1)`   |
| `!`       | NON (NOT)| Inverse l'état de la condition (Vrai devient Faux). | `if (!systeme_pret)` (si le système n'est PAS prêt) |

En langage C, **0** est considéré comme **Faux (FALSE)**. Et tout ce qui n'est pas 0 (1, -5, 100...) est considéré comme **Vrai (TRUE)**.

---
<br>

### **Les Structures de Contrôle (Le Flux)**

**Exemple Conditions : Sécurité "ET" (&&)**

On ne lance l'action que si toutes les conditions de sécurité sont réunies.
```c
// Sécurité : Le moteur ne tourne que si la porte est fermée ET le bouton pressé
if (Porte_Est_Fermee() && Bouton_Start_Presse()) {
    Moteur_On();
} else {
    Moteur_Off(); // Sécurité par défaut
}
```

Avec &&, si la première condition est fausse, le C n'évalue même pas la deuxième (le résultat sera forcément faux).

**Exemple Conditions : Alerte "OU" (||)**

On déclenche l'arrêt d'urgence si au moins un défaut est détecté.
```c
// Arrêt si la température est trop haute OU si le courant est excessif
if (Temperature > 80 || Courant > 10) {
    Arret_Urgence();
    Allumer_LED_Rouge();
}
```

Avec ||, si la première est vraie, la deuxième n'est pas testée (le résultat sera forcément vrai).

**Exemple Conditions : Inversion "NON" (!)**

On vérifie l'absence d'un signal ou un état inverse.
```c
// Si le système n'est PAS en erreur, on continue le traitement
if (!Systeme_En_Erreur()) {
    Continuer_Acquisition();
}
```

On peut combiner les trois pour des logiques plus fines :

```c
// Autorisation de charge batterie : 
// (Tension OK ET Température OK) ET (PAS de mode maintenance actif)
if ((Tension < 4.2 && Temp < 45) && !Mode_Maintenance) {
    Demarrer_Charge();
}
```

**Le Choix Multiple : switch...case**

Le switch est l'outil idéal pour gérer des machines à états ou des menus. Il est plus lisible et souvent plus performant qu'une longue série de if...else if lorsqu'on teste plusieurs valeurs pour une même variable.

```c
typedef enum { IDLE, RUNNING, ERROR } State_t;
State_t systemeStatut = IDLE;

switch (systemeStatut) {
    case IDLE:
        Attendre_Commande();
        break; // Quitte le switch. Obligatoire pour ne pas exécuter la suite.
    case RUNNING:
        Executer_Tache();
        break;
    case ERROR:
        Declencher_Alarme();
        break;
    default: // Sécurité : exécuté si aucune valeur ne correspond
        Reset_Systeme();
        break;
}
```

N'oubliez jamais le break, sinon le programme exécute aussi le code du case suivant (phénomène de fall-through).

---
<br>

### **Les Boucles (Répétitions)**

Dans l'embarqué, le processeur ne doit jamais s'arrêter. Les boucles permettent de gérer cette continuité.

**Boucle : for**

Idéale quand le nombre de répétitions est connu à l'avance. Sa structure est : `for (initialisation ; condition ; incrémentation)`

Exemple : Parcourir un tableau de données capteurs ou moyenner 10 mesures ADC.

```c
uint32_t somme = 0;

for (int i = 0; i < 10; i++) {
    somme += Lire_ADC(); // Somme 10 échantillons
}

uint32_t moyenne = somme / 10;
```

**Boucle : do...while**

Contrairement au `while`, cette boucle exécute le code au moins une fois avant de tester la condition.

```c
uint8_t tentative = 0;

do {
    Tenter_Connexion_Capteur();
    tentative++;
} while (!Capteur_Pret && tentative < 3);
```

Cette boucle est très utilisée pour les séquences d'initialisation matérielle où l'on doit tenter une action avant de vérifier si elle a réussi.

**Boucle : while**

Idéale quand on attend un événement extérieur dont on ne connaît pas la durée. On peut l'utilise pour attendre qu'un bit de registre change d'état.

Exemple : Parcourir un tableau de données capteurs ou moyenner 10 mesures ADC.

```c
// Attendre que l'horloge système soit stable
while ((RCC->CR & RCC_CR_HSERDY) == 0); 
```

Un while sur un registre matériel (ex: attendre un signal UART) peut bloquer tout le programme si le périphérique tombe en panne. Pour des raisons de sécurité on ajoute souvent un timeout à un while.

```c
uint32_t timeout = 10000;

while (!Signal_Recu && timeout > 0) {
    timeout--; // On évite de rester bloqué à l'infini
}
```

**Boucle infinie : while(1)**

Pour le flux en embarqué sur STM32, le processeur ne doit jamais s'arrêter, on utilise la boucle infinie `while(1)`. Si le main se termine, le comportement devient imprévisible. On verrouille donc toujours la fin du programme :

```c
int main(void) {

    Init_Hardware();

    while(1) {
        // Le coeur du système bat ici indéfiniment
        Lire_Capteurs();
        Traiter_Donnees();
    }
}
```

---
<br>

### **Manipulation de bits (Opérateurs Bitwise)**

Dans la programmation _baremetal C_, on utilise largement la manipulation des bits Ce sont les outils les plus utilisés pour configurer les registres du microcontrôleur. Contrairement aux opérateurs logiques (&&, ||, !), ceux-ci agissent sur chaque bit individuellement.

- L'operateur **<< (décalage gauche)** permet de positionner un bit à un emplacement précis.
- L'operateur **>> (décalage droite)** permet de lire la valeur d'un bit spécifique.
- **SET (Mise un bit à 1)** : REG |= (1 << 5); (Met le bit 5 à 1).
Le	OU (OR)	permet de mettre un ou plusieurs bits à 1 sans modifier les autres.
```c
    // Mettre le bit 13 à 1 (Activer PC13 en sortie)
    GPIOC->MODER |= (1 << 26); 
```
- **CLEAR (Mise un bit à 0)** : REG &= ~(1 << 5); (Met le bit 5 à 0).
Le 	ET (AND) permet de vérifier l'état d'un bit ou le mettre à 0. Et le NON (NOT) souvent utilisé avec & inverse tous les bits.
```c
    // Mettre le bit 13 à 0
    GPIOC->ODR &= ~(1 << 13); 
```
- **TOGGLE (Basculer un bit)** : REG ^= (1 << 5); (Inverse l'état du bit 5).
Le OU Exclusif (XOR) permet d'inverser (TOGGLE) l'état d'un bit (ex: faire clignoter une LED).
```c
    // Change l'état de la LED à chaque passage
    GPIOC->ODR ^= (1 << 13); 
```
- **CHECK (Tester un bit)** : if (REG & (1 << 5)) (Vérifie si le bit 5 est à 1).
```c
    // Vérifier si le bouton sur PA0 est pressé (bit 0)
    if (GPIOA->IDR & (1 << 0)) {
        // Action...
    }
```

---
<br>

### **Les Pointeurs**

**Un pointeur** est une variable qui contient l'adresse mémoire d'une autre variable. C'est l'outil le plus puissant du C pour manipuler directement le matériel.

- **& (Adresse de)** : Récupère l'emplacement mémoire d'une variable.
- **(Contenu de)** : Accède à la valeur située à l'adresse stockée par le pointeur.

```c
uint32_t variable = 100;
uint32_t *monPointeur = &variable; // monPointeur contient l'adresse de variable

*monPointeur = 200; // La "variable" vaut maintenant 200
```

Sur STM32, les structures de registres (ex: `GPIOA->MODER`) sont des pointeurs pointant vers des adresses physiques fixes du processeur.
Toutes fonctions du matériel est mappé en mémoire. Pour configurer le STM32, on crée des pointeurs vers des adresses fixes définies dans la datasheet.

```c
// L'adresse du registre MODER du GPIOA est 0x40020000
#define GPIOA_MODER *((volatile uint32_t *) 0x40020000)

GPIOA_MODER |= (1 << 0); // On écrit directement dans le matériel
```

on utilise l'opérateur Flèche `->` comme un raccourci partout en embarqué (ex: GPIOA->ODR).
- `structure.membre` : Accès direct si vous avez la variable.
- `pointeur->membre` : Accès si vous avez l'adresse de la structure.

---
<br>

### **Les Fonctions**

Elles permettent de modulariser le code. Une fonction peut retrourner une valeur, par exemple : `void` (rien), `int`, `uint8_t`, etc, et peut recevoir des paramètres. 

```c
int addition(int a, int b) {
    return a + b;
}
```

---
<br>

### **Bibliotheque**

Lorsqu'on a plusieurs fonctions pour un objet (périphérique) quelconque, on les regroupe dans deux fichiers : le header (`.h`) et la source (`.c`).

**Le fichier Header : `led.h` (L'interface)**

C'est le "menu" de la bibliothèque. Il contient les prototypes des fonctions et les définitions.

```c
#ifndef LED_H    // Garde d'inclusion : évite les erreurs si le fichier est inclus 2 fois
#define LED_H

#include "stm32f4xx.h" // Pour les types et registres

// Définition de la pin (PC13 sur Black Pill)
#define LED_PIN  13
#define LED_PORT GPIOC

// Prototypes des fonctions
void LED_Init(void);
void LED_On(void);
void LED_Off(void);
void LED_Toggle(void);

#endif
```

**Le fichier Source : `led.c` (L'implémentation)**

C'est ici que l'on écrit la "recette" réelle des fonctions en manipulant les registres.

```c
#include "led.h"

void LED_Init(void) {
    // Activer horloge GPIOC
    RCC->AHB1ENR |= RCC_AHB1ENR_GPIOCEN;
    // Configurer PC13 en sortie
    LED_PORT->MODER &= ~(3U << (LED_PIN * 2));
    LED_PORT->MODER |=  (1U << (LED_PIN * 2));
}

void LED_On(void) {
    LED_PORT->BSRR = (1U << (LED_PIN + 16)); // Reset bit (0V -> Allumé)
}

void LED_Off(void) {
    LED_PORT->BSRR = (1U << LED_PIN);        // Set bit (3.3V -> Éteint)
}

void LED_Toggle(void) {
    LED_PORT->ODR ^= (1U << LED_PIN);        // Inversion du bit
}
```

**Utilisation dans : main.c**

Votre programme principal devient alors très propre et lisible.

```c
#include "led.h"

int main(void) {
    LED_Init(); // Initialisation via notre driver

    while(1) {
        LED_Toggle();
        for(int i=0; i<500000; i++); // Délai rudimentaire
    }
}
```

Les avantages de cette méthode est que l'on a un code réutilisable, on peut copier ces fichiers dans n'importe quel projet. Le code est facilement maintenable si on change de pin (ex: de PC13 à PA5), on ne modifie que le fichier led.h. On a aussi une clarté, le main.c ne contient que la logique applicative, pas les détails techniques des registres.


### Lien connexe

[GPIO et Interruptions](../stm32f4/gpio/index.md)