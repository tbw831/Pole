# AGENTS.md

## Project Structure
- `Pole/`: main iOS app target.
- `Pole/Domain/`: shared domain models and cross-series abstractions.
- `Pole/Sports/`: data clients, caching, AI, weather, news, intents.
- `Pole/Features/`: SwiftUI screens and view models by feature/series.
- `Pole/Theme/`: design tokens, brand colors, reusable UI styling.
- `PoleTests/`: unit tests with Swift Testing.
- `PoleUITests/`: UI tests with XCTest.
- `PoleWidgets/`: widget and Live Activity code.
- `docs/`: setup and deployment notes.

## Development Commands
- List schemes/targets:
  - `xcodebuild -list -project Pole.xcodeproj`
- Build on a Mac with Xcode installed:
  - `xcodebuild -project Pole.xcodeproj -scheme Pole -destination 'platform=iOS Simulator,name=iPhone 14 Pro' build`
- Run tests:
  - `xcodebuild -project Pole.xcodeproj -scheme Pole -destination 'platform=iOS Simulator,name=iPhone 14 Pro' test`
- Run a single test:
  - `xcodebuild test -project Pole.xcodeproj -scheme Pole -destination 'platform=iOS Simulator,name=iPhone 14 Pro' -only-testing:PoleTests/PoleTests/example`

## Coding Conventions
- Follow the existing four-layer architecture: `Domain -> Sports -> Features -> Theme`.
- Keep transport/DTO types inside `Sports`; do not leak API formats into `Domain` or `Features`.
- Use SwiftUI + `@Observable` view models, typically `@MainActor final class`.
- Prefer design tokens from `Pole/Theme/DesignSystem.swift`; avoid magic numbers and ad-hoc colors.
- Route user-visible strings through the localization helpers already used in the app.
- Reuse existing series/theme patterns before introducing new abstractions.

## Testing Expectations
- Add or update tests for behavior changes when practical.
- Prefer unit coverage in `PoleTests/`; keep UI flows in `PoleUITests/`.
- Run the lightest relevant `xcodebuild ... test` command before opening a PR when possible.

## Commit and Pull Request Guidelines
- Keep commits focused and descriptive; this repo currently uses short imperative messages.
- In PRs, include: purpose, main files changed, test evidence, and screenshots for UI work.
- Call out config or secret setup explicitly; never commit API keys or user-specific scheme data.
