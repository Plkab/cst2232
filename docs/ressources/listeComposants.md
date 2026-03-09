# Liste des composants du cours CST2232

*Ir Paul S. Kabidu, M.Eng. <spaulkabidu@gmail.com>*
{: style="text-align: center;" }

---

[Accueil](../../#Accueil)

<br>
<br>



### **Introduction**

Cette page récapitule l'ensemble du **matériel nécessaire** pour suivre le cours CST2232 dans son intégralité. Les composants sont organisés par catégorie fonctionnelle afin de faciliter la préparation des kits pédagogiques.

---
<br>

### **1. Carte de développement principale (MCU)**

| Composant | Référence / Modèle | Quantité | Description / Rôle dans le cours |
|-----------|-------------------|----------|--------------------------------|
| **Carte Black Pill** | WeAct Studio Black Pill V3.0 (STM32F401CCU6) | 1 par étudiant | Carte principale du cours. Basée sur STM32F401CCU6 (Cortex-M4, 84 MHz, 256 Ko Flash, 64 Ko SRAM). Supporte FreeRTOS et tous les périphériques étudiés. |

---
<br>

### **2. Programmation et débogage**

| Composant | Référence / Modèle | Quantité | Description / Rôle dans le cours |
|-----------|-------------------|----------|--------------------------------|
| **Programmateur ST-LINK V2** | ST-LINK V2 (clone ou officiel) | 1 pour 2 étudiants | Programmation et débogage via SWD. Interface 4 fils : SWDIO, SWCLK, GND, 3.3V. |
| **Câble USB** | USB-C vers USB-A | 1 | Alimentation de la carte et communication série (USART2). |

---
<br>

### **3. Capteurs et modules de mesure**

| Composant | Référence / Modèle | Quantité | Description / Rôle dans le cours |
|-----------|-------------------|----------|--------------------------------|
| **Centrale inertielle (IMU)** | MPU6050 (GY-521) | 1 | Accéléromètre 3 axes + gyroscope 3 axes. Communication I2C. Utilisé pour l'estimation d'angle (filtre complémentaire/Kalman). |
| **Capteur de température** | LM75 ou DS1621 | 1 | Capteur de température avec interface I2C. Utilisé pour le projet de lecture I2C. |
| **Module GPS** | NEO-6M / NEO-7M | 1 | Récepteur GPS avec interface UART. Utilisé pour le projet de parsing NMEA et affichage Python. |
| **Potentiomètre** | 10 kΩ linéaire | 3-4 | Génération de tension analogique variable pour les TP ADC (consigne de vitesse, contrôle de fréquence, etc.). |

---
<br>

### **4. Actionneurs et contrôle moteur**

| Composant | Référence / Modèle | Quantité | Description / Rôle dans le cours |
|-----------|-------------------|----------|--------------------------------|
| **Moteur DC avec encodeur** | JGA25-370 (6V/12V) avec encodeur Hall | 1-2 | Moteur à courant continu avec encodeur quadrature. Utilisé pour l'asservissement PID (régulation de vitesse). |
| **Driver moteur (pont en H)** | L298N ou TB6612 | 1 | Pilotage du moteur DC à partir des signaux PWM du STM32. |
| **Servomoteur** | SG90 ou MG996R | 1 | Servomoteur standard commandé par PWM (projet DDS / positionnement). |

---
<br>

### **5. Communication et connectivité**

| Composant | Référence / Modèle | Quantité | Description / Rôle dans le cours |
|-----------|-------------------|----------|--------------------------------|
| **Module Wi-Fi** | ESP8266 (ESP-01) | 1 | Module Wi-Fi avec interface UART (commandes AT). Utilisé pour l'IoT et le monitoring industriel. |
| **Module Bluetooth** (optionnel) | HC-05 / HC-06 | 1 | Alternative pour communication sans-fil locale. |
| **Module CAN** (optionnel) | MCP2515 + TJA1050 | 1 | Pour les TP sur le bus CAN (communication entre deux cartes). |

---
<br>

### **6. Conversion numérique-analogique (DAC)**

| Composant | Référence / Modèle | Quantité | Description / Rôle dans le cours |
|-----------|-------------------|----------|--------------------------------|
| **DAC externe SPI** | MCP4822 (double 12 bits) | 1 | Convertisseur numérique-analogique pour la synthèse DDS (génération de signaux) car le STM32F401 n'a pas de DAC interne. |

---
<br>

### **7. Affichage et interface utilisateur**

| Composant | Référence / Modèle | Quantité | Description / Rôle dans le cours |
|-----------|-------------------|----------|--------------------------------|
| **Écran TFT couleur** | ILI9488 (320x480, SPI) | 1 | Écran TFT couleur pour le graphisme embarqué et l'affichage de données. |
| **Module OLED** (optionnel) | SSD1306 (I2C) | 1 | Alternative plus simple pour l'affichage. |
| **Boutons poussoirs** | Boutons tactiles 6x6mm | 4-5 | Entrées utilisateur pour menus, calibration, reset. |
| **Encodeur rotatif** | Encodeur incrémental avec bouton | 1 | Interface de réglage précis. |

---
<br>

### **8. Stockage et horodatage**

| Composant | Référence / Modèle | Quantité | Description / Rôle dans le cours |
|-----------|-------------------|----------|--------------------------------|
| **Carte microSD + adaptateur SPI** | Module lecteur microSD (SPI) | 1 | Stockage local de données (datalogger). |

---
<br>

### **9. Composants passifs et conditionnement**

| Composant | Valeur / Référence | Quantité | Description / Rôle |
|-----------|--------------------|----------|---------------------|
| **Résistances** | 220 Ω, 1 kΩ, 4,7 kΩ, 10 kΩ | Lot | LEDs, pull-up I2C, ponts diviseurs. |
| **Condensateurs** | 100 nF, 10 µF | Lot | Filtrage d'alimentation, découplage. |
| **LEDs** | Rouge, verte, jaune | 5-10 | Indication visuelle (état, debug). |
| **Résistances de tirage (pull-up)** | 4,7 kΩ (pour I2C) | Lot | Obligatoires pour le bus I2C (MPU6050, LM75, etc.). |

---
<br>

### **10. Alimentation**

| Composant | Spécification | Quantité | Description |
|-----------|---------------|----------|-------------|
| **Alimentation secteur** | 12V / 2A (ou 5V / 3A) | 1 | Alimentation principale pour la carte et les moteurs. |
| **Câbles d'alimentation** | Jack DC / bornier | 1 | Connexion alimentation. |

---
<br>

### **11. Outillage et consommables**

| Élément | Description |
|---------|-------------|
| **Câbles Dupont** | Lot de câbles femelle-femelle, femelle-mâle, mâle-mâle (au moins 40 de chaque). |
| **Breadboard** | Platine d'expérimentation sans soudure (400-800 points). |
| **Oscilloscope** | (1 pour 2-3 étudiants) Pour visualisation des signaux PWM, I2C, UART, mesure de gigue. |
| **Analyseur logique** | Optionnel mais recommandé (ex: 8 canaux 24 MHz). |
| **Multimètre** | (1 par étudiant idéalement) Pour vérification des tensions et continuité. |
| **Fer à souder + étain** | Pour les montages définitifs (optionnel). |

---
<br>

### **Récapitulatif par projet / TP**

| Projet / TP | Composants spécifiques utilisés |
|-------------|--------------------------------|
| **TP GPIO & Interruptions** | Bouton, LED, résistances. |
| **TP Timer & PWM** | LED (pour visualisation PWM), oscilloscope. |
| **TP ADC** | Potentiomètre. |
| **TP UART** | Câble USB, terminal série PC. |
| **TP I2C** | MPU6050 (IMU), résistances de pull-up 4,7 kΩ. |
| **TP SPI** | MCP4822 (DAC), écran TFT ILI9488 (optionnel). |
| **TP CAN** | Deux cartes Black Pill + modules MCP2515. |
| **Projet PID (moteur)** | Moteur DC avec encodeur, driver L298N, potentiomètre. |
| **Projet DDS** | MCP4822 (DAC), potentiomètre, écran TFT ou PC (Python). |
| **Projet GPS** | Module GPS NEO-6M, câble USB. |
| **Projet IoT** | Module ESP8266. |
| **Projet IMU + Filtre de Kalman** | MPU6050, résistances pull-up. |
| **Laboratoire final** | Combinaison selon projet choisi (ex: IMU + PID, GPS + IoT, etc.). |

---
<br>

### **Liens connexes**

- [Accueil](../../#Accueil)
- [Philosophie du cours](../../philosophie/index.md)
- [Ressources et références](../../ressources/index.md)

---