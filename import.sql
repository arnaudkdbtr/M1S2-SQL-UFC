-- Script d'importation des données depuis les fichiers CSV

-- Configuration pour l'importation CSV
.mode csv
.headers on
.separator ,

-- ===== IMPORT DES CATÉGORIES =====
-- Importer les catégories
.import --skip 1 CSV/catégories.csv CATEGORIE

-- ===== IMPORT DES COMBATTANTS =====

-- Créer une table temporaire pour les données brutes
CREATE TEMPORARY TABLE temp_combattants (
    FIGHTER TEXT,
    HEIGHT TEXT,
    WEIGHT TEXT,
    REACH TEXT,
    STANCE TEXT,
    DOB TEXT,
    sexe TEXT
);

-- Importer les données
.import CSV/TOTT.csv temp_combattants
DELETE FROM temp_combattants WHERE FIGHTER = 'FIGHTER';

-- Insérer dans la table finale
INSERT INTO COMBATTANT (nom, taille, poids, allonge, stance, date_naissance, sexe)
SELECT FIGHTER, HEIGHT, WEIGHT, REACH, STANCE, DOB, sexe FROM temp_combattants;

-- Calcul des unités impériales
UPDATE COMBATTANT SET
    taille_pouces = CASE 
        WHEN taille LIKE '%''%"%' THEN 
            CAST(SUBSTR(taille, 1, INSTR(taille, '''') - 1) AS INTEGER) * 12 + 
            CAST(SUBSTR(taille, INSTR(taille, '''') + 2, INSTR(taille, '"') - INSTR(taille, '''') - 2) AS INTEGER)
        ELSE NULL
    END,
    poids_livres = CASE 
        WHEN poids LIKE '% lbs.%' THEN 
            CAST(SUBSTR(poids, 1, INSTR(poids, ' lbs.') - 1) AS REAL)
        ELSE NULL
    END,
    allonge_pouces = CASE 
        WHEN allonge LIKE '%"%' THEN 
            CAST(SUBSTR(allonge, 1, INSTR(allonge, '"') - 1) AS REAL)
        ELSE NULL
    END;

-- Ajout des colonnes métriques
ALTER TABLE COMBATTANT ADD COLUMN taille_cm REAL;
ALTER TABLE COMBATTANT ADD COLUMN poids_kg REAL;

UPDATE COMBATTANT SET
    taille_cm = ROUND(taille_pouces * 2.54, 2),
    poids_kg = ROUND(poids_livres * 0.453592, 2);

-- Nettoyage
DROP TABLE temp_combattants;

-- ===== IMPORT DES ÉVÉNEMENTS =====

CREATE TEMPORARY TABLE temp_evenements (
    event TEXT,
    date TEXT,
    city TEXT,
    state TEXT,
    country TEXT
);

.import CSV/evenements.csv temp_evenements
DELETE FROM temp_evenements WHERE event = 'event';

INSERT INTO EVENEMENT (nom, date, lieu)
SELECT 
    event,
    date,
    city || ', ' || state || ', ' || country
FROM temp_evenements;

DROP TABLE temp_evenements;

-- ===== IMPORT DES COMBATS =====

-- Création d'une table temporaire pour stocker les combats existants
CREATE TEMPORARY TABLE combats_existants AS
SELECT 
    e.nom AS evenement,
    c1.nom AS combattant1,
    c2.nom AS combattant2
FROM COMBAT cb
JOIN EVENEMENT e ON cb.evenement_id = e.id
JOIN COMBATTANT c1 ON cb.combattant1_id = c1.id
JOIN COMBATTANT c2 ON cb.combattant2_id = c2.id;

-- Importation des combats du CSV
CREATE TEMPORARY TABLE temp_combats (
    Event TEXT,
    Fight TEXT
);

.import CSV/combats.csv temp_combats
DELETE FROM temp_combats WHERE Event = 'Event';

-- Prétraitement: normalisation des noms de combats et extraction des combattants
CREATE TEMPORARY TABLE import_tracking (
    event TEXT,
    combattant1 TEXT,
    combattant2 TEXT
);

INSERT INTO import_tracking (event, combattant1, combattant2)
SELECT 
    Event,
    TRIM(SUBSTR(REPLACE(REPLACE(REPLACE(Fight, ' vs ', ' vs. '), ' VS. ', ' vs. '), ' VS ', ' vs. '), 1, INSTR(REPLACE(REPLACE(REPLACE(Fight, ' vs ', ' vs. '), ' VS. ', ' vs. '), ' VS ', ' vs. '), ' vs. ') - 1)) AS fighter1,
    TRIM(SUBSTR(REPLACE(REPLACE(REPLACE(Fight, ' vs ', ' vs. '), ' VS. ', ' vs. '), ' VS ', ' vs. '), INSTR(REPLACE(REPLACE(REPLACE(Fight, ' vs ', ' vs. '), ' VS. ', ' vs. '), ' VS ', ' vs. '), ' vs. ') + 5)) AS fighter2
FROM temp_combats;

BEGIN TRANSACTION;

-- Insérer les nouveaux combats
INSERT INTO COMBAT (evenement_id, combattant1_id, combattant2_id)
SELECT 
    e.id,
    c1.id,
    c2.id
FROM import_tracking it
JOIN EVENEMENT e ON it.event = e.nom
JOIN COMBATTANT c1 ON it.combattant1 = c1.nom
JOIN COMBATTANT c2 ON it.combattant2 = c2.nom
WHERE NOT EXISTS (
    SELECT 1 
    FROM combats_existants ce
    WHERE ce.evenement = it.event
    AND ce.combattant1 = it.combattant1
    AND ce.combattant2 = it.combattant2
)
-- Protection contre les doublons
AND NOT EXISTS (
    SELECT 1 FROM COMBAT c
    WHERE c.evenement_id = e.id
    AND c.combattant1_id = c1.id
    AND c.combattant2_id = c2.id
);

COMMIT;

-- Nettoyage
DROP TABLE combats_existants;
DROP TABLE temp_combats;
DROP TABLE import_tracking;

-- ===== IMPORT DES RÉSULTATS =====

-- Configuration du mode d'import
.mode csv
.headers on
.separator ,

-- 1. Créer une table temporaire pour stocker les données brutes
CREATE TEMPORARY TABLE temp_resultats (
    EVENT TEXT,
    BOUT TEXT,
    OUTCOME TEXT,
    WEIGHTCLASS TEXT,
    METHOD TEXT,
    ROUND INTEGER,
    TIME TEXT,
    TIME_FORMAT TEXT,
    REFEREE TEXT,
    DETAILS TEXT
);

-- 2. Importer les données CSV
.import "CSV/Résultats_combats.csv" temp_resultats

-- 3. Supprimer la ligne d'en-tête éventuellement réimportée
DELETE FROM temp_resultats WHERE EVENT = 'EVENT';

-- 4. Normaliser le nom des combats
UPDATE temp_resultats
SET BOUT = REPLACE(REPLACE(REPLACE(BOUT, ' vs ', ' vs. '), ' VS. ', ' vs. '), ' VS ', ' vs. ');

-- 5. Extraire et prétraiter les données avec correspondance EXACTE des événements
CREATE TEMPORARY TABLE resultats_pretraites AS
SELECT 
    tr.EVENT,
    e.id AS evenement_id,
    tr.BOUT,
    tr.OUTCOME,
    tr.METHOD,
    tr.ROUND,
    tr.TIME,
    tr.TIME_FORMAT,
    tr.REFEREE,
    tr.DETAILS,
    TRIM(SUBSTR(tr.BOUT, 1, INSTR(tr.BOUT, ' vs. ') - 1)) AS fighter1,
    TRIM(SUBSTR(tr.BOUT, INSTR(tr.BOUT, ' vs. ') + 5)) AS fighter2,
    CASE 
        WHEN tr.OUTCOME = 'W/L' THEN 1
        WHEN tr.OUTCOME = 'L/W' THEN 2
        ELSE 0
    END AS winner_index
FROM temp_resultats tr
JOIN EVENEMENT e ON e.nom = tr.EVENT;  -- Correspondance exacte uniquement

-- 6. Identifier les combats avec numérotation pour gérer les combats multiples
CREATE TEMPORARY TABLE combats_identifies AS
WITH result_numbered AS (
    SELECT 
        *,
        ROW_NUMBER() OVER (
            PARTITION BY evenement_id, fighter1, fighter2 
            ORDER BY ROWID
        ) as result_order
    FROM resultats_pretraites
),
combat_numbered AS (
    SELECT 
        cb.id AS combat_id,
        cb.evenement_id,
        cb.combattant1_id,
        cb.combattant2_id,
        c1.nom AS fighter1_name,
        c2.nom AS fighter2_name,
        ROW_NUMBER() OVER (
            PARTITION BY cb.evenement_id, c1.nom, c2.nom 
            ORDER BY cb.id
        ) as combat_order
    FROM COMBAT cb
    JOIN COMBATTANT c1 ON cb.combattant1_id = c1.id
    JOIN COMBATTANT c2 ON cb.combattant2_id = c2.id
)
SELECT 
    rn.*,
    cn.combat_id,
    CASE 
        WHEN rn.winner_index = 1 THEN 
            CASE 
                WHEN cn.fighter1_name = rn.fighter1 THEN cn.combattant1_id
                WHEN cn.fighter2_name = rn.fighter1 THEN cn.combattant2_id
                ELSE NULL
            END
        WHEN rn.winner_index = 2 THEN 
            CASE 
                WHEN cn.fighter1_name = rn.fighter2 THEN cn.combattant1_id
                WHEN cn.fighter2_name = rn.fighter2 THEN cn.combattant2_id
                ELSE NULL
            END
        ELSE NULL
    END AS vainqueur_id
FROM result_numbered rn
JOIN combat_numbered cn ON 
    rn.evenement_id = cn.evenement_id
    AND rn.result_order = cn.combat_order
    AND (
        (cn.fighter1_name = rn.fighter1 AND cn.fighter2_name = rn.fighter2)
        OR (cn.fighter1_name = rn.fighter2 AND cn.fighter2_name = rn.fighter1)
        OR (cn.fighter1_name LIKE rn.fighter1 || '%' AND cn.fighter2_name LIKE rn.fighter2 || '%')
        OR (cn.fighter1_name LIKE rn.fighter2 || '%' AND cn.fighter2_name LIKE rn.fighter1 || '%')
    );

-- 7. Insérer dans la table RESULTAT en évitant les doublons
INSERT INTO RESULTAT (
    combat_id,
    vainqueur_id,
    methode,
    round,
    temps,
    format_temps,
    arbitre,
    details
)
SELECT 
    combat_id,
    vainqueur_id,
    METHOD,
    ROUND,
    TIME,
    TIME_FORMAT,
    REFEREE,
    DETAILS
FROM combats_identifies
WHERE combat_id IS NOT NULL
AND NOT EXISTS (
    SELECT 1 FROM RESULTAT r WHERE r.combat_id = combats_identifies.combat_id
);

-- 8. Vérifier combien de résultats ont été importés
SELECT COUNT(*) AS resultats_importes FROM RESULTAT;

-- 9. Liste des combats sans résultats
SELECT 
    e.nom AS evenement,
    c1.nom || ' vs. ' || c2.nom AS combat,
    'Non trouvé dans le CSV' AS statut
FROM COMBAT cb
JOIN EVENEMENT e ON cb.evenement_id = e.id
JOIN COMBATTANT c1 ON cb.combattant1_id = c1.id
JOIN COMBATTANT c2 ON cb.combattant2_id = c2.id
LEFT JOIN RESULTAT r ON cb.id = r.combat_id
WHERE r.id IS NULL
ORDER BY e.nom, combat;

-- 10. Nettoyer les tables temporaires
DROP TABLE temp_resultats;
DROP TABLE resultats_pretraites;
DROP TABLE combats_identifies;

-- ===== ATTRIBUTION DES CATÉGORIES =====

-- Création d'une table temporaire pour les résultats avec catégories
CREATE TEMPORARY TABLE temp_resultats_combats (
    EVENT TEXT,
    BOUT TEXT,
    OUTCOME TEXT,
    WEIGHTCLASS TEXT,
    METHOD TEXT,
    ROUND INTEGER,
    TIME TEXT,
    TIME_FORMAT TEXT,
    REFEREE TEXT,
    DETAILS TEXT
);

.import CSV/resultats_combats.csv temp_resultats_combats
DELETE FROM temp_resultats_combats WHERE EVENT = 'EVENT';

-- Normaliser les formats
UPDATE temp_resultats_combats
SET BOUT = REPLACE(REPLACE(REPLACE(BOUT, ' vs ', ' vs. '), ' VS. ', ' vs. '), ' VS ', ' vs. ');

-- Extraire et normaliser les noms des combattants
CREATE TEMPORARY TABLE resultats_normalises AS
SELECT 
    EVENT,
    BOUT,
    WEIGHTCLASS,
    TRIM(SUBSTR(BOUT, 1, INSTR(BOUT, ' vs. ') - 1)) AS fighter1,
    TRIM(SUBSTR(BOUT, INSTR(BOUT, ' vs. ') + 5)) AS fighter2
FROM temp_resultats_combats;

-- Mise à jour des catégories par correspondance directe
UPDATE COMBAT
SET categorie_id = (
    SELECT cat.id
    FROM resultats_normalises rn
    JOIN EVENEMENT e ON rn.EVENT = e.nom
    JOIN COMBATTANT c1 ON rn.fighter1 = c1.nom
    JOIN COMBATTANT c2 ON rn.fighter2 = c2.nom
    JOIN CATEGORIE cat ON rn.WEIGHTCLASS = cat.weightclass
    WHERE e.id = COMBAT.evenement_id
    AND c1.id = COMBAT.combattant1_id
    AND c2.id = COMBAT.combattant2_id
    LIMIT 1
)
WHERE EXISTS (
    SELECT 1
    FROM resultats_normalises rn
    JOIN EVENEMENT e ON rn.EVENT = e.nom
    JOIN COMBATTANT c1 ON rn.fighter1 = c1.nom
    JOIN COMBATTANT c2 ON rn.fighter2 = c2.nom
    WHERE e.id = COMBAT.evenement_id
    AND c1.id = COMBAT.combattant1_id
    AND c2.id = COMBAT.combattant2_id
);

-- Mise à jour par estimation (féminin)
UPDATE COMBAT
SET categorie_id = (
    SELECT cat.id
    FROM CATEGORIE cat
    WHERE cat.weightclass LIKE 'Women''s%'
    AND (
        SELECT AVG(c.poids_livres)
        FROM COMBATTANT c
        WHERE c.id IN (COMBAT.combattant1_id, COMBAT.combattant2_id)
    ) BETWEEN cat.limite_poids_inf * 2.20462 AND cat.limite_poids_sup * 2.20462
    LIMIT 1
)
WHERE categorie_id IS NULL
AND (
    SELECT COUNT(*) FROM COMBATTANT c
    WHERE c.id IN (COMBAT.combattant1_id, COMBAT.combattant2_id) AND c.sexe = 'F'
) = 2;

-- Mise à jour par estimation (masculin)
UPDATE COMBAT
SET categorie_id = (
    SELECT cat.id
    FROM CATEGORIE cat
    WHERE cat.weightclass NOT LIKE 'Women''s%'
    AND (
        SELECT AVG(c.poids_livres)
        FROM COMBATTANT c
        WHERE c.id IN (COMBAT.combattant1_id, COMBAT.combattant2_id)
    ) BETWEEN cat.limite_poids_inf * 2.20462 AND cat.limite_poids_sup * 2.20462
    LIMIT 1
)
WHERE categorie_id IS NULL
AND (
    SELECT COUNT(*) FROM COMBATTANT c
    WHERE c.id IN (COMBAT.combattant1_id, COMBAT.combattant2_id) AND c.sexe = 'F'
) < 2;

-- Cas spécial Heavyweight
UPDATE COMBAT
SET categorie_id = (
    SELECT id FROM CATEGORIE WHERE weightclass = 'Heavyweight Bout'
)
WHERE categorie_id IS NULL
AND (
    SELECT AVG(c.poids_livres)
    FROM COMBATTANT c
    WHERE c.id IN (COMBAT.combattant1_id, COMBAT.combattant2_id)
) >= 205
AND (
    SELECT COUNT(*) FROM COMBATTANT c
    WHERE c.id IN (COMBAT.combattant1_id, COMBAT.combattant2_id) AND c.sexe = 'F'
) < 2;

-- Nettoyage
DROP TABLE temp_resultats_combats;
DROP TABLE resultats_normalises;

-- ===== IMPORT DES STATISTIQUES DE COMBAT =====

-- Créer une table temporaire pour les données brutes
CREATE TEMPORARY TABLE temp_statistiques_combats (
    EVENT TEXT,
    BOUT TEXT,
    ROUND INTEGER,
    FIGHTER TEXT,
    KD REAL,
    SIG_STR TEXT,
    SIG_STR_PCT TEXT,
    TOTAL_STR TEXT,
    TD TEXT,
    TD_PCT TEXT,
    SUB_ATT REAL,
    REV REAL,
    CTRL TEXT,
    HEAD TEXT,
    BODY TEXT,
    LEG TEXT,
    DISTANCE TEXT,
    CLINCH TEXT,
    GROUND TEXT
);

-- Importer le CSV dans la table temporaire
.import "CSV/Statistiques_combats.csv" temp_statistiques_combats

-- Nettoyer les données (supprimer l'en-tête)
DELETE FROM temp_statistiques_combats WHERE EVENT = 'EVENT';

-- Créer une table de correspondance pour les événements
CREATE TEMPORARY TABLE correspondance_evenements (
    nom_csv TEXT PRIMARY KEY,
    evenement_id INTEGER
);

-- Optimisation : pré-calculer les transformations d'événements
CREATE TEMPORARY TABLE event_preprocessed AS
SELECT DISTINCT EVENT, 
       LOWER(TRIM(EVENT)) AS event_lower,
       CASE WHEN INSTR(EVENT, ':') > 0 
            THEN LOWER(TRIM(SUBSTR(EVENT, 1, INSTR(EVENT, ':') - 1)))
            ELSE LOWER(TRIM(EVENT)) 
       END AS event_prefix
FROM temp_statistiques_combats;

CREATE TEMPORARY TABLE evenement_preprocessed AS
SELECT id, 
       nom,
       LOWER(TRIM(nom)) AS nom_lower,
       CASE WHEN INSTR(nom, ':') > 0 
            THEN LOWER(TRIM(SUBSTR(nom, 1, INSTR(nom, ':') - 1)))
            ELSE LOWER(TRIM(nom)) 
       END AS nom_prefix
FROM EVENEMENT;

-- Créer des index pour accélérer les jointures
CREATE INDEX idx_event_lower ON event_preprocessed(event_lower);
CREATE INDEX idx_event_prefix ON event_preprocessed(event_prefix);
CREATE INDEX idx_nom_lower ON evenement_preprocessed(nom_lower); 
CREATE INDEX idx_nom_prefix ON evenement_preprocessed(nom_prefix);

-- Remplir la table de correspondance des événements
INSERT OR IGNORE INTO correspondance_evenements (nom_csv, evenement_id)
SELECT ep.EVENT, ep2.id
FROM event_preprocessed ep
JOIN evenement_preprocessed ep2 ON 
    ep.event_lower = ep2.nom_lower OR
    ep.event_prefix = ep2.nom_prefix;

-- Créer une vue pour les correspondances de combats
CREATE TEMPORARY VIEW vue_combats AS
SELECT 
    cb.id AS combat_id,
    e.id AS evenement_id,
    e.nom AS evenement_nom,
    cb.combattant1_id,
    cb.combattant2_id,
    c1.nom AS combattant1_nom,
    c2.nom AS combattant2_nom,
    c1.nom || ' vs. ' || c2.nom AS bout_format1,
    c2.nom || ' vs. ' || c1.nom AS bout_format2
FROM COMBAT cb
JOIN EVENEMENT e ON cb.evenement_id = e.id
JOIN COMBATTANT c1 ON cb.combattant1_id = c1.id
JOIN COMBATTANT c2 ON cb.combattant2_id = c2.id;

-- Créer une table de correspondance pour les combats (avec modification pour gérer les combats multiples)
CREATE TEMPORARY TABLE correspondance_combats (
    event_csv TEXT,
    bout_csv TEXT,
    combat_id INTEGER,
    PRIMARY KEY (event_csv, bout_csv, combat_id)
);

-- Pour les combats multiples (comme Sakuraba vs Silveira), insérer toutes les correspondances possibles
INSERT OR IGNORE INTO correspondance_combats (event_csv, bout_csv, combat_id)
SELECT DISTINCT tsc.EVENT, tsc.BOUT, vc.combat_id
FROM temp_statistiques_combats tsc
LEFT JOIN correspondance_evenements ce ON tsc.EVENT = ce.nom_csv
JOIN vue_combats vc ON 
    (ce.evenement_id IS NOT NULL AND vc.evenement_id = ce.evenement_id OR tsc.EVENT = vc.evenement_nom) AND
    (tsc.BOUT = vc.bout_format1 OR tsc.BOUT = vc.bout_format2);

-- Partie 1: Insérer les données valides avec combattants spécifiés
INSERT OR REPLACE INTO STATISTIQUE_ROUND (
    combat_id,
    combattant_id,
    round,
    knockdowns,
    sig_frappes,
    sig_frappes_pct,
    total_frappes,
    takedowns,
    takedowns_pct,
    tentatives_soumission,
    reversals,
    temps_controle,
    frappes_tete,
    frappes_corps,
    frappes_jambes,
    frappes_distance,
    frappes_clinch,
    frappes_sol
)
WITH numbered_stats AS (
    SELECT 
        tsc.*,
        ROW_NUMBER() OVER (
            PARTITION BY tsc.EVENT, tsc.BOUT, tsc.ROUND, tsc.FIGHTER 
            ORDER BY ROWID
        ) as stat_occurrence
    FROM temp_statistiques_combats tsc
    WHERE tsc.FIGHTER <> ''
),
numbered_combats AS (
    SELECT 
        cc.*,
        ROW_NUMBER() OVER (
            PARTITION BY cc.event_csv, cc.bout_csv 
            ORDER BY cc.combat_id
        ) as combat_occurrence
    FROM correspondance_combats cc
)
SELECT 
    nc.combat_id,
    (SELECT id FROM COMBATTANT WHERE nom = ns.FIGHTER) AS combattant_id,
    ns.ROUND,
    ns.KD,
    ns.SIG_STR,
    ns.SIG_STR_PCT,
    ns.TOTAL_STR,
    ns.TD,
    ns.TD_PCT,
    ns.SUB_ATT,
    ns.REV,
    ns.CTRL,
    ns.HEAD,
    ns.BODY,
    ns.LEG,
    ns.DISTANCE,
    ns.CLINCH,
    ns.GROUND
FROM numbered_stats ns
JOIN numbered_combats nc ON 
    ns.EVENT = nc.event_csv AND 
    ns.BOUT = nc.bout_csv AND 
    ns.stat_occurrence = nc.combat_occurrence
JOIN COMBAT c ON nc.combat_id = c.id
WHERE 
    ns.FIGHTER <> '' AND
    (SELECT id FROM COMBATTANT WHERE nom = ns.FIGHTER) IN (c.combattant1_id, c.combattant2_id);

-- Partie 2: Insérer les données pour les lignes avec FIGHTER vide
INSERT OR IGNORE INTO STATISTIQUE_ROUND (
    combat_id,
    combattant_id,
    round,
    knockdowns,
    sig_frappes,
    sig_frappes_pct,
    total_frappes,
    takedowns,
    takedowns_pct,
    tentatives_soumission,
    reversals,
    temps_controle,
    frappes_tete,
    frappes_corps,
    frappes_jambes,
    frappes_distance,
    frappes_clinch,
    frappes_sol
)
SELECT 
    cc.combat_id,
    c.combattant1_id AS combattant_id,
    tsc.ROUND,
    NULL AS KD,
    NULL AS SIG_STR,
    NULL AS SIG_STR_PCT,
    NULL AS TOTAL_STR,
    NULL AS TD,
    NULL AS TD_PCT,
    NULL AS SUB_ATT,
    NULL AS REV,
    NULL AS CTRL,
    NULL AS HEAD,
    NULL AS BODY,
    NULL AS LEG,
    NULL AS DISTANCE,
    NULL AS CLINCH,
    NULL AS GROUND
FROM temp_statistiques_combats tsc
JOIN correspondance_combats cc ON tsc.EVENT = cc.event_csv AND tsc.BOUT = cc.bout_csv
JOIN COMBAT c ON cc.combat_id = c.id
WHERE tsc.FIGHTER = '';

-- Ajouter également les entrées pour le combattant 2 des mêmes combats
INSERT OR IGNORE INTO STATISTIQUE_ROUND (
    combat_id,
    combattant_id,
    round,
    knockdowns,
    sig_frappes,
    sig_frappes_pct,
    total_frappes,
    takedowns,
    takedowns_pct,
    tentatives_soumission,
    reversals,
    temps_controle,
    frappes_tete,
    frappes_corps,
    frappes_jambes,
    frappes_distance,
    frappes_clinch,
    frappes_sol
)
SELECT 
    cc.combat_id,
    c.combattant2_id AS combattant_id,
    tsc.ROUND,
    NULL AS KD,
    NULL AS SIG_STR,
    NULL AS SIG_STR_PCT,
    NULL AS TOTAL_STR,
    NULL AS TD,
    NULL AS TD_PCT,
    NULL AS SUB_ATT,
    NULL AS REV,
    NULL AS CTRL,
    NULL AS HEAD,
    NULL AS BODY,
    NULL AS LEG,
    NULL AS DISTANCE,
    NULL AS CLINCH,
    NULL AS GROUND
FROM temp_statistiques_combats tsc
JOIN correspondance_combats cc ON tsc.EVENT = cc.event_csv AND tsc.BOUT = cc.bout_csv
JOIN COMBAT c ON cc.combat_id = c.id
WHERE tsc.FIGHTER = '';

-- Vérifier le nombre total de statistiques importées
SELECT COUNT(*) AS statistiques_totales_importees FROM STATISTIQUE_ROUND;

-- Nettoyer les objets temporaires utilisés pour l'import
DROP TABLE temp_statistiques_combats;
DROP TABLE correspondance_evenements;
DROP TABLE correspondance_combats;
DROP VIEW vue_combats;
DROP TABLE event_preprocessed;
DROP TABLE evenement_preprocessed;

-- Certaines statistiques sont manquantes (valeurs NULL) car les données détaillées ne sont pas disponibles sur le site officiel : http://ufcstats.com/statistics/events/completed.
-- C'est notamment le cas pour les combats suivants :
-- "UFC - Ultimate Brazil", "Cesar Marscucci vs. Paulo Santos"
-- "UFC - Ultimate Ultimate '95", "Joe Charles vs. Scott Bessac"
-- "UFC - Ultimate Ultimate '96", "Mark Hall vs. Felix Lee Mitchell"
-- "UFC - Ultimate Ultimate '96", "Steve Nelmark vs. Marcus Bossett"
-- "UFC - Ultimate Ultimate '96", "Tai Bowden vs. Jack Nilson"
-- "UFC 10: The Tournament", "Sam Adkins vs. Felix Lee Mitchell"
-- "UFC 11: The Proving Ground", "Roberto Traven vs. Dave Berry"
-- "UFC 11: The Proving Ground", "Scott Ferrozzo vs. Sam Fulton"
-- "UFC 12: Judgement Day", "Justin Martin vs. Eric Martin"
-- "UFC 12: Judgement Day", "Nick Sanzo vs. Jackie Lee"
-- "UFC 16: Battle in the Bayou", "Chris Brennan vs. Courtney Turner"
-- "UFC 16: Battle in the Bayou", "Laverne Clark vs. Josh Stuart"
-- "UFC 17: Redemption", "Andre Roberts vs. Harry Moskowitz"
-- "UFC 4: Revenge of the Warriors", "Joe Charles vs. Kevin Rosier"
-- "UFC 4: Revenge of the Warriors", "Marcus Bossett vs. Eldo Xavier Dias"
-- "UFC 6: Clash of the Titans", "Anthony Macias vs. He-Man Gipson"
-- "UFC 6: Clash of the Titans", "Joel Sutton vs. Jack McGlaughlin"
-- "UFC 7: The Brawl in Buffalo", "Joel Sutton vs. Geza Kalman"
-- "UFC 7: The Brawl in Buffalo", "Onassis Parungao vs. Francesco Maturi"
-- "UFC 8: David vs Goliath", "Sam Adkins vs. Keith Mielke"