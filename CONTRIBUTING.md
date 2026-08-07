# Contributing to Notepad for macOS

Thanks for taking the time to contribute! This project is a 1:1 replica of Windows 11 Notepad for macOS — native AppKit, no Electron.

## Getting Started

1. Fork the repository and clone it locally.
2. Install prerequisites: **Xcode 15+** and **XcodeGen** (`brew install xcodegen`).
3. Generate the Xcode project and build:

   ```bash
   ./Scripts/setup.sh     # checks deps, generates Notepad.xcodeproj
   make build             # Debug build (Universal Binary)
   ```

   No Xcode available? `./Scripts/dev-build.sh` compiles directly with `swiftc`.

## Development Loop

```bash
make test      # unit + UI tests (xcodebuild test)
make lint      # SwiftLint --strict
make format    # SwiftFormat (config in .swiftformat)
```

Please run lint and the test suite before opening a PR.

## Coding Conventions

The repository is governed by two documents at the repo root (in Chinese):

- **`Docs/Specs/03_DEV_GUIDE.md`** — code generation standards: `NP` prefix for classes, 4-space indent, ≤120 char lines, K&R braces, `weak` delegates, explicit `[weak self]`, `throws`/`Result` over force-unwraps, `// MARK: -` sections, `///` doc comments on all internal/public methods.
- **`Docs/Specs/08_KIMI_INSTRUCTION.md`** — module layering (App → Editor/UI → Preferences/Services → Document → Utilities), the ban on reverse dependencies, and the quality checklist.

A few hard rules from those documents:

- **Never** force-unwrap (`!`) or use implicitly-unwrapped optionals in app code (tests may, see the test-plan exemption).
- All user-visible strings must go through `NSLocalizedString` (en / zh-Hans / zh-Hant).
- UI work stays on the main thread (`@MainActor`).
- No magic numbers; constants live in `Utilities/Constants/NPConstants.swift`.

## Project Layout

```
Notepad/
├── App/            # lifecycle, menu, document controller
├── Document/       # NSDocument, encoding & line-ending managers
├── Editor/         # text view, find & replace, go-to-line
├── UI/             # tab bar, status bar, find bar, theme
├── Preferences/    # persisted preferences
├── Services/       # print, backup, shortcuts, updates, crash reporting
├── Utilities/      # constants, helpers, extensions
└── Resources/      # localizations, app icon
```

Each module's public contract is defined in `Docs/Specs/04_MODULE_API.md`; keep it in sync when you change an interface.

## Reporting Issues

- **Bugs**: use the [bug report template](.github/ISSUE_TEMPLATE/bug_report.md) — include the macOS version, reproduction steps and expected vs. actual behavior.
- **Feature requests**: use the [feature request template](.github/ISSUE_TEMPLATE/feature_request.md).
- **Security issues**: see [SECURITY.md](SECURITY.md) — do **not** open a public issue for vulnerabilities.

## Pull Request Checklist

- [ ] `make lint` passes
- [ ] `make test` passes
- [ ] New logic has unit tests (`NotepadTests/`, IDs follow `Docs/Specs/05_TEST_PLAN.md`)
- [ ] `CHANGELOG.md` updated under `[Unreleased]`
- [ ] `Docs/Specs/04_MODULE_API.md` updated if the interface changed
- [ ] Localization keys added in all three `Localizable.strings`

## License

By contributing you agree that your contributions are licensed under the [MIT License](LICENSE).
