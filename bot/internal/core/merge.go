package core

import (
	"context"
	"errors"
	"fmt"
	"net/http"
	"slices"
	"strconv"
	"strings"
	"time"

	"github.com/tfpp/the-game/bot/internal/github"
	"github.com/tfpp/the-game/bot/internal/store"
)

// Merging: a trusted Discord role approves a PR at its head SHA (a button under "CI
// passed", or /approve in the thread). Approvals queue up, and one coordinator merges them
// in order: it re-checks the head, brings the branch up to date with the base on GitHub's
// side and waits for CI when the base has moved, then squash-merges with the expected
// SHA. Conflicts send the PR to the agent in resolve-conflicts mode; the result needs a
// new approval. After a merge, the other open PRs are checked for new conflicts, and once
// the web client and server builds of a commit finish, the server is deployed.

const (
	// updateTimeout drops an approval whose branch update never shows up.
	updateTimeout = 10 * time.Minute
	// ciTimeout drops an approval whose CI run never starts or finishes.
	ciTimeout = 45 * time.Minute
	// conflictCheckFor is how long to keep asking GitHub for mergeability after the base
	// branch moves (it computes it in the background).
	conflictCheckFor = 10 * time.Minute

	approvePrefix = "approve:"
	autoUser      = "auto" // user ID of runs the bot starts on its own
	codeowners    = ".github/CODEOWNERS"
)

// Kick wakes the coordinator.
func (s *Service) Kick() {
	select {
	case s.kick <- struct{}{}:
	default:
	}
}

// RunCoordinator runs merge steps whenever something may have changed, and every
// interval, until ctx ends.
func (s *Service) RunCoordinator(ctx context.Context, interval time.Duration) {
	t := time.NewTicker(interval)
	defer t.Stop()
	for {
		if err := s.MergeStep(ctx); err != nil && ctx.Err() == nil {
			s.log.Error("merge step", "err", err)
		}
		select {
		case <-ctx.Done():
			return
		case <-t.C:
		case <-s.kick:
		}
	}
}

// --- approving -----------------------------------------------------------------------------

// ApproveRequest is an Approve & merge button press or an /approve command in a thread.
type ApproveRequest struct {
	UserID   string
	UserName string
	HasRole  bool // the approver role
	ThreadID string
	ButtonID string // the pressed button's custom ID; "" for /approve (the current head)
}

// ApproveButtonID is the custom ID of the Approve & merge button for pr at sha.
func ApproveButtonID(pr int, sha string) string {
	return fmt.Sprintf("%s%d:%s", approvePrefix, pr, sha)
}

// IsApproveButton reports whether a button's custom ID is an Approve & merge button.
func IsApproveButton(id string) bool { return strings.HasPrefix(id, approvePrefix) }

