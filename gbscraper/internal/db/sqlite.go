package db

import (
	"database/sql"
	"fmt"

	"github.com/airone01/x/gbscraper/internal/models"
	_ "github.com/mattn/go-sqlite3"
)

type Store struct {
	Conn *sql.DB
}

func InitDB(dbPath string) (*Store, error) {
	db, err := sql.Open("sqlite3", dbPath)
	if err != nil {
		return nil, fmt.Errorf("failed to open database: %w", err)
	}

	// Create tables if they don't exist
	schema := `
	CREATE TABLE IF NOT EXISTS mods (
		id INTEGER PRIMARY KEY,
		game_id INTEGER,
		name TEXT
	);

	CREATE TABLE IF NOT EXISTS files (
		id INTEGER PRIMARY KEY,
		mod_id INTEGER,
		download_url TEXT,
		filename TEXT,
		version TEXT,
		FOREIGN KEY(mod_id) REFERENCES mods(id)
	);

	CREATE TABLE IF NOT EXISTS processing_results (
		file_id INTEGER,
		processor_name TEXT,
		result_data TEXT,
		PRIMARY KEY (file_id, processor_name),
		FOREIGN KEY(file_id) REFERENCES files(id)
	);
	`

	_, err = db.Exec(schema)
	if err != nil {
		return nil, fmt.Errorf("failed to create schema: %w", err)
	}

	return &Store{Conn: db}, nil
}

// EnsureModExists inserts a mod record if it doesn't already exist.
func (s *Store) EnsureModExists(modID int) error {
	query := `INSERT OR IGNORE INTO mods (id) VALUES (?)`
	_, err := s.Conn.Exec(query, modID)
	if err != nil {
		return fmt.Errorf("failed to ensure mod exists %d: %w", modID, err)
	}
	return nil
}

// EnsureFileExists inserts the file metadata if we haven't seen it yet.
func (s *Store) EnsureFileExists(file models.ModFile) error {
	query := `INSERT OR IGNORE INTO files (id, mod_id, download_url, filename, version) VALUES (?, ?, ?, ?, ?)`
	_, err := s.Conn.Exec(query, file.ID, file.ModID, file.DownloadURL, file.Filename, file.Version)
	if err != nil {
		return fmt.Errorf("failed to ensure file exists %d: %w", file.ID, err)
	}
	return nil
}

// SaveProcessResult saves the output of a post-processor (like the sha256 hash).
func (s *Store) SaveProcessResult(fileID int, processorName string, resultData string) error {
	query := `INSERT OR REPLACE INTO processing_results (file_id, processor_name, result_data) VALUES (?, ?, ?)`
	_, err := s.Conn.Exec(query, fileID, processorName, resultData)
	if err != nil {
		return fmt.Errorf("failed to save process result for file %d, processor %s: %w", fileID, processorName, err)
	}
	return nil
}

// HasFileBeenProcessed checks if we can skip this file to maintain idempotency.
func (s *Store) HasFileBeenProcessed(fileID int, processorName string) (bool, error) {
	var exists bool
	query := `SELECT EXISTS(SELECT 1 FROM processing_results WHERE file_id = ? AND processor_name = ?)`
	err := s.Conn.QueryRow(query, fileID, processorName).Scan(&exists)
	return exists, err
}
