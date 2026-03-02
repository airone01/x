package scraper

import (
	"context"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"sync"
	"time"

	"github.com/airone01/x/gbscraper/internal/db"
	"github.com/airone01/x/gbscraper/internal/models"
	"github.com/airone01/x/gbscraper/internal/processor"
)

type WorkerPool struct {
	Concurrency int
	TempDir     string
	Store       *db.Store
	Processors  []processor.PostProcessor
}

func (wp *WorkerPool) Start(ctx context.Context, jobs <-chan models.ModFile, wg *sync.WaitGroup) {
	for i := 0; i < wp.Concurrency; i++ {
		wg.Add(1)
		go func(workerID int) {
			defer wg.Done()
			for fileJob := range jobs {
				wp.processJob(ctx, workerID, fileJob)
			}
		}(i)
	}
}

func (wp *WorkerPool) processJob(ctx context.Context, workerID int, file models.ModFile) {
	log.Printf("[Worker %d] Processing File ID: %d (%s)\n", workerID, file.ID, file.Filename)

	tempFilePath := filepath.Join(wp.TempDir, fmt.Sprintf("%d_%s", file.ID, file.Filename))
	if err := downloadFile(ctx, file.DownloadURL, tempFilePath); err != nil {
		log.Printf("[Worker %d] Failed to download %d: %v\n", workerID, file.ID, err)
		return
	}
	defer os.Remove(tempFilePath)

	// ensure Mod and File exist in the database before saving results
	wp.Store.EnsureModExists(file.ModID)
	wp.Store.EnsureFileExists(file)

	fileInfo, err := os.Stat(tempFilePath)
	if err == nil {
		wp.Store.UpdateFileStats(file.ID, fileInfo.Size(), time.Now().Format(time.RFC3339))
	} else {
		log.Printf("[Worker %d] Warning: Could not stat file %d: %v", workerID, file.ID, err)
	}

	for _, p := range wp.Processors {
		// idempotency check
		processed, err := wp.Store.HasFileBeenProcessed(file.ID, p.Name())
		if err == nil && processed {
			log.Printf("[Worker %d] Skipping %s for file %d (Already processed)\n", workerID, p.Name(), file.ID)
			continue
		}

		resp := p.Process(tempFilePath)
		if resp.Status == "FAILED" {
			log.Printf("[Worker %d] %s FAILED on %d (Step: %s) - %s\n", workerID, p.Name(), file.ID, resp.ErrorStep, resp.Data)
		} else {
			log.Printf("[Worker %d] %s SUCCESS on file %d\n", workerID, p.Name(), file.ID)
		}

		if err := wp.Store.SaveProcessResult(file.ID, p.Name(), resp.Status, resp.ErrorStep, resp.Data); err != nil {
			log.Printf("[Worker %d] DB Save failed for %d: %v\n", workerID, file.ID, err)
		}
	}
}

func downloadFile(ctx context.Context, url string, dest string) error {
	req, err := http.NewRequestWithContext(ctx, "GET", url, nil)
	if err != nil {
		return err
	}

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("bad status: %s", resp.Status)
	}

	out, err := os.Create(dest)
	if err != nil {
		return err
	}
	defer out.Close()

	_, err = io.Copy(out, resp.Body)
	return err
}
