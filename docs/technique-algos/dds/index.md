# Synthèse Numérique Directe (DDS) avec DAC externe MCP4822


*Ir Paul S. Kabidu, M.Eng. <spaulkabidu@gmail.com>*
{: style="text-align: center;" }

---

[Accueil](../../#Accueil)

<br>
<br>



### **Introduction**

La **synthèse numérique directe (DDS)** est une technique de génération de signaux analogiques (sinus, triangle, carré, etc.) à partir d’une horloge de référence et d’une table d’onde. Elle permet de produire des fréquences très précises et facilement ajustables avec une grande résolution. On la trouve dans les générateurs de signaux, les synthétiseurs de fréquence, les instruments de mesure, etc.

Le STM32F401 ne dispose pas de convertisseur numérique-analogique (DAC) interne. Pour générer un signal analogique, nous utiliserons un **DAC externe** via le bus SPI. Le **MCP4822** de Microchip est un DAC double canal 12 bits avec interface SPI, très simple d’utilisation. Dans ce chapitre, nous allons :

- Comprendre le principe de la DDS.
- Configurer le MCP4822 pour recevoir des données via SPI.
- Implémenter un générateur de signaux sinusoïdaux avec contrôle de fréquence.
- Intégrer le tout dans une tâche FreeRTOS pour une génération en temps réel.

---
<br>

### **Principe de la DDS**

Un système DDS classique se compose de :

- Un **accumulateur de phase** (registre qui s’incrémente à chaque coup d’horloge).
- Une **table d’onde** (look-up table) contenant les échantillons d’une période du signal désiré.
- Un **convertisseur numérique-analogique** (DAC) qui transforme la valeur lue en tension.

La fréquence du signal de sortie est donnée par :

\[
f_{out} = \frac{M \cdot f_{clk}}{2^N}
\]

où :
- \(M\) est le pas d’incrémentation (mot de réglage de fréquence),
- \(f_{clk}\) est la fréquence d’horloge du système (cadence d’envoi au DAC),
- \(N\) est le nombre de bits de l’accumulateur de phase (ex: 32 bits).

En modifiant \(M\), on change la fréquence sans modifier la table d’onde. La résolution en fréquence est :

\[
\Delta f = \frac{f_{clk}}{2^N}
\]

---
<br>

### **Le DAC externe MCP4822**

Le **MCP4822** est un DAC double canal 12 bits avec sortie rail-to-rail. Il communique via SPI (mode 0,0) et nécessite une tension de référence (peut être interne ou externe). Caractéristiques :

- Résolution 12 bits (0 à 4095).
- Tension de sortie : 0 à \(V_{ref}\) (interne 2.048V ou externe jusqu’à 5V).
- Interface SPI simple : données sur 16 bits (bit de configuration + 12 bits de valeur).
- Temps d’établissement rapide (4.5 µs typ.).

#### **Trame SPI**

Les 16 bits sont formatés ainsi :

| Bit 15 | Bit 14 | Bit 13 | Bits 12-0 |
|--------|--------|--------|-----------|
| 0/1 (A/B) | 1 (GA) | 1 (SHDN) | Données 12 bits (justifiés à gauche) |

- **Bit 15** : sélection du canal (0 = canal A, 1 = canal B).
- **Bit 14** : GA = 1 pour utiliser la référence interne (x1), 0 pour x2.
- **Bit 13** : SHDN = 1 pour sortie active, 0 pour sortie haute impédance.
- **Bits 12-1** : valeur 12 bits (les bits 12-1 sont les bits de donnée, le bit 0 est ignoré car les données sont justifiées à gauche). En pratique, on envoie un uint16_t où les bits 15-4 sont la valeur 12 bits décalée de 4.

#### **Connexion au STM32**

On utilisera le SPI1 (par exemple) avec les broches :

- PA5 (SCLK)
- PA6 (MISO non utilisé ici)
- PA7 (MOSI)
- PA4 (CS) pour sélectionner le MCP4822.

---
<br>

### **Implémentation de la DDS**

Nous allons générer un signal sinusoïdal. Pour cela, nous créons une table d’onde contenant 256 échantillons d’une période de sinus (codés sur 12 bits). La résolution de phase est donc de 8 bits (2^8 = 256). L’accumulateur de phase sera sur 32 bits pour une bonne résolution en fréquence.

#### **Table d’onde (look-up table)**

```c
#define LUT_SIZE 256
uint16_t sinLUT[LUT_SIZE];

void generate_sin_lut(void) {
    for (int i = 0; i < LUT_SIZE; i++) {
        // Valeur entre 0 et 4095, centrée sur 2048 pour un sinus bipolaire
        // On génère un sinus entre 0 et 4095 (offset 2048)
        float val = sinf(2 * M_PI * i / LUT_SIZE);
        sinLUT[i] = (uint16_t)((val + 1.0f) * 2047.5f); // 0..4095
    }
}
```























---
<br>


### **Liens connexes**


- [GPIO et Interruptions](../../stm32f4/gpio/index.md)
- [Timer et Interruption](../../stm32f4/timer/index.md)
- [Acquisition Analogique via ADC](../../stm32f4/adc/index.md)
- [Génération des signaux PWM](../../stm32f4/pwm/index.md)
- [Communication Série USART](../../stm32f4/usart/index.md)
- [Communication Série I2C](../../stm32f4/i2c/index.md)
- [Machine d’État Fini (FSM)](../../technique-algos/fsm/index.md)
- [Optimisation de Transfert des Données avec DMA](../../stm32f4/dma/index.md)

- [Filtres Numériques](../../technique-algos/filtre/index.md)
- [Introduction pratique à freeRTOS](../../rtos/#introduction-a-freertos)

