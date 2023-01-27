import Cocoa
import Postbox
import TelegramCore
import SyncCore
import SwiftSignalKit
import AVFoundation
import TelegramVoip

private extension PresentationGroupCallState {
    static var initialValue: PresentationGroupCallState {
        return PresentationGroupCallState(
            networkState: .connecting,
            canManageCall: false,
            adminIds: Set(),
            muteState: GroupCallParticipantsContext.Participant.MuteState(canUnmute: true),
            defaultParticipantMuteState: nil
        )
    }
}

final class PresentationGroupCallImpl: PresentationGroupCall {
    private enum InternalState {
        case requesting
        case active(GroupCallInfo)
        case estabilished(info: GroupCallInfo, clientParams: String, localSsrc: UInt32, initialState: GroupCallParticipantsContext.State)
        
        var callInfo: GroupCallInfo? {
            switch self {
            case .requesting:
                return nil
            case let .active(info):
                return info
            case let .estabilished(info, _, _, _):
                return info
            }
        }
    }
    
    private struct SummaryInfoState: Equatable {
          public var info: GroupCallInfo
          
          public init(
              info: GroupCallInfo
          ) {
              self.info = info
          }
      }
      
    private struct SummaryParticipantsState: Equatable {
        var participantCount: Int
        var topParticipants: [GroupCallParticipantsContext.Participant]
        var numberOfActiveSpeakers: Int
        
        public init(
            participantCount: Int,
            topParticipants: [GroupCallParticipantsContext.Participant],
            numberOfActiveSpeakers: Int
        ) {
            self.participantCount = participantCount
            self.topParticipants = topParticipants
            self.numberOfActiveSpeakers = numberOfActiveSpeakers
        }
    }

    private class SpeakingParticipantsContext {
        private let speakingLevelThreshold: Float = 0.15
        private let cutoffTimeout: Int32 = 1
        private let silentTimeout: Int32 = 3
        
        struct Participant {
            let timestamp: Int32
            let level: Float
        }
        
        private var participants: [PeerId: Participant] = [:]
        private let speakingParticipantsPromise = ValuePromise<Set<PeerId>>()
        private var speakingParticipants = Set<PeerId>() {
            didSet {
                self.speakingParticipantsPromise.set(self.speakingParticipants)
            }
        }
        
        init() {
        }
        
        func update(levels: [(PeerId, Float)]) {
            let timestamp = Int32(CFAbsoluteTimeGetCurrent())
            let currentParticipants: [PeerId: Participant] = self.participants
            
            var validSpeakers: [PeerId: Participant] = [:]
            var silentParticipants = Set<PeerId>()
            var speakingParticipants = Set<PeerId>()
            for (peerId, level) in levels {
                if level > speakingLevelThreshold {
                    validSpeakers[peerId] = Participant(timestamp: timestamp, level: level)
                    speakingParticipants.insert(peerId)
                } else {
                    silentParticipants.insert(peerId)
                }
            }
            
            for (peerId, participant) in currentParticipants {
                if let _ = validSpeakers[peerId] {
                } else {
                    let delta = timestamp - participant.timestamp
                    if silentParticipants.contains(peerId) {
                        if delta < silentTimeout {
                            validSpeakers[peerId] = participant
                            speakingParticipants.insert(peerId)
                        }
                    } else if delta < cutoffTimeout {
                        validSpeakers[peerId] = participant
                        speakingParticipants.insert(peerId)
                    }
                }
            }
            
            self.participants = validSpeakers
            self.speakingParticipants = speakingParticipants
        }
        
        func get() -> Signal<Set<PeerId>, NoError> {
            return self.speakingParticipantsPromise.get() |> distinctUntilChanged
        }
    }


    
    let account: Account
    let sharedContext: SharedAccountContext
    
    let internalId: CallSessionInternalId
    let peerId: PeerId
    let peer: Peer?
    let initialCall: CachedChannelData.ActiveCall?
    
    private var internalState: InternalState = .requesting
    
    private var callContext: OngoingGroupCallContext?
    private var ssrcMapping: [UInt32: PeerId] = [:]
    
