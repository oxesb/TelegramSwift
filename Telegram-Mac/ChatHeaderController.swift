//
//  ChatHeaderController.swift
//  TelegramMac
//
//  Created by keepcoder on 15/11/2016.
//  Copyright © 2016 Telegram. All rights reserved.
//


import Cocoa
import TGUIKit
import SwiftSignalKit
import TelegramCore
import SyncCore
import Postbox









enum ChatHeaderState : Identifiable, Equatable {
    case none
    case search(ChatSearchInteractions, Peer?, String?)
    case addContact(block: Bool, autoArchived: Bool)
    case shareInfo
    case pinned(ChatPinnedMessage, doNotChangeTable: Bool)
    case groupCall(ChatActiveGroupCallInfo)
    case report(autoArchived: Bool)
    case promo(PromoChatListItem.Kind)
    var stableId:Int {
        switch self {
        case .none:
            return 0
        case .search:
            return 1
        case .report:
            return 2
        case .addContact:
            return 3
        case .pinned:
            return 4
        case .promo:
            return 5
        case .shareInfo:
            return 6
        case .groupCall:
            return 7
        }
    }
    
    var viewClass: AnyClass? {
        switch self {
        case .addContact:
            return AddContactView.self
        case .shareInfo:
            return ShareInfoView.self
        case .pinned:
            return ChatPinnedView.self
        case .search:
            return ChatSearchHeader.self
        case .report:
            return ChatReportView.self
        case .promo:
            return ChatSponsoredView.self
        case .groupCall:
            return ChatGroupCallView.self
        case .none:
            return nil
        }
    }
    
    var height:CGFloat {
        switch self {
        case .none:
            return 0
        case .search:
            return 44
        case .report:
            return 44
        case .addContact:
            return 44
        case .shareInfo:
            return 44
        case .pinned:
            return 44
        case .promo:
            return 44
        case .groupCall:
            return 44
        }
    }
    
    var toleranceHeight: CGFloat {
        switch self {
        case let .pinned(_, doNotChangeTable):
            return doNotChangeTable ? 0 : height
        default:
            return height
        }
    }
    
    static func ==(lhs:ChatHeaderState, rhs: ChatHeaderState) -> Bool {
        switch lhs {
        case let .pinned(pinnedId, value):
            if case .pinned(pinnedId, value) = rhs {
                return true
            } else {
                return false
            }
        case let .addContact(block, autoArchive):
            if case .addContact(block, autoArchive) = rhs {
                return true
            } else {
                return false
            }
        case let .groupCall(data):
            if case .groupCall(data) = rhs {
                return true
            } else {
                return false
            }
        default:
            return lhs.stableId == rhs.stableId
        }
    }
}


class ChatHeaderController {
    
    
    private var _headerState:ChatHeaderState = .none
    private let chatInteraction:ChatInteraction
    
    private(set) var currentView:View?
    
    var state:ChatHeaderState {
        return _headerState
    }
    
    func updateState(_ state:ChatHeaderState, animated:Bool, for view:View) -> Void {
        if _headerState != state {
            let previousState = _headerState
            _headerState = state
            
            
            if previousState.viewClass == state.viewClass {
                switch state {
                case let .pinned(message, _):
                    (currentView as? ChatPinnedView)?.update(message, animated: animated)
                    return
                case let .groupCall(data):
                    (currentView as? ChatGroupCallView)?.update(data, animated: animated)
                    return
                default:
                    break
                }
            }
            
            if let current = currentView {
                if animated {
                    currentView?.layer?.animatePosition(from: NSZeroPoint, to: NSMakePoint(0, -previousState.height), duration: 0.2, removeOnCompletion:false, completion: { [weak current] complete in
                        if complete {
                            current?.removeFromSuperview()
                        }
                        
                    })
                } else {
                    currentView?.removeFromSuperview()
                    currentView = nil
                }
            }
            
            currentView = viewIfNecessary(NSMakeSize(view.frame.width, state.height))
            
            if let newView = currentView {
                view.addSubview(newView)
                (newView as? ChatSearchHeader)?.applySearchResponder()
                newView.layer?.removeAllAnimations()
                if animated {
                    newView.layer?.animatePosition(from: NSMakePoint(0,-state.height), to: NSZeroPoint, duration: 0.2, completion: { [weak newView] _ in
                        
                    })
                }
            }
        }
    }
    
    private func viewIfNecessary(_ size:NSSize) -> View? {
        let view:View?
        switch _headerState {
        case let .addContact(block, autoArchived):
            view = AddContactView(chatInteraction, canBlock: block, autoArchived: autoArchived)
        case .shareInfo:
            view = ShareInfoView(chatInteraction)
        case let .pinned(messageId, _):
            view = ChatPinnedView(messageId, chatInteraction: chatInteraction)
        case let .search(interactions, initialPeer, initialString):
            view = ChatSearchHeader(interactions, chatInteraction: chatInteraction, initialPeer: initialPeer, initialString: initialString)
        case let .report(autoArchived):
            view = ChatReportView(chatInteraction, autoArchived: autoArchived)
        case let .promo(kind):
            view = ChatSponsoredView(chatInteraction: chatInteraction, kind: kind)
        case let .groupCall(data):
            view = ChatGroupCallView(chatInteraction: chatInteraction, data: data, frame: NSMakeRect(0, 0, size.width, size.height))
        case .none:
            view = nil
        
        }
        view?.frame = NSMakeRect(0, 0, size.width, size.height)
        return view
    }
    
    init(_ chatInteraction:ChatInteraction) {
        self.chatInteraction = chatInteraction
    }
    
}

struct ChatSearchInteractions {
    let jump:(Message)->Void
    let results:(String)->Void
    let calendarAction:(Date)->Void
    let cancel:()->Void
    let searchRequest:(String, PeerId?, SearchMessagesState?) -> Signal<([Message], SearchMessagesState?), NoError>
}

private class ChatSponsoredModel: ChatAccessoryModel {
    

    init(title: String, text: String) {
        super.init()
        update(title: title, text: text)
    }
    
    func update(title: String, text: String) {
        //L10n.chatProxySponsoredCapTitle
        self.headerAttr = .initialize(string: title, color: theme.colors.link, font: .medium(.text))
        self.messageAttr = .initialize(string: text, color: theme.colors.text, font: .normal(.text))
        nodeReady.set(.single(true))
        self.setNeedDisplay()
    }
}

private extension PromoChatListItem.Kind {
    var title: String {
        switch self {
        case .proxy:
            return L10n.chatProxySponsoredCapTitle
        case .psa:
            return L10n.psaChatTitle
        }
    }
    var text: String {
        switch self {
        case .proxy:
            return L10n.chatProxySponsoredCapDesc
        case let .psa(type, _):
            return localizedPsa("psa.chat.text", type: type)
        }
    }
    var learnMore: String? {
        switch self {
        case .proxy:
            return nil
        case let .psa(type, _):
            let localized = localizedPsa("psa.chat.alert.learnmore", type: type)
            return localized != localized ? localized : nil
        }
    }
}

