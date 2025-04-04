import os
import xml.etree.ElementTree as ET

# Use data from https://github.com/rwev/bible

# Define sets for filtering by Bible section.
TORAH = {"GENESIS", "EXODUS", "LEVITICUS", "NUMBERS", "DEUTERONOMY"}
OT_BOOKS = TORAH.union({
    "JOSHUA", "JUDGES", "RUTH", "1 SAMUEL", "2 SAMUEL", "1 KINGS", "2 KINGS",
    "1 CHRONICLES", "2 CHRONICLES", "EZRA", "NEHEMIAH", "ESTHER", "JOB", "PSALMS",
    "PROVERBS", "ECCLESIASTES", "SONG OF SOLOMON", "ISAIAH", "JEREMIAH", "LAMENTATIONS",
    "EZEKIEL", "DANIEL", "HOSEA", "JOEL", "AMOS", "OBADIAH", "JONAH", "MICAH",
    "NAHUM", "HABAKKUK", "ZEPHANIAH", "HAGGAI", "ZECHARIAH", "MALACHI"
})
NT_BOOKS = {
    "MATTHEW", "MARK", "LUKE", "JOHN", "ACTS", "ROMANS", "1 CORINTHIANS",
    "2 CORINTHIANS", "GALATIANS", "EPHESIANS", "PHILIPPIANS", "COLOSSIANS",
    "1 THESSALONIANS", "2 THESSALONIANS", "1 TIMOTHY", "2 TIMOTHY", "TITUS",
    "PHILEMON", "HEBREWS", "JAMES", "1 PETER", "2 PETER", "1 JOHN", "2 JOHN",
    "3 JOHN", "JUDE", "REVELATION"
}

# Mapping of acceptable mode inputs to our standard codes.
ALLOWED_MODES = {
    "OTF": "OTF", "OT": "OTF",                     # Old Testament Forwards (default)
    "OTB": "OTB", "OTBACKWARDS": "OTB",             # Old Testament Backwards
    "NTF": "NTF", "NT": "NTF",                     # New Testament Forwards
    "NTB": "NTB", "NTBACKWARDS": "NTB",             # New Testament Backwards
    "TORAHB": "TORAHB", "TORAHBACKWARDS": "TORAHB", "TB": "TORAHB"  # Torah (first 5 books) Backwards
}

def load_verses(xml_path):
    """
    Parse the XML file and return a list of verses.
    Each verse is a dictionary containing book, chapter, verse number, and text.
    """
    verses = []
    try:
        tree = ET.parse(xml_path)
        root = tree.getroot()
        for book in root.findall('b'):
            book_name = book.attrib.get('n', 'Unknown')
            for chapter in book.findall('c'):
                chapter_num = chapter.attrib.get('n', '0')
                for verse in chapter.findall('v'):
                    verse_num = verse.attrib.get('n', '0')
                    text = verse.text.strip() if verse.text else ""
                    verses.append({
                        'book': book_name,
                        'chapter': chapter_num,
                        'verse': verse_num,
                        'text': text
                    })
    except Exception as e:
        print(f"Error loading {xml_path}: {e}")
    return verses

def load_all_translations(translations_dir):
    """
    Recursively search for all XML files in translations_dir and return a dictionary
    mapping translation name (derived from the file name in upper-case) to its list of verses.
    """
    translations = {}
    for root_dir, dirs, files in os.walk(translations_dir):
        for file in files:
            if file.lower().endswith('.xml'):
                xml_path = os.path.join(root_dir, file)
                translation_name = os.path.splitext(file)[0].upper()
                verses = load_verses(xml_path)
                if verses:
                    translations[translation_name] = verses
                else:
                    print(f"No verses loaded for translation: {translation_name}")
    return translations

def filter_verses(verses, mode):
    """
    Return a filtered list of verses based on the mode:
      - OTF / OTB: verses from the Old Testament.
      - NTF / NTB: verses from the New Testament.
      - TORAHB: verses from the Torah (first 5 books).
    If a backwards mode is selected, the list is reversed.
    """
    mode = mode.upper()
    if mode in ["OTF", "OTB"]:
        filtered = [v for v in verses if v['book'].upper() in OT_BOOKS]
    elif mode in ["NTF", "NTB"]:
        filtered = [v for v in verses if v['book'].upper() in NT_BOOKS]
    elif mode == "TORAHB":
        filtered = [v for v in verses if v['book'].upper() in TORAH]
    else:
        filtered = []  # Should not occur if mode is validated.
    
    # Reverse the order for backwards modes.
    if mode in ["OTB", "NTB", "TORAHB"]:
        filtered = list(reversed(filtered))
    return filtered

def display_verse(translation_name, verse_data, mode):
    """
    Display the verse information.
    """
    print(f"\n[{translation_name} | {mode}] {verse_data['book']} {verse_data['chapter']}:{verse_data['verse']}")
    print(verse_data['text'], "\n")

