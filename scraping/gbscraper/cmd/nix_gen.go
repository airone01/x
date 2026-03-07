package cmd

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"text/template"

	"github.com/airone01/x/gbscraper/internal/db"
	"github.com/spf13/cobra"
)

var outputDir string

const nixTemplate = `{ fetchurl }:
{
{{- range $version, $data := .Versions }}
  "{{ $version }}" = {
    src = fetchurl {
      url = "{{ $data.DownloadURL }}";
      sha256 = "{{ $data.SHA256 }}";
    };
    dependencies = [
      {{- range $dep := $data.Dependencies }}
      { name = "{{ $dep.Name }}"; version = "{{ $dep.Version }}"; }
      {{- end }}
    ];
  };
{{- end }}
}
`

var nixGenCmd = &cobra.Command{
	Use:   "nix-gen [ModName]",
	Short: "Generate Nix fetchurl derivations for a mod and its dependency tree",
	Args:  cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		startMod := args[0]
		fmt.Printf("Starting Nix generation for tree: %s\n", startMod)

		store, err := db.InitDB(dbPath)
		if err != nil {
			return fmt.Errorf("database init failed: %w", err)
		}
		defer store.Conn.Close()

		tmpl, err := template.New("nix").Parse(nixTemplate)
		if err != nil {
			return fmt.Errorf("failed to parse nix template: %w", err)
		}

		queue := []string{startMod}
		visited := make(map[string]bool)

		visited[strings.ToLower(startMod)] = true

		for len(queue) > 0 {
			currentMod := queue[0]
			queue = queue[1:]

			if visited[currentMod] {
				continue
			}
			visited[currentMod] = true

			versions, err := store.GetNixModData(currentMod)
			if err != nil {
				fmt.Printf("Error fetching data for %s: %v\n", currentMod, err)
				continue
			}

			if len(versions) == 0 {
				fmt.Printf("WARNING: Mod '%s' not found in database or has no versions. Skipping.\n", currentMod)
				continue
			}

			if err := writeNixFile(tmpl, currentMod, versions, outputDir); err != nil {
				fmt.Printf("Failed to write Nix file for %s: %v\n", currentMod, err)
				continue
			}
			fmt.Printf("Generated %s.nix (%d versions)\n", currentMod, len(versions))

			for _, vData := range versions {
				for _, dep := range vData.Dependencies {
					lowerDep := strings.ToLower(dep.Name)
					if !visited[lowerDep] {
						visited[lowerDep] = true
						queue = append(queue, dep.Name)
					}
				}
			}
		}

		fmt.Println("Nix generation complete!")
		return nil
	},
}

func init() {
	nixGenCmd.Flags().StringVarP(&outputDir, "out-dir", "d", "mods", "Output directory for the Nix tree")
	rootCmd.AddCommand(nixGenCmd)
}

func writeNixFile(tmpl *template.Template, modName string, versions map[string]db.NixModVersion, baseDir string) error {
	firstLetter := strings.ToLower(string(modName[0]))

	targetDir := filepath.Join(baseDir, firstLetter)
	if err := os.MkdirAll(targetDir, 0755); err != nil {
		return err
	}

	filePath := filepath.Join(targetDir, modName+".nix")
	file, err := os.Create(filePath)
	if err != nil {
		return err
	}
	defer file.Close()

	data := struct {
		Versions map[string]db.NixModVersion
	}{
		Versions: versions,
	}

	return tmpl.Execute(file, data)
}
