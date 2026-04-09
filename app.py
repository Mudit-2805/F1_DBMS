"""
Grand Prix Hub — Flask REST API  (Enhanced)
============================================
New in this version
-------------------
1. User-role authentication  (/api/auth/login, /api/auth/logout)
   Roles: viewer · analyst · team_manager · steward · admin

2. N:N transaction endpoints  (/api/txn/*)
   - sign_driver          — DRIVER ↔ TEAM via DRIVER_CONTRACT
   - incident_penalty     — INCIDENT + PENALTY in one atomic write
   - register_weekend     — RACE_WEEKEND + n SESSION rows
   - conflicting_contracts— fires two competing transactions on the
                            same driver (Task 6 conflict demo)

All transaction routes use explicit MySQL BEGIN / COMMIT / ROLLBACK
so the effect is visible in MySQL Workbench in real time.

Install:  pip install flask flask-cors mysql-connector-python
Run:      python app.py
"""

from flask import Flask, jsonify, request, session
from flask_cors import CORS
import mysql.connector
from mysql.connector import Error as MySQLError
from datetime import date, datetime
import time, threading, secrets

app = Flask(__name__)
app.secret_key = secrets.token_hex(32)
CORS(app, supports_credentials=True)

# ── Database config ────────────────────────────────────────────────
DB_CONFIG = {
    "host":     "localhost",
    "user":     "root",
    "password": "MySQL@12345",   # ← change to your MySQL password
    "database": "grand_prix_hub",
    "charset":  "utf8mb4",
}

# ── Resource map ───────────────────────────────────────────────────
RESOURCES = {
    "teams":            ("TEAM",            "TeamID"),
    "drivers":          ("DRIVER",          "DriverID"),
    "driver_contracts": ("DRIVER_CONTRACT", "ContractID"),
    "cars":             ("CAR",             "CarID"),
    "race_weekends":    ("RACE_WEEKEND",    "WeekendID"),
    "sessions":         ("SESSION",         "SessionID"),
    "lap_times":        ("LAP_TIME",        "LapTimeID"),
    "pit_stops":        ("PIT_STOP",        "PitStopID"),
    "stewards":         ("STEWARD",         "StewardID"),
    "incidents":        ("INCIDENT",        "IncidentID"),
    "penalties":        ("PENALTY",         "PenaltyID"),
}

# ── Trigger definitions ────────────────────────────────────────────
TRIGGER_DEFS = {
    1: {
        "name": "trg_no_duplicate_driver_number",
        "sql": """
CREATE TRIGGER trg_no_duplicate_driver_number
BEFORE INSERT ON DRIVER
FOR EACH ROW
BEGIN
  DECLARE v_count INT DEFAULT 0;
  SELECT COUNT(*) INTO v_count FROM DRIVER WHERE DriverNumber = NEW.DriverNumber;
  IF v_count > 0 THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'T1 BLOCKED: Driver number already taken — each driver must have a unique race number.';
  END IF;
END
""",
    },
    2: {
        "name": "trg_auto_contract_end_date",
        "sql": """
CREATE TRIGGER trg_auto_contract_end_date
BEFORE INSERT ON DRIVER_CONTRACT
FOR EACH ROW
BEGIN
  IF NEW.EndDate IS NULL THEN
    SET NEW.EndDate = DATE_ADD(NEW.StartDate, INTERVAL 1 YEAR);
  END IF;
END
""",
    },
    3: {
        "name": "trg_no_duplicate_contract",
        "sql": """
CREATE TRIGGER trg_no_duplicate_contract
BEFORE INSERT ON DRIVER_CONTRACT
FOR EACH ROW
BEGIN
  DECLARE v_count INT DEFAULT 0;
  SELECT COUNT(*) INTO v_count
    FROM DRIVER_CONTRACT
   WHERE DriverID = NEW.DriverID;
  IF v_count > 0 THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'T3 BLOCKED: Driver already has an active contract — release them first before reassigning.';
  END IF;
END
""",
    },
    4: {
        "name": "trg_protect_active_contract",
        "sql": """
CREATE TRIGGER trg_protect_active_contract
BEFORE UPDATE ON DRIVER_CONTRACT
FOR EACH ROW
BEGIN
  IF OLD.EndDate >= CURDATE() THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'T4 BLOCKED: Contract is currently active and cannot be modified. Wait until the contract expires or remove it first.';
  END IF;
END
""",
    },
}

# ── User role definitions ──────────────────────────────────────────
USER_ACCOUNTS = {
    "viewer":       {"password": None,          "role": "viewer"},
    "analyst":      {"password": "analyst123",  "role": "analyst"},
    "team_manager": {"password": "team123",     "role": "team_manager"},
    "steward":      {"password": "steward123",  "role": "steward"},
    "admin":        {"password": "admin123",    "role": "admin"},
}

