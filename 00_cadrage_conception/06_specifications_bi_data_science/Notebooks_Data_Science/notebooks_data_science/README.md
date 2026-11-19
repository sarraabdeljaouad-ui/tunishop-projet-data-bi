# Notebooks data science – TuniShop (TS-DATA-DSC-001)

Notebooks exécutés le 14/10/2026 ; les sorties (tableaux, graphiques) sont enregistrées dans les fichiers.

| Notebook | Cas d'usage | Résultat |
|---|---|---|
| `DS01_score_refus_colis.ipynb` | Risque de refus d'un colis payable à la livraison (PR-2) | Critère non atteint : pas mieux que la règle métier |
| `DS02_prevision_demande.ipynb` | Demande hebdomadaire par univers et entrepôt à 4 semaines (PR-1, PR-4) | Critère atteint : WAPE 30 % contre 45 % |
| `DS03_attrition_clients.ipynb` | Clients à risque d'attrition à 6 mois (PR-3) | Critère atteint de justesse |

## Réexécution

```bash
pip install pandas numpy scikit-learn matplotlib jupyter
export TUNISHOP_REF_DIR=/chemin/vers/tunishop_dataset/donnees_reference
export TUNISHOP_FIG_DIR=./figures
jupyter nbconvert --to notebook --execute --inplace DS0*.ipynb
```

Versions utilisées : Python 3.12, pandas 2.x, scikit-learn 1.8, graine aléatoire 42.
`figures/` contient les graphiques et les résultats (JSON) repris dans le dossier Word.
