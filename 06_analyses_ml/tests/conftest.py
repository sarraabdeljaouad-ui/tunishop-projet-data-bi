# -*- coding: utf-8 -*-
"""Configuration commune des tests : le module tunishop_analytics est dans 00_Commun.

Lancement (depuis le dossier TuniShop_Etape7_Analyse) :  python -m pytest -q tests
Les tests n'utilisent NI SQL Server NI les fichiers du projet : ils travaillent sur de petites
données fabriquées et sur des bases SQLite temporaires. Ils durent quelques secondes.
"""
import os
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "00_Commun"))


@pytest.fixture
def base_test(tmp_path, monkeypatch):
    """Base de publication temporaire (SQLite) : rien n'est écrit dans TuniShop_ANALYTICS."""
    from tunishop_analytics import config, publication
    monkeypatch.setenv("TUNISHOP_BASE_TEST", str(tmp_path / "bi_test.sqlite"))
    monkeypatch.setenv("TUNISHOP_PUBLIER_SQL", "1")
    monkeypatch.setattr(config, "DOSSIER_METADATA", tmp_path / "metadata")
    publication.fermer_connexion()
    publication._connexion = None
    yield publication
    publication.fermer_connexion()
    publication._connexion = None
