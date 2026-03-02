package cmd

import (
	"fmt"
	"os"
	"strings"
	"sync"

	"github.com/shirou/gopsutil/v3/disk"
	"github.com/spf13/cobra"

	"github.com/airone01/x/gbscraper/internal/db"
	"github.com/airone01/x/gbscraper/internal/models"
	"github.com/airone01/x/gbscraper/internal/processor"
	"github.com/airone01/x/gbscraper/internal/scraper"
)

var (
	gameID      int
	postProcess string
	tempDir     string
)

var scrapeCmd = &cobra.Command{
	Use:   "scrape",
	Short: "Scrape mods for a specific game",
	RunE: func(cmd *cobra.Command, args []string) error {
		processorNames := strings.Split(postProcess, ",")
		processors, err := processor.GetProcessors(processorNames)
		if err != nil {
			return err
		}
		fmt.Printf("Loaded %d post-processors: %s\n", len(processors), postProcess)

		if err := checkDiskSpace(tempDir, concurrency); err != nil {
			fmt.Printf("WARNING: %v\n", err)
		} else {
			fmt.Println("Disk space check passed.")
		}

		store, err := db.InitDB(dbPath)
		if err != nil {
			return fmt.Errorf("database init failed: %w", err)
		}
		defer store.Conn.Close()
		fmt.Println("Database initialized successfully.")

		fmt.Printf("Ready to scrape GameID: %d with concurrency: %d\n", gameID, concurrency)

		api := scraper.NewAPIClient()
		ctx := cmd.Context()

		jobs := make(chan models.ModFile, concurrency*2) // buffer channel
		var wg sync.WaitGroup

		pool := &scraper.WorkerPool{
			Concurrency: concurrency,
			TempDir:     tempDir,
			Store:       store,
			Processors:  processors,
		}

		pool.Start(ctx, jobs, &wg)

		fmt.Printf("Fetching mods for Game ID: %d...\n", gameID)
		page := 1
		for {
			mods, err := api.FetchModsPage(ctx, gameID, page)
			if err != nil {
				fmt.Printf("Error fetching page %d: %v\n", page, err)
				break
			}
			if len(mods) == 0 {
				fmt.Println("No more mods found. Finished pagination.")
				break
			}

			for _, mod := range mods {
				query := `INSERT OR REPLACE INTO mods (id, game_id, name) VALUES (?, ?, ?)`
				store.Conn.Exec(query, mod.ID, mod.GameID, mod.Name)

				files, err := api.FetchModFiles(ctx, mod.ID)
				if err != nil {
					fmt.Printf("Error fetching files for Mod %d: %v\n", mod.ID, err)
					continue
				}

				for _, f := range files {
					// feed job queue
					jobs <- f
				}
			}
			page++
		}

		// gracefully
		close(jobs)
		wg.Wait()

		fmt.Println("Scraping completed successfully.")
		return nil
	},
}

func init() {
	scrapeCmd.Flags().IntVar(&gameID, "game-id", 6460, "GameBanana Game ID (Celeste = 6460)")
	scrapeCmd.Flags().StringVar(&postProcess, "postprocess", "sha256", "Comma-separated list of post-processors")
	scrapeCmd.Flags().StringVar(&tempDir, "temp-dir", os.TempDir(), "Directory for temporary downloads")
	rootCmd.AddCommand(scrapeCmd)
}

// checkDiskSpace ensures we have roughly 2GB per concurrent worker
func checkDiskSpace(path string, workers int) error {
	usage, err := disk.Usage(path)
	if err != nil {
		return fmt.Errorf("could not read disk usage for %s: %w", path, err)
	}

	requiredBytes := uint64(workers) * 2 * 1024 * 1024 * 1024 // 2GB per worker
	if usage.Free < requiredBytes {
		freeGB := float64(usage.Free) / (1024 * 1024 * 1024)
		reqGB := float64(requiredBytes) / (1024 * 1024 * 1024)
		return fmt.Errorf("low disk space in %s. Have %.2f GB, recommend %.2f GB", path, freeGB, reqGB)
	}
	return nil
}
