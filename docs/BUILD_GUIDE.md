# Build Guide — step by step

Total time: roughly **2–3 weekends**. Most of the waiting is Data Cloud jobs
(data streams, identity resolution, calculated insights), not your own work.

> Salesforce renames menus often (Data Cloud is now also called **Data 360**).
> If a menu name below does not match your org, search for the feature in the
> Setup / Data Cloud search bar. The concepts stay the same.

---

## Step 0 — Install tools (30 min)

| Tool | Why | Check |
|---|---|---|
| Salesforce CLI | deploy code, load data | `sf --version` |
| VS Code + "Salesforce Extension Pack" | edit Apex | — |
| Git | version control | `git --version` |
| GitHub account + GitHub CLI (optional) | publish the repo | `gh --version` |
| Python 3 | generate sample data | `python3 --version` |

Install the CLI with `npm install -g @salesforce/cli` (or the installer from developer.salesforce.com/tools/salesforcecli).

---

## Step 1 — Get a free org with Data Cloud + Agentforce (30 min + waiting)

1. Sign up at **developer.salesforce.com/signup** → "Developer Edition with Agentforce and Data Cloud".
   - Use a **personal email**, not your work email.
   - Limits to know: about 10 GB Data Cloud data, 1 data space, ~150 LLM calls/hour.
   - The org is deleted if not used for a long time (≈45 days). Log in regularly.
2. In **Setup → Data Cloud Setup**, click **Get Started** if Data Cloud is not already provisioned. This can take a while.
3. Assign yourself the Data Cloud admin permission set (Setup → Users → your user → Permission Set Assignments → e.g. *Data Cloud Admin*).
4. In **Setup → Einstein Setup**, turn Einstein on. In **Setup → Agentforce Agents**, turn Agentforce on.

✅ Done when: the App Launcher shows **Data Cloud** and Setup shows **Agentforce Agents**.

---

## Step 2 — Get the project and connect it to the org (15 min)

```bash
# Unzip the project, then:
cd sf-data360-agentforce-demo
sf org login web --alias demo --set-default
sf org display --target-org demo      # confirms you are connected
```

---

## Step 3 — Create sample data and load CRM accounts (15 min)

```bash
python3 scripts/generate_sample_data.py           # re-run so order dates end "today"
sf data import bulk --sobject Account --file data/crm_accounts.csv --line-ending CRLF --target-org demo --wait 10
```

What you now have:

| File | Goes to | Purpose |
|---|---|---|
| `crm_accounts.csv` | Salesforce CRM (Account) | Source 1 |
| `erp_customers.csv` | Data Cloud (file upload) | Same companies, **messy names** → proves identity resolution |
| `orders.csv` | Data Cloud (file upload) | Source 2: 18 months of orders |
| `_answer_key.csv` | nowhere | Which accounts were *designed* to be at risk — use it to check the agent |

✅ Done when: Accounts tab shows 40 accounts.

---

## Step 4 — Ingest both sources into Data Cloud (1–2 h + waiting)

Open **App Launcher → Data Cloud**.

### 4a. CRM accounts (Source 1)
1. **Data Streams → New → Salesforce CRM**.
2. Choose the **Account** object (or the standard Sales bundle) → Next → Deploy.
3. Open the stream and check **Fields mapped** in the Data Mapping box. If it shows 0/0, click
   **Start** → **Standard Data Model → Account** and map `Account ID` → Account Id,
   `Account Name` → Account Name. Save.

> Lesson learned: a data stream can be **Active / Success** and still feed nothing, because the
> mapping is a separate step. Always check "Fields mapped" on every stream.

### 4b. ERP customers CSV (the link between orders and CRM accounts)
1. **Data Streams → New → File Upload** → `data/erp_customers.csv`.
2. Category: **Profile**. Primary key: `erp_customer_id`.
3. Mapping: **Custom Data Model → New Custom Object** named **ERP_Customer**, category Profile,
   primary key `erp_customer_id`, keep all 7 fields ticked → Save → Save mapping.
   (`crm_account_number` in this file is the shared key to CRM `Account.AccountNumber`.)
4. Map **only** to ERP_Customer here (plus Account / Contact Point objects if you do Step 5).
   Do **not** map this stream to Customer_Order.

### 4c. Orders CSV (Source 2)
1. **Data Streams → New → File Upload** → `data/orders.csv`.
2. Category: **Engagement**. Primary key: `order_id`. Event time field: `order_date`.
   - `order_date` must be type **Date** and `amount` **Number**.
3. Mapping: **Custom Data Model → New Custom Object** named **Customer_Order**, category Engagement,
   primary key **`order_id`**, event time `order_date`, all 6 fields ticked → Save → Save mapping.
   Fields mapped should show 6/10 (the other 4 are system fields).
4. Relationship: **Data Model → Customer_Order → Relationships → Edit → New Relationship**:
   `erp_customer_id` → **N:1** → **ERP_Customer** → `erp_customer_id`. Save. It turns Active once
   both objects have data.

