# -*- coding: utf-8 -*-
"""TuniShop - générateur de données synthétiques (partie 1 : référentiels)."""
import numpy as np, pandas as pd, math, string

SEED = 2026
rng = np.random.default_rng(SEED)
START = pd.Timestamp("2023-01-01")
END = pd.Timestamp("2025-12-31")
CUTOFF = pd.Timestamp("2025-12-31 23:59:59")
DAYS = pd.date_range(START, END, freq="D")
D = len(DAYS)

def r3(x):
    return float(np.round(x, 3))

def price_900(x):
    """Prix psychologique tunisien en .900 (ex : 129,900 DT)."""
    if x < 10:
        return round(math.floor(x) + 0.9, 3) if x >= 1 else 0.9
    return round(math.floor(x) + 0.9, 3)

# ---------------------------------------------------------------- Géographie
GOVS = [
    ("Tunis", "Grand Tunis", 10.0, ["Tunis", "La Marsa", "Le Bardo", "Carthage"]),
    ("Ariana", "Grand Tunis", 6.0, ["Ariana Ville", "La Soukra", "Raoued"]),
    ("Ben Arous", "Grand Tunis", 6.5, ["Ben Arous", "Radès", "Ezzahra", "Mégrine"]),
    ("Manouba", "Grand Tunis", 3.8, ["Manouba", "Den Den", "Oued Ellil"]),
    ("Nabeul", "Nord-Est", 6.5, ["Nabeul", "Hammamet", "Kélibia"]),
    ("Zaghouan", "Nord-Est", 1.4, ["Zaghouan", "El Fahs"]),
    ("Bizerte", "Nord-Est", 4.6, ["Bizerte", "Menzel Bourguiba", "Mateur"]),
    ("Béja", "Nord-Ouest", 2.3, ["Béja", "Medjez el-Bab"]),
    ("Jendouba", "Nord-Ouest", 2.6, ["Jendouba", "Tabarka", "Aïn Draham"]),
    ("Le Kef", "Nord-Ouest", 1.8, ["Le Kef", "Dahmani"]),
    ("Siliana", "Nord-Ouest", 1.5, ["Siliana", "Makthar"]),
    ("Sousse", "Centre-Est", 6.5, ["Sousse", "Hammam Sousse", "Msaken", "Kalâa Kebira"]),
    ("Monastir", "Centre-Est", 4.8, ["Monastir", "Moknine", "Ksar Hellal"]),
    ("Mahdia", "Centre-Est", 3.2, ["Mahdia", "El Jem", "Ksour Essef"]),
    ("Sfax", "Centre-Est", 9.0, ["Sfax", "Sakiet Ezzit", "Sakiet Eddaïer"]),
    ("Kairouan", "Centre-Ouest", 3.8, ["Kairouan", "Haffouz"]),
    ("Kasserine", "Centre-Ouest", 2.6, ["Kasserine", "Sbeïtla"]),
    ("Sidi Bouzid", "Centre-Ouest", 2.6, ["Sidi Bouzid", "Regueb"]),
    ("Gabès", "Sud-Est", 3.0, ["Gabès", "El Hamma"]),
    ("Médenine", "Sud-Est", 4.0, ["Médenine", "Djerba Houmt Souk", "Zarzis"]),
    ("Tataouine", "Sud-Est", 1.1, ["Tataouine", "Ghomrassen"]),
    ("Gafsa", "Sud-Ouest", 2.4, ["Gafsa", "Métlaoui", "Redeyef"]),
    ("Tozeur", "Sud-Ouest", 0.8, ["Tozeur", "Nefta"]),
    ("Kébili", "Sud-Ouest", 1.1, ["Kébili", "Douz"]),
]
gov_df = pd.DataFrame({
    "gouvernorat_id": [f"G{i+1:02d}" for i in range(len(GOVS))],
    "gouvernorat": [g[0] for g in GOVS],
    "region": [g[1] for g in GOVS],
    "poids_clients": [g[2] for g in GOVS],
})
WH_OF_REGION = {"Grand Tunis": "ENT01", "Nord-Est": "ENT01", "Nord-Ouest": "ENT01",
                "Centre-Est": "ENT02", "Centre-Ouest": "ENT02", "Sud-Est": "ENT03", "Sud-Ouest": "ENT03"}
gov_df["entrepot_rattachement_id"] = gov_df["region"].map(WH_OF_REGION)
gov_df.loc[gov_df.gouvernorat == "Sfax", "entrepot_rattachement_id"] = "ENT03"
gov_df["zone_livraison"] = gov_df["region"].map({
    "Grand Tunis": "Z1", "Nord-Est": "Z2", "Centre-Est": "Z2", "Nord-Ouest": "Z3",
    "Centre-Ouest": "Z3", "Sud-Est": "Z3", "Sud-Ouest": "Z4"})
GOV_CITIES = {f"G{i+1:02d}": g[3] for i, g in enumerate(GOVS)}

