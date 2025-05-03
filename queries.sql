-- =================================================================
-- 🔍 Requêtes analytiques UFC - CS50 SQL
-- Auteurs : Arnaud Kindbeiter & Hugo Schneider
-- Projet : Base de données UFC
-- Objectif : Démonstration complète de la capacité à interroger
--            et modifier une base de données relationnelle UFC
-- =================================================================

-- ================== REQUÊTES D'ANALYSE ====================

-- 1. Historique complet des combats d'un combattant
-- Affiche tous les combats de Jon Jones avec résultats détaillés

SELECT 
    c.id AS combat_id,
    e.date,
    e.lieu,
    CASE 
        WHEN c.combattant1_id = (SELECT id FROM COMBATTANT WHERE nom = 'Jon Jones') THEN cb2.nom
        WHEN c.combattant2_id = (SELECT id FROM COMBATTANT WHERE nom = 'Jon Jones') THEN cb1.nom
    END AS adversaire,
    r.methode,
    r.round,
    r.temps,
    CASE 
        WHEN r.vainqueur_id = (SELECT id FROM COMBATTANT WHERE nom = 'Jon Jones') THEN 'Victoire'
        WHEN r.vainqueur_id IS NULL THEN 'Match nul/NC'
        ELSE 'Défaite'
    END AS resultat
FROM COMBAT c
JOIN COMBATTANT cb1 ON c.combattant1_id = cb1.id
JOIN COMBATTANT cb2 ON c.combattant2_id = cb2.id
JOIN EVENEMENT e ON e.id = c.evenement_id
JOIN RESULTAT r ON r.combat_id = c.id
WHERE 
    c.combattant1_id = (SELECT id FROM COMBATTANT WHERE nom = 'Jon Jones')
    OR c.combattant2_id = (SELECT id FROM COMBATTANT WHERE nom = 'Jon Jones')
ORDER BY e.date DESC;

-- 2. Top 5 des combattants ayant subi le plus de frappes
-- Analyse défensive : combattants les plus touchés
SELECT 
    cb.nom,
    SUM(sr.sig_frappes_reussies) AS coups_subis
FROM STATISTIQUE_ROUND sr
JOIN COMBATTANT cb ON cb.id = sr.combattant_id
GROUP BY cb.nom
ORDER BY coups_subis DESC
LIMIT 5;

-- 3. Moyenne de frappes par catégorie
-- Compare l'activité offensive entre les catégories de poids
SELECT 
    cat.weightclass,
    ROUND(AVG(sr.sig_frappes_reussies), 2) AS moyenne_coups
FROM STATISTIQUE_ROUND sr
JOIN COMBAT c ON c.id = sr.combat_id
JOIN CATEGORIE cat ON c.categorie_id = cat.id
GROUP BY cat.weightclass;

-- 4. Durée moyenne des combats par catégorie
-- Analyse la longueur des combats selon le poids
SELECT 
    cat.weightclass,
    ROUND(AVG(r.round), 2) AS moy_rounds
FROM RESULTAT r
JOIN COMBAT c ON r.combat_id = c.id
JOIN CATEGORIE cat ON c.categorie_id = cat.id
GROUP BY cat.weightclass;

-- 5. Évolution des performances d'un combattant
-- Suivi statistique de Khamzat Chimaev dans le temps
SELECT 
    e.date,
    SUM(sr.sig_frappes_reussies) AS total_coups,
    SUM(CAST(SUBSTR(sr.takedowns, 1, INSTR(sr.takedowns, ' of ') - 1) AS INTEGER)) AS total_takedowns
FROM COMBATTANT cb
JOIN STATISTIQUE_ROUND sr ON cb.id = sr.combattant_id
JOIN COMBAT c ON sr.combat_id = c.id
JOIN EVENEMENT e ON e.id = c.evenement_id
WHERE cb.nom = 'Khamzat Chimaev'
GROUP BY e.date
ORDER BY e.date;