private final class ChatSponsoredView : Control {
    private let chatInteraction:ChatInteraction
    private let container:ChatAccessoryView = ChatAccessoryView()
    private let dismiss:ImageButton = ImageButton()
    private let node: ChatSponsoredModel
    private let kind: PromoChatListItem.Kind
    init(chatInteraction:ChatInteraction, kind: PromoChatListItem.Kind) {
        self.chatInteraction = chatInteraction
        
        self.kind = kind
        
        node = ChatSponsoredModel(title: kind.title, text: kind.text)
        super.init()
        
        dismiss.disableActions()
        self.dismiss.set(image: theme.icons.dismissPinned, for: .Normal)
        _ = self.dismiss.sizeToFit()
        
        self.set(handler: { _ in
            
            switch kind {
            case .proxy:
                confirm(for: chatInteraction.context.window, header: L10n.chatProxySponsoredAlertHeader, information: L10n.chatProxySponsoredAlertText, cancelTitle: "", thridTitle: L10n.chatProxySponsoredAlertSettings, successHandler: { result in
                    switch result {
                    case .thrid:
                        chatInteraction.openProxySettings()
                    default:
                        break
                    }
                })
            case .psa:
                if let learnMore = kind.learnMore {
                    confirm(for: chatInteraction.context.window, header: kind.title, information: kind.text, cancelTitle: "", thridTitle: learnMore, successHandler: { result in
                        switch result {
                        case .thrid:
                            execute(inapp: .external(link: learnMore, false))
                        default:
                            break
                        }
                    })
                }
                
            }
            
            
        }, for: .Click)
        
        dismiss.set(handler: { _ in
            FastSettings.removePromoTitle(for: chatInteraction.peerId)
            chatInteraction.update({$0.withoutInitialAction()})
        }, for: .SingleClick)
        
        node.view = container
        
        addSubview(dismiss)
        container.userInteractionEnabled = false
        self.style = ControlStyle(backgroundColor: theme.colors.background)
        addSubview(container)
        updateLocalizationAndTheme(theme: theme)
    }
    
    override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
        let theme = (theme as! TelegramPresentationTheme)
        self.backgroundColor = theme.colors.background
        self.dismiss.set(image: theme.icons.dismissPinned, for: .Normal)
        container.backgroundColor = theme.colors.background
        node.update(title: self.kind.title, text: self.kind.text)
    }
    
    override func layout() {
        node.update(title: self.kind.title, text: self.kind.text)
        node.measureSize(frame.width - 70)
        container.setFrameSize(frame.width - 70, node.size.height)
        container.centerY(x: 20)
        dismiss.centerY(x: frame.width - 20 - dismiss.frame.width)
        node.setNeedDisplay()
    }
    
    override func draw(_ layer: CALayer, in ctx: CGContext) {
        ctx.setFillColor(theme.colors.border.cgColor)
        ctx.fill(NSMakeRect(0, layer.frame.height - .borderSize, layer.frame.width, .borderSize))
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    required init(frame frameRect: NSRect) {
        fatalError("init(frame:) has not been implemented")
    }
}

class ChatPinnedView : Control {
    private var node:ReplyModel
    private let chatInteraction:ChatInteraction
    private let readyDisposable = MetaDisposable()
    private var container:ChatAccessoryView = ChatAccessoryView()
    private let dismiss:ImageButton = ImageButton()
    private let loadMessageDisposable = MetaDisposable()
    private var pinnedMessage: ChatPinnedMessage
    private let particleList: VerticalParticleListControl = VerticalParticleListControl()
    init(_ pinnedMessage:ChatPinnedMessage, chatInteraction:ChatInteraction) {
        self.pinnedMessage = pinnedMessage
        
        node = ReplyModel(replyMessageId: pinnedMessage.messageId, account: chatInteraction.context.account, replyMessage: pinnedMessage.message, isPinned: true, headerAsName: chatInteraction.mode.threadId != nil, customHeader: pinnedMessage.isLatest ? nil : pinnedMessage.totalCount == 2 ? L10n.chatHeaderPinnedPrevious : L10n.chatHeaderPinnedMessageNumer(pinnedMessage.totalCount - pinnedMessage.index), drawLine: false)
        self.chatInteraction = chatInteraction
        super.init()
        
        dismiss.disableActions()
        self.dismiss.set(image: pinnedMessage.totalCount <= 1 ? theme.icons.dismissPinned : theme.icons.chat_pinned_list, for: .Normal)
        _ = self.dismiss.sizeToFit()
        
        self.dismiss.isHidden = chatInteraction.mode.threadId == pinnedMessage.messageId
        
        self.set(handler: { [weak self] _ in
            guard let `self` = self else {
                return
            }
            if self.chatInteraction.mode.threadId == self.pinnedMessage.messageId {
                self.chatInteraction.scrollToTheFirst()
            } else {
                self.chatInteraction.focusPinnedMessageId(self.pinnedMessage.messageId)
            }
            
        }, for: .Click)
        
        dismiss.set(handler: { [weak self] _ in
            guard let `self` = self else {
                return
            }
            if self.pinnedMessage.totalCount > 1 {
                self.chatInteraction.openPinnedMessages(self.pinnedMessage.messageId)
            } else {
                self.chatInteraction.updatePinned(self.pinnedMessage.messageId, true, false, false)
            }
        }, for: .SingleClick)
        
        addSubview(dismiss)
        container.userInteractionEnabled = false
        self.style = ControlStyle(backgroundColor: theme.colors.background)
        addSubview(container)
        node.view = container
        readyDisposable.set(node.nodeReady.get().start(next: { [weak self] result in
            self?.needsLayout = true
            
            if !result, let chatInteraction = self?.chatInteraction {
                _ = requestUpdatePinnedMessage(account: chatInteraction.context.account, peerId: chatInteraction.peerId, update: .clear(id: pinnedMessage.messageId)).start()
            }
        }))
        
        particleList.frame = NSMakeRect(20, 5, 3, 34)
        
        addSubview(particleList)
        
        particleList.update(count: pinnedMessage.totalCount, selectedIndex: pinnedMessage.index, animated: false)
        
        updateLocalizationAndTheme(theme: theme)
    }
    
    func update(_ pinnedMessage: ChatPinnedMessage, animated: Bool) {
        
        let animated = animated && (!pinnedMessage.isLatest || (self.pinnedMessage.isLatest != pinnedMessage.isLatest))
        
        particleList.update(count: pinnedMessage.totalCount, selectedIndex: pinnedMessage.index, animated: animated)
        
        self.dismiss.set(image: pinnedMessage.totalCount <= 1 ? theme.icons.dismissPinned : theme.icons.chat_pinned_list, for: .Normal)
        
        if pinnedMessage.messageId != self.pinnedMessage.messageId {
            let oldContainer = self.container
            let newContainer = ChatAccessoryView()
            newContainer.userInteractionEnabled = false
            
            let newNode = ReplyModel(replyMessageId: pinnedMessage.messageId, account: chatInteraction.context.account, replyMessage: pinnedMessage.message, isPinned: true, headerAsName: chatInteraction.mode.threadId != nil, customHeader: pinnedMessage.isLatest ? nil : pinnedMessage.totalCount == 2 ? L10n.chatHeaderPinnedPrevious : L10n.chatHeaderPinnedMessageNumer(pinnedMessage.totalCount - pinnedMessage.index), drawLine: false)
            
            newNode.view = newContainer
            
            addSubview(newContainer)
            
            let width = frame.width - (40 + (dismiss.isHidden ? 0 : 30))
            newNode.measureSize(width)
            newContainer.setFrameSize(width, newNode.size.height)
            newContainer.centerY(x: 23)
            
            if animated {
                let oldFrom = oldContainer.frame.origin
                let oldTo = pinnedMessage.messageId > self.pinnedMessage.messageId ? NSMakePoint(oldContainer.frame.minX, -oldContainer.frame.height) : NSMakePoint(oldContainer.frame.minX, frame.height)
                
                
                oldContainer.layer?.animatePosition(from: oldFrom, to: oldTo, duration: 0.3, timingFunction: .spring, removeOnCompletion: false, completion: { [weak oldContainer] _ in
                    oldContainer?.removeFromSuperview()
                })
                oldContainer.layer?.animateAlpha(from: 1, to: 0, duration: 0.3, timingFunction: .spring, removeOnCompletion: false)
                
                
                let newTo = newContainer.frame.origin
                let newFrom = pinnedMessage.messageId < self.pinnedMessage.messageId ? NSMakePoint(newContainer.frame.minX, -newContainer.frame.height) : NSMakePoint(newContainer.frame.minX, frame.height)
                
                
                newContainer.layer?.animatePosition(from: newFrom, to: newTo, duration: 0.3, timingFunction: .spring)
                newContainer.layer?.animateAlpha(from: 0, to: 1, duration: 0.3
                    , timingFunction: .spring)
            } else {
                oldContainer.removeFromSuperview()
            }
            
            self.container = newContainer
            self.node = newNode
        }
        self.pinnedMessage = pinnedMessage
    }
    
