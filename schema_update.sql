-- ═══════════════════════════════════════════════════════════════════
-- Grand Prix Hub — Schema Update
-- Run AFTER the original schema.sql
-- ═══════════════════════════════════════════════════════════════════

USE grand_prix_hub;

-- ── Add missing columns to existing tables ────────────────────────

-- TEAM: add emoji and color if not already present
ALTER TABLE TEAM
  ADD COLUMN IF NOT EXISTS emoji VARCHAR(8)   DEFAULT '🏎️',
  ADD COLUMN IF NOT EXISTS color VARCHAR(16)  DEFAULT '#666666';

-- RACE_WEEKEND: add name, flag columns (may already exist)
ALTER TABLE RACE_WEEKEND
  ADD COLUMN IF NOT EXISTS name    VARCHAR(100) DEFAULT 'Grand Prix',
  ADD COLUMN IF NOT EXISTS circuit VARCHAR(200) DEFAULT 'TBC',
  ADD COLUMN IF NOT EXISTS flag    VARCHAR(8)   DEFAULT '🏁';

-- DRIVER: add flag column for emoji nationality display
ALTER TABLE DRIVER
  ADD COLUMN IF NOT EXISTS flag VARCHAR(8) DEFAULT '🏁';

-- ── Seed emoji/color for teams (update to match your TeamID values) ─

UPDATE TEAM SET emoji = '🔴', color = '#E8002D'   WHERE TeamName LIKE '%Ferrari%';
UPDATE TEAM SET emoji = '🔵', color = '#3671C6'   WHERE TeamName LIKE '%Red Bull%';
UPDATE TEAM SET emoji = '🟠', color = '#FF8000'   WHERE TeamName LIKE '%McLaren%';
UPDATE TEAM SET emoji = '⚫', color = '#27F4D2'   WHERE TeamName LIKE '%Mercedes%';
UPDATE TEAM SET emoji = '🟢', color = '#00A19C'   WHERE TeamName LIKE '%Aston%';
UPDATE TEAM SET emoji = '🩷', color = '#FF69B4'   WHERE TeamName LIKE '%Alpine%';
UPDATE TEAM SET emoji = '⚪', color = '#64C4FF'   WHERE TeamName LIKE '%Williams%';
UPDATE TEAM SET emoji = '⚪', color = '#B0B0B0'   WHERE TeamName LIKE '%Haas%';
UPDATE TEAM SET emoji = '🔵', color = '#3671C6'   WHERE TeamName LIKE '%RB%';
UPDATE TEAM SET emoji = '🔵', color = '#3671C6'   WHERE TeamName LIKE '%Kick%' OR TeamName LIKE '%Sauber%';

-- ── Seed flag emojis for drivers ──────────────────────────────────

UPDATE DRIVER SET flag = '🇳🇱' WHERE LastName = 'Verstappen';
UPDATE DRIVER SET flag = '🇲🇽' WHERE LastName = 'Perez';
UPDATE DRIVER SET flag = '🇬🇧' WHERE LastName = 'Hamilton';
UPDATE DRIVER SET flag = '🇬🇧' WHERE LastName = 'Russell';
UPDATE DRIVER SET flag = '🇲🇨' WHERE LastName = 'Leclerc';
UPDATE DRIVER SET flag = '🇪🇸' WHERE LastName = 'Sainz';
UPDATE DRIVER SET flag = '🇬🇧' WHERE LastName = 'Norris';
UPDATE DRIVER SET flag = '🇦🇺' WHERE LastName = 'Piastri';
UPDATE DRIVER SET flag = '🇪🇸' WHERE LastName = 'Alonso';
UPDATE DRIVER SET flag = '🇨🇦' WHERE LastName = 'Stroll';
UPDATE DRIVER SET flag = '🇫🇷' WHERE LastName = 'Ocon';
UPDATE DRIVER SET flag = '🇦🇺' WHERE LastName = 'Gasly';
UPDATE DRIVER SET flag = '🇹🇭' WHERE LastName = 'Albon';
UPDATE DRIVER SET flag = '🇺🇸' WHERE LastName = 'Sargeant';
UPDATE DRIVER SET flag = '🇩🇰' WHERE LastName = 'Magnussen';
UPDATE DRIVER SET flag = '🇩🇪' WHERE LastName = 'Hulkenberg';
UPDATE DRIVER SET flag = '🇯🇵' WHERE LastName = 'Tsunoda';
UPDATE DRIVER SET flag = '🇦🇷' WHERE LastName = 'Colapinto';
UPDATE DRIVER SET flag = '🇨🇳' WHERE LastName = 'Zhou';
UPDATE DRIVER SET flag = '🇫🇮' WHERE LastName = 'Bottas';

