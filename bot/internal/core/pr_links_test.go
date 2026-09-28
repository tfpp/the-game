package core

import "testing"

func TestFormatPRLinks(t *testing.T) {
	for _, tt := range []struct{ name, input, want string }{
		{"opened", "🤖 Opened https://github.com/tfpp/the-game/pull/123", "🤖 Opened [PR #123](<https://github.com/tfpp/the-game/pull/123>)"},
		{"angle link", "<https://github.com/tfpp/the-game/pull/123>", "[PR #123](<https://github.com/tfpp/the-game/pull/123>)"},
		{"punctuation", "See https://github.com/tfpp/the-game/pull/123.", "See [PR #123](<https://github.com/tfpp/the-game/pull/123>)."},
		{"anchor", "https://github.com/tfpp/the-game/pull/123#issuecomment-456", "[PR #123](<https://github.com/tfpp/the-game/pull/123#issuecomment-456>)"},
		{"existing label", "[Review](https://github.com/tfpp/the-game/pull/123)", "[Review](https://github.com/tfpp/the-game/pull/123)"},
		{"existing angle label", "[PR #123](<https://github.com/tfpp/the-game/pull/123>)", "[PR #123](<https://github.com/tfpp/the-game/pull/123>)"},
		{"issue", "https://github.com/tfpp/the-game/issues/123", "https://github.com/tfpp/the-game/issues/123"},
		{"invalid number", "https://github.com/tfpp/the-game/pull/123abc", "https://github.com/tfpp/the-game/pull/123abc"},
	} {
		t.Run(tt.name, func(t *testing.T) {
			if got := formatPRLinks(tt.input); got != tt.want {
				t.Errorf("got %q, want %q", got, tt.want)
			}
		})
	}
}
