# Development Setup Guide

This guide will help you set up the development environment for this project.

## Quick Setup

**Option 1: Using Makefile (Recommended)**

```bash
# Install pre-commit first
pip install pre-commit

# Then run setup (installs hooks automatically)
make setup
```

**Option 2: Manual Setup**

1. **Install pre-commit**:
   ```bash
   pip install pre-commit
   # or
   pip3 install pre-commit
   ```

2. **Install pre-commit hooks**:
   ```bash
   pre-commit install
   pre-commit install --hook-type commit-msg
   ```

3. **Install ShellCheck** (optional but recommended):
   ```bash
   # macOS
   brew install shellcheck

   # Ubuntu/Debian
   sudo apt-get install shellcheck

   # Fedora
   sudo dnf install ShellCheck
   ```

4. **Install shfmt** (optional, for formatting):
   ```bash
   # macOS
   brew install shfmt

   # Or download from https://github.com/mvdan/sh/releases
   ```

5. **Update package.json** (if needed):
   Edit `package.json` and update the repository URL to match your GitHub repository.

## Verify Setup

Run the pre-commit hooks manually to verify everything works:

```bash
# Using Makefile
make pre-commit

# Or directly
pre-commit run --all-files
```

This will:
- Check commit message format (if you have a commit)
- Run ShellCheck on the script
- Format shell scripts
- Check for common issues

**Quick check with Makefile:**

```bash
make check  # Runs lint, format-check, and test
```

## First Commit

When making your first commit, use a conventional commit message:

```bash
git add .
git commit -m "chore: initial commit with CI/CD setup"
```

## Testing Locally

Before pushing, test your changes:

**Using Makefile (Recommended):**

```bash
make check      # Run all checks (lint, format-check, test)
make lint       # Just linting
make test       # Just tests
make format     # Format the code
```

**Or manually:**

```bash
# Lint check
shellcheck create-cloud-template.sh

# Syntax check
bash -n create-cloud-template.sh

# Test help output
./create-cloud-template.sh --help
```

See all available commands:
```bash
make help
```

## Troubleshooting

### Pre-commit hooks not running

If hooks aren't running automatically:
```bash
pre-commit install --install-hooks
```

### ShellCheck errors

Some ShellCheck warnings can be ignored. The configuration excludes:
- `SC1090`: Can't follow non-constant source
- `SC1091`: Not following source

If you need to ignore more, add them to `.pre-commit-config.yaml`.

### Commit message rejected

Make sure your commit message follows the conventional commit format:
```
<type>(<scope>): <description>
```

See [CONTRIBUTING.md](CONTRIBUTING.md) for details.
