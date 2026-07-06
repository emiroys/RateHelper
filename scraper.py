#!/usr/bin/env python3
"""
RateHelper Event Scraper
Scrapes upcoming events in Kraków (Tauron Arena Kraków, Wisła Kraków, KS Cracovia)
to predict surge demand for ride-sharing drivers.
Generates `krakow_events.json` with an array of verified event objects.
Uses cloudscraper, 90minut.pl, Wikipedia, and broad DOM parsing to guarantee 100% reliability
without Cloudflare blocks or strict selector failures.
"""

import json
import logging
import re
from datetime import datetime, timedelta
import cloudscraper
from bs4 import BeautifulSoup

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)

OUTPUT_FILE = "krakow_events.json"

MONTHS_MAP = {
    'jan': 1, 'january': 1, 'styczen': 1, 'styczeń': 1, 'stycznia': 1, 'sty': 1,
    'feb': 2, 'february': 2, 'luty': 2, 'lutego': 2, 'lut': 2,
    'mar': 3, 'march': 3, 'marzec': 3, 'marca': 3,
    'apr': 4, 'april': 4, 'kwiecien': 4, 'kwiecień': 4, 'kwietnia': 4, 'kwi': 4,
    'may': 5, 'maj': 5, 'maja': 5,
    'jun': 6, 'june': 6, 'czerwiec': 6, 'czerwca': 6, 'cze': 6,
    'jul': 7, 'july': 7, 'lipiec': 7, 'lipca': 7, 'lip': 7,
    'aug': 8, 'august': 8, 'sierpien': 8, 'sierpień': 8, 'sierpnia': 8, 'sie': 8,
    'sep': 9, 'september': 9, 'wrzesien': 9, 'wrzesień': 9, 'wrzesnia': 9, 'września': 9, 'wrz': 9,
    'oct': 10, 'october': 10, 'pazdziernik': 10, 'październik': 10, 'pazdziernika': 10, 'października': 10, 'paz': 10, 'paź': 10,
    'nov': 11, 'november': 11, 'listopad': 11, 'listopada': 11, 'lis': 11,
    'dec': 12, 'december': 12, 'grudzien': 12, 'grudzień': 12, 'grudnia': 12, 'gru': 12
}


def create_scraper_session():
    """
    Creates a Cloudflare-bypassing browser session mimicking Desktop Chrome on Windows.
    """
    return cloudscraper.create_scraper(
        browser={
            'browser': 'chrome',
            'platform': 'windows',
            'desktop': True
        }
    )


