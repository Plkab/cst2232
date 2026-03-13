# CST2232, Conception des Systèmes Temps Réel à Base de Microcontrôleur 

*Ir Paul S. Kabidu, M.Eng.*  
Enseignant au Département de Génie Électrique et Informatique  
Institut Supérieur des Techniques Appliquées de Goma (ISTA)  
Contact : [spaulkabidu@gmail.com](mailto:spaulkabidu@gmail.com)  
{: style="text-align: center;" }

---
<br>
 <br> 
 

Le **cours CST2232 – Conception de Systèmes Temps Réel à Base de Microcontrôleur** s’adresse aux étudiants du **Master en Génie Logiciel Industriel** de l’ISTA. Il a pour ambition de former des ingénieurs capables de concevoir et de réaliser des systèmes embarqués temps réel complets, en intégrant à la fois les aspects matériels (microcontrôleurs, capteurs, actionneurs) et logiciels (programmation bas niveau, RTOS, algorithmes de contrôle et de traitement du signal).

L’approche pédagogique adoptée est celle d’une **expérience de conception cumulative (Cumulative Design Experience – CDE)** : chaque chapitre apporte une brique nouvelle et les projets finaux synthétisent l’ensemble des connaissances. À l’issue de ce cours, vous serez capable de :

- Concevoir un firmware temps réel structuré sur microcontrôleur STM32F4.
- Maîtriser un système d’exploitation temps réel (FreeRTOS) et ses primitives (tâches, queues, sémaphores, mutex).
- Implémenter des algorithmes de contrôle (PID) et de traitement numérique du signal (filtres, FFT).
- Intégrer des périphériques de communication (UART, I2C, SPI, CAN) et des modules sans fil (ESP8266).
- Réaliser des interfaces homme-machine et des systèmes connectés (IoT).  

---
<br>



### Accueil {#Accueil} 
  
- [Philosophie du cours](philosophie/index.md)
- [Introduction aux Systèmes Temps Réels](rtos/index.md)
- [Introduction pratique à FreeRTOS](rtos/freertos.md)
- [Présentation architecturale du Microcontrôleur STM32F4](stm32f4/mcu_intro/index.md)

---
<br>



### Périphériques du STM32F4
- [GPIO et Interruptions](stm32f4/gpio/index.md)
- [Timer et Interruption Matérielles ](stm32f4/timer/index.md)
- [Acquisition Analogique via ADC](stm32f4/adc/index.md)
- [Génération des signaux PWM](stm32f4/pwm/index.md)
- [Optimisation de Transfert des Données avec DMA](stm32f4/dma/index.md)

**Communication Série**

- [Communication Série USART](stm32f4/usart/index.md)
- [Communication Série I2C](stm32f4/i2c/index.md)
- [Communication Série SPI](stm32f4/spi/index.md)
- [Communication Série CAN](stm32f4/can/index.md)
- [Communication Série USB](stm32f4/usb/index.md)

---
<br>


### Algorithmes et Techniques de Programmation
- [Machine d’État Fini (FSM)](technique-algos/fsm/index.md)
- [Contrôle Numérique avec PID](technique-algos/pid/index.md)
- [Estimation d’État et Fusion Capteurs](technique-algos/estimation/index.md)
- [Filtres Numériques](technique-algos/filtre/index.md)
- [Analyse fréquentielle avec FFT](technique-algos/fft/index.md)
- [Synthèse Numérique Directe (DDS) avec DAC externe MCP4822](technique-algos/dds/index.md)
- [Bases du Graphisme Embarqué sur écran TFT ili9488 3.2](technique-algos/graphisme/index.md)

---
<br>



### Projets d’Application


