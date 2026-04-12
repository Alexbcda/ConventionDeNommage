-- Schema.sql - Version PRO avec timestamps

CREATE TABLE IF NOT EXISTS Agent (
    id_agent INTEGER PRIMARY KEY AUTOINCREMENT,
    nom TEXT NOT NULL,
    prenom TEXT NOT NULL,
    telephone TEXT,
    email TEXT,
    date_entree INTEGER,  -- timestamp Unix
    date_sortie INTEGER,  -- timestamp Unix
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
    marque TEXT,
    modele TEXT,
    capacite INTEGER,
    conducteur_id INTEGER,
    actif INTEGER DEFAULT 1
);

CREATE INDEX IF NOT EXISTS idx_agent_poste ON Agent(poste);
CREATE INDEX IF NOT EXISTS idx_agent_actif ON Agent(actif);
