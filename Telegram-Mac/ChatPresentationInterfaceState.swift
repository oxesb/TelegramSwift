//
//  ChatPresentationInterfaceState.swift
//  Telegram-Mac
//
//  Created by keepcoder on 01/10/2016.
//  Copyright © 2016 Telegram. All rights reserved.
//

import Cocoa
import OpusBinding
import Postbox
import TelegramCore
import SyncCore
import TGUIKit
import SwiftSignalKit

enum ChatPresentationInputContext {
    case none
    case hashtag
    case mention
    case botCommand
    case emoji
}

enum RestrictedMediaType {
    case stickers
    case media
    
}

final class ChatPinnedMessage: Equatable {
    let messageId: MessageId
    let message: Message?
    let isLatest: Bool
    let index: Int
    let totalCount: Int
    let others:[MessageId]
    init(messageId: MessageId, message: Message?, others: [MessageId] = [], isLatest: Bool, index:Int = 0, totalCount: Int = 1) {
        self.messageId = messageId
        self.message = message
        self.others = others
        self.isLatest = isLatest
        self.index = index
        self.totalCount = totalCount
    }
    
    static func ==(lhs: ChatPinnedMessage, rhs: ChatPinnedMessage) -> Bool {
        if lhs === rhs {
            return true
        }
        if lhs.messageId != rhs.messageId {
            return false
        }
        if lhs.message?.id != rhs.message?.id {
            return false
        }
        if lhs.message?.stableVersion != rhs.message?.stableVersion {
            return false
        }
        if lhs.isLatest != rhs.isLatest {
            return false
        }
        if lhs.index != rhs.index {
            return false
        }
        if lhs.totalCount != rhs.totalCount {
            return false
        }
        return true
    }
}


struct GroupCallPanelData : Equatable {
    let peerId: PeerId
    let info: GroupCallInfo
    let topParticipants: [GroupCallParticipantsContext.Participant]
    let participantCount: Int
    let numberOfActiveSpeakers: Int
    private(set) weak var groupCall: GroupCallContext?
    init(
        peerId: PeerId,
        info: GroupCallInfo,
        topParticipants: [GroupCallParticipantsContext.Participant],
        participantCount: Int,
        numberOfActiveSpeakers: Int,
        groupCall: GroupCallContext?
    ) {
        self.peerId = peerId
        self.info = info
        self.topParticipants = topParticipants
        self.participantCount = participantCount
        self.numberOfActiveSpeakers = numberOfActiveSpeakers
        self.groupCall = groupCall
    }
    
    static func ==(lhs: GroupCallPanelData, rhs: GroupCallPanelData) -> Bool {
        if lhs.peerId != rhs.peerId {
            return false
        }
        if lhs.info != rhs.info {
            return false
        }
        if lhs.topParticipants != rhs.topParticipants {
            return false
        }
        if lhs.numberOfActiveSpeakers != rhs.numberOfActiveSpeakers {
            return false
        }
        if (lhs.groupCall != nil) != (rhs.groupCall != nil) {
            return false
        }
        return true
    }
}



enum ChatPresentationInputQuery: Equatable {
    case none
    case hashtag(String)
    case mention(query: String, includeRecent: Bool)
    case command(String)
    case contextRequest(addressName: String, query: String)
    case emoji(String, firstWord: Bool)
    case stickers(String)
}


struct ChatActiveGroupCallInfo: Equatable {
    var activeCall: CachedChannelData.ActiveCall
    let data: GroupCallPanelData?
    
    func withUpdatedData(_ data: GroupCallPanelData?) -> ChatActiveGroupCallInfo {
        return ChatActiveGroupCallInfo(activeCall: self.activeCall, data: data)
    }
    func withUpdatedActiveCall(_ activeCall: CachedChannelData.ActiveCall) -> ChatActiveGroupCallInfo {
        return ChatActiveGroupCallInfo(activeCall: activeCall, data: self.data)
    }
}



enum ChatRecordingStatus : Equatable {
    case paused
    case recording(duration: Double)
}


class ChatRecordingState : Equatable {
  
    let autohold: Bool
    let holdpromise: ValuePromise<Bool> = ValuePromise()
    init(autohold: Bool) {
        self.autohold = autohold
        holdpromise.set(autohold)
    }
    
    var micLevel: Signal<Float, NoError> {
        return .complete()
    }
    var status: Signal<ChatRecordingStatus, NoError> {
        return .complete()
    }
    var data:Signal<[MediaSenderContainer], NoError>  {
        return .complete()
    }
    
    func start() {
        
    }
    func stop() {
        
    }
    func dispose() {
        
    }
    
    deinit {
        var bp:Int = 0
        bp += 1
    }
}

func ==(lhs:ChatRecordingState, rhs:ChatRecordingState) -> Bool {
    return lhs === rhs
}

final class ChatRecordingVideoState : ChatRecordingState {
    let pipeline: VideoRecorderPipeline
    private let path: String
    init(account: Account, liveUpload:Bool, autohold: Bool) {
        let id:Int64 = arc4random64()
        self.path = NSTemporaryDirectory() + "video_message\(id).mp4"
        self.pipeline = VideoRecorderPipeline(url: URL(fileURLWithPath: path), liveUploading: liveUpload ? PreUploadManager(path, account: account, id: id) : nil)
        super.init(autohold: autohold)
    }
    
    override var micLevel: Signal<Float, NoError> {
        return pipeline.powerAndDuration.get() |> map {$0.0}
    }
    
    override var status: Signal<ChatRecordingStatus, NoError> {
        return pipeline.powerAndDuration.get() |> map { .recording(duration: $0.1) }
    }
    
    override var data: Signal<[MediaSenderContainer], NoError> {
        return pipeline.statePromise.get() |> filter { state in
            switch state {
            case .finishRecording:
                return true
            default:
                return false
            }
        } |> take(1) |> map { state in
            switch state {
            case let .finishRecording(path, duration, id, _):
                return [VideoMessageSenderContainer(path: path, duration: duration, size: CGSize(width: 200, height: 200), id: id)]
            default:
                return []
            }
        }
    }
    
    override func start() {
        pipeline.start()
    }
    override func stop() {
        pipeline.stop()
    }
    override func dispose() {
        pipeline.dispose()
    }
}

final class ChatRecordingAudioState : ChatRecordingState {
    private let recorder:ManagedAudioRecorder

    
    override var micLevel: Signal<Float, NoError> {
        return recorder.micLevel
    }
    
    override var status: Signal<ChatRecordingStatus, NoError> {
        return recorder.recordingState |> map { state in
            switch state {
            case .paused:
                return .paused
            case let .recording(duration, _):
                return .recording(duration: duration)
            }
        }
    }
    
    override var data: Signal<[MediaSenderContainer], NoError> {
        return recorder.takenRecordedData() |> map { value in
            if let value = value, value.duration > 0.5 {
                return [VoiceSenderContainer(data: value, id: value.id)]
            }
            return []
        }
    }
    
    var recordingState: Signal<AudioRecordingState, NoError> {
        return recorder.recordingState
    }
    
    
    
    init(account: Account, liveUpload: Bool, autohold: Bool) {
        let id = arc4random64()
        let path = NSTemporaryDirectory() + "voice_message\(id).ogg"
        let uploadManager:PreUploadManager? = liveUpload ? PreUploadManager(path, account: account, id: id) : nil
        let dataItem = DataItem(path: path)
        recorder = ManagedAudioRecorder(liveUploading: uploadManager, dataItem: dataItem)
        super.init(autohold: autohold)
    }
    
    
    
    override func start() {
        recorder.start()
    }
    
    override func stop() {
        recorder.stop()
    }
    
    override func dispose() {
        recorder.stop()
        _ = data.start(next: { data in
            for container in data {
               // try? FileManager.default.removeItem(atPath: container.path)
            }
        })
    }
    
    
    deinit {
        recorder.stop()
    }
}



enum ChatState : Equatable {
    case normal
    case selecting
    case block(String)
    case action(String, (ChatInteraction)->Void)
    case channelWithDiscussion(discussionGroupId: PeerId?, leftAction: String, rightAction: String)
    case editing
    case recording(ChatRecordingState)
    case restricted(String)
}

func ==(lhs:ChatState, rhs:ChatState) -> Bool {
    switch lhs {
    case .normal:
        if case .normal = rhs {
            return true
        } else {
            return false
        }
    case let .channelWithDiscussion(discussionGroupId, leftAction, rightAction):
        if case .channelWithDiscussion(discussionGroupId, leftAction, rightAction) = rhs {
            return true
        } else {
            return false
        }
    case .selecting:
        if case .selecting = rhs {
            return true
        } else {
            return false
        }
    case .editing:
        if case .editing = rhs {
            return true
        } else {
            return false
        }
    case .recording:
        if case .recording = rhs {
            return true
        } else {
            return false
        }
    case let .block(lhsReason):
        if case let .block(rhsReason) = rhs {
            return lhsReason == rhsReason
        } else {
            return false
        }
    case let .action(lhsAction,_):
        if case let .action(rhsAction,_) = rhs {
            return lhsAction == rhsAction
        } else {
            return false
        }
    case .restricted(let text):
        if case .restricted(text) = rhs {
            return true
        } else {
            return false
        }
    }
}

struct ChatPeerStatus : Equatable {
    let canAddContact: Bool
    let peerStatusSettings: PeerStatusSettings?
    init(canAddContact: Bool, peerStatusSettings: PeerStatusSettings?) {
        self.canAddContact = canAddContact
        self.peerStatusSettings = peerStatusSettings
    }
}

struct SlowMode : Equatable {
    let validUntil: Int32?
    let timeout: Int32?
    let sendingIds: [MessageId]
    init(validUntil: Int32? = nil, timeout: Int32? = nil, sendingIds: [MessageId] = []) {
        self.validUntil = validUntil
        self.timeout = timeout
        self.sendingIds = sendingIds
    }
    func withUpdatedValidUntil(_ validUntil: Int32?) -> SlowMode {
        return SlowMode(validUntil: validUntil, timeout: self.timeout, sendingIds: self.sendingIds)
    }
    func withUpdatedTimeout(_ timeout: Int32?) -> SlowMode {
        return SlowMode(validUntil: self.validUntil, timeout: timeout, sendingIds: self.sendingIds)
    }
    func withUpdatedSendingIds(_ sendingIds: [MessageId]) -> SlowMode {
        return SlowMode(validUntil: self.validUntil, timeout: self.timeout, sendingIds: sendingIds)
    }
    
    var hasLocked: Bool {
        return timeout != nil || !sendingIds.isEmpty
    }
    
    var sendingLocked: Bool {
        return timeout != nil
    }
    
    var errorText: String? {
        if let timeout = timeout {
            return slowModeTooltipText(timeout)
        } else if !sendingIds.isEmpty {
            return L10n.slowModeMultipleError
        } else {
            return nil
        }
    }
}

struct ChatPresentationInterfaceState: Equatable {
    let interfaceState: ChatInterfaceState
    let peer: Peer?
    let mainPeer: Peer?
    let chatLocation: ChatLocation
    let chatMode: ChatMode
    let isSearchMode:(Bool, Peer?, String?)
    let notificationSettings: TelegramPeerNotificationSettings?
    let inputQueryResult: ChatPresentationInputQueryResult?
    let keyboardButtonsMessage: Message?
    let initialAction:ChatInitialAction?
    let historyCount:Int?
    let isBlocked:Bool?
    let recordingState:ChatRecordingState?
    let peerStatus:ChatPeerStatus?
    let pinnedMessageId:ChatPinnedMessage?
    let urlPreview: (String, TelegramMediaWebpage)?
    let selectionState: ChatInterfaceSelectionState?
    let limitConfiguration: LimitsConfiguration
   
