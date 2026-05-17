#!/usr/bin/env bun

import * as Data from "@blaze-cardano/data";
import {
  Core,
  makeValue,
} from "@blaze-cardano/sdk";
import { select } from "@inquirer/prompts";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

import { VendorDatum } from "../contracts/treasury-contracts/offchain/src/generated-types/contracts.ts";
import { toPermission } from "../contracts/treasury-contracts/offchain/src/metadata/types/permission.ts";
import {
  constructScriptsFromBytes,
} from "../contracts/treasury-contracts/offchain/src/shared/index.ts";
import { Vendor } from "../contracts/treasury-contracts/offchain/src/index.ts";
import {
  getBlazeInstance,
  getSigners,
  transactionDialog,
} from "../contracts/treasury-contracts/offchain/cli/shared.ts";

const REPO_ROOT = dirname(dirname(fileURLToPath(import.meta.url)));
const INSTANCE_ID =
  process.env.INSTANCE_ID ??
  "d161c89f1123fac8043df44aeec0ca36b2a76e84df47592fe92980ac";
const INSTANCE_METADATA_FILE =
  process.env.INSTANCE_METADATA_FILE ??
  join(REPO_ROOT, "metadata", "offchain-metadata.json");

const TX_AUTHOR_HASH =
  process.env.TX_AUTHOR_HASH ??
  process.env.BLINK_LABS_KEYHASH ??
  "058a5ab0c66647dcce82d7244f80bfea41ba76c7c9ccaf86a41b00fe";
const USDCX_POLICY_ID =
  process.env.USDCX_POLICY_ID ??
  "1f3aec8bfe7ea4fe14c5f121e2a92e301afe414147860d557cac7e34";
const USDCX_ASSET_NAME = process.env.USDCX_ASSET_NAME ?? "5553444378";
const USDCX_ASSET_ID = USDCX_POLICY_ID + USDCX_ASSET_NAME;

const USDCX_DESTINATION =
  process.env.USDCX_DESTINATION ??
  "addr1q8g9808jhwhqjp3ylqgdpzzuur4u53n5zv4ahadskq6djd3lwzwsdphplcdpzla0vnksx0vd2xk70ykyfl3fmuwxr4vqv7tkrw";
const ADA_DESTINATION =
  process.env.ADA_DESTINATION ??
  "addr1qyzc5k4sceny0hxwsttjgnuqhl4yrwnkclyuetux5sdsplh9r9z8yaghysf05atjyv79t73lercjdqnejetxm307m49qsugwpk";

type Milestone = {
  identifier: string;
  label: string;
  date: string;
  usdcx?: bigint;
  lovelace?: bigint;
};

const MILESTONES: Milestone[] = [
  { identifier: "M-0", label: "Bootstrap", usdcx: 225_000_000_000n, date: "2026-05-18T00:00:00Z" },
  { identifier: "M-1", label: "Infra May", usdcx: 4_166_666_667n, date: "2026-05-31T00:00:00Z" },
  { identifier: "M-2", label: "Q2 Testnet", usdcx: 225_000_000_000n, lovelace: 92_500_000_000n, date: "2026-06-30T00:00:00Z" },
  { identifier: "M-3", label: "Infra June", usdcx: 4_166_666_667n, date: "2026-06-30T00:00:00Z" },
  { identifier: "M-4", label: "Infra July", usdcx: 4_166_666_667n, date: "2026-07-31T00:00:00Z" },
  { identifier: "M-5", label: "Infra August", usdcx: 4_166_666_667n, date: "2026-08-31T00:00:00Z" },
  { identifier: "M-6", label: "Q3 Storage", usdcx: 225_000_000_000n, lovelace: 92_500_000_000n, date: "2026-09-30T00:00:00Z" },
  { identifier: "M-7", label: "Infra September", usdcx: 4_166_666_667n, date: "2026-09-30T00:00:00Z" },
  { identifier: "M-8", label: "Infra October", usdcx: 4_166_666_667n, date: "2026-10-31T00:00:00Z" },
  { identifier: "M-9", label: "Infra November", usdcx: 4_166_666_667n, date: "2026-11-30T00:00:00Z" },
  { identifier: "M-10", label: "Audit", usdcx: 500_000_000_000n, date: "2026-06-30T00:00:00Z" },
  { identifier: "M-11", label: "Q4 Leios", usdcx: 225_000_000_000n, lovelace: 92_500_000_000n, date: "2026-12-31T00:00:00Z" },
  { identifier: "M-12", label: "Infra December", usdcx: 4_166_666_667n, date: "2026-12-31T00:00:00Z" },
  { identifier: "M-13", label: "Q1 Mainnet", usdcx: 95_000_000_000n, lovelace: 92_500_000_000n, date: "2027-01-31T00:00:00Z" },
];

