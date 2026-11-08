# Changelog

## v1.4.1 — 2026-11-08
- Trash sync fixes: counter and trash view now update instantly after any delete, undo, due-deletion or restore; deleted-via-notification shots show up without a manual refresh
- App reconciles all data (gallery / trash / schedules / pins) every time it returns to the foreground, so native-side changes are never missed
- "Already in trash" state detected — delete actions on an already-trashed screenshot no longer claim success or offer a bogus Undo (the double-undo bug)
- Batch actions in gallery: Delete Now (with Undo), Unschedule (batch cancel of scheduled deletions), Pin now toggles to Unpin
- Batch actions in trash: long-press to select, then Restore or Delete Permanently for many items at once; select-all respects the active view
- Image options menu reordered: View → Share → Keep Forever → Schedule controls, divider, then Batch select and Delete Now (destructive actions last)

## v1.4.0 — 2026-11-08
- All-new fullscreen viewer: swipe between screenshots with PageView, pinch to zoom, page counter, fade/scale open transition with Hero animation from the gallery tile
- Share screenshots anywhere — native Share sheet from the viewer, the image options sheet and the trash sheet (FileProvider-based Android share intent)
- Viewer respects the active view (Gallery / Scheduled / Pinned) plus search and sort order

## v1.3.3 — 2026-11-08
- Info-rich gallery tiles: press-scale animation, relative date caption + filename footer, floating scheduled-countdown pill, trash pills with countdown progress ring, animated selection checkmark, image fade-in
- Loading skeleton grid while shots are scanned — no more "No screenshots yet" flash
- Batch mode: "All" (select-all) button, "Cancel selection" action, haptic feedback
- Haptics across toggles, deletions, pinning and scheduling
- Dark theme depth: unified elevated card surfaces and consistent corner radii via shared design tokens (cards / sheets / fields / tiles)

## v1.3.2 — 2026-11-08
- Stats strip is now strictly mutually exclusive — exactly one of Gallery / Scheduled / Pinned / Trash is active at a time (Gallery + Scheduled could previously both be lit)
- Pinned chip is now tappable and filters the gallery to pinned shots only
- Sort toggle in the gallery header: newest-first ↔ oldest-first
- Dedicated empty states for the Scheduled-filter ("No scheduled deletions") and Pinned-filter ("Nothing pinned yet") views

## v1.3.1 — 2026-11-08
- UI pass: branded app bar with gradient logo bubble and screen-matched background
- New tappable stats strip (Gallery / Scheduled / Pinned / Trash) — replaces the amber pill and trash icon-button; Scheduled chip toggles the filter, Trash chip opens the trash view, Gallery chip returns
- Redesigned status and Auto-pilot cards with leading icon bubbles and a glowing status dot
- Empty states for all three situations: no screenshots (with action hint), empty trash, and polished search no-results
- Schedule dialog quick presets: one-tap chips for 1h / 4h / 1d / 3d / 1w / 1mo
- Refresh button now also refreshes trash and pins
- Empty states made scroll-safe on small viewports

## v1.3.0 — 2026-11-07
- Trash with undo: every deletion (manual or scheduled) now moves screenshots to a private trash folder first; hard deletion happens after a 7-day grace period with self-cleaning alarms
- Trash view: dedicated gallery mode with restore, single permanent delete, and empty-trash and per-item countdowns; Undo snackbar right after every deletion
- Keep Forever pins: protect screenshots from deletion timers, batch operations and auto-pilot — teal pin badge on tiles, pin/unpin from bottom sheet or in bulk from the batch bar
- Auto-pilot: one rule ("Auto-delete every new screenshot after N") applied natively the instant a screenshot is detected — no manual scheduling needed; alert notifications reflect the auto-schedule
- Scheduled deletion alarm chain now covers both deletion timers and trash expiry dates
- Restored screenshots are marked as already-processed so the detector does not re-alert on them

## v1.2.4 — 2026-11-07
- Background reliability: screenshot detection now survives system kills, reboots and app updates without re-launching the app
  - Watchdog alarm revives the detector service every 15 min if it was killed
  - Detector restarts on boot (`BOOT_COMPLETED`), after app update, and after swipe-away
  - In-app battery-optimization banner prompts for "Unrestricted" battery usage
- Performance: countdown ticker now runs only while deletions are scheduled and rebuilds just the gallery; gallery renders downsampled thumbnails instead of full-resolution files
- Responsive gallery: column count scales with screen width (2–6 columns)
- Removed per-file disk I/O (sorting and existence checks bypassed via native ordering)
- Batch delete runs natively in a single call (`delete_batch`)
- Failed deletions are surfaced in-app and retried a minute later instead of disappearing silently
- Calendar-accurate month/year schedules (Jan 31 + 1 month = Feb 28, not Mar 3) for preview and actual target
- Fixed hidden bug: screenshot count was requested over a channel (`shotkeeper/count`) no native code listened to
- Modernized deprecated APIs (`WidgetStateProperty`, `DropdownButtonFormField.initialValue`, `Color.withValues`); Flutter analyze passes with zero issues
- Housekeeping: removed dead `com.example.shot_keeper` MainActivity stub and one-off fix scripts; pubspec version synced to 1.2.4+2007; replaced stale template test with a real smoke test

## v1.2.3 — 2026-10-03
- Scheduled pill (amber badge) with second-tap toggle filter and subtle interactive styling
- Batch delete confirmation removed; direct confirmation from popup
- Notification refresh: updates on cancel/delete; `DeletionAlarmReceiver` restarts service
- Search keyboard: `autofocus: false`
- Schedule: removed extra `ScheduleDetailsScreen`; popup confirms directly with preview

## v1.2.0 — 2026-10-03
- Added clear (cross) icon to search bar for one-tap search reset
- Search controller handles both visual text and query state cleanly
- Release APK rebuilt and pushed (48.3MB)
- Zero breaking changes

## v1.1.0 — 2026-10-02
- Added search functionality (filter screenshots by filename)
- Search bar above gallery grid
- Real-time filtering as you type
- "No results" empty state for searches
- Zero breaking changes to existing features

## v1.0.0 — 2026-10-02
- Initial release
- Screenshot capture and retention
- Permission handling for storage
- Modern Flutter Material UI
- MIT license added
- Documentation and build reports included
