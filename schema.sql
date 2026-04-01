-- ═══════════════════════════════════════════════════════════════════
--  GRAND PRIX HUB — MySQL Schema
--  Run this entire file in MySQL Workbench to set up the database.
--  MySQL 8.0+ required.
-- ═══════════════════════════════════════════════════════════════════

CREATE DATABASE IF NOT EXISTS grand_prix_hub
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

USE grand_prix_hub;

-- ── Drop in reverse FK order ─────────────────────────────────────
DROP TABLE IF EXISTS PENALTY;
DROP TABLE IF EXISTS INCIDENT;
DROP TABLE IF EXISTS PIT_STOP;
DROP TABLE IF EXISTS LAP_TIME;
DROP TABLE IF EXISTS SESSION;
DROP TABLE IF EXISTS DRIVER_CONTRACT;
DROP TABLE IF EXISTS CAR;
DROP TABLE IF EXISTS RACE_WEEKEND;
DROP TABLE IF EXISTS STEWARD;
DROP TABLE IF EXISTS DRIVER;
DROP TABLE IF EXISTS TEAM;

-- ── Drop triggers (recreated below) ──────────────────────────────
DROP TRIGGER IF EXISTS trg_no_duplicate_driver_number;
DROP TRIGGER IF EXISTS trg_auto_contract_end_date;


-- ═══════════════════════════════════════════════════════════════════
--  TABLE DEFINITIONS
-- ═══════════════════════════════════════════════════════════════════

CREATE TABLE TEAM (
  TeamID      INT          NOT NULL AUTO_INCREMENT,
  TeamName    VARCHAR(100) NOT NULL,
  BaseCountry VARCHAR(60)  NOT NULL,
  color       VARCHAR(10)  DEFAULT '#666666'  COMMENT 'Hex colour for UI',
  emoji       VARCHAR(10)  DEFAULT '🏎️',
  PRIMARY KEY (TeamID)
) ENGINE=InnoDB;

-- ─────────────────────────────────────────────────────────────────
CREATE TABLE DRIVER (
  DriverID     INT          NOT NULL AUTO_INCREMENT,
  DriverNumber INT          NOT NULL,          -- T1 enforces uniqueness via trigger
  FirstName    VARCHAR(50)  NOT NULL,
  LastName     VARCHAR(50)  NOT NULL,
  Nationality  VARCHAR(50),
  DOB          DATE,
  flag         VARCHAR(10)  COMMENT 'Flag emoji',
  PRIMARY KEY (DriverID),
  UNIQUE KEY uq_driver_number (DriverNumber)   -- belt-and-braces alongside T1
) ENGINE=InnoDB;

-- ─────────────────────────────────────────────────────────────────
CREATE TABLE DRIVER_CONTRACT (
  ContractID INT  NOT NULL AUTO_INCREMENT,
  TeamID     INT  NOT NULL,
  DriverID   INT  NOT NULL,
  StartDate  DATE NOT NULL,
  EndDate    DATE              COMMENT 'T2 auto-fills this if left NULL',
  PRIMARY KEY (ContractID),
  CONSTRAINT fk_dc_team   FOREIGN KEY (TeamID)   REFERENCES TEAM   (TeamID)   ON DELETE CASCADE,
  CONSTRAINT fk_dc_driver FOREIGN KEY (DriverID) REFERENCES DRIVER (DriverID) ON DELETE CASCADE
) ENGINE=InnoDB;

-- ─────────────────────────────────────────────────────────────────
CREATE TABLE CAR (
  CarID       INT         NOT NULL AUTO_INCREMENT,
  TeamID      INT         NOT NULL,
  CarNumber   INT,
  ChassisCode VARCHAR(20),
  PRIMARY KEY (CarID),
  CONSTRAINT fk_car_team FOREIGN KEY (TeamID) REFERENCES TEAM (TeamID) ON DELETE CASCADE
) ENGINE=InnoDB;

-- ─────────────────────────────────────────────────────────────────
CREATE TABLE RACE_WEEKEND (
  WeekendID INT          NOT NULL AUTO_INCREMENT,
  CircuitID INT                   COMMENT 'FK to future CIRCUIT table',
  name      VARCHAR(100) NOT NULL,
  circuit   VARCHAR(100),
  StartDate DATE,
  EndDate   DATE,
  flag      VARCHAR(10)  COMMENT 'Country flag emoji',
  PRIMARY KEY (WeekendID)
) ENGINE=InnoDB;