entrepots = pd.DataFrame([
    ("ENT01", "Entrepôt Grand Tunis", "Ben Arous", "G03", "2019-03-01", 4200),
    ("ENT02", "Entrepôt Sahel", "Sousse", "G12", "2021-09-15", 2500),
    ("ENT03", "Entrepôt Sud", "Sfax", "G15", "2022-05-02", 2200),
], columns=["entrepot_id", "nom_entrepot", "ville", "gouvernorat_id", "date_ouverture", "surface_m2"])
WH = list(entrepots.entrepot_id)
WH_GOV = dict(zip(entrepots.entrepot_id, entrepots.gouvernorat_id))

# Délai de transit de base (jours) entrepôt -> région
TRANSIT = {
    "ENT01": {"Grand Tunis": 1, "Nord-Est": 1.5, "Nord-Ouest": 2.2, "Centre-Est": 2, "Centre-Ouest": 2.5, "Sud-Est": 3.2, "Sud-Ouest": 3.5},
    "ENT02": {"Grand Tunis": 2, "Nord-Est": 2, "Nord-Ouest": 2.8, "Centre-Est": 1.2, "Centre-Ouest": 1.6, "Sud-Est": 2.4, "Sud-Ouest": 2.8},
    "ENT03": {"Grand Tunis": 3, "Nord-Est": 3, "Nord-Ouest": 3.4, "Centre-Est": 1.5, "Centre-Ouest": 2.2, "Sud-Est": 1.5, "Sud-Ouest": 2.0},
}

transporteurs = pd.DataFrame([
    ("TR01", "Rapid Colis", "national", 6.5, 0.0, "2020-01-01"),
    ("TR02", "TunExpress", "national", 7.8, -0.3, "2020-06-01"),
    ("TR03", "SahelLog", "régional Centre/Sud", 5.4, 0.2, "2021-09-15"),
    ("TR04", "Poste Colis Plus", "national", 4.9, 0.8, "2019-01-01"),
], columns=["transporteur_id", "nom_transporteur", "couverture", "cout_base_ht", "ecart_delai_moyen_j", "date_debut_contrat"])

# ---------------------------------------------------------------- Calendrier
HOLI = {}
for y in (2023, 2024, 2025):
    for md, nm in [("01-01", "Jour de l'An"), ("03-20", "Fête de l'Indépendance"), ("04-09", "Journée des Martyrs"),
                   ("05-01", "Fête du Travail"), ("07-25", "Fête de la République"), ("08-13", "Fête de la Femme"),
                   ("10-15", "Fête de l'Évacuation"), ("12-17", "Fête de la Révolution")]:
        HOLI[pd.Timestamp(f"{y}-{md}")] = nm
# Fêtes religieuses : dates indicatives (calendrier lunaire)
REL = {
    2023: {"fitr": "2023-04-21", "adha": "2023-06-28", "hijri": "2023-07-19", "mouled": "2023-09-27", "ram": ("2023-03-23", "2023-04-20")},
    2024: {"fitr": "2024-04-10", "adha": "2024-06-16", "hijri": "2024-07-07", "mouled": "2024-09-15", "ram": ("2024-03-11", "2024-04-09")},
    2025: {"fitr": "2025-03-30", "adha": "2025-06-06", "hijri": "2025-06-26", "mouled": "2025-09-04", "ram": ("2025-03-01", "2025-03-29")},
}
for y, r in REL.items():
    f = pd.Timestamp(r["fitr"]); a = pd.Timestamp(r["adha"])
    for k in range(3):
        HOLI.setdefault(f + pd.Timedelta(days=k), "Aïd el-Fitr")
    for k in range(2):
        HOLI.setdefault(a + pd.Timedelta(days=k), "Aïd el-Idha")
    HOLI.setdefault(pd.Timestamp(r["hijri"]), "Nouvel An de l'Hégire")
    HOLI.setdefault(pd.Timestamp(r["mouled"]), "Mouled")

def last_friday_nov(y):
    d = pd.Timestamp(f"{y}-11-30")
    while d.weekday() != 4:
        d -= pd.Timedelta(days=1)
    return d

