import SwiftUI
import SquishPolicy
import SquishWorkshop

/// The Squishy Workshop: six stations along a belt. Pick a mould, pour the goo, bake or freeze it,
/// give it a face, dress it up and bring it to life. Made squishies live in the Squish Room and as
/// a Buddy, never on boards, in capsules or in the Collection.
struct WorkshopView: View {
    @EnvironmentObject var model: AppModel

    enum Station: Int, CaseIterable {
        case mould, goo, bake, face, dress, life

        var icon: String {
            switch self {
            case .mould: return "square.on.circle"
            case .goo: return "drop.fill"
            case .bake: return "flame.fill"
            case .face: return "face.smiling"
            case .dress: return "tshirt.fill"
            case .life: return "sparkles"
            }
        }
    }

    /// Why a part cannot be used yet.
    enum Lock: Equatable {
        case open
        /// Opens with the next world finished.
        case world
        /// Won by finishing this many worlds, never bought.
        case win(Int)
        /// One wearable for coins (13 and over, without Workshop Pro).
        case coins(Int)
        /// Comes with Remove Ads.
        case pro
    }

    struct Tile: Identifiable {
        let id: String
        let lock: Lock
        let selected: Bool
    }

    /// What the line above the belt says after a tap on a locked part.
    enum Note: Equatable {
        case world
        case win(Int)
        case coins(category: String, part: String, price: Int)
        case pro
    }

    /// The squishy on the belt, kept while the player looks at the shop or goes Home and comes back.
    struct Draft {
        var id: String
        var design: WorkshopDesign
        var name: String
        var station: Station
        var baked: Bool
    }
    private static var kept: Draft?

    @State private var id = UUID().uuidString
    @State private var design = WorkshopView.blank
    @State private var name = ""
    @State private var station = Station.mould
    @State private var baked = false
    @State private var baking = false
    @State private var pouring = false
    @State private var colour: UInt32 = 0xFF9EB5
    /// Pro: the next pour mixes into the goo already there, like paint.
    @State private var mixing = false
    @State private var mixFrom: UInt32?
    @State private var mixShare = 0.0
    @State private var glug = 0.0
    @State private var wave = 0.0
    /// Pro: the next mould tapped goes on top of the first, as a head.
    @State private var onTop = false
    @State private var faceKind = "eyes"
    @State private var tray = "ears"
    /// The part or sticker being moved.
    @State private var picked: String?
    @State private var dragID: String?
    @State private var dragFrom = CGPoint.zero
    @State private var squash: CGFloat = 0
    @State private var tilt = 0.0
    @State private var spin = 0.0
    @State private var hop: CGFloat = 0
    @State private var note: Note?
    @State private var shelf = false
    @State private var card: MadeSquishy?
    @State private var problem = false
    @State private var typing = false
    @State private var drawingShape = false
    @State private var mixer = false
    @State private var drawingFace = false

