# Architecture du projet ConventionDeNommage

## Vue d'ensemble

Application de bureau PowerShell/WinForms pour la gestion de flotte et planification :
- Gestion des agents (CRUD)
- Gestion des vehicules (CRUD)
- Optimisation de plannings PDF
- Convention de nommage de fichiers

---

## Architecture en couches (CRUD Agent / Vehicule)

```
UI (Panel / Form)
       |
  Service Layer
       |
  Repository
       |
  Database.ps1 (SQLite)
```

| Couche | Responsabilite | Fichiers |
|--------|---------------|----------|
| **UI** | Affichage, events WinForms, feedback utilisateur | `AgentPanel.ps1`, `AgentForm.ps1`, `VehiculesPanel.ps1`, `VehiculesForm.ps1` |
| **Service** | Guard d'entree, orchestration, mapping donnees | `AgentService.ps1`, `VehiculeService.ps1` |
| **Repository** | Validation metier, normalisation, appels DB | `AgentRepository.ps1`, `VehiculesRepository.ps1` |
| **Database** | Acces SQLite pur (queries parametrees) | `Database.ps1` |

### Regles strictes

- **UI ne doit JAMAIS appeler** Repository ou Database directement
- **Service ne doit JAMAIS appeler** Database directement
- **Repository appelle** uniquement Database.ps1
- **Database.ps1** est le seul fichier qui execute du SQL

---

## Flux d'une operation CRUD (exemple : ajout agent)

```
1. AgentPanel.ps1  →  Add-AgentEntry (Service)
2. AgentService.ps1  →  Assert-AgentServiceInput (guard)
                     →  Add-AgentWithValidation (Repository)
3. AgentRepository.ps1  →  Assert-AgentContactFields (validation metier)
                         →  Add-Agent (Database)
4. Database.ps1  →  INSERT parametre SQLite
```

---

## Validation (defense-in-depth)

La validation se fait a 3 niveaux complementaires :

| Niveau | Role | Exemple |
|--------|------|---------|
| **UI (Form)** | UX immediat, feedback visuel | Champ vide → message rouge, `MaxLength` sur TextBox |
| **Service** | Guard d'entree rapide | `Assert-RequiredString`, longueur max, securite input |
| **Repository** | Validation metier finale | Format telephone, email, longueur min/max |

### Fonctions de validation (`Validation.ps1`)

| Fonction | Usage |
|----------|-------|
| `Test-Email` | Format email valide (ou vide accepte) |
| `Test-TelephoneValide` | Format telephone FR (ou vide accepte) |
| `Test-StringLength` | Longueur min/max generique |
| `Assert-RequiredString` | Champ obligatoire + longueur max + securite |
| `Assert-EntityId` | ID numerique valide |
| `Test-SecuriteInput` | Detection caracteres dangereux |
| `Sanitize-TextInput` | Nettoyage input utilisateur |
| `Format-Telephone` | Normalisation telephone FR (XX XX XX XX XX) |
| `Format-Nom` / `Format-Prenom` | Capitalisation noms propres |

---

## Securite SQL

### Regles absolues

1. **Toutes les queries utilisent des parametres** (`$cmd.Parameters.AddWithValue`)
2. **Zero concatenation de string** dans les requetes SQL
3. **Identifiants dynamiques** valides via `Test-SafeSqlIdentifier` avant insertion
4. **Index critiques** geres par `Invoke-DatabaseMigrations` (source unique de verite)

### Schema

- `Schema.sql` : snapshot initial (lecture seule, ne pas modifier)
- `Invoke-DatabaseMigrations` : evolutions (ALTER TABLE, CREATE INDEX) — idempotentes

---

## Structure des fichiers

```
src/
  Main.ps1                          # Point d'entree
  Bootstrap.ps1                     # Initialisation
  GUI.ps1                           # Construction fenetre principale
  Config.ps1                        # Configuration

  Common/
    Validation.ps1                  # Validations centralisees
    WinFormsHelpers.ps1             # Helpers UI (grilles, headers, erreurs)
    WinFormsGuard.ps1               # Guard de securite WinForms
    Styles.ps1                      # Constantes visuelles
    ...

  Core/
    Logger.ps1                      # Write-Log centralise

  Database/
    Database.ps1                    # Acces SQLite (queries parametrees)
    Schema.sql                      # Snapshot schema initial

  Services/
    AgentService.ps1                # Service agents (guard + orchestration)
    VehiculeService.ps1             # Service vehicules (guard + orchestration)

  ODM/
    Agents/
      AgentPanel.ps1                # UI panel agents
      AgentForm.ps1                 # Formulaire agent
      AgentRepository.ps1           # Repository agents

    Vehicules/
      VehiculesPanel.ps1            # UI panel vehicules
      VehiculesForm.ps1             # Formulaire vehicule
      VehiculesRepository.ps1       # Repository vehicules

    ConventionNommage/              # Module convention de nommage
    PdfPlanningOptimizer/           # Module optimisation plannings PDF
```

---

## Logging

- **Production** : uniquement `Write-Log` (jamais `Write-Host`)
- **Niveaux** : `INFO` (operations cles), `WARN` (validation echouee), `ERROR` (exceptions)
- **Principe** : 1 log par operation significative, pas de "begin/success" en doublon
- **Fichier** : `src/Logs/app.log`

---

## Conventions de nommage PowerShell

| Element | Convention | Exemple |
|---------|-----------|---------|
| Fonctions | `Verb-Noun` (PascalCase) | `Add-AgentEntry`, `Get-VehiculeList` |
| Variables locales | `$camelCase` | `$newId`, `$telFormatted` |
| Variables script | `$script:camelCase` | `$script:database` |
| Parametres | `PascalCase` | `-Nom`, `-IncludeInactive` |
| Fichiers | `PascalCase.ps1` | `AgentService.ps1` |

---

## Regles d'evolution

1. **Pas de nouvelle couche** — l'architecture UI → Service → Repository → Database est finale
2. **Pas de framework externe** — PowerShell + WinForms + SQLite uniquement
3. **Modifications schema** — uniquement via `Invoke-DatabaseMigrations`
4. **Nouvelles entites** — suivre le pattern Agent/Vehicule (Panel, Form, Repository, Service)
