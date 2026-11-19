# -*- coding: utf-8 -*-
"""TuniShop - partie 5 : exports, couche brute, documentation."""
import os, json, pickle, shutil, sqlite3, sys
import numpy as np, pandas as pd
BASE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, BASE)
from meta import META
from gen_part4_checks import run_checks

OUT = os.environ.get("TUNISHOP_OUT", os.path.join(BASE, "tunishop_dataset"))
d = pickle.load(open(os.path.join(BASE, "tables.pkl"), "rb"))
T, TRUTH, HOLI = d["TABLES"], d["TRUTH"], d["HOLI"]
if os.path.exists(OUT):
    shutil.rmtree(OUT)
for sub in ["donnees_reference", "donnees_brutes", "docs", "sql", "solutions"]:
    os.makedirs(os.path.join(OUT, sub), exist_ok=True)

# ===================================================== 1. Couche de référence
for k, v in T.items():
    v.to_csv(os.path.join(OUT, "donnees_reference", f"{k}.csv"), index=False, encoding="utf-8")
con = sqlite3.connect(os.path.join(OUT, "donnees_reference", "tunishop_reference.sqlite"))
for k, v in T.items():
    vv = v.copy()
    for c in vv.columns:
        if vv[c].dtype == bool:
            vv[c] = vv[c].astype(int)
    vv.to_sql(k, con, index=False)
con.commit(); con.close()
checks = run_checks(T, HOLI)
assert checks.violations.sum() == 0, checks

# ===================================================== 2. Couche brute (avec anomalies)
rg = np.random.default_rng(7)
R = {k: v.copy() for k, v in T.items()}
AN = []
def log(fichier, table, ident, col, typ, regle, brut, attendu):
    AN.append({"fichier": fichier, "table": table, "identifiant": ident, "colonne": col, "type_anomalie": typ,
               "regle_dq": regle, "valeur_brute": None if brut is None else str(brut), "valeur_attendue": None if attendu is None else str(attendu)})
pick = lambda df, n: rg.choice(df.index.values, size=min(n, len(df)), replace=False)

# --- clients (CRM)
F = "crm/clients.csv"; c = R["clients"]
for i in pick(c, int(len(c) * 0.08)):
    t = c.at[i, "telephone"]; n8 = t[4:]
    v = rg.choice([f"+216 {n8[:2]} {n8[2:5]} {n8[5:]}", n8, f"00216{n8}", f"{n8[:2]}-{n8[2:5]}-{n8[5:]}"])
    c.at[i, "telephone"] = v; log(F, "clients", c.at[i, "client_id"], "telephone", "format_telephone_non_normalise", "DQ-30", v, t)
em = c[c.email.notna()]
for i in pick(em, 320):
    e = c.at[i, "email"]; v = rg.choice([e.upper(), f" {e} ", e.capitalize()])
    c.at[i, "email"] = v; log(F, "clients", c.at[i, "client_id"], "email", "email_non_normalise", "DQ-38", v, e)
for i in pick(em, 80):
    e = c.at[i, "email"]; v = e.replace("@", rg.choice(["", " at ", "@@"]))
    c.at[i, "email"] = v; log(F, "clients", c.at[i, "client_id"], "email", "email_invalide", "DQ-30", v, e)
for i in pick(c, int(len(c) * 0.05)):
    o = c.at[i, "ville"]; v = rg.choice([o.upper(), o.lower(), f"  {o} ", o.replace("é", "e").replace("è", "e").replace("â", "a").replace("ï", "i")])
    if v != o:
        c.at[i, "ville"] = v; log(F, "clients", c.at[i, "client_id"], "ville", "libelle_non_normalise", "DQ-38", v, o)
for i in pick(c, int(len(c) * 0.015)):
    log(F, "clients", c.at[i, "client_id"], "genre", "valeur_manquante", "DQ-41", None, c.at[i, "genre"]); c.at[i, "genre"] = None
bd = c[c.date_naissance.notna()]
for i in pick(bd, int(len(bd) * 0.08)):
    o = c.at[i, "date_naissance"]; v = pd.Timestamp(o).strftime("%d/%m/%Y")
    c.at[i, "date_naissance"] = v; log(F, "clients", c.at[i, "client_id"], "date_naissance", "format_date_non_iso", "DQ-35", v, o)
