// The README's navigation snippets, compiled. @Observable needs macOS 14, above the
// package's floor, so the types using it say so outside the README's text.

import BkitNavigation
import Foundation
import SwiftUI

struct LibraryNavigation: Equatable, Sendable {
    var stack = StackState<LibraryRoute>()
    var sheet = SheetState<LibrarySheet>()
}

struct NoteNavigation: Equatable, Sendable {
    var sheet = SheetState<LibrarySheet>()
    var inspector = PresentationFlag()
}

func readState(of navigation: inout LibraryNavigation, inboxID: UUID) {
    let isComposing = navigation.sheet.isPresenting(.newNote)
    navigation.stack.pop(to: .folder(id: inboxID))
    _ = isComposing
}

// In the Library feature module.
public enum LibraryRoute: Hashable, Sendable {
    case folder(id: UUID)
    case note(id: UUID)
    case editor(noteID: UUID)
}

public enum LibrarySheet: Identifiable, Equatable, Sendable {
    case newNote
    case share(noteID: UUID)

    public var id: String {
        switch self {
        case .newNote: "newNote"
        case .share(let noteID): "share-\(noteID)"
        }
    }
}

public protocol SettingsNavigating {
    func openSettings()
}

@available(macOS 14, iOS 17, *)
@Observable
@MainActor
final class LibraryRouter {
    var flow = FlowState<LibraryRoute, LibrarySheet, NoPresentation>()

    func showNote(id: UUID) {
        flow.stack.push(.note(id: id))
    }

    func composeNote() {
        flow.sheet.present(.newNote)
    }
}

@available(macOS 14, iOS 17, *)
struct LibraryView: View {
    @State private var router = LibraryRouter()

    var body: some View {
        NavigationStack(path: $router.flow.stack.path) {
            NoteListView(onSelect: router.showNote(id:))
                .navigationDestination(for: LibraryRoute.self) { route in
                    switch route {
                    case .folder(let id):
                        FolderView(id: id)
                    case .note(let id):
                        NoteView(id: id)
                    case .editor(let noteID):
                        NoteEditor(noteID: noteID)
                    }
                }
        }
        .sheet(item: $router.flow.sheet.item) { sheet in
            switch sheet {
            case .newNote:
                NewNoteView()
            case .share(let noteID):
                ShareNoteView(noteID: noteID)
            }
        }
    }
}

// The patterns, on one model and two screens.

struct StoredNote {
    let id: UUID
}

@available(macOS 14, iOS 17, *)
@Observable
@MainActor
final class ComposerModel {}

@available(macOS 14, iOS 17, *)
@Observable
@MainActor
final class LibraryModel {
    var nav = LibraryNavigation()
    var createdNoteID: UUID?
    var composer: ComposerModel?

    func share(_ note: StoredNote) {
        nav.sheet.present(.share(noteID: note.id))  // replaces whatever was up
    }

    // In the model:
    func sheetDidDismiss() {
        guard let id = createdNoteID else { return }
        createdNoteID = nil
        nav.stack.push(.note(id: id))
    }

    // In the model:
    func compose() {
        composer = ComposerModel()  // stored on the owner
        nav.sheet.present(.newNote)
    }
}

@available(macOS 14, iOS 17, *)
struct LibraryScreen: View {
    @State private var model = LibraryModel()

    var body: some View {
        NoteListView(onSelect: { _ in })
            // In the view:
            .sheet(item: $model.nav.sheet.item, onDismiss: model.sheetDidDismiss) { sheet in
                LibrarySheetView(sheet: sheet)
            }
    }

    private func look(for id: UUID) {
        let isEditing = model.nav.stack.path.contains(.editor(noteID: id))
        let top = model.nav.stack.path.last
        _ = (isEditing, top)
    }
}

@available(macOS 14, iOS 17, *)
struct ComposingScreen: View {
    @State private var model = LibraryModel()

    var body: some View {
        NoteListView(onSelect: { _ in })
            .sheet(item: $model.nav.sheet.item) { sheet in
                switch sheet {
                // In the view:
                case .newNote:
                    if let composer = model.composer { ComposerView(model: composer) }
                case .share(let noteID):
                    ShareNoteView(noteID: noteID)
                }
            }
    }
}

// Stand-ins for the app's own screens.

struct NoteListView: View {
    let onSelect: (UUID) -> Void
    var body: some View { EmptyView() }
}

struct FolderView: View {
    let id: UUID
    var body: some View { EmptyView() }
}

struct NoteView: View {
    let id: UUID
    var body: some View { EmptyView() }
}

struct NoteEditor: View {
    let noteID: UUID
    var body: some View { EmptyView() }
}

struct NewNoteView: View {
    var body: some View { EmptyView() }
}

struct ShareNoteView: View {
    let noteID: UUID
    var body: some View { EmptyView() }
}

struct LibrarySheetView: View {
    let sheet: LibrarySheet
    var body: some View { EmptyView() }
}

@available(macOS 14, iOS 17, *)
struct ComposerView: View {
    let model: ComposerModel
    var body: some View { EmptyView() }
}
