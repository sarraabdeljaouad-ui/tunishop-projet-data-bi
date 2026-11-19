# -*- coding: utf-8 -*-
"""TuniShop - partie 3 : construction des tables finales (couche de référence)."""
import os
_HERE = os.path.dirname(os.path.abspath(__file__))
exec(open(os.path.join(_HERE, "gen_part2.py"), encoding="utf-8").read())

TSF = "%Y-%m-%d %H:%M:%S"
O = pd.DataFrame(orders)
L = pd.DataFrame(lines_out)
PAY = pd.DataFrame(payments)
RMB = pd.DataFrame(refunds)
LIV = pd.DataFrame(shipments)
CF = pd.DataFrame(pos)
LCF = pd.DataFrame(po_lines)
MV = pd.DataFrame(movements, columns=["mouvement_id", "date_mouvement", "produit_id", "entrepot_id", "type_mouvement", "quantite", "reference_id", "cout_unitaire_ht"])
MV = MV[MV.date_mouvement <= CUTOFF].sort_values(["date_mouvement", "mouvement_id"]).reset_index(drop=True)

# ------------------------------------------------ Clients
first_order = O.groupby("client_id").date_commande.min()
cust = []
for c in range(N_CUST):
    cid = f"CLI{c+1:06d}"
    g = gender[c]
    fn = rng.choice(FN_F if g == "F" else FN_M); ln = rng.choice(LN)
    sday = START + pd.Timedelta(days=int(sign_day[c]))
    st = sday + pd.Timedelta(hours=int(rng.integers(7, 24)), minutes=int(rng.integers(0, 60)), seconds=int(rng.integers(0, 60)))
    fo = first_order.get(cid)
    if fo is not None and fo < st:
        st = max(sday, fo - pd.Timedelta(minutes=int(rng.integers(2, 30))))
    pro = persona[c] == "professionnel"
    age = int(np.clip(rng.gamma(6, 5.5) + 16, 18, 75))
    bd = pd.Timestamp("2025-12-31") - pd.Timedelta(days=age * 365 + int(rng.integers(0, 365)))
    dom = rng.choice(["gmail.com", "yahoo.fr", "hotmail.com", "outlook.com", "topnet.tn", "gnet.tn"], p=[0.55, 0.12, 0.13, 0.1, 0.06, 0.04])
    slug = lambda s: s.lower().replace(" ", "").replace("ï", "i").replace("é", "e").replace("è", "e").replace("â", "a")
    email = f"{slug(fn)}.{slug(ln)}{rng.integers(1, 999)}@{dom}"
    if not pro and rng.random() < 0.025:
        email = None  # inscription par téléphone uniquement
    tel = "+216" + str(rng.choice([2, 5, 9, 4], p=[0.38, 0.27, 0.30, 0.05])) + "".join(str(x) for x in rng.integers(0, 10, 7))
    camp = None; can = None
    if sign_day[c] >= 0:
        acq = [i for i in active_camps[int(sign_day[c])] if C.at[i, "objectif"] == "acquisition"]
        if acq and rng.random() < 0.55:
            i = acq[int(rng.integers(0, len(acq)))]
            camp = C.at[i, "campagne_id"]
            can = {"facebook_ads": "reseaux_sociaux", "instagram_ads": "reseaux_sociaux", "tiktok_ads": "reseaux_sociaux",
                   "influence": "reseaux_sociaux", "google_ads": "moteur_recherche_payant", "emailing": "emailing", "sms": "sms"}[C.at[i, "canal"]]
    if can is None:
        can = rng.choice(["acces_direct", "recherche_naturelle", "parrainage", "application_mobile"], p=[0.35, 0.3, 0.12, 0.23])
    cust.append({"client_id": cid, "type_client": "professionnel" if pro else "particulier",
                 "prenom": fn, "nom": ln, "genre": g, "date_naissance": None if pro else bd.strftime("%Y-%m-%d"),
                 "raison_sociale": f"{ln} {rng.choice(['Services', 'Commerce', 'Distribution', 'Bureautique', 'Équipements'])} {rng.choice(COMPANY)}" if pro else None,
                 "matricule_fiscal": f"{rng.integers(1000000, 9999999)}{rng.choice(list('ABCDEFGHJKLMNPQRSTVWXYZ'))}/{rng.choice(['A', 'B', 'D', 'N', 'P'])}/M/000" if pro else None,
                 "email": email, "telephone": tel, "gouvernorat_id": GOV_IDS[gov_idx[c]], "ville": rng.choice(GOV_CITIES[GOV_IDS[gov_idx[c]]]),
                 "date_inscription": st, "canal_inscription": can, "campagne_acquisition_id": camp,
                 "opt_in_email": bool(email is not None and rng.random() < 0.62), "opt_in_sms": bool(rng.random() < 0.48)})
