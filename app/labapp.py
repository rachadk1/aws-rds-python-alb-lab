"""Flask service for the private EC2 web tier / Service Flask pour les EC2 privées."""

import json
import os
import re
import ssl
from pathlib import Path

import pymysql
from flask import Flask, jsonify, render_template, request

app = Flask(__name__)
app.config["MAX_CONTENT_LENGTH"] = 8192
EMAIL = re.compile(r"[^\s@]+@[^\s@]+\.[^\s@]+")
IDENTITY = {
    "served_by": os.getenv("LAB_INSTANCE_ID", "local"),
    "az": os.getenv("LAB_AZ", "local"),
}


def connect():
    # systemd supplies the application secret through a service credential.
    # systemd fournit le secret applicatif dans un fichier réservé au service.
    secret_path = Path(os.environ["CREDENTIALS_DIRECTORY"]) / "db.json"
    account = json.loads(secret_path.read_text(encoding="utf-8"))
    context = ssl.create_default_context(cafile=os.environ["LAB_CA_FILE"])
    context.minimum_version = ssl.TLSVersion.TLSv1_2
    return pymysql.connect(
        host=os.environ["LAB_DB_HOST"],
        port=3306,
        user=account["username"],
        password=account["password"],
        database=account["dbname"],
        charset="utf8mb4",
        ssl=context,
        cursorclass=pymysql.cursors.DictCursor,
        connect_timeout=3,
        read_timeout=3,
        write_timeout=3,
    )


def log_failure(error):
    # Avoid logging SQL values, credentials or database error messages.
    # Éviter les valeurs SQL, identifiants et messages d'erreur bruts.
    app.logger.warning("Database / Base de données: %s", type(error).__name__)


DB_ERRORS = (pymysql.MySQLError, OSError, KeyError, ValueError)


@app.get("/health")
def health():
    if request.args.get("strict") != "1":
        return jsonify(status="ok", **IDENTITY)
    try:
        with connect() as db, db.cursor() as cursor:
            cursor.execute("SHOW SESSION STATUS LIKE 'Ssl_cipher'")
            tls = cursor.fetchone()["Value"]
            cursor.execute("SELECT COUNT(*) AS total FROM students")
            count = cursor.fetchone()["total"]
            if not tls:
                raise ValueError("TLS required")
    except DB_ERRORS as error:
        log_failure(error)
        return jsonify(status="degraded", db="unreachable", **IDENTITY), 503
    return jsonify(status="ok", db="reachable", db_tls=tls, students=count, **IDENTITY)


@app.get("/")
def index():
    lang = "fr" if request.args.get("lang") == "fr" else "en"
    try:
        with connect() as db, db.cursor() as cursor:
            cursor.execute("SELECT id, code, title, track, hours FROM courses ORDER BY code")
            courses = cursor.fetchall()
            cursor.execute("SELECT full_name FROM students ORDER BY id DESC LIMIT 20")
            students = cursor.fetchall()
    except DB_ERRORS as error:
        log_failure(error)
        return render_template("index.html", lang=lang, node=IDENTITY, available=False), 503
    return render_template(
        "index.html", lang=lang, node=IDENTITY, available=True, courses=courses, students=students
    )


@app.post("/students")
def register_student():
    data = request.get_json(silent=True)
    if not isinstance(data, dict):
        return jsonify(error="invalid_input"), 400
    full_name, email, city = (
        data[field].strip() if isinstance(data.get(field), str) else ""
        for field in ("full_name", "email", "city")
    )
    course_id = data.get("course_id")
    if (
        not 1 <= len(full_name) <= 100
        or len(email) > 120
        or not EMAIL.fullmatch(email)
        or len(city) > 60
        or type(course_id) is not int
        or not 1 <= course_id <= 4294967295
    ):
        return jsonify(error="invalid_input"), 400
    try:
        # Both writes share a transaction / les deux écritures sont atomiques.
        with connect() as db, db.cursor() as cursor:
            cursor.execute("SELECT id FROM courses WHERE id=%s", (course_id,))
            if cursor.fetchone() is None:
                return jsonify(error="invalid_course"), 400
            cursor.execute(
                "INSERT INTO students(full_name,email,city) VALUES(%s,%s,%s)",
                (full_name, email.lower(), city or None),
            )
            cursor.execute(
                "INSERT INTO enrollments(student_id,course_id,enrolled_on) VALUES(%s,%s,CURRENT_DATE)",
                (cursor.lastrowid, course_id),
            )
            db.commit()
    except pymysql.err.IntegrityError as error:
        if error.args[0] == 1062:
            return jsonify(error="duplicate_email"), 409
        log_failure(error)
        return jsonify(error="database_unavailable"), 503
    except DB_ERRORS as error:
        log_failure(error)
        return jsonify(error="database_unavailable"), 503
    return jsonify(status="registered", **IDENTITY), 201
