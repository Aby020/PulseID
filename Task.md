You are performing a Git-only release checkpoint for the PulseID project.

## Objective

Commit the completed **Task 2 — Foundation** work and push it to the newly created GitHub repository.

The Git commit MUST be authored by the human developer, **Abi Thomas**, NOT Claude, an AI agent, or any Claude-related identity.

## IMPORTANT

Do NOT modify application code.

Do NOT start Task 3.

Do NOT create Django, React, Expo, or backend implementation.

Only perform Git configuration, verification, commit, remote configuration, and push.

---

## 1. Verify repository

Confirm:

* Current directory is the PulseID repository.
* It is an independent Git repository.
* Current branch is `main`.
* There is no existing remote that should be preserved.
* Task 2 foundation files are present.

Run appropriate Git commands to verify this.

---

## 2. Configure human Git identity

Set the repository-local Git identity to:

Name:

`Abi Thomas`

Email:

`USE_THE_EMAIL_CONFIGURED_FOR_MY_GITHUB_ACCOUNT`

IMPORTANT:

* Do NOT use Claude's name.
* Do NOT use an AI-generated identity.
* Do NOT use `noreply@anthropic.com`.
* Do NOT use any Claude Code email.
* Do NOT change my global Git identity.
* Configure the identity only for this PulseID repository.

If the correct GitHub email cannot be determined safely from the local Git configuration or GitHub CLI authentication, STOP before committing and report that the email needs to be provided.

Verify with:

`git config --local user.name`

and

`git config --local user.email`

---

## 3. Inspect changes

Run:

`git status`

Then inspect the complete diff and staged/untracked files.

Make sure the commit contains only the intended Task 2 foundation:

* README.md
* .gitignore
* .env.example
* Makefile
* LICENSE placeholder
* docs/
* .github/workflows/
* required directory placeholders such as .gitkeep
* any other intentional Task 2 foundation files

Do NOT commit:

* `.env`
* secrets
* credentials
* API keys
* private keys
* `.claude/settings.local.json`
* temporary files
* generated artifacts
* unrelated files
* TrackWise files/code
* Task 3 implementation

If anything suspicious is found, STOP and report it instead of committing it.

---

## 4. Stage Task 2

Stage only the intended Task 2 files.

Then run:

`git status`

and verify the staged changes one final time.

---

## 5. Create the commit

Create exactly one commit with this message:

`chore: initialize PulseID foundation`

The commit author and committer must be:

`Abi Thomas`

Do NOT mention Claude Code, Anthropic, AI, or Claude in the commit author, committer, or commit message.

After committing, verify:

`git log -1 --format=fuller`

Confirm the author and committer are Abi Thomas.

---

## 6. Configure GitHub remote

The GitHub repository has already been created by the developer.

Determine the authenticated GitHub account/repository safely using available Git/GitHub CLI information.

The expected repository is:

`PulseID`

Do NOT invent a GitHub username or URL.

If the repository URL cannot be determined safely, STOP and report what information is missing.

Add the GitHub repository as:

`origin`

If an incorrect `origin` already exists, do not blindly overwrite it. Report it first.

---

## 7. Push main

Push the local `main` branch to GitHub:

`git push -u origin main`

Do not force push.

Do not use:

`git push --force`

Do not rewrite history.

---

## 8. Generate the next task

After the push succeeds, analyze the current PulseID project state and create or update `Next.md`.

Do NOT implement the next task.

`Next.md` must contain only a short, clear, ready-to-use prompt describing what Claude Code should do next.

Keep it concise and include:

* **Next Task**
* **Objective**
* **What to inspect**
* **Main requirements**
* **Acceptance criteria**

The next task must be based on the actual current state of PulseID after Task 2.

Do not invent unrelated features.

Do not start Task 3 during this checkpoint.

Example structure:

```md
# Next Task

## Objective

[Short description of the next development task.]

## Inspect First

- Analyze the current PulseID project structure.
- Review the existing foundation and documentation.
- Identify the files/components that need to be created or modified.

## Requirements

- [Requirement 1]
- [Requirement 2]
- [Requirement 3]

## Acceptance Criteria

- [ ] Requirement 1 completed
- [ ] Requirement 2 completed
- [ ] Tests/validation completed
- [ ] Existing functionality remains intact

Do not begin unrelated work.
After completing this task, analyze the project again and update `Next.md` with the following logical task.
```

The `Next.md` task must not contain implementation work from Task 3 that is actually performed during this checkpoint.

---

## 9. Final verification

After the push succeeds, verify:

* branch is `main`
* `origin` points to the intended PulseID GitHub repository
* local `main` tracks `origin/main`
* latest commit is `chore: initialize PulseID foundation`
* commit author is Abi Thomas
* commit committer is Abi Thomas
* working tree is clean

Run an appropriate final status/log check.

If `Next.md` is intentionally part of the repository workflow, ensure its status is handled consistently with the existing repository configuration so the final working tree remains clean.

---

## Final report

Return only a concise report containing:

1. Git identity used
2. Commit hash
3. Commit message
4. Remote repository
5. Push result
6. Final branch/status
7. Confirmation that Claude/Anthropic was NOT used as the commit author
8. Confirmation that `Next.md` was created/updated with the next task prompt

STOP after this Git checkpoint.
