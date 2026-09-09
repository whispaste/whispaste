# Contributing to WhisPaste

Thanks for considering a contribution — bug reports, feature ideas, and pull
requests are all welcome.

## Reporting bugs / requesting features

Use [GitHub Issues](../../issues/new/choose) — pick the bug report or feature
request template. Please include your OS/version, WhisPaste version, and
reproduction steps for bugs.

For open-ended questions or discussion, use [GitHub
Discussions](../../discussions) instead of opening an issue.

## Where to look before proposing something big

The [Roadmap / Vote on Ideas board](https://app.votepit.com/silvio-und-maik/whispaste)
shows the current rough direction and what other people have already proposed —
check there first so your idea doesn't overlap with something already planned or
in progress. It reflects direction, not a binding schedule.

## Contributing code

1. Fork the repo and create a branch off `main`.
2. Make your change. Keep it focused — one logical change per PR.
3. Run the gate commands below for the parts of the repo you touched and make
   sure they pass.
4. Open a pull request against `main` describing what changed and why.

### Gate commands

Desktop app (Dart/Flutter, repo root):

```bash
dart format --output=none --set-exit-if-changed lib test
flutter analyze --fatal-infos --fatal-warnings
flutter test test/<path>   # the tests relevant to your change
```

Website (`cd website`):

```bash
npx tsc --noEmit
npx eslint .
npx vitest run <path>
npx playwright test <path>
```

### Prerequisites

[Flutter](https://flutter.dev/docs/get-started/install) 3.x, and Windows 10
(64-bit), macOS 11 Big Sur or newer (Apple Silicon), or a recent Linux distro
to build/run the desktop app. See the [README](README.md#development) for the
quickstart.

## Design changes

WhisPaste favors existing `Wp*` widgets and the theme tokens in
`lib/core/theme/`. If your change touches UI, try to reuse what's already
there rather than introducing a new pattern.

## License

By contributing, you agree that your contributions will be licensed under the
project's [MIT License](LICENSE).
