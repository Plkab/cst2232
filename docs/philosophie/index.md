# Philosophie du cours

*Ir Paul S. Kabidu, M.Eng. <spaulkabidu@gmail.com>*
{: style="text-align: center;" }

---

<br>

La philosophie de ce cours d'ingénierie repose sur l'étude approfondie du microcontrôleur : son architecture, ses périphériques et son interaction avec capteurs et actionneurs, dans le but de concevoir des systèmes numériques complets. Face à la complexité croissante des systèmes embarqués et aux contraintes temporelles sévères, nous utiliserons un **système d'exploitation temps réel (RTOS)** pour orchestrer l'ensemble des tâches.

La programmation des drivers du microcontrôleur est réalisée en **C bare metal**, c'est-à-dire sans utiliser de couche d'abstraction matérielle (HAL). Ce choix, délibérément pédagogique, vise à acquérir une **compréhension totale** de la puce. Il permet aussi à avoir un **code plus optimisé** et plus proche du matériel, egalement à évelopper une **autonomie et libérté** face à la documentation technique.

Pour chaque périphérique abordé, des **codes drivers commentés** seront fournis et expliqués. C'est sur ces bases solides que nous construirons progressivement des systèmes temps réel complexes.

Chaque étudiant, à son tour, devra être capable de **concevoir et réaliser un système numérique complet** à partir d'un cahier des charges tout en utilisant un RTOS. Il devra suivre une démarche d'ingénieur complète. Cela implique une comprehension réelle du mode physique, des signaux réels, en **modélisant** un problème sous forme d'équations mathématiques et physiques; en **concevant** une architecture logicielle (découpage en tâches, choix des mécanismes de communication). Par après l'**implémenter** en code en C, en intégrant les drivers et le RTOS et puis enfin le **valider** le fonctionnement sur la cible matérielle (STM32F4):

Le système final construit devra répondre à un cahier des charges prédéfini, à une problématique concrète, issue de domaines variés : de la biologie en passant par la physique et la robotique, aérospatiale, etc.

Nous ne programmons pas pour programmer. Nous construisons des systèmes pour résoudre des problèmes, pour nous aider dans la vie quotidienne, pour explorer de nouveaux champs d'application. Les défis abordés dans ce cours couvrent un large spectre de l'ingénierie, mais un principe demeure :
  
Seule notre imagination est notre limite.

---
<br>
  
### Lien connexe

- [Introduction aux Systèmes Temps Réels](../rtos/index.md)