ROLE_PERMISSIONS = {
    "viewer":       {"can_read": True,  "can_write": False, "can_transact": False, "can_admin": False},
    "analyst":      {"can_read": True,  "can_write": False, "can_transact": False, "can_admin": False},
    "team_manager": {"can_read": True,  "can_write": True,  "can_transact": True,  "can_admin": False},
    "steward":      {"can_read": True,  "can_write": True,  "can_transact": True,  "can_admin": False},
    "admin":        {"can_read": True,  "can_write": True,  "can_transact": True,  "can_admin": True},
}


# ═══════════════════════════════════════════════════════════════════
#  HELPERS
# ═══════════════════════════════════════════════════════════════════

def get_db():
    return mysql.connector.connect(**DB_CONFIG)


def serialize(obj):
    if isinstance(obj, dict):
        return {k: serialize(v) for k, v in obj.items()}
    if isinstance(obj, list):
        return [serialize(item) for item in obj]
    if isinstance(obj, (date, datetime)):
        return obj.isoformat()
    return obj


def mysql_error_msg(exc):
    return getattr(exc, "msg", str(exc))


def step(n, msg, status="ok"):
    """Build a transaction step object for the frontend log."""
    return {"step": n, "status": status, "msg": msg,
            "ts": datetime.now().strftime("%H:%M:%S.%f")[:-3]}


# ═══════════════════════════════════════════════════════════════════
#  AUTH ROUTES
# ═══════════════════════════════════════════════════════════════════

@app.route("/api/auth/login", methods=["POST"])
def auth_login():
    data = request.json or {}
    username = data.get("username", "").strip().lower()
    password = data.get("password", "")

    account = USER_ACCOUNTS.get(username)
    if not account:
        return jsonify({"error": "Unknown user"}), 401

    # viewer has no password
    if account["password"] and account["password"] != password:
        return jsonify({"error": "Invalid credentials"}), 401

    session["user"]  = username
    session["role"]  = account["role"]
    perms = ROLE_PERMISSIONS[account["role"]]
    return jsonify({
        "success":     True,
        "user":        username,
        "role":        account["role"],
        "permissions": perms,
    })


@app.route("/api/auth/logout", methods=["POST"])
def auth_logout():
    session.clear()
    return jsonify({"success": True})


@app.route("/api/auth/me", methods=["GET"])
def auth_me():
    user = session.get("user", "viewer")
    role = session.get("role", "viewer")
    return jsonify({
        "user":        user,
        "role":        role,
        "permissions": ROLE_PERMISSIONS.get(role, ROLE_PERMISSIONS["viewer"]),
    })


# ═══════════════════════════════════════════════════════════════════
#  GENERIC CRUD ROUTES
# ═══════════════════════════════════════════════════════════════════

@app.route("/api/<resource>", methods=["GET"])
def get_all(resource):
    if resource not in RESOURCES:
        return jsonify({"error": "Unknown resource"}), 404
    table, pk = RESOURCES[resource]
    try:
        conn = get_db()
        cur  = conn.cursor(dictionary=True)
        cur.execute(f"SELECT * FROM `{table}` ORDER BY `{pk}`")
        rows = cur.fetchall()
        conn.close()
        return jsonify(serialize(rows))
    except MySQLError as exc:
        return jsonify({"error": mysql_error_msg(exc)}), 500


@app.route("/api/<resource>/<int:row_id>", methods=["GET"])
def get_one(resource, row_id):
    if resource not in RESOURCES:
        return jsonify({"error": "Unknown resource"}), 404
    table, pk = RESOURCES[resource]
    try:
        conn = get_db()
        cur  = conn.cursor(dictionary=True)
        cur.execute(f"SELECT * FROM `{table}` WHERE `{pk}` = %s", (row_id,))
        row = cur.fetchone()
        conn.close()
        if row is None:
            return jsonify({"error": "Not found"}), 404
        return jsonify(serialize(row))
    except MySQLError as exc:
        return jsonify({"error": mysql_error_msg(exc)}), 500


@app.route("/api/<resource>", methods=["POST"])
def create(resource):
    if resource not in RESOURCES:
        return jsonify({"error": "Unknown resource"}), 404
    table, pk = RESOURCES[resource]
    data = {k: v for k, v in (request.json or {}).items() if v not in ("", None) or k == "EndDate"}
    data.pop(pk, None)
    data.pop("__key", None)
    data = {k: (None if v == "" else v) for k, v in data.items()}
    if not data:
        return jsonify({"error": "No data provided"}), 400
    cols         = ", ".join(f"`{k}`" for k in data)
    placeholders = ", ".join("%s" for _ in data)
    vals         = list(data.values())
    try:
        conn = get_db()
        cur  = conn.cursor(dictionary=True)
        cur.execute(f"INSERT INTO `{table}` ({cols}) VALUES ({placeholders})", vals)
        new_id = cur.lastrowid
        conn.commit()
        cur.execute(f"SELECT * FROM `{table}` WHERE `{pk}` = %s", (new_id,))
        saved_row = cur.fetchone()
        conn.close()
        t2_fired = (
            resource == "driver_contracts"
            and data.get("EndDate") is None
            and saved_row is not None
            and saved_row.get("EndDate") is not None
        )
        return jsonify({"success": True, "id": new_id, "row": serialize(saved_row), "t2_fired": t2_fired}), 201
    except MySQLError as exc:
        return jsonify({"error": mysql_error_msg(exc)}), 400


