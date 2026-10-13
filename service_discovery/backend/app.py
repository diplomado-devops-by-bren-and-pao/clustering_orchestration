from flask import Flask, jsonify
import psycopg2
import os

app = Flask(__name__)


def get_connection():

    return psycopg2.connect(
        host=os.getenv("DB_HOST", "database"),
        database=os.getenv("DB_NAME", "saludos_db"),
        user=os.getenv("DB_USER", "saludos_user"),
        password=os.getenv("DB_PASSWORD"),
        port=int(os.getenv("DB_PORT", "5432"))
    )

@app.route("/health", methods=["GET"])
def health():
    return jsonify({"status": "OK"})

@app.route("/config", methods=["GET"])
def config():
    return jsonify({
        "environment": os.getenv("APP_ENV", "default")
    })

@app.route("/saludo", methods=["GET"])
def saludo():
    try:
        connection = get_connection()
        cursor = connection.cursor()

        cursor.execute("""
            SELECT mensaje
            FROM saludos
            ORDER BY RANDOM()
            LIMIT 1;
        """)

        result = cursor.fetchone()

        cursor.close()
        connection.close()

        if result:
            return jsonify({"mensaje": result[0]})

        return jsonify({"mensaje": "No hay saludos disponibles"})

    except Exception as error:
        return jsonify({"error": str(error)}), 500


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)