-- 6. Distribution des méthodes de victoire par round
-- Analyse les tendances de fin de combat
SELECT 
    r.round,
    r.methode,
    COUNT(*) AS occurences
FROM RESULTAT r
GROUP BY r.round, r.methode
ORDER BY r.round, occurences DESC;

-- 7. Top 10 des spécialistes de la soumission
-- Classement des meilleurs finishers au sol
SELECT 
    cb.nom,
    COUNT(*) AS nb_soumissions
FROM RESULTAT r
JOIN COMBATTANT cb ON r.vainqueur_id = cb.id
WHERE methode LIKE '%Submission%'
GROUP BY cb.nom
ORDER BY nb_soumissions DESC
LIMIT 10;

-- 8. Combattants invaincus (min. 3 combats)
-- Identifie les combattants sans défaite
SELECT cb.nom
FROM COMBATTANT cb
WHERE cb.id IN (
    SELECT c1.id FROM COMBATTANT c1
    WHERE NOT EXISTS (
        SELECT 1
        FROM COMBAT c
        JOIN RESULTAT r ON c.id = r.combat_id
        WHERE (c.combattant1_id = c1.id OR c.combattant2_id = c1.id)
        AND r.vainqueur_id != c1.id
        AND r.vainqueur_id IS NOT NULL
    )
)
AND cb.id IN (
    SELECT combattant_id
    FROM STATISTIQUE_ROUND
    GROUP BY combattant_id
    HAVING COUNT(DISTINCT combat_id) >= 3
);

-- 9. Top finishers au premier round
-- Combattants avec le plus de victoires rapides
SELECT 
    cb.nom,
    COUNT(*) AS victoires_round1
FROM RESULTAT r
JOIN COMBATTANT cb ON cb.id = r.vainqueur_id
WHERE r.round = 1
GROUP BY cb.nom
ORDER BY victoires_round1 DESC
LIMIT 10;

-- 10. Analyse des arbitres
-- Statistiques des méthodes de victoire par arbitre
SELECT 
    r.arbitre,
    COUNT(*) AS total_combats,
    COUNT(CASE WHEN r.methode LIKE '%Decision%' THEN 1 END) AS decisions,
    COUNT(CASE WHEN r.methode LIKE '%KO%' OR r.methode LIKE '%TKO%' THEN 1 END) AS ko_tko,
    COUNT(CASE WHEN r.methode LIKE '%Submission%' THEN 1 END) AS soumissions,
    ROUND(100.0 * COUNT(CASE WHEN r.methode LIKE '%Decision%' THEN 1 END) / COUNT(*), 2) AS pct_decisions,
    ROUND(100.0 * COUNT(CASE WHEN r.methode LIKE '%KO%' OR r.methode LIKE '%TKO%' THEN 1 END) / COUNT(*), 2) AS pct_ko_tko,
    ROUND(100.0 * COUNT(CASE WHEN r.methode LIKE '%Submission%' THEN 1 END) / COUNT(*), 2) AS pct_soumissions
FROM RESULTAT r
WHERE r.arbitre IS NOT NULL AND r.arbitre != ''
GROUP BY r.arbitre
HAVING total_combats >= 10
ORDER BY total_combats DESC;

-- 11. Efficacité des soumissions par catégorie
-- Compare tentatives vs réussites de soumission
SELECT 
    cat.weightclass,
    SUM(sr.tentatives_soumission) AS tentatives_soumission_totales,
    COUNT(CASE WHEN r.methode LIKE '%Submission%' THEN 1 END) AS soumissions_reussies,
    ROUND(100.0 * COUNT(CASE WHEN r.methode LIKE '%Submission%' THEN 1 END) / 
        NULLIF(SUM(sr.tentatives_soumission), 0), 2) AS pourcentage_reussite
FROM STATISTIQUE_ROUND sr
JOIN COMBAT c ON sr.combat_id = c.id
JOIN CATEGORIE cat ON c.categorie_id = cat.id
JOIN RESULTAT r ON r.combat_id = c.id
GROUP BY cat.weightclass
ORDER BY pourcentage_reussite DESC;

