# Contributing to PawsOff

Thank you for your interest in contributing to PawsOff.

## Code Quality and Style Standards

To maintain high engineering standards, all contributions must adhere to the following principles:

1. **Zero Emoji Policy**: No emojis, pictographs, or decorative Unicode characters in code, comments, docstrings, terminal logs, or documentation.
2. **Platform Scope**: This application is strictly macOS-native (macOS 13.0+ AppKit, Carbon, and CoreGraphics).
3. **Fail-Open Invariant**: Event tapping must always preserve user recovery. Never remove or circumvent fail-open behavior on event tap invalidation or Secure Event Input activation.
4. **Zero Disruption Invariant**: The application must never trigger OS lock screens, sleep the machine, or throttle background processes.

## Development Workflow

1. Fork the repository and create a feature branch.
2. Build the project locally:
   ```bash
   make build
   ```
3. Run the test suite:
   ```bash
   make test
   ```
4. Run the source audit:
   ```bash
   python3 Scripts/audit_source.py
   ```
5. Ensure all checks pass before submitting a pull request.

## License

By contributing to PawsOff, you agree that your contributions will be licensed under the project's [MIT License](LICENSE).
