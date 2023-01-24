// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.4;

import "hardhat/console.sol";

error EventStaking_Rsvp_Price_Not_Met();
error EventStaking_Event_Not_Found();
error EventStaking_Cannot_Withdraw_Not_Creator();

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
        /// @dev 2^32 = 4,294,967,296 which should allow us to include half the earth population
        uint32 maxParticipantCount;
        /// @notice The price of attendance.
        /// @dev The maximum price that can be set is ~1.2M (2^80/10^18) ETH.
        uint80 rsvpPrice;
        /// @notice The time that the event starts.
        uint32 eventStartDateInSeconds;
        /// @notice The time that the event lasts.
        uint32 eventDurationInSeconds;
    }
    /// @notice Tracks the next sequence ID to be assigned to an exhibition.
    uint256 private lastStakedEventId;

    /// @notice Maps the event ID to their details.
    mapping(uint256 => StakedEvent) private idToStakedEvent;

    /// @notice Maps the event ID to a mapping of addresses to RSVP statuses.
    /// @dev 0 means not RSVP'd, true means RSVP'd, false means checked in
    mapping(uint256 => mapping(uint256 => bool)) private eventIdToRsvpMapping;

    /// @notice Maps the event ID to the total staked amount.
    mapping(uint256 => uint256) private idToStakedAmount;

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
        uint32 maxParticipantCount,
        uint80 rsvpPrice,
        uint32 eventStartDateInSeconds,
        uint32 eventDurationInSeconds
    );

    /**
     * @notice Emitted when an RSVP is created
     * @param eventId the ID of the event
     * @param participant the address of the participant
     */
    event RSVP(uint256 indexed eventId, address participant);

    /**
     * @notice Emitted when an Checkin is created
     * @param eventId the ID of the event
     * @param participant the address of the participant
     */
    event Checkin(uint256 indexed eventId, address participant);

    /**
     * @notice Emitted when an withdraw happens
     * @param eventId the ID of the event
     * @param amount the amount withdrawn
     */
    event Withdraw(uint256 indexed eventId, uint256 amount);

    /// @notice Requires the staked event exists
    modifier stakedEventExists(uint256 eventId) {
        if (idToStakedEvent[eventId] == 0) {
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
        // TODO: Validate rsvp price below max?
        // TODO: Validate start and duration below max?
        unchecked {
            eventId = ++lastStakedEventId;
        }
        idToStakedEvent[eventId] = StakedEvent({
            id: eventId,
            creator: payable(_msgSender()),
            name: eventName,
            maxParticipantCount: maxParticipantCount,
            rsvpPrice: rsvpPrice,
            eventStartDateInSeconds: eventStartDateInSeconds,
            eventDurationInSeconds: eventDurationInSeconds
        });
        emit StakedEventCreated({
            exhibitionId: exhibitionId,
            creator: _msgSender(),
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
    function getEventMetadata(uint256 eventId) external view returns (string eventName, address creator) {
        StakedEvent memory stakedEvent = idToStakedEvent[eventId];
        eventName = stakedEvent.name;
        creator = stakedEvent.curator;
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
        eventIdToRsvpMapping[eventId][_msgSender()] = true;
        idToStakedAmount[eventId] += msg.value;
        emit RSVP({ eventId: eventId, participant: _msgSender() });
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
        if (eventIdToRsvpMapping[eventId] == 0 || eventIdToRsvpMapping[eventId][_msgSender()] != true) {
            revert EventStaking_RSVP_Not_Found();
        }
        // TODO: Check the event time, return an error if the event is not started or in progress
        eventIdToRsvpMapping[eventId][_msgSender()] = false;
        uint256 memory stakedAmountForEvent = idToStakedAmount[eventId];
        _msgSender().send(stakedAmountForEvent);
        emit Checkin({ eventId: eventId, participant: _msgSender() });
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
        if (stakedEvent.creator != _msgSender()) {
            revert EventStaking_Cannot_Withdraw_Not_Creator();
        }
        // TODO: Check event has ended
        uint256 memory stakedAmountForEvent = idToStakedAmount[eventId];
        _msgSender().send(stakedAmountForEvent);
        emit Withdraw({ eventId: eventId, amount: stakedAmountForEvent });
    }
}
