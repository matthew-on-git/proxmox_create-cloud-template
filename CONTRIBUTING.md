# Contributing

Thank you for your interest in contributing to this project!

## Development Setup

See the [README.md](README.md#for-developers) for setup instructions.

## Commit Message Format

This project uses [Conventional Commits](https://www.conventionalcommits.org/) for commit messages. This allows for automatic versioning and changelog generation.

### Format

```
<type>(<scope>): <description>

[optional body]

[optional footer]
```

### Types

- `feat`: A new feature (triggers minor version bump)
- `fix`: A bug fix (triggers patch version bump)
- `docs`: Documentation only changes
- `style`: Code style changes (formatting, missing semicolons, etc.)
- `refactor`: Code refactoring without changing functionality
- `perf`: Performance improvements
- `test`: Adding or updating tests
- `build`: Changes to build system or dependencies
- `ci`: Changes to CI configuration
- `chore`: Other changes that don't modify src or test files
- `revert`: Reverts a previous commit

### Examples

```bash
# Feature
git commit -m "feat: add support for Debian cloud images"

# Bug fix
git commit -m "fix: resolve VMID conflict detection issue"

# Documentation
git commit -m "docs: add troubleshooting section to README"

# With scope
git commit -m "feat(storage): add support for Ceph storage pools"

# Breaking change (use ! after type)
git commit -m "feat!: change default VMID from 9000 to 9010"
```

### Scope (Optional)

The scope should be the area of the codebase affected:
- `storage`: Storage-related changes
- `network`: Network configuration changes
- `cloud-init`: Cloud-init configuration changes
- `ui`: Interactive prompts and user interface
- `validation`: Input validation and error handling

## Pull Request Process

1. Fork the repository
2. Create a feature branch (`git checkout -b feat/amazing-feature`)
3. Make your changes
4. Ensure all pre-commit hooks pass
5. Commit your changes using conventional commit format
6. Push to your branch (`git push origin feat/amazing-feature`)
7. Open a Pull Request

## Code Style

- Follow shell script best practices
- Use `shellcheck` to check for issues
- Scripts should be formatted with `shfmt`
- Use 2-space indentation
- Prefer `bash` over `sh` for better compatibility

## Testing

Before submitting a PR, please:

**Using Makefile (Recommended):**

```bash
make check  # Runs all checks (lint, format-check, test)
```

**Or manually:**

1. Run linting: `shellcheck create-cloud-template.sh`
2. Check syntax: `bash -n create-cloud-template.sh`
3. Test the help output: `./create-cloud-template.sh --help`
4. If possible, test on a Proxmox host (or use a test environment)

See all available commands: `make help`

## Release Process

Releases are automatically created when code is merged to `main`:

- `feat:` commits → Minor version bump (0.1.0 → 0.2.0)
- `fix:` commits → Patch version bump (0.1.0 → 0.1.1)
- Other commits → Patch version bump

To skip a release, include `[skip release]` in your commit message.

## Questions?

Feel free to open an issue for questions or discussions!
