package scraper

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"time"

	"github.com/airone01/x/gbscraper/internal/models"
	"golang.org/x/time/rate"
)

// APIClient manages rate-limited communication with GameBanana.
type APIClient struct {
	client  *http.Client
	limiter *rate.Limiter
	baseURL string
}

func NewAPIClient() *APIClient {
	return &APIClient{
		client:  &http.Client{Timeout: 15 * time.Second},
		limiter: rate.NewLimiter(rate.Every(500*time.Millisecond), 1), // Max 2 requests per second
		baseURL: "https://gamebanana.com/apiv11",
	}
}

// FetchModsPage gets a single page of mods for a specific game.
func (api *APIClient) FetchModsPage(ctx context.Context, gameID int, page int) ([]models.Mod, error) {
	if err := api.limiter.Wait(ctx); err != nil {
		return nil, err
	}

	reqURL, err := url.Parse(fmt.Sprintf("%s/Mod/Index", api.baseURL))
	if err != nil {
		return nil, err
	}

	q := reqURL.Query()
	q.Set("_nPage", fmt.Sprintf("%d", page))
	q.Set("_nPerpage", "50")
	// q.Set("_sSort", "new")
	q.Set("_aFilters[Generic_Game]", fmt.Sprintf("%d", gameID))
	reqURL.RawQuery = q.Encode()

	req, err := http.NewRequestWithContext(ctx, "GET", reqURL.String(), nil)
	if err != nil {
		return nil, err
	}

	req.Header.Set("User-Agent", "gbscraper/1.0 (Celeste Mod Hash Project)")
	req.Header.Set("Accept", "application/json")

	resp, err := api.client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	rawBody, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("failed to read response body: %w", err)
	}

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("API returned status: %s | Body: %s", resp.Status, string(rawBody))
	}

	var result struct {
		Records []struct {
			ID   int    `json:"_idRow"`
			Name string `json:"_sName"`
		} `json:"_aRecords"`
	}

	if err := json.Unmarshal(rawBody, &result); err != nil {
		return nil, fmt.Errorf("failed to decode JSON: %w", err)
	}

	if len(result.Records) == 0 && page == 1 {
		return nil, fmt.Errorf("0 mods found. Please verify that Game ID %d is correct", gameID)
	}

	var mods []models.Mod
	for _, rec := range result.Records {
		mods = append(mods, models.Mod{
			ID:     rec.ID,
			GameID: gameID,
			Name:   rec.Name,
		})
	}
	return mods, nil
}

// FetchModFiles gets the downloadable files associated with a Mod ID.
func (api *APIClient) FetchModFiles(ctx context.Context, modID int) ([]models.ModFile, error) {
	if err := api.limiter.Wait(ctx); err != nil {
		return nil, err
	}

	url := fmt.Sprintf("%s/Mod/%d/ProfilePage", api.baseURL, modID)
	req, err := http.NewRequestWithContext(ctx, "GET", url, nil)
	if err != nil {
		return nil, err
	}

	req.Header.Set("User-Agent", "gbscraper/1.0")

	resp, err := api.client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("API returned status: %s", resp.Status)
	}

	// CHANGED: Files is now a slice []struct instead of a map[string]struct
	var result struct {
		Files []struct {
			ID          int    `json:"_idRow"`
			Filename    string `json:"_sFile"`
			DownloadURL string `json:"_sDownloadUrl"`
		} `json:"_aFiles"`
	}

	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return nil, fmt.Errorf("failed to decode files for Mod %d: %w", modID, err)
	}

	var files []models.ModFile
	for _, f := range result.Files {
		files = append(files, models.ModFile{
			ID:          f.ID,
			ModID:       modID,
			Filename:    f.Filename,
			DownloadURL: f.DownloadURL,
		})
	}
	return files, nil
}
