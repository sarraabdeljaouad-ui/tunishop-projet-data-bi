
## Version 1.1 (recette du 03/12/2026)

- E1 : colonne `cluster` en texte (matrice des groupes k-means remplie).
- E2 : page 2, « Churn réel et prévu par type de client » (deux taux au lieu d'un taux et d'un nombre).
- E3 : cartes en valeur complète (plus de « 7M » ni « 27K »).
- E4 : carte « Dernière publication » élargie.
- E5 : colonne « Retenu » en Oui / Non.
- E6 : séparateur de milliers sur le nombre de lignes publiées.

## Version 1.3 (demande prévue de l'année suivante)

- Table `v_ml_scores_demande` (vue `pbi.v_ml_scores_demande`, notebook `08_Scoring_Actuel`), reliée à `v_dim_produit` et `v_dim_mois`.
- 13 mesures dans le dossier « 8 Demande prévue ».
- Page 7 « Demande prévue et risque de rupture » : 5 cartes, 1 courbe, 1 histogramme, 1 tableau (v056 à v063).
- Prévision plancher : la méthode a sous-estimé 2025 (biais de -23,5 %).
