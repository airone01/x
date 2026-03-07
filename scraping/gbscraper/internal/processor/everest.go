package processor

import (
	"archive/zip"
	"encoding/json"
	"io"
	"path/filepath"
	"strings"

	"github.com/airone01/x/gbscraper/internal/models"
	"gopkg.in/yaml.v3"
)

type EverestProcessor struct{}

func (e *EverestProcessor) Name() string {
	return "everest"
}

func (e *EverestProcessor) Process(filePath string) ProcessResponse {
	if !strings.HasSuffix(strings.ToLower(filePath), ".zip") {
		return ProcessResponse{Status: "FAILED", ErrorStep: "unsupported_archive", Data: "Not a .zip file"}
	}

	r, err := zip.OpenReader(filePath)
	if err != nil {
		return ProcessResponse{Status: "FAILED", ErrorStep: "archive_open", Data: err.Error()}
	}
	defer r.Close()

	var yamlFile *zip.File
	for _, f := range r.File {
		if strings.ToLower(filepath.Base(f.Name)) == "everest.yaml" || strings.ToLower(filepath.Base(f.Name)) == "everest.yml" {
			yamlFile = f
			break
		}
	}

	if yamlFile == nil {
		return ProcessResponse{Status: "FAILED", ErrorStep: "missing_file", Data: "everest.yaml not found"}
	}

	rc, err := yamlFile.Open()
	if err != nil {
		return ProcessResponse{Status: "FAILED", ErrorStep: "archive_read", Data: err.Error()}
	}
	defer rc.Close()

	yamlBytes, err := io.ReadAll(rc)
	if err != nil {
		return ProcessResponse{Status: "FAILED", ErrorStep: "archive_read", Data: err.Error()}
	}

	var metaList []models.EverestModMeta
	if err := yaml.Unmarshal(yamlBytes, &metaList); err != nil {
		return ProcessResponse{Status: "FAILED", ErrorStep: "yaml_parse", Data: err.Error()}
	}

	jsonBytes, err := json.Marshal(metaList)
	if err != nil {
		return ProcessResponse{Status: "FAILED", ErrorStep: "json_encode", Data: err.Error()}
	}

	return ProcessResponse{
		Status:    "SUCCESS",
		ErrorStep: "",
		Data:      string(jsonBytes),
	}
}

func init() {
	Register(&EverestProcessor{})
}