@app.route("/api/<resource>/<int:row_id>", methods=["PUT"])
def update(resource, row_id):
    """Update an existing row by primary key."""
    if resource not in RESOURCES:
        return jsonify({"error": "Unknown resource"}), 404
    table, pk = RESOURCES[resource]
    data = request.json or {}
    data.pop(pk, None)
    data.pop("__key", None)
    data = {k: (None if v == "" else v) for k, v in data.items()}
    if not data:
        return jsonify({"error": "No data provided"}), 400

    # Block updates on active driver contracts
    if resource == "driver_contracts":
        try:
            conn_chk = get_db()
            cur_chk  = conn_chk.cursor(dictionary=True)
            cur_chk.execute(
                "SELECT EndDate, CASE WHEN EndDate >= CURDATE() THEN 1 ELSE 0 END AS is_active "
                "FROM DRIVER_CONTRACT WHERE ContractID = %s", (row_id,)
            )
            chk = cur_chk.fetchone()
            conn_chk.close()
            if chk and chk.get("is_active"):
                return jsonify({
                    "error": f"BLOCKED: This contract is ACTIVE until {chk['EndDate']}. "
                             f"Active contracts cannot be modified. "
                             f"Wait for it to expire or delete it first."
                }), 403
        except MySQLError:
            pass

    set_clause = ", ".join(f"`{k}` = %s" for k in data)
    vals = list(data.values()) + [row_id]
    try:
        conn = get_db()
        cur  = conn.cursor()
        cur.execute(f"UPDATE `{table}` SET {set_clause} WHERE `{pk}` = %s", vals)
        conn.commit()
        conn.close()
        return jsonify({"success": True})
    except MySQLError as exc:
        return jsonify({"error": mysql_error_msg(exc)}), 400


def delete(resource, row_id):
    """Delete a row by primary key."""
    if resource not in RESOURCES:
        return jsonify({"error": "Unknown resource"}), 404
    table, pk = RESOURCES[resource]

    # Block deletion of active driver contracts
    if resource == "driver_contracts":
        try:
            conn_chk = get_db()
            cur_chk  = conn_chk.cursor(dictionary=True)
            cur_chk.execute(
                "SELECT EndDate, CASE WHEN EndDate >= CURDATE() THEN 1 ELSE 0 END AS is_active "
                "FROM DRIVER_CONTRACT WHERE ContractID = %s", (row_id,)
            )
            chk = cur_chk.fetchone()
            conn_chk.close()
            if chk and chk.get("is_active"):
                return jsonify({
                    "error": f"BLOCKED: This contract is ACTIVE until {chk['EndDate']}. "
                             f"Active contracts cannot be deleted. "
                             f"The contract must expire before removal."
                }), 403
        except MySQLError:
            pass

    try:
        conn = get_db()
        cur  = conn.cursor()
        cur.execute(f"DELETE FROM `{table}` WHERE `{pk}` = %s", (row_id,))
        conn.commit()
        conn.close()
        return jsonify({"success": True})
    except MySQLError as exc:
        return jsonify({"error": mysql_error_msg(exc)}), 400



# ═══════════════════════════════════════════════════════════════════
#  TRIGGER MANAGEMENT
# ═══════════════════════════════════════════════════════════════════

@app.route("/api/triggers/status", methods=["GET"])
def trigger_status():
    try:
        conn = get_db()
        cur  = conn.cursor()
        statuses = {}
        for t in TRIGGER_DEFS.values():
            cur.execute(
                "SELECT COUNT(*) FROM information_schema.TRIGGERS "
                "WHERE TRIGGER_NAME = %s AND TRIGGER_SCHEMA = %s",
                (t["name"], DB_CONFIG["database"]),
            )
            statuses[t["name"]] = cur.fetchone()[0] > 0
        conn.close()
        return jsonify(statuses)
    except MySQLError as exc:
        return jsonify({"error": mysql_error_msg(exc)}), 500


