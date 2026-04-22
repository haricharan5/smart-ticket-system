from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker, DeclarativeBase
from urllib.parse import quote_plus
import os
from dotenv import load_dotenv

load_dotenv()

server = os.environ["AZURE_SQL_SERVER"]
database = os.environ["AZURE_SQL_DATABASE"]
username = os.environ["AZURE_SQL_USERNAME"]
password = os.environ["AZURE_SQL_PASSWORD"]

# TrustServerCertificate=yes for Azure SQL with self-signed/managed certs
trust_cert = os.getenv("SQL_TRUST_CERT", "no")
encrypt = os.getenv("SQL_ENCRYPT", "yes")

# Use odbc_connect to bypass URL parsing — password may contain '@' which breaks
# the standard SQLAlchemy URL format (mssql+pyodbc://user:pass@host/db).
odbc_str = (
    f"Driver={{ODBC Driver 18 for SQL Server}};"
    f"Server={server},1433;"
    f"Database={database};"
    f"Uid={username};"
    f"Pwd={password};"
    f"Encrypt={encrypt};"
    f"TrustServerCertificate={trust_cert};"
    f"Connection Timeout=30;"
)
DATABASE_URL = f"mssql+pyodbc:///?odbc_connect={quote_plus(odbc_str)}"

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