    private var summaryInfoState = Promise<SummaryInfoState?>(nil)
    private var summaryParticipantsState = Promise<SummaryParticipantsState?>(nil)
   
    private let summaryStatePromise = Promise<PresentationGroupCallSummaryState?>(nil)
    public var summaryState: Signal<PresentationGroupCallSummaryState?, NoError> {
        return self.summaryStatePromise.get()
    }
    private var summaryStateDisposable: Disposable?

    
    private var isMutedValue: PresentationGroupCallMuteAction = .muted(isPushToTalkActive: false)
    private let isMutedPromise = ValuePromise<PresentationGroupCallMuteAction>(.muted(isPushToTalkActive: false))
    public var isMuted: Signal<Bool, NoError> {
        return self.isMutedPromise.get()
        |> map { value -> Bool in
            switch value {
            case let .muted(isPushToTalkActive):
                return isPushToTalkActive
            case .unmuted:
                return true
            }
        }
    }

        
    private let audioLevelsPipe = ValuePipe<[(PeerId, Float)]>()
    public var audioLevels: Signal<[(PeerId, Float)], NoError> {
        return self.audioLevelsPipe.signal()
    }
    
    private let speakingParticipantsContext = SpeakingParticipantsContext()

    
   private var audioLevelsDisposable = MetaDisposable()
   
   private var participantsContextStateDisposable = MetaDisposable()
   private var participantsContext: GroupCallParticipantsContext?
   
   private let myAudioLevelPipe = ValuePipe<Float>()
   public var myAudioLevel: Signal<Float, NoError> {
       return self.myAudioLevelPipe.signal()
   }
   private var myAudioLevelDisposable = MetaDisposable()

    
    private let _canBeRemoved = Promise<Bool>(false)
    var canBeRemoved: Signal<Bool, NoError> {
        return self._canBeRemoved.get()
    }
    
    private var stateValue = PresentationGroupCallState.initialValue {
       didSet {
           if self.stateValue != oldValue {
               self.statePromise.set(self.stateValue)
           }
       }
   }
   private let statePromise = ValuePromise<PresentationGroupCallState>(PresentationGroupCallState.initialValue)
   public var state: Signal<PresentationGroupCallState, NoError> {
       return self.statePromise.get()
   }
       
    
    private var membersValue: PresentationGroupCallMembers? {
        didSet {
            if self.membersValue != oldValue {
                self.membersPromise.set(self.membersValue)
            }
        }
    }
    private let membersPromise = ValuePromise<PresentationGroupCallMembers?>(nil, ignoreRepeated: true)
    public var members: Signal<PresentationGroupCallMembers?, NoError> {
        return self.membersPromise.get()
    }

    
    private var invitedPeersValue: Set<PeerId> = Set() {
        didSet {
            if self.invitedPeersValue != oldValue {
                self.inivitedPeersPromise.set(self.invitedPeersValue)
            }
        }
    }
    private let inivitedPeersPromise = ValuePromise<Set<PeerId>>(Set())
    public var invitedPeers: Signal<Set<PeerId>, NoError> {
        return self.inivitedPeersPromise.get()
    }

    
    private let requestDisposable = MetaDisposable()
    private var groupCallParticipantUpdatesDisposable: Disposable?
    
    private let networkStateDisposable = MetaDisposable()
    private let isMutedDisposable = MetaDisposable()
    private let memberStatesDisposable = MetaDisposable()
    private let leaveDisposable = MetaDisposable()
    
    private var checkCallDisposable: Disposable?
    private var isCurrentlyConnecting: Bool?
    
    private let devicesContext: DevicesContext
    private var settingsDisposable: Disposable?
    
