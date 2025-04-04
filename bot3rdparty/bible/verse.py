import os
import xml.etree.ElementTree as ET

# Use data from https://github.com/rwev/bible

def generate_book_abbrevs(nasb_xml_path):
    """
    Parse the NASB.xml file to extract canonical book names and
    generate a mapping from every unique normalized prefix (no spaces, uppercased)
    to its canonical book name.
    """
    try:
        tree = ET.parse(nasb_xml_path)
        root = tree.getroot()
    except Exception as e:
        print(f"Error loading NASB.xml for book abbreviations: {e}")
        return {}
    
    # Extract book names from <b n="..."> tags.
    book_names = []
    for book in root.findall('b'):
        book_name = book.attrib.get('n', '').strip()
        if book_name:
            book_names.append(book_name)
    
    # Build a mapping: for each book, generate every prefix from its normalized name.
    # Normalization: remove spaces and uppercase.
    prefix_map = {}  # prefix -> set of canonical book names
    for book in book_names:
        normalized = ''.join(book.upper().split())
        for i in range(1, len(normalized) + 1):
            prefix = normalized[:i]
            if prefix in prefix_map:
                prefix_map[prefix].add(book)
            else:
                prefix_map[prefix] = {book}
    
    # Only keep prefixes that uniquely identify a book.
    book_abbrevs = {}
    for prefix, books_set in prefix_map.items():
        if len(books_set) == 1:
            book_abbrevs[prefix] = list(books_set)[0]
    return book_abbrevs

def load_translation(xml_path):
    """
    Parse the XML file and return a list of verses.
    Each verse is stored as a dictionary with keys: 'book', 'chapter', 'verse', and 'text'.
    """
    verses = []
    try:
        tree = ET.parse(xml_path)
        root = tree.getroot()
        for book in root.findall('b'):
            book_name = book.attrib.get('n', '').strip()
            for chapter in book.findall('c'):
                chapter_num = chapter.attrib.get('n', '').strip()
                for verse in chapter.findall('v'):
                    verse_num = verse.attrib.get('n', '').strip()
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
    Recursively load all XML Bible translations from translations_dir.
    Returns a dictionary mapping translation code (upper-case) to its list of verses.
    """
    translations = {}
    for root_dir, dirs, files in os.walk(translations_dir):
        for file in files:
            if file.lower().endswith('.xml'):
                xml_path = os.path.join(root_dir, file)
                translation_name = os.path.splitext(file)[0].upper()
                verses = load_translation(xml_path)
                if verses:
                    translations[translation_name] = verses
                else:
                    print(f"No verses loaded for translation: {translation_name}")
    return translations

def lookup_verse(verses, canonical_book, chapter, verse_number):
    """
    Look up a verse in the given verses list that matches the canonical book name,
    chapter, and verse number. Returns the verse dictionary if found.
    """
    for v in verses:
        if (v['book'].strip().upper() == canonical_book.upper() and 
            v['chapter'].strip() == str(chapter) and 
            v['verse'].strip() == str(verse_number)):
            return v
    return None

def main():
    translations_dir = os.path.expanduser('~/bible/bible/translations/')
    nasb_path = os.path.join(translations_dir, "NASB.xml")
    if not os.path.exists(nasb_path):
        print("NASB.xml not found in", translations_dir)
        return

    # Generate dynamic book abbreviation mapping from the NASB file.
    book_abbrevs = generate_book_abbrevs(nasb_path)
    if not book_abbrevs:
        print("No book abbreviations generated.")
        return

    # Load all available translations.
    translations = load_all_translations(translations_dir)
    if not translations:
        print("No translations loaded.")
        return

    default_translation = "NASB"
    if default_translation not in translations:
        default_translation = list(translations.keys())[0]

    print("Bible Verse Lookup Ready.")
    print("Input format: <book> <chapter:verse> [translation]")
    print("Example: 1 j 1:1 kjv")
    print("You can enter the book name with or without spaces (e.g. '1 j', '1john', '1 john').")

    while True:
        user_input = input("\nEnter command (or type 'exit' to quit): ").strip()
        if user_input.lower() in ['exit', 'quit']:
            break
        if not user_input:
            continue

        # Split input into tokens.
        tokens = user_input.split()
        # Find the token that contains a colon (chapter:verse indicator).
        chapter_verse_idx = None
        for i, token in enumerate(tokens):
            if ':' in token:
                chapter_verse_idx = i
                break
        if chapter_verse_idx is None:
            print("Input must include chapter:verse in format 'chapter:verse' (e.g., 1:1).")
            continue

        # The book abbreviation is all tokens before the chapter:verse token.
        book_input = ' '.join(tokens[:chapter_verse_idx])
        normalized_book_input = ''.join(book_input.upper().split())
        canonical_book = None
        if normalized_book_input in book_abbrevs:
            canonical_book = book_abbrevs[normalized_book_input]
        else:
            # Try matching any key that starts with the normalized input.
            possibles = [v for k, v in book_abbrevs.items() if k.startswith(normalized_book_input)]
            possibles = list(set(possibles))
            if len(possibles) == 1:
                canonical_book = possibles[0]
        if not canonical_book:
            print(f"Book abbreviation '{book_input}' not recognized.")
            continue

        # The chapter:verse token.
        chapter_verse = tokens[chapter_verse_idx]
        if ':' not in chapter_verse:
            print("Chapter and verse must be in the format chapter:verse (e.g., 1:1).")
            continue
        try:
            chapter_str, verse_str = chapter_verse.split(":", 1)
            chapter = int(chapter_str)
            verse_number = int(verse_str)
        except Exception as e:
            print("Error parsing chapter and verse. Please use the format chapter:verse (e.g., 1:1).")
            continue

        # Optional translation: if there is a token after chapter:verse.
        if len(tokens) > chapter_verse_idx + 1:
            translation_choice = tokens[chapter_verse_idx + 1].upper()
        else:
            translation_choice = default_translation

        if translation_choice not in translations:
            available = ", ".join(translations.keys())
            print(f"Translation '{translation_choice}' not found. Available translations: {available}")
            continue

        verses = translations[translation_choice]
        result = lookup_verse(verses, canonical_book, chapter, verse_number)
        if result:
            print(f"\n[{translation_choice}] {result['book']} {result['chapter']}:{result['verse']}")
            print(result['text'], "\n")
        else:
            print(f"Verse {canonical_book} {chapter}:{verse_number} not found in translation {translation_choice}.")

if __name__ == '__main__':
    main()
