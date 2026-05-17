#!/usr/bin/env bun

import * as Data from "../contracts/treasury-contracts/offchain/node_modules/@blaze-cardano/data";
import {
  Core,
  makeValue,
  Value as SdkValue,
} from "../contracts/treasury-contracts/offchain/node_modules/@blaze-cardano/sdk";
import { select } from "../contracts/treasury-contracts/offchain/node_modules/@inquirer/prompts";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

import {
  TreasurySpendRedeemer,
  VendorDatum,
} from "../contracts/treasury-contracts/offchain/src/generated-types/contracts.ts";
import { toTxMetadata } from "../contracts/treasury-contracts/offchain/src/metadata/shared.ts";
import {
  toMultisig,
  type TPermissionMetadata,
} from "../contracts/treasury-contracts/offchain/src/metadata/types/permission.ts";
import {
  constructScriptsFromBytes,
  coreValueToContractsValue,
} from "../contracts/treasury-contracts/offchain/src/shared/index.ts";
import {
  getActualPermission,
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

const BLINK_LABS_KEYHASH =
  process.env.BLINK_LABS_KEYHASH ??
  "058a5ab0c66647dcce82d7244f80bfea41ba76c7c9ccaf86a41b00fe";
const TX_AUTHOR_HASH = process.env.TX_AUTHOR_HASH ?? BLINK_LABS_KEYHASH;

const USDCX_POLICY_ID =
  process.env.USDCX_POLICY_ID ??
  "1f3aec8bfe7ea4fe14c5f121e2a92e301afe414147860d557cac7e34";
const USDCX_ASSET_NAME = process.env.USDCX_ASSET_NAME ?? "5553444378";
const USDCX_ASSET_ID = USDCX_POLICY_ID + USDCX_ASSET_NAME;
const REGISTRY_ASSET_NAME = "5245474953545259";

type Milestone = {
  identifier: string;
  label: string;
  description: string;
  date: string;
  usdcx?: bigint;
  lovelace?: bigint;
  status?: "Active" | "Paused";
};

// Dates are the user's UTC schedule encoded explicitly.
const MILESTONES: Milestone[] = [
  {
    identifier: "M-0",
    label: "Bootstrap",
    description: "Bootstrap funding for Blink Labs Dingo development.",
    usdcx: 225_000_000_000n,
    date: "2026-05-18T00:00:00Z",
  },
  {
    identifier: "M-1",
    label: "Infra May",
    description: "May infrastructure funding.",
    usdcx: 4_166_666_667n,
    date: "2026-05-31T00:00:00Z",
  },
  {
    identifier: "M-2",
    label: "Q2 Testnet",
    description: "Q2 testnet block production and Leios prototype milestone.",
    usdcx: 225_000_000_000n,
    lovelace: 92_500_000_000n,
    date: "2026-06-30T00:00:00Z",
  },
  {
    identifier: "M-3",
    label: "Infra June",
    description: "June infrastructure funding.",
    usdcx: 4_166_666_667n,
    date: "2026-06-30T00:00:00Z",
  },
  {
    identifier: "M-4",
    label: "Infra July",
    description: "July infrastructure funding.",
    usdcx: 4_166_666_667n,
    date: "2026-07-31T00:00:00Z",
  },
  {
    identifier: "M-5",
    label: "Infra August",
    description: "August infrastructure funding.",
    usdcx: 4_166_666_667n,
    date: "2026-08-31T00:00:00Z",
  },
  {
    identifier: "M-6",
    label: "Q3 Storage",
    description: "Q3 operational hardening and storage scalability milestone.",
    usdcx: 225_000_000_000n,
    lovelace: 92_500_000_000n,
    date: "2026-09-30T00:00:00Z",
  },
  {
    identifier: "M-7",
    label: "Infra September",
    description: "September infrastructure funding.",
    usdcx: 4_166_666_667n,
    date: "2026-09-30T00:00:00Z",
  },
  {
    identifier: "M-8",
    label: "Infra October",
    description: "October infrastructure funding.",
    usdcx: 4_166_666_667n,
    date: "2026-10-31T00:00:00Z",
  },
  {
    identifier: "M-9",
    label: "Infra November",
    description: "November infrastructure funding.",
    usdcx: 4_166_666_667n,
    date: "2026-11-30T00:00:00Z",
  },
  {
    identifier: "M-10",
    label: "Audit",
    description: "Security audit funding.",
    usdcx: 500_000_000_000n,
    date: "2026-06-30T00:00:00Z",
    status: "Paused",
  },
  {
    identifier: "M-11",
    label: "Q4 Leios",
    description: "Q4 Dijkstra readiness and Leios integration milestone.",
    usdcx: 225_000_000_000n,
    lovelace: 92_500_000_000n,
    date: "2026-12-31T00:00:00Z",
  },
  {
    identifier: "M-12",
    label: "Infra December",
    description: "December infrastructure funding.",
    usdcx: 4_166_666_667n,
    date: "2026-12-31T00:00:00Z",
  },
  {
    identifier: "M-13",
    label: "Q1 Mainnet",
    description: "Q1 2027 mainnet readiness, audit completion, and ecosystem integration milestone.",
    usdcx: 95_000_000_000n,
    lovelace: 92_500_000_000n,
    date: "2027-01-31T00:00:00Z",
  },
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
    metadata: instance.metadata,
    configs: {
      treasury: scripts.treasuryScript.config,
      vendor: scripts.vendorScript.config,
    },
    scripts,
  };
}

