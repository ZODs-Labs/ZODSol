#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SCHEME_NAME="ZODSol Signed App"
SCHEME_DIR="$ROOT/.swiftpm/xcode/xcshareddata/xcschemes"
SCHEME_FILE="$SCHEME_DIR/${SCHEME_NAME}.xcscheme"
APP_PATH="$ROOT/ZODSol.app"
PREACTION_SCRIPT="$ROOT/Scripts/xcode_package_preaction.sh"

mkdir -p "$SCHEME_DIR"

# Absolute paths are baked in here because Xcode's $(SRCROOT) macro is only
# reliably resolved for SwiftPM schemes that own a BuildableProductRunnable -
# our launch target is a hand-built .app bundle, not a SwiftPM product, so the
# safest path is "regenerate per machine and per repo location".
TMP=$(mktemp)
cat > "$TMP" <<XML
<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "1640"
   version = "1.7">
   <BuildAction
      parallelizeBuildables = "YES"
      buildImplicitDependencies = "YES">
   </BuildAction>
   <TestAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      shouldUseLaunchSchemeArgsEnv = "YES">
   </TestAction>
   <LaunchAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      launchStyle = "0"
      useCustomWorkingDirectory = "YES"
      customWorkingDirectory = "$ROOT"
      ignoresPersistentStateOnLaunch = "NO"
      debugDocumentVersioning = "YES"
      debugServiceExtension = "internal"
      allowLocationSimulation = "YES">
      <PreActions>
         <ExecutionAction
            ActionType = "Xcode.IDEStandardExecutionActionsCore.ExecutionActionType.ShellScriptAction">
            <ActionContent
               title = "Package signed ZODSol.app"
               scriptText = "&quot;$PREACTION_SCRIPT&quot;">
            </ActionContent>
         </ExecutionAction>
      </PreActions>
      <PathRunnable
         runnableDebuggingMode = "0"
         FilePath = "$APP_PATH">
      </PathRunnable>
   </LaunchAction>
   <ProfileAction
      buildConfiguration = "Release"
      shouldUseLaunchSchemeArgsEnv = "YES"
      savedToolIdentifier = ""
      useCustomWorkingDirectory = "NO"
      debugDocumentVersioning = "YES">
      <PathRunnable
         runnableDebuggingMode = "0"
         FilePath = "$APP_PATH">
      </PathRunnable>
   </ProfileAction>
   <AnalyzeAction
      buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction
      buildConfiguration = "Release"
      revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
XML

if [[ -f "$SCHEME_FILE" ]] && cmp -s "$TMP" "$SCHEME_FILE"; then
    rm "$TMP"
    printf 'Xcode scheme up to date: %s\n' "$SCHEME_FILE"
else
    mv "$TMP" "$SCHEME_FILE"
    printf 'Wrote Xcode scheme: %s\n' "$SCHEME_FILE"
fi

chmod +x "$PREACTION_SCRIPT"
./Scripts/setup_local_signing.sh

printf 'Ready. Open Package.swift in Xcode, select "%s", then press Run.\n' "$SCHEME_NAME"