// Approve checks an approval and adds it to the merge queue. The responder's answers are
// for the approver only; the thread hears about it publicly.
func (s *Service) Approve(ctx context.Context, req ApproveRequest, r Responder) error {
	var pr int
	var sha string
	if req.ButtonID != "" {
		p, h, _ := strings.Cut(strings.TrimPrefix(req.ButtonID, approvePrefix), ":")
		pr, _ = strconv.Atoi(p)
		sha = h
	}
	if !req.HasRole {
		return r.Reject(ctx, "You need the approver role to approve merges.")
	}
	job, err := s.st.JobByThread(ctx, req.ThreadID)
	if errors.Is(err, store.ErrNotFound) {
		return r.Reject(ctx, "Use `/approve` inside a feature's thread.")
	} else if err != nil {
		return err
	}
	switch {
	case job.State != store.JobOpen:
		return r.Reject(ctx, "This feature's PR is "+job.State+".")
	case job.PR == 0:
		return r.Reject(ctx, "There's no PR to approve yet.")
	case pr != 0 && pr != job.PR:
		return r.Reject(ctx, "That button belongs to another PR.")
	}
	if _, err := s.st.ActiveRunForJob(ctx, job.ID); err == nil {
		return r.Reject(ctx, "The agent is working on this PR. Wait for it to finish and for CI to pass.")
	} else if !errors.Is(err, store.ErrNotFound) {
		return err
	}
	if m, err := s.st.ActiveMergeForJob(ctx, job.ID); err == nil {
		return r.Reject(ctx, fmt.Sprintf("PR #%d is already in the merge queue (approved by %s).", job.PR, m.ApproverName))
	} else if !errors.Is(err, store.ErrNotFound) {
		return err
	}
	if err := r.Defer(ctx); err != nil {
		return err
	}
	head, problem, err := s.approvable(ctx, job, sha)
	if err != nil {
		s.log.Error("check approval", "err", err, "pr", job.PR)
		return r.Respond(ctx, "❌ I couldn't check the PR on GitHub. Try again later.")
	}
	if problem != "" {
		return r.Respond(ctx, problem)
	}
	name := cleanName(req.UserName)
	_, err = s.st.Enqueue(ctx, store.Merge{
		JobID: job.ID, PR: job.PR, ApprovedSHA: head, ApproverID: req.UserID, ApproverName: name,
	}, s.cfg.Now())
	if errors.Is(err, store.ErrQueued) {
		return r.Respond(ctx, fmt.Sprintf("PR #%d is already in the merge queue.", job.PR))
	} else if err != nil {
		return err
	}
	queue, err := s.st.MergeQueue(ctx)
	if err != nil {
		return err
	}
	pos := fmt.Sprintf("It's number %d in the merge queue.", len(queue))
	if len(queue) == 1 {
		pos = "Merging it now."
	}
	if err := r.Respond(ctx, fmt.Sprintf("Approved `%s`. %s", short(head), pos)); err != nil {
		s.log.Error("respond to approval", "err", err)
	}
	s.post(ctx, job, fmt.Sprintf("👍 <@%s> approved `%s` for merging. %s", req.UserID, short(head), pos))
	s.Kick()
	return nil
}

// approvable checks that the job's PR can be approved at sha (its head if ""), and returns
// the head, or a problem to tell the approver.
func (s *Service) approvable(ctx context.Context, job store.Job, sha string) (string, string, error) {
	pr, err := s.gh.PullRequest(ctx, job.PR)
	if err != nil {
		return "", "", err
	}
	switch {
	case pr.State != "open":
		return "", fmt.Sprintf("PR #%d is closed.", job.PR), nil
	case sha != "" && pr.Head.SHA != sha:
		return "", fmt.Sprintf("PR #%d has changed since `%s`. Approve its latest commit once CI passes on it.",
			job.PR, short(sha)), nil
	}
	sha = pr.Head.SHA
	hits, err := s.protectedFiles(ctx, job.PR)
	if err != nil {
		return "", "", err
	}
	if len(hits) > 0 {
		return "", fmt.Sprintf("PR #%d changes %s, which a maintainer has to review and merge on GitHub.",
			job.PR, listPaths(hits)), nil
	}
	switch ci, err := s.ciState(ctx, sha); {
	case err != nil:
		return "", "", err
	case ci == "success":
		return sha, "", nil
	case ci == "pending":
		return "", fmt.Sprintf("CI is still running on `%s`. Approve once it passes.", short(sha)), nil
	case ci == "none":
		return "", fmt.Sprintf("CI hasn't run on `%s` yet.", short(sha)), nil
	default:
		return "", fmt.Sprintf("CI failed on `%s`, so it can't be merged. Use `/revise` to fix it.", short(sha)), nil
	}
}

// ciPassed announces a green CI run in the job's thread, with the Approve & merge button
// when the PR could be approved from Discord.
func (s *Service) ciPassed(ctx context.Context, job store.Job, sha string) {
	msg := fmt.Sprintf("✅ CI passed on `%s`.", short(sha))
	if job.PR == 0 || job.State != store.JobOpen || job.ThreadID == "" {
		s.post(ctx, job, msg)
		return
	}
	if _, err := s.st.ActiveMergeForJob(ctx, job.ID); err == nil {
		s.post(ctx, job, msg+" The merge queue carries on.")
		return
	}
	hits, err := s.protectedFiles(ctx, job.PR)
	if err != nil {
		s.log.Error("protected files", "err", err, "pr", job.PR)
	} else if len(hits) > 0 {
		s.post(ctx, job, fmt.Sprintf("%s PR #%d changes %s, so a maintainer has to review and merge it on GitHub.",
			msg, job.PR, listPaths(hits)))
		return
	}
	if err := s.chat.PostButton(ctx, job.ThreadID, msg+" Anyone with the approver role can merge it.",
		"Approve & merge", ApproveButtonID(job.PR, sha)); err != nil {
		s.log.Error("post to thread", "err", err, "issue", job.Issue)
	}
}