period = []
season = np.ones(D)
is_ram = np.zeros(D, bool)
cat_boost_flags = []  # list of sets per day
MOIS = ["janvier", "février", "mars", "avril", "mai", "juin", "juillet", "août", "septembre", "octobre", "novembre", "décembre"]
JOURS = ["lundi", "mardi", "mercredi", "jeudi", "vendredi", "samedi", "dimanche"]
WD_FACTOR = [0.95, 0.95, 0.97, 1.0, 0.92, 1.08, 1.15]
for i, d in enumerate(DAYS):
    y = d.year; r = REL[y]
    tags = set(); p = "normale"; f = WD_FACTOR[d.weekday()]
    rs, re_ = pd.Timestamp(r["ram"][0]), pd.Timestamp(r["ram"][1])
    fitr = pd.Timestamp(r["fitr"]); adha = pd.Timestamp(r["adha"])
    bf = last_friday_nov(y)
    if pd.Timestamp(f"{y}-02-01") <= d <= pd.Timestamp(f"{y}-03-07"):
        p = "soldes_hiver"; f *= 1.25; tags.add("soldes")
    if pd.Timestamp(f"{y}-08-01") <= d <= pd.Timestamp(f"{y}-09-07"):
        p = "soldes_ete"; f *= 1.2; tags.add("soldes")
    if pd.Timestamp(f"{y}-06-15") <= d <= pd.Timestamp(f"{y}-08-31"):
        tags.add("ete")
        if d.month == 7:
            f *= 0.9
    if pd.Timestamp(f"{y}-09-01") <= d <= pd.Timestamp(f"{y}-09-25"):
        p = "rentree_scolaire"; f *= 1.25; tags.add("rentree")
    if rs <= d <= re_:
        is_ram[i] = True; p = "ramadan"; f *= 1.2; tags.add("ramadan")
        if (fitr - d).days <= 10:
            p = "pre_aid_fitr"; f *= 1.25; tags.add("pre_fitr")
    if 0 < (adha - d).days <= 8:
        p = "pre_aid_idha"; f *= 1.15; tags.add("pre_adha")
    if bf - pd.Timedelta(days=6) <= d <= bf + pd.Timedelta(days=3):
        p = "black_friday"; f *= 1.7; tags.add("bf")
        if d == bf:
            f *= 1.6
    if pd.Timestamp(f"{y}-12-15") <= d <= pd.Timestamp(f"{y}-12-31"):
        p = "fin_annee" if p == "normale" else p; f *= 1.15; tags.add("fin_annee")
    if d in HOLI:
        f *= 0.75
    season[i] = f; period.append(p); cat_boost_flags.append(tags)

calendrier = pd.DataFrame({
    "date": DAYS.strftime("%Y-%m-%d"),
    "annee": DAYS.year, "trimestre": DAYS.quarter, "mois": DAYS.month,
    "nom_mois": [MOIS[m - 1] for m in DAYS.month],
    "semaine_iso": DAYS.isocalendar().week.values.astype(int),
    "jour_semaine": DAYS.weekday + 1,
    "nom_jour": [JOURS[w] for w in DAYS.weekday],
    "est_weekend": DAYS.weekday >= 5,
    "est_jour_ferie": [d in HOLI for d in DAYS],
    "nom_jour_ferie": [HOLI.get(d, "") for d in DAYS],
    "est_ramadan": is_ram,
    "periode_commerciale": period,
})
HOLI_SET = set(HOLI.keys())
NP_HOLI = np.array(sorted(HOLI_SET), dtype="datetime64[D]")

def is_ship_day(ts):
    """Jour d'expédition : lundi-samedi hors jours fériés."""
    return ts.weekday() != 6 and ts.normalize() not in HOLI_SET

def next_ship_day(ts):
    t = ts.normalize()
    while not is_ship_day(t):
        t += pd.Timedelta(days=1)
    return t

def add_business_days(ts, n):
    """Jours ouvrables (lun-ven hors fériés) : utilisé pour le délai de rétractation."""
    return pd.Timestamp(np.busday_offset(np.datetime64(ts.normalize(), "D"), n, roll="forward",
                                         weekmask="1111100", holidays=NP_HOLI))

# Tendance : croissance ~22 %/an + adoption mobile
trend = 1 + 0.22 * (np.arange(D) / 365.0)

