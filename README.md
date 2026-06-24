# Personal Portfolio + Agentforce Agent

A self-contained Salesforce DX project that ships **two things that work together**:

1. **A public portfolio website** — an Experience Cloud (LWR) site with a rich hero + content grid (`portfolioHome` LWC) that anyone can visit, plus AI-assisted admin tools to fill it with your content.
2. **A "Personal Portfolio" Agentforce agent** — a public-facing service agent, embedded on the site, that answers visitor questions about you (bio, resume, skills, projects, content links) and captures connection requests as Leads.

Everything the site shows and the agent says is grounded in one custom object — `Portfolio_Item__c` — so there are **no prompt templates, retrievers, or external web calls** to configure. Add records, and both the site and the agent update automatically.

---

## Live demo

A deployed example of this project:

🔗 **[orgfarm-7d0791f685-dev-ed.develop.my.site.com/myportfolio](https://orgfarm-7d0791f685-dev-ed.develop.my.site.com/myportfolio/)**

[![Personal Portfolio site with the embedded Personal Portfolio Agent](docs/portfolio-site-preview.png)](https://orgfarm-7d0791f685-dev-ed.develop.my.site.com/myportfolio/)

The hero, content grid, and resume download come from `Portfolio_Item__c` records, and the **Personal Portfolio Agent** answers questions in the chat panel (open it with **Ask AI** / **Chat with my AI assistant**).

---

## What's in the box

| Area                | Metadata                                                                                                                                                                              |
| ------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Data model**      | `Portfolio_Item__c` custom object (13 fields), tab, layout, `All_Items` list view                                                                                                     |
| **Portfolio site**  | Digital Experience (LWR) site bundle `Vishal_Shukla_Portfolio1` (label `My_Portfolio` — see **Phase 3**), `portfolioHome` LWC, `portfolioBridge` static resource, 6 CSP Trusted Sites |
| **Admin tools**     | `Portfolio_Manager` app, `portfolioOnboarding` LWC ("Portfolio Setup (AI)"), `portfolioItemAssistant` LWC ("Portfolio Item AI Assistant")                                             |
| **Agent**           | `Personal_Portfolio_Agent` (Agent Script bundle + Bot + version `v14` + planner bundles), `Portfolio_Agent` Messaging Channel + Embedded Service deployment                           |
| **Apex**            | 8 classes (+ tests): public/PDF controllers and the agent's invocable actions                                                                                                         |
| **Messaging queue** | `Portfolio_Queue` + `Messaging` queue routing config (Phase 1)                                                                                                                        |
| **Security**        | 5 permission sets (owner, manager, guest, agent, agent-guest)                                                                                                                         |

**Apex classes at a glance**

- `PortfolioPublicController` — read-only data for the public `portfolioHome` grid.
- `PortfolioPdfController` — generates the downloadable resume/portfolio PDF in Apex (no Visualforce).
- `PortfolioOnboardingService` — turns a pasted resume into draft records (Models API). Powers onboarding.
- `PortfolioContentAssistant` — generates/improves descriptions & resume text on a record (Models API).
- `PortfolioItemProvider`, `PortfolioOverviewProvider`, `ResumeDetailsProvider`, `ConnectionRequestCreator` — the agent's invocable actions.

---

## Prerequisites

- **Salesforce CLI** (`sf`) — [install guide](https://developer.salesforce.com/docs/atlas.en-us.sfdx_setup.meta/sfdx_setup/sfdx_setup_intro.htm). Verify with `sf version`.
- A target **Salesforce org** (Developer Edition, sandbox, or scratch org) with these features enabled in **Setup**:
  - **Agentforce** (Agentforce Service Agents)
  - **Einstein / Models API** (required by the AI onboarding + content assistant)
  - **Digital Experiences** (Experience Cloud) with the **"Build Your Own (LWR)"** template available
  - **Omni-Channel** (required by the messaging queue deployed in Phase 1)
- **Node.js 18+** — only needed to run the linter / Jest tests locally (`npm install`).

---

## Installation

Deploy in **phases**. A single `package.xml` deploy fails on a fresh org because three metadata types are org-specific or need a site shell that is not in the repo. The phased manifests live under `manifest/package-phase*.xml`. Make sure the [Prerequisites](#prerequisites) features are enabled in Setup before you start.

### Why a one-shot deploy fails

| Root cause                             | Metadata                 | What the error means                                                                                                                                                                           |
| -------------------------------------- | ------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Missing site shell**                 | 29 × `DigitalExperience` | The bundle ships pages/themes/routes but not `DigitalExperienceConfig`, which creates the Experience Cloud site. Salesforce cannot create `site/<your-site-name>` content without that shell.  |
| **Org-specific Embedded Service site** | `EmbeddedServiceConfig`  | References `ESW_Portfolio_Agent_17813183264601` — a CustomSite auto-created in the **source** org. That name does not exist in yours.                                                          |
| **Deploy order / missing bot**         | `MessagingChannel`       | References bot `Personal_Portfolio_Agent`. If the bot is not deployed yet (or Agentforce is not enabled), the channel fails. Even when the bot deploys, the bundled ESW config still will not. |

**What already succeeds** in a partial deploy: data model, Apex, LWCs, permission sets, app, CSP sites (~55 components). If you hit the errors above, continue from **Phase 2** below instead of starting over.

### 1. Get the code and dependencies

```bash
git clone https://github.com/SalesforceDiariesBySanket/publish-portfolio-with-agentforce.git "Personal Portfolio"
cd "Personal Portfolio"
npm install   # optional — only for linting / LWC Jest tests
```

### 2. Authorize your org

```bash
# Existing org (Dev Edition / sandbox)
sf org login web --alias myorg --set-default

# …or spin up a scratch org instead (Dev Hub required)
sf org create scratch --definition-file config/project-scratch-def.json \
  --alias myorg --set-default --duration-days 30
```

### 3. Deploy Phase 1 — Core

Object, Apex, LWCs, app, permission sets, CSP Trusted Sites, and the messaging queue.

```bash
sf project deploy start --manifest manifest/package-phase1-core.xml --target-org myorg
```

### 4. Deploy Phase 2 — Agent

Script bundle, bot, and planner bundles. One command creates a fresh Einstein Agent User, patches metadata, deploys, assigns permission sets, and activates. Set your name **before** this first deploy — after activation, changing `owner_name` requires a new agent version:

```powershell
.\scripts\deploy-phase2-agent.ps1 -TargetOrg myorg -OwnerName "Your Name"
```

The script creates a new Einstein Agent User, updates `owner_name`, `botUser`, and `default_agent_user` in your local project, then deploys `manifest/package-phase2-agent.xml`.

### 5. Deploy Phase 3 — Experience site (manual site shell required)

Enable **Digital Experiences** in Setup → **Feature Settings → Digital Experiences → Settings** before creating the site shell.

Create the site shell:

```bash
sf community create --name "My_Portfolio" --template-name "Build Your Own (LWR)" --url-path-prefix "myportfolio" --description "Personal Portfolio site" templateParams.AuthenticationType=AUTHENTICATED_WITH_PUBLIC_ACCESS_ENABLED --target-org myorg
```

Site creation is async (usually 1–2 minutes). Wait until the job completes before deploying — or use the helper script, which runs the command above and polls until the shell is ready:

```powershell
.\scripts\create-portfolio-site.ps1 -TargetOrg myorg
```

Then deploy Phase 3:

```bash
sf project deploy start --manifest manifest/package-phase3-site.xml --target-org myorg
```

### 6. Configure Phase 4 — Enhanced Chat + Embedded Messaging (manual)

Do **not** deploy `EmbeddedServiceConfig` or `MessagingChannel` from this repo into a new org — they contain source-org IDs. Phase 1 already deploys **`Portfolio_Queue`** and the **`Messaging`** queue routing config used as the agent fallback queue.

Complete this **after** Phase 2 (agent activated) and Phase 3 (site published). You need your published portfolio site URL for the channel domain.

#### Step 1 — Add a channel

1. Setup → **Messaging Settings** → **Messaging Channels** → **Add Channel**.
2. Under **Native Channels**, select **Enhanced Chat**.

#### Step 2 — Channel settings

Fill in the required fields, then click **Next** and **Save**:

| Field               | Value                                                                                                                                          |
| ------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------- |
| **Channel Name**    | `Portfolio Agent` (or your preferred label)                                                                                                    |
| **Developer Name**  | `Portfolio_Agent`                                                                                                                              |
| **Deployment Type** | **Web**                                                                                                                                        |
| **Domain**          | Your published portfolio site domain — e.g. `myportfolio.my.site.com` (from **Setup → Digital Experiences → All Sites** after Phase 3 publish) |

Saving creates an **Embedded Service deployment** automatically (with **Client Version WebV1**).

#### Step 3 — Switch the deployment to Enhanced Chat V2

The auto-created deployment starts on **WebV1**. Upgrade it before publishing:

1. Setup → **Embedded Service Deployments** → open **Portfolio_Agent** (or from **Messaging Settings** → open your channel → **Embedded Service Deployments** → click **Portfolio_Agent**).
2. Confirm the page title shows **Embedded Service Deployment Settings - Web (v1)** and **Client Version** is **WebV1**.
3. Click **Switch to V2** (top right, next to **Publish**).
4. Complete the upgrade prompts. When finished, the deployment should show **WebV2** (verify under **Messaging Settings** → your channel → **Embedded Service Deployments**).

#### Step 4 — Omni-Channel Routing

Open the new channel (or the auto-created deployment) and edit **Omni-Channel Routing**:

| Field                        | Value                        |
| ---------------------------- | ---------------------------- |
| **Routing Type**             | **Agentforce Service Agent** |
| **Agentforce Service Agent** | **Personal Portfolio Agent** |
| **Fallback Queue**           | **Portfolio Queue**          |

(`Portfolio Queue` is deployed in Phase 1.)

#### Step 5 — Publish the deployment

1. Setup → **Embedded Service Deployments** → open the deployment created for this channel.
2. Confirm it is linked to your Experience site, the **Portfolio Agent** channel, and **Client Version** is **WebV2** (after Step 3).
3. **Publish** the deployment.

#### Step 6 — Wire the site LWC (Custom Labels)

`portfolioHome` reads Embedded Messaging settings from **Custom Labels** — you do not edit the LWC source.

1. Open the deployment's **code snippet** and copy its four values (`orgId`, deployment name, site URL, `scrt2URL`).
2. In Setup, go to **Custom Labels** and update each label to match your snippet:

| Custom Label                 | Code snippet value                      |
| ---------------------------- | --------------------------------------- |
| **Portfolio ESW Org Id**     | `orgId`                                 |
| **Portfolio ESW Deployment** | deployment / `embeddedServiceName`      |
| **Portfolio ESW Site Url**   | `siteUrl` (full URL, no trailing slash) |
| **Portfolio ESW Scrt2 Url**  | `scrt2URL`                              |

Changes take effect immediately on the site — no LWC redeploy is required.

**Alternative (metadata deploy):** edit the four values in `force-app/main/default/labels/CustomLabels.labels-meta.xml`, then deploy:

```bash
sf project deploy start --source-dir force-app/main/default/labels --target-org myorg
```

> **All-in-one deploy** (`manifest/package.xml`) is only safe when the target org already has the site shell, bot, and ESW deployment from a prior install. For greenfield orgs, use the phases above.

### 7. Assign permission sets

Assign each set to the right user. (`--on-behalf-of` lets an admin assign to another user.)

```bash
# You (owner / admin) — manage content, the app, and follow up on Leads
sf org assign permset --name Portfolio_Owner_Access --target-org myorg

# Optional: a content editor who only manages records + AI authoring
sf org assign permset --name Portfolio_Manager --target-org myorg
```

The guest and agent permission sets are assigned in **Part 1** and **Part 2** below.

---

## Part 1 — Portfolio site setup

Goal: a public Experience Cloud page where visitors see your hero, content cards, resume download, and the "Ask AI" button.

### 1.1 Confirm Models API access (for the AI authoring tools)

In **Setup → Einstein / Models API**, confirm generative models are turned on. The onboarding and item-assistant components call `aiplatform.ModelsAPI`; without it you can still add records manually.

### 1.2 Add your content

Open the **Portfolio Manager** app (App Launcher → _Portfolio Manager_). Choose either path:

- **Fast start (AI):** Add the **"Portfolio Setup (AI)"** component (`portfolioOnboarding`) to a Home/App page, paste your resume, pick a model, review the generated items, and click **Create**. Re-running with an updated resume updates records in place instead of duplicating them.
- **Manual / fine-tune:** Use the **Portfolio Item** tab to create records directly. Drop the **"Portfolio Item AI Assistant"** (`portfolioItemAssistant`) onto the record page to generate or improve a description or the resume text per item.

Key fields on `Portfolio_Item__c`:

| Field                                                                                                                          | Purpose                                                                                                                              |
| ------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------ |
| `Type__c`                                                                                                                      | Category that drives grouping/rendering (Bio, Experience, Project, Skill, LinkedIn, GitHub, etc. — pick **Other** to type your own). |
| `Active__c`                                                                                                                    | Only active items appear on the site and to the agent.                                                                               |
| `Is_Featured__c`                                                                                                               | Promotes an item into the "Featured" row.                                                                                            |
| `Sort_Order__c`                                                                                                                | Manual ordering within a section.                                                                                                    |
| `Resume_Details__c`                                                                                                            | Rich-text resume body the agent reads for free-form career questions.                                                                |
| `Subtitle__c`, `Description__c`, `URL__c`, `Secondary_URL__c`, `Image_URL__c`, `Tech_Stack__c`, `Start_Date__c`, `End_Date__c` | Display / detail fields.                                                                                                             |

### 1.3 Publish the Experience site

After Phase 3 deploy succeeds (or if you created the shell manually in Setup), configure and publish the site:

1. **Setup → Digital Experiences → All Sites** and open your site in **Experience Builder** (`My_Portfolio`).
2. On the Home page, drop in the **Portfolio Home** component and set its properties: `ownerName`, `roleTitle`, `headline`, `location`, `avatarUrl`, `subheadline`, and `showItems`.
3. **Publish** the site and note its base URL (you'll need it for the agent in Part 2).

### 1.4 Grant guest access

So anonymous visitors can read your items and download the PDF, assign the guest permission set to the **site Guest User** (Experience Builder → Settings → General → _Guest User Profile_, or via CLI):

```bash
sf org assign permset --name Portfolio_Guest_Access \
  --on-behalf-of "<Site> Site Guest User" --target-org myorg
```

### 1.5 Allow external images (CSP)

The 6 bundled **CSP Trusted Sites** (`Portfolio_YouTube`, `Portfolio_YouTube_Img`, `Portfolio_YTImg`, `Portfolio_YouTube_NoCookie`, `Portfolio_Google_Favicons`, `Portfolio_Placehold`) cover YouTube thumbnails/embeds, link favicons, and image placeholders. If you host avatars/images elsewhere, add that domain as a CSP Trusted Site too.

### 1.6 Share Portfolio records with the guest user (criteria-based sharing rule)

The guest permission set (Part 1.4) grants the Guest User **object + field** access to `Portfolio_Item__c`, but with private org-wide defaults the guest still can't **see any records**. Create a criteria-based sharing rule so active items become visible on the public site.

1. **Setup → Sharing Settings** (or **Setup → Security → Sharing Settings**). Under **Portfolio Item Sharing Rules**, click **New**.
2. Fill in the rule:

| Field            | Value                                                            |
| ---------------- | ---------------------------------------------------------------- |
| **Label**        | `Share Portfolio Records`                                        |
| **Rule Name**    | `Share_Portfolio_Records`                                        |
| **Rule type**    | **Based on criteria**                                            |
| **Criteria**     | Field `Active` &nbsp;**equals**&nbsp; `True`                     |
| **Share with**   | `<Site> Site Guest User` (e.g. **My_Portfolio Site Guest User**) |
| **Access Level** | **Read Only**                                                    |

3. **Save**. Salesforce shows a warning that the rule grants access to guest users without login credentials — this is expected for a public portfolio. Confirm to apply.

> Guest-user sharing rules can only share with a single **Site Guest User** and only at **Read Only** access. Matching only `Active = True` keeps drafts/inactive items hidden from the public site and the agent.

✅ Visit the published site as a guest (incognito) — you should see your hero and content cards.

---

## Part 2 — Agent setup

Goal: the **Personal Portfolio Agent** answers visitor questions on the site via Embedded Messaging and logs connection requests as Leads.

### 2.1 Personalize the agent

If you ran `deploy-phase2-agent.ps1` with `-OwnerName`, then `owner_name`, `botUser`, and `default_agent_user` are already set. For manual edits later:

- **`Personal_Portfolio_Agent.agent`** — `owner_name`, `default_agent_user`
- **`Personal_Portfolio_Agent.bot-meta.xml`** — `botUser`

After the agent is **activated**, changing `owner_name` requires deactivating, redeploying, and activating again (or publishing a new version). Set the name on the first Phase 2 run.

### 2.2 Assign agent permission sets

```bash
# The bot's run-as user (Einstein Agent User): read items + create Leads
sf org assign permset --name Portfolio_Agent_Access \
  --on-behalf-of "<einstein agent user>" --target-org myorg

# The site Guest User (so the embedded agent can run its actions for visitors)
sf org assign permset --name Portfolio_Agent_Guest_Access \
  --on-behalf-of "<Site> Site Guest User" --target-org myorg
```

### 2.3 Activate the agent

`sf agent activate` does **not** assign the run-as user. If you see _"This Agent Type should have a user assigned"_, the bot was deployed with a `botUser` that does not exist in your org. Fix it from the CLI:

```bash
# Confirm BotUser is null or wrong
sf data query --query "SELECT BotUser.Username FROM BotDefinition WHERE DeveloperName = 'Personal_Portfolio_Agent'" --target-org myorg

# Find a valid Einstein Agent User, set botUser + default_agent_user in the repo, redeploy the bot, then activate:
sf project deploy start --metadata Bot:Personal_Portfolio_Agent --target-org myorg
sf agent activate --api-name Personal_Portfolio_Agent --target-org myorg
```

After Phase 2 deploy (with a valid `botUser`), activate:

```bash
sf agent activate --api-name Personal_Portfolio_Agent --target-org myorg
```

Or in **Setup → Agentforce / Agent Studio**, open **Personal Portfolio Agent**, confirm the latest version (**v14**) is selected, and **activate** it.

### 2.4 Wire up Embedded Messaging on the site

Follow **Phase 4** above: create the **Enhanced Chat** channel, **Switch to V2** on the auto-created deployment, set Omni-Channel Routing to **Personal Portfolio Agent** with fallback **Portfolio Queue**, publish the Embedded Service deployment, then complete **Phase 4 Step 6** — paste the deployment code snippet into the four **Portfolio ESW** Custom Labels (`Portfolio_ESW_Org_Id`, `Portfolio_ESW_Deployment`, `Portfolio_ESW_Site_Url`, `Portfolio_ESW_Scrt2_Url`).

> `portfolioHome` loads Embedded Messaging itself so the hero's **"Ask AI"** button can launch the chat directly. Those four Custom Label values **must** match your org/deployment or the chat won't open.

### 2.5 Test the agent

```bash
# Conversational test from the CLI
sf agent preview --api-name Personal_Portfolio_Agent --target-org myorg
```

Then load the published site and click **Ask AI** — try "what's in the portfolio?", "tell me about your experience", and "I'd like to connect" (which should create a Lead).

---

## Customizing for your own portfolio (checklist)

- [ ] Phase 2 script with your name: `.\scripts\deploy-phase2-agent.ps1 -TargetOrg myorg -OwnerName "Your Name"`
- [ ] `botUser` in the bot meta + `default_agent_user` in the agent file
- [ ] Phase 4 Enhanced Chat channel + **Switch to V2** + Omni-Channel Routing (Personal Portfolio Agent → Portfolio Queue fallback)
- [ ] Portfolio ESW Custom Labels (org id, deployment, site URL, scrt2 URL) — Phase 4 Step 6
- [ ] Hero properties on the `portfolioHome` component in Experience Builder
- [ ] Your own `Portfolio_Item__c` records (via onboarding or the Portfolio Manager app)
- [ ] CSP Trusted Sites for any external image / avatar hosts
- [ ] Criteria-based sharing rule `Share_Portfolio_Records` (Active = True → Site Guest User, Read Only) — Part 1.6

---

## Useful commands

```bash
sf project deploy start --manifest manifest/package-phase1-core.xml --target-org myorg   # Phase 1 — Core
.\scripts\deploy-phase2-agent.ps1 -TargetOrg myorg -OwnerName "Your Name"                # Phase 2 — Agent (automated)
.\scripts\create-portfolio-site.ps1 -TargetOrg myorg                                     # Phase 3 — create LWR site shell + wait
sf project deploy start --manifest manifest/package-phase3-site.xml --target-org myorg   # Phase 3 — deploy site bundle
# Phase 4 — manual: Enhanced Chat channel + Switch to V2 + publish ESW deployment (see Phase 4 above)
sf project deploy start --manifest manifest/package.xml --target-org myorg               # full deploy (existing org only)

sf apex run test --target-org myorg --code-coverage --result-format human                # run Apex tests
npm run test:unit                                                                        # LWC Jest tests
npm run lint                                                                             # ESLint (aura / lwc)
npm run prettier                                                                         # format
sf agent preview --api-name Personal_Portfolio_Agent --target-org myorg                  # chat with the agent
```

---

## Learn more

- [Salesforce DX Developer Guide](https://developer.salesforce.com/docs/atlas.en-us.sfdx_dev.meta/sfdx_dev/sfdx_dev_intro.htm)
- [Agentforce / Agent Script](https://developer.salesforce.com/docs/einstein/genai/guide/agent-dsl.html)
- [Models API](https://developer.salesforce.com/docs/einstein/genai/guide/models-api.html)
- [Experience Cloud (LWR sites)](https://developer.salesforce.com/docs/atlas.en-us.exp_cloud_lwr.meta/exp_cloud_lwr/intro.htm)
- [Salesforce CLI Command Reference](https://developer.salesforce.com/docs/atlas.en-us.sfdx_cli_reference.meta/sfdx_cli_reference/cli_reference.htm)
