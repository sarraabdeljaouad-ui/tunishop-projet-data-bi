# -*- coding: utf-8 -*-
"""TuniShop - partie 2 : commandes et simulation des flux."""
import math, os
_HERE = os.path.dirname(os.path.abspath(__file__))
from collections import defaultdict
exec(open(os.path.join(_HERE, "gen_part1.py"), encoding="utf-8").read())

HOUR_W = np.array([1, .6, .3, .2, .1, .1, .3, .8, 1.5, 2.2, 2.8, 3, 3.2, 3.4, 3, 2.8, 2.8, 3, 3.4, 3.8, 4.4, 4.8, 4, 2.4])
HOUR_W_RAM = HOUR_W.copy(); HOUR_W_RAM[12:19] *= 0.55; HOUR_W_RAM[19] *= 0.4; HOUR_W_RAM[21:24] *= 1.6; HOUR_W_RAM[0:2] *= 2.2
HOUR_W /= HOUR_W.sum(); HOUR_W_RAM /= HOUR_W_RAM.sum()
PROMO_TAGS = {"soldes", "bf", "pre_fitr"}

# ------------------------------------------------ 1) Planification des commandes (client, jour)
plan = []
for d in range(D):
    act = np.where((sign_day < d) & (end_day >= d))[0]
    if len(act):
        pm = np.where(persona[act] == "chasseur_promo", 1.9 if cat_boost_flags[d] & PROMO_TAGS else 0.7, 1.0)
        lam = rate[act] * season[d] * (1 + camp_int[d]) * pm
        n = rng.poisson(lam)
        for c, k in zip(act[n > 0], n[n > 0]):
            for _ in range(min(int(k), 2)):
                plan.append((d, int(c)))
    newc = np.where(sign_day == d)[0]
    for c in newc[rng.random(len(newc)) < 0.55]:
        plan.append((d, int(c)))
plan.sort()
print("commandes planifiées :", len(plan))

# ------------------------------------------------ 2) Contenu des paniers
LAUNCH = ((P.date_lancement - START).dt.days).values
ARRET = np.array([(x - START).days if x is not None and not pd.isna(x) else 10**6 for x in P.date_arret])
POP = P.popularite.values
PRICE23 = P.prix_2023.values
CAT_NAME = np.array([CATS[i][0] for i in P_CAT_IDX])
CHEAP_QTY = np.isin(P_SUB, ["Produits du terroir", "Fournitures scolaires & Livres", "Accessoires téléphone", "Parapharmacie"])
BOOST = np.ones((D, NP_))
for d in range(D):
    tags = cat_boost_flags[d]
    if tags:
        for k, c in enumerate(CATS):
            f = 1.0
            for t, v in c[11].items():
                if t in tags:
                    f *= v
            if f != 1.0:
                BOOST[d, P_CAT_IDX == k] = f
PERS_PRICE = {"occasionnel": -0.60, "regulier": -0.55, "chasseur_promo": -0.75, "premium": -0.30, "professionnel": -0.65}
day_weights = {}

def weights(d, pers):
    key = (d, pers)
    if key not in day_weights:
        avail = (LAUNCH <= d) & (ARRET >= d)
        w = POP * BOOST[d] * PRICE23 ** PERS_PRICE[pers] * avail
        day_weights.clear()
        day_weights[key] = w / w.sum()
    return day_weights[key]

plan_lines = []
for (d, c) in plan:
    pers = persona[c]
    nl = min(int(rng.geometric(0.35 if pers == "professionnel" else 0.58)), 8 if pers == "professionnel" else 6)
    prods = np.unique(rng.choice(NP_, size=nl, p=weights(d, pers)))
    lines = []
    for p in prods:
        if pers == "professionnel":
            q = int(rng.integers(3, 16)) if PRICE23[p] < 80 else int(rng.integers(1, 3))
        elif CHEAP_QTY[p]:
            q = 1 + int(rng.poisson(0.6))
        else:
            q = 1 if rng.random() < 0.92 else 2
        lines.append((int(p), q))
    plan_lines.append(lines)