@app.route("/api/triggers/<int:trigger_num>/toggle", methods=["POST"])
def toggle_trigger(trigger_num):
    if trigger_num not in TRIGGER_DEFS:
        return jsonify({"error": "Unknown trigger number"}), 404
    t = TRIGGER_DEFS[trigger_num]
    try:
        conn = get_db()
        cur  = conn.cursor()
        cur.execute(
            "SELECT COUNT(*) FROM information_schema.TRIGGERS "
            "WHERE TRIGGER_NAME = %s AND TRIGGER_SCHEMA = %s",
            (t["name"], DB_CONFIG["database"]),
        )
        currently_enabled = cur.fetchone()[0] > 0
        if currently_enabled:
            cur.execute(f"DROP TRIGGER IF EXISTS `{t['name']}`")
            enabled = False
        else:
            cur.execute(t["sql"])
            enabled = True
        conn.commit()
        conn.close()
        return jsonify({"success": True, "enabled": enabled, "trigger": t["name"]})
    except MySQLError as exc:
        return jsonify({"error": mysql_error_msg(exc)}), 500


# ═══════════════════════════════════════════════════════════════════
#  TRANSACTION ROUTES  (Task 6 — real MySQL BEGIN/COMMIT/ROLLBACK)
# ═══════════════════════════════════════════════════════════════════

@app.route("/api/txn/sign_driver", methods=["POST"])
def txn_sign_driver():
    """
    TXN 1 — Sign a driver to a team  (N:N: DRIVER ↔ TEAM via DRIVER_CONTRACT)
    --------------------------------------------------------------------------
    Steps executed inside a single MySQL transaction:
      1. SELECT … FOR UPDATE on DRIVER row  (row-level lock)
      2. SELECT … FOR UPDATE on TEAM row
      3. DELETE existing DRIVER_CONTRACT for this driver
      4. INSERT new DRIVER_CONTRACT  (may fire Trigger T2 if EndDate is NULL)
      5. COMMIT
    On any error → ROLLBACK and return the partial step log.
    """
    d = request.json or {}
    driver_id  = d.get("driver_id")
    team_id    = d.get("team_id")
    start_date = d.get("start_date")
    end_date   = d.get("end_date")   # may be None → T2 auto-fills

    steps = []
    conn  = get_db()
    cur   = conn.cursor(dictionary=True)

    try:
        conn.start_transaction(isolation_level="REPEATABLE READ")
        steps.append(step(0, "BEGIN TRANSACTION (REPEATABLE READ isolation)"))

        # Step 1 — lock driver row
        cur.execute("SELECT * FROM DRIVER WHERE DriverID = %s FOR UPDATE", (driver_id,))
        driver = cur.fetchone()
        if not driver:
            raise ValueError(f"DriverID={driver_id} not found in DRIVER table")
        steps.append(step(1, f"SELECT … FOR UPDATE: Driver #{driver['DriverNumber']} "
                             f"{driver['FirstName']} {driver['LastName']} — lock acquired"))

        # Step 2 — lock team row
        cur.execute("SELECT * FROM TEAM WHERE TeamID = %s FOR UPDATE", (team_id,))
        team = cur.fetchone()
        if not team:
            raise ValueError(f"TeamID={team_id} not found in TEAM table")
        steps.append(step(2, f"SELECT … FOR UPDATE: Team '{team['TeamName']}' — lock acquired"))

        # Step 3 — check if existing contract is still active
        cur.execute(
            "SELECT ContractID, EndDate, "
            "CASE WHEN EndDate >= CURDATE() THEN 1 ELSE 0 END AS is_active "
            "FROM DRIVER_CONTRACT WHERE DriverID = %s ORDER BY ContractID DESC LIMIT 1",
            (driver_id,)
        )
        existing = cur.fetchone()
        if existing and existing.get("is_active"):
            end_d = existing["EndDate"]
            raise ValueError(
                f"BLOCKED: Driver #{driver_id} has an ACTIVE contract until {end_d}. "
                f"Active contracts cannot be overridden. Wait for it to expire or remove it first."
            )
        steps.append(step(3, f"Contract status check — {'no active contract, proceeding' if not existing else 'contract expired, proceeding'}"))

        # Step 4 — delete existing (expired) contracts for this driver
        cur.execute("DELETE FROM DRIVER_CONTRACT WHERE DriverID = %s", (driver_id,))
        deleted = cur.rowcount
        steps.append(step(4, f"DELETE FROM DRIVER_CONTRACT WHERE DriverID={driver_id} "
                             f"— {deleted} row(s) removed"))

        # Step 5 — insert new contract
        cur.execute(
            "INSERT INTO DRIVER_CONTRACT (DriverID, TeamID, StartDate, EndDate) "
            "VALUES (%s, %s, %s, %s)",
            (driver_id, team_id, start_date, end_date),
        )
        new_id = cur.lastrowid

        # Fetch saved row to capture any T2-auto-filled EndDate
        cur.execute("SELECT * FROM DRIVER_CONTRACT WHERE ContractID = %s", (new_id,))
        saved = serialize(cur.fetchone())
        t2_fired = end_date is None and saved and saved.get("EndDate") is not None
        steps.append(step(5, f"INSERT DRIVER_CONTRACT #{new_id}: "
                             f"DriverID={driver_id} → TeamID={team_id}, "
                             f"EndDate={saved.get('EndDate')}"
                             + (" [T2 fired: EndDate auto-set]" if t2_fired else "")))

        conn.commit()
        steps.append(step(6, "COMMIT — all changes persisted to MySQL"))

        return jsonify({
            "success":   True,
            "steps":     steps,
            "contract":  saved,
            "t2_fired":  t2_fired,
        })

    except (MySQLError, ValueError) as exc:
        conn.rollback()
        msg = mysql_error_msg(exc) if isinstance(exc, MySQLError) else str(exc)
        steps.append(step(len(steps), f"ROLLBACK — {msg}", status="error"))
        return jsonify({"success": False, "error": msg, "steps": steps, "rolled_back": True}), 400
    finally:
        conn.close()


