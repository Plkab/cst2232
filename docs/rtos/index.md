# Introduction aux Systèmes Temps Réels

*Ir Paul S. Kabidu, M.Eng. <spaulkabidu@gmail.com>*
{: style="text-align: center;" }

---

<br>

### **Les Systèmes Embarquées et Systèmes Digitaux**
  
Un **système embarqué** est un système numérique basé sur un processeur, généralement un microcontrôleur SoC (System On Chip). Il est conçu pour répondre à une **tâche spécifique et bien définie**. Il n'est ni généraliste ni polyvalent, contrairement à un PC qui doit savoir tout faire (bureautique, jeux, navigation web) ou à un smartphone qui exécute des applications diverses simultanément (banque, jeux, réseaux sociaux, outils de travail). 

La différence fondamentale entre les systèmes à base de microcontrôleurs et les ordinateurs de type PC réside dans leur **spécialisation** et leur **tâche dédiée**.
Un système embarqué peut toutefois reposer sur un **microprocesseur** plus puissant. Par exemple, le calculateur de conduite autonome (NVIDIA Drive) utilise la puissance d'un supercalculateur graphique (GPU) pour analyser en temps réel les flux de huit caméras, des radars et des lidars, et prendre des décisions de conduite. Dans ce cas, il n'exécute qu'une seule application, mais extrêmement exigeante.

Un système embarqué combine **matériel (hardware) et logiciel (software)** pour fonctionner. Il est optimisé pour une tâche unique et souvent critique, avec des contraintes de temps réel et de fiabilité. Ses principales caractéristiques sont :

- **Mémoire limitée** : on retrouve quelques kilo-octets comparés aux giga-octets des PC. C'est pour cette raison que le code doit donc être compact et efficace, le langages C/C++ est grandement privilégiés.

- **Consommation énergétique maîtrisée** : la plupart de ces systèmes sont autonomes en énergie, ils fonctionnent sur des batterie ou des piles.

- **Contraintes temporelles** : c'est-à-dire le délai de réponse est souvent critique (systèmes temps réel).

- **Fiabilité et robustesse** : ils doivent fonctionner sans intervention humaine pendant des années, parfois dans des environnements hostiles et délivrer toujours des bons resultats.

- **Interaction minimale** : l'interface avec le monde extérieur est réduite à l'essentiel pour sa fonction dédiée, soit un simple bouton poussoir est suffisant.
  
---

### **Les Systèmes Temps Réels**

Un système est dit **Temps Reel** lorsque les  résultats demeurent toujours pertitantes ou valides après leurs délivrance. Il ne suffit pas seulement de produire un résultat mais de le délivrer dans le délais requis faute de quoi il y aura des conséquences graves. 

La validité des résultats ne dépend pas seulement de la logique correcte du calcul, mais aussi du moment où ce résultat est produit. Prenons l'exemple du déclenchement d'un airbag lors d'un choc d'un vehicule : si le signal arrive ne serait-ce que 50 millisecondes après l'impact, le système est inutile et les conséquences pour le conducteur peuvent être graves. D'une autre facon on peut dire **si les résultats du systèmes produits sont corrects mais arrivent en retard, c'est-à-dire que le système a échoué, c'est équivalente à une défaillance**.

C'est pourquoi on joue sur le **determinisme**, la capacité à garantir un comportement **previsible** dans le temps, le temps est vraiement critique. Un système temps réel privilégie la déterminisme garantir qu'une tâche se terminera toujours en moins de X microsecondes non negociable. 

Pour gérer ces contraintes, deux approches sont possibles sur un processeur : 

- Utiliser le mécanisme des **interruptions matérielles**, géré directement par le CPU.
- Employer un **ordonnanceur** (scheduler) fourni par un système d'exploitation temps réel (RTOS) lorsqu'il faut coordonner plusieurs tâches avec des échéances prévisibles.


### Les trois types de systèmes temps réel 

On distingue classiquement trois catégories :

- **Systèmes temps réel stricts (Hard Real-Time)**
Dans ce type de système, le non-respect du delais entraine une catastophe ou une défaillance totale du système. 
Exemple : comme précédement cité, le déclenchement d'un airbag ou le système de freinage d'un train, commande de vol d'un avion. Si le signal arrive avec centaines de millisecondes de retard, le système est inutile.

- **Systèmes temps réel mous (Soft Real-Time)**
Pour ce type de système, léger retard est tolérable sans conséquences graves, même si l'on cherche toujours à respecter les délais. 
Exemple : Un distributeur automatique de billets (ATM). Si l'affichage met deux secondes de plus, l'utilisateur attend, mais le service est finalement rendu.

- **Systèmes temps réel fermes (Firm Real-Time)**
Ici le non-respect du délais rend le résultat inutile, cependant cela ne détruit pas le système. 
Exemple : Un flux vidéo en direct, un système de contrôle qualité sur une ligne de production. Si une image est traitée trop tard, on l'ignore et on passe à la suivante, mais la qualité globale diminue. ceci affecte directement la qualité du service du système.


---

### **Les Systèmes d'Exploitation Temps Réels**

---

### **Introduction à FreeRTOS** {#introduction-a-freertos}



---
<br>
  
### Lien connexe

- [Présentation architecturale du Microcontrôleur STM32F4](../stm32f4/mcu_intro/index.md)