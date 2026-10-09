#!/usr/bin/env python3
"""Cross-check BuiltInLibrary.json against an independent reference: the scale and chord
dictionaries of tonal (https://github.com/tonaljs/tonal, MIT licence).

    python3 -I SpotCore/Scripts/check_library.py

Downloads the pinned tonal packages to a cache folder on first run. The downloaded JavaScript
is only read as text, never executed.

Reports:
  ERROR     a Spot entry and a tonal entry share a name or symbol but not the same notes
  SPELLING  same notes, but the degrees are spelled differently (e.g. #5 vs b6)
  UNMATCHED a Spot entry with no tonal entry of the same name; tonal entries with the same notes are listed
  MISSING   (with --missing) tonal entries whose notes match nothing in Spot

Exits with status 1 if there are errors.
"""

import json
import os
import re
import sys
import tempfile
import urllib.request

TONAL_FILES = {
    "scales": "https://unpkg.com/@tonaljs/scale-type@4.9.3/dist/index.mjs",
    "chords": "https://unpkg.com/@tonaljs/chord-type@5.2.0/dist/index.mjs",
}
LIBRARY = os.path.join(os.path.dirname(__file__), "..", "Sources", "SpotCore", "Resources", "BuiltInLibrary.json")
CACHE = os.path.join(tempfile.gettempdir(), "spot-tonal-reference")

MAJOR_SEMITONES = [0, 2, 4, 5, 7, 9, 11]


