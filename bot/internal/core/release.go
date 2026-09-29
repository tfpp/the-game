package core

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"regexp"
	"slices"
	"strconv"
	"strings"
	"unicode/utf8"

	"github.com/tfpp/the-game/bot/internal/github"
)

// Release announcements: the release workflow (run by hand) publishes a GitHub Release
// with its CHANGELOG.md notes, and its commit bumps the game's version, so it deploys
// like any merge. Once the deployed game server contains a release, the bot posts it to
// ReleaseChannelID, oldest first, each once. Then it posts the bullets of CHANGELOG.md's
// `## [edge]` section and feature-owned JSON notes that went live since, each once.

const (
	releaseAnnouncedKey = "release_announced" // version of the last announced release
	releaseCheckedKey   = "release_checked"   // deploy the releases were last checked for
	edgeAnnouncedKey    = "edge_announced"    // JSON list of the edge bullets announced
	changelogPath       = "CHANGELOG.md"
	// maxReleasePost keeps a post under Discord's 2000-character message limit.
	maxReleasePost = 1900
)

var releaseTag = regexp.MustCompile(`^v(\d+)\.(\d+)\.(\d+)$`)

// version is a parsed vX.Y.Z tag.
type version [3]int

func parseVersion(tag string) (version, bool) {
	m := releaseTag.FindStringSubmatch(tag)
	if m == nil {
		return version{}, false
	}
	var v version
	for i := range v {
		n, err := strconv.Atoi(m[i+1])
		if err != nil {
			return version{}, false
		}
		v[i] = n
	}
	return v, true
}

func (v version) compare(o version) int { return slices.Compare(v[:], o[:]) }

// announceReleases posts the releases the deployed game server contains that haven't
// been announced yet. On first use it announces only the newest live release.
func (s *Service) announceReleases(ctx context.Context) error {
	if s.cfg.ReleaseChannelID == "" || s.cfg.Deployer == nil {
		return nil
	}
	deployed, err := s.cfg.Deployer.Deployed(ctx)
	if err != nil || deployed == "" {
		return err
	}
	if checked, err := s.st.Get(ctx, releaseCheckedKey); err != nil || checked == deployed {
		return err
	}
	all, err := s.gh.Releases(ctx)
	if err != nil {
		return err
	}
	type release struct {
		github.Release
		v version
	}
	var rels []release
	for _, r := range all {
		if v, ok := parseVersion(r.TagName); ok && !r.Draft && !r.Prerelease {
			rels = append(rels, release{r, v})
		}
	}
	slices.SortFunc(rels, func(a, b release) int { return a.v.compare(b.v) })

	last, err := s.st.Get(ctx, releaseAnnouncedKey)
	if err != nil {
		return err
	}
	var pending []release
	if lastV, ok := parseVersion(last); ok {
		for _, r := range rels {
			if r.v.compare(lastV) > 0 {
				pending = append(pending, r)
			}
		}
	} else {
		// First run: don't replay history, just the newest release that's live.
		for i := len(rels) - 1; i >= 0; i-- {
			live, err := s.contains(ctx, deployed, rels[i].Target)
			if err != nil {
				return err
			}
			if live {
				pending = rels[i : i+1]
				break
			}
		}
	}
	for _, r := range pending {
		live, err := s.contains(ctx, deployed, r.Target)
		if err != nil {
			return err
		}
		if !live {
			break // later releases can't be live either
		}
		if err := s.chat.Post(ctx, s.cfg.ReleaseChannelID, releasePost(r.Release)); err != nil {
			return fmt.Errorf("announce %s: %w", r.TagName, err)
		}
		s.log.Info("announced release", "tag", r.TagName)
		if err := s.st.Set(ctx, releaseAnnouncedKey, r.TagName); err != nil {
			return err
		}
	}
	if err := s.announceEdge(ctx, deployed); err != nil {
		return err
	}
	return s.st.Set(ctx, releaseCheckedKey, deployed)
}

// announceEdge posts legacy and feature-owned edge bullets at deployed that haven't been
// announced. On first use it only records them. A bullet that leaves the edge (released,
// or reworded) is forgotten, so a reworded one is announced again.
func (s *Service) announceEdge(ctx context.Context, deployed string) error {
	raw, err := s.gh.FileContent(ctx, changelogPath, deployed)
	var apiErr *github.APIError
	if errors.As(err, &apiErr) && apiErr.Status == http.StatusNotFound {
		raw, err = nil, nil
	}
	if err != nil {
		return err
	}
	edge := edgeBullets(string(raw))
	lastRelease, err := s.st.Get(ctx, releaseAnnouncedKey)
	if err != nil {
		return err
	}
	featureNotes, err := s.featureEdge(ctx, deployed, lastRelease)
	if err != nil {
		return err
	}
	edge = append(edge, featureNotes...)
	saved, err := s.st.Get(ctx, edgeAnnouncedKey)
	if err != nil {
		return err
	}
	if saved != "" {
		var announced []string
		if err := json.Unmarshal([]byte(saved), &announced); err != nil {
			return fmt.Errorf("stored %s: %w", edgeAnnouncedKey, err)
		}
		var fresh []string
		for _, b := range edge {
			if !slices.Contains(announced, b) {
				fresh = append(fresh, b)
			}
		}
		if len(fresh) > 0 {
			link := fmt.Sprintf("https://github.com/%s/blob/%s/%s", s.cfg.Repo, deployed, changelogPath)
			if len(featureNotes) > 0 {
				link = fmt.Sprintf("https://github.com/%s/tree/%s/game/features", s.cfg.Repo, deployed)
			}
			if err := s.chat.Post(ctx, s.cfg.ReleaseChannelID, edgePost(fresh, link)); err != nil {
				return fmt.Errorf("announce edge: %w", err)
			}
			s.log.Info("announced edge", "bullets", len(fresh), "sha", deployed)
		}
	}
	b, err := json.Marshal(append([]string{}, edge...))
	if err != nil {
		return err
	}
	return s.st.Set(ctx, edgeAnnouncedKey, string(b))
}