function scheduleValue(milestone: Milestone) {
  const coin = milestone.lovelace ?? 0n;
  if (milestone.usdcx) {
    return makeValue(coin, [USDCX_ASSET_ID, milestone.usdcx]);
  }
  return makeValue(coin);
}

function valueSummary(value: ReturnType<typeof makeValue>): string {
  const coin = value.coin();
  const usdcx = value.multiasset()?.get(Core.AssetId(USDCX_ASSET_ID)) ?? 0n;
  return `${Number(coin) / 1_000_000} ADA, ${Number(usdcx) / 1_000_000} USDCx`;
}

function totals() {
  let lovelace = 0n;
  let usdcx = 0n;
  for (const milestone of MILESTONES) {
    lovelace += milestone.lovelace ?? 0n;
    usdcx += milestone.usdcx ?? 0n;
  }
  return { lovelace, usdcx };
}

async function resolveTxIns(
  blaze: Awaited<ReturnType<typeof getBlazeInstance>>,
  txIns: string[],
) {
  const inputs = txIns.map((txIn) => {
    const [txId, index] = txIn.split("#");
    if (!txId || index === undefined) {
      throw new Error(`Invalid tx-in ${txIn}; expected txId#index`);
    }
    return new Core.TransactionInput(Core.TransactionId(txId), BigInt(index));
  });
  return await blaze.provider.resolveUnspentOutputs(inputs);
}

async function selectTreasuryInputs(
  blaze: Awaited<ReturnType<typeof getBlazeInstance>>,
  treasuryAddress: any,
) {
  if (process.env.TREASURY_TX_INS) {
    return await resolveTxIns(
      blaze,
      process.env.TREASURY_TX_INS.split(/[,\s]+/).filter(Boolean),
    );
  }

  const { lovelace, usdcx } = totals();
  const utxos = await blaze.provider.getUnspentOutputs(treasuryAddress);
  const selected = new Set<number>();
  let haveLovelace = 0n;
  let haveUsdcx = 0n;

  const byUsdcx = utxos
    .map((utxo, index) => ({
      index,
      qty:
        utxo.output().amount().multiasset()?.get(Core.AssetId(USDCX_ASSET_ID)) ??
        0n,
    }))
    .filter((x) => x.qty > 0n)
    .sort((a, b) => Number(b.qty - a.qty));

  for (const candidate of byUsdcx) {
    if (haveUsdcx >= usdcx) break;
    selected.add(candidate.index);
    haveUsdcx += candidate.qty;
    haveLovelace += utxos[candidate.index].output().amount().coin();
  }

  const byAda = utxos
    .map((utxo, index) => ({
      index,
      qty: utxo.output().amount().coin(),
    }))
    .sort((a, b) => Number(b.qty - a.qty));

  for (const candidate of byAda) {
    if (haveLovelace >= lovelace) break;
    if (selected.has(candidate.index)) continue;
    selected.add(candidate.index);
    haveLovelace += candidate.qty;
    haveUsdcx +=
      utxos[candidate.index]
        .output()
        .amount()
        .multiasset()
        ?.get(Core.AssetId(USDCX_ASSET_ID)) ?? 0n;
  }

  if (haveLovelace < lovelace || haveUsdcx < usdcx) {
    throw new Error(
      `Treasury UTxOs do not cover schedule: have ${haveLovelace} lovelace and ${haveUsdcx} USDCx base units, need ${lovelace} and ${usdcx}`,
    );
  }

  const selectedUtxos = [...selected].map((index) => utxos[index]);
  if (process.env.NONINTERACTIVE === "1") {
    return selectedUtxos;
  }

  const answer = await select({
    message: "Use these treasury inputs for the mixed milestone funding transaction?",
    choices: [
      {
        name: selectedUtxos
          .map(
            (utxo) =>
              `${utxo.input().transactionId().toString()}#${utxo.input().index().toString()} (${valueSummary(utxo.output().amount())})`,
          )
          .join(" + "),
        value: "yes",
      },
      { name: "Abort", value: "abort" },
    ],
  });
  if (answer !== "yes") {
    throw new Error("Aborted");
  }
  return selectedUtxos;
}

