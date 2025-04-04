import os
import xml.etree.ElementTree as ET
import datetime
import random

def load_nasb(xml_path):
    """
    Parse NASB.xml and return a list of verses.
    Each verse is a dictionary with keys: 'book', 'chapter', 'verse', and 'text'.
    """
    verses = []
    try:
        tree = ET.parse(xml_path)
        root = tree.getroot()
    except Exception as e:
        print(f"Error loading NASB.xml: {e}")
        return verses

    # Loop through each book, chapter, and verse.
    for book in root.findall('b'):
        book_name = book.attrib.get('n', '').strip()
        for chapter in book.findall('c'):
            try:
                chapter_num = int(chapter.attrib.get('n'))
            except (ValueError, TypeError):
                continue
            for verse in chapter.findall('v'):
                try:
                    verse_num = int(verse.attrib.get('n'))
                except (ValueError, TypeError):
                    continue
                verse_text = verse.text.strip() if verse.text else ""
                verses.append({
                    'book': book_name,
                    'chapter': chapter_num,
                    'verse': verse_num,
                    'text': verse_text
                })
    return verses

def find_verses_for_time(verses, chapter, verse_num):
    """
    Return a list of verses where the chapter equals the given chapter
    and the verse number equals the given verse_num.
    """
    return [v for v in verses if v['chapter'] == chapter and v['verse'] == verse_num]

def main():
    # Path to NASB.xml (update the path if necessary)
    nasb_path = os.path.expanduser("~/bible/bible/translations/NASB.xml")
    if not os.path.exists(nasb_path):
        print("NASB.xml not found at:", nasb_path)
        return

    # Load all verses from NASB.xml.
    verses = load_nasb(nasb_path)
    if not verses:
        print("No verses loaded from NASB.xml.")
        return

    # Get the current time.
    now = datetime.datetime.now()
    current_hour = now.hour
    current_minute = now.minute

    # Show current time.
    print(f"Current time: {current_hour}:{current_minute:02d}")

    # Find verses where chapter equals current hour and verse equals current minute.
    matching_verses = find_verses_for_time(verses, current_hour, current_minute)
    
    if not matching_verses:
        print(f"No verse found for chapter {current_hour} and verse {current_minute}.")
    else:
        # Pick a random verse from the matching verses.
        chosen = random.choice(matching_verses)
        print(f"\nRandom Bible Verse for {current_hour}:{current_minute:02d}")
        print(f"{chosen['book']} {chosen['chapter']}:{chosen['verse']}")
        print(chosen['text'])

if __name__ == '__main__':
    main()