for i in pick(bd, 35):
    o = c.at[i, "date_naissance"]; v = rg.choice(["1900-01-01", "2031-05-12", "2015-07-03", "1880-11-30"])
    c.at[i, "date_naissance"] = v; log(F, "clients", c.at[i, "client_id"], "date_naissance", "valeur_aberrante", "DQ-41", v, o)
dups = []
for k, i in enumerate(pick(c[c.type_client == "particulier"], 150)):
    r = c.loc[i].copy(); orig = r.client_id
    r["client_id"] = f"CLI9{k+1:05d}"
    if isinstance(r.email, str):
        r["email"] = rg.choice([r.email.upper(), None, r.email.replace("@", "2@")])
    t = T["clients"].at[i, "telephone"]; r["telephone"] = rg.choice([t, t[4:], f"+216 {t[4:6]} {t[6:9]} {t[9:]}"])
    r["date_inscription"] = (pd.Timestamp(T["clients"].at[i, "date_inscription"]) + pd.Timedelta(days=int(rg.integers(30, 400)))).strftime("%Y-%m-%d %H:%M:%S")
    r["segment_fidelite"] = "aucun"
    dups.append(r); log(F, "clients", r.client_id, "*", "doublon_client (même personne, nouveau compte)", "DQ-37", r.client_id, orig)
c = pd.concat([c, pd.DataFrame(dups)], ignore_index=True).sample(frac=1, random_state=3)
R["clients"] = c

# --- produits
F = "catalogue/produits.csv"; p = R["produits"]
for i in pick(p, 6):
    o = p.at[i, "prix_catalogue_ttc_actuel"]; v = rg.choice([0.0, -o])
    p.at[i, "prix_catalogue_ttc_actuel"] = v; log(F, "produits", p.at[i, "produit_id"], "prix_catalogue_ttc_actuel", "valeur_aberrante", "DQ-41", v, o)
for i in pick(p, 6):
    log(F, "produits", p.at[i, "produit_id"], "categorie_id", "valeur_manquante", "DQ-41", None, p.at[i, "categorie_id"]); p.at[i, "categorie_id"] = None
idx = pick(p, 6)
for a, b in zip(idx[:3], idx[3:]):
    o = p.at[b, "sku"]; p.at[b, "sku"] = p.at[a, "sku"]; log(F, "produits", p.at[b, "produit_id"], "sku", "sku_en_double", "DQ-36", p.at[a, "sku"], o)
for i in pick(p, 15):
    o = p.at[i, "marque"]; v = rg.choice([o.upper(), o + " ", o.lower()])
    p.at[i, "marque"] = v; log(F, "produits", p.at[i, "produit_id"], "marque", "libelle_non_normalise", "DQ-38", v, o)

# --- commandes (extractions mensuelles)
F = "ventes/commandes/commandes_AAAA_MM.csv"; o = R["commandes"]
o["_mois"] = o.date_commande.str[:7]
for i in pick(o, int(len(o) * 0.04)):
    v = pd.Timestamp(o.at[i, "date_commande"]).strftime("%d/%m/%Y %H:%M")
    log(F, "commandes", o.at[i, "commande_id"], "date_commande", "format_date_non_iso (secondes perdues)", "DQ-35", v, o.at[i, "date_commande"]); o.at[i, "date_commande"] = v
for i in pick(o, 350):
    s = o.at[i, "statut_commande"]; v = rg.choice([s.upper(), s.capitalize(), f" {s}", s.replace("livree", "livrée").replace("annulee", "annulée")])
    if v != s:
        o.at[i, "statut_commande"] = v; log(F, "commandes", o.at[i, "commande_id"], "statut_commande", "libelle_non_normalise", "DQ-38", v, s)
for k, i in enumerate(pick(o, 25)):
    v = f"CLI0{999000 + k}"; log(F, "commandes", o.at[i, "commande_id"], "client_id", "cle_etrangere_orpheline", "DQ-02", v, o.at[i, "client_id"]); o.at[i, "client_id"] = v