    let sidebarEnabled:Bool?
    let sidebarShown:Bool?
    let layout:SplitViewState?
    let discussionGroupId: CachedChannelData.LinkedDiscussionPeerId
    let canAddContact:Bool?
    let isEmojiSection: Bool
    let canInvokeBasicActions:(delete: Bool, forward: Bool)
    let isNotAccessible: Bool
    let hasScheduled: Bool
    let slowMode: SlowMode?
    let failedMessageIds:Set<MessageId>
    let hidePinnedMessage: Bool
    let canPinMessage: Bool
    let tempPinnedMaxId: MessageId?
    let restrictionInfo: PeerAccessRestrictionInfo?
    let groupCall: ChatActiveGroupCallInfo?
    var inputContext: ChatPresentationInputQuery {
        return inputContextQueryForChatPresentationIntefaceState(self, includeContext: true)
    }
    
    var isKeyboardActive:Bool {
        guard let reply = keyboardButtonsMessage?.replyMarkup else {
            return false
        }
        
        return reply.rows.count > 0
    }
    
    var canPinMessageInPeer: Bool {
        if let peer = peer as? TelegramChannel, peer.hasPermission(.pinMessages) || (peer.isChannel && peer.hasPermission(.editAllMessages)) {
            return true
        } else if let peer = peer as? TelegramGroup, peer.canPinMessage {
            return true
        } else if let _ = peer as? TelegramSecretChat {
            return false
        } else {
            return canPinMessage
        }
    }
    
    var state:ChatState {
        if self.selectionState == nil {
            
            if let recordingState = recordingState {
                return .recording(recordingState)
            }
            
            if self.interfaceState.editState != nil {
                return .editing
            }
            
            switch chatMode {
            case .pinned:
                if canPinMessageInPeer {
                    return .action(L10n.chatPinnedUnpinAllCountable(pinnedMessageId?.totalCount ?? 0), { chatInteraction in
                        let navigation = chatInteraction.context.sharedContext.bindings.rootNavigation()
                        (navigation.previousController as? ChatController)?.chatInteraction.unpinAllMessages()
                    })
                } else {
                    return .action(L10n.chatPinnedDontShow, { chatInteraction in
                        let navigation = chatInteraction.context.sharedContext.bindings.rootNavigation()
                        (navigation.previousController as? ChatController)?.chatInteraction.unpinAllMessages()
                    })
                }
                
            default:
                break
            }
            
            if let peer = peer as? TelegramChannel {
                #if APP_STORE
                if let restrictionInfo = restrictionInfo {
                    for rule in restrictionInfo.rules {
                        if rule.platform == "ios" || rule.platform == "all" {
                            return .action(L10n.chatInputClose, { chatInteraction in
                                chatInteraction.context.sharedContext.bindings.rootNavigation().back()
                            })
                        }
                    }
                }
                #endif
                
                switch chatMode {
                case .replyThread:
                    if let permissionText = permissionText(from: peer, for: .banSendMessages) {
                        return .restricted(permissionText)
                    } else if peer.participationStatus == .left {
                        return .normal
                    } else if peer.participationStatus == .kicked {
                        return .restricted(L10n.chatCommentsKicked)
                    } else if peer.participationStatus == .member {
                        return .normal
                    }
                default:
                    break
                }
                
                
                
                if peer.participationStatus == .left {
                    return .action(L10n.chatInputJoin, { chatInteraction in
                        chatInteraction.joinChannel()
                    })
                } else if peer.participationStatus == .kicked {
                    return .action(L10n.chatInputDelete, { chatInteraction in
                        chatInteraction.removeAndCloseChat()
                    })
                } else if let permissionText = permissionText(from: peer, for: .banSendMessages) {
                    return .restricted(permissionText)
                } else if !peer.canSendMessage(chatMode.isThreadMode), let notificationSettings = notificationSettings {
                    return .action(notificationSettings.isMuted ? L10n.chatInputUnmute : L10n.chatInputMute, { chatInteraction in
                        chatInteraction.toggleNotifications(nil)
                    })
                }
            } else if let peer = peer as? TelegramGroup {
                if  peer.membership == .Left {
                    return .action(L10n.chatInputReturn,{ chatInteraction in
                        chatInteraction.returnGroup()
                    })
                } else if peer.membership == .Removed {
                    return .action(L10n.chatInputDelete, { chatInteraction in
                        chatInteraction.removeAndCloseChat()
                    })
                }
            } else if let peer = peer as? TelegramSecretChat, let mainPeer = mainPeer {
                
                switch peer.embeddedState {
                case .terminated:
                    return .action(L10n.chatInputDelete, { chatInteraction in
                        chatInteraction.removeAndCloseChat()
                    })
                case .handshake:
                    return .restricted(L10n.chatInputSecretChatWaitingToUserOnline(mainPeer.compactDisplayTitle))
                default:
                    break
                }
            }
            
            if let peer = peer, !peer.canSendMessage(chatMode.isThreadMode), let notificationSettings = notificationSettings {
                return .action(notificationSettings.isMuted ? L10n.chatInputUnmute : L10n.chatInputMute, { chatInteraction in
                    chatInteraction.toggleNotifications(nil)
                })
            }
            
            if let blocked = isBlocked, blocked {
                
                if let peer = peer, peer.isBot {
                    return .action(L10n.chatInputRestart, { chatInteraction in
                        chatInteraction.unblock()
                        chatInteraction.startBot()
                    })
                }
                
                return .action(tr(L10n.chatInputUnblock), { chatInteraction in
                    chatInteraction.unblock()
                })
            }
            
            if let peer = peer, let permissionText = permissionText(from: peer, for: .banSendMessages) {
                return .restricted(permissionText)
            }
            

           

            if let initialAction = initialAction, case .start(_) = initialAction  {
                return .action(tr(L10n.chatInputStartBot), { chatInteraction in
                    chatInteraction.invokeInitialAction()
                })
            }
            
            if let peer = peer as? TelegramUser {
                
                if peer.botInfo != nil, let historyCount = historyCount, historyCount == 0 {
                    return .action(tr(L10n.chatInputStartBot), { chatInteraction in
                        chatInteraction.startBot()
                    })
                }
            }
           
            
            return .normal
        } else {
            return .selecting
        }
    }
    
    var messageSecretTimeout: Int32? {
        return (peer as? TelegramSecretChat)?.messageAutoremoveTimeout
    }
    
    var isKeyboardShown:Bool {
        if let keyboard = keyboardButtonsMessage, let attribute = keyboard.replyMarkup {
            return interfaceState.messageActionsState.closedButtonKeyboardMessageId != keyboard.id && attribute.hasButtons && state == .normal

        }
        return false
    }
    
    var isShowSidebar: Bool {
        if let sidebarEnabled = sidebarEnabled, let peer = peer, let sidebarShown = sidebarShown, let layout = layout {
            return sidebarEnabled && peer.canSendMessage(chatMode.isThreadMode) && sidebarShown && layout == .dual
        }
        return false
    }
    
    var slowModeMultipleLocked: Bool {
        if let _ = self.slowMode {
            
            var keys:[Int64:Int64] = [:]
            var forwardMessages:[Message] = []
            for message in self.interfaceState.forwardMessages {
                if let groupingKey = message.groupingKey {
                    if keys[groupingKey] == nil {
                        keys[groupingKey] = groupingKey
                        forwardMessages.append(message)
                    }
                } else {
                    forwardMessages.append(message)
                }
            }
            if forwardMessages.count > 1 || (!effectiveInput.inputText.isEmpty && forwardMessages.count == 1) {
                return true
            } else if effectiveInput.inputText.length > 4096 {
                return true
            }
        }
        return false
    }
    
    var slowModeErrorText: String? {
        if let slowMode = self.slowMode, slowMode.hasLocked {
            return slowMode.errorText
        } else if slowModeMultipleLocked {
            if effectiveInput.inputText.length > 4096 {
                return L10n.slowModeTooLongError
            }
            return L10n.slowModeForwardCommentError
        } else {
            return nil
        }
    }
    
    var abilityToSend:Bool {
        if state == .normal {
            if let slowMode = self.slowMode {
                if slowMode.hasLocked {
                    return false
                } else if self.slowModeMultipleLocked {
                    return false
                }
            }
            return (!effectiveInput.inputText.isEmpty || !interfaceState.forwardMessageIds.isEmpty)
        } else if let editState = interfaceState.editState {
            if editState.message.media.count == 0 {
                return !effectiveInput.inputText.isEmpty
            } else {
                for media in editState.message.media {
                    if !(media is TelegramMediaWebpage) {
                        return true
                    }
                }
                return !effectiveInput.inputText.isEmpty
            }
        }
        
        return false
    }
    
    static let maxInput:Int32 = 50000
    static let maxShortInput:Int32 = 1024
    static let textLimit: Int32 = 4096
    var maxInputCharacters:Int32 {
        if state == .normal {
            return ChatPresentationInterfaceState.maxInput
        } else if let editState = interfaceState.editState {
            if editState.message.media.count == 0 {
                return ChatPresentationInterfaceState.textLimit
            } else {
                for media in editState.message.media {
                    if !(media is TelegramMediaWebpage) {
                        return ChatPresentationInterfaceState.maxShortInput
                    }
                }
                return ChatPresentationInterfaceState.textLimit
            }
        }
        
        return ChatPresentationInterfaceState.maxInput
    }
    
    var effectiveInput:ChatTextInputState {
        if let editState = interfaceState.editState {
            return editState.inputState
        } else {
            return interfaceState.inputState
        }
    }
    
    init(chatLocation: ChatLocation, chatMode: ChatMode) {
        self.interfaceState = ChatInterfaceState()
        self.peer = nil
        self.notificationSettings = nil
        self.inputQueryResult = nil
        self.keyboardButtonsMessage = nil
        self.initialAction = nil
        self.historyCount = 0
        self.isSearchMode = (false, nil, nil)
        self.recordingState = nil
        self.isBlocked = nil
        self.peerStatus = nil
        self.pinnedMessageId = nil
        self.urlPreview = nil
        self.selectionState = nil
        self.sidebarEnabled = nil
        self.sidebarShown = nil
        self.layout = nil
        self.canAddContact = nil
        self.isEmojiSection = FastSettings.entertainmentState == .emoji
        self.chatLocation = chatLocation
        self.chatMode = chatMode
        self.canInvokeBasicActions = (delete: false, forward: false)
        self.isNotAccessible = false
        self.restrictionInfo = nil
        self.mainPeer = nil
        self.limitConfiguration = LimitsConfiguration.defaultValue
        self.discussionGroupId = .unknown
        self.slowMode = nil
        self.hasScheduled = false
        self.failedMessageIds = Set()
        self.hidePinnedMessage = false
        self.canPinMessage = false
        self.tempPinnedMaxId = nil
        self.groupCall = nil
    }
    