# ------------------------------------------------ 3) Préparation simulation
cust_gov = gov_idx.copy()
GOV_IDS = gov_df.gouvernorat_id.values
GOV_REGION = gov_df.region.values
GOV_WH = gov_df.entrepot_rattachement_id.values
WH_IDX = {w: i for i, w in enumerate(WH)}
SUP_OF = P.fournisseur_id.values
SUP_LT = dict(zip(fournisseurs.fournisseur_id, fournisseurs.delai_appro_moyen_j))
SUP_REL = dict(zip(fournisseurs.fournisseur_id, fournisseurs.fiabilite_livraison))
P_LT = np.array([SUP_LT[s] for s in SUP_OF])

# demande planifiée par (produit, entrepôt de rattachement) pour stock initial
planned = np.zeros((NP_, 3))
for (d, c), lines in zip(plan, plan_lines):
    w = WH_IDX[GOV_WH[cust_gov[c]]]
    for p, q in lines:
        if d - LAUNCH[p] < 60:
            planned[p, w] += q
planned_avg = planned / 60.0

stock = np.zeros((NP_, 3), dtype=np.int64)
on_order = np.zeros((NP_, 3), dtype=np.int64)
RING = 28
dem_ring = np.zeros((RING, NP_, 3)); dem_sum = np.zeros((NP_, 3))
events = defaultdict(list)

movements, orders, lines_out, payments, refunds, shipments, pos, po_lines = [], [], [], [], [], [], [], []
mv_id = [0]

def mv(ts, p, w, typ, q, ref, cost):
    mv_id[0] += 1
    movements.append((f"MVT{mv_id[0]:07d}", ts, P.produit_id.iat[p], WH[w], typ, int(q), ref, cost))

def cost_at(p, ts):
    return cost_by_year[(p, ts.year)]

def price_at(p, ts):
    return price_by_year[(p, ts.year)]

# stock initial
for p in range(NP_):
    if LAUNCH[p] == 0:
        for w in range(3):
            q = int(math.ceil(planned_avg[p, w] * 40)) + int(rng.integers(2, 8))
            stock[p, w] = q
            mv(START, p, w, "stock_initial", q, "INIT-2023", cost_at(p, START))
LAUNCH_AT = defaultdict(list)
for p in range(NP_):
    if LAUNCH[p] > 0:
        LAUNCH_AT[LAUNCH[p]].append(p)

CARRIER_P = {"ENT01": ([0.35, 0.25, 0.05, 0.35]), "ENT02": ([0.25, 0.15, 0.40, 0.20]), "ENT03": ([0.20, 0.0, 0.50, 0.30])}
TR_IDS = list(transporteurs.transporteur_id)
TR_ECART = dict(zip(transporteurs.transporteur_id, transporteurs.ecart_delai_moyen_j))
TR_COST = dict(zip(transporteurs.transporteur_id, transporteurs.cout_base_ht))
TR_NAME = dict(zip(transporteurs.transporteur_id, transporteurs.nom_transporteur))
ZONE_K = {"Z1": 0, "Z2": 1, "Z3": 2, "Z4": 3}
GOV_ZONE = gov_df.zone_livraison.values
SAHEL_DEGRADE = pd.Timestamp("2024-07-01")
PREPAID = ("carte_bancaire", "portefeuille_mobile", "carte_prepayee")
ERR = ["fonds_insuffisants", "authentification_3ds_echouee", "carte_expiree", "delai_depasse", "refus_banque"]
RET_REASONS = {
    "Mode": ["taille_inadaptee", "taille_inadaptee", "taille_inadaptee", "ne_correspond_pas_a_la_description", "qualite_decevante", "changement_d_avis"],
    "default": ["produit_defectueux", "ne_correspond_pas_a_la_description", "changement_d_avis", "erreur_de_preparation", "colis_endommage"],
}
has_success = np.zeros(N_CUST, bool)
n_prev = np.zeros(N_CUST, int)
bad_exp = np.zeros(N_CUST, int)
order_seq = 0; pay_seq = 0; ref_seq = 0; ship_seq = 0; line_seq = 0; po_seq = 0; pol_seq = 0
cust_spend = defaultdict(float)
review_candidates = []
pay_ref = lambda: "TXN" + "".join(rng.choice(list(string.ascii_uppercase + string.digits), 10))