# ---------------------------------------------------------------- Catégories
# (categorie, sous_categorie, nb_produits, prix_min, prix_max, tva, taux_retour, marge, poids_min, poids_max, pays_fourn, boosts)
CATS = [
    ("Électronique & High-Tech", "Smartphones", 28, 380, 2600, 19, 0.06, 0.14, 0.2, 0.5, "import", {"bf": 2.2, "fin_annee": 1.3}),
    ("Électronique & High-Tech", "Accessoires téléphone", 45, 12, 130, 19, 0.07, 0.50, 0.05, 0.4, "import", {"bf": 1.6}),
    ("Électronique & High-Tech", "Informatique", 26, 650, 4200, 19, 0.05, 0.13, 1.0, 3.5, "import", {"bf": 2.0, "rentree": 1.7}),
    ("Électronique & High-Tech", "Audio & Casques", 24, 35, 650, 19, 0.08, 0.35, 0.1, 2.0, "import", {"bf": 1.8, "fin_annee": 1.4}),
    ("Électronique & High-Tech", "TV & Vidéo", 14, 690, 3600, 19, 0.04, 0.15, 6, 18, "import", {"bf": 2.2}),
    ("Électroménager", "Petit électroménager", 34, 55, 480, 19, 0.05, 0.30, 1, 6, "mixte", {"ramadan": 1.4, "pre_adha": 1.6, "bf": 1.6}),
    ("Électroménager", "Gros électroménager", 18, 890, 3200, 19, 0.03, 0.16, 35, 80, "mixte", {"pre_adha": 1.5, "bf": 1.7}),
    ("Électroménager", "Climatisation & Chauffage", 12, 120, 2900, 19, 0.03, 0.18, 4, 45, "import", {"ete": 2.8}),
    ("Mode", "Mode Femme", 60, 25, 260, 19, 0.17, 0.55, 0.2, 1.2, "local", {"soldes": 1.7, "pre_fitr": 2.3}),
    ("Mode", "Mode Homme", 45, 25, 240, 19, 0.14, 0.55, 0.2, 1.2, "local", {"soldes": 1.6, "pre_fitr": 2.1}),
    ("Mode", "Chaussures", 35, 45, 320, 19, 0.15, 0.50, 0.6, 1.5, "mixte", {"soldes": 1.6, "pre_fitr": 2.0, "rentree": 1.3}),
    ("Beauté & Santé", "Parfums & Cosmétiques", 40, 15, 290, 19, 0.03, 0.45, 0.1, 0.6, "mixte", {"fin_annee": 1.6, "pre_fitr": 1.4, "ete": 1.2}),
    ("Beauté & Santé", "Parapharmacie", 22, 8, 120, 13, 0.02, 0.35, 0.1, 0.8, "local", {}),
    ("Maison & Cuisine", "Cuisine & Arts de la table", 38, 15, 380, 19, 0.05, 0.45, 0.4, 5, "local", {"ramadan": 1.7, "pre_adha": 1.4}),
    ("Maison & Cuisine", "Décoration & Linge", 32, 20, 450, 19, 0.06, 0.50, 0.5, 8, "local", {"soldes": 1.3, "pre_fitr": 1.3}),
    ("Épicerie fine", "Produits du terroir", 30, 6, 95, 7, 0.01, 0.30, 0.3, 5, "local", {"ramadan": 2.3, "pre_fitr": 1.4}),
    ("Bébé & Enfants", "Puériculture & Jouets", 30, 18, 420, 19, 0.06, 0.40, 0.3, 12, "mixte", {"pre_fitr": 1.7, "fin_annee": 1.4, "rentree": 1.2}),
    ("Sport & Loisirs", "Sport & Plein air", 28, 25, 950, 19, 0.07, 0.38, 0.3, 25, "mixte", {"ete": 1.5}),
    ("Fournitures & Livres", "Fournitures scolaires & Livres", 35, 4, 85, 7, 0.02, 0.32, 0.1, 2, "local", {"rentree": 4.0}),
]
cat_rows = []
for k, c in enumerate(CATS):
    cat_rows.append({"categorie_id": f"CAT{k+1:02d}", "categorie": c[0], "sous_categorie": c[1], "taux_tva": c[5],
                     "taux_retour_cible": c[6], "marge_brute_cible": c[7]})
categories = pd.DataFrame(cat_rows)

# ---------------------------------------------------------------- Fournisseurs
SUP_LOCAL = ["Atlas Distribution", "Carthage Import-Export", "Medina Textiles", "Zitouna Foods", "Sahel Industries",
             "Jasmin Cosmetics", "Kairouan Artisanat", "Bizerte Plast", "Nabeul Céramique", "Djerba Trading",
             "Cap Bon Agro", "Tunis Papeterie", "Sfax Electro Distribution", "Monastir Confection", "Golfe Sport",
             "Oasis Bio", "El Jem Maison", "Hammamet Linge", "Gafsa Négoce", "Tabarka Distribution", "Mahdia Fashion",
             "Ariana Kids", "Manouba Electro", "Sousse Shoes"]
SUP_IMPORT = [("Shenzhen Bright Tech", "Chine"), ("Guangzhou Home Appliances", "Chine"), ("Ningbo Accessories Co.", "Chine"),
              ("Yiwu Global Toys", "Chine"), ("Istanbul Moda Tekstil", "Turquie"), ("Ankara Beyaz Eşya", "Turquie"),
              ("Bursa Home", "Turquie"), ("Lyon Distribution Pro", "France"), ("Marseille Cosmétiques", "France"),
              ("Milano Calzature", "Italie"), ("Torino Elettro", "Italie"), ("Hangzhou Smart Devices", "Chine"),
              ("Izmir Sport", "Turquie"), ("Paris Audio Pro", "France"), ("Dongguan Climatech", "Chine"), ("Valencia Kids", "Espagne")]
sup_rows = []
for i, n in enumerate(SUP_LOCAL):
    sup_rows.append((n, "Tunisie", int(rng.integers(3, 11)), rng.choice(["30 jours fin de mois", "45 jours", "60 jours", "comptant"])))
for n, c in SUP_IMPORT:
    sup_rows.append((n, c, int(rng.integers(21, 46)), rng.choice(["paiement à la commande", "30% acompte / 70% à expédition", "lettre de crédit 60 jours"])))
fournisseurs = pd.DataFrame(sup_rows, columns=["nom_fournisseur", "pays", "delai_appro_moyen_j", "conditions_paiement"])
fournisseurs.insert(0, "fournisseur_id", [f"FRN{i+1:03d}" for i in range(len(fournisseurs))])
fournisseurs["fiabilite_livraison"] = np.round(rng.uniform(0.80, 0.99, len(fournisseurs)), 2)
fournisseurs["email_contact"] = ["achats@" + n.lower().replace(" ", "").replace("-", "").replace(".", "").replace("ş", "s").replace("é", "e")[:18] + (".tn" if p == "Tunisie" else ".com")
                                 for n, p in zip(fournisseurs.nom_fournisseur, fournisseurs.pays)]
