#!/usr/bin/env python3
"""
RateHelper Event Scraper
Scrapes upcoming events in Kraków (e.g., Tauron Arena Kraków, Wisła Kraków)
to predict surge demand for ride-sharing drivers.
Generates `krakow_events.json` with an array of event objects.
"""

import json
import logging
from datetime import datetime, timedelta
import requests
from bs4 import BeautifulSoup

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)

OUTPUT_FILE = "krakow_events.json"


def get_dummy_events() -> list:
    """
    Fallback dummy data used when live web scraping fails or websites are unreachable.
    Returns realistic events for RateHelper driver demand forecasting.
    """
    logging.info("Using dummy data fallback for Kraków events.")
    base_date = datetime.now()
    return [
        {
            "title": "Dawid Podsiadło - Stadium Tour Concert",
            "venue": "Tauron Arena Kraków",
            "date": (base_date + timedelta(days=2)).replace(hour=20, minute=0, second=0, microsecond=0).isoformat(),
            "surgeLevel": "High"
        },
        {
            "title": "Wisła Kraków vs. KS Cracovia - Derby Match",
            "venue": "Stadion Miejski im. Henryka Reymana (Wisła Kraków)",
            "date": (base_date + timedelta(days=5)).replace(hour=18, minute=0, second=0, microsecond=0).isoformat(),
            "surgeLevel": "High"
        },
        {
            "title": "Kraków Tech & AI Summit 2026",
            "venue": "ICE Kraków Congress Centre",
            "date": (base_date + timedelta(days=7)).replace(hour=9, minute=0, second=0, microsecond=0).isoformat(),
            "surgeLevel": "Medium"
        },
        {
            "title": "International Food & Wine Festival",
            "venue": "Tauron Arena Kraków",
            "date": (base_date + timedelta(days=10)).replace(hour=12, minute=0, second=0, microsecond=0).isoformat(),
            "surgeLevel": "Medium"
        },
        {
            "title": "Local Indie Band Showcase",
            "venue": "Klub Studio",
            "date": (base_date + timedelta(days=12)).replace(hour=21, minute=0, second=0, microsecond=0).isoformat(),
            "surgeLevel": "Low"
        }
    ]


def estimate_surge_level(title: str, venue: str) -> str:
    """
    Estimate ride-sharing surge level ('High', 'Medium', 'Low') based on
    event venue capacity and title keywords.
    """
    title_lower = title.lower()
    venue_lower = venue.lower()
    
    high_keywords = [
        'concert', 'koncert', 'derby', 'match', 'mecz', 'festiwal', 'festival',
        'tour', 'championship', 'mistrzostwa', 'podsiadło', 'metallica'
    ]
    medium_keywords = [
        'targi', 'fair', 'exhibition', 'wystawa', 'summit', 'konferencja',
        'conference', 'gala', 'showcase', 'forum'
    ]
    
    # Major venues and high-demand keywords trigger High surge
    if any(kw in title_lower for kw in high_keywords) or 'tauron arena' in venue_lower or 'wisła' in venue_lower:
        return "High"
    elif any(kw in title_lower for kw in medium_keywords) or 'ice kraków' in venue_lower:
        return "Medium"
    return "Low"


def scrape_tauron_arena() -> list:
    """
    Scrapes events from Tauron Arena Kraków website.
    Uses robust selectors and fallback logic with graceful exception handling.
    """
    events = []
    url = "https://www.tauronarenakrakow.pl/en/events/"
    headers = {
        "User-Agent": (
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
            "AppleWebKit/537.36 (KHTML, like Gecko) "
            "Chrome/122.0.0.0 Safari/537.36"
        )
    }
    
    try:
        logging.info(f"Scraping Tauron Arena Kraków: {url}")
        response = requests.get(url, headers=headers, timeout=10)
        response.raise_for_status()
        
        soup = BeautifulSoup(response.text, 'html.parser')
        
        # Look for event containers using flexible selector strategies
        event_cards = (
            soup.find_all('article') or
            soup.find_all('div', class_=lambda c: c and any(k in c.lower() for k in ['event', 'item', 'card']))
        )
        
        for card in event_cards[:10]:
            # Title parsing
            title_elem = (
                card.find(['h1', 'h2', 'h3', 'h4']) or
                card.find(class_=lambda c: c and 'title' in c.lower())
            )
            if not title_elem:
                continue
                
            title = title_elem.get_text(strip=True)
            if not title or len(title) < 3:
                continue
                
            # Date parsing
            date_elem = (
                card.find('time') or
                card.find(class_=lambda c: c and any(k in c.lower() for k in ['date', 'time', 'day']))
            )
            iso_date = ""
            if date_elem:
                date_str = date_elem.get('datetime') or date_elem.get_text(strip=True)
                if date_str:
                    for fmt in ("%Y-%m-%d", "%d.%m.%Y", "%Y-%m-%dT%H:%M:%S", "%d/%m/%Y"):
                        try:
                            iso_date = datetime.strptime(date_str[:10], fmt).replace(hour=20, minute=0).isoformat()
                            break
                        except ValueError:
                            continue
            
            # Fallback date if parsing specific timestamp fails
            if not iso_date:
                iso_date = (datetime.now() + timedelta(days=3)).replace(hour=20, minute=0, second=0, microsecond=0).isoformat()
                
            events.append({
                "title": title,
                "venue": "Tauron Arena Kraków",
                "date": iso_date,
                "surgeLevel": estimate_surge_level(title, "Tauron Arena Kraków")
            })
            
        logging.info(f"Successfully scraped {len(events)} events from Tauron Arena.")
    except Exception as e:
        logging.warning(f"Failed to scrape Tauron Arena Kraków ({url}): {e}")
        
    return events


