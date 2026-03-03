package cmd

import (
	"fmt"

	"github.com/airone01/x/gbscraper/internal/db"
	"github.com/spf13/cobra"
)

var searchCmd = &cobra.Command{
	Use:   "search [keyword]",
	Short: "Fuzzy search the database to debug missing mods",
	Args:  cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		keyword := "%" + args[0] + "%"

		store, err := db.InitDB(dbPath)
		if err != nil {
			return fmt.Errorf("database init failed: %w", err)
		}
		defer store.Conn.Close()

		fmt.Printf("Searching for: '%s'\n\n", args[0])

		fmt.Println("Everest YAML names (everest_metadata):")
		rows1, err := store.Conn.Query(`SELECT DISTINCT everest_name FROM everest_metadata WHERE everest_name LIKE ? COLLATE NOCASE`, keyword)
		if err == nil {
			defer rows1.Close()
			count := 0
			for rows1.Next() {
				var name string
				rows1.Scan(&name)
				fmt.Printf("Found: %s\n", name)
				count++
			}
			if count == 0 {
				fmt.Println("No matches found.")
			}
		}

		fmt.Println("\nGameBanana mod names:")
		rows2, err := store.Conn.Query(`SELECT id, name FROM mods WHERE name LIKE ? COLLATE NOCASE`, keyword)
		if err == nil {
			defer rows2.Close()
			count := 0
			for rows2.Next() {
				var id int
				var name string
				rows2.Scan(&id, &name)
				fmt.Printf("Found: [%d] %s\n", id, name)
				count++
			}
			if count == 0 {
				fmt.Println("No matches found.")
			}
		}

		fmt.Println("\nProcessor failures:")
		query3 := `
			SELECT f.filename, p.error_step 
			FROM files f 
			JOIN processing_results p ON f.id = p.file_id 
			WHERE p.processor_name = 'everest' AND p.status = 'FAILED' AND f.filename LIKE ? COLLATE NOCASE
		`
		rows3, err := store.Conn.Query(query3, keyword)
		if err == nil {
			defer rows3.Close()
			count := 0
			for rows3.Next() {
				var filename, errorStep string
				rows3.Scan(&filename, &errorStep)
				fmt.Printf("Failed: %s (Reason: %s)\n", filename, errorStep)
				count++
			}
			if count == 0 {
				fmt.Println("No failures found matching this name.")
			}
		}

		return nil
	},
}

func init() {
	rootCmd.AddCommand(searchCmd)
}