@app.route("/api/txn/incident_penalty", methods=["POST"])
def txn_incident_penalty():
    """
    TXN 2 — Raise an incident and issue a penalty atomically
    ---------------------------------------------------------
    N:N relationship: INCIDENT ↔ DRIVER (one driver per incident, but
    a driver can have many incidents) and INCIDENT → PENALTY → DRIVER.

    Steps:
      1. Validate SESSION exists
      2. Validate DRIVER exists
      3. INSERT INCIDENT
      4. INSERT PENALTY (linked to new IncidentID)
      5. COMMIT
    Optional: pass force_fail=true to simulate a crash after step 3,
    proving the INCIDENT insert is rolled back too.
    """
    d          = request.json or {}
    session_id = d.get("session_id")
    driver_id  = d.get("driver_id")
    lap_no     = d.get("lap_no", 1)
    severity   = d.get("severity", "Medium")
    description= d.get("description", "Race incident")
    pen_type   = d.get("penalty_type", "Reprimand")
    pen_value  = d.get("penalty_value", "—")
    force_fail = d.get("force_fail", False)

    steps = []
    conn  = get_db()
    cur   = conn.cursor(dictionary=True)

    try:
        conn.start_transaction()
        steps.append(step(0, "BEGIN TRANSACTION"))

        # Step 1
        cur.execute("SELECT SessionID, SessionType FROM SESSION WHERE SessionID = %s", (session_id,))
        sess = cur.fetchone()
        if not sess:
            raise ValueError(f"SessionID={session_id} not found")
        steps.append(step(1, f"Validated SESSION #{session_id} ({sess['SessionType']})"))

        # Step 2
        cur.execute("SELECT DriverID, FirstName, LastName FROM DRIVER WHERE DriverID = %s", (driver_id,))
        drv = cur.fetchone()
        if not drv:
            raise ValueError(f"DriverID={driver_id} not found")
        steps.append(step(2, f"Validated DRIVER: {drv['FirstName']} {drv['LastName']}"))

        # Step 3
        cur.execute(
            "INSERT INTO INCIDENT (SessionID, DriverID, LapNo, Description, Severity) "
            "VALUES (%s, %s, %s, %s, %s)",
            (session_id, driver_id, lap_no, description, severity),
        )
        incident_id = cur.lastrowid
        steps.append(step(3, f"INSERT INCIDENT #{incident_id}: Lap {lap_no}, Severity={severity}"))

        # Simulate crash after step 3 to demonstrate rollback
        if force_fail:
            raise RuntimeError(
                "Simulated failure after INCIDENT insert — "
                "ROLLBACK will undo the INCIDENT row too (atomicity guaranteed)"
            )

        # Step 4
        cur.execute(
            "INSERT INTO PENALTY (IncidentID, DriverID, PenaltyType, PenaltyValue, Status) "
            "VALUES (%s, %s, %s, %s, 'Applied')",
            (incident_id, driver_id, pen_type, pen_value),
        )
        penalty_id = cur.lastrowid
        steps.append(step(4, f"INSERT PENALTY #{penalty_id}: {pen_type} ({pen_value}) "
                             f"linked to INCIDENT #{incident_id}"))

        conn.commit()
        steps.append(step(5, "COMMIT — INCIDENT + PENALTY both persisted"))

        return jsonify({"success": True, "steps": steps,
                        "incident_id": incident_id, "penalty_id": penalty_id})

    except (MySQLError, ValueError, RuntimeError) as exc:
        conn.rollback()
        msg = mysql_error_msg(exc) if isinstance(exc, MySQLError) else str(exc)
        steps.append(step(len(steps), f"ROLLBACK — {msg}", status="error"))
        return jsonify({"success": False, "error": msg, "steps": steps, "rolled_back": True}), 400
    finally:
        conn.close()