function loadInstance() {
  const all = JSON.parse(readFileSync(INSTANCE_METADATA_FILE, "utf8"));
  const instance = all[INSTANCE_ID];
  if (!instance) {
    throw new Error(`No instance ${INSTANCE_ID} in ${INSTANCE_METADATA_FILE}`);
  }
  return instance;
}

function loadConfigsAndScripts(blaze: Awaited<ReturnType<typeof getBlazeInstance>>) {
  const instance = loadInstance();
  const scripts = constructScriptsFromBytes(
    instance.scripts.treasuryScript.network,
    instance.scripts.treasuryScript.config,
    instance.scripts.treasuryScript.script,
    instance.scripts.vendorScript.config,
    instance.scripts.vendorScript.script,
    instance.scripts.treasuryScript.scriptRef ?? undefined,
    instance.scripts.vendorScript.scriptRef ?? undefined,
  );
  return {
    configs: {
      treasury: scripts.treasuryScript.config,
      vendor: scripts.vendorScript.config,
    },
    scripts,
  };
}

async function resolveTxIn(
  blaze: Awaited<ReturnType<typeof getBlazeInstance>>,
  txIn: string,
) {
  const [txId, index] = txIn.split("#");
  if (!txId || index === undefined) {
    throw new Error(`Invalid tx-in ${txIn}; expected txId#index`);
  }
  const [resolved] = await blaze.provider.resolveUnspentOutputs([
    new Core.TransactionInput(Core.TransactionId(txId), BigInt(index)),
  ]);
  if (!resolved) {
    throw new Error(`Could not resolve ${txIn}`);
  }
  return resolved;
}

function valueParts(value: Record<string, Record<string, bigint>>) {
  const lovelace = value[""]?.[""] ?? 0n;
  const usdcx = value[USDCX_POLICY_ID]?.[USDCX_ASSET_NAME] ?? 0n;
  const supportedPolicies = new Set(["", USDCX_POLICY_ID]);
  for (const [policy, assets] of Object.entries(value)) {
    if (!supportedPolicies.has(policy)) {
      throw new Error(`Unsupported payout policy ${policy}`);
    }
    for (const assetName of Object.keys(assets)) {
      if (policy === "" && assetName !== "") {
        throw new Error(`Unsupported ADA asset name ${assetName}`);
      }
      if (policy === USDCX_POLICY_ID && assetName !== USDCX_ASSET_NAME) {
        throw new Error(`Unsupported asset ${policy}.${assetName}`);
      }
    }
  }
  return { lovelace, usdcx };
}

function payoutSummary(lovelace: bigint, usdcx: bigint) {
  return `${Number(lovelace) / 1_000_000} ADA, ${Number(usdcx) / 1_000_000} USDCx`;
}

function matchingMilestone(index: number) {
  return MILESTONES[index] ?? {
    identifier: `vendor-payout-${index}`,
    label: `Vendor payout ${index}`,
  };
}