def churn_hit(c, day_idx):
    if rng.random() < 0.35:
        end_day[c] = min(end_day[c], day_idx + int(rng.integers(0, 30)))

def add_refund(oid, lid, typ, motif, qty, amount, t_req, t_rec, t_ref, mode, statut, etat):
    global ref_seq
    if t_req > CUTOFF:
        return
    if t_rec is not None and t_rec > CUTOFF:
        t_rec, t_ref, statut = None, None, "en_cours"
    if t_ref is not None and t_ref > CUTOFF:
        t_ref, statut = None, "en_cours"
    ref_seq += 1
    refunds.append({"remboursement_id": f"RMB{ref_seq:06d}", "commande_id": oid, "ligne_id": lid, "type_remboursement": typ,
                    "motif": motif, "quantite": qty, "montant_rembourse_ttc": r3(amount) if statut != "refuse" else 0.0,
                    "montant_demande_ttc": r3(amount), "date_demande": t_req, "date_reception_retour": t_rec,
                    "date_remboursement": t_ref, "mode_remboursement": mode, "statut": statut, "etat_article": etat})

def pay_row(oid, att, mode, amount, statut, err, ts, prest, rev=None):
    global pay_seq
    pay_seq += 1
    payments.append({"paiement_id": f"PAY{pay_seq:07d}", "commande_id": oid, "num_tentative": att, "mode_paiement": mode,
                     "montant_ttc": r3(amount), "statut_paiement": statut, "code_erreur": err, "date_paiement": ts,
                     "prestataire": prest, "reference_transaction": pay_ref(), "date_reversement": rev})

plan_by_day = defaultdict(list)
for k, (d, c) in enumerate(plan):
    plan_by_day[d].append(k)

