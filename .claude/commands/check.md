Run the air_pointer quality gate. Always operate from the **package root** — run `cd /Users/zml-mac-ranveerg-01/flutterProject/air_pointer` before each step. Execute the three steps in order and stop on first failure.

**Step 1 — Static analysis**
```
cd /Users/zml-mac-ranveerg-01/flutterProject/air_pointer && flutter analyze --no-pub
```
Pass criterion: output ends with "No issues found!". If any issues are reported, list them and stop.

**Step 2 — Tests**
```
cd /Users/zml-mac-ranveerg-01/flutterProject/air_pointer && flutter test --no-pub
```
Pass criterion: all tests pass (exit 0). If any tests fail, show the failing test names and error output, then stop.

**Step 3 — Publish dry-run**
```
cd /Users/zml-mac-ranveerg-01/flutterProject/air_pointer && flutter pub publish --dry-run
```
Pass criterion: "Package has 0 warnings." Any warnings or errors must be listed and treated as a failure.

**Output format**
After all three pass, print a one-line summary:
```
✓ analyze  ✓ test (N tests)  ✓ publish dry-run
```
If a step fails, print which step failed and why. Do not continue to the next step after a failure.

Do not run `flutter build web` — that is covered by `/build-web`.