CL = pd.DataFrame(cust)

# Segment fidélité : CA net 2025 (commandes livrées/retournées - remboursements)
net = O[O.statut_commande.isin(["livree", "retournee", "partiellement_retournee"]) & (O.date_commande.dt.year == 2025)]
ca = net.groupby("client_id").montant_total_ttc.sum()
rb = RMB[(RMB.statut == "rembourse") & RMB.commande_id.isin(net.commande_id)].groupby("commande_id").montant_rembourse_ttc.sum()
rbc = O.set_index("commande_id").loc[rb.index, "client_id"].to_frame().assign(m=rb.values).groupby("client_id").m.sum()
ca_net = ca.sub(rbc, fill_value=0)
CL["ca_net_2025_ttc"] = CL.client_id.map(ca_net).fillna(0).round(3)
CL["segment_fidelite"] = np.select([CL.ca_net_2025_ttc >= 1500, CL.ca_net_2025_ttc >= 500, CL.ca_net_2025_ttc > 0], ["or", "argent", "bronze"], "aucun")
CL = CL.drop(columns=["ca_net_2025_ttc"])

# ------------------------------------------------ Produits (vue actuelle)
PR = P[["produit_id", "sku", "nom_produit", "categorie_id", "marque", "fournisseur_id", "poids_kg", "date_lancement", "date_arret"]].copy()
PR["prix_catalogue_ttc_actuel"] = [price_by_year[(i, 2025)] if (P.date_arret.iat[i] is None or pd.isna(P.date_arret.iat[i])) else price_by_year[(i, P.date_arret.iat[i].year)] for i in range(NP_)]
PR["cout_achat_unitaire_ht_actuel"] = [cost_by_year[(i, 2025)] if (P.date_arret.iat[i] is None or pd.isna(P.date_arret.iat[i])) else cost_by_year[(i, P.date_arret.iat[i].year)] for i in range(NP_)]
PR["taux_tva"] = P.tva.values
PR["statut_produit"] = np.where(P.date_arret.isna(), "actif", "arrete")
PR["date_lancement"] = PR.date_lancement.dt.strftime("%Y-%m-%d")
PR["date_arret"] = [x.strftime("%Y-%m-%d") if x is not None and not pd.isna(x) else None for x in P.date_arret]
PR = PR[["produit_id", "sku", "nom_produit", "categorie_id", "marque", "fournisseur_id", "prix_catalogue_ttc_actuel", "cout_achat_unitaire_ht_actuel",
         "taux_tva", "poids_kg", "date_lancement", "date_arret", "statut_produit"]]

# ------------------------------------------------ Avis clients
POS_TXT = ["Très satisfait, produit conforme et livraison rapide.", "Excellent rapport qualité/prix, je recommande.", "Behi barcha, livraison fi wa9tha.",
           "Produit de bonne qualité, emballage soigné.", "Rien à dire, parfait !", "Mriguel, merci TuniShop.", "Conforme à la photo, très contente.",
           "Deuxième commande, toujours aussi satisfait."]
NEU_TXT = ["Produit correct mais livraison un peu longue.", "Moyen, je m'attendais à mieux.", "Bon produit mais emballage abîmé.", "Ça va, sans plus."]
NEG_TXT = ["Livraison très en retard, aucun suivi.", "Produit non conforme à la description.", "Qualité décevante, je ne recommande pas.",
           "Le livreur n'a jamais appelé.", "Taille trop petite, retour compliqué.", "Khayeb, ma3jebnich.", "Service client injoignable."]
