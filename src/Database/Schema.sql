CREATE TABLE IF NOT EXISTS Agent (
    id_agent INTEGER PRIMARY KEY AUTOINCREMENT,
    nom TEXT NOT NULL,
    prenom TEXT NOT NULL,
    telephone TEXT,
    date_entree DATE,
    actif INTEGER DEFAULT 1
);

CREATE TABLE IF NOT EXISTS Vehicule (
    id_vehicule INTEGER PRIMARY KEY AUTOINCREMENT,
    immatriculation TEXT UNIQUE NOT NULL,
    numero_parc TEXT UNIQUE,
    capacite INTEGER DEFAULT 100,
    actif INTEGER DEFAULT 1
);

CREATE TABLE IF NOT EXISTS Tournee (
    id_tournee INTEGER PRIMARY KEY AUTOINCREMENT,
    date DATE NOT NULL,
    vacation TEXT CHECK(vacation IN ('matin', 'aprem'))
);

CREATE TABLE IF NOT EXISTS Collecte (
    id_collecte INTEGER PRIMARY KEY AUTOINCREMENT,
    id_tournee INTEGER NOT NULL,
    id_conteneur TEXT NOT NULL,
    quantite INTEGER DEFAULT 0
);

