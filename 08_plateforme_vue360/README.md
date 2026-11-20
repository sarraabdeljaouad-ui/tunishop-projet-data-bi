# Plateforme de recherche vue 360

Une plateforme de recherche floue sur les clients, produits, fournisseurs, commandes et transporteurs,
avec une fiche 360 par entité : chiffres clés, prédictions expliquées, historique et avis.

Le code est dans deux dépôts séparés :

| Version | En ligne | Code |
|---|---|---|
| Streamlit | [tunishopsarraapps.streamlit.app](https://tunishopsarraapps.streamlit.app) | [tunishop-plateforme-360](https://github.com/sarraabdeljaouad-ui/tunishop-plateforme-360) |
| HTML statique | [Voir le site](https://sarraabdeljaouad-ui.github.io/Tunishop-plateforme-360-web/) | [Tunishop-plateforme-360-web](https://github.com/sarraabdeljaouad-ui/Tunishop-plateforme-360-web) |

## Contenu de ce dossier

| Dossier | Contenu |
|---|---|
| `conception/` | Organisation générale (ce que chaque page affiche) |
| `maquettes/` | Maquettes des 9 écrans et leur explication |
| `Streamlit/` | Documents de la version Streamlit (captures, inventaires des données, validation) |
| `Validation Plateforme/` | Rapport de phase complet des deux versions et PV de recette global (étape 9 close) |
| `HTML/` | Documents de la version HTML (captures, inventaires des données, validation) |

## Recette

| Version recettée | Recette d'origine | Édition 2 (21/12/2026) | Décision |
|---|---|---|---|
| Streamlit v0.14.1 | PV du 11/12/2026 (v0.12.5) | 73 tests ; test de fumée sur la vraie base : 17 sur 17 | validée sans réserve |
| HTML v1.1.1 | PV du 18/12/2026 (v1.0.0) | test de fumée 17 sur 17 ; comportements 19 sur 19 | validée sans réserve |

Les deux versions affichent les mêmes données et les mêmes textes (141 pages comparées, puis la page Modèles
en édition 2). Chaque document de recette est fourni en Word et en PDF ; le PV global
(`Validation Plateforme/PV_Recette_Global_Plateforme_Vue360.pdf`) prononce la recette des deux versions.
