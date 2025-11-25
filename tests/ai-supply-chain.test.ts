import { Clarinet, Tx, Chain, Account } from "@hirosystems/clarinet-sdk";
import { describe, it, expect } from "vitest";

describe("AI-powered dynamic supply chain", () => {
  Clarinet.test("buyer can create a shipment with escrow", (chain: Chain, accounts: Map<string, Account>) => {
    const buyer = accounts.get("wallet_1")!;
    const supplier = accounts.get("wallet_2")!;
    const carrier = accounts.get("wallet_3")!;
    const oracle = accounts.get("wallet_4")!;

    const block = chain.mineBlock([
      Tx.contractCall(
        "ai-supply-chain",
        "create-shipment",
        ["u1", `'${supplier.address}`, `'${carrier.address}`, `'${oracle.address}`, "u1000"],
        buyer.address,
      ),
    ]);

    block.receipts[0].result.expectOk().expectUint(1);
  });

  Clarinet.test("oracle can update shipment status and penalties", (chain: Chain, accounts: Map<string, Account>) => {
    const buyer = accounts.get("wallet_1")!;
    const supplier = accounts.get("wallet_2")!;
    const carrier = accounts.get("wallet_3")!;
    const oracle = accounts.get("wallet_4")!;

    chain.mineBlock([
      Tx.contractCall(
        "ai-supply-chain",
        "create-shipment",
        ["u2", `'${supplier.address}`, `'${carrier.address}`, `'${oracle.address}`, "u500"],
        buyer.address,
      ),
    ]);

    const block = chain.mineBlock([
      Tx.contractCall(
        "ai-supply-chain",
        "update-status",
        ["u2", "u2", "u100"],
        oracle.address,
      ),
    ]);

    block.receipts[0].result.expectOk().expectBool(true);
  });

  Clarinet.test("finalization releases funds or applies penalty", (chain: Chain, accounts: Map<string, Account>) => {
    const buyer = accounts.get("wallet_1")!;
    const supplier = accounts.get("wallet_2")!;
    const carrier = accounts.get("wallet_3")!;
    const oracle = accounts.get("wallet_4")!;

    chain.mineBlock([
      Tx.contractCall(
        "ai-supply-chain",
        "create-shipment",
        ["u3", `'${supplier.address}`, `'${carrier.address}`, `'${oracle.address}`, "u1000"],
        buyer.address,
      ),
      Tx.contractCall(
        "ai-supply-chain",
        "update-status",
        ["u3", "u1", "u0"],
        oracle.address,
      ),
    ]);

    const block = chain.mineBlock([
      Tx.contractCall(
        "ai-supply-chain",
        "finalize-shipment",
        ["u3"],
        buyer.address,
      ),
    ]);

    block.receipts[0].result.expectOk();
  });
});
