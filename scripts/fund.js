const hre = require("hardhat");

function getArg(name) {
  const idx = process.argv.indexOf(name);
  if (idx === -1) return null;
  return process.argv[idx + 1] || null;
}

async function main() {
  const to = getArg("--to") || process.env.FUND_TO;
  const amountEth = getArg("--amount") || process.env.FUND_AMOUNT || "1";

  if (!to) {
    throw new Error("Missing recipient. Provide --to <address> or set FUND_TO env var.");
  }

  const [sender] = await hre.ethers.getSigners();
  const value = hre.ethers.parseEther(String(amountEth));

  console.log(`Funding ${to} with ${amountEth} ETH from ${sender.address} on ${hre.network.name}...`);

  const tx = await sender.sendTransaction({ to, value });
  console.log("tx:", tx.hash);
  await tx.wait();

  const bal = await hre.ethers.provider.getBalance(to);
  console.log("Recipient balance:", hre.ethers.formatEther(bal), "ETH");
}

main().then(() => process.exit(0)).catch((e) => {
  console.error(e);
  process.exit(1);
});