for i in pick(o, 60):
    a = o.at[i, "montant_total_ttc"]; v = rg.choice([o.at[i, "sous_total_ttc"], round(a * 1.19, 3), round(a + 7, 3)])
    if abs(v - a) > 0.001:
        o.at[i, "montant_total_ttc"] = v; log(F, "commandes", o.at[i, "commande_id"], "montant_total_ttc", "total_incoherent", "DQ-03", v, a)
for i in pick(o, int(len(o) * 0.01)):
    log(F, "commandes", o.at[i, "commande_id"], "canal", "valeur_manquante", "DQ-41", None, o.at[i, "canal"]); o.at[i, "canal"] = None
late = pick(o[o._mois < "2025-12"], 60)
for i in late:
    m = pd.Period(o.at[i, "_mois"], "M") + 1
    log(F, "commandes", o.at[i, "commande_id"], "_fichier", "donnee_arrivee_en_retard", "DQ-40", f"commandes_{m.strftime('%Y_%m')}.csv", f"commandes_{o.at[i, '_mois'].replace('-', '_')}.csv")
    o.at[i, "_mois"] = str(m)
dd = o.loc[pick(o, 300)]
for _, r in dd.iterrows():
    log(F, "commandes", r.commande_id, "*", "ligne_en_double (ré-extraction)", "DQ-36", "2 occurrences", "1 occurrence")
o = pd.concat([o, dd]).sort_values("commande_id")
os.makedirs(os.path.join(OUT, "donnees_brutes/ventes/commandes"), exist_ok=True)
for m, g in o.groupby("_mois"):
    g.drop(columns="_mois").to_csv(os.path.join(OUT, f"donnees_brutes/ventes/commandes/commandes_{m.replace('-', '_')}.csv"), index=False, encoding="utf-8")

# --- lignes de commande (extractions mensuelles alignées sur le mois de commande)
F = "ventes/lignes_commande/lignes_commande_AAAA_MM.csv"; l = R["lignes_commande"]
mois_cmd = T["commandes"].set_index("commande_id").date_commande.str[:7]
l["_mois"] = l.commande_id.map(mois_cmd)
for i in pick(l, 45):
    q = l.at[i, "quantite"]; v = -q if rg.random() < 0.67 else 0
    l.at[i, "quantite"] = v; log(F, "lignes_commande", l.at[i, "ligne_id"], "quantite", "quantite_negative_ou_nulle", "DQ-06", v, q)
for k, i in enumerate(pick(l, 20)):
    v = f"PRD9{k:03d}"; log(F, "lignes_commande", l.at[i, "ligne_id"], "produit_id", "cle_etrangere_orpheline", "DQ-02", v, l.at[i, "produit_id"]); l.at[i, "produit_id"] = v
for i in pick(l, 40):
    a = l.at[i, "montant_ligne_ttc"]; v = round(a * float(rg.choice([10, 0.1, 1.07])), 3)
    l.at[i, "montant_ligne_ttc"] = v; log(F, "lignes_commande", l.at[i, "ligne_id"], "montant_ligne_ttc", "montant_incoherent", "DQ-05", v, a)
dd = l.loc[pick(l, 120)]
for _, r in dd.iterrows():
    log(F, "lignes_commande", r.ligne_id, "*", "ligne_en_double", "DQ-36", "2 occurrences", "1 occurrence")
l = pd.concat([l, dd]).sort_values("ligne_id")
os.makedirs(os.path.join(OUT, "donnees_brutes/ventes/lignes_commande"), exist_ok=True)
for m, g in l.groupby("_mois"):
    g.drop(columns="_mois").to_csv(os.path.join(OUT, f"donnees_brutes/ventes/lignes_commande/lignes_commande_{m.replace('-', '_')}.csv"), index=False, encoding="utf-8")

# --- paiements (API JSON Lines, UTC, codes anglais)
F = "paiements_api/paiements.jsonl"; pa = R["paiements"]
MODE_API = {"paiement_a_la_livraison": "COD", "carte_bancaire": "CARD", "portefeuille_mobile": "WALLET", "carte_prepayee": "PREPAID_CARD", "virement": "BANK_TRANSFER"}
STAT_API = {"reussi": "SUCCESS", "echoue": "FAILED", "encaisse": "COLLECTED"}
for i in pick(pa, 50):
    a = pa.at[i, "montant_ttc"]; pa.at[i, "montant_ttc"] = round(a * 1000); log(F, "paiements", pa.at[i, "paiement_id"], "montant_ttc", "montant_en_millimes", "DQ-39", round(a * 1000), a)
