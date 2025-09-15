import logging
import shutil
import tempfile
import zipfile
from logging.handlers import RotatingFileHandler
import os
from urllib.parse import quote_plus
from flask import Flask, send_from_directory, render_template, request
from flask_cors import CORS
from flask_sqlalchemy import SQLAlchemy
from flask_jwt_extended import JWTManager
from sqlalchemy import text
from flask_migrate import Migrate
from dotenv import load_dotenv
from datetime import timedelta
import requests
from dateutil import parser

load_dotenv()
db = SQLAlchemy()

# ------- Frontend Build (GitHub Release) -------
DEPLOYMENT_ENV = os.getenv("DEPLOYMENT_ENV", "local")
GITHUB_USERNAME = "AlejandroRomanIbanez"
REPO_NAME = "AWS_grocery"
FRONTEND_BUILD_ZIP = "frontend-build.zip"
FRONTEND_BUILD_PATH = os.path.abspath(
    os.path.join(os.path.dirname(__file__), "../../frontend/build")
)
TMP_ZIP_PATH = os.path.join(tempfile.gettempdir(), "frontend-build.zip")
GITHUB_RELEASE_URL = (
    f"https://github.com/{GITHUB_USERNAME}/{REPO_NAME}/releases/latest/download/{FRONTEND_BUILD_ZIP}"
)


class Config:
    """Base app configuration."""
    # DB-Parameter kommen aus ENV; keine lokale Fallback-URI mit localhost!
    POSTGRES_USER = os.getenv("POSTGRES_USER", "")
    POSTGRES_PASSWORD = os.getenv("POSTGRES_PASSWORD", "")
    POSTGRES_DB = os.getenv("POSTGRES_DB", "")
    POSTGRES_HOST = os.getenv("POSTGRES_HOST", "")
    POSTGRES_PORT = os.getenv("POSTGRES_PORT", "5432")

    # SQLAlchemy wird in create_app() mit einer dynamisch gebauten URI versorgt
    SQLALCHEMY_DATABASE_URI = ""
    SQLALCHEMY_TRACK_MODIFICATIONS = False

    JWT_SECRET_KEY = os.getenv("JWT_SECRET_KEY", "change-me")
    JWT_ACCESS_TOKEN_EXPIRES = timedelta(hours=4)


def _build_db_uri_from_env() -> str:
    """Baut eine PostgreSQL-URI aus ENV-Variablen und erzwingt SSL für RDS."""
    user = os.getenv("POSTGRES_USER", "")
    pw = os.getenv("POSTGRES_PASSWORD", "")
    host = os.getenv("POSTGRES_HOST", "")
    dbn = os.getenv("POSTGRES_DB", "")
    port = os.getenv("POSTGRES_PORT", "5432")

    missing = [k for k, v in {
        "POSTGRES_USER": user,
        "POSTGRES_PASSWORD": pw,
        "POSTGRES_HOST": host,
        "POSTGRES_DB": dbn,
    }.items() if not v]
    if missing:
        raise RuntimeError(f"Missing DB env vars: {', '.join(missing)}")

    pw_q = quote_plus(pw)
    uri = f"postgresql+psycopg2://{user}:{pw_q}@{host}:{port}/{dbn}"
    if "rds.amazonaws.com" in host and "sslmode=" not in uri:
        uri += "?sslmode=require"
    return uri


def _detect_environment(db_uri: str) -> str:
    if "rds.amazonaws.com" in db_uri:
        return "AWS RDS (Production)"
    return "Local/Custom PostgreSQL"


def fetch_frontend():
    """
    Fetches the latest frontend build from GitHub Releases and ensures it's placed in frontend/build.
    """
    if os.path.exists(FRONTEND_BUILD_PATH):
        print("Frontend build is already present. Checking for updates...")
        latest_release_timestamp = get_github_release_timestamp()
        local_build_timestamp = get_local_build_timestamp()

        if latest_release_timestamp and local_build_timestamp:
            if local_build_timestamp >= latest_release_timestamp:
                print("Frontend build is up to date.")
                return
            print("Frontend build is outdated. Fetching the latest version...")
    else:
        print("Frontend build not found. Fetching the latest version...")

    try:
        response = requests.get(GITHUB_RELEASE_URL, stream=True, timeout=60)
        if response.status_code == 200:
            with open(TMP_ZIP_PATH, "wb") as f:
                f.write(response.content)

            frontend_dir = os.path.dirname(FRONTEND_BUILD_PATH)
            os.makedirs(frontend_dir, exist_ok=True)

            temp_extract_path = os.path.join(frontend_dir, "temp_extract")
            shutil.rmtree(temp_extract_path, ignore_errors=True)
            os.makedirs(temp_extract_path)

            with zipfile.ZipFile(TMP_ZIP_PATH, 'r') as zip_ref:
                zip_ref.extractall(temp_extract_path)

            if os.path.exists(FRONTEND_BUILD_PATH):
                shutil.rmtree(FRONTEND_BUILD_PATH)
            os.makedirs(FRONTEND_BUILD_PATH)

            if os.path.exists(os.path.join(temp_extract_path, "build", "index.html")):
                source_dir = os.path.join(temp_extract_path, "build")
                print("Found build directory in zip, using its contents")
            elif os.path.exists(os.path.join(temp_extract_path, "index.html")):
                source_dir = temp_extract_path
                print("Found files at root of zip, moving them to build directory")
            else:
                raise Exception("Could not find index.html in the extracted content")

            for item in os.listdir(source_dir):
                src = os.path.join(source_dir, item)
                dst = os.path.join(FRONTEND_BUILD_PATH, item)
                if os.path.isdir(src):
                    shutil.copytree(src, dst)
                else:
                    shutil.copy2(src, dst)

            if not os.path.exists(os.path.join(FRONTEND_BUILD_PATH, "index.html")):
                raise Exception("Failed to find index.html in final build directory")

            shutil.rmtree(temp_extract_path, ignore_errors=True)
            os.remove(TMP_ZIP_PATH)

            print("Frontend build downloaded and extracted successfully")
        else:
            print(f"Failed to download frontend build. Status Code: {response.status_code}")
    except Exception as e:
        print(f"Error fetching frontend: {e}")
        if 'temp_extract_path' in locals():
            shutil.rmtree(temp_extract_path, ignore_errors=True)
        if os.path.exists(TMP_ZIP_PATH):
            os.remove(TMP_ZIP_PATH)
        # Fehler weiterreichen, damit der Container-Start sichtbar fehlschlägt
        raise


