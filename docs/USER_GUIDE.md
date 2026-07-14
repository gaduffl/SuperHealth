# User guide

## First setup

1. Create the first profile. Add separate profiles for other people; only the active profile is shown, synced into requests, or exported.
2. Import the existing apps with exported JSON files selected through Android’s file picker. Review the counts and merge warnings before confirming.
3. In Settings, connect OneDrive. The Microsoft approval page must identify the app as **SuperHealth**.
4. Tap **Sync now** after the import to create the first clean SuperHealth snapshot.
5. Add an OpenAI, Anthropic, or Gemini key. Load the provider’s current models, then save separate Advisor and Lab document parser configurations.

## OneDrive storage

SQLite on the device is the working record. OneDrive stores `superhealth_snapshot.json` plus approved documents and advisor-workspace files under the dedicated `OneDrive/Apps/SuperHealth` AppFolder. API keys and OneDrive tokens are never included.

AppFolder permission deliberately prevents SuperHealth from reading the Biomarkers or Supplement Manager AppFolders. For the one-time migration, export or copy their JSON files and select them explicitly with Android’s file picker. After reviewing and committing the import, use **Sync now** to populate the new SuperHealth AppFolder.

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
