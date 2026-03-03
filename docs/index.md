# CST2232, Conception des Systèmes Temps Réel à Base de Microcontrôleur

![Bannière du cours](images/banner.jpg){ align=center width=800 }

Ce cours a pour objectif de **former les étudiants à la conception de systèmes embarqués temps réel à base du microcontrôleur STM32F4**, avec un accent sur le développement multi-capteurs, le contrôle numérique et la communication IoT.

Ce cours CST2232 est élaboré pour les étudiants en **Master en Génie Logiciel Industriel à l'Institut Supérieur des Techniques Appliquées de Goma (ISTA)**. Ce cours suit l'approche **d'expérience de conception culminante (CDE, Cumulative Design Experience)**. Il est conçu pour permettre aux étudiants de synthétiser et d'appliquer l'ensemble des connaissances acquises durant leurs études pour résoudre des problèmes réels et complexes.

## Objectifs Pédagogiques

À l’issue du cours, l’étudiant sera capable de :
- Concevoir un firmware temps réel structuré sur le microcontrôleur STM32F4
- Maîtriser FreeRTOS (tâches, queues, sémaphores, mutex)
- Implémenter des algorithmes de contrôle et de traitement de données en temps réel.
- Réaliser des interfaces homme-machine et des systèmes connectés.


# Navigation
nav:
  - Présentation du Cours: index.md
  - Introduction aux Systèmes Temps Réels: rtos/index.md
  - Présentation du Microcontrôleur STM32F4 : mcu/index.md
  - Présentation des Périphériques: 
    - Le GPIO et les Interruptions Materielles: stm32f4/gpio/index.md
    - Le Timer et interruption: stm32f4/timer/index.md
    - L'acquisition analogique via ADC: stm32f4/adc/index.md
    - La Communication série USART: stm32f4/usart/index.md
    - La Communication série I2C: stm32f4/i2c/index.md
    - La Communication série SPI: stm32f4/spi/index.md
    - La Communication série CAN: stm32f4/can/index.md
    - Optimisation avec DMA: stm32f4/dma/index.md
  - Techniques de Programmation et Algorithmes: 
    - Machine d'Etat Fini (FSM): fsm/index.md
    - Contrôle Numérique avec PID: pid/index.md
    - Estimation d'Etat et Fusion Capteurs: estimation/index.md
    - Les Filtres Numériques: filtre/index.md
    - Analyse fréquentielle avec FFT: fft/index.md
    - La Synthèse Numérique Directe (DDS): dds/index.md
    - Les bases du graphisme embarqué: graphisme/index.md
  - Projets d'Application:
    - Filtrage des Données du IMU 6050 via Filtre Complémentaire: projects/imu_compl/index.md
  - Laboratoires 2026:
    - Labo 1 - Stabilisation d'une Plate-Forme: labos/stabilisation1.md
    - Labo 2 - Monitoring Industriel Via Esp8266: labos/monitoringEsp8266.md
    - Labo 3 - Analyse vibratoire: labos/fft1.md
  - Ressources et Références:
    - Installation: ressources/installation.md
    - Datasheets: ressources/datasheets.md
    - Manuel de Référence STM32F4: ressources/rfm1.md
    - Manuel de Référence Cortex-M: ressources/rfm2.md
    - Manuel de Référence freeRTOS: ressources/freeRTOS.md
    - Création Projet Sous Kiel uVision: ressources/demarrerKiel.md
    - Configuration de freeRTOS Pour Le STM32F4: ressources/configRtosKiel.md
    - Introduction au Langage C Embarqué: ressources/langageC.md
    - Code source: https://github.com/Plkab/code-demo-cours