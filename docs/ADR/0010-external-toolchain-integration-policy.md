# ADR-0010: External Toolchain Integration & Security Boundary Policy

## Status

Accepted

## Date

2026-11-14

## Context

SparkleSFTP v0.6.0 introduces productivity integrations with external binaries, system toolchains, and operating system services:
1. **Archive Toolkit**: System `tar`, `gzip`, and optional `7zz`/`7z` for multi-format archive compression and extraction.
2. **Synchronization & Transfer Acceleration**: System `rsync` for delta-sync operations.
3. **Authentication**: OpenSSH Authentication Agent via `SSH_AUTH_SOCK` Unix domain socket.
4. **External Text Editors**: Launching user-configured GUI/CLI editors (VS Code, Sublime Text, BBEdit, TextMate) to modify remote files with automatic sync-back.

Without strict defensive controls, integrating external binaries introduces significant vulnerabilities: shell argument injection (CWE-78, CWE-88), path traversal / Zip-Slip (CWE-22), symlink races, and credential leakage.

## Decision

1. **Deterministic Binary Resolution & No Shell Spawning**:
   - External tools are located using explicit absolute path probes (`/usr/bin`, `/usr/local/bin`, `/opt/homebrew/bin`).
   - Execution is performed strictly via Foundation `Process` with an array of arguments (`[String]`). Spawning via `/bin/sh -c`, `system()`, or shell interpolations is strictly forbidden.

2. **Zip-Slip & Path Traversal Immunity (`ArchiveService`)**:
   - All archive listings and extraction destinations enforce strict boundary validation.
   - Any member path containing `..`, leading slashes, NUL bytes, or resolving outside the target staging directory is immediately rejected before extraction.
   - Total extraction entry limits (`maxAllowedEntries = 50,000`) prevent decompression bombs.

3. **Argument Injection Defense (`RsyncIntegrationService`)**:
   - All source and destination paths passed to `rsync` are sanitized and positioned following the explicit argument delimiter `--`.
   - Flavor and capability probing detects whether GNU rsync (>= 3.x) or Apple OpenRsync is active, adjusting flags accordingly (`-avzP` vs basic sync flags).

4. **SSH Agent Socket Validation (`SSHAgentAuthHelper`)**:
   - `SSH_AUTH_SOCK` environment variables are verified to exist and confirm they point to a valid, accessible Unix domain socket owned by the current user.
   - Unsafe or non-socket paths are rejected with clear diagnostics.

5. **External Editor Staging & Symlink Traversal Defense (`ExternalEditWatcher`)**:
   - Temporary file caches are created inside `~/Library/Caches/SparkleSFTP/remote-edit/<session-id>/` with POSIX permissions `0700`.
   - The file watcher utilizes `DispatchSourceFileSystemObject` with `O_NOFOLLOW` open flags to prevent symlink redirect attacks.
   - A 500ms debounce window prevents partial writes or transient editor locks from triggering corrupt remote uploads.

## Consequences

- Prevents arbitrary command injection, file overwrite attacks, and privilege escalation vulnerabilities.
- Maintains full compatibility across macOS 13, 14, and 15 on both Intel (x86_64) and Apple Silicon (arm64).
- Extensibility: Future tools (such as git-based sync or rclone) can be integrated following the same `ExternalToolchainPolicy` abstraction.