for k, i in enumerate(pick(pa, 15)):
    v = f"CMD9{k:06d}"; log(F, "paiements", pa.at[i, "paiement_id"], "commande_id", "cle_etrangere_orpheline", "DQ-02", v, pa.at[i, "commande_id"]); pa.at[i, "commande_id"] = v
dd = pa.loc[pick(pa, int(len(pa) * 0.01))]
for _, r in dd.iterrows():
    log(F, "paiements", r.paiement_id, "*", "webhook_renvoye (doublon)", "DQ-36", "2 occurrences", "1 occurrence")
pa = pd.concat([pa, dd]).sort_values("paiement_id")
os.makedirs(os.path.join(OUT, "donnees_brutes/paiements_api"), exist_ok=True)
with open(os.path.join(OUT, "donnees_brutes/paiements_api/paiements.jsonl"), "w", encoding="utf-8") as f:
    for r in pa.itertuples(index=False):
        utc = (pd.Timestamp(r.date_paiement) - pd.Timedelta(hours=1)).strftime("%Y-%m-%dT%H:%M:%SZ")
        nn = lambda x: None if x is None or (isinstance(x, float) and np.isnan(x)) else x
        rec = {"payment_id": r.paiement_id, "order_ref": r.commande_id, "attempt": int(r.num_tentative), "method": MODE_API[r.mode_paiement],
               "amount": {"value": float(r.montant_ttc), "currency": "TND"}, "status": STAT_API[r.statut_paiement], "error_code": nn(r.code_erreur),
               "created_at": utc, "provider": r.prestataire, "transaction_ref": r.reference_transaction, "settlement_date": nn(r.date_reversement)}
        f.write(json.dumps(rec, ensure_ascii=False) + "\n")

# --- remboursements
F = "sav/remboursements.csv"; rb = R["remboursements"]
ok = rb[(rb.statut == "rembourse") & (rb.type_remboursement == "retour")]
for i in pick(ok, 20):
    a = rb.at[i, "montant_rembourse_ttc"]; v = round(a * float(rg.choice([2, 10, 1.6])), 3)
    rb.at[i, "montant_rembourse_ttc"] = v; log(F, "remboursements", rb.at[i, "remboursement_id"], "montant_rembourse_ttc", "montant_superieur_a_la_ligne", "DQ-19", v, a)
for i in pick(ok, 15):
    a = rb.at[i, "date_remboursement"]; v = (pd.Timestamp(rb.at[i, "date_demande"]) - pd.Timedelta(days=int(rg.integers(1, 6)))).strftime("%Y-%m-%d %H:%M:%S")
    rb.at[i, "date_remboursement"] = v; log(F, "remboursements", rb.at[i, "remboursement_id"], "date_remboursement", "chronologie_incoherente", "DQ-20", v, a)

# --- livraisons
F = "logistique/livraisons.csv"; lv = R["livraisons"]
dl = lv[lv.date_livraison_reelle.notna()]
for i in pick(dl, 25):
    a = lv.at[i, "date_livraison_reelle"]; v = (pd.Timestamp(lv.at[i, "date_expedition"]) - pd.Timedelta(days=int(rg.integers(1, 4)))).strftime("%Y-%m-%d %H:%M:%S")
    lv.at[i, "date_livraison_reelle"] = v; log(F, "livraisons", lv.at[i, "livraison_id"], "date_livraison_reelle", "chronologie_incoherente", "DQ-12", v, a)
for i in pick(lv, 100):
    a = lv.at[i, "transporteur_id"]; lv.at[i, "transporteur_id"] = a.lower(); log(F, "livraisons", lv.at[i, "livraison_id"], "transporteur_id", "casse_identifiant", "DQ-38", a.lower(), a)