    init(interfaceState: ChatInterfaceState, peer: Peer?, notificationSettings:TelegramPeerNotificationSettings?, inputQueryResult: ChatPresentationInputQueryResult?, keyboardButtonsMessage:Message?, initialAction:ChatInitialAction?, historyCount:Int?, isSearchMode:(Bool, Peer?, String?), recordingState: ChatRecordingState?, isBlocked:Bool?, peerStatus: ChatPeerStatus?, pinnedMessageId:ChatPinnedMessage?, urlPreview: (String, TelegramMediaWebpage)?, selectionState: ChatInterfaceSelectionState?, sidebarEnabled: Bool?, sidebarShown: Bool?, layout:SplitViewState?, canAddContact:Bool?, isEmojiSection: Bool, chatLocation: ChatLocation, chatMode: ChatMode, canInvokeBasicActions: (delete: Bool, forward: Bool), isNotAccessible: Bool, restrictionInfo: PeerAccessRestrictionInfo?, mainPeer: Peer?, limitConfiguration: LimitsConfiguration, discussionGroupId: CachedChannelData.LinkedDiscussionPeerId, slowMode: SlowMode?, hasScheduled: Bool, failedMessageIds: Set<MessageId>, hidePinnedMessage: Bool, canPinMessage: Bool, tempPinnedMaxId: MessageId?, groupCall: ChatActiveGroupCallInfo?) {
        self.interfaceState = interfaceState
        self.peer = peer
        self.notificationSettings = notificationSettings
        self.inputQueryResult = inputQueryResult
        self.keyboardButtonsMessage = keyboardButtonsMessage
        self.initialAction = initialAction
        self.historyCount = historyCount
        self.isSearchMode = isSearchMode
        self.recordingState = recordingState
        self.isBlocked = isBlocked
        self.peerStatus = peerStatus
        self.pinnedMessageId = pinnedMessageId
        self.urlPreview = urlPreview
        self.selectionState = selectionState
        self.sidebarEnabled = sidebarEnabled
        self.sidebarShown = sidebarShown
        self.layout = layout
        self.canAddContact = canAddContact
        self.isEmojiSection = isEmojiSection
        self.chatLocation = chatLocation
        self.canInvokeBasicActions = canInvokeBasicActions
        self.isNotAccessible = isNotAccessible
        self.restrictionInfo = restrictionInfo
        self.mainPeer = mainPeer
        self.limitConfiguration = limitConfiguration
        self.discussionGroupId = discussionGroupId
        self.slowMode = slowMode
        self.hasScheduled = hasScheduled
        self.failedMessageIds = failedMessageIds
        self.chatMode = chatMode
        self.hidePinnedMessage = hidePinnedMessage
        self.canPinMessage = canPinMessage
        self.tempPinnedMaxId = tempPinnedMaxId
        self.groupCall = groupCall
    }
    
    static func ==(lhs: ChatPresentationInterfaceState, rhs: ChatPresentationInterfaceState) -> Bool {
        if lhs.interfaceState != rhs.interfaceState {
            return false
        }
        if lhs.discussionGroupId != rhs.discussionGroupId {
            return false
        }
        if let lhsPeer = lhs.peer, let rhsPeer = rhs.peer {
            if !lhsPeer.isEqual(rhsPeer) {
                return false
            }
        } else if (lhs.peer == nil) != (rhs.peer == nil) {
            return false
        }
        
        if let lhsPeer = lhs.mainPeer, let rhsPeer = rhs.mainPeer {
            if !lhsPeer.isEqual(rhsPeer) {
                return false
            }
        } else if (lhs.mainPeer == nil) != (rhs.mainPeer == nil) {
            return false
        }
        if lhs.tempPinnedMaxId != rhs.tempPinnedMaxId {
            return false
        }
        
        if lhs.restrictionInfo != rhs.restrictionInfo {
            return false
        }
        if lhs.limitConfiguration != rhs.limitConfiguration {
            return false
        }
        
        if lhs.chatLocation != rhs.chatLocation {
            return false
        }
        if lhs.hasScheduled != rhs.hasScheduled {
            return false
        }
        if lhs.chatMode != rhs.chatMode {
            return false
        }
        if lhs.canPinMessage != rhs.canPinMessage {
            return false
        }
        if lhs.hidePinnedMessage != rhs.hidePinnedMessage {
            return false
        }
        if lhs.state != rhs.state {
            return false
        }
        if lhs.slowMode != rhs.slowMode {
            return false
        }
        if lhs.isSearchMode.0 != rhs.isSearchMode.0 {
            return false
        }
        if lhs.sidebarEnabled != rhs.sidebarEnabled {
            return false
        }
        if lhs.sidebarShown != rhs.sidebarShown {
            return false
        }
        if lhs.layout != rhs.layout {
            return false
        }
        if lhs.canAddContact != rhs.canAddContact {
            return false
        }
        
        if lhs.recordingState != rhs.recordingState {
            return false
        }
        
        if lhs.inputQueryResult != rhs.inputQueryResult {
            return false
        }
        
        if lhs.initialAction != rhs.initialAction {
            return false
        }
        
        if lhs.historyCount != rhs.historyCount {
            return false
        }
        
        if lhs.isBlocked != rhs.isBlocked {
            return false
        }
        
        if lhs.peerStatus != rhs.peerStatus {
            return false
        }
        if lhs.isNotAccessible != rhs.isNotAccessible {
            return false
        }
        
        if lhs.selectionState != rhs.selectionState {
            return false
        }
        
        if lhs.groupCall != rhs.groupCall {
            return false
        }
        
        if lhs.pinnedMessageId != rhs.pinnedMessageId {
            return false
        }
        if lhs.isEmojiSection != rhs.isEmojiSection {
            return false
        }
        if lhs.failedMessageIds != rhs.failedMessageIds {
            return false
        }
        
        if let lhsUrlPreview = lhs.urlPreview, let rhsUrlPreview = rhs.urlPreview {
            if lhsUrlPreview.0 != rhsUrlPreview.0 {
                return false
            }
            if !lhsUrlPreview.1.isEqual(to: rhsUrlPreview.1) {
                return false
            }
        } else if (lhs.urlPreview != nil) != (rhs.urlPreview != nil) {
            return false
        }
        
        if let lhsMessage = lhs.keyboardButtonsMessage, let rhsMessage = rhs.keyboardButtonsMessage {
            if  lhsMessage.id != rhsMessage.id || lhsMessage.stableVersion != rhsMessage.stableVersion {
                return false
            }
        } else if (lhs.keyboardButtonsMessage == nil) != (rhs.keyboardButtonsMessage == nil) {
            return false
        }
        
        if lhs.inputContext != rhs.inputContext {
            return false
        }
        if lhs.canInvokeBasicActions != rhs.canInvokeBasicActions {
            return false
        }
        return true
    }
    
    func updatedInterfaceState(_ f: (ChatInterfaceState) -> ChatInterfaceState) -> ChatPresentationInterfaceState {
        return ChatPresentationInterfaceState(interfaceState: f(self.interfaceState), peer: self.peer, notificationSettings: self.notificationSettings, inputQueryResult: self.inputQueryResult, keyboardButtonsMessage:self.keyboardButtonsMessage, initialAction:self.initialAction, historyCount: self.historyCount, isSearchMode: self.isSearchMode, recordingState: self.recordingState, isBlocked: self.isBlocked, peerStatus: self.peerStatus, pinnedMessageId: self.pinnedMessageId, urlPreview: self.urlPreview, selectionState: self.selectionState, sidebarEnabled: self.sidebarEnabled, sidebarShown: self.sidebarShown, layout: self.layout, canAddContact: self.canAddContact, isEmojiSection: self.isEmojiSection, chatLocation: self.chatLocation, chatMode: self.chatMode, canInvokeBasicActions: self.canInvokeBasicActions, isNotAccessible: self.isNotAccessible, restrictionInfo: self.restrictionInfo, mainPeer: self.mainPeer, limitConfiguration: self.limitConfiguration, discussionGroupId: self.discussionGroupId, slowMode: self.slowMode, hasScheduled: self.hasScheduled, failedMessageIds: self.failedMessageIds, hidePinnedMessage: self.hidePinnedMessage, canPinMessage: self.canPinMessage, tempPinnedMaxId: self.tempPinnedMaxId, groupCall: self.groupCall)
        
    }
    
    func updatedKeyboardButtonsMessage(_ message: Message?) -> ChatPresentationInterfaceState {
        let interface = ChatPresentationInterfaceState(interfaceState: self.interfaceState, peer: self.peer, notificationSettings: self.notificationSettings, inputQueryResult: self.inputQueryResult, keyboardButtonsMessage:message, initialAction:self.initialAction, historyCount: self.historyCount, isSearchMode: self.isSearchMode, recordingState: self.recordingState, isBlocked: self.isBlocked, peerStatus: self.peerStatus, pinnedMessageId: self.pinnedMessageId, urlPreview: self.urlPreview, selectionState: self.selectionState, sidebarEnabled: self.sidebarEnabled, sidebarShown: self.sidebarShown, layout: self.layout, canAddContact: self.canAddContact, isEmojiSection: self.isEmojiSection, chatLocation: self.chatLocation, chatMode: self.chatMode, canInvokeBasicActions: self.canInvokeBasicActions, isNotAccessible: self.isNotAccessible, restrictionInfo: self.restrictionInfo, mainPeer: self.mainPeer, limitConfiguration: self.limitConfiguration, discussionGroupId: self.discussionGroupId, slowMode: self.slowMode, hasScheduled: self.hasScheduled, failedMessageIds: self.failedMessageIds, hidePinnedMessage: self.hidePinnedMessage, canPinMessage: self.canPinMessage, tempPinnedMaxId: self.tempPinnedMaxId, groupCall: self.groupCall)
        
        if let peerId = peer?.id, let keyboardMessage = interface.keyboardButtonsMessage {
            if keyboardButtonsMessage?.id != keyboardMessage.id || keyboardButtonsMessage?.stableVersion != keyboardMessage.stableVersion {
                if peerId.namespace == Namespaces.Peer.CloudChannel || peerId.namespace == Namespaces.Peer.CloudGroup {
                    return interface.updatedInterfaceState({$0.withUpdatedMessageActionsState({$0.withUpdatedProcessedSetupReplyMessageId(keyboardMessage.id)})})
                }
            }
            
        }
        return interface
    }
    
    func updatedPeer(_ f: (Peer?) -> Peer?) -> ChatPresentationInterfaceState {
        
        let peer = f(self.peer)
        
        var restrictionInfo: PeerAccessRestrictionInfo? = self.restrictionInfo
        if let peer = peer as? TelegramChannel, let info = peer.restrictionInfo {
            restrictionInfo = info
        }
        
        return ChatPresentationInterfaceState(interfaceState: self.interfaceState, peer: peer, notificationSettings: self.notificationSettings, inputQueryResult: self.inputQueryResult, keyboardButtonsMessage:self.keyboardButtonsMessage, initialAction: self.initialAction, historyCount: self.historyCount, isSearchMode: self.isSearchMode, recordingState: self.recordingState, isBlocked: self.isBlocked, peerStatus: self.peerStatus, pinnedMessageId: self.pinnedMessageId, urlPreview: self.urlPreview, selectionState: self.selectionState, sidebarEnabled: self.sidebarEnabled, sidebarShown: self.sidebarShown, layout: self.layout, canAddContact: self.canAddContact, isEmojiSection: self.isEmojiSection, chatLocation: self.chatLocation, chatMode: self.chatMode, canInvokeBasicActions: self.canInvokeBasicActions, isNotAccessible: self.isNotAccessible, restrictionInfo: restrictionInfo, mainPeer: self.mainPeer, limitConfiguration: self.limitConfiguration, discussionGroupId: self.discussionGroupId, slowMode: self.slowMode, hasScheduled: self.hasScheduled, failedMessageIds: self.failedMessageIds, hidePinnedMessage: self.hidePinnedMessage, canPinMessage: self.canPinMessage, tempPinnedMaxId: self.tempPinnedMaxId, groupCall: self.groupCall)
    }
    
