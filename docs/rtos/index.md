# Introduction aux Systèmes Temps Réels

*Ir Paul S. Kabidu, M.Eng. <spaulkabidu@gmail.com>*
{: style="text-align: center;" }

---

<br>

### Les Systèmes Embarquées et Systèmes digitaux

Un **système embarqué** est un système numérique basé sur un processeur, généralement un microcontrôleur SoC (System On Chip). Il est conçu pour répondre à une **tâche spécifique et bien définie**. Il n'est ni généraliste ni polyvalent, contrairement à un PC qui doit savoir tout faire (bureautique, jeux, navigation web) ou à un smartphone qui exécute des applications diverses simultanément (banque, jeux, réseaux sociaux, outils de travail). 

La différence fondamentale entre les systèmes à base de microcontrôleurs et les ordinateurs de type PC réside dans leur **spécialisation** et leur **tâche dédiée**.
Un système embarqué peut toutefois reposer sur un **microprocesseur** plus puissant. Par exemple, le calculateur de conduite autonome (NVIDIA Drive) utilise la puissance d'un supercalculateur graphique (GPU) pour analyser en temps réel les flux de huit caméras, des radars et des lidars, et prendre des décisions de conduite. Dans ce cas, il n'exécute qu'une seule application, mais extrêmement exigeante.

Un système embarqué combine **matériel (hardware) et logiciel (software)** pour fonctionner. Il est optimisé pour une tâche unique et souvent critique, avec des contraintes de temps réel et de fiabilité. Ses principales caractéristiques sont :

- **Mémoire limitée** : on retrouve quelques kilo-octets comparés aux giga-octets des PC. C'est pour cette raison que le code doit donc être compact et efficace, le langages C/C++ est grandement privilégiés.

- **Consommation énergétique maîtrisée** : la plupart de ces systèmes sont autonomes en énergie, ils fonctionnent sur des batterie ou des piles.

- **Contraintes temporelles** : c'est-à-dire le délai de réponse est souvent critique (systèmes temps réel).

- **Fiabilité et robustesse** : ils doivent fonctionner sans intervention humaine pendant des années, parfois dans des environnements hostiles et délivrer toujours des bons resultats.

- **Interaction minimale** : l'interface avec le monde extérieur est réduite à l'essentiel pour sa fonction dédiée, soit un simple bouton poussoir est suffisant.

### Les Systèmes Temps réels


### Les Systèmes d'Exploitation Temps réels


### Introduction à FreeRTOS



---
<br>
  
### Lien connexe

- [Présentation architecturale du Microcontrôleur STM32F4](stm32f4/mcu_intro/index.md)