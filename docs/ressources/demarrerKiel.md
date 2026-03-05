# Création d'un projet Keil uVision pour STM32F401CCU6 en bare metal C

*Ir Paul S. Kabidu, M.Eng. <spaulkabidu@gmail.com>*
{: style="text-align: center;" }

---

[Accueil](../../#Accueil)
  
<br>
<br>

### **Étape 1 : Créer un nouveau projet**

- Lancez Keil uVision.
- Dans le menu, allez dans Project → New uVision Project....
- Choisissez un dossier de destination pour votre projet (par exemple, un dossier Blink/) et donnez un nom à votre projet (par exemple, Blink). Cliquez sur Save.

### ** Étape 2 : Sélectionner le microcontrôleur cible**

- Une fenêtre "Select Device for Target" s'ouvre.
- Dans la barre de recherche, tapez "STM32F401CC".
- Dans la liste des résultats, sélectionnez "STM32F401CC". La description doit mentionner "256KB Flash, 64KB RAM" pour le modèle U6 (Black Pill). Cliquez sur OK.

    Note : La première fois que vous sélectionnez un microcontrôleur de cette famille, Keil vous proposera d'installer les packs (Packs Installer). Acceptez pour télécharger et installer le pack Keil::STM32F4xx_DFP (Device Family Pack) si ce n'est pas déjà fait. Cela ajoutera tous les fichiers de définition (SVD, Flash, etc.) et les exemples nécessaires.

### ** Étape 3 : Gérer les "Run-Time Environment" (RTE)**

Après avoir sélectionné le microcontrôleur, la fenêtre "Manage Run-Time Environment" s'ouvre. C'est là que vous choisissez les composants logiciels à inclure. Pour notre approche bare metal sans HAL, vous allez décocher la plupart des options.

- Dans l'onglet "Software Components", désactivez l'option "CMSIS::CORE" ? Non, il faut le garder. Le CMSIS (Cortex Microcontroller Software Interface Standard) fournit les définitions de base pour accéder aux registres du Cortex-M. Vous en aurez besoin .
- Décochez toutes les cases sous "Device" qui commencent par "STM32Cube HAL" (comme ADC, GPIO, RCC, etc.). Vous n'utiliserez pas la HAL.
- Vérifiez que sous "CMSIS", la case "CORE" est bien cochée.
- Cliquez sur OK.

### ** Étape 4 : Comprendre la structure du projet**

Votre projet dans la fenêtre "Project" (à gauche) contient désormais un dossier "Target 1" qui lui-même contient un dossier "Source Group 1". Vous allez maintenant ajouter les fichiers nécessaires.

### ** Étape 5 : Ajouter les fichiers de démarrage (Startup) et système**

Pour un projet bare metal, vous avez besoin de deux fichiers essentiels, fournis par le pack que vous avez installé.

- **Fichier de démarrage (Startup)** :

    - C'est un fichier assembleur qui contient la table des vecteurs d'interruption et le code de démarrage initial.
    - Faites un clic droit sur "Source Group 1" et sélectionnez "Add Existing Files to Group 'Source Group 1'...".
    - Naviguez jusqu'au dossier d'installation de Keil (souvent C:\Keil_v5\). Le chemin typique est :
    C:\Keil_v5\ARM\PACK\Keil\STM32F4xx_DFP\<version>\Device\Source\ARM\
    - Dans ce dossier, cherchez un fichier nommé startup_stm32f401xx.s. Sélectionnez-le et cliquez sur "Add".

- **Fichier système (System)** :

    - Toujours dans la même boîte de dialogue, naviguez vers :
    C:\Keil_v5\ARM\PACK\Keil\STM32F4xx_DFP\<version>\Device\Source\
    - Ajoutez le fichier system_stm32f4xx.c. Ce fichier contient les fonctions essentielles comme SystemInit() qui configure l'horloge de base.

### **Étape 6 : Ajouter les fichiers d'en-tête CMSIS**

Le fichier system_stm32f4xx.c a besoin de fichiers d'en-tête pour compiler. Le plus important est stm32f401xe.h (ou un nom similaire), qui contient les définitions de tous les registres.

- Allez dans le menu Project → Options for Target 'Target 1'... (ou cliquez sur l'icône de configuration).
- Allez dans l'onglet "C/C++ (AC6)" (ou "C/C++" selon votre compilateur).
- Dans la zone "Include Paths", vous devez ajouter le chemin vers les fichiers d'en-tête CMSIS. Cliquez sur le bouton "..." à côté de la zone de texte.
- Ajoutez le chemin suivant :
C:\Keil_v5\ARM\PACK\Keil\STM32F4xx_DFP\<version>\Device\Include\
(Remplacez <version> par le numéro de version que vous avez installé, par exemple 2.16.0).

### **Étape 7 : Créer votre fichier source principal**

- Créez un nouveau fichier dans Keil : File → New.
- Enregistrez-le immédiatement dans votre dossier de projet (à côté de votre .uvprojx) en lui donnant un nom, par exemple main.c.
- Écrivez votre code "bare metal". Voici un exemple minimal qui fait clignoter la LED sur la carte Black Pill (généralement sur la broche PC13) :

    ```c
    #include "stm32f401xe.h"

    // Fonction de délai simple (dépend de la vitesse CPU)
    void delay(volatile uint32_t count) {
        while(count--) {
            __NOP(); // No Operation, pour éviter que l'optimisation ne supprime la boucle
        }
    }

    int main(void) {
        // 1. Activer l'horloge sur le port C (où se trouve la LED)
        RCC->AHB1ENR |= RCC_AHB1ENR_GPIOCEN;

        // 2. Configurer PC13 en sortie push-pull
        // MODER : 00=Entrée, 01=Sortie, 10=Fonction Alternée, 11=Analogique
        GPIOC->MODER &= ~(3U << (13 * 2));  // Reset des 2 bits de la broche 13
        GPIOC->MODER |=  (1U << (13 * 2));  // Mise à 01 (Sortie standard)

        // OTYPER : 0=Push-Pull (standard), 1=Open-Drain
        GPIOC->OTYPER &= ~(1U << 13);       // Force en Push-Pull

        while(1) {
            // Allumer la LED (Sur la Black Pill, PC13 est reliée à la masse)
            // On écrit dans le registre BSRR (Bit Set Reset Register)
            // BR13 (Bit Reset) met la sortie à 0V -> La LED s'allume
            GPIOC->BSRR = (1U << (13 + 16)); 
            delay(1000000);

            // Éteindre la LED
            // BS13 (Bit Set) met la sortie à 3.3V -> La LED s'éteint
            GPIOC->BSRR = (1U << 13); 
            delay(1000000);
        }
    }
    ```

- Ajoutez ce main.c à votre "Source Group 1" en utilisant "Add Existing Files...".

### **Étape 8 : Compiler, téléverser et tester

- Compilez votre projet : Project → Build target (ou la touche F7).
- Si la compilation est réussie, téléversez le code sur la carte : Flash → Download (ou la touche F8).
- Si vous avez coché "Reset and Run", la LED sur PC13 devrait se mettre à clignoter. Sinon, appuyez sur le bouton reset de la carte.

### **Structure finale de votre projet**

Votre projet Keil devrait maintenant ressembler à ceci dans la fenêtre "Project" :

```py
Target 1
 |-- Source Group 1
 |    |-- startup_stm32f401xx.s
 |    |-- system_stm32f4xx.c
 |    |-- main.c
 ```