    override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
        let theme = (theme as! TelegramPresentationTheme)
        node.update()
        self.backgroundColor = theme.colors.background
        self.dismiss.set(image: pinnedMessage.totalCount <= 1 ? theme.icons.dismissPinned : theme.icons.chat_pinned_list, for: .Normal)
        container.backgroundColor = theme.colors.background
    }
    
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
    }
    
 
    override func layout() {
        node.measureSize(frame.width - (40 + (dismiss.isHidden ? 0 : 30)))
        container.setFrameSize(frame.width - (40 + (dismiss.isHidden ? 0 : 30)), node.size.height)
        container.centerY(x: 23)
        dismiss.centerY(x: frame.width - 20 - dismiss.frame.width)
        node.setNeedDisplay()
    }
    
    override func draw(_ layer: CALayer, in ctx: CGContext) {
        ctx.setFillColor(theme.colors.border.cgColor)
        ctx.fill(NSMakeRect(0, layer.frame.height - .borderSize, layer.frame.width, .borderSize))
    }
    
    deinit {
        readyDisposable.dispose()
        loadMessageDisposable.dispose()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    required init(frame frameRect: NSRect) {
        fatalError("init(frame:) has not been implemented")
    }
}

class ChatReportView : Control {
    private let chatInteraction:ChatInteraction
    private let report:TitleButton = TitleButton()
    private let unarchiveButton = TitleButton()
    private let dismiss:ImageButton = ImageButton()

    private let buttonsContainer = View()
    
    init(_ chatInteraction:ChatInteraction, autoArchived: Bool) {
        self.chatInteraction = chatInteraction
        super.init()
        dismiss.disableActions()
        
        self.style = ControlStyle(backgroundColor: theme.colors.background)
        
        report.set(text: L10n.chatHeaderReportSpam, for: .Normal)
        _ = report.sizeToFit()
        
        self.dismiss.set(image: theme.icons.dismissPinned, for: .Normal)
        _ = self.dismiss.sizeToFit()
        
        report.set(handler: { _ in
            chatInteraction.blockContact()
        }, for: .SingleClick)
        
        dismiss.set(handler: { _ in
            chatInteraction.dismissPeerStatusOptions()
        }, for: .SingleClick)
        
        unarchiveButton.set(handler: { _ in
            chatInteraction.unarchive()
        }, for: .SingleClick)
        
        buttonsContainer.addSubview(report)

        if autoArchived {
            buttonsContainer.addSubview(unarchiveButton)
        }
        addSubview(buttonsContainer)
        
        addSubview(dismiss)
        updateLocalizationAndTheme(theme: theme)
    }
    
    override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
        let theme = (theme as! TelegramPresentationTheme)
        dismiss.set(image: theme.icons.dismissPinned, for: .Normal)
        report.set(text: tr(L10n.chatHeaderReportSpam), for: .Normal)
        report.style = ControlStyle(font: .normal(.text), foregroundColor: theme.colors.redUI, backgroundColor: theme.colors.background, highlightColor: theme.colors.accentSelect)
        _ = report.sizeToFit()
        
        unarchiveButton.set(text: L10n.peerInfoUnarchive, for: .Normal)
        
        unarchiveButton.style = ControlStyle(font: .normal(.text), foregroundColor: theme.colors.accent, backgroundColor: theme.colors.background, highlightColor: theme.colors.accentSelect)
        
        self.backgroundColor = theme.colors.background
        needsLayout = true
    }
    
    override func draw(_ layer: CALayer, in ctx: CGContext) {
        super.draw(layer, in: ctx)
        ctx.setFillColor(theme.colors.border.cgColor)
        ctx.fill(NSMakeRect(0, layer.frame.height - .borderSize, layer.frame.width, .borderSize))
    }
    
    override func layout() {
        report.center()
        dismiss.centerY(x: frame.width - dismiss.frame.width - 20)
        
        
        buttonsContainer.frame = NSMakeRect(0, 0, frame.width, frame.height - .borderSize)
        
        
        var buttons:[Control] = []
        if report.superview != nil {
            buttons.append(report)
        }
        if unarchiveButton.superview != nil {
            buttons.append(unarchiveButton)
        }
        
        let buttonWidth: CGFloat = floor(buttonsContainer.frame.width / CGFloat(buttons.count))
        var x: CGFloat = 0
        for button in buttons {
            button.frame = NSMakeRect(x, 0, buttonWidth, buttonsContainer.frame.height)
            x += buttonWidth
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    required init(frame frameRect: NSRect) {
        fatalError("init(frame:) has not been implemented")
    }
}

class ShareInfoView : Control {
    private let chatInteraction:ChatInteraction
    private let share:TitleButton = TitleButton()
    private let dismiss:ImageButton = ImageButton()
    init(_ chatInteraction:ChatInteraction) {
        self.chatInteraction = chatInteraction
        super.init()
        self.style = ControlStyle(backgroundColor: theme.colors.background)
        dismiss.disableActions()
        
        dismiss.set(image: theme.icons.dismissPinned, for: .Normal)
        _ = dismiss.sizeToFit()
        
        share.set(handler: { _ in
            chatInteraction.shareSelfContact(nil)
            chatInteraction.dismissPeerStatusOptions()
        }, for: .SingleClick)
        
        dismiss.set(handler: { _ in
            chatInteraction.dismissPeerStatusOptions()
        }, for: .SingleClick)
        
        
        
        addSubview(share)
        addSubview(dismiss)
        updateLocalizationAndTheme(theme: theme)
    }
    
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        
        if window == nil {
            var bp:Int = 0
            bp += 1
        }
    }
    
    override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
        let theme = (theme as! TelegramPresentationTheme)
        dismiss.set(image: theme.icons.dismissPinned, for: .Normal)
        share.style = ControlStyle(font: .normal(.text), foregroundColor: theme.colors.accent, backgroundColor: theme.colors.background, highlightColor: theme.colors.accentSelect)
        
        share.set(text: L10n.peerInfoShareMyInfo, for: .Normal)

        self.backgroundColor = theme.colors.background
        needsLayout = true
    }
    
    override func draw(_ layer: CALayer, in ctx: CGContext) {
        super.draw(layer, in: ctx)
        ctx.setFillColor(theme.colors.border.cgColor)
        ctx.fill(NSMakeRect(0, layer.frame.height - .borderSize, layer.frame.width, .borderSize))
    }
    
    override func layout() {
        super.layout()
        dismiss.centerY(x: frame.width - dismiss.frame.width - 20)
        share.center()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    required init(frame frameRect: NSRect) {
        fatalError("init(frame:) has not been implemented")
    }
}

