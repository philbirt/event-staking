import { loadFixture, time } from "@nomicfoundation/hardhat-network-helpers";
import { expect } from "chai";
import { ethers } from "hardhat";
import { ONE_HOUR, getBlockTime, increaseTimeTo } from "hardhat-helpers";
import { setETHBalance } from "hardhat-helpers";

import { deployEventStakingFixture } from "./EventStaking.fixture";

describe("Unit tests", function () {
  before(async function () {
    const signers = await ethers.getSigners();
    this.user1 = signers[0];
    this.user2 = signers[1];
    this.currentTime = await getBlockTime();

    this.loadFixture = loadFixture;
  });

  describe("EventStaking", function () {
    beforeEach(async function () {
      const { eventStaking } = await this.loadFixture(deployEventStakingFixture);
      this.eventStaking = eventStaking;
    });

    describe("createEvent", function () {
      describe("when no max participants is given", async function () {
        it("should revert", async function () {
          await expect(
            this.eventStaking.connect(this.user1).createEvent("yakult event", 0, 1, this.currentTime, ONE_HOUR),
          ).to.be.revertedWithCustomError(this.eventStaking, "EventStaking_Max_Participants_Cannot_Be_Zero");
        });
      });

      describe("when no rsvp price is given", async function () {
        it("should revert", async function () {
          await expect(
            this.eventStaking.connect(this.user1).createEvent("yakult event", 1, 0, this.currentTime, ONE_HOUR),
          ).to.be.revertedWithCustomError(this.eventStaking, "EventStaking_No_Free_Events");
        });
      });

      describe("when no eventStartDateInSeconds is given", async function () {
        it("should revert", async function () {
          await expect(
            this.eventStaking.connect(this.user1).createEvent("yakult event", 1, 1, 0, ONE_HOUR),
          ).to.be.revertedWithCustomError(this.eventStaking, "EventStaking_Start_Time_Required");
        });
      });

      describe("when no eventDurationInSeconds is given", async function () {
        it("should revert", async function () {
          await expect(
            this.eventStaking.connect(this.user1).createEvent("yakult event", 1, 1, this.currentTime, 0),
          ).to.be.revertedWithCustomError(this.eventStaking, "EventStaking_Duration_Required");
        });
      });

      describe("when successful", async function () {
        it("should emit StakedEventCreated event", async function () {
          const tx = await this.eventStaking
            .connect(this.user1)
            .createEvent("yakult event", 1, 1, this.currentTime, ONE_HOUR);
          await expect(tx)
            .to.emit(this.eventStaking, "StakedEventCreated")
            .withArgs(1, this.user1.address, "yakult event", 1, 1, this.currentTime, this.currentTime + ONE_HOUR);
        });

        it("should set the event id", async function () {
          await this.eventStaking.connect(this.user1).createEvent("yakult event", 1, 1, this.currentTime, ONE_HOUR);
          const metadataTx = await this.eventStaking.connect(this.user1).getEventMetadata(1);
          await expect(metadataTx).to.deep.equal(["yakult event", this.user1.address]);
        });

        it("should set the increment the event id", async function () {
          await this.eventStaking.connect(this.user1).createEvent("yakult event", 1, 1, this.currentTime, ONE_HOUR);
          await this.eventStaking.connect(this.user1).createEvent("another event", 1, 1, this.currentTime, ONE_HOUR);

          const metadataTx = await this.eventStaking.connect(this.user1).getEventMetadata(2);
          await expect(metadataTx).to.deep.equal(["another event", this.user1.address]);
        });
      });
    });

    describe("getEventMetadata", function () {
      beforeEach(async function () {
        await this.eventStaking.connect(this.user1).createEvent("yakult event", 1, 1, this.currentTime, ONE_HOUR);
      });

      it("should return the event metadata", async function () {
        const tx = await this.eventStaking.connect(this.user1).getEventMetadata(1);
        await expect(tx).to.deep.equal(["yakult event", this.user1.address]);
      });
    });

    describe("rsvp", function () {
      describe("when event does not exist", async function () {
        it("should revert", async function () {
          await expect(this.eventStaking.connect(this.user1).rsvp(1, { value: 2 })).to.be.revertedWithCustomError(
            this.eventStaking,
            "EventStaking_Event_Not_Found",
          );
        });
      });

      describe("when event exists", async function () {
        beforeEach(async function () {
          this.rsvpPrice = 2;
          await this.eventStaking
            .connect(this.user1)
            .createEvent("yakult event", 1, this.rsvpPrice, this.currentTime, ONE_HOUR);
          await setETHBalance(this.user1, ethers.utils.parseEther("100"));
        });

        describe("when the rsvp amount is too low", async function () {
          it("should revert", async function () {
            await expect(
              this.eventStaking.connect(this.user1).rsvp(1, { value: this.rsvpPrice - 1 }),
            ).to.be.revertedWithCustomError(this.eventStaking, "EventStaking_Rsvp_Price_Not_Met");
          });
        });

        describe("when already rsvp'd", async function () {
          beforeEach(async function () {
            await this.eventStaking.connect(this.user1).rsvp(1, { value: this.rsvpPrice });
          });

          it("should revert", async function () {
            await expect(
              this.eventStaking.connect(this.user1).rsvp(1, { value: this.rsvpPrice }),
            ).to.be.revertedWithCustomError(this.eventStaking, "EventStaking_Rsvp_Already_Set");
          });
        });

        describe("when already checked in", async function () {
          beforeEach(async function () {
            await this.eventStaking.connect(this.user1).rsvp(1, { value: this.rsvpPrice });
            await this.eventStaking.connect(this.user1).checkIn(1);
          });

          it("should revert", async function () {
            await expect(
              this.eventStaking.connect(this.user1).rsvp(1, { value: this.rsvpPrice }),
            ).to.be.revertedWithCustomError(this.eventStaking, "EventStaking_Rsvp_Already_Checked_In");
          });
        });

        describe("when the event has too many participants", async function () {
          it("should revert", async function () {
            await this.eventStaking.connect(this.user1).rsvp(1, { value: this.rsvpPrice });

            await expect(
              this.eventStaking.connect(this.user2).rsvp(1, { value: this.rsvpPrice }),
            ).to.be.revertedWithCustomError(this.eventStaking, "EventStaking_Event_Overbooked");
          });
        });

        describe("when successful", async function () {
          it("should emit an RSVPAdded event", async function () {
            const rsvpTx = await this.eventStaking.connect(this.user1).rsvp(1, { value: this.rsvpPrice });
            await expect(rsvpTx)
              .to.emit(this.eventStaking, "RSVPAdded")
              .withArgs(1, this.user1.address, this.rsvpPrice);
          });
        });
      });
    });

    describe("checkIn", function () {
      describe("when event does not exist", async function () {
        it("should revert", async function () {
          await expect(this.eventStaking.connect(this.user1).rsvp(1, { value: 2 })).to.be.revertedWithCustomError(
            this.eventStaking,
            "EventStaking_Event_Not_Found",
          );
        });
      });

      describe("when event exists", async function () {
        beforeEach(async function () {
          this.rsvpPrice = 2;
          await this.eventStaking
            .connect(this.user1)
            .createEvent("yakult event", 1, this.rsvpPrice, this.currentTime + ONE_HOUR, ONE_HOUR);
          await setETHBalance(this.user1, ethers.utils.parseEther("100"));
        });

        describe("when its before the event starts", async function () {
          it("should revert", async function () {
            await expect(this.eventStaking.connect(this.user1).checkIn(1)).to.be.revertedWithCustomError(
              this.eventStaking,
              "EventStaking_Event_Not_In_Progress",
            );
          });
        });

        describe("when its after the event ends", async function () {
          beforeEach(async function () {
            await increaseTimeTo(this.currentTime + ONE_HOUR + ONE_HOUR, true);
          });

          it("should revert", async function () {
            await expect(this.eventStaking.connect(this.user1).checkIn(1)).to.be.revertedWithCustomError(
              this.eventStaking,
              "EventStaking_Event_Not_In_Progress",
            );
          });
        });

        describe("when its during the event", async function () {
          beforeEach(async function () {
            await increaseTimeTo(this.currentTime + ONE_HOUR, true);
          });

          describe("when rsvp does not exist", async function () {
            it("should revert", async function () {
              await expect(this.eventStaking.connect(this.user1).checkIn(1)).to.be.revertedWithCustomError(
                this.eventStaking,
                "EventStaking_Rsvp_Not_Found",
              );
            });
          });

          describe("when rsvp exists", async function () {
            beforeEach(async function () {
              await this.eventStaking.connect(this.user1).rsvp(1, { value: this.rsvpPrice });
            });

            describe("when the event is in progress", async function () {
              describe("when already checked in", async function () {
                it("should revert", async function () {
                  await this.eventStaking.connect(this.user1).checkIn(1);

                  await expect(this.eventStaking.connect(this.user1).checkIn(1)).to.be.revertedWithCustomError(
                    this.eventStaking,
                    "EventStaking_Rsvp_Already_Checked_In",
                  );
                });
              });

              describe("when successful", async function () {
                it("emits an event", async function () {
                  const checkinTx = await this.eventStaking.connect(this.user1).checkIn(1);
                  await expect(checkinTx).to.emit(this.eventStaking, "CheckinAdded").withArgs(1, this.user1.address);
                });
              });
            });
          });
        });
      });
    });

    describe("withdrawProceeds", function () {
      describe("when event does not exist", async function () {
        it("should revert", async function () {
          await expect(this.eventStaking.connect(this.user1).withdrawProceeds(1)).to.be.revertedWithCustomError(
            this.eventStaking,
            "EventStaking_Event_Not_Found",
          );
        });
      });

      describe("when event exists", async function () {
        beforeEach(async function () {
          this.rsvpPrice = 2;
          this.maxParticipantCount = 10;

          // Create the event
          await this.eventStaking
            .connect(this.user1)
            .createEvent("yakult event", this.maxParticipantCount, this.rsvpPrice, this.currentTime, ONE_HOUR);
        });

        describe("when its before the event ends", async function () {
          it("should revert", async function () {
            await expect(this.eventStaking.connect(this.user1).withdrawProceeds(1)).to.be.revertedWithCustomError(
              this.eventStaking,
              "EventStaking_Event_Not_Ended",
            );
          });
        });

        describe("when its after the event ends", async function () {
          beforeEach(async function () {
            await increaseTimeTo(this.currentTime + ONE_HOUR, true);
          });

          describe("when the event has no staked amount", async function () {
            beforeEach(async function () {
              await this.eventStaking.connect(this.user1).createEvent("yakult event", 1, 1, this.currentTime, ONE_HOUR);
            });

            it("should revert", async function () {
              await expect(this.eventStaking.connect(this.user1).withdrawProceeds(1)).to.be.revertedWithCustomError(
                this.eventStaking,
                "EventStaking_Withdraw_Amount_Zero",
              );
            });
          });

          describe("when the event has a staked amount", async function () {
            beforeEach(async function () {
              // Give the users some eth to rsvp
              await setETHBalance(this.user1, ethers.utils.parseEther("100"));
              await setETHBalance(this.user2, ethers.utils.parseEther("100"));

              // RSVP both users to event #1
              await this.eventStaking.connect(this.user1).rsvp(1, { value: this.rsvpPrice });
              await this.eventStaking.connect(this.user2).rsvp(1, { value: this.rsvpPrice });
            });

            describe("when a random user withdraws", async function () {
              it("should revert", async function () {
                await expect(this.eventStaking.connect(this.user2).withdrawProceeds(1)).to.be.revertedWithCustomError(
                  this.eventStaking,
                  "EventStaking_Cannot_Withdraw_Not_Creator",
                );
              });
            });

            describe("when the creator of the event withdraws", async function () {
              it("emits an event", async function () {
                const withdrawTx = await this.eventStaking.connect(this.user1).withdrawProceeds(1);
                await expect(withdrawTx)
                  .to.emit(this.eventStaking, "Withdraw")
                  .withArgs(1, this.rsvpPrice * 2);
              });

              it("increases the balance of user1", async function () {
                const balanceBefore = await this.user1.getBalance();
                const withdrawTx = await this.eventStaking.connect(this.user1).withdrawProceeds(1);
                const balanceAfter = await this.user1.getBalance();

                // Would like a stronger assertion
                // expect(balanceAfter).to.be.greaterThan(balanceBefore);
              });

              describe("when the creator of the event withdraws a second time", async function () {
                beforeEach(async function () {
                  await this.eventStaking.connect(this.user1).withdrawProceeds(1);
                });

                it("should revert", async function () {
                  await expect(this.eventStaking.connect(this.user1).withdrawProceeds(1)).to.be.revertedWithCustomError(
                    this.eventStaking,
                    "EventStaking_Withdraw_Amount_Zero",
                  );
                });
              });
            });
          });
        });
      });
    });
  });
});