    private var myAudioLevelTimer: SwiftSignalKit.Timer?
    private let typingDisposable = MetaDisposable()


    
    private var voiceSettings: VoiceCallSettings {
        didSet {
            let microUpdated = devicesContext.updateMicroId(voiceSettings) // todo
            let outputUpdated = devicesContext.updateOutputId(voiceSettings)
            if microUpdated {
                self.callContext?.switchAudioInput(devicesContext.currentMicroId ?? "")
            }
            if outputUpdated {
                 self.callContext?.switchAudioOutput(devicesContext.currentOutputId ?? "")
            }
        }
    }
    
    
    init(
        account: Account,
        sharedContext: SharedAccountContext,
        internalId: CallSessionInternalId,
        initialCall:CachedChannelData.ActiveCall?,
        peerId: PeerId,
        peer: Peer?
    ) {
        self.account = account
        self.sharedContext = sharedContext
        self.internalId = internalId
        self.peerId = peerId
        self.peer = peer
        self.initialCall = initialCall
        
        let semaphore = DispatchSemaphore(value: 0)
        var callSettings: VoiceCallSettings = VoiceCallSettings.defaultSettings
        let _ =  (voiceCallSettings(sharedContext.accountManager) |> take(1)).start(next: { settings in
            callSettings = settings
            semaphore.signal()
        })
        semaphore.wait()
        
        self.voiceSettings = callSettings
        self.devicesContext = DevicesContext(callSettings)

        self.groupCallParticipantUpdatesDisposable = (self.account.stateManager.groupCallParticipantUpdates
        |> deliverOnMainQueue).start(next: { [weak self] updates in
            guard let strongSelf = self else {
                return
            }
            if case let .estabilished(callInfo, _, _, _) = strongSelf.internalState {
                for (callId, update) in updates {
                    if callId == callInfo.id {
                        strongSelf.participantsContext?.addUpdates(updates: [update])
                    }
                }
            }
        })
        
        self.settingsDisposable = combineLatest(queue: .mainQueue(), voiceCallSettings(sharedContext.accountManager), devicesContext.signal).start(next: { [weak self] settings, _ in
            self?.voiceSettings = settings
        })
        
        self.summaryStatePromise.set(combineLatest(queue: .mainQueue(),
            self.summaryInfoState.get(),
            self.summaryParticipantsState.get(),
            self.statePromise.get()
        )
        |> map { infoState, participantsState, callState -> PresentationGroupCallSummaryState? in
            guard let infoState = infoState else {
                return nil
            }
            guard let participantsState = participantsState else {
                return nil
            }
            return PresentationGroupCallSummaryState(
                info: infoState.info,
                participantCount: participantsState.participantCount,
                callState: callState,
                topParticipants: participantsState.topParticipants,
                numberOfActiveSpeakers: participantsState.numberOfActiveSpeakers
            )
        })

        
        self.requestCall()

    }
    
    deinit {
        self.requestDisposable.dispose()
        self.groupCallParticipantUpdatesDisposable?.dispose()
        self.leaveDisposable.dispose()
        self.isMutedDisposable.dispose()
        self.memberStatesDisposable.dispose()
        self.networkStateDisposable.dispose()
        self.checkCallDisposable?.dispose()
        self.audioLevelsDisposable.dispose()
        self.participantsContextStateDisposable.dispose()
        self.myAudioLevelDisposable.dispose()
        self.settingsDisposable?.dispose()
        self.summaryStateDisposable?.dispose()
        self.myAudioLevelTimer?.invalidate()
        self.typingDisposable.dispose()
    }
    
