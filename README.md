# Trade License Management System

A Salesforce application that enforces payment-gated address changes for government-issued trade licenses, with automated card reprint flagging and a complete audit trail.

**Platform:** Salesforce DX · API v64.0 · **Coverage:** 95% Handler · 100% Trigger · **Deploy time:** ~5 minutes

---

## What It Does

Government licensing agencies need to prevent staff from changing a licensed business address without collecting the required $50 fee. This system forces all address changes through a guided workflow: a Screen Flow collects the new address and simulates payment, an Apex trigger auto-updates the License record after confirmation, and a validation rule blocks any attempt to edit the address directly.

**User persona:** Internal licensing agency staff (clerk-facing). Not a public portal — staff process requests on behalf of business owners who call in or walk in.

---

## How It Works

1. Staff opens a License record and clicks **Request Address Change**
2. A 4-screen Flow walks through: current address → new address → $50 payment → success
3. The Flow creates an `Address_Change_Request__c` record, then updates it with `Payment_Confirmed__c = true`
4. That update fires an Apex trigger, which updates the License address and marks the request Completed
5. A validation rule blocks any direct edit to address fields outside this process

---

## Data Model

**`License__c`** — the issued license, tied to a specific operating address. One Account can have multiple Licenses at different locations.

**`Address_Change_Request__c`** — one per address change transaction. Master-Detail to `License__c` (cascade delete, enforces ownership). Stores the full before/after address snapshot, who requested it, when, and payment details.

---

## Key Design Decisions

**Validation rule + Custom Setting bypass instead of a trigger-only block** — validation rules run before triggers and show user-visible error messages natively. The handler opens the bypass window, updates the License, then closes it in a `finally` block so it's always re-disabled even on failure.

**Master-Detail instead of Lookup** — a request cannot exist without its parent License. Cascade delete, no orphaned records, and the relationship accurately models the business constraint.

**Screen Flow instead of LWC** — a 4-step linear wizard with two DML operations and no custom UI logic is exactly what Screen Flow is for. An LWC would be more code for the same result in this context.

**Address fields on `License__c` instead of `Account`** — licensed operating address and billing address are legally distinct. A restaurant chain with 10 locations is one Account, 10 Licenses, each at a unique address.

---

## What's Stubbed

| Component | Current | Production |
|-----------|---------|------------|
| Payment | `STUB_<timestamp>` transaction ID | Stripe/Authorize.net API + webhook |
| Card printing | `Card_Reprint_Required__c = true` flag | API callout to print vendor (e.g., Lob) |
| Address validation | Any text accepted | USPS or Google Maps API |
| Self-service access | Internal Quick Action | Same Flow in Experience Cloud portal |

---

## Deployment

```bash
git clone <repository-url> && cd trade-license-system
sf org login web --set-default --alias trade-license-dev
sf project deploy start --target-org trade-license-dev
sf apex run test --class-names AddressChangeRequestTest --code-coverage --result-format human --synchronous --target-org trade-license-dev
```

After deploy: Setup → Object Manager → License → Page Layouts → add the **Request Address Change** Quick Action to the actions section.

---

*Take-home technical assignment*
