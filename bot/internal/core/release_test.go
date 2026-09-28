package core

import (
	"context"
	"strings"
	"testing"

	"github.com/tfpp/the-game/bot/internal/github"
)

func release(tag, target, body string) github.Release {
	return github.Release{TagName: tag, Target: target, Body: body, URL: "https://gh/releases/tag/" + tag}
}

// releasePosts returns the posts to the release channel.
func (e *env) releasePosts() []string {
	var out []string
	for _, p := range e.chat.posts {
		if p.thread == "releases" {
			out = append(out, p.content)
		}
	}
	return out
}

func TestReleasesAreAnnouncedOnceLive(t *testing.T) {
	e := newEnv(t)
	ctx := context.Background()
	e.gh.releases = []github.Release{
		release("v0.6.2", "t2", "- Add hats."),
		release("v0.6.1", "t1", "- Add frogs."),
		release("v0.6.0", "t0", "- Seed."),
		{TagName: "v0.7.0", Target: "t9", Draft: true},
		release("nightly", "t8", ""),
	}
	e.deploy.deployed = "d1"
	e.gh.compare["t0...d1"] = "ahead"
	e.gh.compare["t1...d1"] = "ahead"
	e.gh.compare["t2...d1"] = "behind" // not deployed yet

	// The first check announces just the newest live release, not the history.
	must(t, e.svc.MergeStep(ctx))
	posts := e.releasePosts()
	if len(posts) != 1 || posts[0] != "🎉 **v0.6.1 is out!** Reload the game to play it.\n\n- Add frogs.\n\n<https://gh/releases/tag/v0.6.1>" {
		t.Fatalf("posts %q", posts)
	}
	// Nothing new is deployed: no second look at GitHub, no repeat.
	calls := e.gh.releaseCalls
	must(t, e.svc.MergeStep(ctx))
	if e.gh.releaseCalls != calls || len(e.releasePosts()) != 1 {
		t.Fatalf("rechecked: calls %d posts %q", e.gh.releaseCalls, e.releasePosts())
	}

	// The next deploy contains v0.6.2 and v0.6.3 (announced in order), not v0.6.4.
	e.gh.releases = append([]github.Release{
		release("v0.6.4", "t4", "- Later."),
		release("v0.6.3", "t3", "- Fix boats."),
	}, e.gh.releases...)
	e.deploy.deployed = "t3"
	e.gh.compare["t2...t3"] = "ahead"
	e.gh.compare["t4...t3"] = "behind"
	must(t, e.svc.MergeStep(ctx))
	posts = e.releasePosts()
	if len(posts) != 3 || !strings.Contains(posts[1], "v0.6.2 is out") || !strings.Contains(posts[2], "v0.6.3 is out") {
		t.Fatalf("posts %q", posts)
	}
}

func TestReleaseAnnouncementsNeedAChannel(t *testing.T) {
	e := newEnv(t)
	e.svc.cfg.ReleaseChannelID = ""
	e.gh.releases = []github.Release{release("v0.6.0", "d1", "- Seed.")}
	e.deploy.deployed = "d1"
	must(t, e.svc.MergeStep(context.Background()))
	if e.gh.releaseCalls != 0 || len(e.releasePosts()) != 0 {
		t.Fatalf("calls %d posts %q", e.gh.releaseCalls, e.releasePosts())
	}
}

func TestReleasePostFitsInADiscordMessage(t *testing.T) {
	body := strings.Repeat("- A long line about a change that shipped in this release.\n", 60)
	post := releasePost(release("v1.2.3", "x", body))
	if len(post) > 2000 || !strings.Contains(post, "\n…\n\n<https://gh/releases/tag/v1.2.3>") {
		t.Fatalf("post (%d bytes) %q", len(post), post)
	}
	if got := releasePost(release("v1.2.3", "x", " ")); got != "🎉 **v1.2.3 is out!** Reload the game to play it.\n<https://gh/releases/tag/v1.2.3>" {
		t.Errorf("empty notes %q", got)
	}
}
