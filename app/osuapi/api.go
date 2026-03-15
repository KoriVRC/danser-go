package osuapi

import (
	"bytes"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"net/url"
	"strconv"

	"github.com/wieku/danser-go/app/settings"
)

type ScoreType int

const (
	NormalMode ScoreType = iota
	FriendsMode
	CountryMode
)

func LookupBeatmap(checksum string) (*LookupResult, error) {
	resp, err := makeRequest("beatmaps/lookup?checksum=" + checksum)

	if err != nil {
		return nil, err
	}

	buf, err2 := io.ReadAll(resp.Body)
	if err2 != nil {
		return nil, err
	}

	lRes := &LookupResult{}
	if err = json.Unmarshal(buf, &lRes); err != nil {
		return nil, err
	}

	return lRes, nil
}

func GetScoresCheksum(checksum string, legacyOnly bool, mode ScoreType, limit int, mods ...string) ([]Score, error) {
	lRes, err := LookupBeatmap(checksum)

	if err != nil {
		return nil, err
	}

	return GetScores(lRes.ID, legacyOnly, mode, limit, mods...)
}

func GetScores(beatmapId int64, legacyOnly bool, mode ScoreType, limit int, mods ...string) ([]Score, error) {
	vls := url.Values{}

	prefix := "solo-"
	if legacyOnly {
		prefix = ""
		vls.Set("legacy_only", "1")
	}

	switch mode {
	case CountryMode:
		vls.Set("type", "country")
	case FriendsMode:
		vls.Set("type", "friend")
	}

	if limit > -1 {
		vls.Add("limit", strconv.Itoa(limit))
	}

	if len(mods) > 0 {
		for _, m := range mods {
			vls.Add("mods[]", m)
		}
	}

	resp, err := makeRequest("beatmaps/" + strconv.FormatInt(beatmapId, 10) + "/" + prefix + "scores?" + vls.Encode())

	if err != nil {
		return nil, err
	}

	buf, err2 := io.ReadAll(resp.Body)
	if err2 != nil {
		return nil, err
	}

	sRes := &ScoresResult{}
	if err = json.Unmarshal(buf, &sRes); err != nil {
		return nil, err
	}

	return sRes.Scores, nil
}

func LookupUser(nickname string) (*User, error) {
	resp, err := makeRequest("users/@" + nickname + "/osu")

	if err != nil {
		return nil, err
	}

	buf, err2 := io.ReadAll(resp.Body)
	if err2 != nil {
		return nil, err
	}

	user := &User{}
	if err = json.Unmarshal(buf, &user); err != nil {
		return nil, err
	}

	return user, nil
}

func DownloadReplay(scoreId int64) (io.ReadCloser, error) {
	resp, err := makeRequest("scores/osu/" + strconv.FormatInt(scoreId, 10) + "/download")

	if err != nil {
		log.Printf("OsuApi: Official V2 download failed for %d (%v). Trying mirror...", scoreId, err)

		// Try osudaily mirror
		mResp, mErr := http.Get("https://osudaily.net/replays/" + strconv.FormatInt(scoreId, 10) + ".osr")
		if mErr == nil && mResp.StatusCode == http.StatusOK {
			log.Printf("OsuApi: Downloaded replay %d from mirror!", scoreId)
			return mResp.Body, nil
		}

		if mErr == nil {
			mResp.Body.Close()
		}

		return nil, err
	}

	return resp.Body, nil
}

func DownloadReplayV1(beatmapId int64, score Score, beatmapMD5 string, mode int) (io.ReadCloser, error) {
	if settings.Credentails.ApiKey == "" {
		return nil, fmt.Errorf("OsuApi: API Key (v1) not provided")
	}

	vls := url.Values{}
	vls.Set("k", settings.Credentails.ApiKey)
	vls.Set("b", strconv.FormatInt(beatmapId, 10))
	vls.Set("u", score.User.Username)
	vls.Set("m", strconv.Itoa(mode))
	vls.Set("type", "string")

	resp, err := http.Get("https://osu.ppy.sh/api/get_replay?" + vls.Encode())
	if err != nil {
		return nil, err
	}

	if resp.StatusCode != http.StatusOK {
		resp.Body.Close()
		return nil, fmt.Errorf("OsuApi: V1 request failed with status %d", resp.StatusCode)
	}

	var res struct {
		Content  string `json:"content"`
		Encoding string `json:"encoding"`
	}

	if err := json.NewDecoder(resp.Body).Decode(&res); err != nil {
		resp.Body.Close()
		return nil, err
	}
	resp.Body.Close()

	if res.Content == "" {
		return nil, fmt.Errorf("OsuApi: V1 API returned empty content")
	}

	decoded, err := base64.StdEncoding.DecodeString(res.Content)
	if err != nil {
		return nil, err
	}

	osr := BuildOSR(score, decoded, beatmapMD5, mode)

	return io.NopCloser(bytes.NewReader(osr)), nil
}
