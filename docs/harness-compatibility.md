# Harness compatibility

The portable unit is the controller protocol, not a dot-directory. Issue contracts, lifecycle labels, leases, digests, worktrees, policy, verification, delivery, and evidence are provider-neutral. Instruction discovery, sandbox flags, structured output, authentication, and hosted invocation are adapter responsibilities.

## Support levels

| Capability | Claude Code | Codex CLI | OpenCode | Copilot CLI | Copilot cloud / IDE |
|---|---|---|---|---|---|
| Repository instructions | `CLAUDE.md` | `AGENTS.md` | installed `AGENTS.md` | installed `AGENTS.md` | surface-dependent |
| Shared Agent Skills | installed | installed | installed | supported CLI surfaces | surface-dependent |
| Interactive spec/TDD/review | native slash/skill | skill | skill | skill where supported | varies |
| Controller adapter | implemented | implemented | absent | absent | absent |
| Structured bounded result | JSON schema | JSONL + schema | untested | untested | not one API |
| Model GitHub credential | removed | removed | n/a | n/a | n/a |
| Controller-owned delivery | implemented | implemented | unsupported | unsupported | unsupported |
| Hosted controller | Claude workflow | unsupported | unsupported | unsupported | unsupported |

Implemented means code and local conformance tests exist. It does not mean a live issue-to-PR smoke or an actual-credential Gate 2 bypass test has passed in your repository. Those are separate release gates.

## Adapter contract

An autonomous adapter must:

1. probe its binary, version, authentication, instruction files, skills, and capability mode;
2. accept one bounded `WorkOrder` through data, never shell interpolation;
3. run in the controller-created worktree with timeout and private artifacts;
4. receive no `GH_TOKEN`, `GITHUB_TOKEN`, SSH agent, or Git delivery capability;
5. emit exactly one strict, versioned `AgentResult`;
6. treat missing usage as unknown and provider text as advisory;
7. preserve the controller-owned branch and HEAD.

The controller independently validates every claimed changed path and verification result. A model-authored `OPENED_PR=42` string has no authority.

## Claude profile

The Claude adapter uses project settings and structured JSON output. Its available tools are Read, Edit, Write, Glob, and Grep; Bash is not exposed. Permission mode is non-interactive and unmatched requests are denied. Session persistence is disabled and the configured dollar budget is passed to the provider.

Claude project hooks and specialist agents remain optional acceleration surfaces. Correctness does not depend on their execution.

## Codex profile

The Codex adapter uses `codex exec` in `workspace-write`, disables web search and sandbox network access, ignores user configuration, requests schema output, and removes delivery credentials. Codex is expected to edit working files but not Git metadata; the controller owns commit and transport.

The adapter never falls back to `danger-full-access`, `--yolo`, or an approval bypass. If the installed CLI cannot preserve the boundary, probe must fail.

## OpenCode and Copilot

These harnesses receive `AGENTS.md` and byte-equivalent Agent Skills, so a human can use the repository workflows where the surface supports them. They do not receive an autonomous adapter, native permission policy, output normalizer, or hosted runner in this release.

“GitHub Copilot” is not one execution target: CLI, cloud coding agent, GitHub.com, code review, and IDE agent modes have different instruction, skill, hook, and prompt support. Any future adapter must name and test one surface explicitly.

## Conformance before promotion

A new adapter moves from **Context** to **Interactive** only after discovery and invocation smoke tests. It moves to **Autonomous local** only after fake-provider, real-Git, timeout, malformed-output, credential-stripping, protected-path, verification, pause, lease, and recovery tests. It moves to **Hosted** only after a real issue-to-PR run and live proof that its automation identity cannot bypass Gate 2.

Useful upstream references:

- [Claude Code skills](https://code.claude.com/docs/en/skills)
- [Claude Code headless mode](https://code.claude.com/docs/en/headless)
- [Codex non-interactive mode](https://learn.chatgpt.com/docs/non-interactive-mode)
- [Codex approvals and security](https://learn.chatgpt.com/docs/agent-approvals-security)
- [OpenCode skills](https://opencode.ai/docs/skills)
- [Copilot customization support](https://docs.github.com/en/copilot/reference/customization-cheat-sheet)
