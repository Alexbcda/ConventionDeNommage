# ArchitectureGuard

**Single Source of Truth = EntityTourneeMergeEngine** (`Merge-EntityTournees`).

Verrou d’architecture pour le module PdfPlanningOptimizer : **`EntityTourneeMergeEngine.ps1`** et **`Merge-EntityTournees`** constituent la **seule** agrégation Excel + PDF / `ResolvedMatches` supportée.

Ce document décrit les variables globales et les deux modes du guard **sans ajouter de règles** au-delà du code (`Services/ArchitectureGuard.ps1`).

---

## Modes : `STRICT` vs `TRACE`

Variable : **`$global:Etme_GuardMode`**

| Valeur   | Comportement |
|----------|----------------|
| **`STRICT`** (défaut) | Si **`Assert-NoDirectLegacyCall`** est invoqué alors que **`Etme_MergeCallDepth = 0`**, le guard lève : `Illegal direct legacy invocation outside Merge context`. |
| **`TRACE`** | Même diagnostic en **Verbose** (pile complète, premier appel hors infrastructure), **sans** `throw` pour ce cas. Utile pour tests ou inspection. |

Toute autre valeur que `TRACE` est traitée comme **`STRICT`**.

---

## Rôle de `Etme_MergeCallDepth`

Variable : **`$global:Etme_MergeCallDepth`**

- Incrémentée au début de **`Merge-EntityTournees`**, décrémentée dans un **`finally`** (même en cas d’erreur).
- Pendant qu’elle est **> 0**, une exécution de **`Merge-EntityTournees`** est en cours.
- Le guard considère qu’un appel à **`Assert-NoDirectLegacyCall`** survenant avec **profondeur > 0** est **inattendu** (journalisation Verbose uniquement, pas de branche « direct legacy » au sens strict).

Les appels **normaux** à **`Merge-EntityTournees`** ne passent pas par le guard ; la profondeur sert au diagnostic et au contexte d’exécution.

---

## Fusion finale : chemins autorisés

**Autorisé**

- Charger **`EntityTourneeMergeEngine.ps1`** et appeler **`Merge-EntityTournees`** avec les tournées Excel et **`ResolvedMatches`**. C’est la **seule** sortie de fusion finale supportée.

**Scripts `Final*` (neutralisés)**

- **`FinalTourneeBuilder.ps1`**, **`FinalResolvedTourneeBuilder.ps1`**, **`EntityReconciliationEngine.ps1`** ne réalisent plus de fusion : chaque fonction exposée **lève** immédiatement avec un message renvoyant vers **`Merge-EntityTournees`**. Elles **n’appellent pas** `ArchitectureGuard` et ne produisent **aucune** structure de sortie alternative.

**Guard `STRICT` / `TRACE`**

- S’applique à **`Assert-NoDirectLegacyCall`** (p. ex. tests ou instrumentation). Pour contourner temporairement le blocage en diagnostic : **`$global:Etme_GuardMode = 'TRACE'`**, puis remettre **`'STRICT'`**.

---

## Inspection sans modifier la logique

Fonction **`Get-EtmeGuardStatus`** (dans `ArchitectureGuard.ps1`) : expose le mode effectif, la profondeur de merge et des indicateurs booléens (`IsStrict`, `IsTrace`).

**Contrat stable (version 1)** : les propriétés retournées et leur sémantique sont figées pour la compatibilité des scripts appelants ; toute évolution doit être reflétée dans ce fichier et dans le commentaire `.NOTES` de la fonction.

---

## Contract stability rules

- **Variables globales** : seules **`Etme_GuardMode`** et **`Etme_MergeCallDepth`** (définies dans `ArchitectureGuard.ps1` / `EntityTourneeMergeEngine.ps1` selon le cas) font partie du modèle documenté. **Aucune nouvelle variable globale** liée au guard ne doit être introduite sans mise à jour explicite de ce document et du code associé.
- **Modes du guard** : seuls **`STRICT`** et **`TRACE`** sont des modes reconnus pour **`$global:Etme_GuardMode`**. Toute autre valeur est normalisée en comportement **`STRICT`** (voir implémentation de `Get-EtmeGuardMode`).
- **Évolutions** : ajout de champs sur l’objet retourné par **`Get-EtmeGuardStatus`**, ou changement de nom / type des propriétés existantes, = **changement de contrat** : documenter et incrémenter la version du contrat dans `ArchitectureGuard.ps1` et ici.
