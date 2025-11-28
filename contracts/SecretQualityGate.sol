// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * SecretQualityGate (Zama FHEVM)
 *
 * Private raw-material quality check:
 *  - Owner uploads encrypted thresholds (hidden rules).
 *  - Supplier submits encrypted batch metrics.
 *  - Contract stores an encrypted verdict (ebool): 1 = ACCEPT, 0 = REJECT.
 *
 * Metrics (uint16 each):
 *   impurityPPM   — <= maxImpurity
 *   moistureBP    — <= maxMoisture
 *   density       — >= minDensity
 *   hardness      — >= minHardness
 *
 * Rules (encrypted on-chain): maxImpurity, maxMoisture, minDensity, minHardness (euint16)
 * ACL: result decryptable by msg.sender and by qualityApp.
 */

import {
    FHE,
    ebool,
    euint16,
    externalEuint16
} from "@fhevm/solidity/lib/FHE.sol";
import { ZamaEthereumConfig } from "@fhevm/solidity/config/ZamaConfig.sol";

contract SecretQualityGate is ZamaEthereumConfig {
    /* ───────── Admin / Ownership ───────── */

    address public owner;
    address public qualityApp;

    modifier onlyOwner() { require(msg.sender == owner, "Not owner"); _; }

    constructor() {
        owner = msg.sender;
        qualityApp = msg.sender;

        // Neutral defaults (accept-all) until owner sets encrypted rules
        _maxImpurity = FHE.asEuint16(type(uint16).max);
        _maxMoisture = FHE.asEuint16(type(uint16).max);
        _minDensity  = FHE.asEuint16(0);
        _minHardness = FHE.asEuint16(0);

        FHE.allowThis(_maxImpurity);
        FHE.allowThis(_maxMoisture);
        FHE.allowThis(_minDensity);
        FHE.allowThis(_minHardness);
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Zero owner");
        owner = newOwner;
    }

    function setQualityApp(address newApp) external onlyOwner {
        require(newApp != address(0), "Zero app");
        qualityApp = newApp;
    }

    function version() external pure returns (string memory) {
        return "SecretQualityGate/1.0.1";
    }

    /* ───────── Hidden Rule Storage ───────── */

    euint16 private _maxImpurity;
    euint16 private _maxMoisture;
    euint16 private _minDensity;
    euint16 private _minHardness;

    event RulesUpdated(bytes32 maxImpurityH, bytes32 maxMoistureH, bytes32 minDensityH, bytes32 minHardnessH);

    /// Set encrypted thresholds in one batch (single proof)
    function setRulesEncrypted(
        externalEuint16[4] calldata ruleExt,
        bytes calldata proof
    ) external onlyOwner {
        _maxImpurity = FHE.fromExternal(ruleExt[0], proof);
        _maxMoisture = FHE.fromExternal(ruleExt[1], proof);
        _minDensity  = FHE.fromExternal(ruleExt[2], proof);
        _minHardness = FHE.fromExternal(ruleExt[3], proof);

        FHE.allowThis(_maxImpurity);
        FHE.allowThis(_maxMoisture);
        FHE.allowThis(_minDensity);
        FHE.allowThis(_minHardness);

        emit RulesUpdated(
            FHE.toBytes32(_maxImpurity),
            FHE.toBytes32(_maxMoisture),
            FHE.toBytes32(_minDensity),
            FHE.toBytes32(_minHardness)
        );
    }

    function makeRulesPublic() external onlyOwner {
        FHE.makePubliclyDecryptable(_maxImpurity);
        FHE.makePubliclyDecryptable(_maxMoisture);
        FHE.makePubliclyDecryptable(_minDensity);
        FHE.makePubliclyDecryptable(_minHardness);
    }

    function getRuleHandles()
        external
        view
        returns (bytes32 maxImpurityH, bytes32 maxMoistureH, bytes32 minDensityH, bytes32 minHardnessH)
    {
        return (
            FHE.toBytes32(_maxImpurity),
            FHE.toBytes32(_maxMoisture),
            FHE.toBytes32(_minDensity),
            FHE.toBytes32(_minHardness)
        );
    }

    /* ───────── Batch Results ───────── */

    struct BatchVerdict {
        bool exists;
        ebool passCt; // 1 = ACCEPT, 0 = REJECT
    }

    mapping(bytes32 => BatchVerdict) private _verdict; // key: batchId

    event BatchChecked(bytes32 indexed batchId, address indexed submitter, bytes32 verdictHandle);

    /* ───────── Internal: compute verdict (to reduce stack) ───────── */

    function _computeAccept(
        euint16 impurity,
        euint16 moisture,
        euint16 density,
        euint16 hardness
    ) internal returns (ebool) {
        // Conditions
        ebool cImp = FHE.le(impurity, _maxImpurity);
        ebool cMoi = FHE.le(moisture, _maxMoisture);
        ebool cDen = FHE.ge(density,  _minDensity);
        ebool cHar = FHE.ge(hardness, _minHardness);

        // AND all
        ebool and1 = FHE.and(cImp, cMoi);
        ebool and2 = FHE.and(cDen, cHar);
        return FHE.and(and1, and2);
    }

    /* ───────── Core Checking ───────── */

    /**
     * Submit encrypted metrics and store encrypted verdict.
     * metricsExt = [impurityPPM, moistureBP, density, hardness] (uint16 each, all from the SAME proof batch)
     */
    function submitBatchAndCheck(
        bytes32 batchId,
        externalEuint16[4] calldata metricsExt,
        bytes calldata proof
    ) external returns (ebool verdictCt) {
        require(!_verdict[batchId].exists, "Batch exists");

        // Deserialize (shared proof)
        euint16 imp = FHE.fromExternal(metricsExt[0], proof);
        euint16 moi = FHE.fromExternal(metricsExt[1], proof);
        euint16 den = FHE.fromExternal(metricsExt[2], proof);
        euint16 har = FHE.fromExternal(metricsExt[3], proof);

        // Compute verdict in a separate scope to shorten local lifetimes
        {
            ebool accept = _computeAccept(imp, moi, den, har);

            // ACL
            FHE.allow(accept, msg.sender);
            FHE.allow(accept, qualityApp);
            FHE.allowThis(accept);

            // Store without local storage reference to avoid stack pressure
            _verdict[batchId].exists = true;
            _verdict[batchId].passCt = accept;

            emit BatchChecked(batchId, msg.sender, FHE.toBytes32(accept));
            return accept;
        }
    }

    /* ───────── Read helpers ───────── */

    function getVerdictHandle(bytes32 batchId) external view returns (bytes32) {
        BatchVerdict storage v = _verdict[batchId];
        if (!v.exists) return bytes32(0);
        return FHE.toBytes32(v.passCt);
    }

    function makeVerdictPublic(bytes32 batchId) external onlyOwner {
        BatchVerdict storage v = _verdict[batchId];
        require(v.exists, "No batch");
        FHE.makePubliclyDecryptable(v.passCt);
    }
}