LOCAL_IDS = list(fournisseurs.fournisseur_id[fournisseurs.pays == "Tunisie"])
IMPORT_IDS = list(fournisseurs.fournisseur_id[fournisseurs.pays != "Tunisie"])
# Fournisseur perturbé (scénario caché) : Shenzhen Bright Tech, été 2024
DISRUPTED_SUP = fournisseurs.loc[fournisseurs.nom_fournisseur == "Shenzhen Bright Tech", "fournisseur_id"].iloc[0]
DISRUPT_WINDOW = (pd.Timestamp("2024-06-10"), pd.Timestamp("2024-08-20"))

# ---------------------------------------------------------------- Produits
BRANDS = {
    "Smartphones": ["Nexora", "Volta Mobile", "Sirius", "Kiwa"], "Accessoires téléphone": ["Volta", "PowerPlus", "Kiwa", "Linko"],
    "Informatique": ["Kompu", "Nexora", "Byteline"], "Audio & Casques": ["Sonaro", "BassLab", "Kiwa"], "TV & Vidéo": ["Visiona", "Nexora", "Lumia TV"],
    "Petit électroménager": ["Carthago Home", "Cuisimax", "Electo"], "Gros électroménager": ["Frigolux", "Carthago Home", "Electo"],
    "Climatisation & Chauffage": ["AirSahel", "Frigolux", "Climatek"], "Mode Femme": ["Yasmine", "Medina Style", "Lina Couture"],
    "Mode Homme": ["Medina Style", "Barbary", "Urban Tunis"], "Chaussures": ["Sabra", "Urban Tunis", "Passo"],
    "Parfums & Cosmétiques": ["Jasmin Beauty", "Néroli", "Ambre d'Orient"], "Parapharmacie": ["DermaZit", "Bio Oasis", "Pharmasoin"],
    "Cuisine & Arts de la table": ["Nabeul Céramique", "Cuisimax", "Fakhar"], "Décoration & Linge": ["El Jem Maison", "Kilim & Co", "Douja Home"],
    "Produits du terroir": ["Zitouna", "Dattes Deglet", "Cap Bon", "Saveurs du Sud"], "Puériculture & Jouets": ["Ariana Kids", "Petit Prince", "Toyland"],
    "Sport & Plein air": ["Golfe Sport", "Atlas Outdoor", "Fitzone"], "Fournitures scolaires & Livres": ["Tunis Papeterie", "Éditions Alyssa", "Cahier d'Or"],
}
NOUNS = {
    "Smartphones": ["Smartphone"], "Accessoires téléphone": ["Coque", "Chargeur rapide", "Câble USB-C", "Power bank", "Protection écran", "Support voiture"],
    "Informatique": ["PC portable", "Ordinateur de bureau", "Écran", "Imprimante", "Tablette"], "Audio & Casques": ["Écouteurs sans fil", "Casque", "Enceinte Bluetooth", "Barre de son"],
    "TV & Vidéo": ["TV LED", "Smart TV", "Récepteur satellite", "Vidéoprojecteur"], "Petit électroménager": ["Robot pâtissier", "Blender", "Hachoir", "Friteuse sans huile", "Bouilloire", "Fer à repasser", "Aspirateur", "Machine à café"],
    "Gros électroménager": ["Réfrigérateur", "Machine à laver", "Cuisinière", "Lave-vaisselle", "Congélateur"], "Climatisation & Chauffage": ["Climatiseur", "Ventilateur", "Radiateur bain d'huile", "Chauffage à gaz"],
    "Mode Femme": ["Robe", "Jebba femme", "Blouse", "Jean", "Kaftan", "Veste", "Jupe", "Foulard"], "Mode Homme": ["Chemise", "Jebba homme", "Pantalon", "Polo", "Blouson", "Costume", "Jean"],
    "Chaussures": ["Baskets", "Mocassins", "Sandales", "Balgha", "Bottines", "Escarpins"], "Parfums & Cosmétiques": ["Eau de parfum", "Crème hydratante", "Rouge à lèvres", "Huile d'argan", "Sérum visage", "Gel douche"],
    "Parapharmacie": ["Écran solaire", "Shampooing doux", "Vitamines", "Thermomètre", "Crème réparatrice"], "Cuisine & Arts de la table": ["Couscoussier", "Service à thé", "Plat à tajine", "Batterie de cuisine", "Set de verres", "Poêle"],
    "Décoration & Linge": ["Kilim", "Parure de lit", "Rideaux", "Coussin brodé", "Lampe en fer forgé", "Miroir"], "Produits du terroir": ["Huile d'olive vierge extra", "Dattes Deglet Nour", "Harissa artisanale", "Miel de thym", "Bsissa", "Café turc", "Thé vert", "Makroudh"],
    "Puériculture & Jouets": ["Poussette", "Siège auto", "Jeu de construction", "Poupée", "Trottinette", "Puzzle"], "Sport & Plein air": ["Vélo", "Tapis de yoga", "Haltères", "Ballon", "Tente", "Survêtement"],
    "Fournitures scolaires & Livres": ["Cartable", "Lot de cahiers", "Trousse", "Calculatrice", "Roman", "Livre parascolaire", "Kit de géométrie"],
}
ADJ = ["Classic", "Pro", "Lite", "Max", "Plus", "Essentiel", "Premium", "Confort", "Évasion", "Prestige", "Eco", "Mini"]
prod_rows = []
pid = 0
for k, c in enumerate(CATS):
    cat_id = f"CAT{k+1:02d}"
    sub = c[1]
    for j in range(c[2]):
        pid += 1
        lo, hi = c[3], c[4]
        p23 = float(np.exp(rng.uniform(np.log(lo), np.log(hi))))
        p23 = price_900(p23)
        brand = rng.choice(BRANDS[sub]); noun = rng.choice(NOUNS[sub])
        name = f"{noun} {brand} {rng.choice(ADJ)} {rng.integers(10, 99)}"
        if c[10] == "local":
            sup = rng.choice(LOCAL_IDS)
        elif c[10] == "import":
            sup = rng.choice(IMPORT_IDS)
        else:
            sup = rng.choice(LOCAL_IDS if rng.random() < 0.5 else IMPORT_IDS)
        if sub in ("Smartphones", "Accessoires téléphone") and rng.random() < 0.6:
            sup = DISRUPTED_SUP
        launch = START if rng.random() < 0.72 else START + pd.Timedelta(days=int(rng.integers(30, D - 120)))
        end = None
        if rng.random() < 0.08:
            end = launch + pd.Timedelta(days=int(rng.integers(200, 700)))
            if end >= END:
                end = None
        prod_rows.append({
            "produit_id": f"PRD{pid:04d}", "sku": f"TS-{cat_id[3:]}-{pid:05d}", "nom_produit": name, "categorie_id": cat_id,
            "marque": brand, "fournisseur_id": sup, "prix_2023": p23, "tva": c[5], "marge": c[7],
            "poids_kg": round(float(rng.uniform(c[8], c[9])), 2), "date_lancement": launch, "date_arret": end,
            "popularite": float(rng.lognormal(0, 0.9)), "infl": float(rng.uniform(0.03, 0.10)),
        })