def degree_semitones(number, accidental):
    return MAJOR_SEMITONES[(number - 1) % 7] + 12 * ((number - 1) // 7) + accidental


def parse_spot_degree(text):
    accidental = -text.count("b") + text.count("#")
    return int(text.strip("b#")), accidental


def parse_tonal_interval(text):
    """'3m' -> (3, -1), '5d' -> (5, -1), '7d' -> (7, -2), '11A' -> (11, 1)."""
    match = re.fullmatch(r"(-?\d+)([PMmdA]+)", text)
    number, quality = int(match.group(1)), match.group(2)
    perfect = (number - 1) % 7 + 1 in (1, 4, 5)
    if quality in ("P", "M"):
        accidental = 0
    elif quality == "m":
        accidental = -1
    elif quality[0] == "d":
        accidental = -len(quality) if perfect else -len(quality) - 1
    else:
        accidental = len(quality)
    return number, accidental


# Entries where Spot deliberately differs from tonal
KNOWN_DIFFERENCES = {
    "builtin.chord.dominant-7-flat-5-sharp-9": "tonal reads b5 as a #11 added to a natural 5th; Spot replaces the 5th",
    "builtin.chord.dominant-7-flat-5-flat-9": "tonal reads b5 as a #11 added to a natural 5th; Spot replaces the 5th",
}


def normalise_symbol(symbol):
    """Chord symbols are case-sensitive (M7 vs m7) and '-' means minor, so only unify accidentals."""
    return symbol.replace("♭", "b").replace("♯", "#").replace("𝄫", "bb").replace("♮", "")


def normalise_name(name):
    return re.sub(r"[\s\-_/()]", "", normalise_symbol(name).lower())


def fetch(kind):
    os.makedirs(CACHE, exist_ok=True)
    path = os.path.join(CACHE, kind + ".mjs")
    if not os.path.exists(path):
        with urllib.request.urlopen(TONAL_FILES[kind], timeout=60) as response:
            data = response.read()
        with open(path, "wb") as file:
            file.write(data)
    with open(path, encoding="utf-8") as file:
        return file.read()


def tonal_entries(kind):
    """Each entry: (degrees, names). Arrays look like ["1P 3M 5P", "major", "M ^ maj"]."""
    entries = []
    for array in re.findall(r'\[\s*("1P[^\]]*)\]', fetch(kind)):
        strings = re.findall(r'"([^"]*)"', array)
        degrees = [parse_tonal_interval(i) for i in strings[0].split()]
        if kind == "scales":
            names, symbols = strings[1:], []
        else:
            names = [strings[1]] if strings[1] else []
            symbols = strings[2].split() if len(strings) > 2 else []
        entries.append((degrees, names, symbols))
    return entries


def pitch_classes(degrees):
    return frozenset(degree_semitones(n, a) % 12 for n, a in degrees)


def check(kind, spot_items, show_missing):
    errors = 0
    tonal = tonal_entries(kind)
    by_key = {}
    for degrees, names, symbols in tonal:
        label = (names or symbols or ["?"])[0]
        for name in names:
            by_key.setdefault(("name", normalise_name(name)), (degrees, label))
        for symbol in symbols:
            by_key.setdefault(("symbol", normalise_symbol(symbol)), (degrees, label))

    matched_tonal_sets = set()
    checked = 0
    for item in spot_items:
        degrees = [parse_spot_degree(d) for d in item["formula"].split()]
        optional = {parse_spot_degree(d) for d in item.get("optional", [])}
        notes = pitch_classes(degrees)
        required = pitch_classes([d for d in degrees if d not in optional])

        keys = [("name", normalise_name(n)) for n in [item["name"]] + item.get("aliases", [])]
        keys += [("symbol", normalise_symbol(s)) for s in item.get("symbols", []) if s]
        match = next((by_key[k] for k in keys if k in by_key), None)

        if match is None:
            same_notes = [(names or symbols)[0] for d, names, symbols in tonal if pitch_classes(d) == notes]
            hint = f" (tonal has the same notes as: {', '.join(same_notes)})" if same_notes else ""
            print(f"UNMATCHED {item['id']}{hint}")
            if same_notes:
                matched_tonal_sets.add(notes)
            continue

        tonal_degrees, label = match
        checked += 1
        tonal_notes = pitch_classes(tonal_degrees)
        matched_tonal_sets.add(tonal_notes)

        # Optional degrees may be left out by the reference (e.g. the 11th of a 13th chord)
        if not (required <= tonal_notes <= notes):
            if item["id"] in KNOWN_DIFFERENCES:
                print(f"KNOWN     {item['id']}: {KNOWN_DIFFERENCES[item['id']]}")
            else:
                errors += 1
                print(f"ERROR     {item['id']}: Spot {item['formula']} vs tonal '{label}' {format_degrees(tonal_degrees)}")
            continue

        spot_spelling = {degree_semitones(n, a) % 12: (n - 1) % 7 for n, a in degrees}
        tonal_spelling = {degree_semitones(n, a) % 12: (n - 1) % 7 for n, a in tonal_degrees}
        differences = [pc for pc in tonal_spelling if pc in spot_spelling and spot_spelling[pc] != tonal_spelling[pc]]
        if differences:
            print(f"SPELLING  {item['id']}: Spot {item['formula']} vs tonal '{label}' {format_degrees(tonal_degrees)}")

    print(f"-- {kind}: {checked} of {len(spot_items)} checked against tonal\n")

    if show_missing:
        spot_sets = {pitch_classes([parse_spot_degree(d) for d in i["formula"].split()]) for i in spot_items}
        for degrees, names, symbols in tonal:
            if pitch_classes(degrees) not in spot_sets | matched_tonal_sets:
                print(f"MISSING   {kind[:-1]} '{(names or symbols or ['?'])[0]}' {format_degrees(degrees)}")

    return errors


def format_degrees(degrees):
    return " ".join(("b" * -a if a < 0 else "#" * a) + str(n) for n, a in degrees)


def main():
    with open(LIBRARY, encoding="utf-8") as file:
        library = json.load(file)

    show_missing = "--missing" in sys.argv
    errors = check("scales", library["scales"], show_missing) + check("chords", library["chords"], show_missing)
    print(f"\n{errors} error(s)")
    sys.exit(1 if errors else 0)


if __name__ == "__main__":
    main()
