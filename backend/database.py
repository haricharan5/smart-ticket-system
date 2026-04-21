from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker, DeclarativeBase
import os
from dotenv import load_dotenv

load_dotenv()

server = os.environ["AZURE_SQL_SERVER"]
database = os.environ["AZURE_SQL_DATABASE"]
username = os.environ["AZURE_SQL_USERNAME"]
password = os.environ["AZURE_SQL_PASSWORD"]
driver = "ODBC+Driver+18+for+SQL+Server"

# TrustServerCertificate=yes for local Docker dev; no for Azure SQL
trust_cert = os.getenv("SQL_TRUST_CERT", "no")
encrypt = os.getenv("SQL_ENCRYPT", "yes")

DATABASE_URL = (
    f"mssql+pyodbc://{username}:{password}@{server}:1433/{database}"
    f"?driver={driver}&Encrypt={encrypt}&TrustServerCertificate={trust_cert}"
)

engine = create_engine(DATABASE_URL, pool_pre_ping=True, pool_size=5, max_overflow=10)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)


class Base(DeclarativeBase):
    pass


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
