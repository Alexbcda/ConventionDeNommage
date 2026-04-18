# PdfPlanningOptimizer — Contrat métier (grouping WorkOrder)

Document contractuel officiel. Il décrit le comportement **effectif** du regroupement `PageEntity` → `WorkOrderEntity` tel qu’implémenté dans `PageEntityAggregator.ps1` et verrouillé par `Test/PdfPlanningOptimizer.Tests.ps1`. Toute évolution du code ou des tests qui contredirait ce document constitue un **changement de contrat** explicite.

**Périmètre :** machine d’état et règles de `groupKey` pour `Group-PagesBySequentialWorkOrder` / `ConvertTo-WorkOrderEntityList`. Hors périmètre : extraction PDF, Excel, fuzzy matching, orchestration amont.

---

## 1. State machine (`currentWorkOrder`)

### 1.1 Source de vérité unique

Pour chaque page (dans l’ordre croissant de `PageNumber` après tri), la clé de groupement `groupKey` est **exclusivement** dérivée de `currentWorkOrder` après application des transitions ci-dessous :

- si `currentWorkOrder` est non vide → `groupKey = currentWorkOrder` ;
- sinon → `groupKey = '__UNSPECIFIED__'` (constante interne unique).

Aucune autre source (lecture globale du document, ancre, pivot, voisinage, post-traitement) n’intervient sur `groupKey`.

### 1.2 Règles de transition (par page, dans l’ordre)

Sur la page courante `P` :

1. **Champ `PageEntity.WorkOrder`**  
   Si non vide (après trim logique via `Test-IsNonEmptyString`) :  
   `currentWorkOrder ← P.WorkOrder.Trim()`  
   → la valeur explicite de la page **remplace** l’état porté, quelle qu’elle soit.

2. **Sinon — préfixe ODM**  
   Si `Get-OdmWorkOrderPrefixFromPage(P)` retourne une chaîne non vide :  
   `currentWorkOrder ←` ce préfixe.  
   → s’applique **uniquement** lorsque le champ `WorkOrder` de la page n’est pas considéré comme renseigné à l’étape 1.  
   → peut donc mettre à jour `currentWorkOrder` même si celui-ci était déjà non vide (héritage d’une page précédente).

3. **Sinon — héritage strict**  
   Aucune assignation : `currentWorkOrder` reste inchangé.

### 1.3 Interdiction de retour à `$null` après initialisation

Le code **n’affecte jamais** `currentWorkOrder` à `$null` après une valeur non vide : seules les mises à jour des cas (1) et (2) modifient la variable ; le cas (3) la laisse telle quelle. Dès qu’un premier signal (WO ou ODM) a initialisé `currentWorkOrder`, les pages suivantes sans signal conservent la dernière valeur connue.

### 1.4 Ordre d’évaluation (clarification « WO actif » vs ODM)

Sur **une même page**, le champ `WorkOrder` est toujours évalué **avant** l’ODM : l’ODM ne « définit » pas la transition de cette page si `WorkOrder` est non vide. En revanche, sur une page **sans** `WorkOrder` non vide, un préfixe ODM extrait **met à jour** `currentWorkOrder` selon le §1.2, indépendamment du fait que l’état courant provienne d’un WO ou d’un ODM d’une page antérieure.

---

## 2. Règles de grouping

### 2.1 `__UNSPECIFIED__`

- La clé interne `__UNSPECIFIED__` est utilisée **uniquement** lorsque, **après** les transitions de la page courante, `currentWorkOrder` est encore vide (`$null` ou chaîne vide au sens `Test-IsNonEmptyString`).
- En pratique : pages **strictement avant** le premier signal WorkOrder ou ODM sur le document (ordonnancement par `PageNumber`).
- **Aucun** merge ni post-traitement ne rattache ensuite ces pages à un autre groupe : pas de « migration » rétroactive vers un WO.

### 2.2 Séparation stricte entre WorkOrders différents

- Un changement de `PageEntity.WorkOrder` explicite (valeur distincte) sur une page ultérieure produit une nouvelle valeur de `currentWorkOrder` et donc un nouveau `groupKey` lorsque cette page est traitée.
- Deux identifiants de commande distincts portés explicitement sur des pages différentes donnent **deux** groupes distincts (deux `WorkOrderEntity` après agrégation), sauf cas où la valeur serait identique (même chaîne).

