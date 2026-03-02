package processor

import (
	"crypto/sha256"
	"encoding/hex"
	"io"
	"os"
)

type SHA256Processor struct{}

func (s *SHA256Processor) Name() string {
	return "sha256"
}

func (s *SHA256Processor) Process(filePath string) ProcessResponse {
	file, err := os.Open(filePath)
	if err != nil {
		return ProcessResponse{Status: "FAILED", ErrorStep: "file_open", Data: err.Error()}
	}
	defer file.Close()

	hash := sha256.New()
	if _, err := io.Copy(hash, file); err != nil {
		return ProcessResponse{Status: "FAILED", ErrorStep: "hash_calc", Data: err.Error()}
	}

	return ProcessResponse{
		Status:    "SUCCESS",
		ErrorStep: "",
		Data:      hex.EncodeToString(hash.Sum(nil)),
	}
}

// Register the processor automatically
func init() {
	Register(&SHA256Processor{})
}