RMB_RET = RMB[RMB.type_remboursement == "retour"]
ret_motif = dict(zip(RMB_RET.ligne_id, RMB_RET.motif))
av = []; aseq = 0
for (oid, c, lids, lns, dt_, late, st) in review_candidates:
    pr = 0.14 + (0.12 if late >= 2 or st != "livree" else 0)
    if rng.random() >= pr:
        continue
    j = int(rng.integers(0, len(lids)))
    note = float(rng.choice([5, 4, 3, 2, 1], p=[0.55, 0.28, 0.09, 0.04, 0.04]))
    if late >= 3: note -= rng.uniform(1, 2.5)
    elif late >= 1: note -= rng.uniform(0, 1)
    m = ret_motif.get(lids[j])
    if m in ("produit_defectueux", "ne_correspond_pas_a_la_description", "qualite_decevante", "colis_endommage"):
        note -= rng.uniform(1.5, 3)
    note = int(np.clip(round(note), 1, 5))
    da = dt_ + pd.Timedelta(days=int(rng.integers(1, 16)), hours=int(rng.integers(0, 12)))
    if da > CUTOFF:
        continue
    txt = None
    if rng.random() > 0.35:
        txt = rng.choice(POS_TXT if note >= 4 else (NEU_TXT if note == 3 else NEG_TXT))
    aseq += 1
    av.append({"avis_id": f"AVI{aseq:06d}", "commande_id": oid, "ligne_id": lids[j], "produit_id": P.produit_id.iat[lns[j][0]], "client_id": f"CLI{c+1:06d}",
               "date_avis": da, "note": note, "commentaire": txt, "achat_verifie": True})
AV = pd.DataFrame(av)

# ------------------------------------------------ Marketing : dépenses quotidiennes + attribution
valid = O[O.statut_commande != "paiement_echoue"].copy()
valid["jour"] = valid.date_commande.dt.normalize()
attr = valid.dropna(subset=["campagne_id"]).groupby(["campagne_id", "jour"]).agg(n=("commande_id", "size"), ca=("montant_total_ttc", "sum"))
new_c = valid[valid.est_premiere_commande].dropna(subset=["campagne_id"]).groupby(["campagne_id", "jour"]).size()
md = []; mseq = 0
for i in C.index:
    ch = C.at[i, "canal"]; cpm, ctr = CH[ch][3], CH[ch][4]
    days_c = pd.date_range(C.at[i, "date_debut"], C.at[i, "date_fin"])
    sp = C.at[i, "budget_j"] * rng.uniform(0.75, 1.15, len(days_c))
    sp = np.minimum(sp, C.at[i, "budget_j"] * 1.15)
    scale = min(1.0, C.at[i, "budget_j"] * len(days_c) / sp.sum())
    for dday, s in zip(days_c, sp * scale):
        imp = int(s / cpm * 1000 * rng.uniform(0.8, 1.2))
        clk = int(imp * ctr * rng.uniform(0.7, 1.3))
        key = (C.at[i, "campagne_id"], dday)
        n = int(attr.n.get(key, 0)); caa = float(attr.ca.get(key, 0.0))
        clk = max(clk, n)
        mseq += 1
        md.append({"depense_id": f"MKT{mseq:06d}", "campagne_id": C.at[i, "campagne_id"], "date": dday.strftime("%Y-%m-%d"), "canal": ch,
                   "depense_ht": r3(s), "impressions": max(imp, clk), "clics": clk, "commandes_attribuees": n,
                   "nouveaux_clients_attribues": int(new_c.get(key, 0)), "ca_attribue_ttc": r3(caa)})
MK = pd.DataFrame(md)
CMP = C[["campagne_id", "nom_campagne", "canal", "objectif", "theme", "categorie_ciblee_id", "code_coupon", "date_debut", "date_fin"]].copy()
CMP["budget_ht"] = C.budget_ttc.values
CMP["date_debut"] = CMP.date_debut.dt.strftime("%Y-%m-%d"); CMP["date_fin"] = CMP.date_fin.dt.strftime("%Y-%m-%d")

# ------------------------------------------------ Stocks mensuels (calculés depuis le grand livre des mouvements)
months = pd.period_range("2023-01", "2025-12", freq="M")
MV["mois"] = MV.date_mouvement.dt.to_period("M")
piv = MV.groupby(["produit_id", "entrepot_id", "mois"]).quantite.sum()
idx = pd.MultiIndex.from_product([P.produit_id, WH, months], names=["produit_id", "entrepot_id", "mois"])
piv = piv.reindex(idx, fill_value=0).groupby(level=[0, 1]).cumsum().rename("stock_fin_mois").reset_index()
pidx = {p: i for i, p in enumerate(P.produit_id)}
piv["launch"] = piv.produit_id.map(dict(zip(P.produit_id, P.date_lancement.dt.to_period("M"))))
piv = piv[piv.mois >= piv.launch].drop(columns="launch")
LCF2 = LCF.merge(CF[["commande_fournisseur_id", "entrepot_id", "date_commande", "date_reception"]], on="commande_fournisseur_id")
oo = []
for m in months:
    me = m.to_timestamp(how="end")
    sel = LCF2[(LCF2.date_commande <= me) & ((LCF2.date_reception.isna()) | (LCF2.date_reception > me))]
    g = sel.groupby(["produit_id", "entrepot_id"]).quantite_commandee.sum().reset_index()
    g["mois"] = m; oo.append(g)