@app.route("/api/txn/register_weekend", methods=["POST"])
def txn_register_weekend():
    """
    TXN 3 — Register a new race weekend with all its sessions
    ----------------------------------------------------------
    Steps:
      1. Check no duplicate race name exists
      2. INSERT RACE_WEEKEND
      3. INSERT each SESSION row (one per session type selected)
      4. COMMIT
    force_fail=true simulates a crash after the RACE_WEEKEND insert,
    proving the session rows and the weekend itself are all rolled back.
    """
    d              = request.json or {}
    name           = d.get("name", "").strip()
    circuit        = d.get("circuit", "").strip()
    flag           = d.get("flag", "🏁")
    start_date     = d.get("start_date")
    end_date       = d.get("end_date")
    session_types  = d.get("session_types", [])   # list of strings
    force_fail     = d.get("force_fail", False)

    if not name or not circuit or not start_date or not end_date:
        return jsonify({"error": "name, circuit, start_date, end_date are required"}), 400

    steps = []
    conn  = get_db()
    cur   = conn.cursor(dictionary=True)

    try:
        conn.start_transaction()
        steps.append(step(0, "BEGIN TRANSACTION"))

        # Step 1 — duplicate check
        cur.execute("SELECT WeekendID FROM RACE_WEEKEND WHERE name = %s", (name,))
        if cur.fetchone():
            raise ValueError(f"Race weekend '{name}' already exists in RACE_WEEKEND")
        steps.append(step(1, f"No duplicate found — '{name}' is unique"))

        # Step 2 — insert weekend
        cur.execute(
            "INSERT INTO RACE_WEEKEND (name, circuit, StartDate, EndDate, flag) "
            "VALUES (%s, %s, %s, %s, %s)",
            (name, circuit, start_date, end_date, flag),
        )
        weekend_id = cur.lastrowid
        steps.append(step(2, f"INSERT RACE_WEEKEND #{weekend_id}: '{name}' at {circuit}"))

        if force_fail:
            raise RuntimeError(
                "Simulated failure after RACE_WEEKEND insert — "
                "ROLLBACK undoes the weekend and prevents orphaned sessions"
            )

        # Step 3 — insert sessions
        inserted_sessions = []
        for i, stype in enumerate(session_types):
            cur.execute(
                "INSERT INTO SESSION (WeekendID, SessionType, SessionStartTime, SessionEndTime) "
                "VALUES (%s, %s, %s, %s)",
                (weekend_id, stype,
                 f"{start_date} 10:00:00", f"{start_date} 11:30:00"),
            )
            sid = cur.lastrowid
            inserted_sessions.append(sid)
            steps.append(step(3 + i, f"INSERT SESSION #{sid}: {stype} for Weekend #{weekend_id}"))

        conn.commit()
        steps.append(step(3 + len(session_types),
                          f"COMMIT — 1 weekend + {len(session_types)} sessions persisted"))

        return jsonify({
            "success":    True,
            "steps":      steps,
            "weekend_id": weekend_id,
            "session_ids": inserted_sessions,
        })

    except (MySQLError, ValueError, RuntimeError) as exc:
        conn.rollback()
        msg = mysql_error_msg(exc) if isinstance(exc, MySQLError) else str(exc)
        steps.append(step(len(steps), f"ROLLBACK — {msg}", status="error"))
        return jsonify({"success": False, "error": msg, "steps": steps, "rolled_back": True}), 400
    finally:
        conn.close()


