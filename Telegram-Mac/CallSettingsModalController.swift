//
//  CallSettingsModalController.swift
//  Telegram
//
//  Created by Mikhail Filimonov on 21/02/2019.
//  Copyright © 2019 Telegram. All rights reserved.
//

import Cocoa
import TelegramCore
import SyncCore
import SwiftSignalKit
import Postbox
import TGUIKit


func CallSettingsModalController(_ sharedContext: SharedAccountContext) -> InputDataModalController {
    
    let modalController = InputDataModalController(CallSettingsController(sharedContext: sharedContext))

    return modalController
    
}
