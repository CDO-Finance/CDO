const hre = require("hardhat");

async function main() {
  const CodexToken = await ethers.getContractFactory("CodexToken")
  const FairLaunch = await ethers.getContractFactory("FairLaunch")
  const TokenTimelock = await ethers.getContractFactory("TokenTimelock")

  const DEVELOPER_ADDRESS = '';
  const MINTED_TOKENS_RECEIVER = '';
  const STAKING_TOKEN_ADDR = '';

  const CODEX_REWARD_PER_BLOCK = ethers.utils.parseEther('20');
  const ALLOC_POINT = '300';
  const BONUS_MULTIPLIER = 7;
  const BONUS_END_BLOCK = '7216410';
  const BONUS_LOCK_BPS = '7000';
  const START_BLOCK = '6823000';
  const CODEX_START_RELEASE = '11997210';
  const CODEX_END_RELEASE = '17181210';

  console.log("Starting the deployment ...");

  const codexToken = await CodexToken.deploy(MINTED_TOKENS_RECEIVER, CODEX_START_RELEASE, CODEX_END_RELEASE)
  await codexToken.deployed()

  const fairLaunch = await FairLaunch(
    codexToken.address,
    DEVELOPER_ADDRESS,
    CODEX_REWARD_PER_BLOCK,
    START_BLOCK,
    BONUS_LOCK_BPS,
    BONUS_END_BLOCK
  )
  await fairLaunch.deployed()

  const timelock = await TokenTimelock(
    codexToken.address,
    DEVELOPER_ADDRESS,
    7776000 // 3 months
  )
  await timelock.deployed()


  console.log("1) Transferring ownership of CodexToken from deployer to FairLaunch");
  await codexToken.transferOwnership(fairLaunch.address);

  console.log(`2) Set Fair Launch bonus to BONUS_MULTIPLIER: "${BONUS_MULTIPLIER}", BONUS_END_BLOCK: "${BONUS_END_BLOCK}", LOCK_BPS: ${BONUS_LOCK_BPS}`)
  await fairLaunch.setBonus(BONUS_MULTIPLIER, BONUS_END_BLOCK, BONUS_LOCK_BPS)

  console.log("3) Adding new pool to fair launch");
  await fairLaunch.addPool(ALLOC_POINT, STAKING_TOKEN_ADDR, false);

  console.log("4) Transfer tokens to lock contract");
  await codexToken.transfer(timelock.address, '2700000000000000000000000');

  console.log("Contracts deployed! ✅");
  console.log("-----------------")
  console.log("CODEX token address:", codexToken.address);
  console.log("Fair launch address:", fairLaunch.address);
  console.log("Timelock address:", timelock.address);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
