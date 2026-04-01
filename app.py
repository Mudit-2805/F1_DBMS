"""
Grand Prix Hub — Flask REST API
================================
Install deps:  pip install flask flask-cors mysql-connector-python

Set your MySQL password in DB_CONFIG below, then run:
    python app.py

The API will be available at http://localhost:5000
"""

from flask import Flask, jsonify, request
from flask_cors import CORS
import mysql.connector
from mysql.connector import Error as MySQLError
from datetime import date, datetime

app = Flask(__name__)
CORS(app)  # Allow the HTML file to call the API from any origin

# ── Database config — change password to match your MySQL Workbench setup ──
DB_CONFIG = {
    "host":     "localhost",
    "user":     "root",
    "password": "MySQL@12345",   # ← change this
    "database": "grand_prix_hub",
    "charset":  "utf8mb4",
}

# ── Resource map: URL slug → (table name, primary key column) ──────────────
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

# Trigger definitions (used by the toggle endpoint to DROP / re-CREATE)
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
}


# ═══════════════════════════════════════════════════════════════════
#  HELPERS
# ═══════════════════════════════════════════════════════════════════

def get_db():
    """Open a new MySQL connection."""
    return mysql.connector.connect(**DB_CONFIG)


def serialize(obj):
    """Recursively convert date/datetime objects to ISO strings for JSON."""
    if isinstance(obj, dict):
        return {k: serialize(v) for k, v in obj.items()}
    if isinstance(obj, list):
        return [serialize(item) for item in obj]
    if isinstance(obj, (date, datetime)):
        return obj.isoformat()
    return obj


def mysql_error_msg(exc):
    """Extract a clean message from a MySQLError."""
    # Trigger SIGNAL messages live in exc.msg
    return getattr(exc, "msg", str(exc))


# ═══════════════════════════════════════════════════════════════════
#  GENERIC CRUD ROUTES  /api/<resource>
# ═══════════════════════════════════════════════════════════════════

@app.route("/api/<resource>", methods=["GET"])
def get_all(resource):
    """Return every row from <resource> ordered by primary key."""
    if resource not in RESOURCES:
        return jsonify({"error": "Unknown resource"}), 404

    table, pk = RESOURCES[resource]
    try:
        conn = get_db()
        cur = conn.cursor(dictionary=True)
        cur.execute(f"SELECT * FROM `{table}` ORDER BY `{pk}`")
        rows = cur.fetchall()
        conn.close()
        return jsonify(serialize(rows))
    except MySQLError as exc:
        return jsonify({"error": mysql_error_msg(exc)}), 500


@app.route("/api/<resource>/<int:row_id>", methods=["GET"])
def get_one(resource, row_id):
    """Return a single row by primary key."""
    if resource not in RESOURCES:
        return jsonify({"error": "Unknown resource"}), 404

    table, pk = RESOURCES[resource]
    try:
        conn = get_db()
        cur = conn.cursor(dictionary=True)
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
    """
    Insert a new row.

    Special behaviour:
      - DRIVER inserts may be blocked by T1 (duplicate driver number).
        The trigger raises SQLSTATE 45000 → Flask returns 400 with the
        trigger message so the frontend can show it in the feedback panel.

      - DRIVER_CONTRACT inserts trigger T2 which auto-fills EndDate when
        it is NULL.  The saved row (with the auto-set date) is returned
        in the JSON response so the frontend can surface "T2 FIRED" info.
    """
    if resource not in RESOURCES:
        return jsonify({"error": "Unknown resource"}), 404

    table, pk = RESOURCES[resource]
    data = {k: v for k, v in (request.json or {}).items() if v not in ("", None) or k == "EndDate"}
    data.pop(pk, None)          # never set the auto-increment PK manually
    data.pop("__key", None)     # frontend attaches this; strip it

    # Convert empty strings to NULL for nullable columns
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

        # Fetch the just-inserted row (captures T2-modified EndDate, etc.)
        cur.execute(f"SELECT * FROM `{table}` WHERE `{pk}` = %s", (new_id,))
        saved_row = cur.fetchone()
        conn.close()

        # Detect whether T2 auto-filled EndDate
        t2_fired = (
            resource == "driver_contracts"
            and data.get("EndDate") is None
            and saved_row is not None
            and saved_row.get("EndDate") is not None
        )

        return jsonify({
            "success":  True,
            "id":       new_id,
            "row":      serialize(saved_row),
            "t2_fired": t2_fired,
        }), 201

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


@app.route("/api/<resource>/<int:row_id>", methods=["DELETE"])
def delete(resource, row_id):
    """Delete a row by primary key."""
    if resource not in RESOURCES:
        return jsonify({"error": "Unknown resource"}), 404

    table, pk = RESOURCES[resource]
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
#  TRIGGER MANAGEMENT  /api/triggers
# ═══════════════════════════════════════════════════════════════════

@app.route("/api/triggers/status", methods=["GET"])
def trigger_status():
    """
    Return the enabled/disabled state of both triggers by querying
    information_schema.TRIGGERS — the ground truth in MySQL.
    """
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
    """
    Toggle a database trigger on or off by DROPping / re-CREATing it.
    Returns {"enabled": true/false} with the new state.
    """
    if trigger_num not in TRIGGER_DEFS:
        return jsonify({"error": "Unknown trigger number"}), 404

    t = TRIGGER_DEFS[trigger_num]
    try:
        conn = get_db()
        cur  = conn.cursor()

        # Check current state
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
            # mysql-connector needs DELIMITER-free SQL for multi-statement triggers
            cur.execute(t["sql"])
            enabled = True

        conn.commit()
        conn.close()
        return jsonify({"success": True, "enabled": enabled, "trigger": t["name"]})

    except MySQLError as exc:
        return jsonify({"error": mysql_error_msg(exc)}), 500


# ═══════════════════════════════════════════════════════════════════
#  HEALTH CHECK
# ═══════════════════════════════════════════════════════════════════

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
    print("=" * 55)
    print("  Grand Prix Hub API  —  http://localhost:5000")
    print("  Health:   GET /api/health")
    print("  Tables:   GET /api/teams, /api/drivers, ...")
    print("  Triggers: GET /api/triggers/status")
    print("=" * 55)
    app.run(debug=True, port=5000)
