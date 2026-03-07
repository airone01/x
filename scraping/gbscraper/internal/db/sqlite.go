package db

import (
	"database/sql"
	"fmt"

	"encoding/json"
	"os"

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
		size_bytes INTEGER DEFAULT 0,
		downloaded_at DATETIME
	);

	CREATE TABLE IF NOT EXISTS processing_results (
		file_id INTEGER,
		processor_name TEXT,
		status TEXT,
		error_step TEXT,
		result_data TEXT,
		PRIMARY KEY (file_id, processor_name),
		FOREIGN KEY(file_id) REFERENCES files(id)
	);

	CREATE TABLE IF NOT EXISTS everest_metadata (
		file_id INTEGER,
		everest_name TEXT,
		version TEXT,
		dll TEXT,
		author TEXT,
		PRIMARY KEY (file_id, everest_name),
		FOREIGN KEY(file_id) REFERENCES files(id)
	);

	CREATE TABLE IF NOT EXISTS everest_dependencies (
		file_id INTEGER,
		everest_name TEXT,
		dependency_name TEXT,
		dependency_version TEXT,
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
func (s *Store) SaveProcessResult(fileID int, processorName string, status string, errorStep string, resultData string) error {
	query := `INSERT OR REPLACE INTO processing_results (file_id, processor_name, status, error_step, result_data) VALUES (?, ?, ?, ?, ?)`
	_, err := s.Conn.Exec(query, fileID, processorName, status, errorStep, resultData)
	if err != nil {
		return fmt.Errorf("failed to save process result: %w", err)
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

// ExportMod represents the nested JSON structure for our export.
type ExportMod struct {
	ID     int          `json:"id"`
	GameID int          `json:"game_id,omitempty"`
	Name   string       `json:"name,omitempty"`
	Files  []ExportFile `json:"files"`
}

type ExportFile struct {
	ID           int               `json:"id"`
	Filename     string            `json:"filename"`
	DownloadURL  string            `json:"download_url"`
	SizeBytes    int64             `json:"size_bytes"`
	DownloadedAt string            `json:"downloaded_at"`
	Results      map[string]string `json:"results"`
}

// ExportToJSON reads the entire database and writes it to a formatted JSON file.
func (s *Store) ExportToJSON(outputPath string) error {
	query := `
		SELECT 
			m.id, m.game_id, m.name, 
			f.id, f.filename, f.download_url, f.size_bytes, f.downloaded_at,
			p.processor_name, p.result_data
		FROM mods m
		LEFT JOIN files f ON m.id = f.mod_id
		LEFT JOIN processing_results p ON f.id = p.file_id
	`
	rows, err := s.Conn.Query(query)
	if err != nil {
		return fmt.Errorf("failed to query database for export: %w", err)
	}
	defer rows.Close()

	modsMap := make(map[int]*ExportMod)
	filesMap := make(map[int]*ExportFile)

	for rows.Next() {
		var (
			modID, fileID                           sql.NullInt64
			gameID, sizeBytes                       sql.NullInt64
			modName, filename, downloadURL          sql.NullString
			downloadedAt, processorName, resultData sql.NullString
		)

		if err := rows.Scan(&modID, &gameID, &modName, &fileID, &filename, &downloadURL, &sizeBytes, &downloadedAt, &processorName, &resultData); err != nil {
			return fmt.Errorf("failed to scan row: %w", err)
		}

		if !modID.Valid {
			continue
		}

		mID := int(modID.Int64)
		if _, exists := modsMap[mID]; !exists {
			modsMap[mID] = &ExportMod{
				ID:     mID,
				GameID: int(gameID.Int64),
				Name:   modName.String,
				Files:  []ExportFile{},
			}
		}

		if fileID.Valid {
			fID := int(fileID.Int64)
			if _, exists := filesMap[fID]; !exists {
				filesMap[fID] = &ExportFile{
					ID:           fID,
					Filename:     filename.String,
					DownloadURL:  downloadURL.String,
					SizeBytes:    sizeBytes.Int64,
					DownloadedAt: downloadedAt.String,
					Results:      make(map[string]string),
				}
			}

			if processorName.Valid && resultData.Valid {
				filesMap[fID].Results[processorName.String] = resultData.String
			}
		}
	}

	return s.writeJSON(outputPath, modsMap, filesMap)
}

// writeJSON is a helper to write the assembled maps to the file
func (s *Store) writeJSON(outputPath string, modsMap map[int]*ExportMod, filesMap map[int]*ExportFile) error {
	rows, err := s.Conn.Query(`SELECT id, mod_id FROM files`)
	if err == nil {
		defer rows.Close()
		for rows.Next() {
			var fID, mID int
			if err := rows.Scan(&fID, &mID); err == nil {
				if mod, ok := modsMap[mID]; ok {
					if file, ok := filesMap[fID]; ok {
						mod.Files = append(mod.Files, *file)
					}
				}
			}
		}
	}

	var finalOutput []ExportMod
	for _, mod := range modsMap {
		finalOutput = append(finalOutput, *mod)
	}

	file, err := os.Create(outputPath)
	if err != nil {
		return fmt.Errorf("failed to create export file: %w", err)
	}
	defer file.Close()

	encoder := json.NewEncoder(file)
	if err := encoder.Encode(finalOutput); err != nil {
		return fmt.Errorf("failed to encode JSON: %w", err)
	}

	return nil
}

func (s *Store) UpdateFileStats(fileID int, sizeBytes int64, downloadedAt string) error {
	query := `UPDATE files SET size_bytes = ?, downloaded_at = ? WHERE id = ?`
	_, err := s.Conn.Exec(query, sizeBytes, downloadedAt, fileID)
	return err
}

// SaveEverestData takes the parsed Everest structures and inserts them into relational tables.
func (s *Store) SaveEverestData(fileID int, metaList []models.EverestModMeta) error {
	tx, err := s.Conn.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()

	metaQuery := `INSERT OR REPLACE INTO everest_metadata (file_id, everest_name, version, dll, author) VALUES (?, ?, ?, ?, ?)`
	depQuery := `INSERT OR REPLACE INTO everest_dependencies (file_id, everest_name, dependency_name, dependency_version) VALUES (?, ?, ?, ?)`

	for _, meta := range metaList {
		_, err := tx.Exec(metaQuery, fileID, meta.Name, meta.Version, meta.DLL, meta.Author)
		if err != nil {
			return fmt.Errorf("failed to save metadata for %s: %w", meta.Name, err)
		}

		for _, dep := range meta.Dependencies {
			_, err := tx.Exec(depQuery, fileID, meta.Name, dep.Name, dep.Version)
			if err != nil {
				return fmt.Errorf("failed to save dependency %s for %s: %w", dep.Name, meta.Name, err)
			}
		}
	}

	return tx.Commit()
}

// NixModVersion groups all the data needed to generate a single version block in Nix.
type NixModVersion struct {
	Version      string
	DownloadURL  string
	SHA256       string
	Dependencies []models.EverestDependency
}

// GetNixModData retrieves all versions and dependencies for a specific Everest mod name.
func (s *Store) GetNixModData(everestName string) (map[string]NixModVersion, error) {
	query := `
		SELECT m.file_id, m.version, f.download_url, p.result_data
		FROM everest_metadata m
		JOIN files f ON m.file_id = f.id
		JOIN processing_results p ON f.id = p.file_id AND p.processor_name = 'sha256'
		WHERE LOWER(m.everest_name) = LOWER(?)
	`
	rows, err := s.Conn.Query(query, everestName)
	if err != nil {
		return nil, fmt.Errorf("failed to query mod data: %w", err)
	}
	defer rows.Close()

	versions := make(map[string]NixModVersion)
	fileIDs := make(map[int]string)

	for rows.Next() {
		var fileID int
		var version, url, sha256 string
		if err := rows.Scan(&fileID, &version, &url, &sha256); err != nil {
			return nil, err
		}

		versions[version] = NixModVersion{
			Version:     version,
			DownloadURL: url,
			SHA256:      sha256,
		}
		fileIDs[fileID] = version
	}

	depQuery := `SELECT file_id, dependency_name, dependency_version FROM everest_dependencies WHERE LOWER(everest_name) = LOWER(?)`
	depRows, err := s.Conn.Query(depQuery, everestName)
	if err == nil {
		defer depRows.Close()
		for depRows.Next() {
			var fID int
			var dName, dVer string
			if err := depRows.Scan(&fID, &dName, &dVer); err == nil {
				if verStr, exists := fileIDs[fID]; exists {
					v := versions[verStr]
					v.Dependencies = append(v.Dependencies, models.EverestDependency{
						Name:    dName,
						Version: dVer,
					})
					versions[verStr] = v
				}
			}
		}
	}

	return versions, nil
}