for i in pick(lv, 30):
    log(F, "livraisons", lv.at[i, "livraison_id"], "statut_livraison", "valeur_manquante", "DQ-41", None, lv.at[i, "statut_livraison"]); lv.at[i, "statut_livraison"] = None

# --- stocks
F = "stocks/mouvements_stock.csv"; mv = R["mouvements_stock"]
for i in pick(mv[mv.type_mouvement == "vente"], 40):
    a = mv.at[i, "quantite"]; mv.at[i, "quantite"] = -a; log(F, "mouvements_stock", mv.at[i, "mouvement_id"], "quantite", "signe_inverse", "DQ-22", -a, a)
dd = mv.loc[pick(mv, 100)]
for _, r in dd.iterrows():
    log(F, "mouvements_stock", r.mouvement_id, "*", "ligne_en_double", "DQ-36", "2 occurrences", "1 occurrence")
R["mouvements_stock"] = pd.concat([mv, dd]).sort_values("mouvement_id")
F = "stocks/stocks_mensuels.csv"; st = R["stocks_mensuels"]
for i in pick(st[st.stock_fin_mois > 0], 10):
    a = st.at[i, "stock_fin_mois"]; st.at[i, "stock_fin_mois"] = -a; log(F, "stocks_mensuels", st.at[i, "inventaire_id"], "stock_fin_mois", "stock_negatif", "DQ-25", -a, a)

# --- achats
F = "achats/commandes_fournisseurs.csv"; cf = R["commandes_fournisseurs"]
for i in pick(cf[cf.date_reception.notna()], 8):
    a = cf.at[i, "date_reception"]; v = (pd.Timestamp(cf.at[i, "date_commande"]) - pd.Timedelta(days=int(rg.integers(1, 10)))).strftime("%Y-%m-%d %H:%M:%S")
    cf.at[i, "date_reception"] = v; log(F, "commandes_fournisseurs", cf.at[i, "commande_fournisseur_id"], "date_reception", "chronologie_incoherente", "DQ-24", v, a)
F = "achats/lignes_commande_fournisseur.csv"; lc = R["lignes_commande_fournisseur"]
for i in pick(lc[lc.quantite_recue.notna()], 10):
    a = lc.at[i, "quantite_recue"]; v = int(lc.at[i, "quantite_commandee"]) * 10
    lc.at[i, "quantite_recue"] = v; log(F, "lignes_commande_fournisseur", lc.at[i, "ligne_cf_id"], "quantite_recue", "recu_superieur_commande", "DQ-24", v, a)

# --- marketing (export régie : séparateur ; décimale , dates JJ/MM/AAAA)
F = "marketing/marketing_depenses_quotidiennes.csv"; mk = R["marketing_depenses_quotidiennes"]
for i in pick(mk, 10):
    a = mk.at[i, "depense_ht"]; mk.at[i, "depense_ht"] = -a; log(F, "marketing_depenses_quotidiennes", mk.at[i, "depense_id"], "depense_ht", "valeur_negative", "DQ-26", -a, a)
for i in pick(mk[mk.clics > 0], 15):
    a = mk.at[i, "impressions"]; v = int(mk.at[i, "clics"]) // 2
    mk.at[i, "impressions"] = v; log(F, "marketing_depenses_quotidiennes", mk.at[i, "depense_id"], "impressions", "clics_superieurs_impressions", "DQ-26", v, a)
for k, i in enumerate(pick(mk, 5)):
    v = f"CMP9{k:03d}"; log(F, "marketing_depenses_quotidiennes", mk.at[i, "depense_id"], "campagne_id", "cle_etrangere_orpheline", "DQ-02", v, mk.at[i, "campagne_id"]); mk.at[i, "campagne_id"] = v
mk["date"] = pd.to_datetime(mk.date).dt.strftime("%d/%m/%Y")

# --- avis
F = "avis/avis_clients.csv"; av = R["avis_clients"]
for i in pick(av, 10):
    a = av.at[i, "note"]; v = int(rg.choice([0, 6, 10])); av.at[i, "note"] = v; log(F, "avis_clients", av.at[i, "avis_id"], "note", "note_hors_plage", "DQ-29", v, a)
