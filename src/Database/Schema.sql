-- ==============================================================
-- Schema.sql — SNAPSHOT ONLY (structure initiale pour nouvelles bases)
-- WARNING: DO NOT ADD PRODUCTION MIGRATIONS HERE
-- All runtime evolutions (indexes, columns, data fixes) go through
-- Invoke-DatabaseMigrations in Database.ps1
-- ==============================================================

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

CREATE TABLE IF NOT EXISTS calendar_index (
    file_id TEXT NOT NULL,
    sheet TEXT NOT NULL,
    semaine TEXT NOT NULL,
    date TEXT NOT NULL,
    column_index INTEGER NOT NULL,
    header_row INTEGER NOT NULL,
    header_text TEXT
);
