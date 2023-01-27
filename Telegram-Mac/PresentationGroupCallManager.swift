import Foundation
import Postbox
import TelegramCore
import SyncCore
import SwiftSignalKit

struct PresentationGroupCallSummaryState: Equatable {
    var info: GroupCallInfo
    var participantCount: Int
    var callState: PresentationGroupCallState
    var topParticipants: [GroupCallParticipantsContext.Participant]
    var numberOfActiveSpeakers: Int
    init(
        info: GroupCallInfo,
        participantCount: Int,
        callState: PresentationGroupCallState,
        topParticipants: [GroupCallParticipantsContext.Participant],
        numberOfActiveSpeakers: Int
    ) {
        self.info = info
        self.participantCount = participantCount
        self.callState = callState
        self.topParticipants = topParticipants
        self.numberOfActiveSpeakers = numberOfActiveSpeakers
    }
}



enum RequestOrJoinGroupCallResult {
    case success(GroupCallContext)
    case fail
    case samePeer(GroupCallContext)
}

public enum PresentationGroupCallMuteAction: Equatable {
    case muted(isPushToTalkActive: Bool)
    case unmuted
}

public struct PresentationGroupCallState: Equatable {
    public enum NetworkState {
        case connecting
        case connected
    }
    
    public enum DefaultParticipantMuteState {
        case unmuted
        case muted
    }

    
    public var networkState: NetworkState
    public var canManageCall: Bool
    public var adminIds: Set<PeerId>
    public var muteState: GroupCallParticipantsContext.Participant.MuteState?
    public var defaultParticipantMuteState: DefaultParticipantMuteState?

    public init(
        networkState: NetworkState,
        canManageCall: Bool,
        adminIds: Set<PeerId>,
        muteState: GroupCallParticipantsContext.Participant.MuteState?,
        defaultParticipantMuteState: DefaultParticipantMuteState?
    ) {
        self.networkState = networkState
        self.canManageCall = canManageCall
        self.adminIds = adminIds
        self.muteState = muteState
        self.defaultParticipantMuteState = defaultParticipantMuteState
    }
}



struct PresentationGroupCallMembers: Equatable {
    public var participants: [GroupCallParticipantsContext.Participant]
    public var speakingParticipants: Set<PeerId>
    public var totalCount: Int
    public var loadMoreToken: String?
    
    public init(
        participants: [GroupCallParticipantsContext.Participant],
        speakingParticipants: Set<PeerId>,
        totalCount: Int,
        loadMoreToken: String?
    ) {
        self.participants = participants
        self.speakingParticipants = speakingParticipants
        self.totalCount = totalCount
        self.loadMoreToken = loadMoreToken
    }
}




protocol PresentationGroupCall: class {
    var account: Account { get }
    var sharedContext: SharedAccountContext { get }
    var internalId: CallSessionInternalId { get }
    var peerId: PeerId { get }
    var peer: Peer? { get }
    var canBeRemoved: Signal<Bool, NoError> { get }
    var state: Signal<PresentationGroupCallState, NoError> { get }
    var members: Signal<PresentationGroupCallMembers?, NoError> { get }
    var audioLevels: Signal<[(PeerId, Float)], NoError> { get }
    var myAudioLevel: Signal<Float, NoError> { get }
    var invitedPeers: Signal<Set<PeerId>, NoError> { get }

    var summaryState: Signal<PresentationGroupCallSummaryState?, NoError> { get }

    func leave(terminateIfPossible: Bool) -> Signal<Bool, NoError>
    
    func toggleIsMuted()
    func setIsMuted(action: PresentationGroupCallMuteAction)
    func updateMuteState(peerId: PeerId, isMuted: Bool)
    func invitePeer(_ peerId: PeerId)
    func updateDefaultParticipantsAreMuted(isMuted: Bool)
}