// ciState is the newest pull_request CI run for sha: success, failure, pending or none.
func (s *Service) ciState(ctx context.Context, sha string) (string, error) {
	runs, err := s.gh.WorkflowRunsForSHA(ctx, s.cfg.CIWorkflow, sha)
	if err != nil {
		return "", err
	}
	for _, wr := range runs {
		if wr.Event != "pull_request" {
			continue
		}
		switch {
		case wr.Status != "completed":
			return "pending", nil
		case wr.Conclusion == "success":
			return "success", nil
		default:
			return "failure", nil
		}
	}
	return "none", nil
}

// protectedFiles returns the PR's paths that CODEOWNERS (on the base branch) reserves for
// humans.
func (s *Service) protectedFiles(ctx context.Context, pr int) ([]string, error) {
	owners, err := s.gh.FileContent(ctx, codeowners, s.cfg.Ref)
	if err != nil {
		return nil, fmt.Errorf("read %s: %w", codeowners, err)
	}
	files, err := s.gh.PullRequestFiles(ctx, pr)
	if err != nil {
		return nil, err
	}
	return protectedPaths(files, codeownersPatterns(string(owners))), nil
}

// codeownersPatterns returns the path patterns of a CODEOWNERS file, without the leading
// slash.
func codeownersPatterns(text string) []string {
	var out []string
	for _, line := range strings.Split(text, "\n") {
		f := strings.Fields(line)
		if len(f) == 0 || strings.HasPrefix(f[0], "#") {
			continue
		}
		out = append(out, strings.TrimPrefix(f[0], "/"))
	}
	return out
}

// protectedPaths returns the files matched by patterns, the way harness/lib.sh's
// filter_protected does: "dir/" matches everything below it, other patterns match the path
// itself and everything below it.
func protectedPaths(files, patterns []string) []string {
	var out []string
	for _, f := range files {
		for _, p := range patterns {
			if (strings.HasSuffix(p, "/") && strings.HasPrefix(f, p)) || f == p || strings.HasPrefix(f, p+"/") {
				if !slices.Contains(out, f) {
					out = append(out, f)
				}
				break
			}
		}
	}
	return out
}

func listPaths(paths []string) string {
	const max = 3
	var b strings.Builder
	for i, p := range paths {
		if i == max {
			fmt.Fprintf(&b, " and %d more", len(paths)-max)
			break
		}
		if i > 0 {
			b.WriteString(", ")
		}
		b.WriteString("`" + p + "`")
	}
	return b.String()
}

// pushed handles new commits on a job's PR: a queued approval of an older head is void.
func (s *Service) pushed(ctx context.Context, job store.Job, head string) error {
	m, err := s.st.ActiveMergeForJob(ctx, job.ID)
	if errors.Is(err, store.ErrNotFound) {
		return nil
	} else if err != nil {
		return err
	}
	if m.Status == store.MergeUpdating || head == m.HeadSHA {
		s.Kick() // probably the coordinator's own update; it checks
		return nil
	}
	return s.dropNewCommits(ctx, job, m)
}

func (s *Service) dropNewCommits(ctx context.Context, job store.Job, m store.Merge) error {
	s.post(ctx, job, fmt.Sprintf("↩️ New commits were pushed to PR #%d after it was approved, so it left the "+
		"merge queue. Approve it again once CI passes.", m.PR))
	return s.st.UpdateMerge(ctx, m.ID, store.MergeDropped, "", "new commits", s.cfg.Now())
}

// --- coordinating --------------------------------------------------------------------------