def scrape_wisla_krakow() -> list:
    """
    Scrapes upcoming match fixtures from Wisła Kraków schedule page.
    """
    events = []
    url = "https://wislakrakow.com/terminarz"
    headers = {
        "User-Agent": (
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
            "AppleWebKit/537.36 (KHTML, like Gecko) "
            "Chrome/122.0.0.0 Safari/537.36"
        )
    }
    
    try:
        logging.info(f"Scraping Wisła Kraków: {url}")
        response = requests.get(url, headers=headers, timeout=10)
        response.raise_for_status()
        
        soup = BeautifulSoup(response.text, 'html.parser')
        
        # Look for match rows or fixture boxes
        match_rows = soup.find_all('div', class_=lambda c: c and any(k in c.lower() for k in ['match', 'fixture', 'game', 'event']))
        
        for row in match_rows[:5]:
            title_elem = (
                row.find(['h3', 'h4', 'span'], class_=lambda c: c and any(k in c.lower() for k in ['team', 'title', 'name', 'opponent'])) or
                row.find(['h3', 'h4'])
            )
            if not title_elem:
                continue
                
            title = title_elem.get_text(strip=True)
            if not title or len(title) < 3:
                continue
                
            date_elem = row.find('time') or row.find(class_=lambda c: c and 'date' in c.lower())
            iso_date = ""
            if date_elem:
                date_str = date_elem.get('datetime') or date_elem.get_text(strip=True)
                try:
                    iso_date = datetime.fromisoformat(date_str[:10]).replace(hour=18, minute=0).isoformat()
                except ValueError:
                    pass
                    
            if not iso_date:
                iso_date = (datetime.now() + timedelta(days=5)).replace(hour=18, minute=0, second=0, microsecond=0).isoformat()
                
            events.append({
                "title": f"Wisła Kraków vs {title}" if "wisła" not in title.lower() else title,
                "venue": "Stadion Miejski im. Henryka Reymana (Wisła Kraków)",
                "date": iso_date,
                "surgeLevel": "High"
            })
            
        logging.info(f"Successfully scraped {len(events)} events from Wisła Kraków.")
    except Exception as e:
        logging.warning(f"Failed to scrape Wisła Kraków ({url}): {e}")
        
    return events


def main():
    logging.info("Starting RateHelper Kraków Event Scraper...")
    events = []
    
    # Attempt live web scraping
    events.extend(scrape_tauron_arena())
    events.extend(scrape_wisla_krakow())
    
    # Fallback to dummy data if live scraping yielded no events
    if not events:
        logging.warning("No live events scraped or web requests failed. Switching to dummy data fallback.")
        events = get_dummy_events()
    else:
        logging.info(f"Total live events scraped: {len(events)}")
        
    # Sort events chronologically by ISO date
    try:
        events.sort(key=lambda x: x.get("date", ""))
    except Exception as e:
        logging.warning(f"Could not sort events: {e}")
        
    # Save to krakow_events.json
    try:
        with open(OUTPUT_FILE, "w", encoding="utf-8") as f:
            json.dump(events, f, indent=2, ensure_ascii=False)
        logging.info(f"Successfully saved {len(events)} events to {OUTPUT_FILE}.")
    except Exception as e:
        logging.error(f"Failed to write output file {OUTPUT_FILE}: {e}")
        raise


if __name__ == "__main__":
    main()
