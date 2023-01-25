// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.4;

import "hardhat/console.sol";

error EventStaking_Event_Not_Found();
error EventStaking_Max_Participants_Cannot_Be_Zero();
error EventStaking_No_Free_Events();
error EventStaking_Start_Time_Required();
error EventStaking_Duration_Required();
error EventStaking_Rsvp_Not_Found();
error EventStaking_Rsvp_Price_Not_Met();
error EventStaking_Rsvp_Already_Set();
error EventStaking_Event_Overbooked();
error EventStaking_Rsvp_Already_Checked_In();
error EventStaking_Cannot_Withdraw_Not_Creator();
error EventStaking_Withdraw_Amount_Zero();

contract EventStaking {
    /**
     * @notice Stores details about an event.
     */
    struct StakedEvent {
        /// @notice The address for the creator of this event.
        address payable creator;
        /// @notice The name for the event.
        string name;
        /// @notice The number of participants that can join the event.
        uint256 maxParticipantCount;
        /// @notice The price of attendance.
        uint256 rsvpPrice;
        /// @notice The time that the event starts.
        uint256 eventStartDateInSeconds;
        /// @notice The time that the event lasts.
        uint256 eventDurationInSeconds;
    }
    /// @notice Tracks the next sequence ID to be assigned to an exhibition.
    uint256 private lastStakedEventId;

    /// @notice Maps the event ID to their details.
    mapping(uint256 => StakedEvent) private idToStakedEvent;

    enum RSVP {
        NOT_ATTENDING,
        ATTENDING,
        CHECKIN
    }

    /// @notice Maps the event ID to a mapping of addresses to RSVP statuses.
    mapping(uint256 => mapping(address => RSVP)) private eventIdToRsvpMapping;

    /// @notice Maps the event ID to the total staked amount.
    mapping(uint256 => uint256) private idToStakedAmount;

    /// @notice maps the event ID to the total number of RSVP'd participants
    mapping(uint256 => uint256) private idToRsvpParticipantCount;

    /**
     * @notice Emitted when an event is created.
     * @param eventId The ID of the event
     * @param creator The address for the creator of this event.
     * @param name The name for the event
     * @param maxParticipantCount The number of participants that can join the event.
     * @param rsvpPrice The price of attendance.
     * @param eventStartDateInSeconds The time that the event starts.
     * @param eventDurationInSeconds The time that the event lasts.
     */
    event StakedEventCreated(
        uint256 indexed eventId,
        address indexed creator,
        string name,
        uint256 maxParticipantCount,
        uint256 rsvpPrice,
        uint256 eventStartDateInSeconds,
        uint256 eventDurationInSeconds
    );

    /**
     * @notice Emitted when an RSVP is created
     * @param eventId the ID of the event
     * @param participant the address of the participant
     */
    event RSVPAdded(uint256 indexed eventId, address participant, uint256 amountStaked);

    /**
     * @notice Emitted when an Checkin is created
     * @param eventId the ID of the event
     * @param participant the address of the participant
     */
    event CheckinAdded(uint256 indexed eventId, address participant);

    /**
     * @notice Emitted when an withdraw happens
     * @param eventId the ID of the event
     * @param amount the amount withdrawn
     */
    event Withdraw(uint256 indexed eventId, uint256 amount);

    /// @notice Requires the staked event exists
    modifier stakedEventExists(uint256 eventId) {
        if (idToStakedEvent[eventId].creator == address(0)) {
            revert EventStaking_Event_Not_Found();
        }
        _;
    }

    /**
     * @notice Can be called by anyone to create a new event.
     * @param eventName The name for the event.
     * @param maxParticipantCount The max number of participants in the allowed in the event.
     * @param rsvpPrice The amount in ETH to rsvp for the event.
     * @param eventStartDateInSeconds The start date of the event, at which participants can check-in.
     * @param eventDurationInSeconds The duration from the start date to the end of the event.
     */
    function createEvent(
        string calldata eventName,
        uint256 maxParticipantCount,
        uint256 rsvpPrice,
        uint256 eventStartDateInSeconds,
        uint256 eventDurationInSeconds
    ) external returns (uint256 eventId) {
        if (maxParticipantCount == 0) {
            revert EventStaking_Max_Participants_Cannot_Be_Zero();
        }
        if (rsvpPrice == 0) {
            revert EventStaking_No_Free_Events();
        }
        if (eventStartDateInSeconds == 0) {
            revert EventStaking_Start_Time_Required();
        }
        if (eventDurationInSeconds == 0) {
            revert EventStaking_Duration_Required();
        }

        unchecked {
            eventId = ++lastStakedEventId;
        }
        idToStakedEvent[eventId] = StakedEvent({
            creator: payable(msg.sender),
            name: eventName,
            maxParticipantCount: maxParticipantCount,
            rsvpPrice: rsvpPrice,
            eventStartDateInSeconds: eventStartDateInSeconds,
            eventDurationInSeconds: eventDurationInSeconds
        });
        emit StakedEventCreated({
            eventId: eventId,
            creator: msg.sender,
            name: eventName,
            maxParticipantCount: maxParticipantCount,
            rsvpPrice: rsvpPrice,
            eventStartDateInSeconds: eventStartDateInSeconds,
            eventDurationInSeconds: eventDurationInSeconds
        });

        return eventId;
    }

    /**
     * @notice Returns metadata related to the event
     * @param eventId The id of the event.
     * @return eventName The name of the event
     * @return creator The creator of the event.
     */
    function getEventMetadata(uint256 eventId) external view returns (string memory eventName, address creator) {
        StakedEvent memory stakedEvent = idToStakedEvent[eventId];
        eventName = stakedEvent.name;
        creator = stakedEvent.creator;
    }

    /**
     * @notice RSVP for an event
     * @param eventId The id of the event.
     */
    function rsvp(uint256 eventId) external payable stakedEventExists(eventId) {
        StakedEvent memory stakedEvent = idToStakedEvent[eventId];
        if (stakedEvent.rsvpPrice > msg.value) {
            // TODO: what happens if someone overpays? Should we allow?
            revert EventStaking_Rsvp_Price_Not_Met();
        }

        RSVP rsvpState = eventIdToRsvpMapping[eventId][msg.sender];
        if (rsvpState == RSVP.ATTENDING) {
            revert EventStaking_Rsvp_Already_Set();
        }
        if (rsvpState == RSVP.CHECKIN) {
            revert EventStaking_Rsvp_Already_Checked_In();
        }

        if (idToRsvpParticipantCount[eventId] >= stakedEvent.maxParticipantCount) {
            revert EventStaking_Event_Overbooked();
        }

        eventIdToRsvpMapping[eventId][msg.sender] = RSVP.ATTENDING;
        idToStakedAmount[eventId] += msg.value;
        ++idToRsvpParticipantCount[eventId];
        emit RSVPAdded({ eventId: eventId, participant: msg.sender, amountStaked: msg.value });
    }

    /**
     * @notice Check in to an event
     * @param eventId The id of the event.
     * @dev Notes:
     *  1) Only the RSVPd participant can check in.
     *  2) Check-in is only successful if its during the event (e.g. within start end time)
     *  3) If check-in is successful, the staked ETH should be returned back to the participant.
     */
    function checkIn(uint256 eventId) external payable stakedEventExists(eventId) {
        if (eventIdToRsvpMapping[eventId][msg.sender] == RSVP.CHECKIN) {
            revert EventStaking_Rsvp_Already_Checked_In();
        }
        if (eventIdToRsvpMapping[eventId][msg.sender] != RSVP.ATTENDING) {
            revert EventStaking_Rsvp_Not_Found();
        }
        // TODO: Check the event time, return an error if the event is not started or in progress
        eventIdToRsvpMapping[eventId][msg.sender] = RSVP.CHECKIN;
        uint256 stakedAmountForEvent = idToStakedAmount[eventId];
        payable(msg.sender).transfer(stakedAmountForEvent);
        emit CheckinAdded({ eventId: eventId, participant: msg.sender });
    }

    /**
     * @notice Withdraw Proceeds of the event staked by participants that did rsvpd but did not attend.
     * @param eventId The id of the event.
     * @dev Notes:
     *  1) This is a bonus fn, implement this if time permits.
     *  2) Should only be callable by the creator or the event.
     *  3) Can only be executed once the event has ended.
     */
    function withdrawProceeds(uint256 eventId) external stakedEventExists(eventId) {
        StakedEvent memory stakedEvent = idToStakedEvent[eventId];
        if (stakedEvent.creator != msg.sender) {
            revert EventStaking_Cannot_Withdraw_Not_Creator();
        }
        if (idToStakedAmount[eventId] == 0) {
            revert EventStaking_Withdraw_Amount_Zero();
        }
        // TODO: Check event has ended
        uint256 stakedAmountForEvent = idToStakedAmount[eventId];
        idToStakedAmount[eventId] = 0;
        payable(msg.sender).transfer(stakedAmountForEvent);
        emit Withdraw({ eventId: eventId, amount: stakedAmountForEvent });
    }
}
