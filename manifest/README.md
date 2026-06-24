# Deployment manifests

| File                       | Deploy when                                 | Contents                                                                                                             |
| -------------------------- | ------------------------------------------- | -------------------------------------------------------------------------------------------------------------------- |
| `package-phase1-core.xml`  | First                                       | Object, Apex, LWCs, app, permission sets, CSP, `Portfolio_Queue` + `Messaging` queue routing config                  |
| `package-phase2-agent.xml` | After Phase 1                               | Agent script, bot, planner bundles — run `.\scripts\deploy-phase2-agent.ps1 -TargetOrg myorg -OwnerName "Your Name"` |
| `package-phase3-site.xml`  | **After** LWR site shell in org (see below) | Digital Experience bundle `Vishal_Shukla_Portfolio1` + CMS content                                                   |
| `package.xml`              | Re-install / org already set up             | Everything (includes org-specific ESW metadata)                                                                      |

### Phase 3 — create the site shell before deploying

```powershell
.\scripts\create-portfolio-site.ps1 -TargetOrg myorg
```

Or manually:

```bash
sf community create --name "My_Portfolio" --template-name "Build Your Own (LWR)" \
  --url-path-prefix myportfolio templateParams.AuthenticationType=AUTHENTICATED_WITH_PUBLIC_ACCESS_ENABLED \
  --target-org myorg
```

`--name My_Portfolio` creates the CMS bundle **`Vishal_Shukla_Portfolio1`** (Salesforce appends `1`). That must match `digitalExperiences/site/Vishal_Shukla_Portfolio1/` in the project.

Then:

```bash
sf project deploy start --manifest manifest/package-phase3-site.xml --target-org myorg
```

Full details in root `README.md`. Phase 4 (Enhanced Chat + Embedded Messaging) is manual after Phases 2–3.