var featureNotePath = regexp.MustCompile(`^game/features/[^/]+/release_notes/[^/]+\.json$`)

// featureEdge collects files added since the latest live release, at the deployed commit.
// Immutable filenames give every PR its own note, including changes to the same feature.
func (s *Service) featureEdge(ctx context.Context, deployed, tag string) ([]string, error) {
	paths, err := s.gh.FilePaths(ctx, deployed)
	if err != nil {
		return nil, err
	}
	old := map[string]bool{}
	if _, ok := parseVersion(tag); ok {
		previous, err := s.gh.FilePaths(ctx, tag)
		if err != nil {
			return nil, err
		}
		for _, path := range previous {
			old[path] = true
		}
	}
	slices.Sort(paths)
	var bullets []string
	for _, path := range paths {
		if old[path] || !featureNotePath.MatchString(path) {
			continue
		}
		raw, err := s.gh.FileContent(ctx, path, deployed)
		if err != nil {
			return nil, err
		}
		var note struct {
			Title   string   `json:"title"`
			Summary string   `json:"summary"`
			Notes   []string `json:"notes"`
		}
		if err := json.Unmarshal(raw, &note); err != nil {
			return nil, fmt.Errorf("feature note %s: %w", path, err)
		}
		if strings.TrimSpace(note.Title) == "" || strings.TrimSpace(note.Summary) == "" || len(note.Notes) == 0 {
			return nil, fmt.Errorf("incomplete feature note %s", path)
		}
		for _, text := range note.Notes {
			if strings.TrimSpace(text) == "" || strings.ContainsAny(text, "\r\n") || strings.HasPrefix(text, "- ") || strings.HasPrefix(text, "* ") {
				return nil, fmt.Errorf("invalid bullet in feature note %s", path)
			}
			bullets = append(bullets, "- "+text)
		}
	}
	return bullets, nil
}

// edgeBullets returns the bullets of the `## [edge]` section of a CHANGELOG.md, each
// with its indented continuation lines.
func edgeBullets(changelog string) []string {
	var out []string
	inEdge := false
	for _, line := range strings.Split(strings.ReplaceAll(changelog, "\r\n", "\n"), "\n") {
		switch {
		case strings.HasPrefix(line, "## "):
			inEdge = strings.TrimSpace(line) == "## [edge]"
		case !inEdge:
		case strings.HasPrefix(line, "- ") || strings.HasPrefix(line, "* "):
			out = append(out, strings.TrimRight(line, " \t"))
		case len(out) > 0 && strings.TrimSpace(line) != "" &&
			(strings.HasPrefix(line, " ") || strings.HasPrefix(line, "\t")):
			out[len(out)-1] += "\n" + strings.TrimRight(line, " \t")
		}
	}
	return out
}

// contains reports whether commit deployed includes commit sha.
func (s *Service) contains(ctx context.Context, deployed, sha string) (bool, error) {
	if sha == deployed {
		return true, nil
	}
	cmp, err := s.gh.Compare(ctx, sha, deployed)
	if err != nil {
		return false, err
	}
	return cmp.Status == "identical" || cmp.Status == "ahead", nil
}

// releasePost is the channel message for r: a heading, its notes (shortened to fit a
// Discord message) and a link.
func releasePost(r github.Release) string {
	return notesPost(fmt.Sprintf("🎉 **%s is out!** Reload the game to play it.", r.TagName), r.Body, r.URL)
}

// edgePost is the channel message for newly live edge bullets.
func edgePost(bullets []string, link string) string {
	return notesPost("🧪 **New on edge** (coming in the next release). Reload the game to try it.",
		strings.Join(bullets, "\n"), link)
}

// notesPost is head, then notes shortened to fit a Discord message, then url.
func notesPost(head, notes, url string) string {
	link := fmt.Sprintf("<%s>", url)
	notes = strings.TrimSpace(strings.ReplaceAll(notes, "\r\n", "\n"))
	if room := maxReleasePost - len(head) - len(link) - 8; len(notes) > room {
		cut := strings.LastIndexByte(notes[:room], '\n')
		if cut <= 0 {
			cut = room
			for cut > 0 && !utf8.RuneStart(notes[cut]) {
				cut--
			}
		}
		notes = strings.TrimSpace(notes[:cut]) + "\n…"
	}
	if notes == "" {
		return head + "\n" + link
	}
	return head + "\n\n" + notes + "\n\n" + link
}