    func updatedMainPeer(_ mainPeer: Peer?) -> ChatPresentationInterfaceState {
        return ChatPresentationInterfaceState(interfaceState: self.interfaceState, peer: self.peer, notificationSettings: self.notificationSettings, inputQueryResult: self.inputQueryResult, keyboardButtonsMessage:self.keyboardButtonsMessage, initialAction: self.initialAction, historyCount: self.historyCount, isSearchMode: self.isSearchMode, recordingState: self.recordingState, isBlocked: self.isBlocked, peerStatus: self.peerStatus, pinnedMessageId: self.pinnedMessageId, urlPreview: self.urlPreview, selectionState: self.selectionState, sidebarEnabled: self.sidebarEnabled, sidebarShown: self.sidebarShown, layout: self.layout, canAddContact: self.canAddContact, isEmojiSection: self.isEmojiSection, chatLocation: self.chatLocation, chatMode: self.chatMode, canInvokeBasicActions: self.canInvokeBasicActions, isNotAccessible: self.isNotAccessible, restrictionInfo: restrictionInfo, mainPeer: mainPeer, limitConfiguration: self.limitConfiguration, discussionGroupId: self.discussionGroupId, slowMode: self.slowMode, hasScheduled: self.hasScheduled, failedMessageIds: self.failedMessageIds, hidePinnedMessage: self.hidePinnedMessage, canPinMessage: self.canPinMessage, tempPinnedMaxId: self.tempPinnedMaxId, groupCall: self.groupCall)
    }
    
    func updatedNotificationSettings(_ notificationSettings:TelegramPeerNotificationSettings?) -> ChatPresentationInterfaceState {
        return ChatPresentationInterfaceState(interfaceState: self.interfaceState, peer:self.peer, notificationSettings: notificationSettings, inputQueryResult: self.inputQueryResult, keyboardButtonsMessage:self.keyboardButtonsMessage, initialAction:self.initialAction, historyCount: self.historyCount, isSearchMode: self.isSearchMode, recordingState: self.recordingState, isBlocked: self.isBlocked, peerStatus: self.peerStatus, pinnedMessageId: self.pinnedMessageId, urlPreview: self.urlPreview, selectionState: self.selectionState, sidebarEnabled: self.sidebarEnabled, sidebarShown: self.sidebarShown, layout: self.layout, canAddContact: self.canAddContact, isEmojiSection: self.isEmojiSection, chatLocation: self.chatLocation, chatMode: self.chatMode, canInvokeBasicActions: self.canInvokeBasicActions, isNotAccessible: self.isNotAccessible, restrictionInfo: self.restrictionInfo, mainPeer: self.mainPeer, limitConfiguration: self.limitConfiguration, discussionGroupId: self.discussionGroupId, slowMode: self.slowMode, hasScheduled: self.hasScheduled, failedMessageIds: self.failedMessageIds, hidePinnedMessage: self.hidePinnedMessage, canPinMessage: self.canPinMessage, tempPinnedMaxId: self.tempPinnedMaxId, groupCall: self.groupCall)
    }
    
    
    
    func updatedHistoryCount(_ historyCount:Int?) -> ChatPresentationInterfaceState {
        return ChatPresentationInterfaceState(interfaceState: self.interfaceState, peer:self.peer, notificationSettings: notificationSettings, inputQueryResult: self.inputQueryResult, keyboardButtonsMessage:self.keyboardButtonsMessage, initialAction:self.initialAction, historyCount: historyCount, isSearchMode: self.isSearchMode, recordingState: self.recordingState, isBlocked: self.isBlocked, peerStatus: self.peerStatus, pinnedMessageId: self.pinnedMessageId, urlPreview: self.urlPreview, selectionState: self.selectionState, sidebarEnabled: self.sidebarEnabled, sidebarShown: self.sidebarShown, layout: self.layout, canAddContact: self.canAddContact, isEmojiSection: self.isEmojiSection, chatLocation: self.chatLocation, chatMode: self.chatMode, canInvokeBasicActions: self.canInvokeBasicActions, isNotAccessible: self.isNotAccessible, restrictionInfo: self.restrictionInfo, mainPeer: self.mainPeer, limitConfiguration: self.limitConfiguration, discussionGroupId: self.discussionGroupId, slowMode: self.slowMode, hasScheduled: self.hasScheduled, failedMessageIds: self.failedMessageIds, hidePinnedMessage: self.hidePinnedMessage, canPinMessage: self.canPinMessage, tempPinnedMaxId: self.tempPinnedMaxId, groupCall: self.groupCall)
    }
    
    func updatedSearchMode(_ isSearchMode: (Bool, Peer?, String?)) -> ChatPresentationInterfaceState {
        return ChatPresentationInterfaceState(interfaceState: self.interfaceState, peer:self.peer, notificationSettings: notificationSettings, inputQueryResult: self.inputQueryResult, keyboardButtonsMessage:self.keyboardButtonsMessage, initialAction:self.initialAction, historyCount: historyCount, isSearchMode: isSearchMode, recordingState: self.recordingState, isBlocked: self.isBlocked, peerStatus: self.peerStatus, pinnedMessageId: self.pinnedMessageId, urlPreview: self.urlPreview, selectionState: self.selectionState, sidebarEnabled: self.sidebarEnabled, sidebarShown: self.sidebarShown, layout: self.layout, canAddContact: self.canAddContact, isEmojiSection: self.isEmojiSection, chatLocation: self.chatLocation, chatMode: self.chatMode, canInvokeBasicActions: self.canInvokeBasicActions, isNotAccessible: self.isNotAccessible, restrictionInfo: self.restrictionInfo, mainPeer: self.mainPeer, limitConfiguration: self.limitConfiguration, discussionGroupId: self.discussionGroupId, slowMode: self.slowMode, hasScheduled: self.hasScheduled, failedMessageIds: self.failedMessageIds, hidePinnedMessage: self.hidePinnedMessage, canPinMessage: self.canPinMessage, tempPinnedMaxId: self.tempPinnedMaxId, groupCall: self.groupCall)
    }
    
    func updatedInputQueryResult(_ f: (ChatPresentationInputQueryResult?) -> ChatPresentationInputQueryResult?) -> ChatPresentationInterfaceState {
        return ChatPresentationInterfaceState(interfaceState: self.interfaceState, peer: self.peer, notificationSettings: self.notificationSettings, inputQueryResult: f(self.inputQueryResult), keyboardButtonsMessage:self.keyboardButtonsMessage, initialAction:self.initialAction, historyCount: self.historyCount, isSearchMode: self.isSearchMode, recordingState: self.recordingState, isBlocked: self.isBlocked, peerStatus: self.peerStatus, pinnedMessageId: self.pinnedMessageId, urlPreview: self.urlPreview, selectionState: self.selectionState, sidebarEnabled: self.sidebarEnabled, sidebarShown: self.sidebarShown, layout: self.layout, canAddContact: self.canAddContact, isEmojiSection: self.isEmojiSection, chatLocation: self.chatLocation, chatMode: self.chatMode, canInvokeBasicActions: self.canInvokeBasicActions, isNotAccessible: self.isNotAccessible, restrictionInfo: self.restrictionInfo, mainPeer: self.mainPeer, limitConfiguration: self.limitConfiguration, discussionGroupId: self.discussionGroupId, slowMode: self.slowMode, hasScheduled: self.hasScheduled, failedMessageIds: self.failedMessageIds, hidePinnedMessage: self.hidePinnedMessage, canPinMessage: self.canPinMessage, tempPinnedMaxId: self.tempPinnedMaxId, groupCall: self.groupCall)
    }
    
    func updatedInitialAction(_ initialAction:ChatInitialAction?) -> ChatPresentationInterfaceState {
        return ChatPresentationInterfaceState(interfaceState: self.interfaceState, peer: self.peer, notificationSettings: self.notificationSettings, inputQueryResult: self.inputQueryResult, keyboardButtonsMessage:self.keyboardButtonsMessage, initialAction:initialAction, historyCount: self.historyCount, isSearchMode: self.isSearchMode, recordingState: self.recordingState, isBlocked: self.isBlocked, peerStatus: self.peerStatus, pinnedMessageId: self.pinnedMessageId, urlPreview: self.urlPreview, selectionState: self.selectionState, sidebarEnabled: self.sidebarEnabled, sidebarShown: self.sidebarShown, layout: self.layout, canAddContact: self.canAddContact, isEmojiSection: self.isEmojiSection, chatLocation: self.chatLocation, chatMode: self.chatMode, canInvokeBasicActions: self.canInvokeBasicActions, isNotAccessible: self.isNotAccessible, restrictionInfo: self.restrictionInfo, mainPeer: self.mainPeer, limitConfiguration: self.limitConfiguration, discussionGroupId: self.discussionGroupId, slowMode: self.slowMode, hasScheduled: self.hasScheduled, failedMessageIds: self.failedMessageIds, hidePinnedMessage: self.hidePinnedMessage, canPinMessage: self.canPinMessage, tempPinnedMaxId: self.tempPinnedMaxId, groupCall: self.groupCall)
    }
    
    
    func withRecordingState(_ state:ChatRecordingState) -> ChatPresentationInterfaceState {
         return ChatPresentationInterfaceState(interfaceState: self.interfaceState, peer: self.peer, notificationSettings: self.notificationSettings, inputQueryResult: self.inputQueryResult, keyboardButtonsMessage:self.keyboardButtonsMessage, initialAction: self.initialAction, historyCount: self.historyCount, isSearchMode: self.isSearchMode, recordingState: state, isBlocked: self.isBlocked, peerStatus: self.peerStatus, pinnedMessageId: self.pinnedMessageId, urlPreview: self.urlPreview, selectionState: self.selectionState, sidebarEnabled: self.sidebarEnabled, sidebarShown: self.sidebarShown, layout: self.layout, canAddContact: self.canAddContact, isEmojiSection: self.isEmojiSection, chatLocation: self.chatLocation, chatMode: self.chatMode, canInvokeBasicActions: self.canInvokeBasicActions, isNotAccessible: self.isNotAccessible, restrictionInfo: self.restrictionInfo, mainPeer: self.mainPeer, limitConfiguration: self.limitConfiguration, discussionGroupId: self.discussionGroupId, slowMode: self.slowMode, hasScheduled: self.hasScheduled, failedMessageIds: self.failedMessageIds, hidePinnedMessage: self.hidePinnedMessage, canPinMessage: self.canPinMessage, tempPinnedMaxId: self.tempPinnedMaxId, groupCall: self.groupCall)
    }
    
