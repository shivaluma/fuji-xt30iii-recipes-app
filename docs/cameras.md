# Cameras & X‑Trans generations

FilmLab works with Fujifilm **X‑Trans IV and X‑Trans V** cameras. The X‑T30 III is still the
**reference body**: it is the only camera whose ranges were checked against its owner's manual,
and the only one where FilmLab offers (experimental) USB slot access.

## One catalog, two platforms

`shared/camera-catalog.json` is the single source of truth. Both platforms read it:

- **Web:** `web/src/lib/recipe/cameras.ts`.
- **iOS:** `FilmLab/Domain/Camera/CameraCatalog.swift` mirrors it in code.
  - `CameraCatalogParityTests` decodes the JSON and checks every field matches.
  - Change the JSON first, then the Swift mirror. The test fails until both agree.

Each body records:
- its name and aliases;
- sensor and processor;
- recipe family (`xTransGeneration`);
- the film simulations it has;
- recipe properties it lacks;
- range overrides on top of `baseRanges`;
- whether it has a film simulation dial;
- two verification statuses: one for the feature data, one for PTP.

## What "X‑Trans IV / V" means here

The community labels recipes **X‑Trans IV** or **X‑Trans V**. In practice the label follows the
**processor's feature set**, not the sensor:

| Recipe family | Processor | Bodies (catalog) |
|---|---|---|
| X‑Trans V | X‑Processor 5 | X‑T30 III, X‑M5, X‑S20 (X‑Trans CMOS 4 sensors); X‑T50, X‑E5, X100VI, X‑T5, X‑H2 (5 HR); X‑H2S (5 HS) |
| X‑Trans IV | X‑Processor 4 | X‑T30 II, X‑T4, X‑S10, X‑E4, X100V, X‑Pro3, X‑T3, X‑T30 |

- An **X‑Trans IV recipe runs on X‑Trans V bodies**.
- An X‑Trans V recipe runs on X‑Trans IV bodies only if it avoids REALA ACE and NOSTALGIC Neg.
- Per-body gaps also apply:
  - X100V and X‑Pro3 have no ETERNA BLEACH BYPASS.
  - X‑T3 and X‑T30 lack:
    - CLASSIC Neg.;
    - Color Chrome FX Blue;
    - Clarity;
    - grain size;
    - monochromatic magenta–green;
    - half-step Highlight/Shadow.

Feature support is still modelled **per property** (`CameraProfile`). The generation is only a
label for browsing and tagging.

## Recipe tag

- **Format:** `FilmRecipe.xTransGeneration` is an optional `"IV"` / `"V"` field in FilmLab JSON.
  - The transfer document stays at schema version 1.
  - Files without the field still decode.
- **Inference** (`inferredGeneration`, the same rule as the web), in order:
  1. the explicit tag;
  2. REALA ACE / NOSTALGIC Neg. ⇒ V;
  3. otherwise the generation of the first recognised camera in `compatibleCameras`. "X‑T30 III" counts only when it is the sole entry, because older recipes always had it added by default. So `["X-T30 III", "X100V"]` → IV;
  4. otherwise unknown.
- **Website recipes** carry the tag the website publishes (`xTransGeneration`); without one, the inference above applies.
- **Imports** record the camera the source names, and any "X‑Trans IV/V" text it contains.

## Model recognition

`CameraCatalog.recognize(_:)` handles PTP model strings, recipe cards and free text:

1. Remove "FUJIFILM" and "MARK", collapse whitespace, and uppercase.
2. Try catalog keys (name + aliases, alphanumerics only), **longest first**.
3. A key's characters may be separated by one space or hyphen.
4. The match must not touch another letter or digit.

So "X‑T30 Mark II" → X‑T30 II, "X‑T50" is never X‑T5, and "X100VI" is never X100V.

## Compatibility

`RecipeCompatibility.evaluate(settings, on: profile)` returns one of:

- **Works**
- **Works with changes**: a setting is missing, or a value is out of range or off-step.
- **Not available**: the body lacks the film simulation.

Dependency hints, such as COLOR on monochrome, apply to every body and are ignored here.

If a body lacks a setting but the recipe uses its neutral value (0, OFF, Small), the result is
only an info note. Nothing is lost.

## In the app

- **Settings › Camera › My camera:** grouped picker, default X‑T30 III. It drives:
  - the Studio film simulation strip: simulations the body lacks are disabled and explained;
  - the Tune panel:
    - the body's own ranges;
    - settings the body lacks are hidden;
    - if the recipe sets one, it is shown disabled with a Clear button;
  - Save checks, Explore/Library compatibility and the import review.
- **Explore / Library:**
  - a generation badge on cards;
  - filters: All / X‑Trans V / X‑Trans IV / Works on my camera;
  - recipe detail shows "Written for …", lets you edit the tag on your own recipes, and has a
    *Check every camera* list.
- **Camera tab:** a connected camera is identified through the catalog.
  - **X‑T30 III:** read/backup, plus experimental writes behind the existing gates.
  - **Other recognised bodies:** *Recognised · Profile only*.
    - Even reading a slot selects it over PTP (a property write), and nobody has reported the
      property map on those bodies.
    - So FilmLab shows their profile and releases the camera without reading or writing slots.
  - **Unknown models:** unsupported.
  - *Supported cameras* lists every profile.

## Verification status (honesty)

| Data | Status |
|---|---|
| X‑T30 III ranges and simulations | DOC (owner's manual), with 3P notes where marked |
| Other bodies' simulations, missing features and ranges | **3P: community-reported, not checked by FilmLab against each manual** |
| REALA ACE on X‑T5 / X‑H2 / X‑H2S / X‑S20 | 3P: added by firmware updates; older firmware lacks it |
| Film simulation dial on X‑M5 / X‑T50 / X‑E5 | 3P |
| PTP slot access on bodies other than the X‑T30 III | NV, so FilmLab doesn't attempt it |

The validator gives each non-reference body one summary note saying its data is
community-reported, rather than one note per field.