-- ─────────────────────────────────────────────────────────────────
CREATE TABLE SESSION (
  SessionID        INT      NOT NULL AUTO_INCREMENT,
  WeekendID        INT      NOT NULL,
  SessionType      ENUM('Race','Qualifying','Practice 1','Practice 2','Practice 3','Sprint') NOT NULL,
  SessionStartTime DATETIME,
  SessionEndTime   DATETIME,
  PRIMARY KEY (SessionID),
  CONSTRAINT fk_sess_weekend FOREIGN KEY (WeekendID) REFERENCES RACE_WEEKEND (WeekendID) ON DELETE CASCADE
) ENGINE=InnoDB;

-- ─────────────────────────────────────────────────────────────────
CREATE TABLE LAP_TIME (
  LapTimeID INT         NOT NULL AUTO_INCREMENT,
  SessionID INT         NOT NULL,
  DriverID  INT         NOT NULL,
  LapNo     INT         NOT NULL,
  LapTime   VARCHAR(20)          COMMENT 'e.g. 1:23.456',
  Sector1MS INT                  COMMENT 'Sector 1 milliseconds',
  Sector2MS INT                  COMMENT 'Sector 2 milliseconds',
  Sector3MS INT                  COMMENT 'Sector 3 milliseconds',
  PRIMARY KEY (LapTimeID),
  CONSTRAINT fk_lt_session FOREIGN KEY (SessionID) REFERENCES SESSION (SessionID) ON DELETE CASCADE,
  CONSTRAINT fk_lt_driver  FOREIGN KEY (DriverID)  REFERENCES DRIVER  (DriverID) ON DELETE CASCADE
) ENGINE=InnoDB;

-- ─────────────────────────────────────────────────────────────────
CREATE TABLE PIT_STOP (
  PitStopID    INT  NOT NULL AUTO_INCREMENT,
  SessionID    INT  NOT NULL,
  DriverID     INT  NOT NULL,
  PitNo        INT           COMMENT 'Pit stop number in race (1, 2, …)',
  LapNo        INT,
  DurationMS   INT           COMMENT 'Total pit stop duration in milliseconds',
  TyreCompound ENUM('Soft','Medium','Hard','Inter','Wet'),
  PRIMARY KEY (PitStopID),
  CONSTRAINT fk_ps_session FOREIGN KEY (SessionID) REFERENCES SESSION (SessionID) ON DELETE CASCADE,
  CONSTRAINT fk_ps_driver  FOREIGN KEY (DriverID)  REFERENCES DRIVER  (DriverID) ON DELETE CASCADE
) ENGINE=InnoDB;

-- ─────────────────────────────────────────────────────────────────
CREATE TABLE STEWARD (
  StewardID INT          NOT NULL AUTO_INCREMENT,
  Name      VARCHAR(100),
  Roll      VARCHAR(60)  COMMENT 'Steward role / title',
  PRIMARY KEY (StewardID)
) ENGINE=InnoDB;

-- ─────────────────────────────────────────────────────────────────
CREATE TABLE INCIDENT (
  IncidentID  INT      NOT NULL AUTO_INCREMENT,
  SessionID   INT      NOT NULL,
  DriverID    INT               COMMENT 'Primary driver involved (nullable)',
  LapNo       INT,
  Description TEXT,
  Severity    ENUM('Low','Medium','High'),
  PRIMARY KEY (IncidentID),
  CONSTRAINT fk_inc_session FOREIGN KEY (SessionID) REFERENCES SESSION (SessionID) ON DELETE CASCADE,
  CONSTRAINT fk_inc_driver  FOREIGN KEY (DriverID)  REFERENCES DRIVER  (DriverID) ON DELETE SET NULL
) ENGINE=InnoDB;

-- ─────────────────────────────────────────────────────────────────
CREATE TABLE PENALTY (
  PenaltyID   INT NOT NULL AUTO_INCREMENT,
  IncidentID  INT NOT NULL,
  DriverID    INT NOT NULL,
  DescisionID INT           COMMENT 'FK to future STEWARD_DECISION table',
  PenaltyType ENUM('Time Penalty','Grid Penalty','Drive-Through','Stop-Go','DSQ','Reprimand'),
  PenaltyValue VARCHAR(30),
  Status      ENUM('Pending','Applied','Overturned') DEFAULT 'Pending',
  PRIMARY KEY (PenaltyID),
  CONSTRAINT fk_pen_incident FOREIGN KEY (IncidentID) REFERENCES INCIDENT (IncidentID) ON DELETE CASCADE,
  CONSTRAINT fk_pen_driver   FOREIGN KEY (DriverID)   REFERENCES DRIVER   (DriverID)   ON DELETE CASCADE
) ENGINE=InnoDB;


-- ═══════════════════════════════════════════════════════════════════
--  TRIGGERS
-- ═══════════════════════════════════════════════════════════════════

DELIMITER //