✅ Done when (run in **Explore & Optimize → Query Editor**, see `docs/datacloud/check_queries.sql`):
- `Customer_Order__dlm` has ~1,325 rows. **If it has exactly 40**, a wrong stream is mapped into it
  or its primary key is `erp_customer_id` (one row kept per customer).
- `ERP_Customer__dlm` has 40 rows.
- The join query returns 40 account numbers.

---

## Step 5 — Identity resolution on Account (optional, 1–2 h + waiting)

The insight in Step 6 does **not** depend on this step. Do it to show Customer 360 configuration.

1. Map `erp_customers.csv` **also** to the standard **Account** DMO (`erp_customer_id` → Account Id,
   `customer_name` → Account Name). *Account only appears as a ruleset object once something is
   mapped to it.*
2. Map both CRM and ERP streams to **Contact Point Address** (City, Country) and **Contact Point
   Phone** (Telephone Number). In each, map **Party** and the object's Id to the account id
   (`Account ID` for CRM, `erp_customer_id` for ERP). Missing Party / Id fields show up as
   "Data mapping warnings" on the ruleset and stop all merging.
3. **Identity Resolution → New Ruleset** → Primary object **Account**.
4. Create **two separate match rules** (separate rules = OR; criteria inside one rule = AND):
   - Rule "Name + Address": Account Name (Fuzzy, Medium) + City (Exact) + Country (Exact)
   - Rule "Phone": Telephone Number (Exact) + Account Name (Fuzzy, Low)
   Every rule must contain at least one Account field, so phone alone is rejected.
5. Save → **Run Ruleset**.

**Result in the reference build:** 80 source profiles → 74 unified (8%). Fuzzy name matching missed
most variants ("Sued Reifen GmbH" vs "SUED REIFEN-HANDEL GMBH"). Because the ERP master carries the
CRM account number, the insight uses that exact key instead. When a shared key exists, an exact
match is more reliable than fuzzy matching; fuzzy identity resolution is for when none exists.

---

## Step 6 — Calculated Insight (30 min + waiting)

1. **Analyze & Predict → Calculated Insights → New → Create with SQL**.
2. Paste the **definition** SQL from `docs/datacloud/account_health_calculated_insight.sql`
   (not the check queries; those read *from* the insight and only work after it has run).
3. **Check Syntax**, then **Preview Insight**: expect 40 rows and **positive** days since last order.
   - Data Cloud SQL has no `DATE_SUB`, and `DATEDIFF` takes 3 arguments: `DATEDIFF('day', start, end)`.
   - When typing in the editor, press **Esc** to close autocomplete, or it inserts duplicate names.
4. API name **Account_Health** (becomes `Account_Health__cio`). Types: `account_number__c` =
   Dimension, the 4 numbers = Measures/Metrics. Save → Publish. Set a schedule.
5. **It does not run on its own right away.** Use **Publish Now / Run Now**, and wait until
   *Last Run Status = Success*.

✅ Done when: `SELECT * FROM Account_Health__cio LIMIT 20` in Query Editor returns rows.

---

## Step 7 — Deploy and test the Apex action (30 min)

```bash
sf project deploy start --source-dir force-app
sf apex run test --test-level RunLocalTests --code-coverage --result-format human --wait 10
sf org assign permset --name Account_Insight_Agent_Access
sf apex run --file scripts/run_action.apex
```

- If the deploy table shows **Unchanged** for a file you edited, the edit is not in the folder you
  deploy from (e.g. you unzipped into a sub-folder).
- "Duplicate PermissionSetAssignment" means it is already assigned — not an error.
- In the debug log, `|` shows as `&#124;`. That is log escaping only.

Compare the printed list with `data/_answer_key.csv`: every returned account should be `declining`
or `gone_quiet`. The reference build flagged exactly the 16 designed accounts.

---

## Step 8 — Build the Agentforce agent (1 h)

In the current Agentforce Builder, **topics are called "Subagents"**.

1. **Setup → Agentforce Agents → New Agent** → **Agentforce Employee Agent** → name it
   `Account Insight Agent`.
2. Explorer → **+** → **New Subagent**:
   - **Name:** At-Risk Account Outreach
   - **Description** (used by the Agent Router to pick this subagent): Questions about which
     customer accounts are at risk of churn, which accounts to call, or which accounts need
     attention because orders dropped or stopped.
   - **Instructions:**
     - Always use the action "Get At-Risk Accounts To Call" to answer. Never guess account names or numbers.
     - Use 5 results unless the user asks for a different number.
     - If the user says "my accounts", set Only My Accounts to true; otherwise false.
     - Show the result as a numbered list and keep the reason for each account.
     - If no accounts are returned, say so and state the rule that was used.
     - Do not create or change records.
3. In the subagent: **Actions → Add Action**:
   - Reference Action Type **Apex** → Reference Action Category **Invocable Method** →
     **Get At-Risk Accounts To Call**.
   - Inputs: none required. Output **Summary**: show in conversation.
   - If it is not listed: Setup → **Agentforce Assets → Actions → New Agent Action**, then add it
     to the subagent from the asset library.
