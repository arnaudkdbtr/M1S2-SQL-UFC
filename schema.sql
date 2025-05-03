-- Script de création du schéma de la base de données UFC
-- Projet Final CS50 SQL

-- Suppression des tables si elles existent déjà (pour faciliter les tests)
DROP TABLE IF EXISTS STATISTIQUE_ROUND;
DROP TABLE IF EXISTS RESULTAT;
DROP TABLE IF EXISTS COMBAT;
DROP TABLE IF EXISTS EVENEMENT;
DROP TABLE IF EXISTS COMBATTANT;
DROP TABLE IF EXISTS CATEGORIE;
DROP VIEW IF EXISTS VUE_DETAILS_COMBAT;    
DROP VIEW IF EXISTS VUE_PALMARES;          
DROP VIEW IF EXISTS VUE_STATS_COMBATTANT;

-- Création des tables principales

-- Table des catégories de poids
CREATE TABLE CATEGORIE (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    weightclass TEXT NOT NULL,
    limite_poids_inf INTEGER NOT NULL,
    limite_poids_sup INTEGER NOT NULL,
    CHECK (limite_poids_inf < limite_poids_sup)
);

-- Table des combattants
CREATE TABLE COMBATTANT (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    nom TEXT NOT NULL,
    taille TEXT,          -- Format: '5' 11"'
    poids TEXT,           -- Format: '155 lbs.'
    allonge TEXT,         -- Format: '76"'
    stance TEXT,          -- Orthodox, Southpaw, Switch
    sexe TEXT,
    date_naissance TEXT,  -- Format: 'Jul 13, 1978'
    
    -- Conversion des valeurs pour faciliter les recherches et le tri
    taille_pouces REAL,    -- Taille convertie en pouces pour les calculs
    poids_livres REAL,     -- Poids converti en livres pour les calculs
    allonge_pouces REAL    -- Allonge convertie en pouces pour les calculs
);

-- Table des événements UFC
CREATE TABLE EVENEMENT (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    nom TEXT NOT NULL,
    date TEXT NOT NULL,   -- Format: 'April 26, 2025'
    lieu TEXT NOT NULL    -- Format: 'Kansas City, Missouri, USA'
);

-- Table des combats
CREATE TABLE COMBAT (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    evenement_id INTEGER NOT NULL,
    combattant1_id INTEGER NOT NULL,
    combattant2_id INTEGER NOT NULL,
    categorie_id INTEGER,
    FOREIGN KEY (evenement_id) REFERENCES EVENEMENT(id),
    FOREIGN KEY (combattant1_id) REFERENCES COMBATTANT(id),
    FOREIGN KEY (combattant2_id) REFERENCES COMBATTANT(id),
    FOREIGN KEY (categorie_id) REFERENCES CATEGORIE(id),
    CHECK (combattant1_id != combattant2_id)
);

-- Table des résultats de combats
CREATE TABLE RESULTAT (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    combat_id INTEGER NOT NULL,
    vainqueur_id INTEGER,  -- NULL en cas de match nul ou no contest
    methode TEXT NOT NULL, -- KO/TKO, Decision, Submission, etc.
    round INTEGER,
    temps TEXT,           -- Format: '4:03'
    format_temps TEXT,    -- Format: '3 Rnd (5-5-5)'
    arbitre TEXT,
    details TEXT,         -- Détails supplémentaires
    FOREIGN KEY (combat_id) REFERENCES COMBAT(id),
    FOREIGN KEY (vainqueur_id) REFERENCES COMBATTANT(id)
);

-- Table des statistiques détaillées par round
CREATE TABLE STATISTIQUE_ROUND (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    combat_id INTEGER NOT NULL,
    combattant_id INTEGER NOT NULL,
    round INTEGER NOT NULL,
    knockdowns REAL,
    sig_frappes TEXT,     -- Format: '15 of 39'
    sig_frappes_pct TEXT, -- Format: '38%'
    total_frappes TEXT,   -- Format: '15 of 39'
    takedowns TEXT,       -- Format: '0 of 1'
    takedowns_pct TEXT,   -- Format: '0%'
    tentatives_soumission REAL,
    reversals REAL,
    temps_controle TEXT,  -- Format: '0:12'
    frappes_tete TEXT,    -- Format: '8 of 25'
    frappes_corps TEXT,   -- Format: '3 of 7'
    frappes_jambes TEXT,  -- Format: '4 of 7'
    frappes_distance TEXT,-- Format: '11 of 34'
    frappes_clinch TEXT,  -- Format: '0 of 0'
    frappes_sol TEXT,     -- Format: '4 of 5'
    
    -- Conversion des valeurs pour faciliter les analyses
    sig_frappes_reussies INTEGER GENERATED ALWAYS AS (CAST(SUBSTR(sig_frappes, 1, INSTR(sig_frappes, ' of ') - 1) AS INTEGER)) STORED,
    sig_frappes_tentees INTEGER GENERATED ALWAYS AS (CAST(SUBSTR(sig_frappes, INSTR(sig_frappes, ' of ') + 4) AS INTEGER)) STORED,
    
    FOREIGN KEY (combat_id) REFERENCES COMBAT(id),
    FOREIGN KEY (combattant_id) REFERENCES COMBATTANT(id),
    UNIQUE (combat_id, combattant_id, round)
);

