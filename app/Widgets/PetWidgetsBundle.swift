// Расширение PetWidgets: виджет, Live Activity и два контрола Пункта управления.

import SwiftUI
import WidgetKit

@main
struct PetWidgetsBundle: WidgetBundle {
    var body: some Widget {
        PetWidget()
        PetLiveActivity()
        PetIslandControl()
        PetFeedControl()
    }
}
