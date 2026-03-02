package models

// Mod represents the parent mod page on GameBanana.
type Mod struct {
	ID     int
	GameID int
	Name   string
}

// ModFile represents a specific downloadable file/version for a Mod.
type ModFile struct {
	ID          int
	ModID       int
	Version     string
	DownloadURL string
	Filename    string
}

// ProcessResult holds the output of a specific post-processor.
type ProcessResult struct {
	FileID        int
	ProcessorName string
	ResultData    string
}