P = pd.DataFrame(prod_rows)
NP_ = len(P)
P_CAT_IDX = P.categorie_id.str[3:].astype(int).values - 1
P_SUB = np.array([CATS[i][1] for i in P_CAT_IDX])

# Historique de prix (SCD type 2) : révision au 1er janvier de chaque année
price_hist = []
price_by_year = {}
cost_by_year = {}
for i, r in P.iterrows():
    for y in (2023, 2024, 2025):
        py = price_900(r.prix_2023 * (1 + r.infl) ** (y - 2023)) if y > 2023 else r.prix_2023
        ht = py / (1 + r.tva / 100)
        cost = r3(ht * (1 - r.marge) * rng.uniform(0.95, 1.05))
        price_by_year[(i, y)] = py; cost_by_year[(i, y)] = cost
        start = max(pd.Timestamp(f"{y}-01-01"), r.date_lancement)
        endy = pd.Timestamp(f"{y}-12-31")
        if r.date_arret is not None and r.date_arret < endy:
            endy = r.date_arret
        if start > endy:
            continue
        price_hist.append({"produit_id": r.produit_id, "date_debut": start.strftime("%Y-%m-%d"),
                           "date_fin": None if (y == 2025 and r.date_arret is None) else endy.strftime("%Y-%m-%d"),
                           "prix_catalogue_ttc": py, "cout_achat_unitaire_ht": cost, "est_prix_actuel": y == 2025 and r.date_arret is None})
prix_hist = pd.DataFrame(price_hist)
# un prix "actuel" pour les produits arrêtés = dernier prix
prix_hist.insert(0, "prix_id", [f"PRX{i+1:05d}" for i in range(len(prix_hist))])

# Promotions par produit et par période (fixe pour toute la période)
PROMO = {}  # (prod_idx, tag, year) -> taux
for i in range(NP_):
    sub = P_SUB[i]
    for y in (2023, 2024, 2025):
        if sub in ("Mode Femme", "Mode Homme", "Chaussures", "Décoration & Linge") and rng.random() < 0.6:
            PROMO[(i, "soldes", y)] = float(rng.choice([0.2, 0.3, 0.4, 0.5]))
        if CATS[P_CAT_IDX[i]][0] in ("Électronique & High-Tech", "Électroménager") and rng.random() < 0.5:
            PROMO[(i, "bf", y)] = float(rng.choice([0.1, 0.15, 0.2, 0.3]))