// MergeStep advances the merge queue as far as it can without waiting, then checks open
// PRs for conflicts, starts pending conflict resolutions and announces deploys.
func (s *Service) MergeStep(ctx context.Context) error {
	s.mergeMu.Lock()
	defer s.mergeMu.Unlock()
	for i := 0; i < 20; i++ {
		queue, err := s.st.MergeQueue(ctx)
		if err != nil {
			return err
		}
		if len(queue) == 0 {
			break
		}
		next, err := s.advance(ctx, queue[0])
		if err != nil {
			return err
		}
		if !next {
			break
		}
	}
	if err := s.checkConflicts(ctx); err != nil {
		return err
	}
	if err := s.resolvePending(ctx); err != nil {
		return err
	}
	s.drain(ctx)
	return s.announceDeploys(ctx)
}

// advance moves the approval at the front of the queue on, and reports whether it left
// the queue (so the next one can start).
func (s *Service) advance(ctx context.Context, m store.Merge) (bool, error) {
	now := s.cfg.Now()
	job, err := s.st.JobByID(ctx, m.JobID)
	if err != nil {
		return false, err
	}
	pr, err := s.gh.PullRequest(ctx, m.PR)
	if err != nil {
		return false, fmt.Errorf("get PR #%d: %w", m.PR, err)
	}
	switch {
	case pr.Merged:
		return true, s.merged(ctx, job, m, pr.MergeCommitSHA)
	case pr.State != "open":
		return true, s.drop(ctx, job, m, "closed", fmt.Sprintf("PR #%d was closed, so it left the merge queue.", m.PR))
	}
	head := pr.Head.SHA
	if head != m.HeadSHA {
		ok, err := m.Status == store.MergeUpdating, error(nil)
		if ok {
			ok, err = s.isBaseMerge(ctx, head, m.HeadSHA, pr.Base.Ref)
		}
		if err != nil {
			return false, err
		}
		if !ok {
			return true, s.dropNewCommits(ctx, job, m)
		}
		// Our own update: the approval carries over to the new head, which needs CI.
		if err := s.st.UpdateMerge(ctx, m.ID, store.MergeTesting, head, "", now); err != nil {
			return false, err
		}
		m.HeadSHA, m.Status, m.UpdatedAt = head, store.MergeTesting, now
	}
	if pr.Mergeable != nil && !*pr.Mergeable {
		return true, s.conflict(ctx, job, m, head)
	}
	cmp, err := s.gh.Compare(ctx, pr.Base.Ref, head)
	if err != nil {
		return false, err
	}
	if cmp.BehindBy > 0 {
		if m.Status == store.MergeUpdating {
			if now.Sub(m.UpdatedAt) > updateTimeout {
				return true, s.drop(ctx, job, m, "update timed out", fmt.Sprintf(
					"⚠️ GitHub didn't bring PR #%d up to date with %s, so it left the merge queue. Approve it again to retry.",
					m.PR, pr.Base.Ref))
			}
			return false, nil
		}
		err := s.gh.UpdateBranch(ctx, m.PR, head)
		var apiErr *github.APIError
		switch {
		case errors.As(err, &apiErr) && apiErr.Status == http.StatusUnprocessableEntity &&
			strings.Contains(strings.ToLower(apiErr.Message), "conflict"):
			return true, s.conflict(ctx, job, m, head)
		case errors.As(err, &apiErr) && apiErr.Status/100 == 4:
			return true, s.drop(ctx, job, m, "update failed: "+apiErr.Message, fmt.Sprintf(
				"⚠️ I couldn't bring PR #%d up to date with %s (GitHub said: %s), so it left the merge queue. "+
					"A maintainer has to merge it on GitHub.", m.PR, pr.Base.Ref, apiErr.Message))
		case err != nil:
			return false, err
		}
		if err := s.st.UpdateMerge(ctx, m.ID, store.MergeUpdating, head, "", now); err != nil {
			return false, err
		}
		s.post(ctx, job, fmt.Sprintf("🔄 PR #%d is next in the merge queue. Bringing it up to date with %s, "+
			"then waiting for CI.", m.PR, pr.Base.Ref))
		return false, nil
	}

	ci, err := s.ciState(ctx, head)
	if err != nil {
		return false, err
	}
	switch ci {
	case "pending", "none":
		if m.Status != store.MergeTesting {
			if err := s.st.UpdateMerge(ctx, m.ID, store.MergeTesting, head, "", now); err != nil {
				return false, err
			}
		} else if now.Sub(m.UpdatedAt) > ciTimeout {
			return true, s.drop(ctx, job, m, "CI timed out", fmt.Sprintf(
				"⚠️ CI didn't finish on `%s`, so PR #%d left the merge queue. Approve it again to retry.", short(head), m.PR))
		}
		return false, nil
	case "failure":
		msg := fmt.Sprintf("❌ <@%s> CI failed on `%s` after bringing PR #%d up to date, so it left the merge queue. "+
			"Use `/revise` to fix it.", job.RequesterID, short(head), m.PR)
		if job.ThreadID != "" {
			if err := s.chat.Post(ctx, job.ThreadID, msg, job.RequesterID); err != nil {
				s.log.Error("post to thread", "err", err, "issue", job.Issue)
			}
		}
		return true, s.st.UpdateMerge(ctx, m.ID, store.MergeDropped, "", "CI failed", now)
	}

	title := fmt.Sprintf("%s (#%d)", pr.Title, m.PR)
	body := fmt.Sprintf("Requested-by: %s on Discord\nApproved-by: %s on Discord\n", job.RequesterName, m.ApproverName)
	sha, err := s.gh.SquashMerge(ctx, m.PR, head, title, body)
	var apiErr *github.APIError
	switch {
	case errors.As(err, &apiErr) && apiErr.Status == http.StatusConflict:
		return false, nil // the head moved under us; the next step sees it
	case errors.As(err, &apiErr) && apiErr.Status/100 == 4:
		return true, s.drop(ctx, job, m, "merge failed: "+apiErr.Message, fmt.Sprintf(
			"⚠️ GitHub refused to merge PR #%d (%s), so it left the merge queue.", m.PR, apiErr.Message))
	case err != nil:
		return false, err
	}
	if err := s.merged(ctx, job, m, sha); err != nil {
		return false, err
	}
	if err := s.gh.DeleteBranch(ctx, pr.Head.Ref); err != nil {
		s.log.Warn("delete merged branch", "err", err, "branch", pr.Head.Ref)
	}
	return true, s.scheduleConflictCheck(ctx)
}

