/* Vérifier le calendrier 2026 dans le DWH après le rechargement (à exécuter dans SSMS) */
USE TuniShop_DWH;
GO
-- 1. Jours par période commerciale en 2025 et 2026 : 2026 ne doit plus contenir « hors_referentiel »
SELECT annee, periode_commerciale, COUNT(*) AS jours, MIN([date]) AS du, MAX([date]) AS au
FROM bi.v_dim_date
WHERE annee IN (2025, 2026)
GROUP BY annee, periode_commerciale
ORDER BY annee, MIN([date]);

-- 2. Ramadan et jours fériés 2026 (attendu : 29 jours de Ramadan, 14 jours fériés)
SELECT SUM(CASE WHEN est_ramadan = 1 THEN 1 ELSE 0 END)    AS jours_ramadan,
       SUM(CASE WHEN est_jour_ferie = 1 THEN 1 ELSE 0 END) AS jours_feries
FROM bi.v_dim_date
WHERE annee = 2026;

-- 3. Contrôle de non-régression : les années validées n'ont pas changé (comparer avec le PV du DWH)
SELECT annee, periode_commerciale, COUNT(*) AS jours
FROM bi.v_dim_date
WHERE annee BETWEEN 2023 AND 2025
GROUP BY annee, periode_commerciale
ORDER BY annee, periode_commerciale;
