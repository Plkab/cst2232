# CST2232, Conception des Systèmes Temps Réel à Base de Microcontrôleur
##### Ir Paul S. Kabidu, Enseignant à l'Institut Supérieur des Techniques Appliquées de Goma (ISTA) dans le departement de génie électrique et Informatique

---

La Conception des Systèmes Embarqués Temps Réel à base du Microcontrôleur est un cours qui a pour objectif de former les étudiants à la conception de systèmes électroniques, avec un accent sur le développement multi-capteurs, le contrôle numérique, le traitement numérique du signal et la communication IoT.

Ce cours CST2232 est élaboré pour les étudiants en **Master en Génie Logiciel Industriel à l'Institut Supérieur des Techniques Appliquées de Goma (ISTA)**. Ce cours suit l'approche **d'expérience de conception culminante (CDE, Cumulative Design Experience)**. Il est conçu pour permettre aux étudiants de synthétiser et d'appliquer l'ensemble des connaissances acquises durant leurs études pour résoudre des problèmes réels et complexes.

À l’issue de ce cours, l’étudiant sera capable de :
- Concevoir un firmware temps réel structuré sur le microcontrôleur STM32F4
- Maîtriser FreeRTOS (tâches, queues, sémaphores, mutex)
- Implémenter des algorithmes de contrôle et de traitement de données en temps réel.
- Réaliser des interfaces homme-machine et des systèmes connectés.


---

- [Introduction aux Systèmes Temps Réels](rtos/index.md)
- [Présentation architecturale du Microcontrôleur STM32F4](stm32f4/mcu_intro/index.md)

---

### Périphériques STM32F4
- [GPIO et Interruptions](stm32f4/gpio/index.md)
- [Timer et Interruption](stm32f4/timer/index.md)
- [Acquisition Analogique via ADC](stm32f4/adc/index.md)
- [Communication Série USART](stm32f4/usart/index.md)
- [Communication Série I2C](stm32f4/i2c/index.md)
- [Communication Série SPI](stm32f4/spi/index.md)
- [Communication Série CAN](stm32f4/can/index.md)
- [Optimisation de Transfert des Données avec DMA](stm32f4/dma/index.md)

---

### Techniques de Programmation et Algorithmes
- [Machine d’État Fini (FSM)](technique-algos/fsm/index.md)
- [Contrôle Numérique avec PID](technique-algos/pid/index.md)
- [Estimation d’État et Fusion Capteurs](technique-algos/estimation/index.md)
- [Filtres Numériques](technique-algos/filtre/index.md)
- [Analyse fréquentielle avec FFT](technique-algos/fft/index.md)
- [Synthèse Numérique Directe (DDS)](technique-algos/dds/index.md)
- [Bases du Graphisme Embarqué](technique-algos/graphisme/index.md)

---

### Projets d’Application
- [Filtrage des données du IMU 6050 via Filtre Complémentaire](projects/imu_compl/index.md)

---

### Laboratoires 2026
- [Labo 1 – Stabilisation Plate-Forme dynamique](labos/stabilisation1.md)
- [Labo 2 – Monitoring Industriel via ESP8266](labos/monitoringEsp8266.md)
- [Labo 3 – Analyse vibratoire avec FFT](labos/fft1.md)

---

### Ressources et Références
- [Manuel de Références pour STM32F4](ressources/rfm1.md)
- [Manuel de Références pour Cortex-M](ressources/rfm2.md)
- [Manuel de Références pour FreeRTOS](ressources/freeRTOS.md)
- [Création Projet sous Keil uVision](ressources/demarrerKiel.md)
- [Configuration FreeRTOS ous Kiel pour STM32F4](ressources/configRtosKiel.md)
- [Introduction au Langage C embarqué](ressources/langageC.md)
- [Codes source Github](https://github.com/Plkab/code-demo-cours)

---