    private func updateSessionState(internalState: InternalState) {
        
        let previousInternalState = self.internalState
        self.internalState = internalState
        
        
        switch previousInternalState {
        case .requesting:
            break
        default:
            if case .requesting = internalState {
                self.isCurrentlyConnecting = nil
            }
        }
        
        switch previousInternalState {
        case .active:
            break
        default:
            if case let .active(callInfo) = internalState {
                let callContext = OngoingGroupCallContext()
                self.callContext = callContext
                self.requestDisposable.set((callContext.joinPayload
                |> take(1)
                |> deliverOnMainQueue).start(next: { [weak self] joinPayload, ssrc in
                    guard let strongSelf = self else {
                        return
                    }
                    strongSelf.requestDisposable.set((joinGroupCall(
                        account: strongSelf.account,
                        peerId: strongSelf.peerId,
                        callId: callInfo.id,
                        accessHash: callInfo.accessHash,
                        preferMuted: true,
                        joinPayload: joinPayload
                    )
                    |> deliverOnMainQueue).start(next: { joinCallResult in
                        guard let strongSelf = self else {
                            return
                        }
                        if let clientParams = joinCallResult.callInfo.clientParams {
                            strongSelf.updateSessionState(internalState: .estabilished(info: joinCallResult.callInfo, clientParams: clientParams, localSsrc: ssrc, initialState: joinCallResult.state))
                        }
                    }))
                }))
                
                self.networkStateDisposable.set((callContext.networkState
                |> deliverOnMainQueue).start(next: { [weak self] state in
                    guard let strongSelf = self else {
                        return
                    }
                    let mappedState: PresentationGroupCallState.NetworkState
                    switch state {
                    case .connecting:
                        mappedState = .connecting
                    case .connected:
                        mappedState = .connected
                    }
                    if strongSelf.stateValue.networkState != mappedState {
                        strongSelf.stateValue.networkState = mappedState
                    }
                    
                    let isConnecting = mappedState == .connecting
                    
                    if strongSelf.isCurrentlyConnecting != isConnecting {
                        strongSelf.isCurrentlyConnecting = isConnecting
                        if isConnecting {
                            strongSelf.startCheckingCallIfNeeded()
                        } else {
                            strongSelf.checkCallDisposable?.dispose()
                            strongSelf.checkCallDisposable = nil
                        }
                    }
                }))
                
                self.audioLevelsDisposable.set((callContext.audioLevels
                |> deliverOnMainQueue).start(next: { [weak self] levels in
                    guard let strongSelf = self else {
                        return
                    }
                    var result: [(PeerId, Float)] = []
                    for (ssrc, level) in levels {
                        if let peerId = strongSelf.ssrcMapping[ssrc] {
                            result.append((peerId, level))
                        }
                    }
                    if !result.isEmpty {
                        strongSelf.audioLevelsPipe.putNext(result)
                    }
                    strongSelf.speakingParticipantsContext.update(levels: result)
                }))
                
                self.myAudioLevelDisposable.set((callContext.myAudioLevel
                |> deliverOnMainQueue).start(next: { [weak self] level in
                    guard let strongSelf = self else {
                        return
                    }
                    
                    let mappedLevel = level * 1.5
                    
                    strongSelf.processMyAudioLevel(level: mappedLevel)
                    strongSelf.myAudioLevelPipe.putNext(level)
                }))
            }
        }
        
        switch previousInternalState {
        case .estabilished:
            break
        default:
            if case let .estabilished(callInfo, clientParams, _, initialState) = internalState {
                self.summaryInfoState.set(.single(SummaryInfoState(info: callInfo)))
                
                self.stateValue.canManageCall = initialState.isCreator || initialState.adminIds.contains(self.account.peerId)
                if self.stateValue.canManageCall && initialState.defaultParticipantsAreMuted.canChange {
                    self.stateValue.defaultParticipantMuteState = initialState.defaultParticipantsAreMuted.isMuted ? .muted : .unmuted
                }

                
                self.ssrcMapping.removeAll()
                var ssrcs: [UInt32] = []
                for participant in initialState.participants {
                    self.ssrcMapping[participant.ssrc] = participant.peer.id
                    ssrcs.append(participant.ssrc)
                }
                self.callContext?.setJoinResponse(payload: clientParams, ssrcs: ssrcs)
                
                let participantsContext = GroupCallParticipantsContext(
                    account: self.account,
                    peerId: peerId,
                    id: callInfo.id,
                    accessHash: callInfo.accessHash,
                    state: initialState
                )
                self.participantsContext = participantsContext
                self.participantsContextStateDisposable.set(combineLatest(queue: .mainQueue(),
                   participantsContext.state,
                   participantsContext.numberOfActiveSpeakers,
                   self.speakingParticipantsContext.get()
               ).start(next: { [weak self] state, numberOfActiveSpeakers, speakingParticipants in
                   guard let strongSelf = self else {
                       return
                   }
                   
                   var topParticipants: [GroupCallParticipantsContext.Participant] = []
                   
                   var members = PresentationGroupCallMembers(
                       participants: [],
                       speakingParticipants: speakingParticipants,
                       totalCount: 0,
                       loadMoreToken: nil
                   )
                   for participant in state.participants {
                       members.participants.append(participant)
                       
                       
                       if topParticipants.count < 3 {
                           topParticipants.append(participant)
                       }
                       
                       strongSelf.ssrcMapping[participant.ssrc] = participant.peer.id
                       
                       if participant.peer.id == strongSelf.account.peerId {
                           if let muteState = participant.muteState {
                               strongSelf.stateValue.muteState = muteState
                               strongSelf.callContext?.setIsMuted(true)
                           } else if let currentMuteState = strongSelf.stateValue.muteState, !currentMuteState.canUnmute {
                               strongSelf.stateValue.muteState = GroupCallParticipantsContext.Participant.MuteState(canUnmute: true)
                               strongSelf.callContext?.setIsMuted(true)
                           }
                       }
                   }
                   
                   members.totalCount = state.totalCount
                   members.loadMoreToken = state.nextParticipantsFetchOffset
                   
                   strongSelf.membersValue = members
                   
                   strongSelf.stateValue.adminIds = state.adminIds
                   
                   strongSelf.summaryParticipantsState.set(.single(SummaryParticipantsState(
                       participantCount: state.totalCount,
                       topParticipants: topParticipants,
                       numberOfActiveSpeakers: numberOfActiveSpeakers
                   )))
               }))

                
                if let isCurrentlyConnecting = self.isCurrentlyConnecting, isCurrentlyConnecting {
                    self.startCheckingCallIfNeeded()
                }
            }
        }

    }
    
