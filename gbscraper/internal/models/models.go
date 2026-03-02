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

// EverestDependency represents a single requirement for a mod.
type EverestDependency struct {
	Name    string `yaml:"Name" json:"name"`
	Version string `yaml:"Version" json:"version"`
}

// EverestModMeta represents one entry in the everest.yaml file.
type EverestModMeta struct {
	Name         string              `yaml:"Name" json:"name"`
	Version      string              `yaml:"Version" json:"version"`
	DLL          string              `yaml:"DLL" json:"dll"`
	Author       string              `yaml:"Author" json:"author"`
	Dependencies []EverestDependency `yaml:"Dependencies" json:"dependencies"`
}