// isBaseMerge reports whether head is prev with the base branch merged in: a merge commit
// whose first parent is prev and whose second is in the base's history. That is what
// update-branch makes, so it brings no new changes of its own.
func (s *Service) isBaseMerge(ctx context.Context, head, prev, base string) (bool, error) {
	parents, err := s.gh.CommitParents(ctx, head)
	if err != nil || len(parents) != 2 || parents[0] != prev {
		return false, err
	}
	cmp, err := s.gh.Compare(ctx, parents[1], base)
	if err != nil {
		return false, err
	}
	return cmp.Status == "identical" || cmp.Status == "ahead", nil
}

func (s *Service) merged(ctx context.Context, job store.Job, m store.Merge, sha string) error {
	now := s.cfg.Now()
	if err := s.st.SetMerged(ctx, m.ID, sha, now); err != nil {
		return err
	}
	if job.State != store.JobMerged {
		if err := s.st.SetJobState(ctx, job.ID, store.JobMerged, now); err != nil {
			return err
		}
		if job.ThreadID != "" {
			msg := fmt.Sprintf("🎉 <@%s> PR #%d was merged (approved by %s). It goes live once the web client "+
				"and server builds finish.", job.RequesterID, m.PR, m.ApproverName)
			if err := s.chat.Post(ctx, job.ThreadID, msg, job.RequesterID); err != nil {
				s.log.Error("post to thread", "err", err, "issue", job.Issue)
			}
		}
	}
	return nil
}

func (s *Service) drop(ctx context.Context, job store.Job, m store.Merge, detail, msg string) error {
	s.post(ctx, job, msg)
	return s.st.UpdateMerge(ctx, m.ID, store.MergeDropped, "", detail, s.cfg.Now())
}

// --- conflicts -----------------------------------------------------------------------------

