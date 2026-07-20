# ad-computer-group-automation

Event-driven AD automation: the moment a computer object is created in Active Directory, it's added to every baseline security group it needs — LAPS, Intune enrollment, OneDrive policy, local-admin cleanup — with zero polling and zero human steps.

## Problem
Every new machine joined to the domain needs the same baseline group memberships before it's actually managed: LAPS coverage, Intune enrollment, OneDrive policy, and the group that strips users from local Administrators. Doing it by hand means machines sit unmanaged until someone remembers — and "unmanaged" is exactly the window where a device is imaged, handed to a user, and forgotten.

Scheduled sweeps (run a script every hour, catch stragglers) close the gap but leave machines unmanaged for up to the polling interval, and burn cycles running when nothing changed.

## Approach: trigger on the event, not a timer
Windows already announces every computer-account creation: **Security Event ID 4741** on the domain controller. So the automation subscribes to it.

```
New computer object created in AD
        │
        ▼
Security log — Event ID 4741 (fires immediately)
        │
        ▼
Task Scheduler event trigger ──► AddComputerGroups.ps1
        │
        ├─ Pulls the 4741 event, parses its XML payload
        ├─ Extracts SamAccountName → resolves the computer object
        └─ Adds it to each baseline group, individually try/caught:
           LAPS · Intune-Enrollment · OneDriveComputers ·
           OneDrive-PublicFolder · Remove-Users-From-LocalAdminGrp
        │
        ▼
Per-step log (C:\Scripts\GroupScriptLog.txt) — every add,
success or failure, is written down
```

## Design decisions
- **Event-driven, not scheduled.** The task's trigger is an event-log subscription (`*[System[(EventID=4741)]]` on the Security log), so it fires within seconds of the object existing. No polling loop, no coverage gap, no wasted runs.
- **The event itself carries the payload.** The script parses the 4741 event's XML and reads `SamAccountName` from the event data — no directory search to guess which machine is new, and the trailing `$` on the computer account name is stripped before lookup.
- **Per-group error isolation.** Each group add is its own try/catch: one missing or renamed group logs an ERROR line and the rest still land. A partial success beats an all-or-nothing failure for a machine that's about to be handed to a user.
- **`IgnoreNew` instance policy.** If two machines are created back-to-back, an already-running instance isn't interrupted and duplicates don't stack.
- **Everything is logged.** Start, extracted name, each add, each failure, finish — auditable after the fact from one text file.

This is the machine-side counterpart to [ad-onboarding-automation](https://github.com/michaellawrence-it/ad-onboarding-automation): users get access from stamped attributes, computers get management from creation events. Nothing in the domain waits for a human to remember it.

## Files
- [`AddComputerGroups.ps1`](AddComputerGroups.ps1) — the script (production, sanitized paths only)
- [`Task/Add-computer-to-appropriate-groups.xml`](Task/Add-computer-to-appropriate-groups.xml) — the exported Task Scheduler definition with the 4741 event subscription (author/SID sanitized)

## Result
- New machines are LAPS-covered, Intune-enrolled, and policy-compliant **before they reach a user's desk**
- Running in production since March 2026 — last run result: `0x0`, like every run before it
- Baseline-membership tickets for new machines: **eliminated**

## Stack
PowerShell · ActiveDirectory module · Windows Task Scheduler (event trigger) · Security event log

> Sanitized: authoring domain/account and SID are placeholders. Group names and logic are the real production configuration.