-- Création des index pour optimiser les performances

-- Index sur les tables principales
CREATE INDEX idx_combat_evenement ON COMBAT(evenement_id);
CREATE INDEX idx_combat_combattants ON COMBAT(combattant1_id, combattant2_id);
CREATE INDEX idx_combat_categorie ON COMBAT(categorie_id);
CREATE INDEX idx_resultat_combat ON RESULTAT(combat_id);
CREATE INDEX idx_resultat_vainqueur ON RESULTAT(vainqueur_id);
CREATE INDEX idx_stats_combat ON STATISTIQUE_ROUND(combat_id);
CREATE INDEX idx_stats_combattant ON STATISTIQUE_ROUND(combattant_id);
CREATE INDEX idx_stats_round ON STATISTIQUE_ROUND(round);

-- Index sur les colonnes fréquemment utilisées dans les recherches
CREATE INDEX idx_combattant_nom ON COMBATTANT(nom);
CREATE INDEX idx_evenement_date ON EVENEMENT(date);
CREATE INDEX idx_evenement_nom ON EVENEMENT(nom);
CREATE INDEX idx_categorie_nom ON CATEGORIE(nom);

-- Création des vues pour faciliter les analyses courantes

-- Vue pour obtenir le palmarès complet de chaque combattant
CREATE VIEW VUE_PALMARES AS
SELECT 
    c.id AS combattant_id,
    c.nom AS combattant_nom,
    COUNT(CASE WHEN r.vainqueur_id = c.id THEN 1 END) AS victoires,
    COUNT(CASE WHEN (cb.combattant1_id = c.id OR cb.combattant2_id = c.id) AND r.vainqueur_id != c.id AND r.vainqueur_id IS NOT NULL THEN 1 END) AS defaites,
    COUNT(CASE WHEN (cb.combattant1_id = c.id OR cb.combattant2_id = c.id) AND r.vainqueur_id IS NULL THEN 1 END) AS no_contest
FROM COMBATTANT c
LEFT JOIN COMBAT cb ON c.id = cb.combattant1_id OR c.id = cb.combattant2_id
LEFT JOIN RESULTAT r ON cb.id = r.combat_id
GROUP BY c.id;

-- Vue pour les statistiques agrégées par combattant
CREATE VIEW VUE_STATS_COMBATTANT AS
SELECT
    c.id AS combattant_id,
    c.nom AS combattant_nom,
    AVG(s.knockdowns) AS avg_knockdowns,
    SUM(s.sig_frappes_reussies) AS total_sig_frappes_reussies,
    SUM(s.sig_frappes_tentees) AS total_sig_frappes_tentees,
    CASE 
        WHEN SUM(s.sig_frappes_tentees) > 0 
        THEN ROUND(100.0 * SUM(s.sig_frappes_reussies) / SUM(s.sig_frappes_tentees), 2) 
        ELSE 0 
    END AS precision_frappes_pct
FROM COMBATTANT c
JOIN STATISTIQUE_ROUND s ON c.id = s.combattant_id
GROUP BY c.id;

-- Vue pour les détails complets des combats
CREATE VIEW VUE_DETAILS_COMBAT AS
SELECT
    cb.id AS combat_id,
    e.nom AS evenement,
    e.date AS date_evenement,
    c1.nom AS combattant1,
    c2.nom AS combattant2,
    cat.weightclass AS categorie,
    CASE 
        WHEN r.vainqueur_id = c1.id THEN c1.nom
        WHEN r.vainqueur_id = c2.id THEN c2.nom
        ELSE 'No contest / Draw'
    END AS vainqueur,
    r.methode,
    r.round,
    r.temps,
    r.arbitre
FROM COMBAT cb
JOIN EVENEMENT e ON cb.evenement_id = e.id
JOIN COMBATTANT c1 ON cb.combattant1_id = c1.id
JOIN COMBATTANT c2 ON cb.combattant2_id = c2.id
LEFT JOIN CATEGORIE cat ON cb.categorie_id = cat.id
LEFT JOIN RESULTAT r ON cb.id = r.combat_id;

-- Triggers pour maintenir l'intégrité des données

-- Trigger pour vérifier la cohérence des poids des combattants avec les catégories
CREATE TRIGGER verifier_categorie_poids
BEFORE INSERT ON COMBAT
FOR EACH ROW
BEGIN
    -- Cette logique serait plus complexe en pratique avec conversion des unités
    -- Pour l'instant, on implémente un placeholder
    SELECT RAISE(ROLLBACK, 'Poids du combattant incompatible avec la catégorie')
    WHERE EXISTS (
        SELECT 1 FROM COMBATTANT c, CATEGORIE cat
        WHERE (c.id = NEW.combattant1_id OR c.id = NEW.combattant2_id)
        AND cat.id = NEW.categorie_id
        AND c.poids_livres IS NOT NULL
        AND (c.poids_livres < cat.limite_poids_inf * 2.20462 OR c.poids_livres > cat.limite_poids_sup * 2.20462)
    );
END;
