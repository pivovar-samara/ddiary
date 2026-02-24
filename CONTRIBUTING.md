# Contributing to DIA-ry

Thanks for contributing.

## Ground rules

- Be respectful and follow [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md).
- Keep pull requests focused and small where possible.
- Do not commit secrets, API keys, or personal data.

## Development setup

1. Copy secrets template:
   - `cp Configs/Secrets.xcconfig.example Configs/Secrets.xcconfig`
2. Fill local values in `Configs/Secrets.xcconfig`.
3. Open `DDiary.xcodeproj` in Xcode and run tests before creating a PR.

## Pull request checklist

- Build succeeds locally.
- Relevant tests are added/updated and passing.
- Documentation is updated when behavior/configuration changes.
- No generated artifacts or local config files are included.