# ---------------------------------------------------------------- Campagnes marketing
CH = {  # canal: (part, budget_j_min, budget_j_max, cpm, ctr, force_attribution)
    "facebook_ads": (0.27, 150, 900, 4.5, 0.012, 1.0),
    "instagram_ads": (0.20, 120, 800, 5.5, 0.010, 0.9),
    "google_ads": (0.16, 120, 700, 12.0, 0.035, 1.3),
    "tiktok_ads": (0.13, 100, 700, 2.8, 0.009, 0.45),
    "emailing": (0.10, 20, 80, 1.2, 0.030, 1.6),
    "sms": (0.07, 40, 150, 25.0, 0.020, 0.9),
    "influence": (0.07, 300, 1500, 6.0, 0.006, 0.8),
}
CAMP_THEMES = {"ramadan": "Ramadan Karim", "pre_fitr": "Spécial Aïd", "soldes": "Soldes", "rentree": "Rentrée scolaire",
               "bf": "Black Friday", "fin_annee": "Fêtes de fin d'année", "ete": "Été", None: "Toujours actif"}
camp_rows = []
cid = 0
for y in (2023, 2024, 2025):
    anchors = []
    r = REL[y]
    anchors += [("ramadan", pd.Timestamp(r["ram"][0]), 30), ("pre_fitr", pd.Timestamp(r["fitr"]) - pd.Timedelta(days=10), 10),
                ("soldes", pd.Timestamp(f"{y}-02-01"), 35), ("soldes", pd.Timestamp(f"{y}-08-01"), 35),
                ("rentree", pd.Timestamp(f"{y}-08-25"), 30), ("bf", last_friday_nov(y) - pd.Timedelta(days=6), 10),
                ("fin_annee", pd.Timestamp(f"{y}-12-12"), 20), ("ete", pd.Timestamp(f"{y}-06-20"), 40)]
    for tag, s, dur in anchors:
        for ch in rng.choice(list(CH), size=int(rng.integers(3, 6)), replace=False):
            cid += 1
            camp_rows.append((cid, tag, ch, s + pd.Timedelta(days=int(rng.integers(-3, 3))), dur + int(rng.integers(-3, 4)), y))
    for _ in range(int(14 + (y - 2023) * 4)):  # campagnes "toujours actives"
        cid += 1
        ch = rng.choice(list(CH), p=np.array([v[0] for v in CH.values()]) / sum(v[0] for v in CH.values()))
        s = pd.Timestamp(f"{y}-01-01") + pd.Timedelta(days=int(rng.integers(0, 350)))
        camp_rows.append((cid, None, ch, s, int(rng.integers(7, 28)), y))
camps = []
for (cid, tag, ch, s, dur, y) in camp_rows:
    s = max(s, START); e = min(s + pd.Timedelta(days=dur - 1), END)
    bmin, bmax = CH[ch][1], CH[ch][2]
    bj = float(rng.uniform(bmin, bmax)) * (1 + 0.25 * (y - 2023)) * (1.6 if tag in ("bf", "ramadan", "pre_fitr") else 1)
    obj = rng.choice(["acquisition", "conversion", "fidelisation"], p=[0.4, 0.45, 0.15] if ch not in ("emailing", "sms") else [0.05, 0.45, 0.5])
    camps.append({"campagne_id": f"CMP{cid:04d}", "nom_campagne": f"{CAMP_THEMES[tag]} {y} - {ch.replace('_', ' ').title()}" + ("" if tag else f" #{cid}"),
                  "canal": ch, "objectif": obj, "theme": tag or "permanent", "date_debut": s, "date_fin": e,
                  "budget_ttc": r3(bj * ((e - s).days + 1)), "budget_j": bj})
C = pd.DataFrame(camps)
C["categorie_ciblee_id"] = None
for i in C.index:
    t = C.at[i, "theme"]
    if t == "rentree":
        C.at[i, "categorie_ciblee_id"] = "CAT19"
    elif t == "bf" and rng.random() < 0.5:
        C.at[i, "categorie_ciblee_id"] = rng.choice(["CAT01", "CAT03", "CAT06"])
    elif t in ("soldes", "pre_fitr") and rng.random() < 0.5:
        C.at[i, "categorie_ciblee_id"] = rng.choice(["CAT09", "CAT10", "CAT11"])
    elif t == "ramadan" and rng.random() < 0.5:
        C.at[i, "categorie_ciblee_id"] = rng.choice(["CAT16", "CAT14"])

# Coupons
coupon_rows = [{"code_coupon": "BIENVENUE10", "type_remise": "pourcentage", "valeur": 10.0, "montant_min_ttc": 50.0, "plafond_remise_ttc": 30.0,
                "date_debut": "2022-01-01", "date_fin": None, "campagne_id": None, "reserve_premiere_commande": True}]
CODE_TAG = {"ramadan": "RAMADAN", "pre_fitr": "AID", "soldes": "SOLDES", "rentree": "RENTREE", "bf": "BF", "fin_annee": "FETES", "ete": "ETE", "permanent": "PROMO"}
C["code_coupon"] = None
used = set()
for i in C.index:
    if rng.random() < 0.45:
        y2 = str(C.at[i, "date_debut"].year)[2:]
        base = f"{CODE_TAG[C.at[i, 'theme']]}{y2}"
        code = base + C.at[i, "canal"][:2].upper()
        n = 1
        while code in used:
            n += 1; code = f"{base}{C.at[i, 'canal'][:2].upper()}{n}"
        used.add(code)
        typ = "pourcentage" if rng.random() < 0.8 else "montant_fixe"
        val = float(rng.choice([10, 15, 20])) if typ == "pourcentage" else float(rng.choice([10, 15, 20, 30]))
        coupon_rows.append({"code_coupon": code, "type_remise": typ, "valeur": val, "montant_min_ttc": float(rng.choice([60, 80, 100, 150])),
                            "plafond_remise_ttc": 60.0 if typ == "pourcentage" else None,
                            "date_debut": C.at[i, "date_debut"].strftime("%Y-%m-%d"), "date_fin": C.at[i, "date_fin"].strftime("%Y-%m-%d"),
                            "campagne_id": C.at[i, "campagne_id"], "reserve_premiere_commande": False})
        C.at[i, "code_coupon"] = code