// conflict takes a conflicting PR out of the queue and asks the agent to resolve it.
func (s *Service) conflict(ctx context.Context, job store.Job, m store.Merge, head string) error {
	if err := s.st.UpdateMerge(ctx, m.ID, store.MergeDropped, "", "conflicts", s.cfg.Now()); err != nil {
		return err
	}
	s.post(ctx, job, fmt.Sprintf("⚠️ PR #%d conflicts with %s, so it left the merge queue. I'll ask the agent to "+
		"resolve the conflicts; approve it again once CI passes.", m.PR, s.cfg.Ref))
	return s.markConflict(ctx, job, head)
}

func (s *Service) markConflict(ctx context.Context, job store.Job, head string) error {
	if err := s.st.SetConflict(ctx, job.ID, head, s.cfg.Now()); err != nil {
		return err
	}
	job.ConflictSHA = head
	return s.resolve(ctx, job)
}

// resolve starts a resolve-conflicts run for a job whose head conflicts, unless one ran
// for that head already. If the agent is busy, the run waits for a free slot.
func (s *Service) resolve(ctx context.Context, job store.Job) error {
	if job.ConflictSHA == "" || job.ConflictSHA == job.ResolveSHA || job.State != store.JobOpen {
		return nil
	}
	if _, err := s.st.ActiveRunForJob(ctx, job.ID); err == nil {
		return nil
	} else if !errors.Is(err, store.ErrNotFound) {
		return err
	}
	lim := s.cfg.Limits
	lim.PerUser = 0 // the bot's own runs count only toward the concurrency cap
	s.mu.Lock()
	run, err := s.st.Reserve(ctx, autoUser, job.ID, "resolve-conflicts", "", lim, s.cfg.Now())
	s.mu.Unlock()
	if err != nil {
		return err
	}
	if err := s.st.SetResolve(ctx, job.ID, job.ConflictSHA, s.cfg.Now()); err != nil {
		return err
	}
	if run.Status == store.RunWaiting {
		s.post(ctx, job, fmt.Sprintf("🔧 The agent is busy; it will resolve PR #%d's conflicts when a slot frees up (%s).",
			job.PR, s.linePosition(ctx, run.ID)))
		return nil
	}
	if err := s.dispatch(ctx, run, job.PR, ""); err != nil {
		return s.st.SetResolve(ctx, job.ID, "", s.cfg.Now()) // retry later
	}
	s.post(ctx, job, fmt.Sprintf("🔧 The agent is merging %s into PR #%d and resolving the conflicts.", s.cfg.Ref, job.PR))
	return nil
}

// resolvePending retries conflict resolutions that had to wait for a free agent slot.
func (s *Service) resolvePending(ctx context.Context) error {
	jobs, err := s.st.OpenJobsWithPR(ctx)
	if err != nil {
		return err
	}
	for _, job := range jobs {
		if job.ConflictSHA == "" || job.ConflictSHA == job.ResolveSHA {
			continue
		}
		pr, err := s.gh.PullRequest(ctx, job.PR)
		if err != nil {
			return err
		}
		if pr.State != "open" || pr.Head.SHA != job.ConflictSHA {
			// Someone else pushed; the next conflict check looks at the new head.
			if err := s.st.SetConflict(ctx, job.ID, "", s.cfg.Now()); err != nil {
				return err
			}
			continue
		}
		if err := s.resolve(ctx, job); err != nil {
			return err
		}
	}
	return nil
}

const conflictCheckKey = "conflict_check_since"

func (s *Service) scheduleConflictCheck(ctx context.Context) error {
	if err := s.st.Set(ctx, conflictCheckKey, strconv.FormatInt(s.cfg.Now().Unix(), 10)); err != nil {
		return err
	}
	s.Kick()
	return nil
}