    func withoutRecordingState() -> ChatPresentationInterfaceState {
         return ChatPresentationInterfaceState(interfaceState: self.interfaceState, peer: self.peer, notificationSettings: self.notificationSettings, inputQueryResult: self.inputQueryResult, keyboardButtonsMessage:self.keyboardButtonsMessage, initialAction:initialAction, historyCount: self.historyCount, isSearchMode: self.isSearchMode, recordingState: nil, isBlocked: self.isBlocked, peerStatus: self.peerStatus, pinnedMessageId: self.pinnedMessageId, urlPreview: self.urlPreview, selectionState: self.selectionState, sidebarEnabled: self.sidebarEnabled, sidebarShown: self.sidebarShown, layout: self.layout, canAddContact: self.canAddContact, isEmojiSection: self.isEmojiSection, chatLocation: self.chatLocation, chatMode: self.chatMode, canInvokeBasicActions: self.canInvokeBasicActions, isNotAccessible: self.isNotAccessible, restrictionInfo: self.restrictionInfo, mainPeer: self.mainPeer, limitConfiguration: self.limitConfiguration, discussionGroupId: self.discussionGroupId, slowMode: self.slowMode, hasScheduled: self.hasScheduled, failedMessageIds: self.failedMessageIds, hidePinnedMessage: self.hidePinnedMessage, canPinMessage: self.canPinMessage, tempPinnedMaxId: self.tempPinnedMaxId, groupCall: self.groupCall)
    }
    
    func withUpdatedBlocked(_ blocked:Bool) -> ChatPresentationInterfaceState {
         return ChatPresentationInterfaceState(interfaceState: self.interfaceState, peer: self.peer, notificationSettings: self.notificationSettings, inputQueryResult: self.inputQueryResult, keyboardButtonsMessage:self.keyboardButtonsMessage, initialAction:initialAction, historyCount: self.historyCount, isSearchMode: self.isSearchMode, recordingState: self.recordingState, isBlocked: blocked, peerStatus: self.peerStatus, pinnedMessageId: self.pinnedMessageId, urlPreview: self.urlPreview, selectionState: self.selectionState, sidebarEnabled: self.sidebarEnabled, sidebarShown: self.sidebarShown, layout: self.layout, canAddContact: self.canAddContact, isEmojiSection: self.isEmojiSection, chatLocation: self.chatLocation, chatMode: self.chatMode, canInvokeBasicActions: self.canInvokeBasicActions, isNotAccessible: self.isNotAccessible, restrictionInfo: self.restrictionInfo, mainPeer: self.mainPeer, limitConfiguration: self.limitConfiguration, discussionGroupId: self.discussionGroupId, slowMode: self.slowMode, hasScheduled: self.hasScheduled, failedMessageIds: self.failedMessageIds, hidePinnedMessage: self.hidePinnedMessage, canPinMessage: self.canPinMessage, tempPinnedMaxId: self.tempPinnedMaxId, groupCall: self.groupCall)
    }
    
    func withUpdatedPinnedMessageId(_ pinnedMessageId:ChatPinnedMessage?) -> ChatPresentationInterfaceState {
        return ChatPresentationInterfaceState(interfaceState: self.interfaceState, peer: self.peer, notificationSettings: self.notificationSettings, inputQueryResult: self.inputQueryResult, keyboardButtonsMessage:self.keyboardButtonsMessage, initialAction:initialAction, historyCount: self.historyCount, isSearchMode: self.isSearchMode, recordingState: self.recordingState, isBlocked: self.isBlocked, peerStatus: self.peerStatus, pinnedMessageId: pinnedMessageId, urlPreview: self.urlPreview, selectionState: self.selectionState, sidebarEnabled: self.sidebarEnabled, sidebarShown: self.sidebarShown, layout: self.layout, canAddContact: self.canAddContact, isEmojiSection: self.isEmojiSection, chatLocation: self.chatLocation, chatMode: self.chatMode, canInvokeBasicActions: self.canInvokeBasicActions, isNotAccessible: self.isNotAccessible, restrictionInfo: self.restrictionInfo, mainPeer: self.mainPeer, limitConfiguration: self.limitConfiguration, discussionGroupId: self.discussionGroupId, slowMode: self.slowMode, hasScheduled: self.hasScheduled, failedMessageIds: self.failedMessageIds, hidePinnedMessage: self.hidePinnedMessage, canPinMessage: self.canPinMessage, tempPinnedMaxId: self.tempPinnedMaxId, groupCall: self.groupCall)
    }
    
    
    func withUpdatedPeerStatusSettings(_ peerStatus:ChatPeerStatus?) -> ChatPresentationInterfaceState {
        return ChatPresentationInterfaceState(interfaceState: self.interfaceState, peer: self.peer, notificationSettings: self.notificationSettings, inputQueryResult: self.inputQueryResult, keyboardButtonsMessage:self.keyboardButtonsMessage, initialAction:initialAction, historyCount: self.historyCount, isSearchMode: self.isSearchMode, recordingState: self.recordingState, isBlocked: self.isBlocked, peerStatus: peerStatus, pinnedMessageId: self.pinnedMessageId, urlPreview: self.urlPreview, selectionState: self.selectionState, sidebarEnabled: self.sidebarEnabled, sidebarShown: self.sidebarShown, layout: self.layout, canAddContact: self.canAddContact, isEmojiSection: self.isEmojiSection, chatLocation: self.chatLocation, chatMode: self.chatMode, canInvokeBasicActions: self.canInvokeBasicActions, isNotAccessible: self.isNotAccessible, restrictionInfo: self.restrictionInfo, mainPeer: self.mainPeer, limitConfiguration: self.limitConfiguration, discussionGroupId: self.discussionGroupId, slowMode: self.slowMode, hasScheduled: self.hasScheduled, failedMessageIds: self.failedMessageIds, hidePinnedMessage: self.hidePinnedMessage, canPinMessage: self.canPinMessage, tempPinnedMaxId: self.tempPinnedMaxId, groupCall: self.groupCall)
    }
    
    func withEditMessage(_ message:Message) -> ChatPresentationInterfaceState {
        return self.updatedInterfaceState({$0.withEditMessage(message)})
    }
    
    func withoutEditMessage() -> ChatPresentationInterfaceState {
        return self.updatedInterfaceState({$0.withoutEditMessage()})
    }
    
    func withUpdatedEffectiveInputState(_ inputState: ChatTextInputState) -> ChatPresentationInterfaceState {
        return self.updatedInterfaceState({$0.withUpdatedInputState(inputState)})
    }
    
    func updatedUrlPreview(_ urlPreview: (String, TelegramMediaWebpage)?) -> ChatPresentationInterfaceState {
        return ChatPresentationInterfaceState(interfaceState: self.interfaceState, peer: self.peer, notificationSettings: self.notificationSettings, inputQueryResult: self.inputQueryResult, keyboardButtonsMessage:self.keyboardButtonsMessage, initialAction:initialAction, historyCount: self.historyCount, isSearchMode: self.isSearchMode, recordingState: self.recordingState, isBlocked: self.isBlocked, peerStatus: self.peerStatus, pinnedMessageId: self.pinnedMessageId, urlPreview: urlPreview, selectionState: self.selectionState, sidebarEnabled: self.sidebarEnabled, sidebarShown: self.sidebarShown, layout: self.layout, canAddContact: self.canAddContact, isEmojiSection: self.isEmojiSection, chatLocation: self.chatLocation, chatMode: self.chatMode, canInvokeBasicActions: self.canInvokeBasicActions, isNotAccessible: self.isNotAccessible, restrictionInfo: self.restrictionInfo, mainPeer: self.mainPeer, limitConfiguration: self.limitConfiguration, discussionGroupId: self.discussionGroupId, slowMode: self.slowMode, hasScheduled: self.hasScheduled, failedMessageIds: self.failedMessageIds, hidePinnedMessage: self.hidePinnedMessage, canPinMessage: self.canPinMessage, tempPinnedMaxId: self.tempPinnedMaxId, groupCall: self.groupCall)
    }
    
    
    func isSelectedMessageId(_ messageId:MessageId) -> Bool {
        if let selectionState = selectionState {
            return selectionState.selectedIds.contains(messageId)
        }
        return false
    }
    
    func withUpdatedSelectedMessage(_ messageId: MessageId) -> ChatPresentationInterfaceState {
        var selectedIds = Set<MessageId>()
        if let selectionState = self.selectionState {
            selectedIds.formUnion(selectionState.selectedIds)
        }
        if selectedIds.count < 100 {
            selectedIds.insert(messageId)
        } else {
            NSSound.beep()
        }
        
        return ChatPresentationInterfaceState(interfaceState: self.interfaceState, peer: self.peer, notificationSettings: self.notificationSettings, inputQueryResult: self.inputQueryResult, keyboardButtonsMessage:self.keyboardButtonsMessage, initialAction:initialAction, historyCount: self.historyCount, isSearchMode: self.isSearchMode, recordingState: self.recordingState, isBlocked: self.isBlocked, peerStatus: self.peerStatus, pinnedMessageId: self.pinnedMessageId, urlPreview: self.urlPreview, selectionState: self.selectionState?.withUpdatedSelectedIds(selectedIds), sidebarEnabled: self.sidebarEnabled, sidebarShown: self.sidebarShown, layout: self.layout, canAddContact: self.canAddContact, isEmojiSection: self.isEmojiSection, chatLocation: self.chatLocation, chatMode: self.chatMode, canInvokeBasicActions: self.canInvokeBasicActions, isNotAccessible: self.isNotAccessible, restrictionInfo: self.restrictionInfo, mainPeer: self.mainPeer, limitConfiguration: self.limitConfiguration, discussionGroupId: self.discussionGroupId, slowMode: self.slowMode, hasScheduled: self.hasScheduled, failedMessageIds: self.failedMessageIds, hidePinnedMessage: self.hidePinnedMessage, canPinMessage: self.canPinMessage, tempPinnedMaxId: self.tempPinnedMaxId, groupCall: self.groupCall)
    }
    
    func withUpdatedSelectedMessages(_ ids:Set<MessageId>) -> ChatPresentationInterfaceState {
        return ChatPresentationInterfaceState(interfaceState: self.interfaceState, peer: self.peer, notificationSettings: self.notificationSettings, inputQueryResult: self.inputQueryResult, keyboardButtonsMessage:self.keyboardButtonsMessage, initialAction:initialAction, historyCount: self.historyCount, isSearchMode: self.isSearchMode, recordingState: self.recordingState, isBlocked: self.isBlocked, peerStatus: self.peerStatus, pinnedMessageId: self.pinnedMessageId, urlPreview: self.urlPreview, selectionState: self.selectionState?.withUpdatedSelectedIds(ids), sidebarEnabled: self.sidebarEnabled, sidebarShown: self.sidebarShown, layout: self.layout, canAddContact: self.canAddContact, isEmojiSection: self.isEmojiSection, chatLocation: self.chatLocation, chatMode: self.chatMode, canInvokeBasicActions: self.canInvokeBasicActions, isNotAccessible: self.isNotAccessible, restrictionInfo: self.restrictionInfo, mainPeer: self.mainPeer, limitConfiguration: self.limitConfiguration, discussionGroupId: self.discussionGroupId, slowMode: self.slowMode, hasScheduled: self.hasScheduled, failedMessageIds: self.failedMessageIds, hidePinnedMessage: self.hidePinnedMessage, canPinMessage: self.canPinMessage, tempPinnedMaxId: self.tempPinnedMaxId, groupCall: self.groupCall)
    }
    
