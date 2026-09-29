package core

import (
	"context"
	"slices"
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

func changelog(edge ...string) string {
	return "# Changelog\n\nIntro.\n\n## [edge]\n\n" + strings.Join(edge, "\n") +
		"\n\n## [0.6.0](https://x) - 2026-09-28\n\n- Seed.\n"
}

func TestEdgeBullets(t *testing.T) {
	got := edgeBullets(changelog("- Add hats.\n  With feathers.", "", "- Fix frogs.", "Not a bullet."))
	want := []string{"- Add hats.\n  With feathers.", "- Fix frogs."}
	if !slices.Equal(got, want) {
		t.Errorf("bullets %q", got)
	}
	if got := edgeBullets("# Changelog\n\n## [0.6.0]\n\n- Old.\n"); len(got) != 0 {
		t.Errorf("no edge: %q", got)
	}
}

func TestEdgeChangesAreAnnouncedOnceLive(t *testing.T) {
	e := newEnv(t)
	ctx := context.Background()
	e.gh.releases = []github.Release{release("v0.6.0", "t0", "- Seed.")}
	e.gh.compare["t0...d1"] = "ahead"
	e.gh.compare["t0...d2"] = "ahead"
	e.gh.compare["t0...d3"] = "ahead"
	e.gh.compare["t0...d4"] = "ahead"

	// First run: the edge is recorded, not replayed.
	e.deploy.deployed = "d1"
	e.gh.contents["CHANGELOG.md@d1"] = changelog("- Add hats.")
	must(t, e.svc.MergeStep(ctx))
	if posts := e.releasePosts(); len(posts) != 1 || !strings.Contains(posts[0], "v0.6.0 is out") {
		t.Fatalf("posts %q", posts)
	}

	// New bullets are posted once, with a link to the changelog at the deploy.
	e.deploy.deployed = "d2"
	e.gh.contents["CHANGELOG.md@d2"] = changelog("- Add hats.", "- Add boats.\n  Big ones.", "- Fix frogs.")
	must(t, e.svc.MergeStep(ctx))
	must(t, e.svc.MergeStep(ctx))
	posts := e.releasePosts()
	want := "🧪 **New on edge** (coming in the next release). Reload the game to try it.\n\n" +
		"- Add boats.\n  Big ones.\n- Fix frogs.\n\n<https://github.com/o/r/blob/d2/CHANGELOG.md>"
	if len(posts) != 2 || posts[1] != want {
		t.Fatalf("posts %q", posts)
	}

	// A deploy with no new edge bullets posts nothing.
	e.deploy.deployed = "d3"
	e.gh.contents["CHANGELOG.md@d3"] = changelog("- Add hats.", "- Add boats.\n  Big ones.", "- Fix frogs.")
	must(t, e.svc.MergeStep(ctx))
	if len(e.releasePosts()) != 2 {
		t.Fatalf("posts %q", e.releasePosts())
	}

	// A release empties the edge: the release is announced, then only what's new since.
	e.gh.releases = append([]github.Release{release("v0.7.0", "d4", "- Add hats.\n- Add boats.")}, e.gh.releases...)
	e.deploy.deployed = "d4"
	e.gh.contents["CHANGELOG.md@d4"] = changelog("- Add hats.", "- Add kites.")
	must(t, e.svc.MergeStep(ctx))
	posts = e.releasePosts()
	if len(posts) != 4 || !strings.Contains(posts[2], "v0.7.0 is out") ||
		!strings.Contains(posts[3], "\n\n- Add kites.\n\n") {
		t.Fatalf("posts %q", posts)
	}
}

func TestEdgeWithoutAChangelog(t *testing.T) {
	e := newEnv(t)
	ctx := context.Background()
	e.deploy.deployed = "d1"
	must(t, e.svc.MergeStep(ctx)) // CHANGELOG.md is missing: nothing to announce
	e.deploy.deployed = "d2"
	e.gh.contents["CHANGELOG.md@d2"] = changelog("- Add hats.")
	must(t, e.svc.MergeStep(ctx))
	if posts := e.releasePosts(); len(posts) != 1 || !strings.Contains(posts[0], "- Add hats.") {
		t.Fatalf("posts %q", posts)
	}
}

func TestFeatureEdgeAnnouncementsFollowDeployAndRelease(t *testing.T) {
	e := newEnv(t)
	ctx := context.Background()
	old := "game/features/hats/release_notes/100-hats.json"
	fresh := "game/features/frogs/release_notes/101-frogs.json"
	hat := `{"title":"Hats","summary":"Wear hats.","notes":["Add hats."]}`
	frog := `{"title":"Frogs","summary":"Watch frogs.","notes":["Add frogs.","Color frogs."]}`
	e.gh.releases = []github.Release{release("v0.6.0", "t0", "- Add hats.")}
	e.gh.contents[old+"@v0.6.0"] = hat
	for _, deploy := range []string{"d1", "d2", "d3"} {
		e.gh.contents[old+"@"+deploy] = hat
		e.gh.compare["t0..."+deploy] = "ahead"
	}
	e.deploy.deployed = "d1"
	must(t, e.svc.MergeStep(ctx))
	e.gh.contents[fresh+"@d2"] = frog
	e.deploy.deployed = "d2"
	must(t, e.svc.MergeStep(ctx))
	must(t, e.svc.MergeStep(ctx))
	posts := e.releasePosts()
	if len(posts) != 2 || !strings.Contains(posts[1], "- Add frogs.\n- Color frogs.") || strings.Contains(posts[1], "- Add hats.") {
		t.Fatalf("feature notes %q", posts)
	}
	// A live release removes both files from edge without replaying either.
	e.gh.contents[fresh+"@d3"] = frog
	e.gh.contents[old+"@v0.7.0"] = hat
	e.gh.contents[fresh+"@v0.7.0"] = frog
	e.gh.releases = append(e.gh.releases, release("v0.7.0", "d3", "- Add frogs."))
	e.deploy.deployed = "d3"
	must(t, e.svc.MergeStep(ctx))
	if posts = e.releasePosts(); len(posts) != 3 || !strings.Contains(posts[2], "v0.7.0 is out") {
		t.Fatalf("after release %q", posts)
	}
}

func TestFeatureEdgeRejectsMalformedNotesWithoutMarkingDeployChecked(t *testing.T) {
	e := newEnv(t)
	ctx := context.Background()
	e.deploy.deployed = "d1"
	e.gh.contents["game/features/frogs/release_notes/101-frogs.json@d1"] = `{bad`
	if err := e.svc.MergeStep(ctx); err == nil {
		t.Fatal("malformed feature note accepted")
	}
	if checked, err := e.st.Get(ctx, releaseCheckedKey); err != nil || checked != "" {
		t.Fatalf("failed deploy was marked checked: %q %v", checked, err)
	}
}