cm = av[av.commentaire.notna()]
for i in pick(cm, 20):
    a = av.at[i, "commentaire"]; v = rg.choice([f"<p>{a}</p>", f"   {a}   ", f"{a}<br/>"]); av.at[i, "commentaire"] = v
    log(F, "avis_clients", av.at[i, "avis_id"], "commentaire", "texte_non_nettoye (HTML/espaces)", "DQ-38", v, a)
dd = av.loc[pick(av, 30)]
for _, r in dd.iterrows():
    log(F, "avis_clients", r.avis_id, "*", "ligne_en_double", "DQ-36", "2 occurrences", "1 occurrence")
R["avis_clients"] = pd.concat([av, dd]).sort_values("avis_id")

LAYOUT = {"crm": ["clients"], "catalogue": ["produits", "categories", "produits_prix_historique", "fournisseurs"],
          "sav": ["remboursements"], "logistique": ["livraisons", "transporteurs", "entrepots"], "stocks": ["mouvements_stock", "stocks_mensuels"],
          "achats": ["commandes_fournisseurs", "lignes_commande_fournisseur"], "marketing": ["campagnes_marketing", "coupons", "marketing_depenses_quotidiennes"],
          "avis": ["avis_clients"], "referentiels": ["ref_gouvernorats", "dim_calendrier"]}
for folder, tabs in LAYOUT.items():
    os.makedirs(os.path.join(OUT, "donnees_brutes", folder), exist_ok=True)
    for t in tabs:
        path = os.path.join(OUT, "donnees_brutes", folder, f"{t}.csv")
        if folder == "marketing":
            R[t].to_csv(path, index=False, sep=";", decimal=",", encoding="utf-8")
        else:
            R[t].to_csv(path, index=False, encoding="utf-8")
ANDF = pd.DataFrame(AN); ANDF.insert(0, "anomalie_id", [f"ANO{i+1:05d}" for i in range(len(ANDF))])
ANDF.to_csv(os.path.join(OUT, "solutions", "anomalies_injectees.csv"), index=False, encoding="utf-8")
TRUTH.to_csv(os.path.join(OUT, "solutions", "verite_terrain_clients.csv"), index=False, encoding="utf-8")
print("anomalies :", len(ANDF)); print(ANDF.groupby("regle_dq").size())

# ===================================================== 3. Documentation générée
vol = pd.DataFrame([(k, len(v), len(v.columns), META[k][1]) for k, v in T.items()], columns=["table", "lignes", "colonnes", "grain"])
def sqltype(s, col):
    if col.startswith("date") and s.dtype == object or col.startswith("date_") or col == "date":
        return "TIMESTAMP" if s.dropna().astype(str).str.len().max() > 10 else "DATE"
    if s.dtype == bool: return "BOOLEAN"
    if str(s.dtype) in ("int64", "Int64", "int32"): return "INTEGER"
    if str(s.dtype).startswith("float"): return "NUMERIC(14,3)"
    return f"VARCHAR({max(20, int(s.dropna().astype(str).str.len().max() * 1.5 // 10 * 10 + 10)) if s.notna().any() else 50})"
PK = {"ref_gouvernorats": "gouvernorat_id", "dim_calendrier": "date", "entrepots": "entrepot_id", "transporteurs": "transporteur_id", "fournisseurs": "fournisseur_id",
      "categories": "categorie_id", "produits": "produit_id", "produits_prix_historique": "prix_id", "clients": "client_id", "campagnes_marketing": "campagne_id",
      "coupons": "code_coupon", "marketing_depenses_quotidiennes": "depense_id", "commandes": "commande_id", "lignes_commande": "ligne_id", "paiements": "paiement_id",
      "remboursements": "remboursement_id", "livraisons": "livraison_id", "commandes_fournisseurs": "commande_fournisseur_id",
      "lignes_commande_fournisseur": "ligne_cf_id", "mouvements_stock": "mouvement_id", "stocks_mensuels": "inventaire_id", "avis_clients": "avis_id"}
