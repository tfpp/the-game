package core

import (
	"context"
	"fmt"
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
// ReleaseChannelID, oldest first, each once.

const (
	releaseAnnouncedKey = "release_announced" // version of the last announced release
	releaseCheckedKey   = "release_checked"   // deploy the releases were last checked for
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
	return s.st.Set(ctx, releaseCheckedKey, deployed)
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
	head := fmt.Sprintf("🎉 **%s is out!** Reload the game to play it.", r.TagName)
	link := fmt.Sprintf("<%s>", r.URL)
	notes := strings.TrimSpace(strings.ReplaceAll(r.Body, "\r\n", "\n"))
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
