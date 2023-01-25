import type { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { task } from "hardhat/config";

import type { EventStaking } from "../../types/EventStaking";
import type { EventStaking__factory } from "../../types/factories/EventStaking__factory";

task("deploy:EventStaking").setAction(async function ({ ethers }) {
  const signers: SignerWithAddress[] = await ethers.getSigners();
  const eventStakingFactory: EventStaking__factory = <EventStaking__factory>(
    await ethers.getContractFactory("EventStaking")
  );
  const eventStaking: EventStaking = <EventStaking>await eventStakingFactory.connect(signers[0]).deploy();
  await eventStaking.deployed();
  console.log("EventStaking deployed to: ", eventStaking.address);
});