async function selectVendorInput(
  blaze: Awaited<ReturnType<typeof getBlazeInstance>>,
  vendorAddress: any,
  now: Date,
) {
  if (process.env.VENDOR_TX_IN) {
    return await resolveTxIn(blaze, process.env.VENDOR_TX_IN);
  }

  const utxos = await blaze.provider.getUnspentOutputs(vendorAddress);
  const choices = [];
  for (const [inputIndex, utxo] of utxos.entries()) {
    const inlineDatum = utxo.output().datum()?.asInlineData();
    if (!inlineDatum) continue;
    const datum = Data.parse(VendorDatum, inlineDatum);
    let lovelace = 0n;
    let usdcx = 0n;
    let count = 0;
    for (const payout of datum.payouts) {
      if (payout.status !== "Active" || BigInt(now.valueOf()) <= payout.maturation) {
        continue;
      }
      const parts = valueParts(payout.value);
      lovelace += parts.lovelace;
      usdcx += parts.usdcx;
      count++;
    }
    if (count > 0) {
      choices.push({
        name: `${utxo.input().transactionId().toString()}#${utxo.input().index().toString()} (${count} matured payouts: ${payoutSummary(lovelace, usdcx)})`,
        value: inputIndex,
      });
    }
  }

  if (choices.length === 0) {
    throw new Error(`No matured vendor payouts found as of ${now.toISOString()}`);
  }

  const selectedIndex = await select({
    message: "Select the vendor UTxO to claim",
    choices,
  });
  return utxos[selectedIndex];
}

async function main() {
  const blaze = await getBlazeInstance();
  const { configs, scripts } = loadConfigsAndScripts(blaze);
  const now = process.env.CLAIM_AT
    ? new Date(process.env.CLAIM_AT)
    : new Date();
  if (Number.isNaN(now.valueOf())) {
    throw new Error(`Invalid CLAIM_AT value: ${process.env.CLAIM_AT}`);
  }

  const input = await selectVendorInput(
    blaze,
    scripts.vendorScript.scriptAddress,
    now,
  );

  const inlineDatum = input.output().datum()?.asInlineData();
  if (!inlineDatum) {
    throw new Error("Selected vendor UTxO has no inline datum");
  }
  const datum = Data.parse(VendorDatum, inlineDatum);

  let lovelace = 0n;
  let usdcx = 0n;
  const milestones: Record<string, { comment: string }> = {};

  datum.payouts.forEach((payout, index) => {
    if (payout.status !== "Active" || BigInt(now.valueOf()) <= payout.maturation) {
      return;
    }
    const parts = valueParts(payout.value);
    lovelace += parts.lovelace;
    usdcx += parts.usdcx;
    const milestone = matchingMilestone(index);
    milestones[milestone.identifier] = {
      comment: `Claim ${milestone.label} matured at ${new Date(Number(payout.maturation)).toISOString()}.`,
    };
  });

  if (lovelace === 0n && usdcx === 0n) {
    throw new Error("Selected vendor UTxO has no claimable ADA or USDCx");
  }

  const destinations = [];
  if (usdcx > 0n) {
    destinations.push({
      address: Core.Address.fromBech32(USDCX_DESTINATION),
      amount: makeValue(0n, [USDCX_ASSET_ID, usdcx]),
    });
  }
  if (lovelace > 0n) {
    destinations.push({
      address: Core.Address.fromBech32(ADA_DESTINATION),
      amount: makeValue(lovelace),
    });
  }

  console.log(`Claiming as of:      ${now.toISOString()}`);
  console.log(`Claim amount:        ${payoutSummary(lovelace, usdcx)}`);
  console.log(`USDCx destination:   ${USDCX_DESTINATION}`);
  console.log(`ADA destination:     ${ADA_DESTINATION}`);

  const signers = await getSigners(toPermission(datum.vendor));
  signers.add(TX_AUTHOR_HASH as never);

  const txMetadata = {
    "@context":
      "https://raw.githubusercontent.com/SundaeSwap-finance/treasury-contracts/refs/heads/main/offchain/src/metadata/context.jsonld",
    hashAlgorithm: "blake2b-256" as const,
    txAuthor: TX_AUTHOR_HASH,
    instance: INSTANCE_ID,
    body: {
      event: "withdraw",
      milestones,
    },
    comment:
      "Claim matured Blink Labs Dingo 2026 vendor milestones to the configured ADA and USDCx destinations.",
  };

  const tx = await (
    await Vendor.withdraw({
      configsOrScripts: { configs, scripts },
      blaze,
      now,
      inputs: [input],
      destinations,
      signers: [...signers.values()],
      metadata: txMetadata,
    })
  ).complete();

  await transactionDialog(blaze.provider.network, tx.toCbor(), false);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
