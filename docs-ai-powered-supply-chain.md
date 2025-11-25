# AI-Powered, Dynamic Supply Chain Management – Smart Contract Documentary

## 1. Big-picture idea (what this is)
This project is an enterprise-focused Clarinet (Clarity) smart contract that models an AI-driven, IoT-aware supply chain. The goal is to move away from emails, spreadsheets, and manual reconciliations and toward a system where:

- **IoT sensors** track goods in real time (location, temperature, humidity, shock, etc.).
- **AI services** analyze that data off-chain to detect delays, route issues, or quality problems.
- **Smart contracts** on Stacks automatically handle **escrow, payouts, and penalties** when shipments reach (or fail to reach) their checkpoints.

So instead of “we’ll pay you when our back office approves this invoice,” payment becomes: “when the shipment is confirmed healthy at the final checkpoint, funds are released automatically.”

## 2. On-chain model
The core contract lives in `contracts/ai-supply-chain.clar` and focuses on individual **shipments**.

### Key roles
- **Buyer** – pays for goods, locks funds in escrow.
- **Supplier** – ships the goods and expects payment on successful delivery.
- **Carrier / logistics partner** – physically moves the goods.
- **Oracle** – off-chain connector that receives IoT + AI insights and pushes status updates on-chain.
- **Admin** – contract owner who can maintain the list of trusted oracles.

### Data structures
For each shipment we store:
- `id` – unique shipment identifier (`uint`).
- `buyer`, `supplier`, `carrier`, `oracle` – principals representing parties.
- `escrow-amount` – STX locked by the buyer.
- `released-amount` – how much STX has been paid out.
- `penalty-amount` – amount reserved as a penalty or partial refund.
- `status` – a small enum representing the shipment lifecycle:
  - `STATUS-OPEN` – created, in transit.
  - `STATUS-ONTIME` – arrived on time and in good condition.
  - `STATUS-DELAYED` – late delivery detected by AI.
  - `STATUS-QUALITY-ISSUE` – temperature/quality problem detected.
  - `STATUS-ESCALATED` – escalated to human ops for a decision.
  - `STATUS-FINAL` – closed; funds have been handled.

All shipments are stored in a `define-map shipments` keyed by `id`.

### Security & control
- An **admin variable** tracks who controls oracle registration.
- A **list of allowed oracle principals** defines who is trusted to push status updates. This lets an enterprise plug in multiple AI/IoT providers while keeping them permissioned.

## 3. Core workflows

### 3.1 Create shipment (escrow funding)
Function: `create-shipment` (public)

Flow:
1. The **buyer** calls `create-shipment` with:
   - `id` – new shipment ID.
   - `supplier`, `carrier`, `oracle` – counterparties.
   - `escrow-amount` – how many STX to lock.
2. The contract:
   - Checks that `escrow-amount` is non-zero.
   - Ensures the `id` is not already used.
   - Transfers STX from `buyer` to the contract (`stx-transfer?`).
   - Stores a new shipment with `STATUS-OPEN` and `released-amount = 0`.

Interpretation: the buyer has now pre-funded this shipment. Everyone can see there is money on-chain waiting to be released when conditions are satisfied.

### 3.2 AI + IoT oracle updates status
Function: `update-status` (public)

This is where **AI and IoT** come in.

1. Off-chain:
   - IoT sensors stream data (GPS, temperature, etc.).
   - An AI/ML pipeline scores risk: on-time, risk of spoilage, suspicious idle time, etc.
2. The oracle component summarizes that insight into a discrete on-chain signal:
   - `STATUS-ONTIME` if everything looks good.
   - `STATUS-DELAYED` if ETA is missed.
   - `STATUS-QUALITY-ISSUE` if sensor anomalies suggest damage.
   - `STATUS-ESCALATED` if the AI is uncertain and a human should decide.
3. On-chain:
   - Only the **configured oracle principal** is allowed to call `update-status` for that shipment.
   - The contract verifies the shipment exists and is not already `STATUS-FINAL`.
   - It validates that the new status is one of the supported enums.
   - It stores the new `status` and an optional `penalty-amount` proposed by the oracle.

This is the bridge where **complex off-chain logic** (AI, composite IoT data, external signals) drives deterministic on-chain behavior.

### 3.3 Finalize shipment: payouts and penalties
Function: `finalize-shipment` (public)

Once the shipment is in a terminal state (not `STATUS-OPEN`), anybody can call `finalize-shipment` to settle funds.

The contract reads:
- `status`
- `escrow-amount`
- `penalty-amount`

Then it computes:
- **Payout to supplier**:
  - If `STATUS-ONTIME` or `STATUS-ESCALATED`: supplier gets the full `escrow-amount`.
  - If `STATUS-DELAYED` or `STATUS-QUALITY-ISSUE`: supplier payout is reduced by `penalty-amount` (down to zero).
- **Refund to buyer**:
  - For penalties, the buyer is refunded up to the penalty amount, while never exceeding the escrow.

Transfers:
- STX is sent from the contract to the supplier (payout) and possibly back to the buyer (refund).
- The shipment `status` is set to `STATUS-FINAL` and `released-amount` is recorded.

This gives you **automatic enforcement** of SLA-like terms: on-time + good quality yields full payment; quality issues or delays can trigger automatic reductions and refunds.

## 4. Admin & oracle management

Two admin-level functions keep this system governed:

- `set-admin(new-admin)` – lets the current admin hand control to another address.
- `add-oracle(oracle)` – appends a new oracle principal to the trusted list; these oracles can be assigned per-shipment.

An enterprise could use this to:
- Onboard multiple logistics data providers.
- Rotate keys if an oracle key is compromised.
- Delegate control to a DAO or multi-sig later.

## 5. Read-only views
To keep dashboards and UIs simple, the contract provides helper functions:
- `get-shipment(id)` – returns all key fields for a given shipment.
- `get-admin()` – returns the current admin.
- `get-oracles()` – returns the list of allowed oracles.

A front-end or analytics service can poll or index these views to build:
- Real-time shipment boards.
- SLA / penalty analytics.
- Compliance and audit reports.

## 6. Testing the protocol
The `tests/ai-supply-chain.test.ts` file (Clarinet + Vitest style) illustrates typical scenarios:
- **Escrow creation** – buyer successfully opens a shipment and funds escrow.
- **Status updates** – oracle marks a shipment as delayed with a penalty.
- **Finalization** – shipment is finalized, and the contract returns an `ok` result when funds are distributed.

These tests are intentionally non-trivial: they cover multi-step flows rather than a single read-only getter.

## 7. Why this is “cool” for enterprises

- **End-to-end transparency** – everyone sees the same, immutable shipment + payment state.
- **Automated compliance** – once SLAs and penalty logic are encoded, they execute exactly as written.
- **AI-driven decisions** – the heavy analytics stay off-chain, but their outcomes directly control real money flows.
- **Reduced disputes and fraud** – clear rules plus sensor evidence reduce “he said, she said” moments.
- **Composable** – additional contracts (insurance, financing, carbon tracking) can plug into the same shipment IDs and statuses.

In under five minutes, a stakeholder can understand: there is a **single on-chain escrow and settlement layer** for shipments, informed by powerful **off-chain AI and IoT data**, turning today’s slow, opaque logistics into a fast, programmable, and auditable system.