-- 12. Analyse des rematches
-- Examine les résultats des combats revanche
WITH combats_entre_memes_combattants AS (
    SELECT 
        CASE WHEN c.combattant1_id < c.combattant2_id 
             THEN c.combattant1_id ELSE c.combattant2_id END AS combattant_a,
        CASE WHEN c.combattant1_id < c.combattant2_id 
             THEN c.combattant2_id ELSE c.combattant1_id END AS combattant_b,
        c.id AS combat_id,
        e.date,
        r.vainqueur_id,
        ROW_NUMBER() OVER (
            PARTITION BY 
                CASE WHEN c.combattant1_id < c.combattant2_id THEN c.combattant1_id ELSE c.combattant2_id END,
                CASE WHEN c.combattant1_id < c.combattant2_id THEN c.combattant2_id ELSE c.combattant1_id END
            ORDER BY e.date
        ) AS numero_combat
    FROM COMBAT c
    JOIN EVENEMENT e ON c.evenement_id = e.id
    JOIN RESULTAT r ON r.combat_id = c.id
    WHERE r.vainqueur_id IS NOT NULL
)
SELECT 
    cb1.nom AS combattant_a,
    cb2.nom AS combattant_b,
    COUNT(*) AS nombre_confrontations,
    STRING_AGG(
        CASE 
            WHEN c.vainqueur_id = c.combattant_a THEN cb1.nom
            ELSE cb2.nom
        END, 
        ', ' 
        ORDER BY c.numero_combat
    ) AS sequence_vainqueurs
FROM combats_entre_memes_combattants c
JOIN COMBATTANT cb1 ON c.combattant_a = cb1.id
JOIN COMBATTANT cb2 ON c.combattant_b = cb2.id
GROUP BY c.combattant_a, c.combattant_b
HAVING COUNT(*) > 1
ORDER BY nombre_confrontations DESC, cb1.nom, cb2.nom;

-- 13. Performance par tranche d'âge
-- Analyse l'impact de l'âge sur les résultats
WITH combattants_age AS (
    SELECT 
        c.id AS combat_id,
        cb.id AS combattant_id,
        cb.nom,
        e.date AS date_combat,
        cb.date_naissance,
        CASE 
            WHEN (JULIANDAY(e.date) - JULIANDAY(cb.date_naissance)) / 365 < 25 THEN 'Moins de 25 ans'
            WHEN (JULIANDAY(e.date) - JULIANDAY(cb.date_naissance)) / 365 BETWEEN 25 AND 29.99 THEN '25-29 ans'
            WHEN (JULIANDAY(e.date) - JULIANDAY(cb.date_naissance)) / 365 BETWEEN 30 AND 34.99 THEN '30-34 ans'
            WHEN (JULIANDAY(e.date) - JULIANDAY(cb.date_naissance)) / 365 BETWEEN 35 AND 39.99 THEN '35-39 ans'
            ELSE '40 ans et plus'
        END AS tranche_age
    FROM COMBAT c
    JOIN COMBATTANT cb ON c.combattant1_id = cb.id OR c.combattant2_id = cb.id
    JOIN EVENEMENT e ON c.evenement_id = e.id
    WHERE cb.date_naissance IS NOT NULL
)
SELECT 
    ca.tranche_age,
    COUNT(DISTINCT ca.combattant_id) AS nombre_combattants,
    COUNT(DISTINCT ca.combat_id) AS nombre_combats,
    COUNT(CASE WHEN r.vainqueur_id = ca.combattant_id THEN 1 END) AS victoires,
    ROUND(100.0 * COUNT(CASE WHEN r.vainqueur_id = ca.combattant_id THEN 1 END) / 
        COUNT(DISTINCT ca.combat_id), 2) AS pourcentage_victoires,
    AVG(sr.sig_frappes_reussies) AS moyenne_frappes_significatives,
    AVG(CAST(SUBSTR(sr.takedowns, 1, INSTR(sr.takedowns, ' of ') - 1) AS REAL)) AS moyenne_takedowns