oo = pd.concat(oo).rename(columns={"quantite_commandee": "quantite_en_commande"})
ST = piv.merge(oo, on=["produit_id", "entrepot_id", "mois"], how="left").fillna({"quantite_en_commande": 0})
ST["quantite_en_commande"] = ST.quantite_en_commande.astype(int)
ST["cout_unitaire_ht"] = [cost_by_year[(pidx[p], m.year)] for p, m in zip(ST.produit_id, ST.mois)]
ST["valeur_stock_ht"] = (ST.stock_fin_mois * ST.cout_unitaire_ht).round(3)
ST["date_inventaire"] = ST.mois.dt.to_timestamp(how="end").dt.strftime("%Y-%m-%d")
ST = ST.sort_values(["date_inventaire", "entrepot_id", "produit_id"]).reset_index(drop=True)
ST.insert(0, "inventaire_id", [f"INV{i+1:07d}" for i in range(len(ST))])
ST = ST[["inventaire_id", "date_inventaire", "produit_id", "entrepot_id", "stock_fin_mois", "quantite_en_commande", "cout_unitaire_ht", "valeur_stock_ht"]]
MV = MV.drop(columns="mois")

# ------------------------------------------------ Mise en forme finale
def fmt(df, cols):
    for c in cols:
        df[c] = df[c].apply(lambda x: x.strftime(TSF) if x is not None and not pd.isna(x) else None)
    return df

fmt(O, ["date_commande", "date_annulation"]); fmt(PAY, ["date_paiement"])
PAY["date_reversement"] = PAY.date_reversement.apply(lambda x: x.strftime("%Y-%m-%d") if x is not None and not pd.isna(x) else None)
fmt(RMB, ["date_demande", "date_reception_retour", "date_remboursement"]); fmt(LIV, ["date_expedition", "date_livraison_reelle", "date_dernier_evenement"])
fmt(CF, ["date_commande", "date_reception"]); fmt(MV, ["date_mouvement"]); fmt(AV, ["date_avis"]); fmt(CL, ["date_inscription"])
for df, c in [(RMB, "quantite"), (LIV, "nb_tentatives"), (LCF, "quantite_recue")]:
    df[c] = df[c].astype("Int64")
FO = fournisseurs.copy()
GOVT = gov_df.drop(columns=["poids_clients"])
TABLES = {
    "ref_gouvernorats": GOVT, "dim_calendrier": calendrier, "entrepots": entrepots, "transporteurs": transporteurs,
    "fournisseurs": FO, "categories": categories, "produits": PR, "produits_prix_historique": prix_hist,
    "clients": CL, "campagnes_marketing": CMP, "coupons": coupons, "marketing_depenses_quotidiennes": MK,
    "commandes": O, "lignes_commande": L, "paiements": PAY, "remboursements": RMB, "livraisons": LIV,
    "commandes_fournisseurs": CF, "lignes_commande_fournisseur": LCF, "mouvements_stock": MV, "stocks_mensuels": ST, "avis_clients": AV,
}
TRUTH = pd.DataFrame({"client_id": [f"CLI{c+1:06d}" for c in range(N_CUST)], "persona_reel": persona,
                      "date_fin_activite_simulee": [(START + pd.Timedelta(days=int(min(e, D + 400)))).strftime("%Y-%m-%d") for e in end_day],
                      "nb_mauvaises_experiences": bad_exp})
for k, v in TABLES.items():
    print(f"{k:35s} {len(v):>8d}")

import pickle
with open(os.path.join(_HERE, "tables.pkl"), "wb") as f:
    pickle.dump({"TABLES": TABLES, "TRUTH": TRUTH, "HOLI": sorted(HOLI_SET)}, f)