async function main() {
  const blaze = await getBlazeInstance();
  const { configs, scripts, metadata } = loadConfigsAndScripts(blaze);

  const vendorPermission: TPermissionMetadata = {
    label: "Blink Labs",
    signature: { keyHash: BLINK_LABS_KEYHASH },
  };
  const vendor = toMultisig(vendorPermission);

  const schedule = MILESTONES.map((milestone) => ({
    date: new Date(milestone.date),
    amount: scheduleValue(milestone),
  }));
  const totalPayout = schedule.reduce(
    (acc, item) => SdkValue.merge(acc, item.amount),
    makeValue(0n),
  );

  console.log(`Funding instance: ${INSTANCE_ID}`);
  console.log(`Total payout:     ${valueSummary(totalPayout)}`);
  console.log(`Vendor key hash:  ${BLINK_LABS_KEYHASH}`);

  const treasuryInputs = await selectTreasuryInputs(
    blaze,
    scripts.treasuryScript.scriptAddress,
  );

  const fundPermission = getActualPermission(
    metadata.body.permissions.fund,
    metadata.body.permissions,
  );
  const signers = await getSigners(fundPermission, vendorPermission);
  signers.add(TX_AUTHOR_HASH as never);

  const txMetadata = {
    "@context":
      "https://raw.githubusercontent.com/SundaeSwap-finance/treasury-contracts/refs/heads/main/offchain/src/metadata/context.jsonld",
    hashAlgorithm: "blake2b-256" as const,
    txAuthor: TX_AUTHOR_HASH,
    instance: INSTANCE_ID,
    body: {
      event: "fund",
      identifier: "Dingo-2026-mixed-assets",
      otherIdentifiers: ["Dingo", "Blink Labs Dingo Treasury 2026"],
      label: "Blink Labs Dingo 2026 milestone schedule",
      description:
        "Mixed USDCx and ADA milestone schedule for Blink Labs Dingo development.",
      vendor: { label: "Blink Labs" },
      milestones: MILESTONES.map((milestone) => ({
        identifier: milestone.identifier,
        label: milestone.label,
        description: milestone.description,
        acceptanceCriteria: `Matures at ${milestone.date}; payout ${[
          milestone.usdcx ? `${Number(milestone.usdcx) / 1_000_000} USDCx` : "",
          milestone.lovelace ? `${Number(milestone.lovelace) / 1_000_000} ADA` : "",
        ]
          .filter(Boolean)
          .join(" and ")}.`,
      })),
    },
    comment:
      "Fund Blink Labs Dingo 2026 vendor contract with mixed USDCx and ADA milestones.",
  };

  const registryInput = await blaze.provider.getUnspentOutputByNFT(
    Core.AssetId(configs.treasury.registry_token + REGISTRY_ASSET_NAME),
  );

  const tx = blaze.newTransaction().addReferenceInput(registryInput);
  const now = Date.now();
  const maxHorizonMs =
    blaze.provider.network === Core.NetworkId.Testnet
      ? 6 * 60 * 60 * 1000
      : 36 * 60 * 60 * 1000;
  const validUntilUnix = Math.min(
    Number(configs.treasury.expiration),
    now + maxHorizonMs,
  );
  tx.setValidUntil(Core.Slot(blaze.provider.unixToSlot(validUntilUnix) - 30));

  if (!scripts.treasuryScript.scriptRef) {
    scripts.treasuryScript.scriptRef = await blaze.provider.resolveScriptRef(
      scripts.treasuryScript.script.Script,
    );
  }
  if (scripts.treasuryScript.scriptRef) {
    tx.addReferenceInput(scripts.treasuryScript.scriptRef);
  } else {
    tx.provideScript(scripts.treasuryScript.script.Script);
  }

  const auxData = new Core.AuxiliaryData();
  auxData.setMetadata(toTxMetadata(txMetadata));
  tx.setAuxiliaryData(auxData);

  for (const signer of signers) {
    tx.addRequiredSigner(signer);
  }

  for (const input of treasuryInputs) {
    tx.addInput(
      input,
      Data.serialize(TreasurySpendRedeemer, {
        Fund: { amount: coreValueToContractsValue(totalPayout) },
      }),
    );
  }

  const datum = {
    vendor,
    payouts: schedule.map((item, index) => ({
      maturation: BigInt(item.date.valueOf()),
      value: coreValueToContractsValue(item.amount),
      status: MILESTONES[index].status ?? "Active",
    })),
  };

  tx.lockAssets(
    scripts.vendorScript.scriptAddress,
    totalPayout,
    Data.serialize(VendorDatum, datum),
  );

  const inputValue = treasuryInputs.reduce(
    (acc, input) => SdkValue.merge(acc, input.output().amount()),
    makeValue(0n),
  );
  const remainder = SdkValue.merge(inputValue, SdkValue.negate(totalPayout));
  if (!SdkValue.empty(remainder)) {
    tx.lockAssets(
      scripts.treasuryScript.scriptAddress,
      remainder,
      Data.Void(),
    );
  }

  const complete = await tx.complete();
  await transactionDialog(blaze.provider.network, complete.toCbor(), false);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