-- Fallback for any drivers still without a flag
UPDATE DRIVER SET flag = '🏁' WHERE flag IS NULL OR flag = '';

-- ── Seed flag emojis for race weekends ────────────────────────────

UPDATE RACE_WEEKEND SET flag = '🇦🇺' WHERE name LIKE '%Australian%';
UPDATE RACE_WEEKEND SET flag = '🇯🇵' WHERE name LIKE '%Japanese%';
UPDATE RACE_WEEKEND SET flag = '🇧🇭' WHERE name LIKE '%Bahrain%';
UPDATE RACE_WEEKEND SET flag = '🇸🇦' WHERE name LIKE '%Saudi%';
UPDATE RACE_WEEKEND SET flag = '🇨🇳' WHERE name LIKE '%Chinese%';
UPDATE RACE_WEEKEND SET flag = '🇺🇸' WHERE name LIKE '%Miami%' OR name LIKE '%United States%' OR name LIKE '%Las Vegas%';
UPDATE RACE_WEEKEND SET flag = '🇮🇹' WHERE name LIKE '%Italian%' OR name LIKE '%Emilia%';
UPDATE RACE_WEEKEND SET flag = '🇲🇨' WHERE name LIKE '%Monaco%';
UPDATE RACE_WEEKEND SET flag = '🇨🇦' WHERE name LIKE '%Canadian%';
UPDATE RACE_WEEKEND SET flag = '🇪🇸' WHERE name LIKE '%Spanish%';
UPDATE RACE_WEEKEND SET flag = '🇦🇹' WHERE name LIKE '%Austrian%';
UPDATE RACE_WEEKEND SET flag = '🇬🇧' WHERE name LIKE '%British%';
UPDATE RACE_WEEKEND SET flag = '🇭🇺' WHERE name LIKE '%Hungarian%';
UPDATE RACE_WEEKEND SET flag = '🇧🇪' WHERE name LIKE '%Belgian%';
UPDATE RACE_WEEKEND SET flag = '🇳🇱' WHERE name LIKE '%Dutch%';
UPDATE RACE_WEEKEND SET flag = '🇦🇿' WHERE name LIKE '%Azerbaijan%';
UPDATE RACE_WEEKEND SET flag = '🇸🇬' WHERE name LIKE '%Singapore%';
UPDATE RACE_WEEKEND SET flag = '🇲🇽' WHERE name LIKE '%Mexican%';
UPDATE RACE_WEEKEND SET flag = '🇧🇷' WHERE name LIKE '%Brazilian%';
UPDATE RACE_WEEKEND SET flag = '🇦🇪' WHERE name LIKE '%Abu Dhabi%';
UPDATE RACE_WEEKEND SET flag = '🏁'  WHERE flag IS NULL OR flag = '';