### 2.3 Interdiction de fusion inter-WO

- Le grouping **ne fusionne pas** des pages appartenant à des clés de groupe différentes : chaque page est ajoutée exactement à la liste du groupe identifié par son `groupKey` calculé à son tour de boucle.
- Pas de passe globale pour « corriger » ou regrouper des clés distinctes après coup.

---

## 3. Règles ODM (`Get-OdmWorkOrderPrefixFromPage`)

### 3.1 Forme canonique (prioritaire)

Pour chaque entrée de service avec clé `ODM` non vide, dans l’ordre d’itération :

- correspondance **prioritaire** par expression régulière :  
  `^\s*(\d{7})-\d+\s*$`  
  → le préfixe retourné est le groupe capturant **7 chiffres** (les `xxxx` après le tiret sont au moins un chiffre via `\d+`).

### 3.2 Retombée (fallback)

Si la regex ne correspond pas :

- la valeur `ODM` est découpée sur le **premier** `-` (au plus 2 segments) ;
- si le premier segment est une chaîne non vide après trim, il est retourné comme préfixe.

Ce second chemin autorise des formes **non strictement** `7digits-xxxx` pour autant que le premier segment soit non vide ; le contrat documente le comportement **réel** du code.

### 3.3 Première valeur non vide

La fonction retourne le préfixe issu du **premier** service de la page pour lequel une règle ci-dessus produit une valeur.

### 3.4 Rapport avec le champ `WorkOrder` de la page

L’extraction ODM n’est utilisée pour la transition d’état **que si** le champ `WorkOrder` de la page n’est pas considéré comme renseigné (§1.2). Il n’y a pas de logique « ODM ignoré parce qu’un WO serait déjà actif par héritage » : l’absence de `WorkOrder` **non vide** sur la page suffit pour appliquer l’ODM.

---

## 4. Invariants

### 4.1 Une page, un groupe

Chaque `PageEntity` non nulle traitée dans la boucle est ajoutée **une fois** à exactement **une** liste de groupe (clé `currentWorkOrder` ou `__UNSPECIFIED__`). Elle apparaît donc dans un seul `WorkOrderEntity` après `ConvertTo-WorkOrderEntityList`.

### 4.2 Ordre des pages

- Les pages sont triées par `PageNumber` croissant avant le grouping.
- Les numéros de pages dans chaque `WorkOrderEntity` reflètent les pages du groupe (ordre déterminé par l’agrégateur en aval).

### 4.3 Aucune rétro-propagation

Les décisions pour une page `N` ne dépendent que de l’état `currentWorkOrder` **après** les pages `< N` et des champs de la page `N`. Aucune page `M > N` ne modifie le groupe déjà attribué à `N`.

---

## 5. Anti-patterns interdits (pour ce périmètre)

Les éléments suivants ne font **pas** partie du contrat du grouping actuel et ne doivent pas y être réintroduits sans révision explicite du contrat :

| Anti-pattern | Statut |
|--------------|--------|
| Fuzzy matching pour le regroupement par WO | Interdit |
| Heuristiques Excel (ou autre source externe) dans le grouping | Interdit |
| Re-anchoring, pivot, voisinage ±1, lecture globale du document pour « réparer » les clés | Interdit |
| Merge post-traitement des groupes `__UNSPECIFIED__` avec un WO | Interdit |

---

## 6. Références

| Élément | Emplacement |
|---------|-------------|
| State machine et `groupKey` | `src/ODM/PdfPlanningOptimizer/Services/PageEntityAggregator.ps1` — `Group-PagesBySequentialWorkOrder`, `Get-OdmWorkOrderPrefixFromPage` |
| Construction des entités | Même fichier — `ConvertTo-WorkOrderEntityList`, `Build-WorkOrderEntityFromGroup` |
| Non-régression | `Test/PdfPlanningOptimizer.Tests.ps1` |

---

*Version du contrat alignée sur l’implémentation et les tests au moment de la rédaction. Toute modification du fichier de code ou des tests de non-régression peut exiger une mise à jour maîtrisée de ce document.*
