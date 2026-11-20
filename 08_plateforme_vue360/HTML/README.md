# Plateforme vue 360 — version HTML

Site statique (HTML, CSS, JavaScript) publié sur GitHub Pages : mêmes écrans, mêmes données et mêmes textes
que la version Streamlit, sans serveur.

| En ligne | Code |
|---|---|
| [sarraabdeljaouad-ui.github.io/Tunishop-plateforme-360-web](https://sarraabdeljaouad-ui.github.io/Tunishop-plateforme-360-web/) | [Tunishop-plateforme-360-web](https://github.com/sarraabdeljaouad-ui/Tunishop-plateforme-360-web) |

Version recettée : **v1.1.1** (page Modèles : modèle évalué et modèle de production sur chaque carte, suivi dans le temps).

## Contenu de ce dossier

| Dossier | Contenu |
|---|---|
| `Validation Plateforme Web/` | Note de conception, cahier de recette (Excel et PDF), rapport de recette, PV, rapport de phase ; édition 2 du 21/12/2026, en Word et en PDF |
| `Captures_HTML/` | Captures C01 à C16 (recette d'origine), C17 et C18 (page Modèles, édition 2), aperçus de la charte |
| `Inventaire des données/` | `Inventaire_des_données.csv` : les données lues par la version HTML |

## Recette en bref

- Recette d'origine (v1.0.0, PV du 18/12/2026) : 10 critères conformes sur 10, 39 cas réussis, 141 pages comparées à
  la version Streamlit, identiques ; test de fumée 17 sur 17 en local et en ligne ; 19 comportements sur 19.
- Édition 2 (v1.1.1) : 5 cas ajoutés pour la page Modèles, tous réussis ; test de fumée 17 sur 17 sur le poste de
  recette ; page Modèles identique à la version Streamlit.
- Mise à jour des données : `scripts/mettre_a_jour.ps1` du dépôt du site (exports des deux versions, tests, envoi).