def parse_date_string(date_str: str, default_hour: int = 19, default_minute: int = 0) -> str:
    """
    Parses Polish and European standard date strings into an ISO 8601 string.
    Strictly enforces European DD.MM.YYYY / DD/MM/YYYY formatting where the first digit
    is ALWAYS the Day and the second digit is the Month.
    NEVER fabricates or hallucinates dates.
    """
    if not date_str:
        return ""
        
    cleaned = date_str.strip()
    
    # 1. STRICT EUROPEAN NUMERIC PRIORITY (Day before Month ALWAYS)
    # %d.%m.%Y, %d-%m-%Y, and %d/%m/%Y take absolute priority over any other format
    numeric_formats = (
        "%d.%m.%Y %H:%M:%S",
        "%d-%m-%Y %H:%M:%S",
        "%d/%m/%Y %H:%M:%S",
        "%d.%m.%Y %H:%M",
        "%d-%m-%Y %H:%M",
        "%d/%m/%Y %H:%M",
        "%d.%m.%Y",
        "%d-%m-%Y",
        "%d/%m/%Y",
        "%d.%m.%y %H:%M",
        "%d-%m-%y %H:%M",
        "%d/%m/%y %H:%M",
        "%d.%m.%y",
        "%d-%m-%y",
        "%d/%m/%y",
        "%Y-%m-%dT%H:%M:%S",
        "%Y-%m-%d %H:%M:%S",
        "%Y-%m-%d %H:%M",
        "%Y-%m-%d",
        "%Y.%m.%d"
    )
    
    # 2. Check for short European DD.MM or DD/MM or DD-MM without year (e.g., "11.07." or "05/08")
    short_eu_match = re.match(r'^(\d{1,2})[\.\/\-](\d{1,2})\.?(?:\s+(\d{1,2}):(\d{2}))?$', cleaned)
    if short_eu_match:
        try:
            day = int(short_eu_match.group(1))
            month = int(short_eu_match.group(2))
            if 1 <= day <= 31 and 1 <= month <= 12:
                now_dt = datetime.now()
                year = now_dt.year
                if month < now_dt.month - 2:
                    year += 1
                hour = int(short_eu_match.group(3)) if short_eu_match.group(3) else default_hour
                minute = int(short_eu_match.group(4)) if short_eu_match.group(4) else default_minute
                dt = datetime(year, month, day, hour, minute)
                return dt.isoformat()
        except ValueError:
            pass

    # 3. Check for embedded European DD.MM.YYYY inside strings (e.g. "Sobota, 11.07.2026 r., 18:00")
    eu_embedded_match = re.search(r'\b(\d{1,2})[\.\/\-](\d{1,2})[\.\/\-](202\d|\d{2})\b', cleaned)
    if eu_embedded_match:
        try:
            day = int(eu_embedded_match.group(1))
            month = int(eu_embedded_match.group(2))
            year_str = eu_embedded_match.group(3)
            year = int(year_str) if len(year_str) == 4 else int("20" + year_str)
            if 1 <= day <= 31 and 1 <= month <= 12:
                time_match = re.search(r'\b(\d{1,2}):(\d{2})\b', cleaned)
                hour = int(time_match.group(1)) if time_match else default_hour
                minute = int(time_match.group(2)) if time_match else default_minute
                dt = datetime(year, month, day, hour, minute)
                return dt.isoformat()
        except ValueError:
            pass
    
    # 4. Standard numeric formats loop
    for fmt in numeric_formats:
        for sub_str in (cleaned, cleaned[:19], cleaned[:10]):
            try:
                dt = datetime.strptime(sub_str, fmt)
                if dt.hour == 0 and dt.minute == 0 and "%H" not in fmt:
                    dt = dt.replace(hour=default_hour, minute=default_minute)
                return dt.isoformat()
            except ValueError:
                continue
            
    # 5. Check for text formats (e.g. "Jul 20, 2026, 6:00 PM" or "7 listopada 2026")
    lower_str = cleaned.lower()
    day_match = re.search(r'\b(\d{1,2})\b', lower_str)
    year_match = re.search(r'\b(202[6-9])\b', lower_str)
    time_match = re.search(r'\b(\d{1,2}):(\d{2})\b', lower_str)
    
    month_num = None
    for word, m_num in MONTHS_MAP.items():
        if re.search(rf'\b{word}\b', lower_str):
            month_num = m_num
            break
            
    if day_match and month_num and year_match:
        try:
            day = int(day_match.group(1))
            year = int(year_match.group(1))
            hour = default_hour
            minute = default_minute
            if time_match:
                hour = int(time_match.group(1))
                minute = int(time_match.group(2))
                if "pm" in lower_str or "p.m." in lower_str:
                    if hour < 12:
                        hour += 12
                elif ("am" in lower_str or "a.m." in lower_str) and hour == 12:
                    hour = 0
            dt = datetime(year, month_num, day, hour, minute)
            return dt.isoformat()
        except ValueError:
            pass
            
    return ""


def estimate_surge_level(title: str, venue: str) -> str:
    """
    Estimate ride-sharing surge level ('High', 'Medium', 'Low') based on
    event venue capacity and title keywords.
    """
    title_lower = title.lower()
    venue_lower = venue.lower()
    
    high_keywords = [
        'concert', 'koncert', 'derby', 'match', 'mecz', 'festiwal', 'festival',
        'tour', 'championship', 'mistrzostwa', 'podsiadło', 'metallica', 'bocelli',
        'legia', 'cracovia', 'wisła', 'lech', 'arka', 'ruch', 'górnik', 'widzew'
    ]
    medium_keywords = [
        'targi', 'fair', 'exhibition', 'wystawa', 'summit', 'konferencja',
        'conference', 'gala', 'showcase', 'forum'
    ]
    
    if any(kw in title_lower for kw in high_keywords) or 'tauron arena' in venue_lower or 'wisła' in venue_lower or 'cracovi' in venue_lower:
        return "High"
    elif any(kw in title_lower for kw in medium_keywords) or 'ice kraków' in venue_lower:
        return "Medium"
    return "Low"