**Contrôle et Systèmes Dynamiques**
- [Régulation de vitesse d’un moteur DC avec PID](projects/moteurPID/index.md)
- [Filtrage des données du IMU 6050 via Filtre de Kalman](projects/imu_klf/index.md)
- [Filtrage des données du IMU 6050 via Filtre Complémentaire](technique-algos/estimation/#projet-estimation-angle)
- [Stabilisation dynamique d’un pendule inversé]()


**Traitement du Signal Numérique (DSP) Synthèse Sonore**
- [Analyse spectrale d’un signal audio avec FFT](technique-algos/fft/#projet-fft-audio)
- [Générateur audio DDS via DAC SPI]()
- [Générateur de signaux DDS : Frequencemetre sur TFT](projects/dds_frequencemetre/index.md)
- [Synthèse bio-inspirée (chants d’oiseaux)]()


**Graphique Embarqué et Visualisation**
- [TFT graphics / primitives graphiques]()
- [VGA graphics / primitives graphiques]()
- [Lecture GPS et affichge sur GUI Python](projects/gps/index.md) : parsing NMEA, extraction de la position, envoi sur UART, interface graphique Tkinter avec mise à jour temps réel.


**Simulation Scientifique et Systèmes Complexes**
- [Simulation de comportements collectifs]()
- [Simulation de nuée d’oiseaux (Boids)]()
- [Boids avec prédateur]()
- [Systèmes chaotiques de Lorenz]()
- [Analyse statistique en temps réel (collecte de données capteurs, calcul de moyenne, corrélation, variance et histogrammes en temps réel)]()
- [Modélisation thermique temps réel : mesure et simulation de diffusion de chaleur sur microprocesseur]()


**Interfaces Capteurs et Périphériques**
- [Système de Contrôle de LED Multimode avec Interruption, Sémaphore et File de Messages](stm32f4/gpio/index.md#projet-gpio-interrupt-freertos-multimode) : Un projet complet synthétisant GPIO, Interruptions EXTI, Sémaphores et Files de messages sous FreeRTOS.
- [Pilote graphique de l'afficheur TFT ili9488 3.2](technique-algos/tftili9488/index.md)
- [Pilote graphique de l'afficheur de l'écran VGA](technique-algos/vga/index.md)
- [claviers matriciels]()
- [Interface DAC SPI]()
- [Interface ADC]()


**Systèmes de Communications Embarquées et IOT**
- [Serveur Web embarqué avec ESP-01 : Instrument de laboratoire spectromètre](projects/esp01/index.md)


**Architecture Microcontrôleur Avancée**
- [Bootloader série personnalisé]()
- [Gestion avancée DMA]()


**Intelligence Artificielle Embarquée**
-[Reconnaissance de gestes via IMU]()

---
<br>



### Laboratoires 2026
- [Labo 1 – Stabilisation Plate-Forme dynamique](labos/stabilisation1.md)
- [Labo 2 – Analyse vibratoire avec FFT](labos/fft1.md)
- [Labo Final](labos/laboFinal.md)

---
<br>



### Ressources et Références

**Documentation technique**

- [Manuel de Références pour STM32F4](https://www.st.com/resource/en/reference_manual/rm0368-stm32f401xbc-and-stm32f401xde-advanced-armbased-32bit-mcus-stmicroelectronics.pdf)
- [Manuel de Références RM0390 pour STM32F4](https://www.st.com/resource/en/reference_manual/dm00135183.pdf)
- [Datasheet de STM32F401x](https://www.st.com/resource/en/datasheet/stm32f401re.pdf)
- [Manuel de Références pour Cortex-M](https://documentation-service.arm.com/static/5e8f224c7100066a414f7810?token=)
- [The FreeRTOS Reference Manual ](https://www.freertos.org/media/2018/FreeRTOS_Reference_Manual_V10.0.0.pdf)
- [Mastering the FreeRTOS Real Time Kernel par Richard Barry](https://www.freertos.org/media/2018/161204_Mastering_the_FreeRTOS_Real_Time_Kernel-A_Hands-On_Tutorial_Guide.pdf)

**Guides pratiques**

- [Création Projet sous Keil uVision](ressources/demarrerKiel.md)
- [Configuration FreeRTOS sous Kiel pour STM32F4](ressources/configRtosKiel.md)
- [Liste des composants du cours CST2232](ressources/listeComposants.md)
- [Introduction au Langage C embarqué](ressources/langageC.md)
- [Codes source Github](https://github.com/Plkab/code-demo-cours)
<br>

