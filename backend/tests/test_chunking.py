"""Tests du découpage en chunks : taille, recouvrement et coupures propres."""

import unittest

from ingestion.chunking import chunker_textes


def _chunks(texte: str, taille: int = 120, chevauchement: int = 30):
    structures = [{"source": "t.txt", "page": 1, "contenu": texte}]
    return [c["contenu"] for c in chunker_textes(structures, taille, chevauchement)]


class TestChunking(unittest.TestCase):
    TEXTE = (
        "EMSI est une ecole d'ingenieurs privee au Maroc. "
        "Les candidats deposent leur dossier en ligne. "
        "Le concours d'entree est ouvert apres les classes preparatoires. "
        "Les frais de scolarite varient selon la filiere et le campus. "
        "Les etudiants realisent un stage technique en troisieme annee."
    )

    def test_aucun_chunk_ne_commence_ni_ne_finit_au_milieu_d_un_mot(self):
        mots = set(self.TEXTE.replace(".", " ").replace("'", " ").split())
        for chunk in _chunks(self.TEXTE):
            premier = chunk.split()[0].strip(".")
            dernier = chunk.split()[-1].strip(".")
            self.assertIn(premier.split("'")[-1], mots | {premier}, chunk)
            self.assertIn(dernier, mots, chunk)

    def test_tout_le_texte_est_couvert(self):
        chunks = _chunks(self.TEXTE)
        for mot in self.TEXTE.split():
            self.assertTrue(any(mot in c for c in chunks), mot)

    def test_la_taille_reste_proche_de_la_cible(self):
        for chunk in _chunks(self.TEXTE):
            self.assertLessEqual(len(chunk), 120)

    def test_texte_court_donne_un_seul_chunk(self):
        self.assertEqual(_chunks("Bonjour."), ["Bonjour."])

    def test_texte_sans_espace_progresse_sans_boucle_infinie(self):
        chunks = _chunks("a" * 500)
        self.assertGreater(len(chunks), 1)

    def test_parametres_invalides(self):
        with self.assertRaises(ValueError):
            _chunks("texte", taille=0)
        with self.assertRaises(ValueError):
            _chunks("texte", taille=10, chevauchement=10)


if __name__ == "__main__":
    unittest.main()
