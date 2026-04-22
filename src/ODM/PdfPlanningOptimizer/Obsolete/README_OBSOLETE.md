# Dossier Obsolete - PdfPlanningOptimizer

## Pourquoi ces elements ont ete deplaces

Le module migre vers un **pipeline minimal** :

**Excel -> Tournees -> PDF -> Entites -> Match (WorkOrder exact) -> Merge (PDF prioritaire) -> Export**

Les dossiers **Anchors**, **Decision**, **Routing**, **Scoring**, **Debug** et les scripts Services listes ci-dessous relevent d une couche consideree comme *over-engineering* pour ce perimetre. Ils ont ete **deplaces** (pas supprimes) pour clarifier l architecture et reduire la surface de maintenance.

Les dossiers renommÃ©s en `*.ignore` evitent qu ils soient pris pour du code actif a la racine du module.

## Contenu typique

- Dossiers : `Anchors.ignore`, `Decision.ignore`, `Routing.ignore`, `Scoring.ignore`, `Debug.ignore`
- Scripts (anciennement dans `Services/`) : garde architecture, builders *Final*, reconciliation, telemetrie merge, validation, etc.

## Apres validation

Une fois les tests et l integration valides sur le pipeline simplifie, le contenu de `Obsolete/` peut etre **supprime definitivement** (ou archive ailleurs). Aucune obligation de le conserver au-dela de la periode de transition.

## Imports existants

Les scripts restants peuvent encore contenir des **references** aux anciens chemins ; elles sont **signalees** par `CleanPdfPlanningOptimizer.ps1` lors du scan. Corriger ces imports au fil de la migration.

---
*Genere par `CleanPdfPlanningOptimizer.ps1`.*
