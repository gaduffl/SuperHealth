# User guide

## First setup

1. On the primary phone, choose **Start fresh** and create the first profile. To merge old data cleanly, use the same display name as the corresponding profile in the former apps. Add a separate profile for each person.
2. Follow the setup checklist in Settings. Import the former apps’ JSON exports together, including `user_overrides.json`, and review the counts before confirming.
3. Choose **Attach Biomarkers PDF files**, select all old report PDFs, review the SHA-256 matches, and confirm.
4. Connect OneDrive. The Microsoft approval page must identify the app as **SuperHealth**.
5. Choose **Shared family folder** for separate Microsoft accounts, or **Private AppFolder** when every device will connect to the same Microsoft account.
6. Tap **Sync now**. This uploads the clean SuperHealth snapshot and matched PDFs.
7. Add an OpenAI, Anthropic, or Gemini key. Load the provider’s current models, then save separate Advisor and Lab document parser configurations.

## OneDrive storage

SQLite on each device is the working record. API keys and OneDrive tokens are never included in snapshots.

**Private AppFolder** requests `Files.ReadWrite.AppFolder` and stores data in `OneDrive/Apps/SuperHealth`. This is the least-privilege option, but every device must connect to the same Microsoft account to share data.

**Shared family folder** requests delegated `Files.ReadWrite`. Create a OneDrive folder, share it with edit permission, and select that same folder on both phones. SuperHealth creates a `SuperHealth` subfolder and constrains its file operations to that location. The Microsoft token is technically broader than the AppFolder token, which is why this mode is always an explicit choice.

AppFolder isolation prevents silent reads from the former apps’ private folders. Migration therefore uses Android’s file picker and leaves every original file untouched.

For Supplement Manager, select `supplement_sync.json`. For Biomarkers, select `profiles.json`, `biomarkers.json`, `ranges.json`, `biomarker_lists.json`, `biomarker_list_entries.json`, `user_overrides.json`, `documents.json`, and `measurements.json` together from `OneDrive/Apps/Biomarkers/data`. Do not select `manifest.json`. Approved former-profile overrides are imported as profile-specific personal targets.

After the JSON import, choose **Attach Biomarkers PDF files** and select all PDFs from `OneDrive/Apps/Biomarkers/documents`. SuperHealth matches each PDF to `documents.json` by its SHA-256 hash before copying it locally. **Sync now** then uploads the matched PDFs into the selected SuperHealth storage; another phone downloads them with its next sync.

## Adding another phone

On the welcome screen, choose **Restore or transfer existing data** instead of creating a placeholder profile. Connect with that person’s Microsoft account, choose the same shared family folder, and tap **Sync now**. After the remote profiles appear, return to the main screen. This avoids duplicate profiles with different internal IDs.

Restoring a portable backup pauses ordinary OneDrive sync. Choose **Resume and merge** to reconcile it with the shared cloud data, or use the deliberately destructive **Publish restored data** action only when the restored backup must become the authoritative family copy.

## Daily use

Today opens with the overview tiles. Each one is a shortcut: tapping it opens the screen that owns its number, already filtered — low stock opens the stock list limited to what is running out, biomarkers due opens the catalog limited to overdue markers.

Below the tiles, the day strip selects which day you are working on; the bar under each number shows how much of that day is recorded. The day's doses are grouped into morning, midday, evening, and bedtime:

- Swipe a dose right to record it, or left to skip it. Both actions can be undone from the snack bar.
- **Quick actions** records everything still open in one part of the day at once.
- **Log extra** records an unplanned dose for the selected day. It stays visible in the block it belongs to, marked as unplanned.
- **Check in** scores every tracked symptom for the day in one dialog, and takes a free-text note. New symptoms can be added from inside the dialog. Clearing a score removes that entry rather than storing a zero.
- **Analyze** hands the day's products and their components to the advisor as a question about interactions, duplicated actives, and upper limits.

The Supplements screen has four tabs:

- **Catalog** — products, their ingredients, and their schedules. Ingredients are edited as rows with separate name, amount, and unit fields; the amount is per one stock unit. **Paste label** opens a panel where you paste the ingredient table from the packaging together with the serving size it applies to — for example 4 capsules. The configured lab document parser model reads it into the rows, dividing the stated amounts down to one unit. The rows stay editable, so nothing is stored until you save the product. If the model reads a different serving size on the label than you entered, it says so instead of quietly storing a dose several times too high. No health record is sent with the request; only the pasted packaging text.
- **Plan** — the weekly pillbox: dose per weekday and part of the day. Tap a filled cell to edit the schedule behind it. Below the grid, the components the active plan is designed to deliver each week, independent of adherence.
- **Stock** — days of cover per product, the shopping list for a 1, 3, 6, or 12 month horizon rounded up to whole packages, and the planned monthly cost per product.
- **History** — weekly adherence, product intake, and component exposure charts, the known intake cost trend, and CSV export. Pin a product or component to choose which lines the charts draw; with nothing pinned they show the six largest.

The stock button in the app bar opens a drawer with days of cover for every product, from any screen.

Elsewhere:

- Log scored symptoms and numeric or scored tags such as caffeine, exercise, or sleep. Under Health, the tune button next to the quick check-ins renames, archives, or switches a symptom to a tag and back. Tags are intake proxies used only as predictors in correlations; symptoms are the outcomes. Renaming carries through the recorded history so the journal does not show the same thing under two names, and archiving hides a symptom from future check-ins without removing what was already recorded.
- Store conditions, current medicines, goals, and family history. These materially improve advisor and lab-plan context.
- Run exploratory correlations after at least seven overlapping symptom days. Correlation is hypothesis-generating and does not establish causation.

## Biomarkers and PDFs

- Add biomarkers manually, including the price charged by the German lab, or import the existing Biomarkers catalog.
- Tap a biomarker for trends, change from the previous result, lab range status, and full history.
- Use the document-scanner button in Labs to select a PDF. Parsing does not save the PDF or measurements.
- Review the extracted date, every row, confidence, raw text, and biomarker mapping. Use the edit action to correct the reported name, value, unit, reference limits, PDF page, or notes. Exclude bad rows or map unknown rows. “Save PDF + results” is the explicit persistence approval. Unmapped rows become clearly marked temporary biomarkers.

## Lab planning

1. Choose “Plan” in Labs and optionally add a target date, budget, or priority.
2. The complete active-profile history and full biomarker catalog are sent to the configured advisor model without silent truncation.
3. A fresh second call to the same configured model independently verifies the parsed plan against the same complete context. Rejected or malformed reviews fail closed and cannot be saved or exported.
4. Review the unsaved Core, Advanced, and Comprehensive draft. Advanced includes Core; Comprehensive includes both earlier tiers.
5. Save the plan or export it to PDF, CSV, or JSON. Known totals use stored EUR prices and disclose missing prices; the verifier summary, warnings, sources, and verification time remain attached to the saved plan and exports.

## Advisor files

The advisor may read text files in its profile workspace and propose a create, replace, or delete. A proposal is inert until the app shows its exact operation, path, and complete content and you confirm it. Approved changes are also uploaded to OneDrive when connected. The workspace cannot modify the health database.

## Safety

SuperHealth is a personal research and planning tool. Do not use it to diagnose illness or to start, stop, or change prescription medication without a qualified clinician. Seek urgent medical care for red-flag or emergency symptoms.