@app.route("/api/txn/conflicting_contracts", methods=["POST"])
def txn_conflicting_contracts():
    """
    TXN 4 — Conflict demo  (Task 6: conflicting transactions)
    ----------------------------------------------------------
    Launches two real MySQL transactions in separate threads, both
    trying to sign the SAME driver to different teams at the same time.

    Transaction A:
      - SELECT … FOR UPDATE on the driver row  → acquires row lock
      - Sleeps 1 s (simulating slow processing) so TXN B can arrive
      - Deletes old contract, inserts Team A contract
      - COMMITs

    Transaction B (fires ~100 ms after A):
      - SELECT … FOR UPDATE on the SAME driver row
      - BLOCKS because TXN A holds the lock
      - Once A commits the lock releases, B reads the now-updated row
      - B then tries to DELETE old contract (already replaced by A)
        and INSERT its own contract — succeeds or fails based on
        business logic (we raise an error if the driver is already
        on a team)

    The response includes step logs for both transactions, showing
    exactly when locks were acquired, when B was blocked, and who won.
    """
    d         = request.json or {}
    driver_id = d.get("driver_id")
    team_a_id = d.get("team_a_id")
    team_b_id = d.get("team_b_id")

    if team_a_id == team_b_id:
        return jsonify({"error": "team_a_id and team_b_id must be different"}), 400

    results = {"A": {"steps": [], "success": None}, "B": {"steps": [], "success": None}}
    errors  = {}

    def run_txn(label, team_id, delay_before_lock=0, sleep_after_lock=0):
        steps_local = []
        conn = get_db()
        cur  = conn.cursor(dictionary=True)
        try:
            time.sleep(delay_before_lock)
            conn.start_transaction(isolation_level="REPEATABLE READ")
            steps_local.append(step(0, f"[TXN {label}] BEGIN TRANSACTION"))

            steps_local.append(step(1, f"[TXN {label}] SELECT … FOR UPDATE on DRIVER #{driver_id} — waiting for lock…"))
            cur.execute("SELECT * FROM DRIVER WHERE DriverID = %s FOR UPDATE", (driver_id,))
            driver = cur.fetchone()
            if not driver:
                raise ValueError(f"Driver #{driver_id} not found")
            steps_local.append(step(2, f"[TXN {label}] Lock ACQUIRED on driver {driver['LastName']}"))

            if sleep_after_lock > 0:
                steps_local.append(step(3, f"[TXN {label}] Simulating slow processing ({sleep_after_lock}s) — lock held"))
                time.sleep(sleep_after_lock)

            # Check current team
            cur.execute("SELECT * FROM DRIVER_CONTRACT WHERE DriverID = %s FOR UPDATE", (driver_id,))
            existing = cur.fetchone()
            if existing and existing["TeamID"] == team_id:
                raise ValueError(f"[TXN {label}] Driver already signed to this team (TeamID={team_id})")

            cur.execute("DELETE FROM DRIVER_CONTRACT WHERE DriverID = %s", (driver_id,))
            deleted = cur.rowcount
            steps_local.append(step(4, f"[TXN {label}] DELETE {deleted} old contract(s)"))

            cur.execute(
                "INSERT INTO DRIVER_CONTRACT (DriverID, TeamID, StartDate, EndDate) "
                "VALUES (%s, %s, '2026-01-01', '2027-12-31')",
                (driver_id, team_id),
            )
            new_id = cur.lastrowid
            steps_local.append(step(5, f"[TXN {label}] INSERT DRIVER_CONTRACT #{new_id}: Team {team_id}"))

            conn.commit()
            steps_local.append(step(6, f"[TXN {label}] COMMIT — Team {team_id} wins the signing!"))
            results[label]["steps"]   = steps_local
            results[label]["success"] = True

        except (MySQLError, ValueError) as exc:
            try:
                conn.rollback()
            except Exception:
                pass
            msg = mysql_error_msg(exc) if isinstance(exc, MySQLError) else str(exc)
            steps_local.append(step(len(steps_local), f"[TXN {label}] ROLLBACK — {msg}", status="error"))
            results[label]["steps"]   = steps_local
            results[label]["success"] = False
            errors[label]             = msg
        finally:
            conn.close()

    # Fire both threads — A gets a 1-second head start on the lock
    thread_a = threading.Thread(target=run_txn, args=("A", team_a_id, 0, 1.2))
    thread_b = threading.Thread(target=run_txn, args=("B", team_b_id, 0.1, 0))

    thread_a.start()
    thread_b.start()
    thread_a.join()
    thread_b.join()

    winner = "A" if results["A"]["success"] else ("B" if results["B"]["success"] else None)
    return jsonify({
        "success":  True,
        "winner":   winner,
        "txn_a":    results["A"],
        "txn_b":    results["B"],
        "errors":   errors,
        "summary":  (
            f"TXN A (Team {team_a_id}) won — TXN B (Team {team_b_id}) was blocked then rolled back"
            if winner == "A" else
            f"TXN B (Team {team_b_id}) won — TXN A (Team {team_a_id}) rolled back"
            if winner == "B" else
            "Both transactions rolled back"
        ),
    })


# ═══════════════════════════════════════════════════════════════════
#  ANALYTICS ROUTES  (for Analyst / Steward dashboards)
# ═══════════════════════════════════════════════════════════════════

@app.route("/api/analytics/summary", methods=["GET"])
def analytics_summary():
    """Aggregate stats for the Analyst dashboard."""
    try:
        conn = get_db()
        cur  = conn.cursor(dictionary=True)

        queries = {
            "total_drivers":    "SELECT COUNT(*) AS v FROM DRIVER",
            "total_teams":      "SELECT COUNT(*) AS v FROM TEAM",
            "total_laps":       "SELECT COUNT(*) AS v FROM LAP_TIME",
            "total_pit_stops":  "SELECT COUNT(*) AS v FROM PIT_STOP",
            "total_incidents":  "SELECT COUNT(*) AS v FROM INCIDENT",
            "total_penalties":  "SELECT COUNT(*) AS v FROM PENALTY",
            "fastest_lap":      "SELECT MIN(LapTime) AS v FROM LAP_TIME",
            "fastest_pit_ms":   "SELECT MIN(DurationMS) AS v FROM PIT_STOP",
        }
        summary = {}
        for key, sql in queries.items():
            cur.execute(sql)
            row = cur.fetchone()
            summary[key] = row["v"] if row else None

        # Pit stop ranking
        cur.execute("""
            SELECT d.DriverID, d.FirstName, d.LastName, d.flag,
                   MIN(p.DurationMS) AS best_ms
            FROM PIT_STOP p
            JOIN DRIVER d ON d.DriverID = p.DriverID
            GROUP BY d.DriverID
            ORDER BY best_ms
        """)
        summary["pit_ranking"] = serialize(cur.fetchall())

        # Incident severity breakdown
        cur.execute("""
            SELECT Severity, COUNT(*) AS cnt
            FROM INCIDENT
            GROUP BY Severity
        """)
        summary["incident_severity"] = serialize(cur.fetchall())

        conn.close()
        return jsonify(summary)
    except MySQLError as exc:
        return jsonify({"error": mysql_error_msg(exc)}), 500