    func withToggledSelectedMessage(_ messageId: MessageId) -> ChatPresentationInterfaceState {
        var selectedIds = Set<MessageId>()
        if let selectionState = self.selectionState {
            selectedIds.formUnion(selectionState.selectedIds)
        }
        let isSelected: Bool = selectedIds.contains(messageId)
        if isSelected {
            let _ = selectedIds.remove(messageId)
        } else {
            if selectedIds.count < 100 {
                selectedIds.insert(messageId)
            } else {
                NSSound.beep()
            }
        }
        
        var selectionState: ChatInterfaceSelectionState = self.selectionState?.withUpdatedSelectedIds(selectedIds) ?? ChatInterfaceSelectionState(selectedIds: selectedIds, lastSelectedId: nil)
        
        if let event = NSApp.currentEvent {
            if !event.modifierFlags.contains(.shift) {
                if !isSelected {
                    selectionState = selectionState.withUpdatedLastSelected(messageId)
                } else {
                    var foundBestOption: Bool = false
                    for id in selectedIds {
                        if id > messageId {
                            selectionState = selectionState.withUpdatedLastSelected(id)
                            foundBestOption = true
                            break
                        }
                    }
                    if !foundBestOption {
                        selectionState = selectionState.withUpdatedLastSelected(messageId)
                    }
                }
            }
        }
        
        return ChatPresentationInterfaceState(interfaceState: self.interfaceState, peer: self.peer, notificationSettings: self.notificationSettings, inputQueryResult: self.inputQueryResult, keyboardButtonsMessage:self.keyboardButtonsMessage, initialAction:initialAction, historyCount: self.historyCount, isSearchMode: self.isSearchMode, recordingState: self.recordingState, isBlocked: self.isBlocked, peerStatus: self.peerStatus, pinnedMessageId: self.pinnedMessageId, urlPreview: self.urlPreview, selectionState: selectionState, sidebarEnabled: self.sidebarEnabled, sidebarShown: self.sidebarShown, layout: self.layout, canAddContact: self.canAddContact, isEmojiSection: self.isEmojiSection, chatLocation: self.chatLocation, chatMode: self.chatMode, canInvokeBasicActions: self.canInvokeBasicActions, isNotAccessible: self.isNotAccessible, restrictionInfo: self.restrictionInfo, mainPeer: self.mainPeer, limitConfiguration: self.limitConfiguration, discussionGroupId: self.discussionGroupId, slowMode: self.slowMode, hasScheduled: self.hasScheduled, failedMessageIds: self.failedMessageIds, hidePinnedMessage: self.hidePinnedMessage, canPinMessage: self.canPinMessage, tempPinnedMaxId: self.tempPinnedMaxId, groupCall: self.groupCall)
    }
    
    func withRemovedSelectedMessage(_ messageId: MessageId) -> ChatPresentationInterfaceState {
        var selectedIds = Set<MessageId>()
        if let selectionState = self.selectionState {
            selectedIds.formUnion(selectionState.selectedIds)
        }
        let _ = selectedIds.remove(messageId)
        
        return ChatPresentationInterfaceState(interfaceState: self.interfaceState, peer: self.peer, notificationSettings: self.notificationSettings, inputQueryResult: self.inputQueryResult, keyboardButtonsMessage:self.keyboardButtonsMessage, initialAction:initialAction, historyCount: self.historyCount, isSearchMode: self.isSearchMode, recordingState: self.recordingState, isBlocked: self.isBlocked, peerStatus: self.peerStatus, pinnedMessageId: self.pinnedMessageId, urlPreview: self.urlPreview, selectionState: self.selectionState?.withUpdatedSelectedIds(selectedIds), sidebarEnabled: self.sidebarEnabled, sidebarShown: self.sidebarShown, layout: self.layout, canAddContact: self.canAddContact, isEmojiSection: self.isEmojiSection, chatLocation: self.chatLocation, chatMode: self.chatMode, canInvokeBasicActions: self.canInvokeBasicActions, isNotAccessible: self.isNotAccessible, restrictionInfo: self.restrictionInfo, mainPeer: self.mainPeer, limitConfiguration: self.limitConfiguration, discussionGroupId: self.discussionGroupId, slowMode: self.slowMode, hasScheduled: self.hasScheduled, failedMessageIds: self.failedMessageIds, hidePinnedMessage: self.hidePinnedMessage, canPinMessage: self.canPinMessage, tempPinnedMaxId: self.tempPinnedMaxId, groupCall: self.groupCall)
    }

    
    func withoutSelectionState() -> ChatPresentationInterfaceState {
         return ChatPresentationInterfaceState(interfaceState: self.interfaceState, peer: self.peer, notificationSettings: self.notificationSettings, inputQueryResult: self.inputQueryResult, keyboardButtonsMessage:self.keyboardButtonsMessage, initialAction:initialAction, historyCount: self.historyCount, isSearchMode: self.isSearchMode, recordingState: self.recordingState, isBlocked: self.isBlocked, peerStatus: self.peerStatus, pinnedMessageId: self.pinnedMessageId, urlPreview: self.urlPreview, selectionState: nil, sidebarEnabled: self.sidebarEnabled, sidebarShown: self.sidebarShown, layout: self.layout, canAddContact: self.canAddContact, isEmojiSection: self.isEmojiSection, chatLocation: self.chatLocation, chatMode: self.chatMode, canInvokeBasicActions: self.canInvokeBasicActions, isNotAccessible: self.isNotAccessible, restrictionInfo: self.restrictionInfo, mainPeer: self.mainPeer, limitConfiguration: self.limitConfiguration, discussionGroupId: self.discussionGroupId, slowMode: self.slowMode, hasScheduled: self.hasScheduled, failedMessageIds: self.failedMessageIds, hidePinnedMessage: self.hidePinnedMessage, canPinMessage: self.canPinMessage, tempPinnedMaxId: self.tempPinnedMaxId, groupCall: self.groupCall)
    }
    
    func withSelectionState() -> ChatPresentationInterfaceState {
         return ChatPresentationInterfaceState(interfaceState: self.interfaceState, peer: self.peer, notificationSettings: self.notificationSettings, inputQueryResult: self.inputQueryResult, keyboardButtonsMessage:self.keyboardButtonsMessage, initialAction:initialAction, historyCount: self.historyCount, isSearchMode: self.isSearchMode, recordingState: self.recordingState, isBlocked: self.isBlocked, peerStatus: self.peerStatus, pinnedMessageId: self.pinnedMessageId, urlPreview: self.urlPreview, selectionState: ChatInterfaceSelectionState(selectedIds: [], lastSelectedId: nil), sidebarEnabled: self.sidebarEnabled, sidebarShown: self.sidebarShown, layout: self.layout, canAddContact: self.canAddContact, isEmojiSection: self.isEmojiSection, chatLocation: self.chatLocation, chatMode: self.chatMode, canInvokeBasicActions: self.canInvokeBasicActions, isNotAccessible: self.isNotAccessible, restrictionInfo: self.restrictionInfo, mainPeer: self.mainPeer, limitConfiguration: self.limitConfiguration, discussionGroupId: self.discussionGroupId, slowMode: self.slowMode, hasScheduled: self.hasScheduled, failedMessageIds: self.failedMessageIds, hidePinnedMessage: self.hidePinnedMessage, canPinMessage: self.canPinMessage, tempPinnedMaxId: self.tempPinnedMaxId, groupCall: self.groupCall)
    }

    func withToggledSidebarEnabled(_ enabled: Bool?) -> ChatPresentationInterfaceState {
        return ChatPresentationInterfaceState(interfaceState: self.interfaceState, peer: self.peer, notificationSettings: self.notificationSettings, inputQueryResult: self.inputQueryResult, keyboardButtonsMessage:self.keyboardButtonsMessage, initialAction:initialAction, historyCount: self.historyCount, isSearchMode: self.isSearchMode, recordingState: self.recordingState, isBlocked: self.isBlocked, peerStatus: self.peerStatus, pinnedMessageId: self.pinnedMessageId, urlPreview: self.urlPreview, selectionState: self.selectionState, sidebarEnabled: enabled, sidebarShown: self.sidebarShown, layout: self.layout, canAddContact: self.canAddContact, isEmojiSection: self.isEmojiSection, chatLocation: self.chatLocation, chatMode: self.chatMode, canInvokeBasicActions: self.canInvokeBasicActions, isNotAccessible: self.isNotAccessible, restrictionInfo: self.restrictionInfo, mainPeer: self.mainPeer, limitConfiguration: self.limitConfiguration, discussionGroupId: self.discussionGroupId, slowMode: self.slowMode, hasScheduled: self.hasScheduled, failedMessageIds: self.failedMessageIds, hidePinnedMessage: self.hidePinnedMessage, canPinMessage: self.canPinMessage, tempPinnedMaxId: self.tempPinnedMaxId, groupCall: self.groupCall)
    }
    
    func withToggledSidebarShown(_ shown: Bool?) -> ChatPresentationInterfaceState {
        return ChatPresentationInterfaceState(interfaceState: self.interfaceState, peer: self.peer, notificationSettings: self.notificationSettings, inputQueryResult: self.inputQueryResult, keyboardButtonsMessage:self.keyboardButtonsMessage, initialAction:initialAction, historyCount: self.historyCount, isSearchMode: self.isSearchMode, recordingState: self.recordingState, isBlocked: self.isBlocked, peerStatus: self.peerStatus, pinnedMessageId: self.pinnedMessageId, urlPreview: self.urlPreview, selectionState: self.selectionState, sidebarEnabled: self.sidebarEnabled, sidebarShown: shown, layout: self.layout, canAddContact: self.canAddContact, isEmojiSection: self.isEmojiSection, chatLocation: self.chatLocation, chatMode: self.chatMode, canInvokeBasicActions: self.canInvokeBasicActions, isNotAccessible: self.isNotAccessible, restrictionInfo: self.restrictionInfo, mainPeer: self.mainPeer, limitConfiguration: self.limitConfiguration, discussionGroupId: self.discussionGroupId, slowMode: self.slowMode, hasScheduled: self.hasScheduled, failedMessageIds: self.failedMessageIds, hidePinnedMessage: self.hidePinnedMessage, canPinMessage: self.canPinMessage, tempPinnedMaxId: self.tempPinnedMaxId, groupCall: self.groupCall)
    }
    
    func withUpdatedLayout(_ layout: SplitViewState?) -> ChatPresentationInterfaceState {
        return ChatPresentationInterfaceState(interfaceState: self.interfaceState, peer: self.peer, notificationSettings: self.notificationSettings, inputQueryResult: self.inputQueryResult, keyboardButtonsMessage:self.keyboardButtonsMessage, initialAction:initialAction, historyCount: self.historyCount, isSearchMode: self.isSearchMode, recordingState: self.recordingState, isBlocked: self.isBlocked, peerStatus: self.peerStatus, pinnedMessageId: self.pinnedMessageId, urlPreview: self.urlPreview, selectionState: self.selectionState, sidebarEnabled: self.sidebarEnabled, sidebarShown: self.sidebarShown, layout: layout, canAddContact: self.canAddContact, isEmojiSection: self.isEmojiSection, chatLocation: self.chatLocation, chatMode: self.chatMode, canInvokeBasicActions: self.canInvokeBasicActions, isNotAccessible: self.isNotAccessible, restrictionInfo: self.restrictionInfo, mainPeer: self.mainPeer, limitConfiguration: self.limitConfiguration, discussionGroupId: self.discussionGroupId, slowMode: self.slowMode, hasScheduled: self.hasScheduled, failedMessageIds: self.failedMessageIds, hidePinnedMessage: self.hidePinnedMessage, canPinMessage: self.canPinMessage, tempPinnedMaxId: self.tempPinnedMaxId, groupCall: self.groupCall)
    }
    
