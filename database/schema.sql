-- =============================================================
-- CTI Platform
-- schema.sql
--
-- Complete database schema for the CTI collection/processing
-- pipeline: raw alert ingestion, IOC extraction, threat
-- analysis, and the proactive Discovery Engine.
--
-- Usage:
--   docker exec -i cti-postgres psql -U postgres -d cti_db < schema.sql
-- =============================================================


-- -------------------------------------------------------------
-- Table: watchlist
-- Keywords/domains monitored by the collection probes.
-- Populated manually by an analyst, or automatically when a
-- "domain" candidate is approved through the Discovery Engine.
-- -------------------------------------------------------------
CREATE TABLE IF NOT EXISTS watchlist (
    id          SERIAL PRIMARY KEY,
    keyword     VARCHAR(255) NOT NULL,
    category    VARCHAR(100) NOT NULL,
    created_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);


-- -------------------------------------------------------------
-- Table: alerts
-- Raw alerts submitted by the 5 collection probes (GitHub,
-- Pastebin, Telegram, Twitter/X, Tor). keyword_id is nullable:
-- a "generic credential harvest" alert (no specific keyword
-- match) is still recorded, with keyword_id = NULL.
-- -------------------------------------------------------------
CREATE TABLE IF NOT EXISTS alerts (
    id             SERIAL PRIMARY KEY,
    keyword_id     INTEGER REFERENCES watchlist(id),
    alert_message  TEXT,
    source         TEXT,
    severity       VARCHAR(20),
    status         VARCHAR(30) DEFAULT 'NEW',
    created_at     TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);


-- -------------------------------------------------------------
-- Table: indicators
-- Indicators of compromise (IOCs) automatically extracted from
-- alert text.
--
-- risk_flag  : added alongside keyword-based risk scoring
--              (dump, leak, breach...)
-- alert_id   : added for credential pairing - links each
--              indicator to its source alert, enabling an
--              email to be paired with the password found in
--              the same leak.
-- -------------------------------------------------------------
CREATE TABLE IF NOT EXISTS indicators (
    id               SERIAL PRIMARY KEY,
    indicator_type   VARCHAR(50),
    indicator_value  TEXT,
    confidence       INTEGER,
    risk_flag        VARCHAR(20),
    alert_id         INTEGER REFERENCES alerts(id),
    created_at       TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_indicators_alert_id
    ON indicators(alert_id);


-- -------------------------------------------------------------
-- Table: users
-- Analyst accounts for dashboard authentication. Passwords are
-- hashed (bcrypt via passlib), never stored in plain text.
-- -------------------------------------------------------------
CREATE TABLE IF NOT EXISTS users (
    id             SERIAL PRIMARY KEY,
    username       VARCHAR(100) UNIQUE NOT NULL,
    password_hash  VARCHAR(255) NOT NULL,
    role           VARCHAR(50) DEFAULT 'admin',
    created_at     TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);


-- -------------------------------------------------------------
-- Table: threat_analysis
-- Results of the threat intelligence engine: BIN detection,
-- phishing detection, WHOIS/DNS data, VirusTotal reputation,
-- and final score/classification. One record per analyzed alert.
-- -------------------------------------------------------------
CREATE TABLE IF NOT EXISTS threat_analysis (
    id                        SERIAL PRIMARY KEY,
    alert_id                  INTEGER REFERENCES alerts(id),
    bin_detected              BOOLEAN DEFAULT FALSE,
    bin_values                TEXT,
    phishing_detected         BOOLEAN DEFAULT FALSE,
    phishing_keywords         TEXT,
    domain                    TEXT,
    domain_registrar          TEXT,
    domain_creation_date      TEXT,
    domain_malicious_votes    INTEGER,
    domain_suspicious_votes   INTEGER,
    domain_harmless_votes     INTEGER,
    score                     INTEGER,
    classification            VARCHAR(50),
    analyzed_at               TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);


-- -------------------------------------------------------------
-- Table: discovered_sources
-- Candidates automatically found by the Discovery Engine's 6
-- modules (Domain, Domain Link-Following, GitHub, Pastebin,
-- Telegram, Tor), pending analyst review.
--
-- source_type       : 'domain', 'github_repo', 'telegram_channel',
--                      'tor_onion', 'pastebin_paste'
-- discovery_method  : 'dnstwist', 'crt.sh', 'link_following',
--                      'leak_term_search', 'author_pivot',
--                      'pastebin_reference', 'cross_reference',
--                      'ahmia_or_link_following'
-- status            : 'pending', 'approved', 'rejected'
-- -------------------------------------------------------------
CREATE TABLE IF NOT EXISTS discovered_sources (
    id                 SERIAL PRIMARY KEY,
    source_type        VARCHAR(50) NOT NULL,
    value              TEXT NOT NULL,
    discovery_method   VARCHAR(100),
    confidence         INTEGER DEFAULT 50,
    status             VARCHAR(20) DEFAULT 'pending',
    metadata           JSONB DEFAULT '{}',
    discovered_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    reviewed_at        TIMESTAMP,
    UNIQUE(source_type, value)
);


-- -------------------------------------------------------------
-- Table: crawler_sources
-- Collection targets for Tor and Telegram, read dynamically by
-- their respective probes on each run - replaces previously
-- hardcoded target lists. Destination table for Telegram/Tor
-- candidates approved through the Discovery Engine.
--
-- source_type  : 'tor_onion' or 'telegram_channel'
-- added_via    : 'manual' (initial migration) or 'discovery'
--                (added via an approval action)
-- -------------------------------------------------------------
CREATE TABLE IF NOT EXISTS crawler_sources (
    id           SERIAL PRIMARY KEY,
    source_type  VARCHAR(20) NOT NULL,
    value        TEXT NOT NULL,
    active       BOOLEAN DEFAULT TRUE,
    added_via    VARCHAR(20) DEFAULT 'manual',
    added_at     TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(source_type, value)
);

CREATE INDEX IF NOT EXISTS idx_crawler_sources_type
    ON crawler_sources(source_type);


-- =============================================================
-- End of schema - 7 tables total
-- =============================================================
