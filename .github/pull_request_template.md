# Pull Request

## Summary

<!-- Describe what this PR changes and why. Reference any related issue or TASK-XXX from docs/IMPLEMENTATION_PLAN.md. -->

## Type of Change

- [ ] `feat`: New feature
- [ ] `fix`: Bug fix
- [ ] `refactor`: Structural improvement without behavioral change
- [ ] `docs`: Documentation or ADR update
- [ ] `test`: Test additions or fixtures
- [ ] `chore`: CI, dependencies, or tooling

## 14-Pillar & Security Checklist

- [ ] **Architecture**: Strict dependency boundaries preserved (`Packages/` does not import `Features/`, Views do not call Citadel/libcurl/Keychain directly).
- [ ] **Concurrency**: Swift 6 strict concurrency clean; no unverified `@unchecked Sendable` or `Task.detached` retain cycles.
- [ ] **Security**: No credentials/keys logged (`OSLog` privacy labels applied); host key TOFU and TLS `SecTrust` validation remain enforced.
- [ ] **Path Safety**: Remote/local paths canonicalized and symlinks validated before file writes.
- [ ] **Verification**: Local linters (`markdownlint-cli2`, `yamllint`, `swiftlint`, `swiftformat`) and tests executed with fresh passing output.
