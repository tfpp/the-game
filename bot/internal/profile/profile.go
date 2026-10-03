// Package profile reads minimal game profiles from the accounts API.
package profile

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"regexp"
	"strings"
	"time"
)

var ErrNotFound = errors.New("no linked game profile")
var userID = regexp.MustCompile(`^[1-9][0-9]{0,19}$`)

type Profile struct {
	DisplayName     string `json:"display_name"`
	PlaytimeSeconds int64  `json:"playtime_seconds"`
}

type Client struct {
	baseURL string
	key     string
	http    *http.Client
}

// New requires an operator-configured API URL and a separate read-only credential.
// Redirects are forbidden so a misconfigured endpoint cannot forward that credential.
func New(baseURL, key string) (*Client, error) {
	u, err := url.Parse(baseURL)
	if err != nil || u.Host == "" || (u.Scheme != "http" && u.Scheme != "https") ||
		u.User != nil || u.RawQuery != "" || u.Fragment != "" || len(key) < 32 {
		return nil, errors.New("invalid profile API configuration")
	}
	return &Client{baseURL: strings.TrimRight(baseURL, "/"), key: key,
		http: &http.Client{Timeout: 10 * time.Second, CheckRedirect: func(*http.Request, []*http.Request) error {
			return http.ErrUseLastResponse
		}}}, nil
}

func (c *Client) Lookup(ctx context.Context, user string) (Profile, error) {
	if !userID.MatchString(user) {
		return Profile{}, errors.New("invalid user")
	}
	req, err := http.NewRequestWithContext(ctx, "GET", c.baseURL+"/bot/profile/"+user, nil)
	if err != nil {
		return Profile{}, err
	}
	req.Header.Set("Authorization", "Bearer "+c.key)
	res, err := c.http.Do(req)
	if err != nil {
		// Avoid returning URL/transport details to Discord.
		return Profile{}, errors.New("profile API unavailable")
	}
	defer res.Body.Close()
	if res.StatusCode == http.StatusNotFound {
		return Profile{}, ErrNotFound
	}
	if res.StatusCode != http.StatusOK {
		return Profile{}, fmt.Errorf("profile API status %d", res.StatusCode)
	}
	var p Profile
	raw, err := io.ReadAll(io.LimitReader(res.Body, 4097))
	if err != nil || len(raw) > 4096 || json.Unmarshal(raw, &p) != nil || p.PlaytimeSeconds < 0 {
		return Profile{}, errors.New("invalid profile response")
	}
	return p, nil
}
