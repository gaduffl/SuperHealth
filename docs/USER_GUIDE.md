# User guide

## First setup

1. Create the first profile. Add separate profiles for other people; only the active profile is shown, synced into requests, or exported.
2. In Settings, connect OneDrive if desired.
3. Import the existing apps using selected JSON files or “Import legacy files from OneDrive.” Review the counts and merge warnings before confirming.
4. Add an OpenAI, Anthropic, or Gemini key. Load the provider’s current models, then save separate Advisor and Lab document parser configurations.

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
