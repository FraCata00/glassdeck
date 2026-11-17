import Foundation

/// The animal that now and then walks across the Touch Bar, chosen in settings.
///
/// The raw value is the persisted identifier in user defaults, so it must stay
/// stable. `off` lives here rather than as an optional so the setting is one
/// picker with one stored value.
public enum TouchBarPet: String, Sendable, CaseIterable, Identifiable {
    case off
    case octopus
    case frog
    /// A red toy poodle, drawn after the owner's dog — which is why it goes by
    /// her name rather than by its breed.
    case coco

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .off: L.t("pet.off", "None")
        case .octopus: L.t("pet.octopus", "Octopus")
        case .frog: L.t("pet.frog", "Frog")
        case .coco: L.t("pet.coco", "Coco")
        }
    }
}

extension TouchBarMode {
    /// The bars a pet crosses. The mini bar and the Control Strip meter have no
    /// room for it; a metric's detail gets a pet of its own that stays put.
    public var hostsPetCrossing: Bool {
        switch self {
        case .expanded, .fullscreen: true
        case .collapsed, .mini, .detail: false
        }
    }
}