FKS = {("clients", "gouvernorat_id"): "ref_gouvernorats", ("clients", "campagne_acquisition_id"): "campagnes_marketing", ("produits", "categorie_id"): "categories",
       ("produits", "fournisseur_id"): "fournisseurs", ("produits_prix_historique", "produit_id"): "produits", ("entrepots", "gouvernorat_id"): "ref_gouvernorats",
       ("campagnes_marketing", "categorie_ciblee_id"): "categories", ("coupons", "campagne_id"): "campagnes_marketing",
       ("marketing_depenses_quotidiennes", "campagne_id"): "campagnes_marketing", ("commandes", "client_id"): "clients",
       ("commandes", "gouvernorat_livraison_id"): "ref_gouvernorats", ("commandes", "entrepot_id"): "entrepots", ("commandes", "campagne_id"): "campagnes_marketing",
       ("commandes", "code_coupon"): "coupons", ("lignes_commande", "commande_id"): "commandes", ("lignes_commande", "produit_id"): "produits",
       ("paiements", "commande_id"): "commandes", ("remboursements", "commande_id"): "commandes", ("remboursements", "ligne_id"): "lignes_commande",
       ("livraisons", "commande_id"): "commandes", ("livraisons", "entrepot_id"): "entrepots", ("livraisons", "transporteur_id"): "transporteurs",
       ("livraisons", "gouvernorat_destination_id"): "ref_gouvernorats", ("commandes_fournisseurs", "fournisseur_id"): "fournisseurs",
       ("commandes_fournisseurs", "entrepot_id"): "entrepots", ("lignes_commande_fournisseur", "commande_fournisseur_id"): "commandes_fournisseurs",
       ("lignes_commande_fournisseur", "produit_id"): "produits", ("mouvements_stock", "produit_id"): "produits", ("mouvements_stock", "entrepot_id"): "entrepots",
       ("stocks_mensuels", "produit_id"): "produits", ("stocks_mensuels", "entrepot_id"): "entrepots", ("avis_clients", "commande_id"): "commandes",
       ("avis_clients", "ligne_id"): "lignes_commande", ("avis_clients", "produit_id"): "produits", ("avis_clients", "client_id"): "clients",
       ("ref_gouvernorats", "entrepot_rattachement_id"): "entrepots", ("campagnes_marketing", "code_coupon"): "coupons"}
ORDER = ["ref_gouvernorats", "dim_calendrier", "entrepots", "transporteurs", "fournisseurs", "categories", "produits", "produits_prix_historique",
         "campagnes_marketing", "coupons", "clients", "marketing_depenses_quotidiennes", "commandes", "lignes_commande", "paiements", "remboursements",
         "livraisons", "commandes_fournisseurs", "lignes_commande_fournisseur", "mouvements_stock", "stocks_mensuels", "avis_clients"]
TYPES = {t: {c: sqltype(T[t][c], c) for c in T[t].columns} for t in T}
for t in T:
    for c in T[t].columns:
        if c in ("date_naissance", "date_debut", "date_fin", "date_lancement", "date_arret", "date_ouverture", "date_debut_contrat", "date_livraison_prevue",
                 "date_reversement", "date_inventaire", "date"):
            TYPES[t][c] = "DATE"
ddl = ["-- TuniShop : schéma PostgreSQL de la couche de référence (généré automatiquement)", "-- Charger avec : \\copy <table> FROM 'donnees_reference/<table>.csv' CSV HEADER", "CREATE SCHEMA IF NOT EXISTS tunishop;", "SET search_path TO tunishop;", ""]
for t in ORDER:
    cols = [f"    {c} {TYPES[t][c]}{' PRIMARY KEY' if PK[t] == c else ''}" for c in T[t].columns]
    ddl.append(f"-- {META[t][0]}\nCREATE TABLE {t} (\n" + ",\n".join(cols) + "\n);\n")
ddl.append("-- Clés étrangères (ajoutées après chargement ; les références circulaires gouvernorats<->entrepots et campagnes<->coupons sont incluses)")
for (t, c), rt in FKS.items():
    ddl.append(f"ALTER TABLE {t} ADD CONSTRAINT fk_{t[:20]}_{c[:25]} FOREIGN KEY ({c}) REFERENCES {rt}({PK[rt]});")
open(os.path.join(OUT, "sql", "schema_postgres.sql"), "w", encoding="utf-8").write("\n".join(ddl) + "\n")

