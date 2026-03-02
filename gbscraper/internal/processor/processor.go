package processor

import "fmt"

// PostProcessor defines the contract for analyzing downloaded mod files.
type PostProcessor interface {
	Name() string
	Process(filePath string) (string, error)
}

// Registry holds the available processors mapped by their CLI flag name.
var Registry = map[string]PostProcessor{}

// Register adds a processor to the registry.
func Register(p PostProcessor) {
	Registry[p.Name()] = p
}

// GetProcessors converts a list of comma-separated names from the CLI into actual processors.
func GetProcessors(names []string) ([]PostProcessor, error) {
	var processors []PostProcessor
	for _, name := range names {
		p, exists := Registry[name]
		if !exists {
			return nil, fmt.Errorf("unknown post-processor: %s", name)
		}
		processors = append(processors, p)
	}
	return processors, nil
}