    private func startCheckingCallIfNeeded() {
        if self.checkCallDisposable != nil {
            return
        }
        if case let .estabilished(callInfo, _, ssrc, _) = self.internalState {
            let checkSignal = checkGroupCall(account: self.account, callId: callInfo.id, accessHash: callInfo.accessHash, ssrc: Int32(bitPattern: ssrc))
            
            self.checkCallDisposable = ((
                checkSignal
                |> castError(Bool.self)
                |> delay(4.0, queue: .mainQueue())
                |> mapToSignal { result -> Signal<Bool, Bool> in
                    if case .success = result {
                        return .fail(true)
                    } else {
                        return .single(true)
                    }
                }
            )
            |> restartIfError
            |> take(1)
            |> deliverOnMainQueue).start(completed: { [weak self] in
                guard let strongSelf = self else {
                    return
                }
                strongSelf.checkCallDisposable = nil
                strongSelf.requestCall()
            })
        }
    }
        
    public func leave(terminateIfPossible: Bool) -> Signal<Bool, NoError> {
        if case let .estabilished(callInfo, _, localSsrc, _) = self.internalState {
            if terminateIfPossible {
                self.leaveDisposable.set((stopGroupCall(account: self.account, peerId: self.peerId, callId: callInfo.id, accessHash: callInfo.accessHash)
                |> deliverOnMainQueue).start(completed: { [weak self] in
                    self?._canBeRemoved.set(.single(true))
                }))
            } else {
                self.leaveDisposable.set((leaveGroupCall(account: self.account, callId: callInfo.id, accessHash: callInfo.accessHash, source: localSsrc)
                |> deliverOnMainQueue).start(completed: { [weak self] in
                    self?._canBeRemoved.set(.single(true))
                }))
            }
        } else {
            self.requestDisposable.set(nil)
            self._canBeRemoved.set(.single(true))
        }
        return self._canBeRemoved.get()
    }
    
    public func toggleIsMuted() {
        switch self.isMutedValue {
        case .muted:
            self.setIsMuted(action: .unmuted)
        case .unmuted:
            self.setIsMuted(action: .muted(isPushToTalkActive: false))
        }
    }
    