// checkConflicts, after the base branch moved, warns the threads of open PRs that now
// conflict with it and asks the agent to resolve them. GitHub computes mergeability in the
// background, so undecided PRs are asked again on later steps for a while.
func (s *Service) checkConflicts(ctx context.Context) error {
	v, err := s.st.Get(ctx, conflictCheckKey)
	if err != nil || v == "" {
		return err
	}
	since, _ := strconv.ParseInt(v, 10, 64)
	jobs, err := s.st.OpenJobsWithPR(ctx)
	if err != nil {
		return err
	}
	undecided := false
	for _, job := range jobs {
		pr, err := s.gh.PullRequest(ctx, job.PR)
		if err != nil {
			return err
		}
		switch {
		case pr.State != "open":
		case pr.Mergeable == nil:
			undecided = true
		case !*pr.Mergeable && job.ConflictSHA != pr.Head.SHA:
			if _, err := s.st.ActiveMergeForJob(ctx, job.ID); err == nil {
				continue // the coordinator deals with it when its turn comes
			}
			if job.ThreadID != "" {
				msg := fmt.Sprintf("⚠️ <@%s> PR #%d conflicts with %s now. I'll ask the agent to resolve the conflicts.",
					job.RequesterID, job.PR, s.cfg.Ref)
				if err := s.chat.Post(ctx, job.ThreadID, msg, job.RequesterID); err != nil {
					s.log.Error("post to thread", "err", err, "issue", job.Issue)
				}
			}
			if err := s.markConflict(ctx, job, pr.Head.SHA); err != nil {
				return err
			}
		}
	}
	if undecided && s.cfg.Now().Unix()-since < int64(conflictCheckFor/time.Second) {
		return nil
	}
	return s.st.Set(ctx, conflictCheckKey, "")
}

// --- deploys -------------------------------------------------------------------------------

const deployRequestedKey = "deploy_requested"

// built records a finished build of sha on the base branch, and deploys the server once
// both the server image and the web client of the same commit are out.
func (s *Service) built(ctx context.Context, kind, sha string) error {
	if s.cfg.Deployer == nil || sha == "" {
		return nil
	}
	if err := s.st.Set(ctx, "built_"+kind, sha); err != nil {
		return err
	}
	server, err := s.st.Get(ctx, "built_server")
	if err != nil {
		return err
	}
	pages, err := s.st.Get(ctx, "built_pages")
	if err != nil || server != pages {
		return err
	}
	return s.requestDeploy(ctx, "server", deployRequestedKey, sha, s.cfg.Deployer.Deploy)
}

const apiDeployRequestedKey = "api_deploy_requested"

// builtAPI deploys the accounts API image built from sha on the base branch. The API
// image only builds when api/ changes, and it doesn't wait for the game: API changes
// stay backward compatible, and the API builds faster than the server and web client,
// so a merge touching both deploys the API first.
func (s *Service) builtAPI(ctx context.Context, sha string) error {
	if s.cfg.Deployer == nil || sha == "" {
		return nil
	}
	return s.requestDeploy(ctx, "api", apiDeployRequestedKey, sha, s.cfg.Deployer.DeployAPI)
}

// requestDeploy asks the host to deploy sha unless it (or a newer commit) was already
// requested under key, so an older build finishing late never rolls a deploy back.
func (s *Service) requestDeploy(ctx context.Context, what, key, sha string,
	deploy func(context.Context, string) error) error {
	last, err := s.st.Get(ctx, key)
	if err != nil {
		return err
	}
	if last == sha {
		return nil
	}
	if last != "" {
		cmp, err := s.gh.Compare(ctx, last, sha)
		if err != nil {
			return err
		}
		if cmp.Status != "ahead" {
			return nil // an older build finished late
		}
	}
	if err := deploy(ctx, sha); err != nil {
		return fmt.Errorf("deploy %s %s: %w", what, short(sha), err)
	}
	s.log.Info("requested deploy", "what", what, "sha", sha)
	return s.st.Set(ctx, key, sha)
}

const deployAnnouncedKey = "deploy_announced"

