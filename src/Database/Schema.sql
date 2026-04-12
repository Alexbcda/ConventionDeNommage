-- Schema.sql - Structure complète de la base de données

-- Table Agent
CREATE TABLE IF NOT EXISTS Agent (
    id_agent INTEGER PRIMARY KEY AUTOINCREMENT,
    nom TEXT NOT NULL,
    prenom TEXT NOT NULL,
    telephone TEXT,
    email TEXT,
    date_entree DATE NOT NULL,
    date_sortie DATE,
    type_contrat TEXT NOT NULL,
    base_heures_semaine INTEGER DEFAULT 35,
    vehicule_id INTEGER,
    poste TEXT DEFAULT 'Collecteur',
    actif INTEGER DEFAULT 1
);

-- Table Vehicule
CREATE TABLE IF NOT EXISTS Vehicule (
    id_vehicule INTEGER PRIMARY KEY AUTOINCREMENT,
    numero_parc TEXT,
    immatriculation TEXT NOT NULL UNIQUE,
    marque TEXT,
    modele TEXT,
    capacite INTEGER,
    conducteur_id INTEGER,
    actif INTEGER DEFAULT 1,
    FOREIGN KEY (conducteur_id) REFERENCES Agent(id_agent)
);

-- Table Tournee
CREATE TABLE IF NOT EXISTS Tournee (
    id_tournee INTEGER PRIMARY KEY AUTOINCREMENT,
    nom TEXT NOT NULL,
    secteur TEXT,
    duree_estimee INTEGER,
    nb_tournees INTEGER DEFAULT 1,
    actif INTEGER DEFAULT 1
);

-- Table Planning
CREATE TABLE IF NOT EXISTS Planning (
    id_planning INTEGER PRIMARY KEY AUTOINCREMENT,
    agent_id INTEGER NOT NULL,
    date DATE NOT NULL,
    heure_debut TIME,
    heure_fin TIME,
    tournee_id INTEGER,
    statut TEXT DEFAULT 'Planifie',
    FOREIGN KEY (agent_id) REFERENCES Agent(id_agent),
    FOREIGN KEY (tournee_id) REFERENCES Tournee(id_tournee)
);

-- Table Affectation (pour stocker les affectations date/tournees)
CREATE TABLE IF NOT EXISTS Affectation (
    id_affectation INTEGER PRIMARY KEY AUTOINCREMENT,
    date DATE NOT NULL,
    nb_tournees INTEGER NOT NULL,
    commentaire TEXT,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- Index pour optimiser les performances
CREATE INDEX IF NOT EXISTS idx_agent_poste ON Agent(poste);
CREATE INDEX IF NOT EXISTS idx_agent_actif ON Agent(actif);
CREATE INDEX IF NOT EXISTS idx_vehicule_immat ON Vehicule(immatriculation);
CREATE INDEX IF NOT EXISTS idx_planning_agent ON Planning(agent_id);
CREATE INDEX IF NOT EXISTS idx_planning_date ON Planning(date);
CREATE INDEX IF NOT EXISTS idx_tournee_nom ON Tournee(nom);
CREATE INDEX IF NOT EXISTS idx_affectation_date ON Affectation(date);

-- Données de test pour véhicules
INSERT OR IGNORE INTO Vehicule (numero_parc, immatriculation, marque, modele, capacite) VALUES 
('P001', 'AA-123-AA', 'Renault', 'Kangoo', 800),
('P002', 'BB-456-BB', 'Citroën', 'Jumpy', 1200),
('P003', 'CC-789-CC', 'Peugeot', 'Partner', 1000);

-- Données de test pour tournées
INSERT OR IGNORE INTO Tournee (nom, secteur, duree_estimee, nb_tournees) VALUES 
('Tournée Nord', 'Nord', 240, 3),
('Tournée Sud', 'Sud', 180, 2),
('Tournée Est', 'Est', 300, 4),
('Tournée Ouest', 'Ouest', 200, 2);