-- ═══════════════════════════════════════════════════════════════════
-- TRANSACTION_LOG — records every TXN execution (Task 6)
-- ═══════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS TRANSACTION_LOG (
  LogID        INT          NOT NULL AUTO_INCREMENT,
  TxnType      VARCHAR(40)  NOT NULL COMMENT 'sign_driver | incident_penalty | register_weekend | conflicting_contracts',
  Status       ENUM('committed','rolled_back','error') NOT NULL,
  StepsJSON    JSON         DEFAULT NULL COMMENT 'full step array returned to the client',
  ExecutedBy   VARCHAR(40)  DEFAULT 'admin'  COMMENT 'role/user that triggered this',
  ExecutedAt   DATETIME     DEFAULT CURRENT_TIMESTAMP,
  Notes        TEXT         DEFAULT NULL,
  PRIMARY KEY (LogID),
  INDEX idx_txn_type  (TxnType),
  INDEX idx_txn_status (Status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ═══════════════════════════════════════════════════════════════════
-- USER_SESSION — tracks logins per role (lightweight)
-- ═══════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS USER_SESSION (
  SessionToken VARCHAR(64)  NOT NULL,
  Role         VARCHAR(20)  NOT NULL,
  Username     VARCHAR(40)  NOT NULL,
  CreatedAt    DATETIME     DEFAULT CURRENT_TIMESTAMP,
  ExpiresAt    DATETIME     DEFAULT NULL,
  PRIMARY KEY (SessionToken),
  INDEX idx_role (Role)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ═══════════════════════════════════════════════════════════════════
-- TRIGGER T1 — Unique driver number (safe CREATE OR REPLACE)
-- ═══════════════════════════════════════════════════════════════════

DROP TRIGGER IF EXISTS trg_no_duplicate_driver_number;
-- NOTE: T1 is OFF by default. Toggle it ON from the Admin → Triggers page.
-- Uncomment the block below to have it start enabled:
/*
CREATE TRIGGER trg_no_duplicate_driver_number
BEFORE INSERT ON DRIVER
FOR EACH ROW
BEGIN
  DECLARE v_count INT DEFAULT 0;
  SELECT COUNT(*) INTO v_count FROM DRIVER WHERE DriverNumber = NEW.DriverNumber;
  IF v_count > 0 THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'T1 BLOCKED: Driver number already taken.';
  END IF;
END;
*/

-- ═══════════════════════════════════════════════════════════════════
-- TRIGGER T2 — Auto-fill EndDate on DRIVER_CONTRACT
-- ═══════════════════════════════════════════════════════════════════

DROP TRIGGER IF EXISTS trg_auto_contract_end_date;
-- NOTE: T2 is OFF by default. Toggle from Admin → Triggers.
-- Uncomment to start enabled:
/*
CREATE TRIGGER trg_auto_contract_end_date
BEFORE INSERT ON DRIVER_CONTRACT
FOR EACH ROW
BEGIN
  IF NEW.EndDate IS NULL THEN
    SET NEW.EndDate = DATE_ADD(NEW.StartDate, INTERVAL 1 YEAR);
  END IF;
END;
*/

-- ═══════════════════════════════════════════════════════════════════
-- Verification query — run after applying this update
-- ═══════════════════════════════════════════════════════════════════

SELECT
  'TEAM'             AS tbl, COUNT(*) AS rows, MAX(TeamID)             AS max_pk FROM TEAM   UNION ALL
SELECT 'DRIVER',              COUNT(*), MAX(DriverID)                              FROM DRIVER UNION ALL
SELECT 'DRIVER_CONTRACT',     COUNT(*), MAX(ContractID)                            FROM DRIVER_CONTRACT UNION ALL
SELECT 'RACE_WEEKEND',        COUNT(*), MAX(WeekendID)                             FROM RACE_WEEKEND UNION ALL
SELECT 'SESSION',             COUNT(*), MAX(SessionID)                             FROM SESSION UNION ALL
SELECT 'LAP_TIME',            COUNT(*), MAX(LapTimeID)                             FROM LAP_TIME UNION ALL
SELECT 'PIT_STOP',            COUNT(*), MAX(PitStopID)                             FROM PIT_STOP UNION ALL
SELECT 'INCIDENT',            COUNT(*), MAX(IncidentID)                            FROM INCIDENT UNION ALL
SELECT 'PENALTY',             COUNT(*), MAX(PenaltyID)                             FROM PENALTY UNION ALL
SELECT 'TRANSACTION_LOG',     COUNT(*), MAX(LogID)                                 FROM TRANSACTION_LOG;