-- ── T1: Prevent duplicate DriverNumber (BEFORE INSERT on DRIVER) ──
--   Fires before every INSERT into DRIVER.
--   Raises SQLSTATE 45000 (user-defined error) if the number is taken.
--   The Flask API catches this and returns it as a 400 JSON error so
--   the frontend can display it in the trigger-feedback panel.

CREATE TRIGGER trg_no_duplicate_driver_number
BEFORE INSERT ON DRIVER
FOR EACH ROW
BEGIN
  DECLARE v_count INT DEFAULT 0;
  SELECT COUNT(*) INTO v_count
    FROM DRIVER
   WHERE DriverNumber = NEW.DriverNumber;

  IF v_count > 0 THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'T1 BLOCKED: Driver number already taken — each driver must have a unique race number.';
  END IF;
END //


-- ── T2: Auto-set EndDate to StartDate + 1 year (BEFORE INSERT on DRIVER_CONTRACT) ──
--   Fires before every INSERT into DRIVER_CONTRACT.
--   If EndDate is NULL the trigger calculates it automatically.
--   The Flask API returns the saved row (including the auto-set date)
--   so the frontend can surface "T2 FIRED" feedback to the user.

CREATE TRIGGER trg_auto_contract_end_date
BEFORE INSERT ON DRIVER_CONTRACT
FOR EACH ROW
BEGIN
  IF NEW.EndDate IS NULL THEN
    SET NEW.EndDate = DATE_ADD(NEW.StartDate, INTERVAL 1 YEAR);
  END IF;
END //

DELIMITER ;


-- ═══════════════════════════════════════════════════════════════════
--  SEED DATA
-- ═══════════════════════════════════════════════════════════════════

INSERT INTO TEAM (TeamName, BaseCountry, color, emoji) VALUES
  ('McLaren Formula 1 Team',   'United Kingdom', '#FF8000', '🟠'),
  ('Scuderia Ferrari',          'Italy',          '#E8002D', '🔴'),
  ('Oracle Red Bull Racing',    'Austria',        '#3671C6', '🔵'),
  ('Mercedes-AMG Petronas F1', 'Germany',        '#27F4D2', '🩵'),
  ('Aston Martin Aramco F1',   'United Kingdom', '#00A19C', '🟢'),
  ('BWT Alpine F1 Team',       'France',         '#FF69B4', '🩷');

-- Driver numbers 1,16,44,4,81,63,55,14 — T1 will reject any duplicate
INSERT INTO DRIVER (DriverNumber, FirstName, LastName, Nationality, DOB, flag) VALUES
  (1,  'Max',      'Verstappen', 'Dutch',      '1997-09-30', '🇳🇱'),
  (16, 'Charles',  'Leclerc',    'Monégasque', '1997-10-16', '🇲🇨'),
  (44, 'Lewis',    'Hamilton',   'British',    '1985-01-07', '🇬🇧'),
  (4,  'Lando',    'Norris',     'British',    '1999-11-13', '🇬🇧'),
  (81, 'Oscar',    'Piastri',    'Australian', '2001-04-06', '🇦🇺'),
  (63, 'George',   'Russell',    'British',    '1998-02-15', '🇬🇧'),
  (55, 'Carlos',   'Sainz',      'Spanish',    '1994-09-01', '🇪🇸'),
  (14, 'Fernando', 'Alonso',     'Spanish',    '1981-07-29', '🇪🇸');

-- EndDate supplied here; T2 would auto-fill it if it were NULL
INSERT INTO DRIVER_CONTRACT (TeamID, DriverID, StartDate, EndDate) VALUES
  (3, 1, '2026-01-01', '2027-12-31'),  -- Verstappen → Red Bull
  (2, 2, '2026-01-01', '2027-12-31'),  -- Leclerc    → Ferrari
  (2, 3, '2026-01-01', '2027-12-31'),  -- Hamilton   → Ferrari
  (1, 4, '2026-01-01', '2027-12-31'),  -- Norris     → McLaren
  (1, 5, '2026-01-01', '2027-12-31'),  -- Piastri    → McLaren
  (4, 6, '2026-01-01', '2027-12-31'),  -- Russell    → Mercedes
  (4, 7, '2026-01-01', '2027-12-31'),  -- Sainz      → Mercedes
  (5, 8, '2026-01-01', '2027-12-31');  -- Alonso     → Aston Martin

INSERT INTO CAR (TeamID, CarNumber, ChassisCode) VALUES
  (1, 4,  'MCL62'),
  (1, 81, 'MCL62B'),
  (2, 16, 'SF-26'),
  (2, 44, 'SF-26B'),
  (3, 1,  'RB22'),
  (4, 63, 'W16'),
  (4, 55, 'W16B'),
  (5, 14, 'AMR26');