# ═══════════════════════════════════════════════════════════════════
#  HEALTH CHECK
# ═══════════════════════════════════════════════════════════════════


@app.route("/api/contracts/status/<int:driver_id>", methods=["GET"])
def contract_status(driver_id):
    """
    Returns the active contract status for a driver.
    active: true  — EndDate >= today, contract is live, changes blocked
    active: false — no contract or EndDate < today, changes allowed
    """
    try:
        conn = get_db()
        cur  = conn.cursor(dictionary=True)
        cur.execute("""
            SELECT ContractID, TeamID, StartDate, EndDate,
                   CASE WHEN EndDate >= CURDATE() THEN 1 ELSE 0 END AS is_active,
                   DATEDIFF(EndDate, CURDATE()) AS days_remaining
            FROM DRIVER_CONTRACT
            WHERE DriverID = %s
            ORDER BY ContractID DESC
            LIMIT 1
        """, (driver_id,))
        row = cur.fetchone()
        conn.close()
        if not row:
            return jsonify({"has_contract": False, "active": False, "message": "No contract found — driver is free to sign"})
        is_active = bool(row["is_active"])
        days = row["days_remaining"] or 0
        return jsonify({
            "has_contract":   True,
            "active":         is_active,
            "contract_id":    row["ContractID"],
            "team_id":        row["TeamID"],
            "start_date":     serialize(row["StartDate"]),
            "end_date":       serialize(row["EndDate"]),
            "days_remaining": days,
            "message": (
                f"Contract ACTIVE — {days} day(s) remaining. Modifications blocked."
                if is_active else
                f"Contract EXPIRED — ended {abs(days)} day(s) ago. New contract can be created."
            )
        })
    except MySQLError as exc:
        return jsonify({"error": mysql_error_msg(exc)}), 500


@app.route("/api/contracts/all_status", methods=["GET"])
def all_contract_status():
    """Returns active/expired status for all drivers with contracts."""
    try:
        conn = get_db()
        cur  = conn.cursor(dictionary=True)
        cur.execute("""
            SELECT dc.ContractID, dc.DriverID, dc.TeamID,
                   d.FirstName, d.LastName, d.DriverNumber, d.flag,
                   t.TeamName, t.color,
                   dc.StartDate, dc.EndDate,
                   CASE WHEN dc.EndDate >= CURDATE() THEN 1 ELSE 0 END AS is_active,
                   DATEDIFF(dc.EndDate, CURDATE()) AS days_remaining
            FROM DRIVER_CONTRACT dc
            JOIN DRIVER d ON d.DriverID = dc.DriverID
            JOIN TEAM   t ON t.TeamID   = dc.TeamID
            ORDER BY dc.DriverID
        """)
        rows = cur.fetchall()
        conn.close()
        return jsonify(serialize(rows))
    except MySQLError as exc:
        return jsonify({"error": mysql_error_msg(exc)}), 500


@app.route("/api/health", methods=["GET"])
def health():
    try:
        conn = get_db()
        cur  = conn.cursor()
        cur.execute("SELECT 1")
        conn.close()
        return jsonify({"status": "ok", "database": DB_CONFIG["database"]})
    except MySQLError as exc:
        return jsonify({"status": "error", "error": mysql_error_msg(exc)}), 500


# ═══════════════════════════════════════════════════════════════════
#  ENTRY POINT
# ═══════════════════════════════════════════════════════════════════

if __name__ == "__main__":
    print("=" * 60)
    print("  Grand Prix Hub API  —  http://localhost:5000")
    print("  Roles:   viewer | analyst | team_manager | steward | admin")
    print("  TXN:     POST /api/txn/sign_driver")
    print("           POST /api/txn/incident_penalty")
    print("           POST /api/txn/register_weekend")
    print("           POST /api/txn/conflicting_contracts  ← Task 6")
    print("=" * 60)
    app.run(debug=True, port=5000)