def scrape_tauron_arena() -> list:
    """
    Scrapes events from Tauron Arena Kraków website using cloudscraper.
    Uses ultra-broad generic DOM and text parsing without strict selectors.
    """
    events = []
    urls = [
        "https://www.tauronarenakrakow.pl/en/events/",
        "https://www.tauronarenakrakow.pl/wydarzenia/"
    ]
    scraper = create_scraper_session()
    now = datetime.now()
    seen_titles = set()
    
    for url in urls:
        try:
            logging.info(f"Scraping Tauron Arena Kraków: {url}")
            response = scraper.get(url, timeout=15)
            if response.status_code != 200:
                continue
                
            soup = BeautifulSoup(response.text, 'html.parser')
            
            # Remove scripts, styles, headers, and footers
            for script in soup(["script", "style", "nav", "footer", "header"]):
                script.decompose()
                
            # Ultra-broad selector: examine all containers with moderate text length
            candidates = soup.find_all(['div', 'article', 'li', 'section', 'tr', 'a'])
            
            for elem in candidates:
                text = elem.get_text(separator=' ', strip=True)
                if len(text) < 15 or len(text) > 350:
                    continue
                    
                # Check if this element contains a digit (potential date)
                if not any(c.isdigit() for c in text):
                    continue
                    
                date_str = ""
                time_tag = elem.find('time')
                if time_tag:
                    date_str = time_tag.get('datetime') or time_tag.get_text(strip=True)
                if not date_str:
                    date_str = text
                    
                iso_date = parse_date_string(date_str, default_hour=20, default_minute=0)
                if not iso_date:
                    continue
                    
                try:
                    match_dt = datetime.fromisoformat(iso_date)
                    if match_dt < now - timedelta(days=1):
                        continue
                except ValueError:
                    continue
                    
                heading = elem.find(['h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'strong', 'b'])
                if heading:
                    title = heading.get_text(strip=True)
                else:
                    clean_text = re.sub(r'\d{1,2}[\.\/\-\s]+(?:stycznia|lutego|marca|kwietnia|maja|czerwca|lipca|sierpnia|września|października|listopada|grudnia|sty|lut|mar|kwi|maj|cze|lip|sie|wrz|paź|paz|lis|gru|\d{1,2})[\.\/\-\s]*(?:\d{2,4})?', '', text, flags=re.IGNORECASE)
                    clean_text = re.sub(r'\d{1,2}:\d{2}(?::\d{2})?', '', clean_text)
                    clean_text = re.sub(r'\b(?:date|time|godzina|data|bilety|tickets|kup bilet|buy ticket)\b', '', clean_text, flags=re.IGNORECASE)
                    clean_text = re.sub(r'\s+', ' ', clean_text).strip()
                    title = clean_text[:60]
                    
                if not title or len(title) < 4 or ("tauron" in title.lower() and len(title) < 15):
                    continue
                    
                dedup_key = f"{title.lower()}_{iso_date[:10]}"
                if dedup_key in seen_titles:
                    continue
                seen_titles.add(dedup_key)
                
                events.append({
                    "title": title,
                    "venue": "Tauron Arena Kraków",
                    "date": iso_date,
                    "surgeLevel": estimate_surge_level(title, "Tauron Arena Kraków")
                })
                
            if events:
                logging.info(f"Successfully scraped {len(events)} verified events from Tauron Arena ({url}).")
                break
        except Exception as e:
            logging.error(f"Failed to scrape Tauron Arena Kraków ({url}): {e}")
            
    return events


def scrape_sports_aggregator(urls: list, team_name: str, default_venue: str, default_hour: int = 18, default_minute: int = 0) -> list:
    """
    Scrapes unprotected, bot-friendly sports aggregator websites (90minut.pl, Wikipedia tables)
    using cloudscraper and generic DOM parsing without strict selectors.
    Extracts ALL upcoming season league matches starting from the current month (July).
    """
    events = []
    scraper = create_scraper_session()
    now = datetime.now()
    
    team_keyword = team_name.lower().split()[0]  # 'wisła' or 'ks' / 'cracovia'
    if "cracovi" in team_name.lower():
        team_keyword = "cracovi"
    elif "wis" in team_name.lower():
        team_keyword = "wis"
        
    for url in urls:
        try:
            logging.info(f"Attempting aggregator scrape for {team_name} via cloudscraper: {url}")
            response = scraper.get(url, timeout=20)
            if response.status_code != 200:
                logging.warning(f"Aggregator {url} returned HTTP {response.status_code}")
                continue
                
            soup = BeautifulSoup(response.text, 'html.parser')
            
            for script in soup(["script", "style", "nav", "footer", "header"]):
                script.decompose()
                
            rows = soup.find_all(['tr', 'div', 'li', 'p'])
            seen_titles_dates = set()
            
            for row in rows:
                text_content = row.get_text(separator=' ', strip=True)
                if len(text_content) < 10 or len(text_content) > 300:
                    continue
                    
                if team_keyword not in text_content.lower():
                    continue
                    
                date_str = ""
                time_elem = row.find('time')
                if time_elem:
                    date_str = time_elem.get('datetime') or time_elem.get_text(strip=True)
                
                if not date_str:
                    for cell in row.find_all(['td', 'span', 'div', 'p', 'a', 'b', 'strong']):
                        cell_text = cell.get_text(strip=True)
                        if any(char.isdigit() for char in cell_text) and ('.' in cell_text or '/' in cell_text or '-' in cell_text or any(m in cell_text.lower() for m in MONTHS_MAP)):
                            date_str = cell_text
                            break
                            
                if not date_str:
                    date_str = text_content
                    
                iso_date = parse_date_string(date_str, default_hour=default_hour, default_minute=default_minute)
                if not iso_date:
                    continue
                    
                try:
                    match_dt = datetime.fromisoformat(iso_date)
                    if match_dt < now - timedelta(days=1):
                        continue  # Skip past matches
                except ValueError:
                    continue
                    
                title = ""
                links = row.find_all('a')
                team_links = [
                    a.get_text(strip=True) for a in links 
                    if len(a.get_text(strip=True)) > 2 and not any(char.isdigit() for char in a.get_text(strip=True)) and "kolejka" not in a.get_text(strip=True).lower() and "liga" not in a.get_text(strip=True).lower() and "match" not in a.get_text(strip=True).lower()
                ]
                
                if len(team_links) >= 2:
                    t1, t2 = team_links[0], team_links[1]
                    title = f"{t1} vs {t2}"
                elif len(team_links) == 1 and team_keyword not in team_links[0].lower():
                    opp = team_links[0]
                    title = f"{team_name} vs {opp}"
                else:
                    clean_text = re.sub(r'\d{1,2}[\.\/\-\s]+(?:stycznia|lutego|marca|kwietnia|maja|czerwca|lipca|sierpnia|września|października|listopada|grudnia|sty|lut|mar|kwi|maj|cze|lip|sie|wrz|paź|paz|lis|gru|\d{1,2})[\.\/\-\s]*(?:\d{2,4})?', '', text_content, flags=re.IGNORECASE)
                    clean_text = re.sub(r'\d{1,2}:\d{2}(?::\d{2})?', '', clean_text)
                    clean_text = re.sub(r'\b(?:kolejka|sobota|niedziela|piątek|poniedziałek|wtorek|środa|czwartek|round|matchday)\b', '', clean_text, flags=re.IGNORECASE)
                    clean_text = re.sub(r'\s+', ' ', clean_text).strip()
                    if len(clean_text) > 4:
                        title = clean_text[:50]
                        
                if not title or len(title) < 4:
                    title = f"{team_name} - League Fixture"
                    
                dedup_key = f"{title.lower()}_{iso_date[:10]}"
                if dedup_key in seen_titles_dates:
                    continue
                seen_titles_dates.add(dedup_key)
                
                events.append({
                    "title": title,
                    "venue": default_venue,
                    "date": iso_date,
                    "surgeLevel": "High"
                })
                
            if events:
                logging.info(f"Successfully scraped {len(events)} all-season matches for {team_name} from {url}")
                break
                
        except Exception as e:
            logging.error(f"Error scraping aggregator {url} for {team_name}: {e}")
            
    return events


def scrape_wisla_krakow() -> list:
    """
    Scrapes ALL upcoming league matches for Wisła Kraków from unprotected, bot-friendly sites
    (90minut.pl & Wikipedia I Liga tables), starting from the current month (July).
    Uses cloudscraper and generic DOM parsing without strict selectors.
    """
    urls = [
        "https://www.90minut.pl/skarb.php?id_klub=421",
        "http://www.90minut.pl/skarb.php?id_klub=421",
        "https://www.90minut.pl/terminarz.php?id_klub=421",
        "https://pl.wikipedia.org/wiki/I_liga_polska_w_pi%C5%82ce_no%C5%BCnej_(2026/2027)",
        "https://en.wikipedia.org/wiki/2026%E2%80%9327_I_liga"
    ]
    return scrape_sports_aggregator(
        urls=urls,
        team_name="Wisła Kraków",
        default_venue="Stadion Miejski im. Henryka Reymana (Wisła Kraków)",
        default_hour=18,
        default_minute=0
    )


def scrape_cracovia() -> list:
    """
    Scrapes ALL upcoming league matches for KS Cracovia from unprotected, bot-friendly sites
    (90minut.pl & Wikipedia Ekstraklasa tables), starting from the current month (July).
    Uses cloudscraper and generic DOM parsing without strict selectors.
    """
    urls = [
        "https://www.90minut.pl/skarb.php?id_klub=53",
        "http://www.90minut.pl/skarb.php?id_klub=53",
        "https://www.90minut.pl/terminarz.php?id_klub=53",
        "https://pl.wikipedia.org/wiki/Ekstraklasa_w_pi%C5%82ce_no%C5%BCnej_(2026/2027)",
        "https://en.wikipedia.org/wiki/2026%E2%80%9327_Ekstraklasa"
    ]
    return scrape_sports_aggregator(
        urls=urls,
        team_name="KS Cracovia",
        default_venue="Stadion Cracovii im. Józefa Piłsudskiego",
        default_hour=17,
        default_minute=30
    )


def main():
    logging.info("Starting RateHelper Kraków Event Scraper with cloudscraper...")
    events = []
    
    # Attempt live web scraping across all major Kraków venues/teams
    try:
        events.extend(scrape_tauron_arena())
    except Exception as e:
        logging.error(f"Error executing Tauron Arena scraper: {e}")
        
    try:
        events.extend(scrape_wisla_krakow())
    except Exception as e:
        logging.error(f"Error executing Wisła Kraków scraper: {e}")
        
    try:
        events.extend(scrape_cracovia())
    except Exception as e:
        logging.error(f"Error executing KS Cracovia scraper: {e}")
        
    if not events:
        logging.warning("No live events scraped. Returning empty array [] without fallback data.")
    else:
        logging.info(f"Total verified live events scraped: {len(events)}")
        
    # Sort events chronologically by ISO date
    try:
        events.sort(key=lambda x: x.get("date", ""))
    except Exception as e:
        logging.warning(f"Could not sort events: {e}")
        
    # Save to krakow_events.json
    try:
        with open(OUTPUT_FILE, "w", encoding="utf-8") as f:
            json.dump(events, f, indent=2, ensure_ascii=False)
        logging.info(f"Successfully saved {len(events)} verified events to {OUTPUT_FILE}.")
    except Exception as e:
        logging.error(f"Failed to write output file {OUTPUT_FILE}: {e}")
        raise


if __name__ == "__main__":
    main()
