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

	for _, p := range wp.Processors {
		// idempotency check
		processed, err := wp.Store.HasFileBeenProcessed(file.ID, p.Name())
		if err == nil && processed {
			log.Printf("[Worker %d] Skipping %s for file %d (Already processed)\n", workerID, p.Name(), file.ID)
			continue
		}

		resultData, err := p.Process(tempFilePath)
		if err != nil {
			log.Printf("[Worker %d] Processor %s failed on file %d: %v\n", workerID, p.Name(), file.ID, err)
			continue
		}

		if err := wp.Store.SaveProcessResult(file.ID, p.Name(), resultData); err != nil {
			log.Printf("[Worker %d] Failed to save result to DB for %d: %v\n", workerID, file.ID, err)
		} else {
			log.Printf("[Worker %d] Successfully saved %s for file %d\n", workerID, p.Name(), file.ID)
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
