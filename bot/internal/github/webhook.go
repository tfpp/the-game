package github

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"strings"
)

// ValidSignature checks an X-Hub-Signature-256 header ("sha256=<hex>") against body.
func ValidSignature(secret []byte, body []byte, header string) bool {
	got, ok := strings.CutPrefix(header, "sha256=")
	if !ok || len(secret) == 0 {
		return false
	}
	sig, err := hex.DecodeString(got)
	if err != nil {
		return false
	}
	mac := hmac.New(sha256.New, secret)
	mac.Write(body)
	return hmac.Equal(sig, mac.Sum(nil))
}

// Repository identifies the repository an event came from.
type Repository struct {
	FullName string `json:"full_name"`
}

// IssueCommentEvent is the issue_comment webhook payload (issues and PRs alike).
type IssueCommentEvent struct {
	Action string `json:"action"`
	Issue  struct {
		Number int `json:"number"`
	} `json:"issue"`
	Comment    Comment    `json:"comment"`
	Repository Repository `json:"repository"`
}

// PullRequestEvent is the pull_request webhook payload.
type PullRequestEvent struct {
	Action      string `json:"action"`
	Number      int    `json:"number"`
	PullRequest struct {
		HTMLURL        string `json:"html_url"`
		Merged         bool   `json:"merged"`
		MergeCommitSHA string `json:"merge_commit_sha"`
		Head           struct {
			Ref string `json:"ref"`
			SHA string `json:"sha"`
		} `json:"head"`
	} `json:"pull_request"`
	Repository Repository `json:"repository"`
}

// IssuesEvent is the issues webhook payload.
type IssuesEvent struct {
	Action string `json:"action"` // opened, closed, reopened, ...
	Issue  struct {
		Number int `json:"number"`
	} `json:"issue"`
	Repository Repository `json:"repository"`
}

// WorkflowRunEvent is the workflow_run webhook payload.
type WorkflowRunEvent struct {
	Action      string      `json:"action"` // requested, in_progress, completed
	WorkflowRun WorkflowRun `json:"workflow_run"`
	Repository  Repository  `json:"repository"`
}