def get_github_release_timestamp():
    """Fetches the timestamp of the latest frontend release from GitHub."""
    release_api_url = f"https://api.github.com/repos/{GITHUB_USERNAME}/{REPO_NAME}/releases/latest"
    try:
        response = requests.get(release_api_url, timeout=15)
        if response.status_code == 200:
            timestamp_iso = response.json().get("published_at")
            if timestamp_iso:
                return int(parser.parse(timestamp_iso).timestamp())
    except Exception as e:
        print(f"Error fetching GitHub release timestamp: {e}")
    return None


def get_local_build_timestamp():
    """Retrieves the timestamp of the local frontend build."""
    try:
        return os.path.getmtime(FRONTEND_BUILD_PATH)
    except Exception:
        return None


def create_app():
    """Creates and configures the Flask app."""
    # Frontend aus GitHub Releases beziehen (optional im Container)
    try:
        fetch_frontend()
    except Exception as e:
        # Im Zweifel die App trotzdem starten, wenn bereits ein Build vorhanden ist
        print(f"Frontend fetch warning: {e}")

    app = Flask(
        __name__,
        static_folder="../../frontend/build/static",
        template_folder=os.path.join(os.path.dirname(__file__), "../../frontend/build"),
    )
    CORS(app, resources={r"/*": {"origins": "*"}})

    # --- DB-Verbindung dynamisch bauen & loggen ---
    db_uri = _build_db_uri_from_env()
    app.config.from_object(Config)
    app.config["SQLALCHEMY_DATABASE_URI"] = db_uri

    # Sichere Logausgabe ohne Passwort
    pw_plain = os.getenv("POSTGRES_PASSWORD", "")
    safe_uri = db_uri.replace(quote_plus(pw_plain), "****") if pw_plain else db_uri
    app.logger.info(f"Using Database: {safe_uri}")
    app.logger.info(f"Environment: {_detect_environment(db_uri)}")

    db.init_app(app)

    with app.app_context():
        if app.config["SQLALCHEMY_DATABASE_URI"].startswith("sqlite"):
            db.session.execute(text("PRAGMA foreign_keys=ON"))

    JWTManager(app)
    Migrate(app, db)
    setup_logging(app)

    # --- Blueprints registrieren ---
    from .routes.auth_routes import auth_bp
    from .routes.user_routes import user_bp
    from .routes.product_routes import product_bp
    from .routes.health_routes import health_bp
    from .routes.config_routes import config_bp

    app.register_blueprint(auth_bp)
    app.register_blueprint(user_bp)
    app.register_blueprint(product_bp)
    app.register_blueprint(health_bp)
    app.register_blueprint(config_bp)

    # --- Static/Index Serving für React ---
    def inject_backend_url():
        """Ermittelt die Backend-URL dynamisch (ALB/Reverse Proxy kompatibel)."""
        proto = request.headers.get("X-Forwarded-Proto", request.scheme)
        host = request.headers.get("X-Forwarded-Host", request.host)
        app.logger.debug(f"Resolved URL - Proto: {proto}, Host: {host}")
        return f"{proto}://{host}"

    @app.route("/", defaults={"path": ""})
    @app.route("/<path:path>")
    def serve_react_app(path):
        if path != "" and os.path.exists(os.path.join(app.static_folder, path)):
            return send_from_directory(app.static_folder, path)
        else:
            backend_url = inject_backend_url()
            return render_template("index.html", backend_url=backend_url)

    return app


def setup_logging(app: Flask):
    """Set up rotating file logging."""
    os.makedirs("logs", exist_ok=True)
    log_file = "logs/app.log"

    file_handler = RotatingFileHandler(log_file, maxBytes=1024 * 1024, backupCount=5)
    file_handler.setLevel(logging.INFO)
    formatter = logging.Formatter("%(asctime)s - %(name)s - %(levelname)s - %(message)s")
    file_handler.setFormatter(formatter)

    app.logger.addHandler(file_handler)
    app.logger.setLevel(logging.INFO)
