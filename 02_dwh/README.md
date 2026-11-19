# TuniShop · Étape 2 : création et alimentation du DWH

```
TuniShop_STG_INTEGRATED (vues integ.v_*) ──► TuniShop_DWH (dw : 13 dimensions, 10 faits ; bi : 23 vues)
                                  └── journalisation : TuniShop_ADMIN.audit ──┘
```

## Contenu
| Fichier | Rôle |
|---|---|
| `sql/01_Creation_DWH.sql` | Crée les 13 dimensions, 10 faits, membres -1 / -2, 54 clés étrangères, index columnstore, 23 vues `bi.*` |
| `sql/02_Procedures_DWH.sql` | 25 procédures de chargement + `dw.usp_charger_dwh` (tout en une commande) |
| `sql/03_Charger_DWH.sql` | Lancement du chargement depuis SSMS (option A) + volumes, contrôles, erreurs, contrôle rapide ; script de dépannage si un package SSIS échoue |
| `ssis/TuniShop_DWH_SSIS/DWH_01_Chargement_Dimensions.dtsx` | Package SSIS : les 13 dimensions |
| `ssis/TuniShop_DWH_SSIS/DWH_02_Chargement_Faits.dtsx` | Package SSIS : les 10 faits, puis contrôles qualité et clôture du lot |

## 1. Prérequis
Kit Étape 2 exécuté (scripts 01 à 04) **et** staging chargé (`tunishop_pipeline.py tout`) : le DWH lit les vues `integ.v_*`.

## 2. Créer le DWH (SSMS)
1. `sql/01_Creation_DWH.sql`  ⚠️ recrée les tables du DWH : à exécuter une seule fois (ou pour repartir de zéro).
2. `sql/02_Procedures_DWH.sql` (peut être réexécuté à tout moment : `CREATE OR ALTER`).

Test sans SSIS (option A) : ouvrir `sql/03_Charger_DWH.sql`, renseigner `@lot`, exécuter (F5).

## Chargement incrémental du DWH (aucun TRUNCATE)
| Table | Nouvelle ligne | Ligne modifiée | Ligne disparue du staging |
|---|---|---|---|
| `dim_date` | ajoutée | fériés / Ramadan / période mis à jour | conservée |
| 10 dimensions SCD1 | ajoutée | écrasée | marquée `est_supprime = 1` (réactivée si elle revient) |
| `dim_client` (SCD2) | ajoutée | ancienne version clôturée + nouvelle version ; **même jour** : mise à jour sur place | toutes ses versions marquées |
| `dim_produit` | nouvelle version de prix | mise à jour | marquée |
| 10 faits | ajoutée | mise à jour | marquée `est_supprime = 1` |

- **`dim_date` dynamique** : la plage est recalculée à chaque chargement, du 1er janvier de la plus ancienne date trouvée dans le staging au 31 décembre de l'année suivant la plus récente.
- **Vues `bi.*`** : les vues de faits excluent les lignes `est_supprime = 1` ; les vues de dimensions gardent toutes les lignes (colonne `est_supprime` visible) pour ne jamais casser une relation Power BI.
- Les membres spéciaux -1 (inconnu) et -2 (non applicable) ne sont jamais marqués.
- `02_Procedures_DWH.sql` met aussi à jour `audit.usp_controles_qualite` dans `TuniShop_ADMIN` (réconciliations sur les lignes actives).
- Compteurs par table dans `TuniShop_ADMIN.audit.execution_tache` : `nb_inseres`, `nb_maj`, `nb_supprimes`.

## 3. Les packages SSIS
Ouvrir Visual Studio avec l'extension **SQL Server Integration Services Projects** :
1. Créer un projet *Integration Services Project* (ex. `TuniShop_ETL`).
2. Clic droit sur **SSIS Packages** → **Ajouter un package existant…** → choisir les deux `.dtsx`.
3. Ouvrir chaque package ; si les tâches sont superposées : menu **Format → Disposition automatique → Diagramme**.
4. Exécuter `DWH_01_Chargement_Dimensions`, puis `DWH_02_Chargement_Faits` (F5).

| Élément | Valeur |
|---|---|
| Connexion | `CM_ADMIN` (OLE DB) → base `TuniShop_ADMIN` ; les procédures du DWH sont appelées par leur nom complet `[TuniShop_DWH].dw.…` |
| Paramètre `ServeurSQL` | `localhost` par défaut (ex. `.\SQLEXPRESS`) : alimente le nom du serveur de la connexion |
| Paramètre `IdChargement` | `0` = dernier lot du staging ; sinon numéro de lot précis |
| Variable `User::Lot` | Lot réellement traité, déterminé par la première tâche |

**Déroulé de DWH_01** : Résoudre le lot → `dim_date` → 10 dimensions SCD1 en parallèle → `dim_client` (SCD2) et `dim_produit` en parallèle.
**Déroulé de DWH_02** : Résoudre le lot → 2 conteneurs de 5 faits en parallèle → contrôles qualité → clôture du lot.

Chaque procédure journalise ses volumes (`audit.execution_tache`, couche DWH) et ses erreurs (`audit.journal_erreur`).

## 4. Vérifier
```sql
SELECT * FROM TuniShop_ADMIN.audit.execution_tache WHERE couche = 'DWH' ORDER BY id_tache DESC;
SELECT * FROM TuniShop_ADMIN.audit.controle_resultat ORDER BY id_controle DESC;   -- OK / AVERTISSEMENT / ECHEC
SELECT COUNT(*) FROM TuniShop_DWH.dw.fact_ventes;          -- 115 903 lignes attendues
SELECT SUM(montant_ttc) FROM TuniShop_DWH.bi.v_fact_ventes WHERE est_ca_reconnu = 1;
```

## 5. Si un package ne s'ouvre pas ou échoue
- **Fournisseur OLE DB introuvable** : ouvrir `CM_ADMIN`, choisir *Microsoft OLE DB Driver for SQL Server* (ou *SQL Server Native Client*), base `TuniShop_ADMIN`.
- **Version** : packages au format SSIS 2019+ (PackageFormatVersion 8). Si Visual Studio propose une mise à niveau, accepter.
- Ces fichiers `.dtsx` ont été générés par programme et validés comme XML, **sans** avoir été ouverts dans Visual Studio : en cas de refus d'ouverture, envoyer le message d'erreur.