    public func setIsMuted(action: PresentationGroupCallMuteAction) {
        if self.isMutedValue == action {
            return
        }
        if let muteState = self.stateValue.muteState, !muteState.canUnmute {
            return
        }
        self.isMutedValue = action
        self.isMutedPromise.set(self.isMutedValue)
        let isEffectivelyMuted: Bool
        switch self.isMutedValue {
        case let .muted(isPushToTalkActive):
            isEffectivelyMuted = !isPushToTalkActive
            self.updateMuteState(peerId: self.account.peerId, isMuted: true)
        case .unmuted:
            isEffectivelyMuted = false
            self.updateMuteState(peerId: self.account.peerId, isMuted: false)
        }
        self.callContext?.setIsMuted(isEffectivelyMuted)
        
        if isEffectivelyMuted {
            self.stateValue.muteState = GroupCallParticipantsContext.Participant.MuteState(canUnmute: true)
        } else {
            self.stateValue.muteState = nil
        }
    }
    
    
    public func updateMuteState(peerId: PeerId, isMuted: Bool) {
        let canThenUnmute: Bool
        if isMuted {
            if peerId == self.account.peerId {
                canThenUnmute = true
            } else if self.stateValue.canManageCall {
                if self.stateValue.adminIds.contains(peerId) {
                    canThenUnmute = true
                } else {
                    canThenUnmute = false
                }
            } else if self.stateValue.adminIds.contains(self.account.peerId) {
                canThenUnmute = true
            } else {
                canThenUnmute = true
            }
            self.participantsContext?.updateMuteState(peerId: peerId, muteState: isMuted ? GroupCallParticipantsContext.Participant.MuteState(canUnmute: canThenUnmute) : nil)
        } else {
            if peerId == self.account.peerId {
                self.participantsContext?.updateMuteState(peerId: peerId, muteState: nil)
            } else {
                self.participantsContext?.updateMuteState(peerId: peerId, muteState: GroupCallParticipantsContext.Participant.MuteState(canUnmute: true))
            }
        }
    }
    
    private func requestCall() {
        self.callContext?.stop()
        self.callContext = nil
        
        self.internalState = .requesting
        self.isCurrentlyConnecting = nil
        
        enum CallError {
            case generic
        }
        
        let account = self.account
        let peerId = self.peerId
        
        let currentCall: Signal<GroupCallInfo?, CallError>
        if let initialCall = self.initialCall {
            currentCall = getCurrentGroupCall(account: account, callId: initialCall.id, accessHash: initialCall.accessHash)
            |> mapError { _ -> CallError in
                return .generic
            }
            |> map { summary -> GroupCallInfo? in
                return summary?.info
            }
        } else {
            currentCall = .single(nil)
        }
        
        let currentOrRequestedCall = currentCall
        |> mapToSignal { callInfo -> Signal<GroupCallInfo, CallError> in
            if let callInfo = callInfo {
                return .single(callInfo)
            } else {
                return createGroupCall(account: account, peerId: peerId)
                |> mapError { _ -> CallError in
                    return .generic
                }
            }
        }
        
        /*let restartedCall = currentOrRequestedCall
        |> mapToSignal { value -> Signal<GroupCallInfo, CallError> in
            let stopped: Signal<GroupCallInfo, CallError> = stopGroupCall(account: account, callId: value.id, accessHash: value.accessHash)
            |> mapError { _ -> CallError in
                return .generic
            }
            |> map { _ -> GroupCallInfo in
            }
                
            return stopped
            |> then(currentOrRequestedCall)
        }*/
        
        self.requestDisposable.set((currentOrRequestedCall
        |> deliverOnMainQueue).start(next: { [weak self] value in
            guard let strongSelf = self else {
                return
            }
            strongSelf.updateSessionState(internalState: .active(value))
        }))
    }
    
    public func invitePeer(_ peerId: PeerId) {
        guard case let .estabilished(callInfo, _, _, _) = self.internalState, !self.invitedPeersValue.contains(peerId) else {
            return
        }

        var updatedInvitedPeers = self.invitedPeersValue
        updatedInvitedPeers.insert(peerId)
        self.invitedPeersValue = updatedInvitedPeers
        
        let _ = inviteToGroupCall(account: self.account, callId: callInfo.id, accessHash: callInfo.accessHash, peerId: peerId).start()
    }
    
    private var currentMyAudioLevel: Float = 0.0
      private var currentMyAudioLevelTimestamp: Double = 0.0
      private var isSendingTyping: Bool = false
      
