# Philosophie du cours
{: style="text-align: center;" }

*Ir Paul S. Kabidu, M.Eng.*  
<spaulkabidu@gmail.com>
{: style="text-align: center;" }

---

[Accueil](/) | [Philosophie](.)

<br>

La philosophie de ce cours d'ingénierie repose sur l'étude du microcontrôleur choisi, son architecture, ses périphériques et l'interfaçage avec différents capteurs et actionneurs dans le but de concevoir des systèmes digitaux. Vu le niveau de complexité du système et la gestion du temps et des ressources, nous allons utiliser un système d'exploitation temps réel (RTOS) pour la coordination générale.

La programmation des drivers du microcontrôleur est faite en *bare metal* C (sans HAL) pour une compréhension totale de la puce, mais aussi pour des raisons pédagogiques. Utiliser le langage C permet d'être très proche du matériel et d'avoir un code plus optimisé à un certain niveau.

Nous allons fournir des codes drivers expliqués pour tous les périphériques utilisés dans ce cours. C'est sur base de ces derniers que l'on va commencer à construire des systèmes complexes en temps réel.

Chaque étudiant, à son tour, devra être capable de construire des systèmes digitaux sur base du microcontrôleur tout en utilisant un RTOS. Il devra implémenter tout un système depuis les équations mathématiques et physiques, en passant par le codage, pour enfin atterrir dans une puce et faire fonctionner du matériel.

Le système construit devra répondre à un cahier des charges prédéfini, à une problématique quelconque. Nous construisons des systèmes pour résoudre un problème ou bien nous aider à résoudre des problèmes dans la vie quotidienne. Dans ce cours, les problèmes à résoudre sont de divers domaines d'ingénierie : de la biologie en passant par la physique et la robotique jusqu'à l'aérospatiale.

Seule notre imagination est notre limite.

---

### Liens connexes

- [Introduction aux systèmes temps réel](rtos/index.md)
- [Présentation du microcontrôleur STM32F4](stm32f4/mcu_intro/index.md)
- [Retour à l'accueil](index.md)