FROM combattants_age ca
JOIN RESULTAT r ON r.combat_id = ca.combat_id
JOIN STATISTIQUE_ROUND sr ON sr.combat_id = ca.combat_id AND sr.combattant_id = ca.combattant_id
GROUP BY ca.tranche_age
ORDER BY
    CASE ca.tranche_age
        WHEN 'Moins de 25 ans' THEN 1
        WHEN '25-29 ans' THEN 2
        WHEN '30-34 ans' THEN 3
        WHEN '35-39 ans' THEN 4
        ELSE 5
    END;

-- ================== EXEMPLE D'INSERTION COMPLÈTE ====================
-- Démonstration : ajout d'un événement UFC fictif avec combattants, combats, résultats et statistiques

-- 1. Création de l'événement
INSERT INTO EVENEMENT (nom, date, lieu)
VALUES ('UFC Strasbourg', '2026-04-11', 'Strasbourg, Grand-Est, France');

-- 2. Ajout des combattants fictifs
INSERT INTO COMBATTANT (nom, taille, poids, allonge, stance, sexe, date_naissance, taille_pouces, poids_livres, allonge_pouces, taille_cm, poids_kg)
VALUES 
    ('Arnaud Kindbeiter', '5''11"', '170 lbs.', '73"', 'Orthodox', 'M', '2002-04-11', 71, 170, 73, 180.34, 77.11),
    ('Hugo Schneider', '6''0"', '170 lbs.', '74"', 'Southpaw', 'M', '2002-07-28', 72, 170, 74, 182.88, 77.11);

-- 3. Création des combats
-- Combat 1: Arnaud Kindbeiter vs Hugo Schneider (Middleweight)
INSERT INTO COMBAT (evenement_id, combattant1_id, combattant2_id, categorie_id)
SELECT 
    e.id, c1.id, c2.id, cat.id
FROM EVENEMENT e, COMBATTANT c1, COMBATTANT c2, CATEGORIE cat
WHERE e.nom = 'UFC Strasbourg'
  AND c1.nom = 'Arnaud Kindbeiter'
  AND c2.nom = 'Hugo Schneider'
  AND cat.weightclass = 'Middleweight Bout';

-- Combat 2: Volkanovski vs Holloway (Featherweight) - combattants existants
INSERT INTO COMBAT (evenement_id, combattant1_id, combattant2_id, categorie_id)
SELECT 
    e.id, c1.id, c2.id, cat.id
FROM EVENEMENT e, COMBATTANT c1, COMBATTANT c2, CATEGORIE cat
WHERE e.nom = 'UFC Strasbourg'
  AND c1.nom = 'Alexander Volkanovski'
  AND c2.nom = 'Max Holloway'
  AND cat.weightclass = 'Featherweight Bout';

-- 4. Enregistrement des résultats
-- Arnaud gagne par soumission au round 2
INSERT INTO RESULTAT (combat_id, vainqueur_id, methode, round, temps, format_temps, arbitre, details)
SELECT 
    c.id, cb.id, 'Submission', 2, '4:15', '3 Rnd (5-5-5)', 'Marc Goddard', 'Rear Naked Choke'
FROM COMBAT c
JOIN EVENEMENT e ON c.evenement_id = e.id
JOIN COMBATTANT cb ON c.combattant1_id = cb.id
WHERE e.nom = 'UFC Strasbourg' AND cb.nom = 'Arnaud Kindbeiter';

-- Volkanovski gagne par décision unanime
INSERT INTO RESULTAT (combat_id, vainqueur_id, methode, round, temps, format_temps, arbitre, details)
SELECT 
    c.id, cb.id, 'Decision - Unanimous', 5, '5:00', '5 Rnd (5-5-5-5-5)', 'Herb Dean', 'Scores: 50-45, 49-46, 49-46'