class AddContactView : Control {
    private let chatInteraction:ChatInteraction
    private let add:TitleButton = TitleButton()
    private let dismiss:ImageButton = ImageButton()
    private let blockButton: TitleButton = TitleButton()
    private let unarchiveButton = TitleButton()
    private let buttonsContainer = View()
    init(_ chatInteraction:ChatInteraction, canBlock: Bool, autoArchived: Bool) {
        self.chatInteraction = chatInteraction
        super.init()
        self.style = ControlStyle(backgroundColor: theme.colors.background)
        dismiss.disableActions()
        
        dismiss.set(image: theme.icons.dismissPinned, for: .Normal)
        _ = dismiss.sizeToFit()

        add.set(handler: { _ in
            chatInteraction.addContact()
        }, for: .SingleClick)
        
        dismiss.set(handler: { _ in
            chatInteraction.dismissPeerStatusOptions()
        }, for: .SingleClick)
        
        blockButton.set(handler: { _ in
            chatInteraction.blockContact()
        }, for: .SingleClick)
        
        unarchiveButton.set(handler: { _ in
            chatInteraction.unarchive()
        }, for: .SingleClick)
        
       
        
        if canBlock {
            buttonsContainer.addSubview(blockButton)
        }
        if autoArchived {
            buttonsContainer.addSubview(unarchiveButton)
        }
        
        if !autoArchived && canBlock {
            buttonsContainer.addSubview(add)
        } else if !autoArchived && !canBlock {
            buttonsContainer.addSubview(add)
        }
        
        addSubview(buttonsContainer)
        addSubview(dismiss)
        updateLocalizationAndTheme(theme: theme)
    }
    
    override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
        let theme = (theme as! TelegramPresentationTheme)
        dismiss.set(image: theme.icons.dismissPinned, for: .Normal)
        add.style = ControlStyle(font: .normal(.text), foregroundColor: theme.colors.accent, backgroundColor: theme.colors.background, highlightColor: theme.colors.accentSelect)
        blockButton.style = ControlStyle(font: .normal(.text), foregroundColor: theme.colors.redUI, backgroundColor: theme.colors.background, highlightColor: theme.colors.redUI)
        
        if blockButton.superview == nil, let peer = chatInteraction.peer {
            add.set(text: L10n.peerInfoAddUserToContact(peer.compactDisplayTitle), for: .Normal)
        } else {
            add.set(text: L10n.peerInfoAddContact, for: .Normal)
        }
        blockButton.set(text: L10n.peerInfoBlockUser, for: .Normal)
        unarchiveButton.set(text: L10n.peerInfoUnarchive, for: .Normal)
        
        unarchiveButton.style = ControlStyle(font: .normal(.text), foregroundColor: theme.colors.accent, backgroundColor: theme.colors.background, highlightColor: theme.colors.accentSelect)
        