    func withoutInitialAction() -> ChatPresentationInterfaceState {
        return ChatPresentationInterfaceState(interfaceState: self.interfaceState, peer: self.peer, notificationSettings: self.notificationSettings, inputQueryResult: self.inputQueryResult, keyboardButtonsMessage:self.keyboardButtonsMessage, initialAction: nil, historyCount: self.historyCount, isSearchMode: self.isSearchMode, recordingState: self.recordingState, isBlocked: self.isBlocked, peerStatus: self.peerStatus, pinnedMessageId: self.pinnedMessageId, urlPreview: self.urlPreview, selectionState: self.selectionState, sidebarEnabled: self.sidebarEnabled, sidebarShown: self.sidebarShown, layout: self.layout, canAddContact: self.canAddContact, isEmojiSection: self.isEmojiSection, chatLocation: self.chatLocation, chatMode: self.chatMode, canInvokeBasicActions: self.canInvokeBasicActions, isNotAccessible: self.isNotAccessible, restrictionInfo: self.restrictionInfo, mainPeer: self.mainPeer, limitConfiguration: self.limitConfiguration, discussionGroupId: self.discussionGroupId, slowMode: self.slowMode, hasScheduled: self.hasScheduled, failedMessageIds: self.failedMessageIds, hidePinnedMessage: self.hidePinnedMessage, canPinMessage: self.canPinMessage, tempPinnedMaxId: self.tempPinnedMaxId, groupCall: self.groupCall)
    }
    
    func withUpdatedContactAdding(_ canAddContact:Bool?) -> ChatPresentationInterfaceState {
        return ChatPresentationInterfaceState(interfaceState: self.interfaceState, peer: self.peer, notificationSettings: self.notificationSettings, inputQueryResult: self.inputQueryResult, keyboardButtonsMessage:self.keyboardButtonsMessage, initialAction:initialAction, historyCount: self.historyCount, isSearchMode: self.isSearchMode, recordingState: self.recordingState, isBlocked: self.isBlocked, peerStatus: self.peerStatus, pinnedMessageId: self.pinnedMessageId, urlPreview: self.urlPreview, selectionState: self.selectionState, sidebarEnabled: self.sidebarEnabled, sidebarShown: self.sidebarShown, layout: self.layout, canAddContact: canAddContact, isEmojiSection: self.isEmojiSection, chatLocation: self.chatLocation, chatMode: self.chatMode, canInvokeBasicActions: self.canInvokeBasicActions, isNotAccessible: self.isNotAccessible, restrictionInfo: self.restrictionInfo, mainPeer: self.mainPeer, limitConfiguration: self.limitConfiguration, discussionGroupId: self.discussionGroupId, slowMode: self.slowMode, hasScheduled: self.hasScheduled, failedMessageIds: self.failedMessageIds, hidePinnedMessage: self.hidePinnedMessage, canPinMessage: self.canPinMessage, tempPinnedMaxId: self.tempPinnedMaxId, groupCall: self.groupCall)
    }
    
    func withUpdatedIsEmojiSection(_ isEmojiSection:Bool) -> ChatPresentationInterfaceState {
        return ChatPresentationInterfaceState(interfaceState: self.interfaceState, peer: self.peer, notificationSettings: self.notificationSettings, inputQueryResult: self.inputQueryResult, keyboardButtonsMessage:self.keyboardButtonsMessage, initialAction:initialAction, historyCount: self.historyCount, isSearchMode: self.isSearchMode, recordingState: self.recordingState, isBlocked: self.isBlocked, peerStatus: self.peerStatus, pinnedMessageId: self.pinnedMessageId, urlPreview: self.urlPreview, selectionState: self.selectionState, sidebarEnabled: self.sidebarEnabled, sidebarShown: self.sidebarShown, layout: self.layout, canAddContact: self.canAddContact, isEmojiSection: isEmojiSection, chatLocation: self.chatLocation, chatMode: self.chatMode, canInvokeBasicActions: self.canInvokeBasicActions, isNotAccessible: self.isNotAccessible, restrictionInfo: self.restrictionInfo, mainPeer: self.mainPeer, limitConfiguration: self.limitConfiguration, discussionGroupId: self.discussionGroupId, slowMode: self.slowMode, hasScheduled: self.hasScheduled, failedMessageIds: self.failedMessageIds, hidePinnedMessage: self.hidePinnedMessage, canPinMessage: self.canPinMessage, tempPinnedMaxId: self.tempPinnedMaxId, groupCall: self.groupCall)
    }
    
    func withUpdatedBasicActions(_ canInvokeBasicActions:(delete: Bool, forward: Bool)) -> ChatPresentationInterfaceState {
        return ChatPresentationInterfaceState(interfaceState: self.interfaceState, peer: self.peer, notificationSettings: self.notificationSettings, inputQueryResult: self.inputQueryResult, keyboardButtonsMessage:self.keyboardButtonsMessage, initialAction: self.initialAction, historyCount: self.historyCount, isSearchMode: self.isSearchMode, recordingState: self.recordingState, isBlocked: self.isBlocked, peerStatus: self.peerStatus, pinnedMessageId: self.pinnedMessageId, urlPreview: self.urlPreview, selectionState: self.selectionState, sidebarEnabled: self.sidebarEnabled, sidebarShown: self.sidebarShown, layout: self.layout, canAddContact: self.canAddContact, isEmojiSection: self.isEmojiSection, chatLocation: self.chatLocation, chatMode: self.chatMode, canInvokeBasicActions: canInvokeBasicActions, isNotAccessible: self.isNotAccessible, restrictionInfo: self.restrictionInfo, mainPeer: self.mainPeer, limitConfiguration: self.limitConfiguration, discussionGroupId: self.discussionGroupId, slowMode: self.slowMode, hasScheduled: self.hasScheduled, failedMessageIds: self.failedMessageIds, hidePinnedMessage: self.hidePinnedMessage, canPinMessage: self.canPinMessage, tempPinnedMaxId: self.tempPinnedMaxId, groupCall: self.groupCall)
    }

    
    func withUpdatedIsNotAccessible(_ isNotAccessible:Bool) -> ChatPresentationInterfaceState {
        return ChatPresentationInterfaceState(interfaceState: self.interfaceState, peer: self.peer, notificationSettings: self.notificationSettings, inputQueryResult: self.inputQueryResult, keyboardButtonsMessage:self.keyboardButtonsMessage, initialAction: self.initialAction, historyCount: self.historyCount, isSearchMode: self.isSearchMode, recordingState: self.recordingState, isBlocked: self.isBlocked, peerStatus: self.peerStatus, pinnedMessageId: self.pinnedMessageId, urlPreview: self.urlPreview, selectionState: self.selectionState, sidebarEnabled: self.sidebarEnabled, sidebarShown: self.sidebarShown, layout: self.layout, canAddContact: self.canAddContact, isEmojiSection: self.isEmojiSection, chatLocation: self.chatLocation, chatMode: self.chatMode, canInvokeBasicActions: self.canInvokeBasicActions, isNotAccessible: isNotAccessible, restrictionInfo: self.restrictionInfo, mainPeer: self.mainPeer, limitConfiguration: self.limitConfiguration, discussionGroupId: self.discussionGroupId, slowMode: self.slowMode, hasScheduled: self.hasScheduled, failedMessageIds: self.failedMessageIds, hidePinnedMessage: self.hidePinnedMessage, canPinMessage: self.canPinMessage, tempPinnedMaxId: self.tempPinnedMaxId, groupCall: self.groupCall)
    }
    
    func withUpdatedRestrictionInfo(_ restrictionInfo:PeerAccessRestrictionInfo?) -> ChatPresentationInterfaceState {
        return ChatPresentationInterfaceState(interfaceState: self.interfaceState, peer: self.peer, notificationSettings: self.notificationSettings, inputQueryResult: self.inputQueryResult, keyboardButtonsMessage:self.keyboardButtonsMessage, initialAction: self.initialAction, historyCount: self.historyCount, isSearchMode: self.isSearchMode, recordingState: self.recordingState, isBlocked: self.isBlocked, peerStatus: self.peerStatus, pinnedMessageId: self.pinnedMessageId, urlPreview: self.urlPreview, selectionState: self.selectionState, sidebarEnabled: self.sidebarEnabled, sidebarShown: self.sidebarShown, layout: self.layout, canAddContact: self.canAddContact, isEmojiSection: self.isEmojiSection, chatLocation: self.chatLocation, chatMode: self.chatMode, canInvokeBasicActions: self.canInvokeBasicActions, isNotAccessible: self.isNotAccessible, restrictionInfo: restrictionInfo, mainPeer: self.mainPeer, limitConfiguration: self.limitConfiguration, discussionGroupId: self.discussionGroupId, slowMode: self.slowMode, hasScheduled: self.hasScheduled, failedMessageIds: self.failedMessageIds, hidePinnedMessage: self.hidePinnedMessage, canPinMessage: self.canPinMessage, tempPinnedMaxId: self.tempPinnedMaxId, groupCall: self.groupCall)
    }
    
    func withUpdatedLimitConfiguration(_ limitConfiguration:LimitsConfiguration) -> ChatPresentationInterfaceState {
        return ChatPresentationInterfaceState(interfaceState: self.interfaceState, peer: self.peer, notificationSettings: self.notificationSettings, inputQueryResult: self.inputQueryResult, keyboardButtonsMessage:self.keyboardButtonsMessage, initialAction: self.initialAction, historyCount: self.historyCount, isSearchMode: self.isSearchMode, recordingState: self.recordingState, isBlocked: self.isBlocked, peerStatus: self.peerStatus, pinnedMessageId: self.pinnedMessageId, urlPreview: self.urlPreview, selectionState: self.selectionState, sidebarEnabled: self.sidebarEnabled, sidebarShown: self.sidebarShown, layout: self.layout, canAddContact: self.canAddContact, isEmojiSection: self.isEmojiSection, chatLocation: self.chatLocation, chatMode: self.chatMode, canInvokeBasicActions: self.canInvokeBasicActions, isNotAccessible: self.isNotAccessible, restrictionInfo: self.restrictionInfo, mainPeer: self.mainPeer, limitConfiguration: limitConfiguration, discussionGroupId: self.discussionGroupId, slowMode: self.slowMode, hasScheduled: self.hasScheduled, failedMessageIds: self.failedMessageIds, hidePinnedMessage: self.hidePinnedMessage, canPinMessage: self.canPinMessage, tempPinnedMaxId: self.tempPinnedMaxId, groupCall: self.groupCall)
    }
    