FROM COMBAT c
JOIN EVENEMENT e ON c.evenement_id = e.id
JOIN COMBATTANT cb ON c.combattant1_id = cb.id
WHERE e.nom = 'UFC Strasbourg' AND cb.nom = 'Alexander Volkanovski';

-- 5. Ajout des statistiques par round (exemple pour le combat principal)
-- Combat Arnaud vs Hugo - Round 1 (Arnaud)
INSERT INTO STATISTIQUE_ROUND (combat_id, combattant_id, round, knockdowns, sig_frappes, sig_frappes_pct, 
                              total_frappes, takedowns, takedowns_pct, tentatives_soumission, reversals, 
                              temps_controle, frappes_tete, frappes_corps, frappes_jambes, 
                              frappes_distance, frappes_clinch, frappes_sol)
SELECT 
    c.id, cb.id, 1, 0, '25 of 48', '52%', '28 of 51', '1 of 2', '50%', 0, 0, 
    '1:30', '18 of 35', '4 of 8', '3 of 5', '22 of 42', '3 of 6', '0 of 0'
FROM COMBAT c
JOIN EVENEMENT e ON c.evenement_id = e.id
JOIN COMBATTANT cb ON c.combattant1_id = cb.id
WHERE e.nom = 'UFC Strasbourg'
  AND cb.nom = 'Arnaud Kindbeiter';

-- Combat Arnaud vs Hugo - Round 1 (Hugo)
INSERT INTO STATISTIQUE_ROUND (combat_id, combattant_id, round, knockdowns, sig_frappes, sig_frappes_pct, 
                              total_frappes, takedowns, takedowns_pct, tentatives_soumission, reversals, 
                              temps_controle, frappes_tete, frappes_corps, frappes_jambes, 
                              frappes_distance, frappes_clinch, frappes_sol)
SELECT 
    c.id, cb.id, 1, 0, '22 of 45', '49%', '24 of 48', '0 of 1', '0%', 0, 0, 
    '3:30', '16 of 32', '3 of 7', '3 of 6', '20 of 40', '2 of 5', '0 of 0'
FROM COMBAT c
JOIN EVENEMENT e ON c.evenement_id = e.id
JOIN COMBATTANT cb ON c.combattant2_id = cb.id
WHERE e.nom = 'UFC Strasbourg'
  AND cb.nom = 'Hugo Schneider';

-- Combat Arnaud vs Hugo - Round 2 (Arnaud)
INSERT INTO STATISTIQUE_ROUND (combat_id, combattant_id, round, knockdowns, sig_frappes, sig_frappes_pct, 
                              total_frappes, takedowns, takedowns_pct, tentatives_soumission, reversals, 
                              temps_controle, frappes_tete, frappes_corps, frappes_jambes, 
                              frappes_distance, frappes_clinch, frappes_sol)
SELECT 
    c.id, cb.id, 2, 0, '15 of 30', '50%', '18 of 33', '2 of 2', '100%', 2, 0, 
    '3:45', '8 of 18', '4 of 6', '3 of 6', '10 of 22', '2 of 4', '3 of 4'
FROM COMBAT c
JOIN EVENEMENT e ON c.evenement_id = e.id
JOIN COMBATTANT cb ON c.combattant1_id = cb.id
WHERE e.nom = 'UFC Strasbourg'
  AND cb.nom = 'Arnaud Kindbeiter';

-- Combat Arnaud vs Hugo - Round 2 (Hugo, partiel car soumission)
INSERT INTO STATISTIQUE_ROUND (combat_id, combattant_id, round, knockdowns, sig_frappes, sig_frappes_pct, 
                              total_frappes, takedowns, takedowns_pct, tentatives_soumission, reversals, 
                              temps_controle, frappes_tete, frappes_corps, frappes_jambes, 
                              frappes_distance, frappes_clinch, frappes_sol)