# ------------------------------------------------ 4) Simulation jour par jour
for d in range(D):
    day = DAYS[d]
    for p in LAUNCH_AT.get(d, []):
        for w in range(3):
            q = int(math.ceil(planned_avg[p, w] * 35)) + int(rng.integers(2, 6))
            stock[p, w] += q
            mv(day, p, w, "stock_initial", q, f"LANCEMENT-{P.produit_id.iat[p]}", cost_at(p, day))
    ram = is_ram[d]; tags = cat_boost_flags[d]
    idxs = plan_by_day.get(d, [])
    hours = rng.choice(24, size=len(idxs), p=HOUR_W_RAM if ram else HOUR_W)
    secs = rng.integers(0, 3600, size=len(idxs))
    order_times = sorted([(day + pd.Timedelta(hours=int(h), seconds=int(s)), k) for h, s, k in zip(hours, secs, idxs)])
    ri = d % RING
    dem_sum -= dem_ring[ri]; dem_ring[ri] = 0
    for ot, k in order_times:
        c = plan[k][1]
        if d > end_day[c] and sign_day[c] < d:
            continue  # client churné suite à une mauvaise expérience
        order_seq += 1
        oid = f"CMD{order_seq:07d}"
        pers = persona[c]
        g = cust_gov[c] if rng.random() > 0.06 else int(rng.choice(len(gov_df), p=gov_p))
        region = GOV_REGION[g]
        wpref = GOV_WH[g]
        t = d / D
        r_ch = rng.random()
        app_share = 0.30 + 0.20 * t
        canal = "application_mobile" if r_ch < app_share else ("reseaux_sociaux" if r_ch < app_share + 0.12 else "site_web")
        appareil = "mobile" if canal != "site_web" else rng.choice(["ordinateur", "mobile", "tablette"], p=[0.45, 0.50, 0.05])
        # mode de paiement
        if pers == "professionnel":
            mp = rng.choice(["virement", "carte_bancaire", "paiement_a_la_livraison"], p=[0.7, 0.2, 0.1])
        else:
            cod = 0.60 - 0.10 * t + (0.10 if region in ("Sud-Est", "Sud-Ouest", "Centre-Ouest", "Nord-Ouest") else 0) - (0.25 if pers == "premium" else 0)
            card = 0.22 + 0.07 * t + (0.20 if pers == "premium" else 0)
            wal = 0.10 + 0.04 * t
            pre = max(0.02, 1 - cod - card - wal)
            pv = np.array([cod, card, wal, pre]); pv /= pv.sum()
            mp = rng.choice(["paiement_a_la_livraison", "carte_bancaire", "portefeuille_mobile", "carte_prepayee"], p=pv)
        # attribution campagne
        camp = None
        ac = active_camps[d]
        if ac:
            pa = 0.55 if pers == "chasseur_promo" else 0.30
            if rng.random() < pa:
                wts = np.array([C.at[i, "budget_j"] * CH[C.at[i, "canal"]][5] for i in ac]); wts /= wts.sum()
                camp = ac[int(rng.choice(len(ac), p=wts))]
        # lignes
        lines = []
        for (p, q) in plan_lines[k]:
            if not (LAUNCH[p] <= d <= ARRET[p]):
                continue
            pc = price_at(p, ot)
            pr = 0.0
            if "soldes" in tags and (p, "soldes", day.year) in PROMO:
                pr = PROMO[(p, "soldes", day.year)]
            if "bf" in tags and (p, "bf", day.year) in PROMO:
                pr = PROMO[(p, "bf", day.year)]
            pu = price_900(pc * (1 - pr)) if pr else pc
            pu = min(pu, pc)
            lines.append([p, q, pc, r3(pc - pu), pu, int(P.tva.iat[p])])
        if not lines:
            order_seq -= 1
            continue
        sous_total = r3(sum(l[1] * l[4] for l in lines))
        coupon = None; remise = 0.0
        if camp is not None and C.at[camp, "code_coupon"] and rng.random() < 0.6:
            cp = COUPON[C.at[camp, "code_coupon"]]
            if sous_total >= cp.montant_min_ttc:
                coupon = cp.code_coupon
                remise = min(sous_total * cp.valeur / 100, cp.plafond_remise_ttc) if cp.type_remise == "pourcentage" else cp.valeur
        if coupon is None and n_prev[c] == 0 and pers != "professionnel" and rng.random() < 0.4 and sous_total >= 50:
            coupon = "BIENVENUE10"; remise = min(sous_total * 0.10, 30.0)
        remise = r3(remise)
        frais = 7.0 if sous_total - remise < 150 else 0.0
        total = r3(sous_total - remise + frais)
        first = n_prev[c] == 0
        for l in lines:
            dem_ring[ri][l[0], WH_IDX[wpref]] += l[1]; dem_sum[l[0], WH_IDX[wpref]] += l[1]
        o = {"commande_id": oid, "client_id": f"CLI{c+1:06d}", "date_commande": ot, "canal": canal, "appareil": appareil,
             "gouvernorat_livraison_id": GOV_IDS[g], "ville_livraison": rng.choice(GOV_CITIES[GOV_IDS[g]]),
             "entrepot_id": None, "campagne_id": C.at[camp, "campagne_id"] if camp is not None else None, "code_coupon": coupon,
             "mode_paiement": mp, "nb_lignes": len(lines), "nb_articles": int(sum(l[1] for l in lines)),
             "sous_total_ttc": sous_total, "remise_coupon_ttc": remise, "frais_livraison_ttc": frais, "montant_total_ttc": total,
             "statut_commande": None, "motif_annulation": None, "date_annulation": None, "est_premiere_commande": bool(first)}
        orders.append(o)
        n_prev[c] += 1
        line_ids = []
        for n_, l in enumerate(lines):
            line_seq += 1
            lid = f"LIG{line_seq:08d}"; line_ids.append(lid)
            ttc = r3(l[1] * l[4]); ht = r3(ttc / (1 + l[5] / 100))
            lines_out.append({"ligne_id": lid, "commande_id": oid, "num_ligne": n_ + 1, "produit_id": P.produit_id.iat[l[0]],
                              "quantite": l[1], "prix_catalogue_ttc": l[2], "remise_promo_unitaire_ttc": l[3], "prix_unitaire_ttc": l[4],
                              "taux_tva": l[5], "montant_ligne_ttc": ttc, "montant_ligne_ht": ht, "montant_tva": r3(ttc - ht),
                              "cout_achat_unitaire_ht": cost_at(l[0], ot)})
        # paiement en ligne
        pay_time = ot + pd.Timedelta(seconds=int(rng.integers(20, 300)))
        if mp in PREPAID:
            att = 1; ok = False
            while att <= 3:
                if rng.random() < 0.88:
                    pay_row(oid, att, mp, total, "reussi", None, pay_time, "TuniPay"); ok = True; break
                pay_row(oid, att, mp, total, "echoue", rng.choice(ERR), pay_time, "TuniPay")
                if rng.random() > 0.70:
                    break
                att += 1; pay_time += pd.Timedelta(seconds=int(rng.integers(30, 600)))
            if not ok:
                o["statut_commande"] = "paiement_echoue"; continue
        # disponibilité stock (expédition depuis un seul entrepôt)
        order_wh = [WH_IDX[wpref]] + [i for i in range(3) if i != WH_IDX[wpref]]
        chosen = None
        for w in order_wh:
            if all(stock[l[0], w] >= l[1] for l in lines):
                chosen = w; break
        if chosen is None:
            o["statut_commande"] = "annulee"; o["motif_annulation"] = "rupture_stock"
            o["date_annulation"] = ot + pd.Timedelta(minutes=int(rng.integers(5, 240)))
            if mp in PREPAID:
                tr = o["date_annulation"] + pd.Timedelta(days=int(rng.integers(1, 4)))
                add_refund(oid, None, "annulation", "rupture_stock", None, total, o["date_annulation"], None, tr, mp, "rembourse", None)
            continue
        o["entrepot_id"] = WH[chosen]
        for l in lines:
            stock[l[0], chosen] -= l[1]
            mv(ot, l[0], chosen, "vente", -l[1], oid, cost_at(l[0], ot))
        # expédition
        base_ship = ot if ot.hour < 14 else ot + pd.Timedelta(days=1)
        sd = next_ship_day(base_ship.normalize())
        if tags & {"bf", "pre_fitr"} and rng.random() < 0.35:
            sd = next_ship_day(sd + pd.Timedelta(days=1))
        ship_t = sd + pd.Timedelta(hours=int(rng.integers(10, 18)), minutes=int(rng.integers(0, 60)))
        if ship_t <= ot:
            ship_t = ot + pd.Timedelta(hours=2)
        p_cancel = 0.045 if mp == "paiement_a_la_livraison" else 0.025
        if rng.random() < p_cancel:
            ct = ot + (ship_t - ot) * float(rng.uniform(0.05, 0.8))
            o["statut_commande"] = "annulee"; o["motif_annulation"] = "annulation_client"; o["date_annulation"] = ct
            for l in lines:
                events[max((ct.normalize() - START).days + 1, d + 1)].append(("in", ct, l[0], chosen, l[1], "annulation_commande", oid))
            if mp in PREPAID:
                add_refund(oid, None, "annulation", "annulation_client", None, total, ct, None, ct + pd.Timedelta(days=int(rng.integers(1, 5))), mp, "rembourse", None)
            if mp == "virement":
                pass
            continue
        whid = WH[chosen]
        tr_id = rng.choice(TR_IDS, p=CARRIER_P[whid])
        base = TRANSIT[whid][region]
        sla = int(math.ceil(base + 1))
        prom = sd
        for _ in range(sla):
            prom += pd.Timedelta(days=1)
            if prom.weekday() == 6:
                prom += pd.Timedelta(days=1)
        extra = TR_ECART[tr_id]
        if tr_id == "TR03" and ship_t >= SAHEL_DEGRADE:
            extra += 1.4
        stags = cat_boost_flags[min((sd - START).days, D - 1)]
        if "bf" in stags: extra += 1.2
        if "pre_fitr" in stags: extra += 0.8
        if "fin_annee" in stags: extra += 0.4
        transit = max(1, int(round(base + extra + rng.gamma(2, 0.45) - 0.7)))
        attempts = 1 if rng.random() < 0.88 else (2 if rng.random() < 0.83 else 3)
        dd = sd + pd.Timedelta(days=transit + attempts - 1)
        while dd.weekday() == 6 or dd in HOLI_SET:
            dd += pd.Timedelta(days=1)
        del_t = dd + pd.Timedelta(hours=int(rng.integers(9, 19)), minutes=int(rng.integers(0, 60)))
        late = (dd - prom).days
        # refus / échec
        p_fail = 0.01
        if mp == "paiement_a_la_livraison":
            p_fail = 0.06 + (0.05 if first else 0) + (0.03 if total > 400 else 0) + (0.03 if late > 1 else 0) + (0.03 if tr_id == "TR03" and ship_t >= SAHEL_DEGRADE else 0)
        failed = rng.random() < p_fail
        weight = float(sum(P.poids_kg.iat[l[0]] * l[1] for l in lines))
        zone = ZONE_K[GOV_ZONE[g]]
        cost_tr = r3(TR_COST[tr_id] * (1 + 0.15 * zone) + 0.35 * max(0.0, weight - 2))
        ship_seq += 1
        shp = {"livraison_id": f"LIV{ship_seq:07d}", "commande_id": oid, "entrepot_id": whid, "transporteur_id": tr_id,
               "gouvernorat_destination_id": GOV_IDS[g], "date_expedition": ship_t, "date_livraison_prevue": prom.strftime("%Y-%m-%d"),
               "date_livraison_reelle": None, "date_dernier_evenement": None, "statut_livraison": None, "nb_tentatives": None,
               "poids_kg": round(weight, 2), "cout_transport_ht": cost_tr}
        shipments.append(shp)
        if ship_t > CUTOFF:
            o["statut_commande"] = "en_preparation"; shp["statut_livraison"] = "en_preparation"; shp["date_expedition"] = None
            continue
        if failed:
            attempts = 2 if rng.random() < 0.5 else 3
            fail_t = del_t
            if fail_t > CUTOFF:
                o["statut_commande"] = "expediee"; shp["statut_livraison"] = "en_transit"; continue
            o["statut_commande"] = "livraison_echouee"
            shp["statut_livraison"] = "echec_retour_expediteur"; shp["nb_tentatives"] = attempts; shp["date_dernier_evenement"] = fail_t
            back = fail_t + pd.Timedelta(days=int(rng.integers(2, 7)))
            if back <= CUTOFF:
                for l in lines:
                    events[(back.normalize() - START).days].append(("in", back.normalize() + pd.Timedelta(hours=9), l[0], chosen, l[1], "retour_echec_livraison", oid))
            if mp in PREPAID:
                add_refund(oid, None, "annulation", "echec_livraison", None, total, fail_t, back, back + pd.Timedelta(days=int(rng.integers(1, 5))), mp, "rembourse", None)
            bad_exp[c] += 1; churn_hit(c, (fail_t.normalize() - START).days)
            continue
        if del_t > CUTOFF:
            o["statut_commande"] = "expediee"; shp["statut_livraison"] = "en_transit"; continue
        o["statut_commande"] = "livree"
        shp["statut_livraison"] = "livree"; shp["date_livraison_reelle"] = del_t; shp["nb_tentatives"] = attempts; shp["date_dernier_evenement"] = del_t
        has_success[c] = True
        if mp == "paiement_a_la_livraison":
            rev = del_t.normalize() + pd.Timedelta(days=int(rng.integers(3, 11)))
            pay_row(oid, 1, mp, total, "encaisse", None, del_t, TR_NAME[tr_id], rev if rev <= CUTOFF else None)
        elif mp == "virement":
            pt = del_t + pd.Timedelta(days=int(rng.integers(5, 40)))
            if pt <= CUTOFF:
                pay_row(oid, 1, mp, total, "reussi", None, pt, "Banque")
        if late >= 3:
            bad_exp[c] += 1; churn_hit(c, (dd - START).days)
            if rng.random() < 0.15:
                gv = float(rng.choice([10, 20]))
                gt = del_t + pd.Timedelta(days=int(rng.integers(1, 4)))
                add_refund(oid, None, "geste_commercial", "retard_livraison", None, gv, gt, None, gt, "bon_achat", "rembourse", None)
        # retours
        ratio = 1 - (remise / sous_total if sous_total else 0)
        n_ret_full = 0; n_ret_req = 0
        for lid, l in zip(line_ids, lines):
            ci = P_CAT_IDX[l[0]]
            pr = CATS[ci][6] * (1.6 if late >= 2 else 1.0) * (0.6 if pers == "professionnel" else 1.0) * (1.3 if pers == "chasseur_promo" else 1.0)
            if rng.random() >= pr:
                continue
            reasons = RET_REASONS["Mode"] if CATS[ci][0] == "Mode" else RET_REASONS["default"]
            motif = rng.choice(reasons)
            if late >= 3 and rng.random() < 0.3:
                motif = "livraison_trop_tardive"
            qret = l[1] if l[1] == 1 or rng.random() < 0.6 else int(rng.integers(1, l[1]))
            hors_delai = rng.random() < 0.04
            req = add_business_days(del_t, int(rng.integers(11, 18)) if hors_delai else int(rng.integers(0, 10)))
            req = req + pd.Timedelta(hours=int(rng.integers(8, 22)), minutes=int(rng.integers(0, 60)))
            if req <= del_t:
                req = del_t + pd.Timedelta(minutes=int(rng.integers(60, 300)))
            amount = l[4] * qret * ratio
            mode_r = mp if mp in PREPAID or mp == "virement" else rng.choice(["virement", "bon_achat"], p=[0.55, 0.45])
            n_ret_req += 1
            if hors_delai:
                add_refund(oid, lid, "retour", motif, qret, amount, req, None, None, mode_r, "refuse", None)
                bad_exp[c] += 1; churn_hit(c, (req.normalize() - START).days)
                continue
            rec = req + pd.Timedelta(days=int(rng.integers(2, 6)))
            ok_state = rng.random() < 0.8 or motif in ("taille_inadaptee", "changement_d_avis")
            refused = (not ok_state) and rng.random() < 0.2
            etat = "revendable" if ok_state else "non_revendable"
            if refused:
                add_refund(oid, lid, "retour", motif, qret, amount, req, rec, None, mode_r, "refuse", etat)
                bad_exp[c] += 1; churn_hit(c, (req.normalize() - START).days)
                continue
            tref = rec + pd.Timedelta(days=int(rng.integers(1, 8)))
            add_refund(oid, lid, "retour", motif, qret, amount, req, rec, tref, mode_r, "rembourse", etat)
            if rec <= CUTOFF:
                events[max((rec.normalize() - START).days, d + 1)].append(
                    ("in", rec, l[0], chosen, qret, "retour_client" if ok_state else "retour_client_non_revendable", oid))
            if req <= CUTOFF and qret == l[1]:
                n_ret_full += 1
        if n_ret_req and refunds and refunds[-1]["commande_id"] == oid:
            if n_ret_full == len(lines):
                o["statut_commande"] = "retournee"
            elif any(r["commande_id"] == oid and r["type_remboursement"] == "retour" and r["statut"] != "refuse" for r in refunds[-len(lines):]):
                o["statut_commande"] = "partiellement_retournee"
        review_candidates.append((oid, c, line_ids, lines, del_t, late, o["statut_commande"]))
    for ev in sorted(events.pop(d, []), key=lambda e: e[1]):
        kind, ts = ev[0], ev[1]
        if kind == "in":
            _, ts, p, w, q, typ, ref = ev
            stock[p, w] += q
            mv(ts, p, w, typ, q, ref, cost_at(p, ts))
            if typ == "retour_client_non_revendable":
                stock[p, w] -= q
                mv(ts + pd.Timedelta(minutes=30), p, w, "mise_au_rebut", -q, ref, cost_at(p, ts))
        elif kind == "po":
            _, ts, poi, items, w = ev
            for (lidx, p, qr) in items:
                stock[p, w] += qr; on_order[p, w] -= po_lines[lidx]["quantite_commandee"]
                if qr:
                    mv(ts, p, w, "reception_fournisseur", qr, pos[poi]["commande_fournisseur_id"], po_lines[lidx]["cout_unitaire_ht"])
    # ---- réapprovisionnement (jours ouvrés)
    if day.weekday() < 5 and day not in HOLI_SET:
        days_since = d - LAUNCH
        avgd = np.where((days_since >= RING)[:, None], dem_sum / RING, np.maximum(planned_avg, dem_sum / max(1, RING)))
        rop = avgd * (P_LT[:, None] + 6)
        target = avgd * (P_LT[:, None] + 36)
        active = ((LAUNCH <= d) & (ARRET > d + P_LT + 10))[:, None]
        need = (stock + on_order <= rop) & active & (avgd > 0)
        groups = defaultdict(list)
        for p, w in zip(*np.where(need)):
            q = int(math.ceil(target[p, w] - stock[p, w] - on_order[p, w]))
            q = max(q, 3)
            if q > 10:
                q = int(math.ceil(q / 5) * 5)
            groups[(SUP_OF[p], w)].append((p, q))
        for (s, w), items in groups.items():
            po_seq += 1
            poid = f"CF{po_seq:06d}"
            ts = day + pd.Timedelta(hours=int(rng.integers(9, 17)))
            lt = SUP_LT[s] * float(rng.lognormal(0, 0.15))
            exp_d = day + pd.Timedelta(days=SUP_LT[s])
            if rng.random() > SUP_REL[s]:
                lt += int(rng.integers(3, 16))
            partial_p = 0.06
            if s == DISRUPTED_SUP and DISRUPT_WINDOW[0] - pd.Timedelta(days=40) <= day <= DISRUPT_WINDOW[1] - pd.Timedelta(days=30):
                lt += int(rng.integers(25, 46)); partial_p = 0.5
            rec_d = day + pd.Timedelta(days=int(round(lt)))
            if s == DISRUPTED_SUP and DISRUPT_WINDOW[0] <= rec_d <= DISRUPT_WINDOW[1]:
                rec_d = DISRUPT_WINDOW[1] + pd.Timedelta(days=int(rng.integers(0, 10))); partial_p = 0.5
            while rec_d.weekday() == 6 or rec_d in HOLI_SET:
                rec_d += pd.Timedelta(days=1)
            poi = len(pos)
            total_ht = 0.0; ev_items = []; any_partial = False
            for (p, q) in items:
                pol_seq += 1
                cu = r3(cost_at(p, ts) * rng.uniform(0.97, 1.03))
                qr = q if rng.random() > partial_p else int(q * rng.uniform(0.5, 0.95))
                any_partial |= qr < q
                po_lines.append({"ligne_cf_id": f"LCF{pol_seq:07d}", "commande_fournisseur_id": poid, "produit_id": P.produit_id.iat[p],
                                 "quantite_commandee": q, "quantite_recue": qr if rec_d <= END else None, "cout_unitaire_ht": cu,
                                 "montant_ligne_ht": r3(q * cu)})
                total_ht += q * cu
                on_order[p, w] += q
                ev_items.append((len(po_lines) - 1, p, qr))
            rec_ts = rec_d + pd.Timedelta(hours=8)
            pos.append({"commande_fournisseur_id": poid, "fournisseur_id": s, "entrepot_id": WH[w], "date_commande": ts,
                        "date_livraison_prevue": exp_d.strftime("%Y-%m-%d"), "date_reception": rec_ts if rec_d <= END else None,
                        "statut": ("partiellement_receptionnee" if any_partial else "receptionnee") if rec_d <= END else "en_cours",
                        "montant_total_ht": r3(total_ht)})
            if rec_d <= END:
                events[(rec_d - START).days].append(("po", rec_ts, poi, ev_items, w))
    # ---- inventaire de fin de mois (démarque)
    if (day + pd.Timedelta(days=1)).day == 1:
        cand = np.argwhere(stock > 5)
        sel = cand[rng.random(len(cand)) < 0.02]
        for p, w in sel:
            q = int(rng.integers(1, 4))
            stock[p, w] -= q
            mv(day + pd.Timedelta(hours=20), p, w, "ajustement_inventaire", -q, f"INV-{day.strftime('%Y%m')}", cost_at(p, day))
        sel2 = cand[rng.random(len(cand)) < 0.004]
        for p, w in sel2:
            q = int(rng.integers(1, 3))
            stock[p, w] += q
            mv(day + pd.Timedelta(hours=20), p, w, "ajustement_inventaire", q, f"INV-{day.strftime('%Y%m')}", cost_at(p, day))

print("commandes :", len(orders), "lignes :", len(lines_out), "paiements :", len(payments), "remboursements :", len(refunds),
      "livraisons :", len(shipments), "CF :", len(pos), "mouvements :", len(movements))
