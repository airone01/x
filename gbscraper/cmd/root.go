package cmd

import (
	"os"

	"github.com/spf13/cobra"
)

var (
	dbPath      string
	concurrency int
)

var rootCmd = &cobra.Command{
	Use:   "gbscraper",
	Short: "A CLI to scrape and process GameBanana mods",
	Long:  `gbscraper downloads mods, calculates hashes, and processes dependencies.`,
}

func Execute() {
	if err := rootCmd.Execute(); err != nil {
		os.Exit(1)
	}
}

func init() {
	rootCmd.PersistentFlags().StringVar(&dbPath, "db-path", "gb_mods.sqlite", "Path to the SQLite database file")
	rootCmd.PersistentFlags().IntVar(&concurrency, "concurrency", 3, "Number of concurrent mod downloads")
}
