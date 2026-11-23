"""Recherche multimodale Qdrant et fusion Reciprocal Rank Fusion (RRF)."""

from __future__ import annotations

import os
import sys
from functools import lru_cache
from pathlib import Path
from typing import Any, Mapping, Sequence

import requests
from dotenv import load_dotenv
from qdrant_client import QdrantClient
from sentence_transformers import SentenceTransformer


BACKEND_DIR = Path(__file__).resolve().parents[1]
if str(BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(BACKEND_DIR))

from ingestion.embeddings import MODELE_IMAGES, embedding_texte  # noqa: E402
from ingestion.vectordb import IMAGE_COLLECTION, TEXT_COLLECTION  # noqa: E402


load_dotenv(BACKEND_DIR / ".env")

TOP_K = 5
RRF_K = 60
IMAGE_MIN_SCORE_DEFAULT = 0.25  # À calibrer selon les scores CLIP observés.
GROQ_URL = "https://api.groq.com/openai/v1/chat/completions"
SYSTEM_PROMPT = (
    "Tu es l'assistant officiel de l'EMSI. "
    "Réponds de façon claire et concise, dans la langue de la question "
    "(français par défaut). "
    "Appuie-toi d'abord sur le contexte fourni et nomme la source quand "
    "c'est utile. "
    "Si l'information demandée sur l'EMSI ne figure pas dans le contexte, "
    "ne l'invente jamais : dis qu'elle ne figure pas dans tes documents, "
    "puis, si tu peux aider, donne une réponse générale introduite par "
    "« Information générale (hors documents EMSI) : », sans aucun chiffre, "
    "date, prix, nom ni contact propre à l'EMSI. "
    "Propose alors de contacter l'administration pour confirmer."
)


def _creer_client() -> QdrantClient:
    return QdrantClient(url=os.getenv("QDRANT_URL", "http://localhost:6333"))


@lru_cache(maxsize=1)
def _modele_clip() -> SentenceTransformer:
    """Charge le modèle CLIP une seule fois pour les requêtes texte-image."""

    return SentenceTransformer(MODELE_IMAGES)


def _embedding_question_clip(question: str) -> list[float]:
    """Encode une question texte dans l'espace vectoriel CLIP de dimension 512."""

    vecteurs = _modele_clip().encode(
        [question],
        normalize_embeddings=True,
        convert_to_numpy=True,
        show_progress_bar=False,
    )
    return vecteurs[0].tolist()


def _interroger_qdrant(
    client: QdrantClient,
    collection: str,
    vecteur: Sequence[float],
    top_k: int = TOP_K,
) -> list[Any]:
    """Interroge Qdrant avec l'API récente, avec fallback API historique."""

    if hasattr(client, "query_points"):
        try:
            reponse = client.query_points(
                collection_name=collection,
                query=list(vecteur),
                limit=top_k,
                with_payload=True,
            )
            return list(reponse.points)
        except TypeError:
            # Compatibilité avec des versions où la signature diffère.
            pass

    return list(
        client.search(
            collection_name=collection,
            query_vector=list(vecteur),
            limit=top_k,
            with_payload=True,
        )
    )


def _normaliser_resultat(
    point: Any,
    *,
    collection: str,
    type_attendu: str,
    rang: int,
) -> dict[str, Any]:
    payload = dict(point.payload or {})
    contenu = str(payload.get("contenu", ""))
    type_resultat = str(payload.get("type", type_attendu))
    source = str(payload.get("source", "source inconnue"))
    page = payload.get("page", "?")
    point_id = str(point.id)
    chunk_id = str(payload.get("chunk_id", point_id))

    return {
        "id": point_id,
        "collection": collection,
        "score": 0.0,
        "qdrant_score": float(point.score),
        "rang": rang,
        "source": source,
        "page": page,
        "type": type_resultat,
        "chunk_id": chunk_id,
        "reference": f"{source}, page {page}",
        "contenu": contenu,
        "texte": contenu if type_resultat == "text" else "",
        "chemin_image": contenu if type_resultat == "image" else "",
    }


def fusionner_rrf(
    resultats_textes: Sequence[Mapping[str, Any]],
    resultats_images: Sequence[Mapping[str, Any]],
    k: int = RRF_K,
) -> list[dict[str, Any]]:
    """Fusionne deux classements avec Reciprocal Rank Fusion."""

    if k <= 0:
        raise ValueError("La constante k de RRF doit être strictement positive.")

    fusion: dict[tuple[str, str], dict[str, Any]] = {}
    for resultats in (resultats_textes, resultats_images):
        for resultat in resultats:
            cle = (str(resultat["collection"]), str(resultat["id"]))
            if cle not in fusion:
                fusion[cle] = dict(resultat)
            fusion[cle]["score"] += 1 / (k + int(resultat["rang"]))

    return sorted(
        fusion.values(),
        key=lambda resultat: (-float(resultat["score"]), int(resultat["rang"])),
    )


