-- Schema.sql - Version complète avec toutes les colonnes

CREATE TABLE IF NOT EXISTS Agent (
    id_agent INTEGER PRIMARY KEY AUTOINCREMENT,
    nom TEXT NOT NULL,
    prenom TEXT NOT NULL,
    telephone TEXT,
    email TEXT,
    date_entree INTEGER,
    date_sortie INTEGER,
    type_contrat TEXT NOT NULL,
    base_heures_semaine INTEGER DEFAULT 35,
    vehicule_id INTEGER,
    poste TEXT DEFAULT 'Collecteur',
    actif INTEGER DEFAULT 1
);

-- Migration incrémentale : ajout des dates métier sur Vehicule existant
-- Format base de données : YYYY-MM-DD
ALTER TABLE Vehicule ADD COLUMN date_entree TEXT;
ALTER TABLE Vehicule ADD COLUMN date_sortie TEXT;
ALTER TABLE Vehicule ADD COLUMN date_fin_controle_technique TEXT;

-- Schéma final attendu pour la table Vehicule
CREATE TABLE IF NOT EXISTS Vehicule (
    id_vehicule INTEGER PRIMARY KEY AUTOINCREMENT,
    numero_parc TEXT NOT NULL,
    immatriculation TEXT NOT NULL UNIQUE,
    numero_chassis TEXT,
    marque TEXT,
    modele TEXT,
    date_mise_circulation TEXT,
    date_controle TEXT,
    date_entree TEXT,
    date_sortie TEXT,
    capacite INTEGER,
    conducteur_id INTEGER,
    alerte TEXT,
    date_alerte TEXT,
    date_fin_controle_technique TEXT,
    actif INTEGER DEFAULT 1
);

CREATE INDEX IF NOT EXISTS idx_agent_poste ON Agent(poste);
CREATE INDEX IF NOT EXISTS idx_agent_actif ON Agent(actif);
CREATE INDEX IF NOT EXISTS idx_vehicule_immat ON Vehicule(immatriculation);
CREATE INDEX IF NOT EXISTS idx_vehicule_parc ON Vehicule(numero_parc);

-- Cache planning (import Excel) — voir Database.ps1 Initialize-CalendarIndexTable / migrations
CREATE TABLE IF NOT EXISTS calendar_index (
  file_id TEXT NOT NULL,
  sheet TEXT NOT NULL,
  semaine TEXT NOT NULL,
  date TEXT NOT NULL,
  column_index INTEGER NOT NULL,
  header_row INTEGER NOT NULL,
  header_text TEXT
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_calendar_file_date ON calendar_index (file_id, date);
CREATE INDEX IF NOT EXISTS idx_calendar_semaine_date ON calendar_index (semaine, date);
CREATE INDEX IF NOT EXISTS idx_calendar_file_id ON calendar_index (file_id);
