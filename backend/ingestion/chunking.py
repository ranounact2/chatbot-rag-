"""Découpage des structures textuelles en chunks pour la recherche vectorielle."""

from __future__ import annotations

import re
from collections import defaultdict
from typing import Any, Iterable, Mapping


TAILLE_CHUNK_PAR_DEFAUT = 500
CHEVAUCHEMENT_PAR_DEFAUT = 100


def _slugifier_source(source: str) -> str:
    stem = source.rsplit("/", maxsplit=1)[-1].rsplit("\\", maxsplit=1)[-1]
    stem = stem.rsplit(".", maxsplit=1)[0]
    slug = re.sub(r"[^A-Za-z0-9_-]+", "_", stem).strip("_")
    return slug or "document"


def _decouper(texte: str, taille: int, chevauchement: int) -> Iterable[str]:
    if taille <= 0:
        raise ValueError("La taille d'un chunk doit être positive.")
    if chevauchement < 0 or chevauchement >= taille:
        raise ValueError("Le chevauchement doit être compris entre 0 et taille-1.")

    debut = 0
    while debut < len(texte):
        fin = min(debut + taille, len(texte))
        if fin < len(texte):
            fin = _fin_propre(texte, debut, fin)
        morceau = texte[debut:fin].strip()
        if morceau:
            yield morceau
        if fin == len(texte):
            break
        # Le chunk suivant reprend `chevauchement` caractères avant la
        # coupure, mais commence toujours au début d'un mot.
        prochain = max(fin - chevauchement, debut + 1)
        candidat = prochain
        # Recherche bornée à `fin` : sans espace, on garde la coupure brute
        # plutôt que de sauter le reste du texte.
        while candidat < fin and not texte[candidat - 1].isspace():
            candidat += 1
        if candidat < fin:
            prochain = candidat
        debut = prochain


def _fin_propre(texte: str, debut: int, fin: int) -> int:
    """Recule `fin` jusqu'à une coupure naturelle (ligne, phrase, mot).

    On ne recule que dans la seconde moitié de la fenêtre, pour que les
    chunks gardent une taille proche de la cible. Sans coupure trouvée, la
    coupure brute est conservée.
    """

    plancher = debut + (fin - debut) // 2
    for separateur in ("\n", ". ", " "):
        position = texte.rfind(separateur, plancher, fin)
        if position != -1:
            return position + len(separateur)
    return fin


def chunker_textes(
    structures: Iterable[Mapping[str, Any]],
    taille: int = TAILLE_CHUNK_PAR_DEFAUT,
    chevauchement: int = CHEVAUCHEMENT_PAR_DEFAUT,
) -> list[dict[str, Any]]:
    """Découpe les textes en chunks en conservant source et page."""

    compteurs: defaultdict[str, int] = defaultdict(int)
    chunks: list[dict[str, Any]] = []

    for structure in structures:
        contenu = str(structure.get("contenu", "")).strip()
        source = str(structure.get("source", "document"))
        page = int(structure.get("page", 1))
        if not contenu:
            continue

        for morceau in _decouper(contenu, taille, chevauchement):
            compteurs[source] += 1
            chunk_id = (
                f"{_slugifier_source(source)}_p{page}_"
                f"c{compteurs[source]:04d}"
            )
            chunks.append(
                {
                    "source": source,
                    "page": page,
                    "contenu": morceau,
                    "chunk_id": chunk_id,
                    "type": "text",
                }
            )

    return chunks
