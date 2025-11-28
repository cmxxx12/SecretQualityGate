# Quality Vault — Private Raw‑Material QA (Zama FHEVM)

**Quality Vault** is a reference dApp that performs **hidden quality checks** for raw‑material batches using Zama’s **FHEVM**. Thresholds are stored **encrypted** on‑chain; suppliers submit **encrypted metrics**; the contract returns an **encrypted verdict** (ACCEPT / REJECT). Only the submitter (and an optional app address) can decrypt the result via **User Decrypt (EIP‑712)**.

> Frontend file location: **`frontend/public/index.html`**

---

## Components

### Smart Contract — `SecretQualityGate.sol`

* **Hidden thresholds** (all `euint16`):

  * `maxImpurity`, `maxMoisture`, `minDensity`, `minHardness`.
* **Set rules (encrypted)**: `setRulesEncrypted(externalEuint16[4], bytes proof)` — single batched proof.
* **Submit batch**: `submitBatchAndCheck(bytes32 batchId, externalEuint16[4] metrics, bytes proof)` → stores encrypted `ebool` verdict; emits `BatchChecked(batchId, submitter, verdictHandle)`.
* **Read handle**: `getVerdictHandle(bytes32 batchId)`.
* **Make public**: `makeRulesPublic()` and `makeVerdictPublic(batchId)` (optional, for demos/audits).
* Uses only official Zama FHE libs:

  * `import { FHE, ebool, euint16, externalEuint16 } from "@fhevm/solidity/lib/FHE.sol";`
  * `import { SepoliaConfig } from "@fhevm/solidity/config/ZamaConfig.sol";`

### Frontend — `frontend/public/index.html`

* Modern, three‑step **wizard** UX (distinct from other demos):

  1. **Seal Input** — encrypt 4 metrics locally with **Relayer SDK 0.2.0**.
  2. **Dispatch to Chain** — submit to contract; parse `BatchChecked` to get the handle.
  3. **Reveal Locally** — EIP‑712 sign & **userDecrypt** verdict → **ACCEPT**/**REJECT**.
* **Rules Vault** panel for admins:

  * Upload encrypted thresholds (“**Seal Rules**”), **Audit Handles**, **Make Public** (optional).
* **Deep console logs** for each stage (encryption, staticCall, tx, events, EIP‑712, decrypt).
* Depends on:

  * `@zama-fhe/relayer-sdk-js` **0.2.0** (via CDN),
  * `ethers` v6 (via CDN),
  * MetaMask (or any EIP‑1193 provider).

---

## Feature Highlights

* 🔒 **Hidden rules** and **private inputs** — end‑to‑end ciphertext handling.
* 🧮 **On‑chain FHE comparisons** only; no FHE in `view`/`pure`.
* 🔑 **User‑scoped decryption** via EIP‑712; optional public decryption for audits.
* 🧰 **Relayer SDK 0.2.0** primitives used exclusively: `createInstance`, `createEncryptedInput().add16(...)`, `userDecrypt(...)`.
* 🖥️ **Original UI/UX** (tabs, wizard, right activity rail) — not reused from prior projects.

---

## Getting Started

### Prerequisites

* Node.js ≥ 18
* pnpm / npm / yarn
* MetaMask (connected to **Sepolia**)

### Install

```bash
# 1) Install deps for contracts/workspace
pnpm install   # or npm i / yarn

# 2) (If you will compile/deploy) add FHEVM deps
pnpm add -D hardhat hardhat-deploy @nomicfoundation/hardhat-toolbox
pnpm add @fhevm/solidity
```

### Compile & Deploy (Hardhat)

The project includes a universal deploy script (no constructor args). The script auto-picks the latest contract or use env vars.

```bash
# clean and compile
npx hardhat clean
npx hardhat compile

# deploy to sepolia (reads your named accounts from hardhat config)
npx hardhat deploy --network sepolia
```

**Environment (optional)**

* `CONTRACT_NAME` — explicit contract name (e.g., `SecretQualityGate`).
* `CONTRACT_FILE` — path under `contracts/`.
* `CONSTRUCTOR_ARGS` — JSON array, if the target contract needs args (ours doesn’t).
* `WAIT_CONFIRMS` — confirmations to wait.

> If you ever hit “stack too deep”, you can either use the provided refactor (already applied) or enable `viaIR: true` + optimizer in Hardhat config.

### Run the Frontend

The frontend is a single **static** file at `frontend/public/index.html`. You can open it directly or serve locally:

```bash
# simplest: static server from the folder
npx serve frontend/public
# or
npx http-server frontend/public -p 8080
```

Open **[http://localhost:8080](http://localhost:8080)** (or printed URL), click **Connect**, set rules (admin), then submit a batch (supplier).

---

## Usage Walkthrough

### 1) Admin seals thresholds

1. Open **Rules Vault** tab.
2. Enter `maxImpurity`, `maxMoisture`, `minDensity`, `minHardness` (all `0..65535`).
3. Click **Seal Rules** → values encrypted locally → single batched proof → `setRulesEncrypted` tx.
4. (Optional) **Audit Handles** to view `bytes32` handles or **Make Public** for demo.

### 2) Supplier submits encrypted batch

1. Switch to **Quality Lab** tab.
2. Enter metrics: `impurityPPM`, `moistureBP`, `density`, `hardness`.
3. (Optional) Set a **Batch Salt** (used to derive `batchId = keccak256(salt)`). If empty, the app generates one.
4. Click **Seal Input** → encrypt metrics (shows handle previews + proof size).
5. Click **Dispatch to Chain** → send tx → the UI parses **BatchChecked** and shows the `verdictHandle`.

### 3) Reveal verdict locally

* Click **Reveal Locally** → the app generates a keypair, creates an EIP‑712 request, asks your wallet to sign, and calls **`userDecrypt`**. The result appears as **ACCEPT** / **REJECT**.
* You can later **Recover by Batch ID** to fetch the stored handle and decrypt again.

---

## Development Notes

* **Do not** use deprecated packages (e.g., `@fhevm-js/relayer` or `@fhenixprotocol/...`).
* Use only: `@fhevm/solidity/lib/FHE.sol` and **Relayer SDK JS 0.2.0** (`https://cdn.zama.ai/relayer-sdk-js/0.2.0/relayer-sdk-js.js`).
* Avoid FHE operations in `view`/`pure`. All FHE ops happen in state‑changing functions.
* `euint256`/`eaddress` do **not** support arithmetic; this app uses `euint16` for all comparisons.
* Access control: `FHE.allow`, `FHE.allowThis`, optional `FHE.makePubliclyDecryptable`.

---

## License

MIT — see `LICENSE` (or choose your preferred OSS license).
