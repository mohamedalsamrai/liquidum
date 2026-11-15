// Used by .github/workflows/no-response.yml.

const label = 'waiting for response';
const timeoutLabel = 'r: timeout';
const daysToWait = 21;

const issueComment = `Closing this since we haven't heard back in ${daysToWait} days, and without the details asked for above there isn't enough here to act on.

If you still run into it, please open a new issue with those details and a link to this one.`;

const pullRequestComment = `Closing this since it hasn't been updated in ${daysToWait} days after changes were asked for.

If you get back to it, reopen it or open a new pull request.`;

module.exports = async ({ github, context }) => {
  const { owner, repo } = context.repo;

  const removeLabel = async (issueNumber) => {
    try {
      await github.rest.issues.removeLabel({ owner, repo, issue_number: issueNumber, name: label });
    } catch (error) {
      // Someone already took it off.
      if (error.status !== 404) throw error;
    }
  };

  // A new comment: take the label off if the author is the one replying.
  if (context.eventName === 'issue_comment') {
    const { issue, comment } = context.payload;
    if (comment.user.id === issue.user.id) {
      console.log(`#${issue.number}: the author replied, removing "${label}".`);
      await removeLabel(issue.number);
    }
    return;
  }

  // Scheduled run: go through everything that still has the label.
  const cutoff = Date.now() - daysToWait * 24 * 60 * 60 * 1000;
  const waiting = await github.paginate(github.rest.issues.listForRepo, {
    owner,
    repo,
    state: 'open',
    labels: label,
    per_page: 100,
  });

  for (const item of waiting) {
    const isPullRequest = item.pull_request !== undefined;

    const events = await github.paginate(github.rest.issues.listEvents, {
      owner,
      repo,
      issue_number: item.number,
      per_page: 100,
    });
    const labeled = events.filter((e) => e.event === 'labeled' && e.label?.name === label).pop();
    if (!labeled) continue;
    const labeledAt = new Date(labeled.created_at);

    const comments = await github.paginate(github.rest.issues.listComments, {
      owner,
      repo,
      issue_number: item.number,
      since: labeledAt.toISOString(),
      per_page: 100,
    });
    let replied = comments.some(
      (c) => c.user.id === item.user.id && new Date(c.created_at) > labeledAt,
    );

    // On a pull request, a new commit counts as a reply.
    if (!replied && isPullRequest) {
      const commits = await github.paginate(github.rest.pulls.listCommits, {
        owner,
        repo,
        pull_number: item.number,
        per_page: 100,
      });
      replied = commits.some((c) => new Date(c.commit.committer.date) > labeledAt);
    }

    if (replied) {
      console.log(`#${item.number}: the author replied, removing "${label}".`);
      await removeLabel(item.number);
      continue;
    }

    if (labeledAt.getTime() > cutoff) continue;
    if (item.locked) {
      console.log(`#${item.number}: locked, skipping.`);
      continue;
    }

    console.log(`#${item.number}: no reply in ${daysToWait} days, closing.`);
    await github.rest.issues.createComment({
      owner,
      repo,
      issue_number: item.number,
      body: isPullRequest ? pullRequestComment : issueComment,
    });
    if (isPullRequest) {
      await github.rest.pulls.update({ owner, repo, pull_number: item.number, state: 'closed' });
    } else {
      await github.rest.issues.addLabels({ owner, repo, issue_number: item.number, labels: [timeoutLabel] });
      await github.rest.issues.update({
        owner,
        repo,
        issue_number: item.number,
        state: 'closed',
        state_reason: 'not_planned',
      });
    }
  }
};