def print_help():
    help_message = """
Bible Verse Lookup Command Help:
----------------------------------
Enter a command in the following format:
    <verse_number> [translation] [mode]

Where:
  - <verse_number> is the verse number in the filtered list.
  - [translation] is optional. If omitted, defaults to NASB.
       Use 'ALL' to display from all available translations.
  - [mode] is optional. If omitted, defaults to OTF (Old Testament Forwards).
       Allowed modes (not case-sensitive):
         OTF or OT                 : Old Testament Forwards (default)
         OTB or OTBACKWARDS         : Old Testament Backwards
         NTF or NT                 : New Testament Forwards
         NTB or NTBACKWARDS         : New Testament Backwards
         TORAHB or TORAHBACKWARDS or TB : Torah (first 5 books) Backwards

Examples:
    1000             -> Verse 1000 from NASB (default OT forwards)
    1000 KJV         -> Verse 1000 from KJV in OT forwards
    1000 ALL NTB     -> Verse 1000 from all translations in NT backwards
    50 NASB TB       -> Verse 50 from NASB in Torah backwards

Type "help" or "h" to see this message.
----------------------------------
"""
    print(help_message)

def main():
    translations_dir = os.path.expanduser('~/bible/bible/translations/')
    if not os.path.exists(translations_dir):
        print("Directory not found:", translations_dir)
        return

    translations = load_all_translations(translations_dir)
    if not translations:
        print("No translations were loaded.")
        return

    # Set default translation.
    default_translation = "NASB"
    if default_translation not in translations:
        available = ", ".join(translations.keys())
        print(f"Default translation '{default_translation}' not found. Available translations: {available}")
        default_translation = list(translations.keys())[0]
        print(f"Defaulting to {default_translation}.")

    print("Bible Verse Lookup Ready. (Type 'help' or 'h' for instructions.)")

    while True:
        user_input = input("\nEnter command: ").strip()
        if user_input.lower() in ['exit', 'quit']:
            break
        if user_input.lower() in ['help', 'h']:
            print_help()
            continue

        parts = user_input.split()
        if not parts:
            continue

        # Parse verse number.
        try:
            verse_number = int(parts[0])
            if verse_number < 1:
                print("Please enter a verse number of at least 1.")
                continue
        except ValueError:
            print("The first part of the input must be a valid integer (the verse number).")
            continue

        # Initialize defaults.
        translation_choice = default_translation
        mode = "OTF"

        # Process parameters based on number of parts.
        if len(parts) == 1:
            # Only verse number provided; use defaults.
            pass
        elif len(parts) == 2:
            candidate = parts[1].upper()
            # If candidate is a valid translation, use it.
            if candidate in translations:
                translation_choice = candidate
            # Else if candidate is a valid mode, use default translation with that mode.
            elif candidate in ALLOWED_MODES:
                mode = ALLOWED_MODES[candidate]
            else:
                available = ", ".join(translations.keys())
                allowed_modes = ", ".join(ALLOWED_MODES.keys())
                print(f"'{candidate}' not recognized as a translation or mode.")
                print(f"Available translations: {available}")
                print(f"Allowed modes: {allowed_modes}")
                continue
        else:
            # At least 3 parts provided.
            candidate = parts[1].upper()
            mode_candidate = parts[2].upper()
            # First check: if candidate is not a known translation,
            # see if it's actually a mode.
            if candidate not in translations:
                if candidate in ALLOWED_MODES:
                    mode = ALLOWED_MODES[candidate]
                    translation_choice = default_translation
                else:
                    available = ", ".join(translations.keys())
                    print(f"Translation '{candidate}' not found. Available translations: {available}")
                    continue
            else:
                translation_choice = candidate
            # Now process the mode_candidate.
            if mode_candidate in ALLOWED_MODES:
                mode = ALLOWED_MODES[mode_candidate]
            else:
                allowed_modes = ", ".join(ALLOWED_MODES.keys())
                print(f"Unrecognized mode '{mode_candidate}'. Allowed modes: {allowed_modes}")
                continue

        # Function to process a single translation.
        def process_translation(trans_name):
            verses = translations[trans_name]
            filtered = filter_verses(verses, mode)
            total = len(filtered)
            if total == 0:
                print(f"[{trans_name}] No verses found for the selected mode ({mode}).")
                return
            if verse_number > total:
                print(f"[{trans_name}] Verse number {verse_number} is out of range (1 - {total}).")
                return
            verse_data = filtered[verse_number - 1]  # Convert 1-based index to 0-based.
            display_verse(trans_name, verse_data, mode)

        # Process ALL translations if selected.
        if translation_choice == "ALL":
            for trans_name in sorted(translations.keys()):
                process_translation(trans_name)
        else:
            if translation_choice not in translations:
                available = ", ".join(translations.keys())
                print(f"Translation '{translation_choice}' not found. Available translations: {available}")
                continue
            process_translation(translation_choice)

if __name__ == '__main__':
    main()
