package main

import (
	"github.com/airone01/x/gbscraper/cmd"

	// blank import to trigger init() functions of processors
	_ "github.com/airone01/x/gbscraper/internal/processor"
)

func main() {
	cmd.Execute()
}