def rechercher_contexte(
    question: str,
    client: QdrantClient | None = None,
) -> list[dict[str, Any]]:
    """Recherche les meilleurs contextes texte et image, puis les fusionne."""

    question = question.strip()
    if not question:
        raise ValueError("La question ne peut pas être vide.")

    client = client or _creer_client()

    # (2) La question utilisateur est encodée dans les deux espaces utiles.
    vecteur_texte = embedding_texte([question])[0]
    vecteur_image = _embedding_question_clip(question)

    # (3) Recherche top 5 dans les deux collections Qdrant.
    points_textes = _interroger_qdrant(
        client,
        TEXT_COLLECTION,
        vecteur_texte,
        top_k=TOP_K,
    )
    points_images = _interroger_qdrant(
        client,
        IMAGE_COLLECTION,
        vecteur_image,
        top_k=TOP_K,
    )

    # (4) Récupération du contexte puis fusion des deux classements.
    resultats_textes = [
        _normaliser_resultat(
            point,
            collection=TEXT_COLLECTION,
            type_attendu="text",
            rang=rang,
        )
        for rang, point in enumerate(points_textes, start=1)
    ]
    resultats_images = [
        _normaliser_resultat(
            point,
            collection=IMAGE_COLLECTION,
            type_attendu="image",
            rang=rang,
        )
        for rang, point in enumerate(points_images, start=1)
    ]
    return fusionner_rrf(resultats_textes, resultats_images, k=RRF_K)


def construire_prompt_final(
    question: str,
    contexte: Sequence[Mapping[str, Any]],
) -> str:
    """Construit le prompt (5) avec uniquement le contexte textuel."""

    return (
        f"SYSTEM PROMPT:\n{SYSTEM_PROMPT}\n\n"
        f"{_construire_contexte_et_question(question, contexte)}"
    )


def _construire_contexte_et_question(
    question: str,
    contexte: Sequence[Mapping[str, Any]],
) -> str:
    """Construit la partie contexte et question commune aux fournisseurs."""

    blocs_texte = []
    for resultat in contexte:
        if resultat.get("type") != "text":
            continue
        texte = str(resultat.get("texte") or resultat.get("contenu") or "").strip()
        if not texte:
            continue
        blocs_texte.append(
            f"[Source : {resultat.get('source', 'inconnue')} | "
            f"Page : {resultat.get('page', '?')}]\n{texte}"
        )

    contexte_textuel = "\n\n".join(blocs_texte)
    if not contexte_textuel:
        contexte_textuel = "Aucun contexte textuel pertinent n'a été trouvé."

    return (
        f"CONTEXTE:\n{contexte_textuel}\n\n"
        f"QUESTION:\n{question.strip()}"
    )


def appeler_groq(messages: Sequence[Mapping[str, str]]) -> str:
    """Appelle Groq avec des messages système et utilisateur."""

    api_key = os.getenv("GROQ_API_KEY", "").strip()
    if not api_key:
        raise RuntimeError("GROQ_API_KEY est absente.")

    response = requests.post(
        GROQ_URL,
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
        },
        json={
            "model": os.getenv("GROQ_MODEL", "llama-3.3-70b-versatile"),
            "messages": [dict(message) for message in messages],
            "temperature": 0.2,
        },
        timeout=60,
    )
    response.raise_for_status()
    payload = response.json()
    choices = payload.get("choices") or []
    if not choices:
        raise RuntimeError("Groq n'a renvoyé aucun choix.")

    message = choices[0].get("message") or {}
    answer = message.get("content")
    if not isinstance(answer, str) or not answer.strip():
        raise RuntimeError("Groq a renvoyé une réponse vide.")
    return answer.strip()


CLAUDE_URL = "https://api.anthropic.com/v1/messages"


