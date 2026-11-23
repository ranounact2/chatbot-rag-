"""Tests du choix du fournisseur LLM (Groq ou Claude) sans appel réseau."""

import os
import unittest
from unittest import mock

from api import rag


class _Reponse:
    def __init__(self, payload):
        self._payload = payload

    def raise_for_status(self):
        pass

    def json(self):
        return self._payload


MESSAGES = [
    {"role": "system", "content": "REGLES"},
    {"role": "user", "content": "QUESTION"},
]


class TestFournisseurLLM(unittest.TestCase):
    def test_claude_separe_le_message_systeme(self):
        payload = {"content": [{"type": "text", "text": " Bonjour "}]}
        env = {"ANTHROPIC_API_KEY": "cle-de-test", "LLM_PROVIDER": "claude"}
        with mock.patch.dict(os.environ, env), mock.patch.object(
            rag.requests, "post", return_value=_Reponse(payload)
        ) as post:
            self.assertEqual(rag.appeler_llm(MESSAGES), "Bonjour")
        corps = post.call_args.kwargs["json"]
        self.assertEqual(corps["system"], "REGLES")
        self.assertEqual(corps["messages"], [MESSAGES[1]])
        self.assertNotIn("temperature", corps)  # refusé par les modèles récents
        self.assertEqual(post.call_args.kwargs["headers"]["x-api-key"], "cle-de-test")

    def test_claude_sans_cle_leve_une_erreur(self):
        with mock.patch.dict(os.environ, {"ANTHROPIC_API_KEY": ""}):
            with self.assertRaises(RuntimeError):
                rag.appeler_claude(MESSAGES)

    def test_claude_reponse_vide_leve_une_erreur(self):
        env = {"ANTHROPIC_API_KEY": "cle-de-test"}
        with mock.patch.dict(os.environ, env), mock.patch.object(
            rag.requests, "post", return_value=_Reponse({"content": []})
        ):
            with self.assertRaises(RuntimeError):
                rag.appeler_claude(MESSAGES)

    def test_groq_reste_le_fournisseur_par_defaut(self):
        with mock.patch.dict(os.environ, {"LLM_PROVIDER": ""}), mock.patch.object(
            rag, "appeler_groq", return_value="g"
        ) as groq, mock.patch.object(rag, "appeler_claude") as claude:
            self.assertEqual(rag.appeler_llm(MESSAGES), "g")
        groq.assert_called_once()
        claude.assert_not_called()


if __name__ == "__main__":
    unittest.main()


class TestPromptSysteme(unittest.TestCase):
    def test_prompt_interdit_d_inventer_et_etiquette_le_general(self):
        # Le libellé est utilisé par les tests de bout en bout : s'il change,
        # il faut mettre à jour le jeu d'évaluation.
        self.assertIn("ne l'invente jamais", rag.SYSTEM_PROMPT)
        self.assertIn("Information générale (hors documents EMSI)", rag.SYSTEM_PROMPT)
