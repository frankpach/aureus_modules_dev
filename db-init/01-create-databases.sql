CREATE DATABASE aureus_prod;
CREATE DATABASE aureus_dev;

\connect aureus_prod;
CREATE EXTENSION IF NOT EXISTS vector;

\connect aureus_dev;
CREATE EXTENSION IF NOT EXISTS vector;
