import type { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signer-with-address";
import { ethers } from "hardhat";

import type { EventStaking } from "../../types/EventStaking";
import type { EventStaking__factory } from "../../types/factories/EventStaking__factory";

export async function deployEventStakingFixture(): Promise<{ eventStaking: EventStaking }> {
  const signers: SignerWithAddress[] = await ethers.getSigners();
  const admin: SignerWithAddress = signers[0];

  const eventStakingFactory: EventStaking__factory = <EventStaking__factory>(
    await ethers.getContractFactory("EventStaking")
  );
  const eventStaking: EventStaking = <EventStaking>await eventStakingFactory.connect(admin).deploy();
  await eventStaking.deployed();

  return { eventStaking };
}
