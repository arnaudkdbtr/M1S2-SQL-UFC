-- =================================================================
-- 🔍 Requêtes analytiques UFC - CS50 SQL
-- Auteurs : Arnaud Kindbeiter & Hugo Schneider
-- Projet : Base de données UFC
-- Objectif : Démonstration complète de la capacité à interroger
--            et modifier une base de données relationnelle UFC
-- =================================================================

-- Exemples de requêtes d'analyse pour extraire des informations clés

-- Objectif : Lister tous les combats disputés par un combattant donné, avec les informations clés (date, lieu, adversaire, issue).
-- Exemple avec 'Jon Jones'
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
-- Implémente une jointure multiple entre COMBAT, EVENEMENT, RESULTAT et COMBATTANT.

-- Afficher les 5 combattants ayant subi le plus de coups significatifs
SELECT 
    cb.nom,
    SUM(sr.sig_frappes_reussies) AS coups_subis
FROM STATISTIQUE_ROUND sr
JOIN COMBATTANT cb ON cb.id = sr.combattant_id
GROUP BY cb.nom
ORDER BY coups_subis DESC
LIMIT 5;

-- Objectif : Repérer les combattants ayant subi le plus de frappes significatives.
-- Utilise une agrégation (SUM) sur les frappes reçues.

-- Moyenne de coups donnés par rounds par catégorie de poids
SELECT 
    cat.weightclass,
    ROUND(AVG(sr.sig_frappes_reussies), 2) AS moyenne_coups
FROM STATISTIQUE_ROUND sr
JOIN COMBAT c ON c.id = sr.combat_id
JOIN CATEGORIE cat ON c.categorie_id = cat.id
GROUP BY cat.weightclass;

-- Objectif : Calculer la moyenne de frappes significatives réussies par catégorie de poids.
-- Joint STATISTIQUE_ROUND avec COMBAT et CATEGORIE, puis agrège avec AVG.

--  Nombre moyen de rounds par combat par catégorie
SELECT 
    cat.weightclass,
    ROUND(AVG(r.round), 2) AS moy_rounds
FROM RESULTAT r
JOIN COMBAT c ON r.combat_id = c.id
JOIN CATEGORIE cat ON c.categorie_id = cat.id
GROUP BY cat.weightclass;

-- Objectif : Analyser la durée moyenne des combats par catégorie de poids.
-- Moyenne du round de fin par catégorie via GROUP BY.

-- Suivi des performances d’un combattant au fil du temps (ex: 'Khamzat Chimaev')
SELECT 
    e.date,
    SUM(sr.sig_frappes_reussies) AS total_coups,
    SUM(sr.takedowns) AS total_takedowns
FROM COMBATTANT cb
JOIN STATISTIQUE_ROUND sr ON cb.id = sr.combattant_id
JOIN COMBAT c ON sr.combat_id = c.id
JOIN EVENEMENT e ON e.id = c.evenement_id
WHERE cb.nom = 'Khamzat Chimaev'
GROUP BY e.date
ORDER BY e.date;

-- Objectif : Suivre l'évolution temporelle des performances d’un combattant.
-- Agrège les frappes et takedowns par date d’événement.
-- Interprétation : 15 juillet 2020 Frappes significatives réussies : 43 Takedowns : 2

-- Méthodes de victoire les plus fréquentes par round
SELECT 
    r.round,
    r.methode,
    COUNT(*) AS occurences
FROM RESULTAT r
GROUP BY r.round, r.methode
ORDER BY r.round, occurences DESC;

-- Objectif : Étudier les méthodes de victoire dominantes par round.
-- GROUP BY sur round et méthode avec un COUNT.

-- Combattants avec le plus de soumissions réussies
SELECT 
    cb.nom,
    COUNT(*) AS nb_soumissions
FROM RESULTAT r
JOIN COMBATTANT cb ON r.vainqueur_id = cb.id
WHERE methode LIKE '%Submission%'
GROUP BY cb.nom
ORDER BY nb_soumissions DESC
LIMIT 10;

-- Objectif : Lister les combattants ayant réussi le plus de soumissions.
-- Filtre sur les méthodes de type 'Submission' avec LIKE.

--  Combattants invaincus à l'UFC
SELECT cb.nom
FROM COMBATTANT cb
WHERE cb.id IN (
    SELECT c1.id FROM COMBATTANT c1
    WHERE NOT EXISTS (
        SELECT 1
        FROM COMBAT c
        JOIN RESULTAT r ON c.id = r.combat_id
        WHERE (c.combattant1_id = c1.id OR c.combattant2_id = c1.id)
        AND r.vainqueur_id IS NOT c1.id
    )
)
AND cb.id IN (
    SELECT combattant_id
    FROM STATISTIQUE_ROUND
    GROUP BY combattant_id
    HAVING COUNT(DISTINCT combat_id) >= 3
);

-- Combattants avec le plus de victoires au 1er round
SELECT 
    cb.nom,
    COUNT(*) AS victoires_round1
FROM RESULTAT r
JOIN COMBATTANT cb ON cb.id = r.vainqueur_id
WHERE r.round = 1
GROUP BY cb.nom
ORDER BY victoires_round1 DESC
LIMIT 10;

-- Récupérer les arbitres qui ont officié le plus de combats avec leur pourcentage par méthode de victoire
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

-- Objectif : Analyser l'influence potentielle des arbitres sur les issues de combats
-- Calcule la distribution des méthodes de victoire pour chaque arbitre
-- Permet d'identifier des tendances (arbitres qui laissent plus/moins jouer au sol, etc.

-- Analyse des défenses au sol par catégorie (Tentatives de soumission vs réussites)
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

-- Objectif : Évaluer l'efficacité des techniques de soumission par catégorie
-- Compare les tentatives aux réussites pour identifier les différences entre divisions
-- Permet d'analyser comment le poids influence le jeu au sol

-- Analyse des rematches (combats revanche) et leurs résultats
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

-- Objectif : Analyser les séries de combats entre mêmes adversaires
-- Utilise une CTE pour normaliser l'ordre des combattants et numéroter leurs confrontations
-- Agrège la séquence des vainqueurs pour visualiser facilement les tendances

-- Analyse des performances par tranche d'âge
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

-- Objectif : Étudier l'impact de l'âge sur les performances des combattants
-- Calcule l'âge au moment du combat et classe par tranches d'âge
-- Analyse divers indicateurs (victoires, frappes, takedowns) pour chaque groupe d'âge

-- 3 requêtes de manipulation (INSERT, UPDATE, DELETE)
-- Ces requêtes démontrent la capacité à modifier la base de données

-- Ajouter un nouveau combattant fictif
INSERT INTO COMBATTANT (nom, sexe, taille_cm, poids_kg)
VALUES ('Arnaud Kindbeiter', 'H', 180, 77);

-- Objectif : Ajouter manuellement un combattant fictif pour test.
-- INSERT classique dans COMBATTANT.

-- Mettre à jour son poids
UPDATE COMBATTANT
SET poids_kg = 77
WHERE nom = 'Arnaud Kindbeiter';

-- Objectif : Modifier une information existante (poids).
-- UPDATE sur le combattant fictif inséré.

-- Supprimer ce combattant fictif
DELETE FROM COMBATTANT
WHERE nom = 'Arnaud Kindbeiter';

-- Objectif : Supprimer le combattant fictif.
-- DELETE conditionnel par nom.