4. Check that the **Agent Router** now routes to the new subagent.
5. **Preview**:
   - "Which at-risk accounts should I call this week?" → same 5 accounts as the CLI test
   - "Show me the top 3 at-risk accounts with at least 200,000 EUR revenue." → 2 accounts
   - "What's the weather in Frankfurt?" → must **not** call the action
6. **Save → Commit Version → Activate**.

🎥 Record a 60–90 second video of the main question → answer, with the trace panel open.

---

## Step 9 — Pull the agent config into the repo (15 min)

Agent metadata needs **API version 65+** (`sourceApiVersion` is 66.0 in `sfdx-project.json`).

```bash
sf project retrieve start --metadata Bot GenAiPlannerBundle GenAiPlugin GenAiFunction
# newer builder versions also store an Agent Script bundle:
sf project retrieve start --metadata AiAuthoringBundle
```

If a type is not recognised, update the CLI (`npm install -g @salesforce/cli`) and retry.
Data Cloud setup (streams, rulesets, insights) is documented in `docs/datacloud/` and screenshots,
not deployed as code.

---

## Step 10 — Screenshots and GitHub (45 min)

### Screenshots (save in `docs/screenshots/` with these exact names)

Crop out your org URL and username.

| File | Where to find it |
|---|---|
| `01-data-streams.png` (optional) | Data Cloud → **Connect & Unify → Data Streams**, only once all 3 show **Success**. If refreshes keep failing, use the record-count table in the README instead (as the reference build does) |
| `02-identity-resolution.png` | **Connect & Unify → Identity Resolution → Account Unification** |
| `02b-data-model.png` | **Connect & Unify → Data Model → Customer_Order → Relationships** tab (shows N:1 to ERP_Customer). Alternative: the orders.csv stream → **Review Mappings** canvas |
| `03-calculated-insight.png` | **Analyze & Predict → Calculated Insights → Account_Health** → Edit → **Preview Insight** (40 rows) — or the **Output** tab |
| `04-apex-tests.png` | Terminal output of the `sf apex run test` command (Win + Shift + S to capture) |
| `05-agent-config.png` (optional) | Agentforce Builder → **Agent Definition** diagram. The reference build documents the config as code in `docs/agent/agent-script.md` instead |
| `06-agent-answer.png` | Agentforce Builder → **Preview** with the answer to the main question |

### GitHub

```bash
git init
git add .
git status          # .sf/ and .sfdx/ must NOT be listed (they hold org login info)
git commit -m "Unified Customer 360 + Account Insight Agent (Data Cloud + Agentforce + Apex)"
git branch -M main
# create an EMPTY repo on github.com first (no README), then:
git remote add origin https://github.com/<your-username>/sf-data360-agentforce-demo.git
git push -u origin main
```

On GitHub: add topics `salesforce`, `data-cloud`, `agentforce`, `apex`; add the video link at the
top of the README; **pin** the repo on your profile.

---

## Troubleshooting (everything below happened during the reference build)

| Problem | Cause | Fix |
|---|---|---|
| Bulk import: 40/40 records failed | State & Country picklists on; `BillingCountry` = "DE" rejected | Use the `BillingCountryCode` column (generator now does this); add `--line-ending CRLF` on Windows |
| `python3` not found (Windows) | Windows uses `py` | `py scripts\generate_sample_data.py` |
| Stream Success but nothing in the DMO | Fields mapped 0/0 | Map the stream (Step 4) |
| Relationship shows Inactive | One side has no mapped data | Map both objects, refresh streams |
| Customer_Order has 40 rows, order_date empty | erp_customers.csv mapped into Customer_Order | Remove that mapping; map orders.csv |
| Ruleset only offers Individual / Household | Nothing mapped to Account yet | Map a stream to Account |
| Ruleset 0% with warnings | Party / Id not mapped on contact point objects | Map required fields (Step 5) |
| Ruleset 0% after adding phone | Phone added inside the same rule (AND) | Use separate rules (OR) |
| "More match criteria are required" | Each rule needs an Account field | Add Account Name to the rule |
| `function "DATE_SUB" does not exist` | Not supported in Data Cloud SQL | Use `DATEDIFF('day', start, end)` |
| `wrong number of arguments … DATEDIFF` | Needs 3 arguments | `DATEDIFF('day', o.order_date__c, CURRENT_DATE())` |
| Insight query returns 0 rows | Insight never ran | Publish Now / Run Now |
| Action "Could not read account insights…" | Wrong object/field name | Check names in `DataCloudNames.cls` |
| Retrieve: `UNSUPPORTED_API_VERSION` | Agent metadata needs API 65+ | `sourceApiVersion` 66.0 or `--api-version 66.0` |
| Agent answers without calling the action | Instructions too vague | Make "always use the action" explicit |