INSERT INTO RACE_WEEKEND (name, circuit, StartDate, EndDate, flag) VALUES
  ('Australian Grand Prix',    'Albert Park Circuit, Melbourne',     '2026-03-20', '2026-03-22', '🇦🇺'),
  ('Japanese Grand Prix',      'Suzuka International Racing Course', '2026-04-03', '2026-04-05', '🇯🇵'),
  ('Bahrain Grand Prix',       'Bahrain International Circuit',      '2026-04-17', '2026-04-19', '🇧🇭'),
  ('Saudi Arabian Grand Prix', 'Jeddah Corniche Circuit',            '2026-05-01', '2026-05-03', '🇸🇦'),
  ('Miami Grand Prix',         'Miami International Autodrome',      '2026-05-15', '2026-05-17', '🇺🇸'),
  ('Emilia Romagna Grand Prix','Autodromo Enzo e Dino Ferrari',      '2026-05-29', '2026-05-31', '🇮🇹'),
  ('Monaco Grand Prix',        'Circuit de Monaco',                  '2026-06-12', '2026-06-14', '🇲🇨'),
  ('Spanish Grand Prix',       'Circuit de Barcelona-Catalunya',     '2026-06-26', '2026-06-28', '🇪🇸');

INSERT INTO SESSION (WeekendID, SessionType, SessionStartTime, SessionEndTime) VALUES
  (1, 'Race',       '2026-03-22 15:00:00', '2026-03-22 17:05:00'),
  (1, 'Qualifying', '2026-03-21 15:00:00', '2026-03-21 16:00:00'),
  (1, 'Practice 1', '2026-03-20 11:30:00', '2026-03-20 12:30:00');

-- Verstappen lap times (SessionID=1, DriverID=1)
INSERT INTO LAP_TIME (SessionID, DriverID, LapNo, LapTime) VALUES
  (1,1,1,'1:27.543'),(1,1,2,'1:26.891'),(1,1,3,'1:26.234'),
  (1,1,4,'1:25.876'),(1,1,5,'1:25.112'),(1,1,6,'1:24.987'),
  (1,1,7,'1:24.553'),(1,1,8,'1:24.321'),(1,1,9,'1:24.099'),
  (1,1,10,'1:23.876'),
  -- Leclerc
  (1,2,1,'1:27.891'),(1,2,2,'1:27.123'),(1,2,5,'1:25.441'),(1,2,10,'1:24.201'),
  -- Norris
  (1,4,1,'1:28.001'),(1,4,5,'1:25.887'),(1,4,10,'1:24.445');

INSERT INTO PIT_STOP (SessionID, DriverID, PitNo, LapNo, DurationMS, TyreCompound) VALUES
  (1,1,1,18,2341,'Medium'),(1,1,2,42,2198,'Hard'),
  (1,2,1,17,2567,'Medium'),(1,2,2,40,2312,'Hard'),
  (1,4,1,19,2289,'Medium'),(1,4,2,43,2401,'Hard'),
  (1,3,1,20,2556,'Medium'),
  (1,5,1,21,2190,'Soft');

INSERT INTO STEWARD (Name, Roll) VALUES
  ('Derek Warwick',  'Head Steward'),
  ('Garry Connelly', 'FIA Steward'),
  ('Emanuele Pirro', 'Driver Steward');

INSERT INTO INCIDENT (SessionID, LapNo, Description, Severity) VALUES
  (1,12,'Unsafe release from pit lane — Car #44 rejoined unsafely ahead of Car #16','High'),
  (1,28,'Track limits violation at Turn 6 — Car #1 gained lasting advantage','Low'),
  (1,35,'Collision between Car #4 and Car #81 at Turn 3','Medium'),
  (2,3, 'Impeding during qualifying — Car #14 blocked Car #4 in sector 2','Medium');

INSERT INTO PENALTY (IncidentID, DriverID, PenaltyType, PenaltyValue, Status) VALUES
  (1,3,'Time Penalty','5 seconds','Applied'),
  (3,4,'Grid Penalty','3 places', 'Applied'),
  (4,8,'Reprimand',   '—',        'Applied');


-- ═══════════════════════════════════════════════════════════════════
--  VERIFICATION QUERIES (optional — run to confirm setup)
-- ═══════════════════════════════════════════════════════════════════

-- SELECT TABLE_NAME, TABLE_ROWS FROM information_schema.TABLES WHERE TABLE_SCHEMA = 'grand_prix_hub';
-- SELECT TRIGGER_NAME, EVENT_MANIPULATION, EVENT_OBJECT_TABLE, ACTION_TIMING
--   FROM information_schema.TRIGGERS WHERE TRIGGER_SCHEMA = 'grand_prix_hub';