coupons = pd.DataFrame(coupon_rows)
COUPON = {r.code_coupon: r for r in coupons.itertuples()}

# intensité marketing quotidienne
C_S = ((C.date_debut - START).dt.days).values
C_E = ((C.date_fin - START).dt.days).values
camp_int = np.zeros(D); acq_int = np.zeros(D)
active_camps = [[] for _ in range(D)]
for i in C.index:
    for d in range(C_S[i], C_E[i] + 1):
        w = C.at[i, "budget_j"] * CH[C.at[i, "canal"]][5]
        camp_int[d] += w
        if C.at[i, "objectif"] == "acquisition":
            acq_int[d] += w
        active_camps[d].append(i)
camp_int = camp_int / camp_int.mean() * 0.18
acq_int = acq_int / max(acq_int.mean(), 1) * 0.35

# ---------------------------------------------------------------- Clients
FN_F = ["Amira", "Yasmine", "Salma", "Ines", "Mariem", "Rania", "Sarra", "Nour", "Emna", "Fatma", "Asma", "Khadija", "Hiba", "Mouna", "Olfa",
        "Rim", "Siwar", "Wafa", "Leila", "Sonia", "Imen", "Nesrine", "Chaima", "Eya", "Malek", "Houda", "Samia", "Dorra", "Aya", "Lamia"]
FN_M = ["Mohamed", "Ahmed", "Ali", "Youssef", "Amine", "Hamza", "Karim", "Mehdi", "Omar", "Walid", "Sami", "Anis", "Bilel", "Firas", "Hichem",
        "Nizar", "Riadh", "Skander", "Slim", "Tarek", "Wassim", "Zied", "Aymen", "Fares", "Habib", "Moez", "Nabil", "Rami", "Seif", "Malek"]
LN = ["Ben Ali", "Trabelsi", "Jebali", "Gharbi", "Mejri", "Ayari", "Hammami", "Bouazizi", "Dridi", "Chaabane", "Ben Salah", "Ben Ammar",
      "Khelifi", "Mansouri", "Sassi", "Jlassi", "Saidi", "Hamdi", "Tlili", "Zouari", "Ferchichi", "Baccouche", "Masmoudi", "Karoui",
      "Kammoun", "Ellouze", "Chebbi", "Bouslama", "Mabrouk", "Riahi", "Ghannouchi", "Abidi", "Belhadj", "Brahmi", "Fourati", "Haddad",
      "Jaziri", "Lahmar", "Marzouki", "Nasri", "Ouali", "Rekik", "Sfar", "Turki", "Zaouali", "Ben Youssef", "Arfaoui", "Chouchane"]
COMPANY = ["Sarl", "SUARL", "SA"]
N_CUST = 16000
N_PRE = 3200
PERSONAS = ["occasionnel", "regulier", "chasseur_promo", "premium", "professionnel"]
PERS_P = [0.50, 0.24, 0.16, 0.08, 0.02]
RATE_M = {"occasionnel": 0.14, "regulier": 0.50, "chasseur_promo": 0.26, "premium": 0.70, "professionnel": 0.50}
LIFE_M = {"occasionnel": 9, "regulier": 26, "chasseur_promo": 14, "premium": 30, "professionnel": 36}

# dates d'inscription : base historique + nouvelles inscriptions pondérées (tendance x saison x acquisition)
pre_days = rng.integers(-560, 0, N_PRE)
w_sign = trend * season * (1 + acq_int)
w_sign = w_sign / w_sign.sum()
new_days = np.sort(rng.choice(np.arange(D - 3), size=N_CUST - N_PRE, p=w_sign[:D - 3] / w_sign[:D - 3].sum()))
sign_day = np.concatenate([np.sort(pre_days), new_days])
persona = rng.choice(PERSONAS, size=N_CUST, p=PERS_P)
gov_p = gov_df.poids_clients.values / gov_df.poids_clients.sum()
gov_idx = rng.choice(len(gov_df), size=N_CUST, p=gov_p)
gender = rng.choice(["F", "M"], size=N_CUST, p=[0.56, 0.44])
life_days = np.array([rng.exponential(LIFE_M[p] * 30.4) for p in persona])
end_day = (sign_day + life_days).astype(int)
rate = np.array([RATE_M[p] for p in persona]) / 30.4 * np.exp(rng.normal(0, 0.45, N_CUST))