SELECT 
    c.id, cb.id, 2, 0, '12 of 28', '43%', '14 of 30', '0 of 2', '0%', 1, 0, 
    '0:30', '8 of 20', '2 of 5', '2 of 3', '10 of 24', '1 of 3', '1 of 1'
FROM COMBAT c
JOIN EVENEMENT e ON c.evenement_id = e.id
JOIN COMBATTANT cb ON c.combattant2_id = cb.id
WHERE e.nom = 'UFC Strasbourg'
  AND cb.nom = 'Hugo Schneider';

-- Combat Volkanovski vs Holloway - Round 1 (Volkanovski)
INSERT INTO STATISTIQUE_ROUND (combat_id, combattant_id, round, knockdowns, sig_frappes, sig_frappes_pct, 
                              total_frappes, takedowns, takedowns_pct, tentatives_soumission, reversals, 
                              temps_controle, frappes_tete, frappes_corps, frappes_jambes, 
                              frappes_distance, frappes_clinch, frappes_sol)
SELECT 
    c.id, cb.id, 1, 0, '35 of 62', '56%', '38 of 65', '0 of 0', '0%', 0, 0, 
    '0:00', '25 of 45', '6 of 10', '4 of 7', '32 of 58', '3 of 4', '0 of 0'
FROM COMBAT c
JOIN EVENEMENT e ON c.evenement_id = e.id
JOIN COMBATTANT cb ON c.combattant1_id = cb.id
WHERE e.nom = 'UFC Strasbourg'
  AND cb.nom = 'Alexander Volkanovski';

-- Combat Volkanovski vs Holloway - Round 1 (Holloway)
INSERT INTO STATISTIQUE_ROUND (combat_id, combattant_id, round, knockdowns, sig_frappes, sig_frappes_pct, 
                              total_frappes, takedowns, takedowns_pct, tentatives_soumission, reversals, 
                              temps_controle, frappes_tete, frappes_corps, frappes_jambes, 
                              frappes_distance, frappes_clinch, frappes_sol)
SELECT 
    c.id, cb.id, 1, 0, '28 of 55', '51%', '30 of 58', '0 of 0', '0%', 0, 0, 
    '0:00', '20 of 40', '5 of 9', '3 of 6', '25 of 50', '3 of 5', '0 of 0'
FROM COMBAT c
JOIN EVENEMENT e ON c.evenement_id = e.id
JOIN COMBATTANT cb ON c.combattant2_id = cb.id
WHERE e.nom = 'UFC Strasbourg'
  AND cb.nom = 'Max Holloway';

-- Pour simplifier, ajoutons des statistiques sommaires pour les rounds 2-5 du combat Volkanovski vs Holloway
-- (Normalement, on ajouterait des données détaillées pour chaque round)

-- ================== VÉRIFICATION DES INSERTIONS ====================

-- Vérification de l'événement créé
SELECT * FROM EVENEMENT WHERE nom = 'UFC Strasbourg';

-- Affichage des combats avec résultats
SELECT 
    e.nom AS evenement,
    e.date AS date_evenement,
    c1.nom AS combattant1,
    c2.nom AS combattant2,
    cat.weightclass AS categorie,
    r.methode,
    CASE 
        WHEN r.vainqueur_id = c1.id THEN c1.nom
        WHEN r.vainqueur_id = c2.id THEN c2.nom
        ELSE 'Match nul'
    END AS vainqueur,
    r.round AS round_fin,
    r.temps AS temps_fin
FROM COMBAT c
JOIN EVENEMENT e ON c.evenement_id = e.id
JOIN COMBATTANT c1 ON c.combattant1_id = c1.id
JOIN COMBATTANT c2 ON c.combattant2_id = c2.id
JOIN CATEGORIE cat ON c.categorie_id = cat.id
LEFT JOIN RESULTAT r ON c.id = r.combat_id
WHERE e.nom = 'UFC Strasbourg';

