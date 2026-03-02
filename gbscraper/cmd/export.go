package cmd

import (
	"fmt"

	"github.com/airone01/x/gbscraper/internal/db"
	"github.com/spf13/cobra"
)

var exportOut string

var exportCmd = &cobra.Command{
	Use:   "export",
	Short: "Export the SQLite database to JSON",
	RunE: func(cmd *cobra.Command, args []string) error {
		fmt.Printf("Connecting to database at %s...\n", dbPath)

		store, err := db.InitDB(dbPath)
		if err != nil {
			return fmt.Errorf("database init failed: %w", err)
		}
		defer store.Conn.Close()

		fmt.Printf("Exporting data to %s...\n", exportOut)
		if err := store.ExportToJSON(exportOut); err != nil {
			return fmt.Errorf("export failed: %w", err)
		}

		fmt.Println("Export completed successfully!")
		return nil
	},
}

func init() {
	exportCmd.Flags().StringVarP(&exportOut, "out", "o", "gb_export.json", "Output JSON file path")
	rootCmd.AddCommand(exportCmd)
}