    private let clock = Timer.publish(every: 1.0 / 30, on: .main, in: .common).autoconnect()
    private static let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 5)

    /// A new squishy starts as an empty mould.
    static var blank: WorkshopDesign {
        var d = WorkshopDesign()
        d.layers = []
        return d
    }

    private var access: WorkshopAccess { model.workshopAccess }
    private var gentle: Bool { model.isGentleMode }
    private var palette: [UInt32] { WorkshopArt.catalog?.colours ?? MakerParts.palette }
    private var poured: Double { min(1, design.layers.reduce(0) { $0 + $1.amount }) }
    private var isFull: Bool { poured >= 0.999 }
    private var isSaved: Bool { model.progress.made.contains { $0.id == id } }
    private var shelfFull: Bool { !isSaved && model.progress.made.count >= model.shelfPlaces }
    private var maxLayers: Int { access.pro ? WorkshopDesign.maxLayers : WorkshopGate.freeLayers }

    var body: some View {
        GeometryReader { geo in
            let side = max(120, min(geo.size.width - 32, geo.size.height * 0.36, 340))
            VStack(spacing: 8) {
                bar
                stage(side: side)
                if station == .dress { pickedControls }
                ScrollView {
                    trayView.padding(.horizontal, 16).padding(.bottom, 8)
                }
                .frame(maxHeight: .infinity)
                if let note { noteView(note) }
                belt
            }
        }
        .background(Theme.marshmallow.ignoresSafeArea())
        .overlay { if let made = card { birthdayCard(made) } }
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: card)
        .sheet(isPresented: $shelf) { shelfView }
        .sheet(isPresented: $mixer) {
            MixerView { mixed in
                // The new squishy goes straight to the last station for its voice and name.
                mixer = false
                id = UUID().uuidString
                design = mixed
                baked = true
                note = nil
                picked = nil
                typing = false
                spinName(quiet: true)
                station = .life
            } cancel: {
                mixer = false
            }
            .environmentObject(model)
        }
        .fullScreenCover(isPresented: $drawingShape) {
            DrawPad(kind: .shape) { strokes, brush in
                // Whatever was drawn is the mould now; nothing drawn leaves the mould as it was.
                if !strokes.isEmpty {
                    design.drawnOutline = DrawnShape.outline(strokes: strokes, brush: brush)
                    design.mould = "draw-it"
                    design.mould2 = nil
                    unbake()
                    model.sounds.play("pop")
                }
                drawingShape = false
            } cancel: {
                drawingShape = false
            }
        }
        .fullScreenCover(isPresented: $drawingFace) {
            DrawPad(kind: .face, design: design) { strokes, _ in
                // The pad shows the whole picture; the face is kept in the body's own box.
                let share = WorkshopDesign.bodyShare
                let onBody = strokes.map { $0.map { WorkshopPoint(x: ($0.x - (1 - share) / 2) / share, y: ($0.y - (1 - share) / 2) / share) } }
                let face = DrawnShape.face(strokes: onBody)
                design.drawnFace = face.isEmpty ? nil : face
                drawingFace = false
            } cancel: {
                drawingFace = false
            }
        }
        .onReceive(clock) { _ in pourTick(1.0 / 30) }
        .onAppear(perform: restore)
        .onDisappear(perform: keep)
    }

    // MARK: - Top bar

    private var bar: some View {
        HStack(spacing: 8) {
            IconButton(system: "chevron.left") { model.screen = model.homeScreen }
            Spacer()
            Text("Squishy Workshop").font(Theme.title(22)).foregroundStyle(Theme.plum)
                .lineLimit(1).minimumScaleFactor(0.6)
            Spacer()
            Button(action: surprise) {
                Image(systemName: "dice.fill").font(.system(size: 18, weight: .bold)).foregroundStyle(Theme.plum)
                    .frame(width: 44, height: 44).background(Circle().fill(Theme.butter))
            }
            .buttonStyle(PressSquish())
            .accessibilityLabel(Text("Surprise me"))
            .accessibilityIdentifier("ws-surprise")
            Button { shelf = true } label: {
                Image(systemName: "books.vertical.fill").font(.system(size: 18, weight: .bold)).foregroundStyle(Theme.plum)
                    .frame(width: 44, height: 44).background(Circle().fill(.white))
                    .overlay(alignment: .topTrailing) {
                        if !model.progress.made.isEmpty {
                            Text(verbatim: "\(model.progress.made.count)").font(Theme.body(11)).foregroundStyle(.white)
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(Capsule().fill(Theme.bubblegum)).offset(x: 4, y: -4)
                        }
                    }
            }
            .buttonStyle(PressSquish())
            .accessibilityLabel(Text("My squishies"))
            .accessibilityIdentifier("ws-shelf")
        }
        .padding(.horizontal, 12).padding(.top, 6)
    }

    // MARK: - The squishy on the belt

    private func stage(side: CGFloat) -> some View {
        ZStack {
            WorkshopSquishyView(design: design, fill: baked ? 1 : poured, showsMould: !baked, showsFace: baked,
                                wave: pouring ? wave : nil)
                .frame(width: side, height: side)
                .scaleEffect(x: 1 + squash * 0.25, y: 1 - squash * 0.35, anchor: .bottom)
                .rotationEffect(.degrees(tilt + spin))
                .offset(y: hop)
                .rotationEffect(.degrees(baking ? 2.5 : 0))
                .animation(baking ? .easeInOut(duration: 0.09).repeatForever(autoreverses: true) : .easeOut(duration: 0.15), value: baking)
            if station == .goo && !baked && !isFull && !pouring {
                // Show, do not tell: a finger pressing on the mould.
                Image(systemName: "hand.point.up.left.fill").font(.system(size: side * 0.16))
                    .foregroundStyle(Theme.plum.opacity(0.75)).offset(x: side * 0.12, y: side * 0.16)
                    .allowsHitTesting(false)
            }
            if pouring {
                Image(systemName: "drop.fill").font(.system(size: side * 0.12))
                    .foregroundStyle(WorkshopArt.colour(colour)).offset(y: -side * 0.44)
                    .allowsHitTesting(false)
            }
            if station == .dress { handles(side: side) }
        }
        .frame(width: side, height: side)
        .contentShape(Rectangle())
        .gesture(stageGesture)
        .accessibilityElement(children: station == .dress ? .contain : .ignore)
        .accessibilityLabel(Text("Squishy Workshop"))
        .accessibilityIdentifier("ws-stage")
    }

    /// At the goo station a held finger pours; anywhere else a tap squeezes a finished squishy.
    private var stageGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                if station == .goo { if !pouring { startPour() } }
            }
            .onEnded { _ in
                if station == .goo {
                    pouring = false
                    mixFrom = nil
                } else if baked && station != .dress {
                    squeeze()
                }
            }
    }

    /// A handle over each part and sticker, so it can be picked and dragged about.
    private func handles(side: CGFloat) -> some View {
        ZStack {
            ForEach(design.parts + design.stickers) { p in
                let size = max(44, side * 0.3 * CGFloat(p.scale))
                Circle()
                    .stroke(Theme.bubblegum, style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
                    .opacity(picked == p.id ? 1 : 0)
                    .contentShape(Circle())
                    .frame(width: size, height: size)
                    .position(x: side * CGFloat(p.x), y: side * CGFloat(p.y))
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                if dragID != p.id {
                                    dragID = p.id
                                    dragFrom = CGPoint(x: p.x, y: p.y)
                                    picked = p.id
                                }
                                move(p.id, x: Double(dragFrom.x) + Double(value.translation.width / side),
                                     y: Double(dragFrom.y) + Double(value.translation.height / side))
                            }
                            .onEnded { _ in dragID = nil }
                    )
                    .accessibilityLabel(Text("Parts"))
                    .accessibilityIdentifier("ws-placed-\(p.category)")
            }
        }
        .frame(width: side, height: side)
    }

    private func change(_ placedID: String, _ edit: (inout Placed) -> Void) {
        if let i = design.parts.firstIndex(where: { $0.id == placedID }) {
            edit(&design.parts[i])
            design.parts[i] = WorkshopDesign.clamped(design.parts[i])
        } else if let i = design.stickers.firstIndex(where: { $0.id == placedID }) {
            edit(&design.stickers[i])
            design.stickers[i] = WorkshopDesign.clamped(design.stickers[i])
        }
    }

    private func move(_ placedID: String, x: Double, y: Double) {
        change(placedID) { $0.x = x; $0.y = y }
    }

    private var pickedPart: Placed? { (design.parts + design.stickers).first { $0.id == picked } }

    /// Size, turn and take off, for the part that is picked.
    @ViewBuilder private var pickedControls: some View {
        if let p = pickedPart {
            HStack(spacing: 10) {
                Image(systemName: "arrow.up.left.and.arrow.down.right").foregroundStyle(Theme.plum.opacity(0.6))
                Slider(value: Binding(get: { p.scale }, set: { v in change(p.id) { $0.scale = v } }),
                       in: Placed.minScale...Placed.maxScale)
                    .accessibilityLabel(Text("Size"))
                Image(systemName: "arrow.triangle.2.circlepath").foregroundStyle(Theme.plum.opacity(0.6))
                Slider(value: Binding(get: { p.angle }, set: { v in change(p.id) { $0.angle = v } }),
                       in: -Double.pi...Double.pi)
                    .accessibilityLabel(Text("Turn"))
                Button {
                    design.parts.removeAll { $0.id == p.id }
                    design.stickers.removeAll { $0.id == p.id }
                    picked = nil
                    model.sounds.play("sticker_peel")
                } label: {
                    Image(systemName: "trash.fill").foregroundStyle(Theme.plum)
                        .frame(width: 40, height: 40).background(Circle().fill(.white))
                }
                .buttonStyle(PressSquish())
                .accessibilityLabel(Text("Delete"))
                .accessibilityIdentifier("ws-part-remove")
            }
            .tint(Theme.bubblegum)
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Trays

    @ViewBuilder private var trayView: some View {
        switch station {
        case .mould: mouldTray
        case .goo: gooTray
        case .bake: bakeTray
        case .face: faceTray
        case .dress: dressTray
        case .life: lifeTray
        }
    }

    private func lock(_ isOpen: Bool, _ id: String, free: [String]) -> Lock {
        isOpen ? .open : (free.contains(id) ? .world : .pro)
    }

    /// Open parts first, then the ones to win or buy, then at most one row of the ones that come
    /// with Remove Ads. In gentle mode those are one closed drawer that does nothing when tapped.
    private func grid<Art: View>(_ group: LocalizedStringKey, key: String, _ tiles: [Tile],
                                 @ViewBuilder art: @escaping (String) -> Art, tap: @escaping (String) -> Void) -> some View {
        let open = tiles.filter { $0.lock == .open }
        let reachable = tiles.filter { $0.lock != .open && $0.lock != .pro }
        let pro = tiles.filter { $0.lock == .pro }
        let shownPro = gentle ? [] : Array(pro.prefix(4))
        let shown = open + reachable + shownPro
        return LazyVGrid(columns: WorkshopView.columns, spacing: 8) {
            ForEach(Array(shown.enumerated()), id: \.element.id) { index, t in
                Button {
                    press(t, tap: tap)
                } label: {
                    art(t.id)
                        .frame(maxWidth: .infinity).aspectRatio(1, contentMode: .fit).padding(5)
                        .opacity(t.lock == .open ? 1 : 0.35)
                        .overlay(alignment: .bottom) { badge(t.lock) }
                        .background(RoundedRectangle(cornerRadius: 14).fill(t.selected ? Theme.butter : Color.white))
                }
                .buttonStyle(.plain)
                // Pictures only: VoiceOver reads the group and the number.
                .accessibilityLabel(Text(group))
                .accessibilityValue(Text(verbatim: "\(index + 1)"))
                .accessibilityIdentifier("ws-\(key)-\(t.id)")
            }
            if pro.count > shownPro.count {
                moreTile(count: pro.count - shownPro.count)
            }
        }
    }

    private func press(_ t: Tile, tap: (String) -> Void) {
        switch t.lock {
        case .open:
            note = nil
            tap(t.id)
            model.haptics.lift()
        case .world: note = .world
        case .win(let worlds): note = .win(worlds)
        case .coins(let price): note = .coins(category: tray, part: t.id, price: price)
        case .pro: note = .pro
        }
    }

    /// The rest of a tray. A child sees a plain closed drawer; from 13 it says how many more there are.
    @ViewBuilder private func moreTile(count: Int) -> some View {
        let face = VStack(spacing: 2) {
            Image(systemName: "ellipsis").font(.system(size: 18, weight: .bold))
            if !gentle { Text(verbatim: "+\(count)").font(Theme.body(12)) }
        }
        .foregroundStyle(Theme.plum.opacity(0.45))
        .frame(maxWidth: .infinity).aspectRatio(1, contentMode: .fit)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.6)))
        if gentle {
            face.accessibilityLabel(Text("More"))
        } else {
            Button { note = .pro } label: { face }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("More"))
                .accessibilityIdentifier("ws-more")
        }
    }

    @ViewBuilder private func badge(_ lock: Lock) -> some View {
        switch lock {
        case .open: EmptyView()
        case .world, .pro:
            Image(systemName: "lock.fill").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.plum.opacity(0.7)).padding(4)
        case .win:
            Image(systemName: "trophy.fill").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.plum.opacity(0.7)).padding(4)
        case .coins(let price):
            HStack(spacing: 2) {
                CoinIcon().scaleEffect(0.6).frame(width: 12, height: 12)
                Text(verbatim: "\(price)").font(Theme.body(10)).foregroundStyle(Theme.plum)
            }
            .padding(.horizontal, 4).padding(.vertical, 1)
            .background(Capsule().fill(Theme.butter)).padding(2)
        }
    }

    private func title(_ text: LocalizedStringKey) -> some View {
        Text(text).font(Theme.title(16)).foregroundStyle(Theme.plum).frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A tool that comes with Remove Ads: it works for its owner, is a locked chip from 13, and is not there for a child.
    @ViewBuilder private func proTool(_ text: LocalizedStringKey, icon: String, isOn: Bool, key: String, action: @escaping () -> Void) -> some View {
        if access.pro || !gentle {
            Button {
                if access.pro { action() } else { note = .pro }
            } label: {
                Label(text, systemImage: access.pro ? icon : "lock.fill").font(Theme.body(14))
                    .foregroundStyle(isOn ? Color.white : Theme.plum)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Capsule().fill(isOn ? Theme.grape : Color.white))
            }
            .buttonStyle(PressSquish())
            .accessibilityIdentifier(key)
        }
    }

    private func proSwitch(_ text: LocalizedStringKey, icon: String, isOn: Binding<Bool>, key: String) -> some View {
        proTool(text, icon: icon, isOn: isOn.wrappedValue, key: key) { isOn.wrappedValue.toggle() }
    }

    // Station 1: the mould.

    private var mouldTray: some View {
        let moulds = (WorkshopArt.catalog?.moulds ?? WorkshopGate.freeMoulds).filter { $0 != "draw-it" }
        let tiles = moulds.map { m in
            Tile(id: m, lock: lock(WorkshopGate.mouldOpen(m, access), m, free: WorkshopGate.freeMoulds),
                 selected: onTop ? design.mould2 == m : design.mould == m)
        }
        return VStack(spacing: 10) {
            HStack {
                title("Shape")
                if model.config.workshopDraw {
                    proTool("Draw", icon: "scribble.variable", isOn: design.mould == "draw-it", key: "ws-draw-shape") { drawingShape = true }
                }
                proSwitch("Head on top", icon: "square.stack.fill", isOn: $onTop, key: "ws-on-top")
            }
            grid("Shape", key: "mould", tiles) { m in
                if let image = WorkshopArt.mould(m) {
                    Image(uiImage: image).renderingMode(.template).resizable().scaledToFit().foregroundStyle(Theme.plum.opacity(0.8))
                }
            } tap: { m in
                if onTop {
                    design.mould2 = design.mould2 == m ? nil : m
                } else {
                    design.mould = m
                    design.drawnOutline = nil
                }
                unbake()
                model.sounds.play("pop")
            }
        }
    }

    // Station 2: the goo.

    private var gooTray: some View {
        VStack(spacing: 10) {
            if baked {
                redoButton
            } else {
                HStack(spacing: 8) {
                    gooChip(.jelly, "Jelly", "drop.fill")
                    gooChip(.foam, "Foam", "cloud.fill")
                    gooChip(.gel, "Gel", "circle.hexagongrid.fill")
                    gooChip(.mochi, "Mochi", "circle.fill")
                }
                HStack {
                    title("Colour")
                    proSwitch("Mix", icon: "paintpalette.fill", isOn: $mixing, key: "ws-mix")
                    if !design.layers.isEmpty {
                        Button {
                            design.layers = []
                            model.sounds.play("splat")
                        } label: {
                            Image(systemName: "arrow.uturn.backward").foregroundStyle(Theme.plum)
                                .frame(width: 36, height: 36).background(Circle().fill(.white))
                        }
                        .buttonStyle(PressSquish())
                        .accessibilityLabel(Text("Squash and redo"))
                        .accessibilityIdentifier("ws-empty")
                    }
                }
                colourGrid
                if !design.layers.isEmpty { patternGrid }
                if isFull { effectGrid }
            }
        }
    }

    private func gooChip(_ goo: Goo, _ text: LocalizedStringKey, _ icon: String) -> some View {
        Button {
            design.goo = goo
            model.haptics.lift()
        } label: {
            VStack(spacing: 2) {
                Image(systemName: icon).font(.system(size: 16, weight: .bold))
                Text(text).font(Theme.body(12)).lineLimit(1).minimumScaleFactor(0.6)
            }
            .foregroundStyle(design.goo == goo ? Color.white : Theme.plum)
            .frame(maxWidth: .infinity).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 14).fill(design.goo == goo ? Theme.grape : Color.white))
        }
        .buttonStyle(PressSquish())
        .accessibilityIdentifier("ws-goo-\(goo.rawValue)")
    }

    private var colourGrid: some View {
        let tiles = palette.map { c in
            Tile(id: String(c), lock: WorkshopGate.colourOpen(c, palette: palette, access)
                    ? .open : (palette.firstIndex(of: c).map { $0 < WorkshopGate.freeColourCount } == true ? .world : .pro),
                 selected: colour == c)
        }
        return grid("Colour", key: "colour", tiles) { c in
            Circle().fill(WorkshopArt.colour(UInt32(c) ?? 0)).overlay(Circle().stroke(Theme.plum.opacity(0.2), lineWidth: 2))
        } tap: { c in
            colour = UInt32(c) ?? colour
        }
    }

    private var patternGrid: some View {
        let top = design.layers.last
        let tiles = (WorkshopArt.catalog?.patterns ?? WorkshopGate.freePatterns).map { p in
            Tile(id: p, lock: WorkshopGate.patternOpen(p, access) ? .open : .pro, selected: top?.pattern == p)
        }
        return VStack(spacing: 8) {
            title("Patterns")
            grid("Patterns", key: "pattern", tiles) { p in
                GooFill(design: WorkshopDesign(layers: [GooLayer(colour: top?.colour ?? colour, pattern: p, seed: 3),
                                                        GooLayer(colour: colour, amount: 0)]))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            } tap: { p in
                if let i = design.layers.indices.last { design.layers[i].pattern = p }
            }
        }
    }

    @ViewBuilder private var effectGrid: some View {
        // Sparkles are all Workshop Pro: a child without it sees no tray at all.
        if access.pro || !gentle {
            let tiles = (WorkshopArt.catalog?.effects ?? []).map { e in
                Tile(id: e, lock: access.pro ? .open : .pro, selected: design.fx.contains(e))
            }
            VStack(spacing: 8) {
                title("Sparkles")
                grid("Sparkles", key: "fx", tiles) { e in
                    GooFill(design: WorkshopDesign(layers: [GooLayer(colour: design.mainColour)], fx: [e]))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                } tap: { e in
                    if design.fx.contains(e) { design.fx.removeAll { $0 == e } } else if design.fx.count < 3 { design.fx.append(e) }
                    model.sounds.play("shaker_rattle")
                }
            }
        }
    }

    // Station 3: the oven or the freezer.

    private var bakeTray: some View {
        VStack(spacing: 14) {
            if baked {
                redoButton
            } else {
                Button(action: bake) {
                    VStack(spacing: 6) {
                        Image(systemName: design.goo.baked ? "flame.fill" : "snowflake").font(.system(size: 44, weight: .bold))
                        Text(design.goo.baked ? "Bake" : "Freeze").font(Theme.title(20))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 22)
                    .background(RoundedRectangle(cornerRadius: 26).fill(design.goo.baked ? Theme.bubblegum : Theme.sky))
                    .overlay(RoundedRectangle(cornerRadius: 26).stroke(Theme.plum.opacity(0.15), lineWidth: 2))
                }
                .buttonStyle(PressSquish())
                .disabled(baking || !isFull)
                .opacity(isFull ? 1 : 0.5)
                .accessibilityIdentifier("ws-bake")
            }
        }
        .padding(.top, 10)
    }

    private var redoButton: some View {
        Button(action: squashAndRedo) {
            Label("Squash and redo", systemImage: "arrow.uturn.backward").frame(maxWidth: .infinity)
        }
        .buttonStyle(SquishButtonStyle(fill: .white, text: Theme.plum))
        .accessibilityIdentifier("ws-redo")
    }

    // Station 4: the face.

    private var faceTray: some View {
        let kinds: [(String, String)] = [("eyes", "eye.fill"), ("mouths", "mouth.fill"), ("noses", "nose.fill"),
                                         ("brows", "eyebrow"), ("cheeks", "heart.fill")]
        return VStack(spacing: 10) {
            HStack(spacing: 8) {
                ForEach(kinds, id: \.0) { kind, icon in
                    Button { faceKind = kind } label: {
                        Image(systemName: icon).font(.system(size: 18, weight: .bold))
                            .foregroundStyle(faceKind == kind ? Color.white : Theme.plum)
                            .frame(maxWidth: .infinity).padding(.vertical, 10)
                            .background(RoundedRectangle(cornerRadius: 14).fill(faceKind == kind ? Theme.grape : Color.white))
                    }
                    .buttonStyle(PressSquish())
                    .accessibilityLabel(Text(faceTitle(kind)))
                    .accessibilityIdentifier("ws-face-\(kind)")
                }
            }
            if model.config.workshopDraw {
                HStack {
                    Spacer()
                    proTool("Draw", icon: "scribble.variable", isOn: design.drawnFace != nil, key: "ws-draw-face") { drawingFace = true }
                }
            }
            grid(faceTitle(faceKind), key: faceKind, faceTiles(faceKind)) { piece in
                if let image = WorkshopArt.face(faceKind, piece) {
                    Image(uiImage: image).resizable().scaledToFit()
                } else {
                    Image(systemName: "nosign").font(.system(size: 20, weight: .bold)).foregroundStyle(Theme.plum.opacity(0.4))
                }
            } tap: { piece in
                switch faceKind {
                case "eyes": design.face.eyes = piece
                case "mouths": design.face.mouth = piece
                case "noses": design.face.nose = piece
                case "brows": design.face.brows = piece
                default: design.face.cheeks = piece
                }
                design.drawnFace = nil
                model.sounds.play("pop")
            }
        }
    }

    private func faceTitle(_ kind: String) -> LocalizedStringKey {
        switch kind {
        case "eyes": return "Eyes"
        case "mouths": return "Mouth"
        case "noses": return "Noses"
        case "brows": return "Brows"
        default: return "Cheeks"
        }
    }

    private func faceTiles(_ kind: String) -> [Tile] {
        let c = WorkshopArt.catalog
        let f = design.face
        switch kind {
        case "eyes":
            return (c?.eyes ?? WorkshopGate.freeEyes).map {
                Tile(id: $0, lock: lock(WorkshopGate.eyesOpen($0, access), $0, free: WorkshopGate.freeEyes), selected: f.eyes == $0)
            }
        case "mouths":
            return (c?.mouths ?? WorkshopGate.freeMouths).map {
                Tile(id: $0, lock: lock(WorkshopGate.mouthOpen($0, access), $0, free: WorkshopGate.freeMouths), selected: f.mouth == $0)
            }
        case "noses":
            return (c?.noses ?? WorkshopGate.freeNoses).map {
                Tile(id: $0, lock: lock(WorkshopGate.noseOpen($0, access), $0, free: WorkshopGate.freeNoses), selected: f.nose == $0)
            }
        case "brows":
            return (c?.brows ?? WorkshopGate.freeBrows).map {
                Tile(id: $0, lock: lock(WorkshopGate.browsOpen($0, access), $0, free: WorkshopGate.freeBrows), selected: f.brows == $0)
            }
        default:
            return (c?.cheeks ?? WorkshopGate.freeCheeks).map {
                Tile(id: $0, lock: lock(WorkshopGate.cheeksOpen($0, access), $0, free: WorkshopGate.freeCheeks), selected: f.cheeks == $0)
            }
        }
    }

    // Station 5: dress up.

    private func partLock(_ category: String, _ part: String) -> Lock {
        if WorkshopGate.partOpen(category: category, part: part, access) { return .open }
        if let worlds = WorkshopGate.winOnly[category + "/" + part] { return .win(worlds) }
        if WorkshopGate.freeParts[category]?.contains(part) == true { return .world }
        // Coin prices are for players of 13 and over; a child is never shown one.
        if !gentle, let price = WorkshopGate.coinPrice(category: category, part: part, access) { return .coins(price) }
        return .pro
    }

    private var dressTray: some View {
        let trays = WorkshopArt.catalog?.parts ?? []
        let items = WorkshopArt.catalog?.items(in: tray) ?? []
        let worn = Set((design.parts + design.stickers).filter { $0.category == tray }.map(\.part))
        let tiles = items.map { Tile(id: $0, lock: partLock(tray, $0), selected: worn.contains($0)) }
        return VStack(spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(trays.enumerated()), id: \.element.category) { index, entry in
                        Button {
                            tray = entry.category
                            note = nil
                        } label: {
                            trayIcon(entry.category, entry.items.first ?? "")
                                .frame(width: 44, height: 44).padding(4)
                                .background(RoundedRectangle(cornerRadius: 14).fill(tray == entry.category ? Theme.grape.opacity(0.35) : Color.white))
                        }
                        .buttonStyle(PressSquish())
                        .accessibilityLabel(Text("Parts"))
                        .accessibilityValue(Text(verbatim: "\(index + 1)"))
                        .accessibilityIdentifier("ws-tray-\(entry.category)")
                    }
                }
            }
            grid("Parts", key: "part", tiles) { part in
                trayIcon(tray, part)
            } tap: { part in
                wear(tray, part)
            }
        }
    }

    @ViewBuilder private func trayIcon(_ category: String, _ part: String) -> some View {
        if let image = WorkshopArt.part(category, part) {
            Image(uiImage: image).resizable().scaledToFit()
        } else {
            Image(systemName: "questionmark").foregroundStyle(Theme.plum.opacity(0.3))
        }
    }

    /// Puts a part on, or takes it off when it is already on. One from each tray; stickers up to eight.
    private func wear(_ category: String, _ part: String) {
        if category == WorkshopCatalog.stickerCategory {
            guard design.stickers.count < WorkshopDesign.maxStickers else { return }
            let n = Double(design.stickers.count)
            let placed = Placed(category: category, part: part, x: 0.38 + 0.08 * n.truncatingRemainder(dividingBy: 4),
                                y: 0.56 + 0.07 * (n / 4).rounded(.down), scale: 0.6)
            design.stickers.append(placed)
            picked = placed.id
        } else if let on = design.parts.first(where: { $0.category == category && $0.part == part }) {
            design.parts.removeAll { $0.id == on.id }
            picked = nil
        } else {
            let home = WorkshopArt.home(of: category)
            let placed = Placed(category: category, part: part, x: home.x, y: home.y)
            design.parts.removeAll { $0.category == category }
            design.parts.append(placed)
            picked = placed.id
        }
        model.sounds.play("sticker_peel")
    }

    // Station 6: bring it to life.

    private var lifeTray: some View {
        VStack(spacing: 12) {
            title("Voices")
            LazyVGrid(columns: WorkshopView.columns, spacing: 8) {
                ForEach(Array((WorkshopArt.catalog?.voices ?? WorkshopCatalog.voiceIDs).enumerated()), id: \.element) { index, voice in
                    lifeButton("speaker.wave.2.fill", number: index + 1, on: design.voice == voice, locked: false) {
                        design.voice = voice
                        model.sounds.voice(voice, pitch: design.pitch)
                        squeeze(quiet: true)
                    }
                    .accessibilityLabel(Text("Voices"))
                    .accessibilityIdentifier("ws-voice-\(voice)")
                }
            }
            title("Dances")
            LazyVGrid(columns: WorkshopView.columns, spacing: 8) {
                ForEach(Array((WorkshopArt.catalog?.dances ?? WorkshopGate.freeDances).enumerated()), id: \.element) { index, dance in
                    let open = WorkshopGate.danceOpen(dance, access)
                    // A child without Workshop Pro only sees the dances that are open.
                    if open || !gentle {
                        lifeButton("figure.dance", number: index + 1, on: design.dance == dance, locked: !open) {
                            if open {
                                design.dance = dance
                                show(dance: dance)
                            } else {
                                note = .pro
                            }
                        }
                        .accessibilityLabel(Text("Dances"))
                        .accessibilityIdentifier("ws-dance-\(dance)")
                    }
                }
            }
            nameRow
            doneRow
        }
    }

    private func lifeButton(_ icon: String, number: Int, on: Bool, locked: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: locked ? "lock.fill" : icon).font(.system(size: 16, weight: .bold))
                Text(verbatim: "\(number)").font(Theme.body(12))
            }
            .foregroundStyle(on ? Color.white : Theme.plum.opacity(locked ? 0.4 : 1))
            .frame(maxWidth: .infinity).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 14).fill(on ? Theme.grape : Color.white))
        }
        .buttonStyle(PressSquish())
        .accessibilityValue(Text(verbatim: "\(number)"))
    }

    private var nameRow: some View {
        VStack(spacing: 8) {
            title("Name")
            HStack(spacing: 10) {
                if typing {
                    TextField("Name", text: $name)
                        .font(Theme.body(18)).textFieldStyle(.roundedBorder).autocorrectionDisabled()
                        .onChange(of: name) { _, new in
                            if new.count > NameFilter.maxLength { name = String(new.prefix(NameFilter.maxLength)) }
                            problem = false
                        }
                        .accessibilityIdentifier("ws-name-field")
                } else {
                    Text(verbatim: name.isEmpty ? "…" : name).font(Theme.title(24)).foregroundStyle(Theme.plum)
                        .lineLimit(1).minimumScaleFactor(0.5)
                        .frame(maxWidth: .infinity).padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 14).fill(.white))
                        .accessibilityIdentifier("ws-name")
                }
                Button(action: spinName) {
                    Label("Spin", systemImage: "dice.fill")
                }
                .buttonStyle(SquishButtonStyle(fill: Theme.butter, text: Theme.plum))
                .accessibilityIdentifier("ws-spin")
            }
            // Typing a name is for players of 13 and over; a child has the wheel.
            if !gentle && !typing {
                Button("Type a name") { typing = true }
                    .font(Theme.body(13)).foregroundStyle(Theme.plum.opacity(0.7))
                    .accessibilityIdentifier("ws-type-name")
            }
            if problem && !shelfFull {
                Text("Try another name").font(Theme.body(14)).foregroundStyle(Theme.bubblegum)
            }
        }
    }

    @ViewBuilder private var doneRow: some View {
        if shelfFull {
            if model.canBuyMakerSlot {
                let enough = model.progress.wallet.balance >= MakerSlots.price
                Button { model.buyMakerSlot() } label: {
                    HStack {
                        Label("One more place on your shelf", systemImage: "plus.circle.fill")
                        Spacer()
                        Label { Text(verbatim: "\(MakerSlots.price)") } icon: { CoinIcon() }
                    }
                }
                .buttonStyle(SquishButtonStyle(fill: Theme.butter, text: Theme.plum))
                .disabled(!enough)
                .opacity(enough ? 1 : 0.6)
                .accessibilityIdentifier("maker-slot")
                if !enough {
                    Text("You have \(model.progress.wallet.balance) coins. Win levels to earn more.")
                        .font(Theme.body(13)).foregroundStyle(Theme.plum.opacity(0.6))
                }
            } else {
                Text("Your shelf is full").font(Theme.body(14)).foregroundStyle(Theme.bubblegum)
            }
        } else {
            Button(action: done) {
                Label("Done", systemImage: "checkmark").frame(maxWidth: .infinity)
            }
            .buttonStyle(SquishButtonStyle())
            .accessibilityIdentifier("ws-done")
        }
    }

    // MARK: - The line above the belt

    private func noteView(_ note: Note) -> some View {
        HStack(spacing: 10) {
            switch note {
            case .world:
                Text("More parts open with each world you finish.")
            case .win(let worlds):
                Text("Finish \(worlds) worlds to win this.")
            case .coins(let category, let part, let price):
                trayIcon(category, part).frame(width: 36, height: 36)
                if model.progress.wallet.balance >= price {
                    Spacer()
                    Button {
                        if model.buyWorkshopPart(category: category, part: part) {
                            self.note = nil
                            wear(category, part)
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text("Buy")
                            CoinIcon()
                            Text(verbatim: "\(price)")
                        }
                    }
                    .buttonStyle(SquishButtonStyle(fill: Theme.butter, text: Theme.plum))
                    .accessibilityIdentifier("ws-buy-part")
                } else {
                    Text("You have \(model.progress.wallet.balance) coins. Win levels to earn more.")
                }
            case .pro:
                // Only ever reached by a player of 13 or over. The price is in the shop, not here.
                Text("Comes with Remove Ads")
                Spacer()
                Button("See") { model.screen = .shop }
                    .buttonStyle(SquishButtonStyle(fill: Theme.grape))
                    .accessibilityIdentifier("ws-see-shop")
            }
        }
        .font(Theme.body(14)).foregroundStyle(Theme.plum)
        .padding(.horizontal, 14).padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 18).fill(.white))
        .padding(.horizontal, 12)
        .accessibilityIdentifier("ws-note")
    }

    // MARK: - The belt

    private func canOpen(_ s: Station) -> Bool {
        switch s {
        case .mould, .goo: return true
        case .bake: return isFull || baked
        case .face, .dress, .life: return baked
        }
    }

    private func go(_ s: Station) {
        guard canOpen(s), !baking else { return }
        station = s
        note = nil
        picked = nil
        pouring = false
        if s == .life && name.isEmpty { spinName(quiet: true) }
    }

    private var belt: some View {
        HStack(spacing: 6) {
            Button { if let s = Station(rawValue: station.rawValue - 1) { go(s) } } label: {
                Image(systemName: "arrow.left").font(.system(size: 20, weight: .heavy)).foregroundStyle(Theme.plum)
                    .frame(width: 48, height: 48).background(Circle().fill(.white))
            }
            .buttonStyle(PressSquish())
            .opacity(station == .mould ? 0.3 : 1)
            .disabled(station == .mould)
            .accessibilityLabel(Text("Back"))
            .accessibilityIdentifier("ws-back")
            ForEach(Station.allCases, id: \.rawValue) { s in
                Button { go(s) } label: {
                    Image(systemName: s == .bake && !design.goo.baked ? "snowflake" : s.icon)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(s == station ? Color.white : Theme.plum.opacity(canOpen(s) ? 0.8 : 0.3))
                        .frame(maxWidth: .infinity).frame(height: 40)
                        .background(RoundedRectangle(cornerRadius: 14).fill(s == station ? Theme.bubblegum : Color.white.opacity(0.7)))
                }
                .buttonStyle(.plain)
                .disabled(!canOpen(s))
                .accessibilityValue(Text(verbatim: "\(s.rawValue + 1)"))
                .accessibilityIdentifier("ws-station-\(s.rawValue + 1)")
            }
            let next = Station(rawValue: station.rawValue + 1)
            let ready = next.map(canOpen) ?? false
            Button { if let next { go(next) } } label: {
                Image(systemName: "arrow.right").font(.system(size: 20, weight: .heavy)).foregroundStyle(.white)
                    .frame(width: 48, height: 48).background(Circle().fill(Theme.bubblegum))
            }
            .buttonStyle(PressSquish())
            .opacity(ready ? 1 : 0.3)
            .disabled(!ready)
            .accessibilityLabel(Text("Next"))
            .accessibilityIdentifier("ws-next")
        }
        .padding(.horizontal, 10).padding(.top, 6).padding(.bottom, 4)
        .background(Color.white.opacity(0.5).ignoresSafeArea(edges: .bottom))
    }

    // MARK: - Pouring

    private func startPour() {
        guard !baked, !baking else { return }
        let total = design.layers.reduce(0) { $0 + $1.amount }
        mixFrom = nil
        mixShare = 0
        if let top = design.layers.last, let i = design.layers.indices.last {
            if top.colour == colour {
                // More of the same goo.
            } else if access.pro && mixing {
                mixFrom = top.colour
            } else if design.layers.count < maxLayers {
                // A full mould makes room: the goo already in it sinks a little and the new colour goes on top.
                if total >= 0.999 { for k in design.layers.indices { design.layers[k].amount *= 0.7 } }
                design.layers.append(GooLayer(colour: colour, seed: Int.random(in: 0..<1000), amount: 0))
            } else {
                design.layers[i].colour = colour
            }
        } else {
            design.layers = [GooLayer(colour: colour, seed: Int.random(in: 0..<1000), amount: 0)]
        }
        glug = 1
        pouring = true
    }

    private func pourTick(_ dt: Double) {
        guard pouring, station == .goo, let i = design.layers.indices.last else {
            if pouring { pouring = false }
            return
        }
        wave += dt
        if let from = mixFrom {
            mixShare = min(0.5, mixShare + dt * 0.35)
            design.layers[i].colour = GooMix.mix(from, colour, share: mixShare)
        }
        let total = design.layers.reduce(0) { $0 + $1.amount }
        if total < 1 {
            design.layers[i].amount += min(1 - total, dt * 0.5)
            glug += dt
            if glug > 0.35 {
                glug = 0
                model.sounds.play("goo_glug")
                model.haptics.lift()
            }
            if total + dt * 0.5 >= 1 {
                model.sounds.play("pop")
                model.haptics.land()
            }
        } else if mixFrom == nil || mixShare >= 0.5 {
            pouring = false
        }
    }

    // MARK: - Baking, squeezing, dancing

    private func unbake() {
        baked = false
    }

    private func bake() {
        guard isFull, !baking, !baked else { return }
        baking = true
        model.sounds.play(design.goo.baked ? "boss_rumble" : "freezer_hiss")
        let wait: UInt64 = AppModel.isUITesting ? 300_000_000 : 3_000_000_000
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: wait)
            baking = false
            baked = true
            model.sounds.play("oven_ding")
            model.sounds.play("capsule_pop")
            model.haptics.complete()
            // It pops out with a wobble.
            squash = 0.9
            withAnimation(.spring(response: 0.4, dampingFraction: 0.35)) { squash = 0 }
        }
    }

    private func squeeze(quiet: Bool = false) {
        guard baked else { return }
        if !quiet {
            model.sounds.play("squeeze_in")
            model.haptics.land()
        }
        withAnimation(.easeOut(duration: 0.08)) { squash = 0.8 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.35)) { squash = 0 }
        }
    }

    private func squashAndRedo() {
        model.sounds.play("splat")
        model.haptics.land()
        withAnimation(.easeIn(duration: 0.15)) { squash = 2.2 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            design.layers = []
            baked = false
            squash = 0
            station = .goo
            picked = nil
        }
    }

    private func show(dance: String) {
        model.sounds.play("hop")
        switch dance {
        case "spinner":
            withAnimation(.easeInOut(duration: 0.8)) { spin += 360 }
        case "wiggler", "swayer":
            withAnimation(.easeInOut(duration: 0.14).repeatCount(6, autoreverses: true)) { tilt = 10 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { withAnimation(.easeOut(duration: 0.15)) { tilt = 0 } }
        default:
            withAnimation(.easeOut(duration: 0.16).repeatCount(4, autoreverses: true)) { hop = -26 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { withAnimation(.easeOut(duration: 0.15)) { hop = 0 } }
        }
    }

    // MARK: - Surprise, names, saving

    private func surprise() {
        guard !baking, let catalog = WorkshopArt.catalog else { return }
        var rng = SystemRandomNumberGenerator()
        design = WorkshopSurprise.make(catalog: catalog, access: access, using: &rng)
        id = UUID().uuidString
        baked = false
        note = nil
        picked = nil
        typing = false
        spinName(quiet: true)
        model.sounds.play("shaker_rattle")
        // It lands at the oven, ready for its pop-out.
        station = .bake
    }

    private func spinName() { spinName(quiet: false) }

    private func spinName(quiet: Bool) {
        guard let wheel = WorkshopArt.nameWheel else { return }
        var rng = SystemRandomNumberGenerator()
        name = wheel.spin(using: &rng) { NameFilter.clean($0) != nil }
        typing = false
        problem = false
        if !quiet {
            model.sounds.play("wheel_tick")
            model.haptics.lift()
        }
    }

    private func done() {
        if model.saveMade(MadeSquishy(id: id, name: name, design: design)),
           let saved = model.progress.made.first(where: { $0.id == id }) {
            problem = false
            name = saved.name
            if let kept = saved.design { design = kept }
            WorkshopView.kept = nil
            model.sounds.play("card_print")
            model.haptics.win()
            card = saved
        } else {
            problem = true
        }
    }

    private func startNew() {
        id = UUID().uuidString
        design = WorkshopView.blank
        name = ""
        baked = false
        station = .mould
        note = nil
        picked = nil
        typing = false
        problem = false
        WorkshopView.kept = nil
    }

    private func edit(_ made: MadeSquishy) {
        id = made.id
        let full = made.workshopDesign
        // A look made with Workshop Pro can only be changed with the parts that are open now.
        design = WorkshopGate.allowed(full, palette: palette, access) ? full : WorkshopGate.freeCopy(of: full, palette: palette, access)
        name = made.name
        baked = true
        station = .face
        note = nil
        picked = nil
        problem = false
        typing = false
    }

    private func keep() {
        // An empty mould is not worth keeping; a saved squishy is already on the shelf.
        guard card == nil, !design.layers.isEmpty || isSaved else { WorkshopView.kept = nil; return }
        WorkshopView.kept = Draft(id: id, design: design, name: name, station: station, baked: baked)
    }

    private func restore() {
        guard let draft = WorkshopView.kept else { return }
        id = draft.id
        design = draft.design
        name = draft.name
        baked = draft.baked
        station = canOpen(draft.station) ? draft.station : .mould
    }

    // MARK: - Birthday card

    private func birthdayCard(_ made: MadeSquishy) -> some View {
        let d = made.workshopDesign
        let stats = WorkshopStats(d)
        let born = Date(timeIntervalSince1970: d.born).formatted(date: .long, time: .omitted)
        return ZStack {
            Color.black.opacity(0.3).ignoresSafeArea()
            VStack(spacing: 10) {
                WorkshopSquishyView(design: d).frame(width: 160, height: 160)
                Text("Meet \(made.name)!").font(Theme.title(26)).foregroundStyle(Theme.plum)
                    .lineLimit(1).minimumScaleFactor(0.5)
                    .accessibilityIdentifier("ws-card-name")
                Text(verbatim: born).font(Theme.body(13)).foregroundStyle(Theme.plum.opacity(0.6))
                VStack(spacing: 5) {
                    statRow("Squish", stats.squish, Theme.bubblegum)
                    statRow("Bounce", stats.bounce, Theme.sky)
                    statRow("Stretch", stats.stretch, Theme.mint)
                    statRow("Charm", stats.charm, Theme.grape)
                }
                .padding(.horizontal, 6)
                HStack(spacing: 8) {
                    if model.isExtraUnlocked(.buddy) {
                        if model.progress.buddy.squishy == made.ref {
                            Label("\(made.name) is your Buddy", systemImage: "heart.fill")
                                .font(Theme.body(14)).foregroundStyle(Theme.bubblegum)
                        } else {
                            Button {
                                if model.setBuddy(ref: made.ref, name: made.name) { model.haptics.complete() }
                            } label: {
                                Label("Make my Buddy", systemImage: "heart.fill").font(Theme.body(14)).lineLimit(1).minimumScaleFactor(0.7)
                            }
                            .buttonStyle(SquishButtonStyle(fill: Theme.grape))
                            .accessibilityIdentifier("maker-buddy")
                        }
                    }
                    if model.isExtraUnlocked(.squishRoom) {
                        Button {
                            card = nil
                            startNew()
                            model.squeeze(made.ref)
                        } label: {
                            Label("Squeeze", systemImage: "hand.tap.fill").font(Theme.body(14))
                        }
                        .buttonStyle(SquishButtonStyle(fill: Theme.bubblegum))
                        .accessibilityIdentifier("maker-squeeze")
                    }
                }
                Button("Make another") {
                    card = nil
                    startNew()
                }
                .font(Theme.body(15)).foregroundStyle(Theme.plum.opacity(0.7))
                .accessibilityIdentifier("ws-another")
            }
            .padding(22)
            .background(RoundedRectangle(cornerRadius: 30).fill(Theme.marshmallow))
            .overlay(RoundedRectangle(cornerRadius: 30).stroke(Theme.plum.opacity(0.12), lineWidth: 2))
            .padding(26)
            .frame(maxWidth: 520)
            .transition(.scale(scale: 0.7).combined(with: .opacity))
        }
    }

    private func statRow(_ text: LocalizedStringKey, _ value: Int, _ tint: Color) -> some View {
        HStack(spacing: 8) {
            Text(text).font(Theme.body(13)).foregroundStyle(Theme.plum).frame(width: 84, alignment: .leading)
                .lineLimit(1).minimumScaleFactor(0.6)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white)
                    Capsule().fill(tint).frame(width: g.size.width * CGFloat(min(10, max(0, value))) / 10)
                }
            }
            .frame(height: 10)
            Text(verbatim: "\(value)").font(Theme.body(13)).foregroundStyle(Theme.plum).frame(width: 22)
        }
    }

    // MARK: - The shelf

    private var shelfView: some View {
        VStack(spacing: 12) {
            HStack {
                Text("My squishies").font(Theme.title(22)).foregroundStyle(Theme.plum)
                Spacer()
                Text(verbatim: "\(model.progress.made.count) / \(model.shelfPlaces)").font(Theme.body(15)).foregroundStyle(Theme.plum.opacity(0.6))
                // The Mixer comes with Remove Ads: a child without it does not see it at all.
                if model.config.workshopMixer && (access.pro || !gentle) {
                    Button {
                        shelf = false
                        if access.pro {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { mixer = true }
                        } else {
                            note = .pro
                        }
                    } label: {
                        Label("Mixer", systemImage: access.pro ? "tornado" : "lock.fill").font(Theme.body(14)).foregroundStyle(Theme.plum)
                            .padding(.horizontal, 12).padding(.vertical, 8).background(Capsule().fill(.white))
                    }
                    .buttonStyle(PressSquish())
                    .accessibilityIdentifier("ws-mixer")
                }
                IconButton(system: "xmark") { shelf = false }
            }
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(model.progress.made) { made in
                        HStack(spacing: 10) {
                            MadeSquishyView(made: made).frame(width: 64, height: 64)
                            Text(verbatim: made.name).font(Theme.body(17)).foregroundStyle(Theme.plum).lineLimit(1)
                            Spacer()
                            shelfButton("pencil", "Edit", "ws-edit") {
                                edit(made)
                                shelf = false
                            }
                            if model.isExtraUnlocked(.squishRoom) {
                                shelfButton("hand.tap.fill", "Squeeze", "ws-shelf-squeeze") {
                                    shelf = false
                                    model.squeeze(made.ref)
                                }
                            }
                            shelfButton("trash.fill", "Delete", "ws-delete") {
                                if made.id == id { startNew() }
                                model.deleteMade(made.id)
                            }
                        }
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 18).fill(.white))
                    }
                    if model.progress.made.isEmpty {
                        Text("Make your own squishy. It can be your Buddy and lives in your Squish Room.")
                            .font(Theme.body(14)).foregroundStyle(Theme.plum.opacity(0.7)).multilineTextAlignment(.center).padding(20)
                    }
                }
            }
            Button {
                startNew()
                shelf = false
            } label: {
                Label("New", systemImage: "plus").frame(maxWidth: .infinity)
            }
            .buttonStyle(SquishButtonStyle())
            .accessibilityIdentifier("ws-new")
        }
        .padding(16)
        .background(Theme.marshmallow.ignoresSafeArea())
    }

    private func shelfButton(_ icon: String, _ label: LocalizedStringKey, _ key: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.plum)
                .frame(width: 40, height: 40).background(Circle().fill(Theme.marshmallow))
        }
        .buttonStyle(PressSquish())
        .accessibilityLabel(Text(label))
        .accessibilityIdentifier(key)
    }
}