// announceDeploys tells the threads of merged PRs once a deploy contains them.
func (s *Service) announceDeploys(ctx context.Context) error {
	if s.cfg.Deployer == nil {
		return nil
	}
	deployed, err := s.cfg.Deployer.Deployed(ctx)
	if err != nil || deployed == "" {
		return err
	}
	if last, err := s.st.Get(ctx, deployAnnouncedKey); err != nil || last == deployed {
		return err
	}
	merges, err := s.st.UnannouncedMerges(ctx)
	if err != nil {
		return err
	}
	for _, m := range merges {
		if m.MergedSHA != "" {
			cmp, err := s.gh.Compare(ctx, m.MergedSHA, deployed)
			if err != nil {
				return err
			}
			if cmp.Status != "identical" && cmp.Status != "ahead" {
				continue // not in this deploy
			}
			if job, err := s.st.JobByID(ctx, m.JobID); err == nil {
				s.post(ctx, job, fmt.Sprintf("🚀 PR #%d is live. Reload the game to try it.", m.PR))
			}
		}
		if err := s.st.SetAnnounced(ctx, m.ID); err != nil {
			return err
		}
	}
	return s.st.Set(ctx, deployAnnouncedKey, deployed)
}

// --- /queue --------------------------------------------------------------------------------

// Queue describes the agent runs ("agent") or the merge queue ("merge").
func (s *Service) Queue(ctx context.Context, kind string) (string, error) {
	var b strings.Builder
	switch kind {
	case "agent":
		active, err := s.st.ActiveRuns(ctx)
		if err != nil {
			return "", err
		}
		waiting, err := s.st.WaitingRuns(ctx)
		if err != nil {
			return "", err
		}
		if len(active)+len(waiting) == 0 {
			return "No agent runs are active.", nil
		}
		fmt.Fprintf(&b, "**Agent runs** (%d active", len(active))
		if s.cfg.Limits.MaxActive > 0 {
			fmt.Fprintf(&b, ", at most %d at once", s.cfg.Limits.MaxActive)
		}
		if len(waiting) > 0 {
			fmt.Fprintf(&b, ", %d waiting", len(waiting))
		}
		b.WriteString(")\n")
		for i, r := range append(active, waiting...) {
			line := fmt.Sprintf("%d. ", i+1)
			if job, err := s.st.JobByID(ctx, r.JobID); err == nil {
				n, what := job.Issue, "issue"
				if r.Mode != "implement" && job.PR != 0 {
					n, what = job.PR, "PR"
				}
				line += fmt.Sprintf("%s #%d %s", what, n, escape(job.Title))
				if job.ThreadID != "" {
					line += fmt.Sprintf(" (<#%s>)", job.ThreadID)
				}
			} else {
				line += "a new feature"
			}
			line += fmt.Sprintf(" · %s · %s", r.Mode, strings.ReplaceAll(r.Status, "_", " "))
			if r.UserID == autoUser {
				line += " · started by the merge queue"
			} else {
				line += fmt.Sprintf(" · by <@%s>", r.UserID)
			}
			line += fmt.Sprintf(" · <t:%d:R>", r.CreatedAt.Unix())
			if r.RunURL != "" {
				line += fmt.Sprintf(" · [run](<%s>)", r.RunURL)
			}
			b.WriteString(line + "\n")
		}
	case "merge":
		queue, err := s.st.MergeQueue(ctx)
		if err != nil {
			return "", err
		}
		if len(queue) == 0 {
			return "The merge queue is empty.", nil
		}
		b.WriteString("**Merge queue** (merged in this order, one at a time)\n")
		for i, m := range queue {
			line := fmt.Sprintf("%d. PR #%d", i+1, m.PR)
			if job, err := s.st.JobByID(ctx, m.JobID); err == nil {
				line += " " + escape(job.Title)
				if job.ThreadID != "" {
					line += fmt.Sprintf(" (<#%s>)", job.ThreadID)
				}
			}
			status := "waiting"
			switch {
			case m.Status == store.MergeUpdating:
				status = "updating with " + s.cfg.Ref
			case m.Status == store.MergeTesting:
				status = "waiting for CI"
			case i == 0:
				status = "merging"
			}
			line += fmt.Sprintf(" · %s · approved by <@%s> <t:%d:R>", status, m.ApproverID, m.CreatedAt.Unix())
			b.WriteString(line + "\n")
		}
	default:
		return "", fmt.Errorf("unknown queue %q", kind)
	}
	out := b.String()
	if r := []rune(out); len(r) > 1900 {
		out = string(r[:1900]) + "…"
	}
	return out, nil
}

func short(sha string) string {
	if len(sha) > 7 {
		return sha[:7]
	}
	return sha
}