        self.backgroundColor = theme.colors.background
        needsLayout = true
    }
    
    override func draw(_ layer: CALayer, in ctx: CGContext) {
        super.draw(layer, in: ctx)
        ctx.setFillColor(theme.colors.border.cgColor)
        ctx.fill(NSMakeRect(0, layer.frame.height - .borderSize, layer.frame.width, .borderSize))
    }
    
    override func layout() {
        dismiss.centerY(x: frame.width - dismiss.frame.width - 20)
        
        var buttons:[Control] = []
        
        
        if add.superview != nil {
            buttons.append(add)
        }
        if blockButton.superview != nil {
            buttons.append(blockButton)
        }
        if unarchiveButton.superview != nil {
            buttons.append(unarchiveButton)
        }
        
        buttonsContainer.frame = NSMakeRect(0, 0, frame.width - (frame.width - dismiss.frame.minX), frame.height - .borderSize)

        
        let buttonWidth: CGFloat = floor(buttonsContainer.frame.width / CGFloat(buttons.count))
        var x: CGFloat = 0
        for button in buttons {
            button.frame = NSMakeRect(x, 0, buttonWidth, buttonsContainer.frame.height)
            x += buttonWidth
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    required init(frame frameRect: NSRect) {
        fatalError("init(frame:) has not been implemented")
    }
}

private final class CSearchContextState : Equatable {
    let inputQueryResult: ChatPresentationInputQueryResult?
    let tokenState: TokenSearchState
    let peerId:PeerId?
    let messages: ([Message], SearchMessagesState?)
    let selectedIndex: Int
    let searchState: SearchState
    
    init(inputQueryResult: ChatPresentationInputQueryResult? = nil, messages: ([Message], SearchMessagesState?) = ([], nil), selectedIndex: Int = -1, searchState: SearchState = SearchState(state: .None, request: ""), tokenState: TokenSearchState = .none, peerId: PeerId? = nil) {
        self.inputQueryResult = inputQueryResult
        self.tokenState = tokenState
        self.peerId = peerId
        self.messages = messages
        self.selectedIndex = selectedIndex
        self.searchState = searchState
    }
    func updatedInputQueryResult(_ f: (ChatPresentationInputQueryResult?) -> ChatPresentationInputQueryResult?) -> CSearchContextState {
        return CSearchContextState(inputQueryResult: f(self.inputQueryResult), messages: self.messages, selectedIndex: self.selectedIndex, searchState: self.searchState, tokenState: self.tokenState, peerId: self.peerId)
    }
    func updatedTokenState(_ token: TokenSearchState) -> CSearchContextState {
        return CSearchContextState(inputQueryResult: self.inputQueryResult, messages: self.messages, selectedIndex: self.selectedIndex, searchState: self.searchState, tokenState: token, peerId: self.peerId)
    }
    func updatedPeerId(_ peerId: PeerId?) -> CSearchContextState {
        return CSearchContextState(inputQueryResult: self.inputQueryResult, messages: self.messages, selectedIndex: self.selectedIndex, searchState: self.searchState, tokenState: self.tokenState, peerId: peerId)
    }
    func updatedMessages(_ messages: ([Message], SearchMessagesState?)) -> CSearchContextState {
        return CSearchContextState(inputQueryResult: self.inputQueryResult, messages: messages, selectedIndex: self.selectedIndex, searchState: self.searchState, tokenState: self.tokenState, peerId: self.peerId)
    }
    func updatedSelectedIndex(_ selectedIndex: Int) -> CSearchContextState {
        return CSearchContextState(inputQueryResult: self.inputQueryResult, messages: self.messages, selectedIndex: selectedIndex, searchState: self.searchState, tokenState: self.tokenState, peerId: self.peerId)
    }
    func updatedSearchState(_ searchState: SearchState) -> CSearchContextState {
        return CSearchContextState(inputQueryResult: self.inputQueryResult, messages: self.messages, selectedIndex: self.selectedIndex, searchState: searchState, tokenState: self.tokenState, peerId: self.peerId)
    }
}

private func ==(lhs: CSearchContextState, rhs: CSearchContextState) -> Bool {
    if lhs.messages.0.count != rhs.messages.0.count {
        return false
    } else {
        for i in 0 ..< lhs.messages.0.count {
            if !isEqualMessages(lhs.messages.0[i], rhs.messages.0[i]) {
                return false
            }
        }
    }
    return lhs.inputQueryResult == rhs.inputQueryResult && lhs.tokenState == rhs.tokenState && lhs.selectedIndex == rhs.selectedIndex && lhs.searchState == rhs.searchState && lhs.messages.1 == rhs.messages.1
}

private final class CSearchInteraction : InterfaceObserver {
    private(set) var state: CSearchContextState = CSearchContextState()
    
    func update(animated:Bool = true, _ f:(CSearchContextState)->CSearchContextState) -> Void {
        let oldValue = self.state
        self.state = f(state)
        if oldValue != state {
            notifyObservers(value: state, oldValue:oldValue, animated: animated)
        }
    }
    
    var currentMessage: Message? {
        if state.messages.0.isEmpty {
            return nil
        } else if state.messages.0.count <= state.selectedIndex || state.selectedIndex < 0 {
            return nil
        }
        return state.messages.0[state.selectedIndex]
    }
}

struct SearchStateQuery : Equatable {
    let query: String?
    let state: SearchMessagesState?
    init(_ query: String?, _ state: SearchMessagesState?) {
        self.query = query
        self.state = state
    }
}

struct SearchMessagesResultState : Equatable {
    static func == (lhs: SearchMessagesResultState, rhs: SearchMessagesResultState) -> Bool {
        if lhs.query != rhs.query {
            return false
        }
        if lhs.messages.count != rhs.messages.count {
            return false
        } else {
            for i in 0 ..< lhs.messages.count {
                if !isEqualMessages(lhs.messages[i], rhs.messages[i]) {
                    return false
                }
            }
        }
        return true
    }
    
    let query: String
    let messages: [Message]
    init(_ query: String, _ messages: [Message]) {
        self.query = query
        self.messages = messages
    }
    
    func containsMessage(_ message: Message) -> Bool {
        return self.messages.contains(where: { $0.id == message.id })
    }
}

class ChatSearchHeader : View, Notifable {
    
    private let searchView:ChatSearchView = ChatSearchView(frame: NSZeroRect)
    private let cancel:ImageButton = ImageButton()
    private let from:ImageButton = ImageButton()
    private let calendar:ImageButton = ImageButton()
    
    private let prev:ImageButton = ImageButton()
    private let next:ImageButton = ImageButton()

    
    private let separator:View = View()
    private let interactions:ChatSearchInteractions
    private let chatInteraction: ChatInteraction
    
    private let query:ValuePromise<SearchStateQuery> = ValuePromise()

    private let disposable:MetaDisposable = MetaDisposable()
    
    private var contextQueryState: (ChatPresentationInputQuery?, Disposable)?
    private let inputContextHelper: InputContextHelper
    private let inputInteraction: CSearchInteraction = CSearchInteraction()
    private let parentInteractions: ChatInteraction
    private let loadingDisposable = MetaDisposable()
   
    private let calendarController: CalendarController
    init(_ interactions:ChatSearchInteractions, chatInteraction: ChatInteraction, initialPeer: Peer?, initialString: String?) {
        self.interactions = interactions
        self.parentInteractions = chatInteraction
        self.calendarController = CalendarController(NSMakeRect(0, 0, 250, 250), chatInteraction.context.window, selectHandler: interactions.calendarAction)
        self.chatInteraction = ChatInteraction(chatLocation: chatInteraction.chatLocation, context: chatInteraction.context, mode: chatInteraction.mode)
        self.chatInteraction.update({$0.updatedPeer({_ in chatInteraction.presentation.peer})})
        self.inputContextHelper = InputContextHelper(chatInteraction: self.chatInteraction, highlightInsteadOfSelect: true)
        
        if let initialString = initialString {
            searchView.setString(initialString)
            self.query.set(SearchStateQuery(initialString, nil))
        }

        
        super.init()
        
        self.chatInteraction.movePeerToInput = { [weak self] peer in
            self?.searchView.completeToken(peer.compactDisplayTitle)
            self?.inputInteraction.update({$0.updatedPeerId(peer.id)})
        }
        
        
        self.chatInteraction.focusMessageId = { [weak self] fromId, messageId, state in
            self?.parentInteractions.focusMessageId(fromId, messageId, state)
            self?.inputInteraction.update({$0.updatedSelectedIndex($0.messages.0.firstIndex(where: {$0.id == messageId}) ?? -1)})
            _ = self?.window?.makeFirstResponder(nil)
        }
        
     

        initialize()
        

        
        parentInteractions.loadingMessage.set(.single(false))
        
        inputInteraction.add(observer: self)
        self.loadingDisposable.set((parentInteractions.loadingMessage.get() |> deliverOnMainQueue).start(next: { [weak self] loading in
            self?.searchView.isLoading = loading
        }))
        if let initialPeer = initialPeer {
            self.chatInteraction.movePeerToInput(initialPeer)
            Queue.mainQueue().justDispatch {
                self.searchView.change(state: .Focus, false)
            }
        }
      
    }
    
    func applySearchResponder(_ animated: Bool = false) {
       // _ = window?.makeFirstResponder(searchView.input)
        searchView.layout()
        if searchView.state == .Focus && window?.firstResponder != searchView.input {
            _ = window?.makeFirstResponder(searchView.input)
        }
        searchView.change(state: .Focus, false)
    }
    
    private var calendarAbility: Bool {
        return chatInteraction.mode != .scheduled && chatInteraction.mode != .pinned
    }
    
    private var fromAbility: Bool {
        if let peer = chatInteraction.presentation.peer {
            return (peer.isSupergroup || peer.isGroup) && (chatInteraction.mode == .history || chatInteraction.mode.isThreadMode)
        } else {
            return false
        }
    }
    
    func notify(with value: Any, oldValue: Any, animated: Bool) {
        let context = chatInteraction.context
        if let value = value as? CSearchContextState, let oldValue = oldValue as? CSearchContextState, let view = superview {
            
            let stateValue = self.query
            
            prev.isEnabled = !value.messages.0.isEmpty && value.selectedIndex < value.messages.0.count - 1
            next.isEnabled = !value.messages.0.isEmpty && value.selectedIndex > 0
            next.set(image: next.isEnabled ? theme.icons.chatSearchDown : theme.icons.chatSearchDownDisabled, for: .Normal)
            prev.set(image: prev.isEnabled ? theme.icons.chatSearchUp : theme.icons.chatSearchUpDisabled, for: .Normal)

            
            
            if let peer = chatInteraction.presentation.peer {
                if value.inputQueryResult != oldValue.inputQueryResult {
                    inputContextHelper.context(with: value.inputQueryResult, for: view, relativeView: self, position: .below, selectIndex: value.selectedIndex != -1 ? value.selectedIndex : nil, animated: animated)
                }
                switch value.tokenState {
                case .none:
                    from.isHidden = !fromAbility
                    calendar.isHidden = !calendarAbility
                    needsLayout = true
                    searchView.change(size: NSMakeSize(searchWidth, searchView.frame.height), animated: animated)
                    
                    if (peer.isSupergroup || peer.isGroup) && chatInteraction.mode == .history {
                        if let (updatedContextQueryState, updatedContextQuerySignal) = chatContextQueryForSearchMention(chatLocations: [chatInteraction.chatLocation], .mention(query: value.searchState.request, includeRecent: false), currentQuery: self.contextQueryState?.0, context: context) {
                            self.contextQueryState?.1.dispose()
                            self.contextQueryState = (updatedContextQueryState, (updatedContextQuerySignal |> deliverOnMainQueue).start(next: { [weak self] result in
                                if let strongSelf = self {
                                    strongSelf.inputInteraction.update(animated: animated, { state in
                                        return state.updatedInputQueryResult { previousResult in
                                            let messages = state.searchState.responder ? state.messages : ([], nil)
                                            var suggestedPeers:[Peer] = []
                                            let inputQueryResult = result(previousResult)
                                            if let inputQueryResult = inputQueryResult, state.searchState.responder, !state.searchState.request.isEmpty, messages.1 != nil {
                                                switch inputQueryResult {
                                                case let .mentions(mentions):
                                                    suggestedPeers = mentions
                                                default:
                                                    break
                                                }
                                            }
                                            return .searchMessages((messages.0, messages.1, { searchMessagesState in
                                                stateValue.set(SearchStateQuery(state.searchState.request, searchMessagesState))
                                            }), suggestedPeers, state.searchState.request)
                                        }
                                    })
                                }
                            }))
                        }
                    } else {
                        inputInteraction.update(animated: animated, { state in
                            return state.updatedInputQueryResult { previousResult in
                                let result = state.searchState.responder ? state.messages : ([], nil)
                                return .searchMessages((result.0, result.1, { searchMessagesState in
                                    stateValue.set(SearchStateQuery(state.searchState.request, searchMessagesState))
                                }), [], state.searchState.request)
                            }
                        })
                    }
                    
                    
                case let .from(query, complete):
                    from.isHidden = true
                    calendar.isHidden = true
                    searchView.change(size: NSMakeSize(searchWidth, searchView.frame.height), animated: animated)
                    needsLayout = true
                    if complete {
                        inputInteraction.update(animated: animated, { state in
                            return state.updatedInputQueryResult { previousResult in
                                let result = state.searchState.responder ? state.messages : ([], nil)
                                return .searchMessages((result.0, result.1, { searchMessagesState in
                                    stateValue.set(SearchStateQuery(state.searchState.request, searchMessagesState))
                                }), [], state.searchState.request)
                            }
                        })
                    } else {
                        if let (updatedContextQueryState, updatedContextQuerySignal) = chatContextQueryForSearchMention(chatLocations: [chatInteraction.chatLocation], .mention(query: query, includeRecent: false), currentQuery: self.contextQueryState?.0, context: context) {
                            self.contextQueryState?.1.dispose()
                            var inScope = true
                            var inScopeResult: ((ChatPresentationInputQueryResult?) -> ChatPresentationInputQueryResult?)?
                            self.contextQueryState = (updatedContextQueryState, (updatedContextQuerySignal |> deliverOnMainQueue).start(next: { [weak self] result in
                                if let strongSelf = self {
                                    if Thread.isMainThread && inScope {
                                        inScope = false
                                        inScopeResult = result
                                    } else {
                                        strongSelf.inputInteraction.update(animated: animated, {
                                            $0.updatedInputQueryResult { previousResult in
                                                return result(previousResult)
                                            }.updatedMessages(([], nil)).updatedSelectedIndex(-1)
                                        })
                                        
                                    }
                                }
                            }))
                            inScope = false
                            if let inScopeResult = inScopeResult {
                                inputInteraction.update(animated: animated, {
                                    $0.updatedInputQueryResult { previousResult in
                                        return inScopeResult(previousResult)
                                    }.updatedMessages(([], nil)).updatedSelectedIndex(-1)
                                })
                            }
                        }
                    }
                }
            }
        }
    }
    
    func isEqual(to other: Notifable) -> Bool {
        if let to = other as? ChatSearchView {
            return to === other
        } else {
            return false
        }
    }
    
    
    
    
    
    private func initialize() {
        self.from.isHidden = !fromAbility
        
        _ = self.searchView.tokenPromise.get().start(next: { [weak self] state in
            self?.inputInteraction.update({$0.updatedTokenState(state)})
        })
        
     
        self.searchView.searchInteractions = SearchInteractions({ [weak self] state, _ in
            if state.state == .None {
                self?.parentInteractions.loadingMessage.set(.single(false))
                self?.parentInteractions.updateSearchRequest(SearchMessagesResultState(state.request, []))
                self?.inputInteraction.update({$0.updatedMessages(([], nil)).updatedSelectedIndex(-1).updatedSearchState(state)})
            }
        }, { [weak self] state in
            guard let `self` = self else {return}
            
            self.inputInteraction.update({$0.updatedMessages(([], nil)).updatedSelectedIndex(-1).updatedSearchState(state)})
            
            self.updateSearchState()
            switch self.searchView.tokenState {
            case .none:
                if state.request == L10n.chatSearchFrom, let peer = self.chatInteraction.presentation.peer, peer.isGroup || peer.isSupergroup  {
                    self.query.set(SearchStateQuery("", nil))
                    self.parentInteractions.updateSearchRequest(SearchMessagesResultState("", []))
                    self.searchView.initToken()
                } else {
                    self.parentInteractions.updateSearchRequest(SearchMessagesResultState(state.request, []))
                    self.parentInteractions.loadingMessage.set(.single(true))
                    self.query.set(SearchStateQuery(state.request, nil))
                }
                
            case .from(_, let complete):
                if complete {
                    self.parentInteractions.updateSearchRequest(SearchMessagesResultState(state.request, []))
                    self.parentInteractions.loadingMessage.set(.single(true))
                    self.query.set(SearchStateQuery(state.request, nil))
                }
            }
            
        }, responderModified: { [weak self] state in
            self?.inputInteraction.update({$0.updatedSearchState(state)})
        })
 
        
        let apply = query.get() |> mapToSignal { [weak self] state -> Signal<([Message], SearchMessagesState?, String), NoError> in
            
            guard let `self` = self else { return .single(([], nil, "")) }
            if let query = state.query {
                
                let stateSignal: Signal<SearchMessagesState?, NoError>
                if state.state == nil {
                    stateSignal = .single(state.state) |> delay(0.3, queue: Queue.mainQueue())
                } else {
                    stateSignal = .single(state.state)
                }
                
                return stateSignal |> mapToSignal { [weak self] state in
                    
                    guard let `self` = self else { return .single(([], nil, "")) }
                    
                    let emptyRequest: Bool
                    if case .from = self.inputInteraction.state.tokenState {
                        emptyRequest = true
                    } else {
                        emptyRequest = !query.isEmpty
                    }
                    if emptyRequest {
                        return self.interactions.searchRequest(query, self.inputInteraction.state.peerId, state) |> map { ($0.0, $0.1, query) }
                    } else {
                        return .single(([], nil, ""))
                    }
                }
            } else {
                return .single(([], nil, ""))
            }
        } |> deliverOnMainQueue
        
        self.disposable.set(apply.start(next: { [weak self] messages in
            guard let `self` = self else {return}
            self.parentInteractions.updateSearchRequest(SearchMessagesResultState(messages.2, messages.0))
            self.inputInteraction.update({$0.updatedMessages((messages.0, messages.1)).updatedSelectedIndex(-1)})
            self.parentInteractions.loadingMessage.set(.single(false))
        }))
        
        next.autohighlight = false
        prev.autohighlight = false



        _ = calendar.sizeToFit()
        
        addSubview(next)
        addSubview(prev)

        
        addSubview(from)
        
        
        addSubview(calendar)
        
        calendar.isHidden = !calendarAbility
        
        _ = cancel.sizeToFit()
        
        let interactions = self.interactions
        let searchView = self.searchView
        cancel.set(handler: { [weak self] _ in
            self?.inputInteraction.update {$0.updatedTokenState(.none).updatedSelectedIndex(-1).updatedMessages(([], nil)).updatedSearchState(SearchState(state: .None, request: ""))}
            self?.parentInteractions.updateSearchRequest(SearchMessagesResultState("", []))
            interactions.cancel()
        }, for: .Click)
        
        next.set(handler: { [weak self] _ in
            self?.nextAction()
            }, for: .Click)
        prev.set(handler: { [weak self] _ in
            self?.prevAction()
        }, for: .Click)

        

        from.set(handler: { [weak self] _ in
            self?.searchView.initToken()
        }, for: .Click)
        
        
        
        calendar.set(handler: { [weak self] calendar in
            guard let `self` = self else {return}
            showPopover(for: calendar, with: self.calendarController, edge: .maxY, inset: NSMakePoint(-160, -40))
        }, for: .Click)

        addSubview(searchView)
        addSubview(cancel)
        addSubview(separator)
        
        updateLocalizationAndTheme(theme: theme)
    }
    
    override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
        let theme = (theme as! TelegramPresentationTheme)
        backgroundColor = theme.colors.background
        
        next.set(image: theme.icons.chatSearchDown, for: .Normal)
        _ = next.sizeToFit()
        
        prev.set(image: theme.icons.chatSearchUp, for: .Normal)
        _ = prev.sizeToFit()


        calendar.set(image: theme.icons.chatSearchCalendar, for: .Normal)
        _ = calendar.sizeToFit()
        
        cancel.set(image: theme.icons.chatSearchCancel, for: .Normal)
        _ = cancel.sizeToFit()

        from.set(image: theme.icons.chatSearchFrom, for: .Normal)
        _ = from.sizeToFit()
        
        separator.backgroundColor = theme.colors.border
        self.backgroundColor = theme.colors.background
        needsLayout = true
        updateSearchState()
    }
    
    func updateSearchState() {
       
    }
    
    func prevAction() {
        inputInteraction.update({$0.updatedSelectedIndex(min($0.selectedIndex + 1, $0.messages.0.count - 1))})
        perform()
    }
    
    func perform() {
        _ = window?.makeFirstResponder(nil)
        if let currentMessage = inputInteraction.currentMessage {
            interactions.jump(currentMessage)
        }
    }
    
    func nextAction() {
        inputInteraction.update({$0.updatedSelectedIndex(max($0.selectedIndex - 1, 0))})
        perform()
    }
    
    private var searchWidth: CGFloat {
        return frame.width - cancel.frame.width - 20 - 20 - 80 - (calendar.isHidden ? 0 : calendar.frame.width + 20) - (from.isHidden ? 0 : from.frame.width + 20)
    }
    
    override func layout() {
        super.layout()
        
        
        prev.centerY(x:10)
        next.centerY(x:prev.frame.maxX)


        cancel.centerY(x:frame.width - cancel.frame.width - 20)

        searchView.setFrameSize(NSMakeSize(searchWidth, 30))
        inputContextHelper.controller.view.setFrameSize(frame.width, inputContextHelper.controller.frame.height)
        searchView.centerY(x: 80)
        separator.frame = NSMakeRect(0, frame.height - .borderSize, frame.width, .borderSize)
        
        from.centerY(x: searchView.frame.maxX + 20)
        calendar.centerY(x: (from.isHidden ? searchView : from).frame.maxX + 20)

    }
    
    override func viewDidMoveToWindow() {
        if let _ = window {
            layout()
            //self.searchView.change(state: .Focus, false)
        }
    }
    
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil {
         //   self.searchView.change(state: .None, false)
        }
    }
    
    
    deinit {
        inputInteraction.update(animated: false, { state in
            return state.updatedInputQueryResult( { _ in return nil } )
        })
        parentInteractions.updateSearchRequest(SearchMessagesResultState("", []))
        disposable.dispose()
        inputInteraction.remove(observer: self)
        loadingDisposable.set(nil)
        if let window = window as? Window {
            window.removeAllHandlers(for: self)
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    init(frame frameRect: NSRect, interactions:ChatSearchInteractions, chatInteraction: ChatInteraction) {
        self.interactions = interactions
        self.chatInteraction = chatInteraction
        self.parentInteractions = chatInteraction
        self.inputContextHelper = InputContextHelper(chatInteraction: chatInteraction, highlightInsteadOfSelect: true)
        self.calendarController = CalendarController(NSMakeRect(0,0,250,250), chatInteraction.context.window, selectHandler: interactions.calendarAction)
        super.init(frame: frameRect)
        initialize()
    }
    
    required init(frame frameRect: NSRect) {
        fatalError("init(frame:) has not been implemented")
    }
}




private final class ChatGroupCallView : Control {
    
    struct Avatar : Comparable, Identifiable {
        static func < (lhs: Avatar, rhs: Avatar) -> Bool {
            return lhs.index < rhs.index
        }
        var stableId: PeerId {
            return peer.id
        }
        static func == (lhs: Avatar, rhs: Avatar) -> Bool {
            if lhs.index != rhs.index {
                return false
            }
            if !lhs.peer.isEqual(rhs.peer) {
                return false
            }
            return true
        }
        
        let peer: Peer
        let index: Int
    }
    private var topPeers: [Avatar] = []
    private var avatars:[AvatarContentView] = []
    private let avatarsContainer = View(frame: NSMakeRect(0, 0, 30 * 3, 30))

    private let joinButton = TitleButton()
    private var data: ChatActiveGroupCallInfo
    private let chatInteraction: ChatInteraction
    private let headerView = TextView()
    private let membersCountView = TextView()
    private let button = Control()
    private var speakingActivity: DynamicCounterTextView?
    private var activeCallButton: ImageButton = ImageButton()
    
    private let stateDisposable = MetaDisposable()
    
    init(chatInteraction: ChatInteraction, data: ChatActiveGroupCallInfo, frame: NSRect) {
        self.data = data
        self.chatInteraction = chatInteraction
        super.init(frame: frame)
        addSubview(joinButton)
        addSubview(headerView)
        addSubview(membersCountView)
        addSubview(button)
        addSubview(activeCallButton)
        addSubview(avatarsContainer)
        avatarsContainer.isEventLess = true
        
        activeCallButton.setFrameSize(NSMakeSize(36, 36))
        activeCallButton.layer?.cornerRadius = activeCallButton.frame.height / 2
        
        headerView.userInteractionEnabled = false
        headerView.isSelectable = false
        membersCountView.userInteractionEnabled = false
        membersCountView.isSelectable = false
        
        joinButton.set(handler: { [weak self] _ in
            if let `self` = self {
                self.chatInteraction.joinGroupCall(self.data.activeCall)
            }
        }, for: .SingleClick)
        
        button.set(handler: { [weak self] _ in
            if let `self` = self {
                self.chatInteraction.joinGroupCall(self.data.activeCall)
            }
        }, for: .SingleClick)
        
        button.set(handler: { [weak self] _ in
            self?.headerView.change(opacity: 0.6, animated: true)
            if self?.speakingActivity == nil {
                self?.membersCountView.change(opacity: 0.6, animated: true)
            }
            self?.speakingActivity?.change(opacity: 0.6, animated: true)
        }, for: .Highlight)
        
        button.set(handler: { [weak self] _ in
            self?.headerView.change(opacity: 1, animated: true)
            if self?.speakingActivity == nil {
                self?.membersCountView.change(opacity: 1, animated: true)
            }
            self?.speakingActivity?.change(opacity: 1, animated: true)
        }, for: .Normal)
        
        button.set(handler: { [weak self] _ in
            self?.headerView.change(opacity: 1, animated: true)
            if self?.speakingActivity == nil {
                self?.membersCountView.change(opacity: 1, animated: true)
            }
            self?.speakingActivity?.change(opacity: 1, animated: true)
        }, for: .Hover)

        updateLocalizationAndTheme(theme: theme)

        update(data, animated: false)
        
        activeCallButton.autohighlight = false
        
        activeCallButton.set(handler: { [weak self] _ in
            self?.data.data?.groupCall?.call.toggleIsMuted()
        }, for: .Click)
        

        
    }
    
    
    func update(_ data: ChatActiveGroupCallInfo, animated: Bool) {
        
        let context = self.chatInteraction.context
        
        let activeCall = data.data?.groupCall != nil
        joinButton.change(opacity: activeCall ? 0 : 1, animated: animated)
        activeCallButton.change(opacity: activeCall ? 1 : 0, animated: animated)
        joinButton.userInteractionEnabled = !activeCall
        activeCallButton.userInteractionEnabled = activeCall
        
        let duration: Double = 0.4
        let timingFunction: CAMediaTimingFunctionName = .spring
        
        var topPeers: [Avatar] = []
        if let participants = data.data?.topParticipants {
            var index:Int = 0
            for participant in participants {
                topPeers.append(Avatar(peer: participant.peer, index: index))
                index += 1
            }
        }
        let (removed, inserted, updated) = mergeListsStableWithUpdates(leftList: self.topPeers, rightList: topPeers)
        
        let avatarSize = NSMakeSize(30, 30)
        
        for removed in removed.reversed() {
            let control = avatars.remove(at: removed)
            let peer = self.topPeers[removed]
            let haveNext = topPeers.contains(where: { $0.stableId == peer.stableId })
            control.updateLayout(size: avatarSize, isClipped: false, animated: animated)
            if animated && !haveNext {
                control.layer?.animateAlpha(from: 1, to: 0, duration: duration, timingFunction: timingFunction, removeOnCompletion: false, completion: { [weak control] _ in
                    control?.removeFromSuperview()
                })
                control.layer?.animateScaleSpring(from: 1.0, to: 0.2, duration: duration)
            } else {
                control.removeFromSuperview()
            }
        }
        for inserted in inserted {
            let control = AvatarContentView(context: context, peer: inserted.1.peer, message: nil, synchronousLoad: false, size: avatarSize)
            control.updateLayout(size: avatarSize, isClipped: inserted.0 != 0, animated: animated)
            control.userInteractionEnabled = false
            control.setFrameSize(avatarSize)
            control.setFrameOrigin(NSMakePoint(CGFloat(inserted.0) * (avatarSize.width - 3), 0))
            avatars.insert(control, at: inserted.0)
            avatarsContainer.subviews.insert(control, at: inserted.0)
            if animated {
                if let index = inserted.2 {
                    control.layer?.animatePosition(from: NSMakePoint(CGFloat(index) * 19, 0), to: control.frame.origin, timingFunction: timingFunction)
                } else {
                    control.layer?.animateAlpha(from: 0, to: 1, duration: duration, timingFunction: timingFunction)
                    control.layer?.animateScaleSpring(from: 0.2, to: 1.0, duration: duration)
                }
            }
        }
        for updated in updated {
            let control = avatars[updated.0]
            control.updateLayout(size: avatarSize, isClipped: updated.0 != 0, animated: animated)
            let updatedPoint = NSMakePoint(CGFloat(updated.0) * (avatarSize.width - 3), 0)
            if animated {
                control.layer?.animatePosition(from: control.frame.origin - updatedPoint, to: .zero, duration: duration, timingFunction: timingFunction, additive: true)
            }
            control.setFrameOrigin(updatedPoint)
        }
        var index: CGFloat = 10
        for control in avatarsContainer.subviews.compactMap({ $0 as? AvatarContentView }) {
            control.layer?.zPosition = index
            index -= 1
        }
        
        if let data = data.data, data.numberOfActiveSpeakers > 0 {
            
            membersCountView.change(opacity: 0, animated: animated)
            
            let textData = DynamicCounterTextView.make(for: L10n.chatGroupCallSpeakersCountable(data.numberOfActiveSpeakers), count: data.numberOfActiveSpeakers, font: .normal(.short), textColor: theme.colors.accent, width: frame.width - 100)
            
            if self.speakingActivity == nil {
                self.speakingActivity = DynamicCounterTextView(frame: .init(origin: .zero, size: textData.size))
                addSubview(self.speakingActivity!, positioned: .below, relativeTo: button)
                self.speakingActivity!.centerX(y: frame.midY)
                if animated {
                    self.speakingActivity?.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
                    self.speakingActivity?.layer?.animateScaleSpring(from: 0.1, to: 1, duration: 0.2)
                }
            }
            
            guard let speakingActivity = self.speakingActivity else {
                return
            }
                        
            speakingActivity.update(textData.values, animated: animated)
            
            var newPoint = focus(textData.size).origin
            newPoint.y = frame.midY
            let newSize = textData.size
            
            let rect: NSRect = .init(origin: newPoint, size: newSize)
            
            if animated {
                speakingActivity.layer?.animatePosition(from: rect.origin - speakingActivity.frame.origin, to: .zero, duration: 0.2, additive: true)
                let size = newSize - speakingActivity.frame.size
                speakingActivity.layer?.animateBounds(from: .init(origin: .zero, size: size), to: .zero, duration: 0.2, additive: true)
            }
            speakingActivity.frame = rect
            
        } else {
            
            membersCountView.change(opacity: 1, animated: animated)
            
            if let current = self.speakingActivity {
                if animated {
                    current.layer?.animateAlpha(from: 1, to: 0, duration: 0.2, removeOnCompletion: false, completion: { [weak current] _ in
                        current?.removeFromSuperview()
                    })
                    current.layer?.animateScaleSpring(from: 1, to: 0.1, duration: 0.2)
                } else {
                    current.removeFromSuperview()
                }
                self.speakingActivity = nil
            }
        }
        
        
        self.topPeers = topPeers
        
        self.data = data
        
        
        if let groupCall = self.data.data?.groupCall {
            stateDisposable.set((groupCall.call.state |> deliverOnMainQueue).start(next: { [weak self] state in
                if let muteState = state.muteState {
                    self?.activeCallButton.set(background: theme.colors.accentIcon, for: .Normal)
                    self?.activeCallButton.set(background: theme.colors.accentIcon.withAlphaComponent(0.6), for: .Highlight)
                    self?.activeCallButton.userInteractionEnabled = muteState.canUnmute
                    if muteState.canUnmute {
                        self?.activeCallButton.set(image: theme.icons.chat_voicechat_can_unmute, for: .Normal)
                    } else {
                        self?.activeCallButton.set(image: theme.icons.chat_voicechat_cant_unmute, for: .Normal)
                    }
                } else {
                    self?.activeCallButton.userInteractionEnabled = true
                    self?.activeCallButton.set(background: theme.colors.greenUI, for: .Normal)
                    self?.activeCallButton.set(background: theme.colors.greenUI.withAlphaComponent(0.6), for: .Highlight)
                    self?.activeCallButton.set(image: theme.icons.chat_voicechat_unmuted, for: .Normal)
                }
            }))
            
        } else {
            stateDisposable.set(nil)
        }
        
        updateLocalizationAndTheme(theme: theme)
    }
    
    override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
        backgroundColor = theme.colors.background
        border = [.Bottom]
        borderColor = theme.colors.border
        joinButton.set(text: L10n.chatGroupCallJoin, for: .Normal)
        joinButton.sizeToFit(NSMakeSize(14, 8), .zero, thatFit: false)
        joinButton.layer?.cornerRadius = joinButton.frame.height / 2
        joinButton.set(color: theme.colors.underSelectedColor, for: .Normal)
        joinButton.set(background: theme.colors.accent, for: .Normal)
        joinButton.set(background: theme.colors.accent.withAlphaComponent(0.8), for: .Highlight)
        
        let headerLayout = TextViewLayout(.initialize(string: L10n.chatGroupCallTitle, color: theme.colors.text, font: .medium(.text)))
        headerLayout.measure(width: frame.width - 100)
        headerView.update(headerLayout)
        
        let membersCountLayout = TextViewLayout(.initialize(string: L10n.chatGroupCallMembersCountable(self.data.data?.participantCount ?? 0), color: theme.colors.grayText, font: .normal(.short)))
        membersCountLayout.measure(width: frame.width - 100)
        membersCountView.update(membersCountLayout)
        
      
        
        needsLayout = true
    }
    
    override func layout() {
        super.layout()
        joinButton.centerY(x: frame.width - joinButton.frame.width - 23)
        self.avatarsContainer.centerY(x: 23)
        
        headerView.layout?.measure(width: frame.width - 100)
        membersCountView.layout?.measure(width: frame.width - 100)
        membersCountView.update(membersCountView.layout)
        headerView.update(headerView.layout)
        
        if let speakingActivity = self.speakingActivity {
            speakingActivity.centerX(y: frame.midY)
        }
        
        headerView.centerX(y: frame.midY - headerView.frame.height)
        membersCountView.centerX(y: frame.midY)
        
        activeCallButton.centerY(x: frame.width - activeCallButton.frame.width - 16)
        
        button.frame = NSMakeRect(headerView.frame.minX, 0, max(headerView.frame.width, membersCountView.frame.width), frame.height)
    }
    
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    required init(frame frameRect: NSRect) {
        fatalError("init(frame:) has not been implemented")
    }
}
