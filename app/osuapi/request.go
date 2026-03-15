package osuapi

import (
	"context"
	"fmt"
	"io"
	"log"
	"net/http"
	"time"

	"golang.org/x/oauth2"
)

const osuEndpoint = "https://osu.ppy.sh/api/v2/"

func makeRequest(reqString string) (res *http.Response, err error) {
	src, err := getTokenSource()

	if err != nil {
		return nil, err
	}

	client := oauth2.NewClient(context.Background(), src)

	for i := 0; i < 5; i++ {
		res, err = client.Get(osuEndpoint + reqString)

		if err != nil {
			return nil, err
		}

		if res.StatusCode == http.StatusOK {
			break
		}

		if res.StatusCode == http.StatusTooManyRequests {
			body, _ := io.ReadAll(res.Body)
			res.Body.Close()

			sleepDuration := 1 * time.Second

			log.Printf("OsuApi: Hit rate limit (429). Retrying in %v... (Attempt %d/5). Body: %s", sleepDuration, i+1, string(body))
			time.Sleep(sleepDuration)
			continue
		}

		status := res.Status
		body, _ := io.ReadAll(res.Body)
		res.Body.Close()
		return nil, fmt.Errorf("OsuApi: Request failed with status %s, body: %s", status, string(body))
	}

	if res.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("OsuApi: Request failed after retries with status %s", res.Status)
	}

	tk, _ := src.Token()

	tryUpdateToken(tk)

	return
}