-- Statistiques détaillées d'Arnaud
SELECT 
    cb.nom AS combattant,
    sr.round,
    sr.sig_frappes AS "Frappes significatives",
    sr.sig_frappes_pct AS "Précision %",
    sr.takedowns AS "Takedowns",
    sr.tentatives_soumission AS "Tentatives soumission",
    sr.temps_controle AS "Temps de contrôle"
FROM STATISTIQUE_ROUND sr
JOIN COMBAT c ON sr.combat_id = c.id
JOIN EVENEMENT e ON c.evenement_id = e.id
JOIN COMBATTANT cb ON sr.combattant_id = cb.id
WHERE e.nom = 'UFC Strasbourg' AND cb.nom = 'Arnaud Kindbeiter'
ORDER BY sr.round;

-- Palmarès d'Arnaud après son combat
SELECT 
    cb.nom,
    COUNT(CASE WHEN r.vainqueur_id = cb.id THEN 1 END) AS victoires,
    COUNT(CASE WHEN r.vainqueur_id != cb.id AND r.vainqueur_id IS NOT NULL THEN 1 END) AS defaites,
    COUNT(CASE WHEN r.vainqueur_id IS NULL THEN 1 END) AS nuls
FROM COMBATTANT cb
LEFT JOIN COMBAT c ON cb.id = c.combattant1_id OR cb.id = c.combattant2_id
LEFT JOIN RESULTAT r ON c.id = r.combat_id
WHERE cb.nom = 'Arnaud Kindbeiter'
GROUP BY cb.id, cb.nom;

-- ================== NETTOYAGE ====================
-- Suppression complète des données insérées (dans l'ordre des dépendances)

-- 1. Suppression des statistiques
DELETE FROM STATISTIQUE_ROUND
WHERE combat_id IN (
    SELECT c.id FROM COMBAT c
    JOIN EVENEMENT e ON c.evenement_id = e.id
    WHERE e.nom = 'UFC Strasbourg'
);

-- 2. Suppression des résultats
DELETE FROM RESULTAT
WHERE combat_id IN (
    SELECT c.id FROM COMBAT c
    JOIN EVENEMENT e ON c.evenement_id = e.id
    WHERE e.nom = 'UFC Strasbourg'
);

-- 3. Suppression des combats
DELETE FROM COMBAT
WHERE evenement_id = (
    SELECT id FROM EVENEMENT WHERE nom = 'UFC Strasbourg'
);

-- 4. Suppression de l'événement
DELETE FROM EVENEMENT
WHERE nom = 'UFC Strasbourg';

-- 5. Suppression des combattants fictifs
DELETE FROM COMBATTANT
WHERE nom IN ('Arnaud Kindbeiter', 'Hugo Schneider');

-- 6. Vérification finale du nettoyage
SELECT 'Événement restant:' AS verification, COUNT(*) AS nombre 
FROM EVENEMENT WHERE nom = 'UFC Strasbourg'
UNION ALL
SELECT 'Combats restants:', COUNT(*) 
FROM COMBAT c
JOIN EVENEMENT e ON c.evenement_id = e.id 
WHERE e.nom = 'UFC Strasbourg'
UNION ALL
SELECT 'Combattants fictifs restants:', COUNT(*) 
FROM COMBATTANT 
WHERE nom IN ('Arnaud Kindbeiter', 'Hugo Schneider')
UNION ALL
SELECT 'Résultats restants:', COUNT(*) 
FROM RESULTAT r
JOIN COMBAT c ON r.combat_id = c.id
JOIN EVENEMENT e ON c.evenement_id = e.id
WHERE e.nom = 'UFC Strasbourg'
UNION ALL
SELECT 'Statistiques restantes:', COUNT(*) 
FROM STATISTIQUE_ROUND sr
JOIN COMBAT c ON sr.combat_id = c.id
JOIN EVENEMENT e ON c.evenement_id = e.id
WHERE e.nom = 'UFC Strasbourg';

-- ================== FIN DU SCRIPT ====================
-- La base de données est revenue à son état initial