    func withUpdatedDiscussionGroupId(_ discussionGroupId: CachedChannelData.LinkedDiscussionPeerId) -> ChatPresentationInterfaceState {
        return ChatPresentationInterfaceState(interfaceState: self.interfaceState, peer: self.peer, notificationSettings: self.notificationSettings, inputQueryResult: self.inputQueryResult, keyboardButtonsMessage:self.keyboardButtonsMessage, initialAction: self.initialAction, historyCount: self.historyCount, isSearchMode: self.isSearchMode, recordingState: self.recordingState, isBlocked: self.isBlocked, peerStatus: self.peerStatus, pinnedMessageId: self.pinnedMessageId, urlPreview: self.urlPreview, selectionState: self.selectionState, sidebarEnabled: self.sidebarEnabled, sidebarShown: self.sidebarShown, layout: self.layout, canAddContact: self.canAddContact, isEmojiSection: self.isEmojiSection, chatLocation: self.chatLocation, chatMode: self.chatMode, canInvokeBasicActions: self.canInvokeBasicActions, isNotAccessible: self.isNotAccessible, restrictionInfo: self.restrictionInfo, mainPeer: self.mainPeer, limitConfiguration: limitConfiguration, discussionGroupId: discussionGroupId, slowMode: self.slowMode, hasScheduled: self.hasScheduled, failedMessageIds: self.failedMessageIds, hidePinnedMessage: self.hidePinnedMessage, canPinMessage: self.canPinMessage, tempPinnedMaxId: self.tempPinnedMaxId, groupCall: self.groupCall)
    }
    func updateSlowMode(_ f: (SlowMode?)->SlowMode?) -> ChatPresentationInterfaceState {
        return ChatPresentationInterfaceState(interfaceState: self.interfaceState, peer: self.peer, notificationSettings: self.notificationSettings, inputQueryResult: self.inputQueryResult, keyboardButtonsMessage:self.keyboardButtonsMessage, initialAction: self.initialAction, historyCount: self.historyCount, isSearchMode: self.isSearchMode, recordingState: self.recordingState, isBlocked: self.isBlocked, peerStatus: self.peerStatus, pinnedMessageId: self.pinnedMessageId, urlPreview: self.urlPreview, selectionState: self.selectionState, sidebarEnabled: self.sidebarEnabled, sidebarShown: self.sidebarShown, layout: self.layout, canAddContact: self.canAddContact, isEmojiSection: self.isEmojiSection, chatLocation: self.chatLocation, chatMode: self.chatMode, canInvokeBasicActions: self.canInvokeBasicActions, isNotAccessible: self.isNotAccessible, restrictionInfo: self.restrictionInfo, mainPeer: self.mainPeer, limitConfiguration: limitConfiguration, discussionGroupId: self.discussionGroupId, slowMode: f(self.slowMode), hasScheduled: self.hasScheduled, failedMessageIds: self.failedMessageIds, hidePinnedMessage: self.hidePinnedMessage, canPinMessage: self.canPinMessage, tempPinnedMaxId: self.tempPinnedMaxId, groupCall: self.groupCall)
    }
    func withUpdatedHasScheduled(_ hasScheduled: Bool) -> ChatPresentationInterfaceState {
        return ChatPresentationInterfaceState(interfaceState: self.interfaceState, peer: self.peer, notificationSettings: self.notificationSettings, inputQueryResult: self.inputQueryResult, keyboardButtonsMessage:self.keyboardButtonsMessage, initialAction: self.initialAction, historyCount: self.historyCount, isSearchMode: self.isSearchMode, recordingState: self.recordingState, isBlocked: self.isBlocked, peerStatus: self.peerStatus, pinnedMessageId: self.pinnedMessageId, urlPreview: self.urlPreview, selectionState: self.selectionState, sidebarEnabled: self.sidebarEnabled, sidebarShown: self.sidebarShown, layout: self.layout, canAddContact: self.canAddContact, isEmojiSection: self.isEmojiSection, chatLocation: self.chatLocation, chatMode: self.chatMode, canInvokeBasicActions: self.canInvokeBasicActions, isNotAccessible: self.isNotAccessible, restrictionInfo: self.restrictionInfo, mainPeer: self.mainPeer, limitConfiguration: limitConfiguration, discussionGroupId: discussionGroupId, slowMode: self.slowMode, hasScheduled: hasScheduled, failedMessageIds: self.failedMessageIds, hidePinnedMessage: self.hidePinnedMessage, canPinMessage: self.canPinMessage, tempPinnedMaxId: self.tempPinnedMaxId, groupCall: self.groupCall)
    }
    func withUpdatedFailedMessageIds(_ failedMessageIds: Set<MessageId>) -> ChatPresentationInterfaceState {
        return ChatPresentationInterfaceState(interfaceState: self.interfaceState, peer: self.peer, notificationSettings: self.notificationSettings, inputQueryResult: self.inputQueryResult, keyboardButtonsMessage:self.keyboardButtonsMessage, initialAction: self.initialAction, historyCount: self.historyCount, isSearchMode: self.isSearchMode, recordingState: self.recordingState, isBlocked: self.isBlocked, peerStatus: self.peerStatus, pinnedMessageId: self.pinnedMessageId, urlPreview: self.urlPreview, selectionState: self.selectionState, sidebarEnabled: self.sidebarEnabled, sidebarShown: self.sidebarShown, layout: self.layout, canAddContact: self.canAddContact, isEmojiSection: self.isEmojiSection, chatLocation: self.chatLocation, chatMode: self.chatMode, canInvokeBasicActions: self.canInvokeBasicActions, isNotAccessible: self.isNotAccessible, restrictionInfo: self.restrictionInfo, mainPeer: self.mainPeer, limitConfiguration: limitConfiguration, discussionGroupId: discussionGroupId, slowMode: self.slowMode, hasScheduled: self.hasScheduled, failedMessageIds: failedMessageIds, hidePinnedMessage: self.hidePinnedMessage, canPinMessage: self.canPinMessage, tempPinnedMaxId: self.tempPinnedMaxId, groupCall: self.groupCall)
    }
    
    func withUpdatedHidePinnedMessage(_ hidePinnedMessage: Bool) -> ChatPresentationInterfaceState {
        return ChatPresentationInterfaceState(interfaceState: self.interfaceState, peer: self.peer, notificationSettings: self.notificationSettings, inputQueryResult: self.inputQueryResult, keyboardButtonsMessage:self.keyboardButtonsMessage, initialAction: self.initialAction, historyCount: self.historyCount, isSearchMode: self.isSearchMode, recordingState: self.recordingState, isBlocked: self.isBlocked, peerStatus: self.peerStatus, pinnedMessageId: self.pinnedMessageId, urlPreview: self.urlPreview, selectionState: self.selectionState, sidebarEnabled: self.sidebarEnabled, sidebarShown: self.sidebarShown, layout: self.layout, canAddContact: self.canAddContact, isEmojiSection: self.isEmojiSection, chatLocation: self.chatLocation, chatMode: self.chatMode, canInvokeBasicActions: self.canInvokeBasicActions, isNotAccessible: self.isNotAccessible, restrictionInfo: self.restrictionInfo, mainPeer: self.mainPeer, limitConfiguration: limitConfiguration, discussionGroupId: discussionGroupId, slowMode: self.slowMode, hasScheduled: self.hasScheduled, failedMessageIds: self.failedMessageIds, hidePinnedMessage: hidePinnedMessage, canPinMessage: self.canPinMessage, tempPinnedMaxId: self.tempPinnedMaxId, groupCall: self.groupCall)
    }
    
    func withUpdatedCanPinMessage(_ canPinMessage: Bool) -> ChatPresentationInterfaceState {
        return ChatPresentationInterfaceState(interfaceState: self.interfaceState, peer: self.peer, notificationSettings: self.notificationSettings, inputQueryResult: self.inputQueryResult, keyboardButtonsMessage:self.keyboardButtonsMessage, initialAction: self.initialAction, historyCount: self.historyCount, isSearchMode: self.isSearchMode, recordingState: self.recordingState, isBlocked: self.isBlocked, peerStatus: self.peerStatus, pinnedMessageId: self.pinnedMessageId, urlPreview: self.urlPreview, selectionState: self.selectionState, sidebarEnabled: self.sidebarEnabled, sidebarShown: self.sidebarShown, layout: self.layout, canAddContact: self.canAddContact, isEmojiSection: self.isEmojiSection, chatLocation: self.chatLocation, chatMode: self.chatMode, canInvokeBasicActions: self.canInvokeBasicActions, isNotAccessible: self.isNotAccessible, restrictionInfo: self.restrictionInfo, mainPeer: self.mainPeer, limitConfiguration: limitConfiguration, discussionGroupId: discussionGroupId, slowMode: self.slowMode, hasScheduled: self.hasScheduled, failedMessageIds: self.failedMessageIds, hidePinnedMessage: self.hidePinnedMessage, canPinMessage: canPinMessage, tempPinnedMaxId: self.tempPinnedMaxId, groupCall: self.groupCall)
    }
    
    func withUpdatedTempPinnedMaxId(_ tempPinnedMaxId: MessageId?) -> ChatPresentationInterfaceState {
        return ChatPresentationInterfaceState(interfaceState: self.interfaceState, peer: self.peer, notificationSettings: self.notificationSettings, inputQueryResult: self.inputQueryResult, keyboardButtonsMessage:self.keyboardButtonsMessage, initialAction: self.initialAction, historyCount: self.historyCount, isSearchMode: self.isSearchMode, recordingState: self.recordingState, isBlocked: self.isBlocked, peerStatus: self.peerStatus, pinnedMessageId: self.pinnedMessageId, urlPreview: self.urlPreview, selectionState: self.selectionState, sidebarEnabled: self.sidebarEnabled, sidebarShown: self.sidebarShown, layout: self.layout, canAddContact: self.canAddContact, isEmojiSection: self.isEmojiSection, chatLocation: self.chatLocation, chatMode: self.chatMode, canInvokeBasicActions: self.canInvokeBasicActions, isNotAccessible: self.isNotAccessible, restrictionInfo: self.restrictionInfo, mainPeer: self.mainPeer, limitConfiguration: limitConfiguration, discussionGroupId: discussionGroupId, slowMode: self.slowMode, hasScheduled: self.hasScheduled, failedMessageIds: self.failedMessageIds, hidePinnedMessage: self.hidePinnedMessage, canPinMessage: self.canPinMessage, tempPinnedMaxId: tempPinnedMaxId, groupCall: self.groupCall)
    }
    
    func updatedGroupCall(_ f: (ChatActiveGroupCallInfo?)->ChatActiveGroupCallInfo?) -> ChatPresentationInterfaceState {
        return ChatPresentationInterfaceState(interfaceState: self.interfaceState, peer: self.peer, notificationSettings: self.notificationSettings, inputQueryResult: self.inputQueryResult, keyboardButtonsMessage:self.keyboardButtonsMessage, initialAction: self.initialAction, historyCount: self.historyCount, isSearchMode: self.isSearchMode, recordingState: self.recordingState, isBlocked: self.isBlocked, peerStatus: self.peerStatus, pinnedMessageId: self.pinnedMessageId, urlPreview: self.urlPreview, selectionState: self.selectionState, sidebarEnabled: self.sidebarEnabled, sidebarShown: self.sidebarShown, layout: self.layout, canAddContact: self.canAddContact, isEmojiSection: self.isEmojiSection, chatLocation: self.chatLocation, chatMode: self.chatMode, canInvokeBasicActions: self.canInvokeBasicActions, isNotAccessible: self.isNotAccessible, restrictionInfo: self.restrictionInfo, mainPeer: self.mainPeer, limitConfiguration: limitConfiguration, discussionGroupId: discussionGroupId, slowMode: self.slowMode, hasScheduled: self.hasScheduled, failedMessageIds: self.failedMessageIds, hidePinnedMessage: self.hidePinnedMessage, canPinMessage: self.canPinMessage, tempPinnedMaxId: self.tempPinnedMaxId, groupCall: f(self.groupCall))
    }
}
