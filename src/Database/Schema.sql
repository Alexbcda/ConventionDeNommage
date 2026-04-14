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

CREATE TABLE IF NOT EXISTS Vehicule (
    id_vehicule INTEGER PRIMARY KEY AUTOINCREMENT,
    numero_parc TEXT,
    immatriculation TEXT NOT NULL UNIQUE,
    numero_chassis TEXT,
    marque TEXT,
    modele TEXT,
    date_mise_circulation TEXT,
    date_controle TEXT,
    capacite INTEGER,
    conducteur_id INTEGER,
    alerte TEXT,
    date_alerte TEXT,
    actif INTEGER DEFAULT 1
);

CREATE INDEX IF NOT EXISTS idx_agent_poste ON Agent(poste);
CREATE INDEX IF NOT EXISTS idx_agent_actif ON Agent(actif);
CREATE INDEX IF NOT EXISTS idx_vehicule_immat ON Vehicule(immatriculation);
CREATE INDEX IF NOT EXISTS idx_vehicule_parc ON Vehicule(numero_parc);