# dictionnaire
dic = ["# Dictionnaire de données - TuniShop", "", "Couche de référence (`donnees_reference/`). Encodage UTF-8, séparateur virgule, décimale point, dates ISO 8601, heure locale Tunis (UTC+1, sans heure d'été).",
       "Montants en dinars tunisiens (DT, code ISO TND) avec 3 décimales (millimes). PK = clé primaire, FK = clé étrangère.", ""]
for t in ORDER:
    desc, grain, cols = META[t]
    dic += [f"## {t}", "", f"{desc} Grain : {grain}. Volume : {len(T[t]):,} lignes.".replace(",", " "), "", "| Colonne | Type | Clé | Nullable | Exemple | Description |", "|---|---|---|---|---|---|"]
    for c in T[t].columns:
        s = T[t][c]; ex = s.dropna().iloc[len(s.dropna()) // 2] if s.notna().any() else ""
        key = "PK" if PK[t] == c else (f"FK → {FKS[(t, c)]}" if (t, c) in FKS else "")
        dic.append(f"| `{c}` | {TYPES[t][c]} | {key} | {'oui' if s.isna().any() else 'non'} | {str(ex)[:40]} | {cols.get(c, '')} |")
    dic.append("")
dic += ["## Différences de la couche brute (`donnees_brutes/`)", "",
        "La couche brute reproduit des exports de systèmes sources hétérogènes. Les colonnes sont identiques à la couche de référence sauf indication contraire.", "",
        "| Source | Particularités à traiter |", "|---|---|",
        "| `ventes/commandes/commandes_AAAA_MM.csv` | 36 extractions mensuelles + données arrivées en retard dans le fichier du mois suivant ; doublons de ré-extraction. |",
        "| `ventes/lignes_commande/lignes_commande_AAAA_MM.csv` | Découpage mensuel selon la date de commande. |",
        "| `paiements_api/paiements.jsonl` | JSON Lines issu de l'API de la passerelle : champs en anglais, montant imbriqué `amount.value`, horodatage `created_at` en **UTC** (ajouter 1 h pour l'heure de Tunis). Correspondances : `method` COD→paiement_a_la_livraison, CARD→carte_bancaire, WALLET→portefeuille_mobile, PREPAID_CARD→carte_prepayee, BANK_TRANSFER→virement ; `status` SUCCESS→reussi, FAILED→echoue, COLLECTED→encaisse ; `payment_id`→paiement_id, `order_ref`→commande_id, `attempt`→num_tentative, `error_code`→code_erreur, `provider`→prestataire, `transaction_ref`→reference_transaction, `settlement_date`→date_reversement. |",
        "| `marketing/*.csv` | Export régie publicitaire : séparateur `;`, décimale `,`, dates `JJ/MM/AAAA` dans le fichier quotidien. |",
        "| `crm/clients.csv` | Contient des comptes en double (identifiants CLI9xxxxx) et des formats de téléphone / email / date non normalisés. |", ""]
open(os.path.join(OUT, "docs", "dictionnaire_donnees.md"), "w", encoding="utf-8").write("\n".join(dic))

# rapport de vérification
rep = ["# Rapport de vérification automatique", "", f"Contrôles exécutés sur la couche de référence par `generateur/gen_part4_checks.py`. Résultat attendu : 0 violation partout.", "",
       "| Règle | Contrôle | Violations |", "|---|---|---|"] + [f"| {r.regle} | {r.description} | {r.violations} |" for r in checks.itertuples()]
rep += ["", "## Anomalies injectées dans la couche brute", "", f"Total : {len(ANDF)} anomalies, détail ligne à ligne dans `anomalies_injectees.csv`.", "", "| Règle | Type d'anomalie | Nombre |", "|---|---|---|"]
for (rr, tt), n in ANDF.groupby(["regle_dq", "type_anomalie"]).size().items():
    rep.append(f"| {rr} | {tt} | {n} |")
open(os.path.join(OUT, "solutions", "rapport_verification.md"), "w", encoding="utf-8").write("\n".join(rep) + "\n")
vol.to_csv(os.path.join(BASE, "volumetrie.csv"), index=False)
print(vol.to_string(index=False))