      private func restartMyAudioLevelTimer() {
          self.myAudioLevelTimer?.invalidate()
          let myAudioLevelTimer = SwiftSignalKit.Timer(timeout: 0.1, repeat: false, completion: { [weak self] in
              guard let strongSelf = self else {
                  return
              }
              strongSelf.myAudioLevelTimer = nil
              
              let timestamp = CACurrentMediaTime()
              
              var shouldBeSendingTyping = false
              if strongSelf.currentMyAudioLevel > 0.01 && timestamp < strongSelf.currentMyAudioLevelTimestamp + 1.0 {
                  strongSelf.restartMyAudioLevelTimer()
                  shouldBeSendingTyping = true
              } else {
                  if timestamp < strongSelf.currentMyAudioLevelTimestamp + 1.0 {
                      strongSelf.restartMyAudioLevelTimer()
                      shouldBeSendingTyping = true
                  }
              }
              if shouldBeSendingTyping != strongSelf.isSendingTyping {
                  strongSelf.isSendingTyping = shouldBeSendingTyping
                  if shouldBeSendingTyping {
                    strongSelf.typingDisposable.set(strongSelf.account.acquireLocalInputActivity(peerId: PeerActivitySpace(peerId: strongSelf.peerId, category: .voiceChat), activity: .speakingInGroupCall(timestamp: 0)))
                    strongSelf.restartMyAudioLevelTimer()
                  } else {
                      strongSelf.typingDisposable.set(nil)
                  }
              }
          }, queue: .mainQueue())
          self.myAudioLevelTimer = myAudioLevelTimer
          myAudioLevelTimer.start()
      }
      
      private func processMyAudioLevel(level: Float) {
          self.currentMyAudioLevel = level
          
          if level > 0.01 {
              self.currentMyAudioLevelTimestamp = CACurrentMediaTime()
              
              if self.myAudioLevelTimer == nil {
                  self.restartMyAudioLevelTimer()
              }
          }
      }
    func updateDefaultParticipantsAreMuted(isMuted: Bool) {
        self.participantsContext?.updateDefaultParticipantsAreMuted(isMuted: isMuted)
        self.stateValue.defaultParticipantMuteState = isMuted ? .muted : .unmuted
    }

}

func requestOrJoinGroupCall(context: AccountContext, peerId: PeerId, initialCall: CachedChannelData.ActiveCall?) -> Signal<RequestOrJoinGroupCallResult, NoError> {
    let signal: Signal<Bool, NoError> = requestMicrophonePermission()
    let sharedContext = context.sharedContext
    let accounts = context.sharedContext.activeAccounts |> take(1)
    let account = context.account
    
    return combineLatest(queue: .mainQueue(), signal, accounts, account.postbox.loadedPeerWithId(peerId)) |> mapToSignal { micro, accounts, peer in
        if let context = sharedContext.bindings.groupCall(), context.call.peerId == peerId {
            return .single(.samePeer(context))
        } else {
            var confirmation:Signal<Bool, NoError> = .single(true)
            if sharedContext.hasActiveCall {
                confirmation = confirmSignal(for: mainWindow, header: L10n.callConfirmDiscardCurrentHeader1, information: L10n.callConfirmDiscardCurrentDescription1, okTitle: L10n.modalYes, cancelTitle: L10n.modalCancel)
            }
            return confirmation |> filter { $0 } |> map { _ in
                return sharedContext.bindings.groupCall()?.close()
            } |> map { _ in
                return .success(startGroupCall(context: context, peerId: peerId, initialCall: initialCall, peer: peer))
            }
        }
    }
    
}


private func startGroupCall(context: AccountContext, peerId: PeerId, initialCall: CachedChannelData.ActiveCall?, internalId: CallSessionInternalId = CallSessionInternalId(), peer: Peer? = nil) -> GroupCallContext {
    return GroupCallContext(call: PresentationGroupCallImpl(
        account: context.account,
        sharedContext: context.sharedContext,
        internalId: internalId, initialCall: initialCall,
        peerId: peerId,
        peer: peer
    ), peerMemberContextsManager: context.peerChannelMemberCategoriesContextsManager)
}





/*
 

 public func requestOrJoinGroupCall(context: AccountContext, peerId: PeerId) -> RequestOrJoinGroupCallResult {
     if let currentGroupCall = self.currentGroupCallValue {
         return .alreadyInProgress(currentGroupCall.peerId)
     }
     let _ = self.startGroupCall(accountContext: context, peerId: peerId).start()
     return .requested
 }
 

 */
