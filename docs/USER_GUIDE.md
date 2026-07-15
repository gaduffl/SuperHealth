# User guide

## First setup

1. On the primary phone, create the first profile. To merge old data cleanly, use the same display name as the corresponding profile in the former apps. Add a separate profile for each person.
2. Import the former apps’ JSON exports in Settings. Select all Biomarkers data files together, including `user_overrides.json`, and review the counts before confirming.
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

For Supplement Manager, select `supplement_sync.json`. For Biomarkers, select `profiles.json`, `biomarkers.json`, `ranges.json`, `biomarker_lists.json`, `biomarker_list_entries.json`, `user_overrides.json`, `documents.json`, and `measurements.json` together from `OneDrive/Apps/Biomarkers/data`. Do not select `manifest.json`. Approved former-profile overrides are imported as shared personal-target ranges.

After the JSON import, choose **Attach Biomarkers PDF files** and select all PDFs from `OneDrive/Apps/Biomarkers/documents`. SuperHealth matches each PDF to `documents.json` by its SHA-256 hash before copying it locally. **Sync now** then uploads the matched PDFs into the selected SuperHealth storage; another phone downloads them with its next sync.

## Adding another phone

On the welcome screen, choose **Restore from OneDrive** instead of creating a placeholder profile. Connect with that person’s Microsoft account, choose the same shared family folder, and tap **Sync now**. After the remote profiles appear, return to the main screen. This avoids duplicate profiles with different internal IDs.

## Daily use

- Add supplement products and schedules under Track. Tap a product to log an intake.
- Log scored symptoms and numeric or scored tags such as caffeine, exercise, or sleep.
- Store conditions, current medicines, goals, and family history. These materially improve advisor and lab-plan context.
- Run exploratory correlations after at least seven overlapping symptom days. Correlation is hypothesis-generating and does not establish causation.

## Biomarkers and PDFs

- Add biomarkers manually, including the price charged by the German lab, or import the existing Biomarkers catalog.
- Tap a biomarker for trends, change from the previous result, lab range status, and full history.
- Use the document-scanner button in Labs to select a PDF. Parsing does not save the PDF or measurements.
- Review the extracted date, every row, confidence, raw text, and biomarker mapping. Exclude bad rows or map unknown rows. “Save PDF + results” is the explicit persistence approval. Unmapped rows become clearly marked temporary biomarkers.

## Lab planning

1. Choose “Plan” in Labs and optionally add a target date, budget, or priority.
2. The complete active-profile history and full biomarker catalog are sent to the configured advisor model without silent truncation.
3. Review the unsaved Core, Advanced, and Comprehensive draft. Advanced includes Core; Comprehensive includes both earlier tiers.
4. Save the plan or export it to PDF, CSV, or JSON. Known totals use stored EUR prices and disclose missing prices.

## Advisor files

The advisor may read text files in its profile workspace and propose a create, replace, or delete. A proposal is inert until the app shows its exact operation, path, and complete content and you confirm it. Approved changes are also uploaded to OneDrive when connected. The workspace cannot modify the health database.

## Safety

SuperHealth is a personal research and planning tool. Do not use it to diagnose illness or to start, stop, or change prescription medication without a qualified clinician. Seek urgent medical care for red-flag or emergency symptoms.
