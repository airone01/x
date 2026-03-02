package cmd

import (
	"fmt"
	"github.com/spf13/cobra"
)

var exportCmd = &cobra.Command{
	Use:   "export",
	Short: "Export the SQLite database to JSON",
	RunE: func(cmd *cobra.Command, args []string) error {
		fmt.Printf("Exporting %s to JSON (Implementation pending)...\n", dbPath)
		return nil
	},
}

func init() {
	rootCmd.AddCommand(exportCmd)
}