def appeler_claude(messages: Sequence[Mapping[str, str]]) -> str:
    """Appelle l'API Claude (Anthropic) avec les mêmes messages que Groq.

    Le message "system" est passé dans le champ dédié ``system`` de l'API
    Messages ; les autres messages restent dans ``messages``.
    """

    api_key = os.getenv("ANTHROPIC_API_KEY", "").strip()
    if not api_key:
        raise RuntimeError("ANTHROPIC_API_KEY est absente.")

    systeme = "\n\n".join(
        m["content"] for m in messages if m.get("role") == "system"
    )
    echanges = [dict(m) for m in messages if m.get("role") != "system"]

    response = requests.post(
        CLAUDE_URL,
        headers={
            "x-api-key": api_key,
            "anthropic-version": "2023-06-01",
            "content-type": "application/json",
        },
        json={
            "model": os.getenv("CLAUDE_MODEL", "claude-haiku-5-5"),
            "max_tokens": 1024,
            "system": systeme,
            "messages": echanges,
        },
        timeout=60,
    )
    response.raise_for_status()
    blocs = response.json().get("content") or []
    answer = "".join(b.get("text", "") for b in blocs if b.get("type") == "text")
    if not answer.strip():
        raise RuntimeError("Claude a renvoyé une réponse vide.")
    return answer.strip()


def appeler_llm(messages: Sequence[Mapping[str, str]]) -> str:
    """Choisit le fournisseur LLM selon LLM_PROVIDER (groq par défaut)."""

    if os.getenv("LLM_PROVIDER", "groq").strip().lower() == "claude":
        return appeler_claude(messages)
    return appeler_groq(messages)


def _url_image_relative(chemin: str) -> str:
    """Convertit un chemin local d'image en URL servie par FastAPI."""

    return f"/images/{Path(chemin).name}"


def _image_min_score() -> float:
    try:
        return float(
            os.getenv("IMAGE_MIN_SCORE", str(IMAGE_MIN_SCORE_DEFAULT))
        )
    except ValueError:
        return IMAGE_MIN_SCORE_DEFAULT


def _reponse_erreur(message: str) -> dict[str, Any]:
    return {"answer": message, "sources": [], "images": []}


def repondre(question: str) -> dict[str, Any]:
    """Exécute (7) la recherche, la génération Groq et le format de réponse."""

    question = question.strip()
    if not question:
        return _reponse_erreur("Veuillez fournir une question.")

    try:
        contexte = rechercher_contexte(question)
    except Exception:
        return _reponse_erreur(
            "Le service de recherche Qdrant est indisponible. "
            "Vérifiez que Qdrant est lancé et que les collections existent."
        )

    sources = [
        {
            "source": str(resultat.get("source", "source inconnue")),
            "page": resultat.get("page", "?"),
            "type": str(resultat.get("type", "text")),
            "score": float(resultat.get("score", 0.0)),
        }
        for resultat in contexte
    ]
    images = []
    image_min_score = _image_min_score()
    for resultat in contexte:
        if resultat.get("type") != "image":
            continue
        if float(resultat.get("qdrant_score", 0.0)) < image_min_score:
            continue
        chemin = str(resultat.get("chemin_image") or resultat.get("contenu") or "")
        if chemin and len(images) < 2:
            images.append(_url_image_relative(chemin))

    messages = [
        {"role": "system", "content": SYSTEM_PROMPT},
        {
            "role": "user",
            "content": _construire_contexte_et_question(question, contexte),
        },
    ]
    try:
        answer = appeler_llm(messages)
    except Exception as exc:
        message_erreur = str(exc)
        # Masque toute clé API avant d'écrire l'erreur dans les logs.
        for nom_cle in ("GROQ_API_KEY", "ANTHROPIC_API_KEY"):
            api_key = os.getenv(nom_cle, "").strip()
            if api_key:
                message_erreur = message_erreur.replace(api_key, "[clé masquée]")
        print(
            f"Erreur LLM ({type(exc).__name__}) : {message_erreur}",
            file=sys.stderr,
        )
        return _reponse_erreur(
            "Le service Groq est indisponible ou sa limite d'utilisation "
            "a été atteinte. Vérifiez GROQ_API_KEY et réessayez."
        )

    return {"answer": answer, "sources": sources, "images": images}


if __name__ == "__main__":
    question_utilisateur = input("Question : ").strip()
    try:
        resultats = rechercher_contexte(question_utilisateur)
    except Exception as exc:
        print(f"Erreur pendant la recherche : {exc}")
        raise SystemExit(1) from exc

    if not resultats:
        print("Aucun résultat trouvé.")
        raise SystemExit(0)

    print("\nMeilleurs résultats :")
    for index, resultat in enumerate(resultats, start=1):
        print(
            f"\n{index}. score={resultat['score']:.6f} | "
            f"{resultat['reference']} | type={resultat['type']}"
        )
        if resultat["type"] == "image":
            print(f"   image : {resultat['chemin_image']}")
        else:
            extrait = resultat["texte"].replace("\n", " ").strip()
            if len(extrait) > 300:
                extrait = f"{extrait[:300]}..."
            print(f"   texte : {extrait}")
