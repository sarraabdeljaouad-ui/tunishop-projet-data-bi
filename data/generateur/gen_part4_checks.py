# -*- coding: utf-8 -*-
"""TuniShop - contrôles des règles métier / qualité (doivent tous être à 0 sur la couche de référence)."""
import pickle, re
import numpy as np, pandas as pd

def run_checks(T, holidays):
    R = []
    def add(rid, desc, n):
        R.append((rid, desc, int(n)))
    ts = lambda s: pd.to_datetime(s, errors="coerce")
    PK = {"ref_gouvernorats": "gouvernorat_id", "dim_calendrier": "date", "entrepots": "entrepot_id", "transporteurs": "transporteur_id",
          "fournisseurs": "fournisseur_id", "categories": "categorie_id", "produits": "produit_id", "produits_prix_historique": "prix_id",
          "clients": "client_id", "campagnes_marketing": "campagne_id", "coupons": "code_coupon", "marketing_depenses_quotidiennes": "depense_id",
          "commandes": "commande_id", "lignes_commande": "ligne_id", "paiements": "paiement_id", "remboursements": "remboursement_id",
          "livraisons": "livraison_id", "commandes_fournisseurs": "commande_fournisseur_id", "lignes_commande_fournisseur": "ligne_cf_id",
          "mouvements_stock": "mouvement_id", "stocks_mensuels": "inventaire_id", "avis_clients": "avis_id"}
    n = sum(T[t][k].isna().sum() + T[t][k].duplicated().sum() for t, k in PK.items())
    add("DQ-01", "Clé primaire non nulle et unique (22 tables)", n)
    FK = [("clients", "gouvernorat_id", "ref_gouvernorats"), ("clients", "campagne_acquisition_id", "campagnes_marketing"),
          ("produits", "categorie_id", "categories"), ("produits", "fournisseur_id", "fournisseurs"), ("produits_prix_historique", "produit_id", "produits"),
          ("entrepots", "gouvernorat_id", "ref_gouvernorats"), ("campagnes_marketing", "categorie_ciblee_id", "categories"),
          ("coupons", "campagne_id", "campagnes_marketing"), ("marketing_depenses_quotidiennes", "campagne_id", "campagnes_marketing"),
          ("commandes", "client_id", "clients"), ("commandes", "gouvernorat_livraison_id", "ref_gouvernorats"), ("commandes", "entrepot_id", "entrepots"),
          ("commandes", "campagne_id", "campagnes_marketing"), ("commandes", "code_coupon", "coupons"), ("lignes_commande", "commande_id", "commandes"),
          ("lignes_commande", "produit_id", "produits"), ("paiements", "commande_id", "commandes"), ("remboursements", "commande_id", "commandes"),
          ("remboursements", "ligne_id", "lignes_commande"), ("livraisons", "commande_id", "commandes"), ("livraisons", "entrepot_id", "entrepots"),
          ("livraisons", "transporteur_id", "transporteurs"), ("livraisons", "gouvernorat_destination_id", "ref_gouvernorats"),
          ("commandes_fournisseurs", "fournisseur_id", "fournisseurs"), ("commandes_fournisseurs", "entrepot_id", "entrepots"),
          ("lignes_commande_fournisseur", "commande_fournisseur_id", "commandes_fournisseurs"), ("lignes_commande_fournisseur", "produit_id", "produits"),
          ("mouvements_stock", "produit_id", "produits"), ("mouvements_stock", "entrepot_id", "entrepots"), ("stocks_mensuels", "produit_id", "produits"),
          ("stocks_mensuels", "entrepot_id", "entrepots"), ("avis_clients", "commande_id", "commandes"), ("avis_clients", "ligne_id", "lignes_commande"),
          ("avis_clients", "produit_id", "produits"), ("avis_clients", "client_id", "clients"), ("ref_gouvernorats", "entrepot_rattachement_id", "entrepots"),
          ("campagnes_marketing", "code_coupon", "coupons")]
    n = 0
    for t, c, rt in FK:
        v = T[t][c].dropna()
        n += (~v.isin(T[rt][PK[rt]])).sum()
    add("DQ-02", f"Intégrité référentielle ({len(FK)} clés étrangères)", n)
    O = T["commandes"].copy(); L = T["lignes_commande"].copy(); PAY = T["paiements"].copy(); RMB = T["remboursements"].copy()
    LIV = T["livraisons"].copy(); CL = T["clients"].copy(); PR = T["produits"]; PH = T["produits_prix_historique"]
    for c in ["date_commande", "date_annulation"]: O[c] = ts(O[c])
    add("DQ-03", "Total commande = sous-total - remise coupon + frais de livraison", (abs(O.montant_total_ttc - (O.sous_total_ttc - O.remise_coupon_ttc + O.frais_livraison_ttc)) > 0.0015).sum())
    s = L.groupby("commande_id").agg(st=("montant_ligne_ttc", "sum"), n=("ligne_id", "size"), q=("quantite", "sum"))
    m = O.set_index("commande_id").join(s)
    add("DQ-04", "Sous-total = somme des lignes ; nb_lignes et nb_articles cohérents",
        ((abs(m.sous_total_ttc - m.st) > 0.0015 * m.n) | (m.nb_lignes != m.n) | (m.nb_articles != m.q)).sum())
    add("DQ-05", "Ligne : prix unitaire = catalogue - remise promo ; montant = qté x prix ; HT + TVA = TTC",
        ((abs(L.prix_unitaire_ttc - (L.prix_catalogue_ttc - L.remise_promo_unitaire_ttc)) > 0.0015) |
         (abs(L.montant_ligne_ttc - L.quantite * L.prix_unitaire_ttc) > 0.0015) |
         (abs(L.montant_ligne_ht + L.montant_tva - L.montant_ligne_ttc) > 0.0015) |
         (abs(L.montant_ligne_ht - L.montant_ligne_ttc / (1 + L.taux_tva / 100)) > 0.0015)).sum())
    add("DQ-06", "Quantités strictement positives (lignes, achats, retours)",
        (L.quantite <= 0).sum() + (T["lignes_commande_fournisseur"].quantite_commandee <= 0).sum() + (RMB.quantite.dropna() <= 0).sum())
    add("DQ-07", "Frais de livraison = 7,000 DT si (sous-total - remise) < 150 DT, sinon 0",
        (O.frais_livraison_ttc != np.where(O.sous_total_ttc - O.remise_coupon_ttc < 150, 7.0, 0.0)).sum())
    add("DQ-08", "0 <= remise coupon <= sous-total ; remise nulle si pas de coupon",
        ((O.remise_coupon_ttc < 0) | (O.remise_coupon_ttc > O.sous_total_ttc) | (O.code_coupon.isna() & (O.remise_coupon_ttc > 0))).sum())
    lt = L.merge(PR[["produit_id", "taux_tva"]], on="produit_id", suffixes=("", "_p"))
    add("DQ-09", "TVA ligne dans {7,13,19} et identique au taux du produit", ((~lt.taux_tva.isin([7, 13, 19])) | (lt.taux_tva != lt.taux_tva_p)).sum())
    lo = L.merge(O[["commande_id", "date_commande"]], on="commande_id")
    lo["d"] = lo.date_commande.dt.normalize()
    ph = PH.copy(); ph["dd"] = ts(ph.date_debut); ph["df"] = ts(ph.date_fin).fillna(pd.Timestamp("2099-12-31"))
    j = lo.merge(ph[["produit_id", "dd", "df", "prix_catalogue_ttc", "cout_achat_unitaire_ht"]], on="produit_id", suffixes=("", "_h"))
    j = j[(j.d >= j.dd) & (j.d <= j.df)]
    bad = (len(lo) - j.ligne_id.nunique()) + ((abs(j.prix_catalogue_ttc - j.prix_catalogue_ttc_h) > 0.0005) | (abs(j.cout_achat_unitaire_ht - j.cout_achat_unitaire_ht_h) > 0.0005)).sum()
    add("DQ-10", "Prix catalogue et coût de la ligne = historique de prix valide à la date de commande (produit actif)", bad)
    CL["di"] = ts(CL.date_inscription)
    fo = O.groupby("client_id").date_commande.min()
    add("DQ-11", "Date d'inscription <= première commande", (CL.set_index("client_id").di.reindex(fo.index) > fo).sum())
    for c in ["date_expedition", "date_livraison_reelle", "date_dernier_evenement"]: LIV[c] = ts(LIV[c])
    lv = LIV.merge(O[["commande_id", "date_commande", "statut_commande", "entrepot_id"]], on="commande_id", suffixes=("", "_o"))
    add("DQ-12", "Chronologie commande <= expédition <= livraison ; annulation >= commande",
        ((lv.date_expedition < lv.date_commande) | (lv.date_livraison_reelle < lv.date_expedition)).sum() + (O.date_annulation < O.date_commande).sum())
    exp_map = {"livree": "livree", "retournee": "livree", "partiellement_retournee": "livree", "livraison_echouee": "echec_retour_expediteur",
               "expediee": "en_transit", "en_preparation": "en_preparation"}
    lv["att"] = lv.statut_commande.map(exp_map)
    no_ship = O[O.statut_commande.isin(exp_map)].commande_id.isin(LIV.commande_id)
    add("DQ-13", "Statut commande cohérent avec la livraison (1 livraison par commande expédiée, aucune pour annulée/échec paiement)",
        (lv.att != lv.statut_livraison).sum() + (~no_ship).sum() + LIV.commande_id.duplicated().sum() + (lv.entrepot_id != lv.entrepot_id_o).sum())
    PAY["dp"] = ts(PAY.date_paiement)
    ok = PAY[PAY.statut_paiement.isin(["reussi", "encaisse"])]
    add("DQ-14", "Au plus un paiement réussi par commande, montant = total commande",
        ok.commande_id.duplicated().sum() + (abs(ok.merge(O[["commande_id", "montant_total_ttc"]], on="commande_id").eval("montant_ttc - montant_total_ttc")) > 0.0015).sum())
    deliv = O[O.statut_commande.isin(["livree", "retournee", "partiellement_retournee"]) & (O.mode_paiement != "virement")]
    pre = O[O.mode_paiement.isin(["carte_bancaire", "portefeuille_mobile", "carte_prepayee"]) & (O.statut_commande != "paiement_echoue")]
    add("DQ-15", "Commande livrée (hors virement) ou prépayée non échouée => paiement réussi", (~deliv.commande_id.isin(ok.commande_id)).sum() + (~pre.commande_id.isin(ok.commande_id)).sum())
    pe = O[O.statut_commande == "paiement_echoue"].commande_id
    add("DQ-16", "Commande 'paiement_echoue' : aucune tentative réussie, aucune livraison, 1 à 3 tentatives",
        pe.isin(ok.commande_id).sum() + pe.isin(LIV.commande_id).sum() + (PAY.num_tentative > 3).sum())
    cod = ok[ok.mode_paiement == "paiement_a_la_livraison"].merge(LIV[["commande_id", "date_livraison_reelle"]], on="commande_id")
    add("DQ-17", "Paiement à la livraison : encaissé à la date de livraison ; reversement >= encaissement",
        (cod.dp != cod.date_livraison_reelle).sum() + (ts(cod.date_reversement) < cod.dp.dt.normalize()).sum())
    for c in ["date_demande", "date_reception_retour", "date_remboursement"]: RMB[c] = ts(RMB[c])
    ret = RMB[RMB.type_remboursement == "retour"].merge(LIV[["commande_id", "date_livraison_reelle"]], on="commande_id", how="left")
    ret = ret.merge(L[["ligne_id", "quantite", "montant_ligne_ttc", "commande_id"]], on="ligne_id", suffixes=("", "_l"))
    ret = ret.merge(O[["commande_id", "sous_total_ttc", "remise_coupon_ttc"]], on="commande_id")
    hol = np.array(holidays, dtype="datetime64[D]")
    acc = ret[ret.statut != "refuse"]
    lim = np.busday_offset(acc.date_livraison_reelle.values.astype("datetime64[D]"), 10, roll="forward", weekmask="1111100", holidays=hol)
    add("DQ-18", "Retour accepté demandé dans les 10 jours ouvrables suivant la livraison (loi 2000-83)",
        (acc.date_demande.values.astype("datetime64[D]") > lim).sum() + (ret.date_demande < ret.date_livraison_reelle).sum() + ret.date_livraison_reelle.isna().sum())
    maxr = ret.montant_ligne_ttc / ret.quantite * ret.quantite_l * 0 + ret.montant_ligne_ttc / ret.quantite * ret.quantite * (1 - ret.remise_coupon_ttc / ret.sous_total_ttc)
    add("DQ-19", "Retour : quantité <= quantité de la ligne ; montant <= montant net de la ligne (au prorata du coupon)",
        (ret.quantite > ret.quantite_l).sum() + (ret.montant_rembourse_ttc > maxr + 0.0015).sum() + ret.ligne_id.duplicated().sum())
    add("DQ-20", "Chronologie remboursement : demande <= réception retour <= remboursement",
        ((RMB.date_reception_retour < RMB.date_demande) | (RMB.date_remboursement < RMB.date_demande) | (RMB.date_remboursement < RMB.date_reception_retour)).sum())
    tot = RMB[RMB.type_remboursement != "geste_commercial"].groupby("commande_id").montant_rembourse_ttc.sum()
    add("DQ-21", "Somme des remboursements (retours + annulations) <= total payé de la commande",
        (tot > O.set_index("commande_id").montant_total_ttc.reindex(tot.index) + 0.0015).sum() + ((RMB.statut == "refuse") & (RMB.montant_rembourse_ttc != 0)).sum())
    MV = T["mouvements_stock"].copy(); MV["t"] = ts(MV.date_mouvement)
    MV = MV.sort_values(["produit_id", "entrepot_id", "t", "mouvement_id"])
    MV["cum"] = MV.groupby(["produit_id", "entrepot_id"]).quantite.cumsum()
    add("DQ-22", "Stock jamais négatif dans le grand livre des mouvements", (MV.cum < 0).sum())
    v = MV[MV.type_mouvement == "vente"].groupby("reference_id").quantite.sum()
    oo = O[O.entrepot_id.notna()].set_index("commande_id").nb_articles
    add("DQ-23", "Chaque commande servie génère des sorties 'vente' = nb_articles", (v.reindex(oo.index).fillna(0) != -oo).sum() + (~v.index.isin(oo.index)).sum())
    LCF = T["lignes_commande_fournisseur"]; CF = T["commandes_fournisseurs"].copy()
    rc = MV[MV.type_mouvement == "reception_fournisseur"].groupby(["reference_id", "produit_id"]).quantite.sum()
    lc = LCF.dropna(subset=["quantite_recue"]).query("quantite_recue > 0").groupby(["commande_fournisseur_id", "produit_id"]).quantite_recue.sum()
    lc.index.names = rc.index.names
    add("DQ-24", "Réceptions fournisseurs en stock = quantités reçues ; reçu <= commandé ; réception >= commande",
        (rc.reindex(lc.index).fillna(0) != lc).sum() + (LCF.quantite_recue > LCF.quantite_commandee).sum() + (ts(CF.date_reception) < ts(CF.date_commande)).sum())
    ST = T["stocks_mensuels"]
    add("DQ-25", "Stock mensuel >= 0 et valeur = quantité x coût", (ST.stock_fin_mois < 0).sum() + (abs(ST.valeur_stock_ht - ST.stock_fin_mois * ST.cout_unitaire_ht) > 0.002).sum())
    MK = T["marketing_depenses_quotidiennes"]; CMP = T["campagnes_marketing"].copy()
    mk = MK.merge(CMP[["campagne_id", "date_debut", "date_fin"]], on="campagne_id")
    att = O[(O.statut_commande != "paiement_echoue") & O.campagne_id.notna()].assign(date=O.date_commande.dt.strftime("%Y-%m-%d")).groupby(["campagne_id", "date"]).size()
    mm = MK.set_index(["campagne_id", "date"]).commandes_attribuees
    add("DQ-26", "Marketing : clics <= impressions, dépense >= 0, jour dans la campagne, commandes attribuées = commandes",
        ((mk.clics > mk.impressions) | (mk.depense_ht < 0) | (mk.date < mk.date_debut) | (mk.date > mk.date_fin)).sum() + (mm.reindex(att.index).fillna(-1) != att).sum())
    oc = O.dropna(subset=["campagne_id"]).merge(CMP[["campagne_id", "date_debut", "date_fin"]], on="campagne_id")
    d = oc.date_commande.dt.strftime("%Y-%m-%d")
    add("DQ-27", "Commande attribuée à une campagne active le jour de la commande", ((d < oc.date_debut) | (d > oc.date_fin)).sum())
    CP = T["coupons"]
    occ = O.dropna(subset=["code_coupon"]).merge(CP, on="code_coupon")
    d = occ.date_commande.dt.strftime("%Y-%m-%d")
    bad = (d < occ.date_debut) | (occ.date_fin.notna() & (d > occ.date_fin)) | (occ.sous_total_ttc < occ.montant_min_ttc) | (occ.reserve_premiere_commande & ~occ.est_premiere_commande)
    w = O[O.code_coupon == "BIENVENUE10"].client_id.duplicated().sum()
    add("DQ-28", "Coupon valide à la date, montant minimum atteint, BIENVENUE10 une seule fois et sur première commande", bad.sum() + w)
    first_flag = O.sort_values("date_commande").groupby("client_id").head(1)
    AV = T["avis_clients"].copy()
    av = AV.merge(LIV[["commande_id", "date_livraison_reelle"]], on="commande_id").merge(L[["ligne_id", "produit_id", "commande_id"]], on="ligne_id", suffixes=("", "_l"))
    av = av.merge(O[["commande_id", "client_id"]], on="commande_id", suffixes=("", "_o"))
    add("DQ-29", "Avis : note 1-5, après livraison, produit et client cohérents avec la commande",
        ((~AV.note.between(1, 5)) | AV.note.isna()).sum() + ((ts(av.date_avis) < av.date_livraison_reelle) | (av.produit_id != av.produit_id_l) | (av.commande_id != av.commande_id_l) | (av.client_id != av.client_id_o)).sum())
    em = CL.email.dropna()
    add("DQ-30", "Format email valide ; téléphone au format E.164 tunisien (+216 suivi de 8 chiffres)",
        (~em.str.match(r"^[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}$")).sum() + (~CL.telephone.str.match(r"^\+216[2-9]\d{7}$")).sum())
    ca = O[O.statut_commande.isin(["livree", "retournee", "partiellement_retournee"]) & (O.date_commande.dt.year == 2025)]
    tot = ca.groupby("client_id").montant_total_ttc.sum()
    rb = RMB[(RMB.statut == "rembourse") & RMB.commande_id.isin(ca.commande_id)].merge(O[["commande_id", "client_id"]], on="commande_id").groupby("client_id").montant_rembourse_ttc.sum()
    net = tot.sub(rb, fill_value=0).reindex(CL.client_id).fillna(0).round(3)
    seg = np.select([net >= 1500, net >= 500, net > 0], ["or", "argent", "bronze"], "aucun")
    add("DQ-31", "Segment fidélité = règle sur le CA net 2025 (or >= 1500, argent >= 500, bronze > 0)", (seg != CL.segment_fidelite.values).sum())
    rk = O.sort_values(["date_commande", "commande_id"]).groupby("client_id").cumcount()
    add("DQ-32", "est_premiere_commande vrai si et seulement si c'est la 1re commande chronologique du client",
        (O.est_premiere_commande != (rk.reindex(O.index) == 0)).sum())
    dom = {"canal": {"site_web", "application_mobile", "reseaux_sociaux"}, "mode_paiement": {"paiement_a_la_livraison", "carte_bancaire", "portefeuille_mobile", "carte_prepayee", "virement"},
           "statut_commande": {"livree", "retournee", "partiellement_retournee", "annulee", "paiement_echoue", "livraison_echouee", "expediee", "en_preparation"}}
    add("DQ-33", "Valeurs des listes fermées (canal, mode de paiement, statut)", sum((~O[c].isin(v)).sum() for c, v in dom.items()))
    add("DQ-34", "Aucune date postérieure à la date d'arrêté (31/12/2025 23:59:59)",
        (O.date_commande > "2025-12-31 23:59:59").sum() + (LIV.date_livraison_reelle > "2025-12-31 23:59:59").sum() + (RMB.date_remboursement > "2025-12-31 23:59:59").sum() + (PAY.dp > "2025-12-31 23:59:59").sum())
    return pd.DataFrame(R, columns=["regle", "description", "violations"])

if __name__ == "__main__":
    d = pickle.load(open(__import__("os").path.join(__import__("os").path.dirname(__import__("os").path.abspath(__file__)), "tables.pkl"), "rb"))
    res = run_checks(d["TABLES"], d["HOLI"])
    pd.set_option("display.width", 200); pd.set_option("display.max_colwidth", 110)
    print(res.to_string(index=False))
