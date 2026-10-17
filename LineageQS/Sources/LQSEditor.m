#import "LQSStrings.h"
#import "LQSEditor.h"
#import "LQSModel.h"
#import "LQSTheme.h"
#import "LQSViews.h"
#import "LQSVectorIcon.h"

// Geometry (docs/qs-edit-mode.md 2.x / 4.3).
static const CGFloat kSide = 16;        // QuickSettingsShade HorizontalPadding
static const CGFloat kGridPad = 10;     // CurrentTilesGridPadding
static const CGFloat kGap = 6;          // TileArrangementPadding
static const CGFloat kTileH = 72;       // TileHeight
static const CGFloat kColumnGap = 10;   // qs_label_container_margin
static const CGFloat kGroupPad = 16;    // available group padding
static const NSInteger kColumns = 4;
static const NSUInteger kUndoMax = 10;  // SNAPSHOTS_MAX_SIZE

// Placement spring: StiffnessMediumLow (400) / DampingRatioLowBouncy (0.75).
static UIViewPropertyAnimator *PlacementSpring(void) {
    UISpringTimingParameters *p = [[UISpringTimingParameters alloc] initWithMass:1 stiffness:400 damping:0.75 * 2 * sqrt(400) initialVelocity:CGVectorMake(0, 0)];
    return [[UIViewPropertyAnimator alloc] initWithDuration:0 timingParameters:p];
}
static UIViewPropertyAnimator *DefaultSpring(void) {
    UISpringTimingParameters *p = [[UISpringTimingParameters alloc] initWithMass:1 stiffness:1500 damping:2 * sqrt(1500) initialVelocity:CGVectorMake(0, 0)];
    return [[UIViewPropertyAnimator alloc] initWithDuration:0 timingParameters:p];
}

#pragma mark - Android-style dialog (QSResetDialogDelegate / SystemUIDialog)

@interface LQSDialog : UIView
+ (void)showIn:(UIView *)host title:(NSString *)title message:(NSString *)message ok:(NSString *)ok cancel:(NSString *)cancel onOK:(void (^)(void))onOK;
@end

@implementation LQSDialog {
    UIView *_card;
    void (^_onOK)(void);
}
+ (void)showIn:(UIView *)host title:(NSString *)title message:(NSString *)message ok:(NSString *)ok cancel:(NSString *)cancel onOK:(void (^)(void))onOK {
    LQSDialog *d = [[LQSDialog alloc] initWithFrame:host.bounds];
    d->_onOK = [onOK copy];
    d.backgroundColor = [UIColor colorWithWhite:0 alpha:0.32]; // M3 dialog scrim (assumption)
    UIView *card = [UIView new];
    card.backgroundColor = LQSColor(@"surface_container_high");
    card.layer.cornerRadius = 28; // M3 dialog shape (assumption: SystemUIDialog 28dp)
    d->_card = card;
    [d addSubview:card];
    CGFloat w = MIN(host.bounds.size.width - 48, 312), pad = 24;
    UILabel *t = [UILabel new];
    t.text = title; t.numberOfLines = 0; t.font = [LQSTheme sansWithSize:24 weight:400]; t.textColor = [LQSTheme onSurface];
    CGSize ts = [t sizeThatFits:CGSizeMake(w - 2 * pad, 200)];
    t.frame = CGRectMake(pad, pad, w - 2 * pad, ts.height);
    UILabel *m = [UILabel new];
    m.text = message; m.numberOfLines = 0; m.font = [LQSTheme sansWithSize:14 weight:400]; m.textColor = [LQSTheme onSurfaceVariant];
    CGSize ms = [m sizeThatFits:CGSizeMake(w - 2 * pad, 400)];
    m.frame = CGRectMake(pad, CGRectGetMaxY(t.frame) + 16, w - 2 * pad, ms.height);
    [card addSubview:t];
    [card addSubview:m];
    // PlatformButton (filled primary) + PlatformTextButton.
    UIButton *okB = [d button:ok filled:YES action:@selector(okTapped)];
    UIButton *cB = [d button:cancel filled:NO action:@selector(close)];
    CGSize os = [okB sizeThatFits:CGSizeMake(200, 40)], cs = [cB sizeThatFits:CGSizeMake(200, 40)];
    CGFloat by = CGRectGetMaxY(m.frame) + 24;
    okB.frame = CGRectMake(w - pad - os.width, by, os.width, 40);
    cB.frame = CGRectMake(CGRectGetMinX(okB.frame) - 8 - cs.width, by, cs.width, 40);
    [card addSubview:okB];
    [card addSubview:cB];
    card.frame = CGRectMake((host.bounds.size.width - w) / 2, (host.bounds.size.height - (by + 40 + pad)) / 2, w, by + 40 + pad);
    [d addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:d action:@selector(scrimTapped:)]];
    [host addSubview:d];
    d.alpha = 0;
    card.transform = CGAffineTransformMakeScale(0.9, 0.9);
    [UIView animateWithDuration:0.2 animations:^{ d.alpha = 1; card.transform = CGAffineTransformIdentity; }];
}
- (UIButton *)button:(NSString *)title filled:(BOOL)filled action:(SEL)sel {
    UIButtonConfiguration *c = [UIButtonConfiguration plainButtonConfiguration];
    c.contentInsets = NSDirectionalEdgeInsetsMake(0, 24, 0, 24);
    c.attributedTitle = [[NSAttributedString alloc] initWithString:title attributes:@{NSFontAttributeName: [LQSTheme sansWithSize:14 weight:500],
        NSForegroundColorAttributeName: filled ? [LQSTheme onPrimary] : [LQSTheme primary]}];
    UIButton *b = [UIButton buttonWithConfiguration:c primaryAction:nil];
    b.backgroundColor = filled ? [LQSTheme primary] : UIColor.clearColor;
    b.layer.cornerRadius = 20;
    [b addTarget:self action:sel forControlEvents:UIControlEventTouchUpInside];
    return b;
}
- (void)scrimTapped:(UITapGestureRecognizer *)g { if (!CGRectContainsPoint(_card.frame, [g locationInView:self])) [self close]; }
- (void)okTapped { void (^b)(void) = _onOK; [self close]; if (b) b(); }
- (void)close { [UIView animateWithDuration:0.15 animations:^{ self.alpha = 0; } completion:^(BOOL f) { [self removeFromSuperview]; }]; }
@end

#pragma mark - Editor

@interface LQSEditor () <UIGestureRecognizerDelegate>
@end

@implementation LQSEditor {
    UIScrollView *_scroll;
    UIButton *_back;
    LQSIconButton *_undo;
    UIButton *_remove;
    UILabel *_title, *_subtitle;
    UIView *_grid;            // current tiles container (border + fill)
    CAShapeLayer *_gridBorder;
    NSMutableArray<LQSTileEntry *> *_entries;
    NSMutableDictionary<NSString *, LQSTileView *> *_tiles; // spec -> view
    NSString *_selected;
    UIView *_selBorder, *_handle;
    CAShapeLayer *_selShape;
    NSMutableArray<NSArray<LQSTileEntry *> *> *_undoStack;
    // available
    NSMutableArray<UIView *> *_groups;
    NSMutableDictionary<NSString *, UIView *> *_cells;
    UIButton *_reset;
    // drag
    NSString *_dragSpec;
    LQSTileView *_dragView;
    UIView *_placeholder;
    CGPoint _dragOffset;
    BOOL _dragOutside;
    NSArray<LQSTileEntry *> *_dragStartEntries;
    CGFloat _handleStartX;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _scroll = [UIScrollView new];
        _scroll.alwaysBounceVertical = YES;
        _scroll.showsVerticalScrollIndicator = NO;
        [self addSubview:_scroll];

        _back = [UIButton buttonWithType:UIButtonTypeCustom];
        [_back setImage:[LQSVectorIcon imageNamed:@"ic_arrow_back" side:24] forState:UIControlStateNormal];
        _back.tintColor = [LQSTheme onSurface];
        _back.accessibilityLabel = LQSL(@"action_bar_up_description");
        [_back addTarget:self action:@selector(backTapped) forControlEvents:UIControlEventTouchUpInside];
        [_scroll addSubview:_back];
        _undo = [[LQSIconButton alloc] initWithIcon:@"ic_menu_undo_material" side:24];
        _undo.accessibilityLabel = @"Undo";
        [_undo addTarget:self action:@selector(undoTapped) forControlEvents:UIControlEventTouchUpInside];
        _undo.alpha = 0;
        [_scroll addSubview:_undo];
        _remove = [UIButton buttonWithType:UIButtonTypeCustom];
        _remove.titleLabel.font = [LQSTheme sansWithSize:14 weight:500]; // labelLarge
        [_remove setTitle:LQSL(@"qs_customize_remove") forState:UIControlStateNormal];
        [_remove addTarget:self action:@selector(removeTapped) forControlEvents:UIControlEventTouchUpInside];
        [_scroll addSubview:_remove];
        _title = [UILabel new];
        _title.text = LQSL(@"qs_edit_tiles");
        _title.font = [LQSTheme sansWithSize:28 weight:500]; // headlineMediumEmphasized 28/36
        _title.textColor = [LQSTheme onSurface];
        _title.numberOfLines = 2;
        [_scroll addSubview:_title];
        _subtitle = [UILabel new];
        _subtitle.text = LQSL(@"select_to_rearrange_tiles");
        _subtitle.font = [LQSTheme sansWithSize:14 weight:400]; // bodyMedium 14/20
        _subtitle.textColor = [LQSTheme onSurface];
        _subtitle.numberOfLines = 0;
        [_scroll addSubview:_subtitle];

        _grid = [UIView new];
        _grid.layer.cornerRadius = 28;
        _gridBorder = [CAShapeLayer layer];
        _gridBorder.fillColor = UIColor.clearColor.CGColor;
        _gridBorder.lineWidth = 2;
        [_grid.layer addSublayer:_gridBorder];
        [_scroll addSubview:_grid];
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(gridTapped:)];
        [_grid addGestureRecognizer:tap];
        UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(gridLongPress:)];
        lp.minimumPressDuration = 0.4;
        [_grid addGestureRecognizer:lp];

        _placeholder = [UIView new];
        _placeholder.userInteractionEnabled = NO;
        _placeholder.hidden = YES;
        [_grid addSubview:_placeholder];
        _selBorder = [UIView new];
        _selBorder.userInteractionEnabled = NO;
        _selShape = [CAShapeLayer layer];
        _selShape.fillColor = UIColor.clearColor.CGColor;
        _selShape.lineWidth = 2; // SelectedBorderWidth
        [_selBorder.layer addSublayer:_selShape];
        _handle = [UIView new];
        _handle.layer.cornerRadius = 4;
        _handle.accessibilityLabel = @"toggle tile size";
        UIPanGestureRecognizer *hp = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
        hp.delegate = self;
        [_handle addGestureRecognizer:hp];
        [_handle addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTapped)]];

        UIButtonConfiguration *rc = [UIButtonConfiguration plainButtonConfiguration];
        rc.contentInsets = NSDirectionalEdgeInsetsMake(0, 24, 0, 24);
        _reset = [UIButton buttonWithConfiguration:rc primaryAction:nil];
        [_reset addTarget:self action:@selector(resetTapped) forControlEvents:UIControlEventTouchUpInside];
        [_scroll addSubview:_reset];

        _undoStack = [NSMutableArray array];
        _tiles = [NSMutableDictionary dictionary];
        _groups = [NSMutableArray array];
        _cells = [NSMutableDictionary dictionary];
        [self applyColors];
        [self reload];
    }
    return self;
}

- (void)applyColors {
    _gridBorder.strokeColor = [LQSTheme primary].CGColor;
    _grid.backgroundColor = [[LQSTheme primary] colorWithAlphaComponent:0.15];
    _undo.fill = [LQSTheme surfaceEffect1];
    _undo.glyph = [LQSTheme onSurface];
    _back.tintColor = [LQSTheme onSurface];
    _selShape.strokeColor = [LQSTheme primary].CGColor;
    _handle.backgroundColor = [LQSTheme primary];
    _placeholder.backgroundColor = [[LQSTheme secondary] colorWithAlphaComponent:0.3]; // PLACEHOLDER_ALPHA
    _reset.backgroundColor = [LQSTheme primary];
    UIButtonConfiguration *rc = _reset.configuration;
    rc.attributedTitle = [[NSAttributedString alloc] initWithString:LQSL(@"Reset") attributes:@{NSFontAttributeName: [LQSTheme sansWithSize:14 weight:500], NSForegroundColorAttributeName: [LQSTheme onPrimary]}];
    _reset.configuration = rc;
    [self updateRemoveButton];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previous { [super traitCollectionDidChange:previous]; [self applyColors]; [self rebuildAvailable]; }

#pragma mark - Data

- (void)reload {
    _entries = [[NSMutableArray alloc] initWithArray:[LQSModel shared].layout copyItems:YES];
    [self rebuildCurrentTiles];
    [self rebuildAvailable];
    if (!_selected && _entries.count) _selected = _entries.firstObject.identifier; // auto-select the first tile
    [self setNeedsLayout];
}

- (LQSTileView *)makeTile:(LQSTileEntry *)e {
    LQSTileSpec *spec = [[LQSModel shared] specForIdentifier:e.identifier];
    LQSTileView *t = [[LQSTileView alloc] initWithSpec:spec size:e.size];
    t.on = NO;           // edit tiles use the inactive colours (editTileColors)
    t.stateText = @"";   // labels only
    t.iconOverride = spec.iconOn; // the tile's default icon, not its live state
    t.userInteractionEnabled = NO;
    return t;
}

- (void)rebuildCurrentTiles {
    NSMutableSet *keep = [NSMutableSet set];
    for (LQSTileEntry *e in _entries) {
        [keep addObject:e.identifier];
        LQSTileView *t = _tiles[e.identifier];
        if (!t) {
            t = [self makeTile:e];
            _tiles[e.identifier] = t;
            [_grid insertSubview:t belowSubview:_placeholder];
            t.alpha = 0;
            [UIView animateWithDuration:0.2 animations:^{ t.alpha = 1; }];
        }
        t.size = e.size;
    }
    for (NSString *k in _tiles.allKeys) if (![keep containsObject:k] && _tiles[k] != _dragView) { [_tiles[k] removeFromSuperview]; [_tiles removeObjectForKey:k]; }
    if (_selected && ![keep containsObject:_selected]) _selected = nil;
}

- (void)rebuildAvailable {
    for (UIView *g in _groups) [g removeFromSuperview];
    [_groups removeAllObjects];
    [_cells removeAllObjects];
    NSMutableDictionary<NSString *, NSMutableArray<LQSTileSpec *> *> *byCat = [NSMutableDictionary dictionary];
    for (LQSTileSpec *s in [LQSModel shared].catalog) {
        NSString *c = LQSTileCategory(s.identifier);
        if (!byCat[c]) byCat[c] = [NSMutableArray array];
        [byCat[c] addObject:s];
    }
    NSDictionary *icons = @{@"connectivity": @"ic_qs_category_connectivty", @"utilities": @"ic_qs_category_utilities", @"display": @"ic_qs_category_display",
                            @"privacy": @"ic_qs_category_privacy", @"accessibility": @"ic_qs_category_accessibility"};
    for (NSString *cat in LQSTileCategories()) {
        NSArray *specs = [byCat[cat] sortedArrayUsingComparator:^NSComparisonResult(LQSTileSpec *a, LQSTileSpec *b) { return [a.title localizedCaseInsensitiveCompare:b.title]; }];
        if (!specs.count) continue;
        UIView *g = [UIView new];
        g.backgroundColor = [[LQSTheme surface] colorWithAlphaComponent:0.32]; // AVAILABLE_TILES_GRID_ALPHA
        UIImageView *icon = [[UIImageView alloc] initWithImage:[LQSVectorIcon imageNamed:icons[cat] side:24]];
        icon.tintColor = [LQSTheme onSurface];
        icon.tag = 1;
        [g addSubview:icon];
        UILabel *h = [UILabel new];
        h.text = LQSL([@"qs_edit_mode_category_" stringByAppendingString:cat]);
        h.font = [LQSTheme sansWithSize:16 weight:600]; // titleMediumEmphasized 16/24
        h.textColor = [LQSTheme onSurface];
        h.tag = 2;
        [g addSubview:h];
        for (LQSTileSpec *s in specs) {
            UIView *cell = [self availableCell:s];
            [g addSubview:cell];
            _cells[s.identifier] = cell;
        }
        [_scroll insertSubview:g belowSubview:_grid];
        [_groups addObject:g];
    }
    [self updateAvailableStates];
    [self setNeedsLayout];
}

// AvailableTileGridCell: 72dp capsule with the 32dp icon, label below (labelMedium,
// 2 lines, centred), "+" badge (24dp primary circle, -4/+4 from the top-right corner).
- (UIView *)availableCell:(LQSTileSpec *)s {
    UIControl *c = [UIControl new];
    c.accessibilityIdentifier = s.identifier;
    UIView *bg = [UIView new];
    bg.tag = 1;
    bg.backgroundColor = [LQSTheme surfaceEffect1];
    bg.userInteractionEnabled = NO;
    [c addSubview:bg];
    UIImageView *iv = [[UIImageView alloc] initWithImage:[LQSVectorIcon imageNamed:s.iconOn side:32]];
    iv.tag = 2;
    iv.tintColor = [LQSTheme onSurface];
    iv.contentMode = UIViewContentModeCenter;
    [c addSubview:iv];
    UILabel *l = [UILabel new];
    l.tag = 3;
    l.text = s.title;
    l.numberOfLines = 2;
    l.textAlignment = NSTextAlignmentCenter;
    l.font = [LQSTheme tileSecondaryFont];
    l.textColor = [LQSTheme onSurface];
    [c addSubview:l];
    UIView *badge = [UIView new];
    badge.tag = 4;
    badge.backgroundColor = [LQSTheme primary];
    badge.layer.cornerRadius = 12;
    badge.userInteractionEnabled = NO;
    UIImageView *plus = [[UIImageView alloc] initWithImage:[LQSVectorIcon imageNamed:@"ic_add" side:16]];
    plus.tintColor = [LQSTheme onPrimary];
    plus.frame = CGRectMake(4, 4, 16, 16);
    [badge addSubview:plus];
    [c addSubview:badge];
    [c addTarget:self action:@selector(availableTapped:) forControlEvents:UIControlEventTouchUpInside];
    c.isAccessibilityElement = YES;
    c.accessibilityLabel = s.title;
    c.accessibilityTraits = UIAccessibilityTraitButton;
    return c;
}

- (void)updateAvailableStates {
    NSMutableSet *current = [NSMutableSet set];
    for (LQSTileEntry *e in _entries) [current addObject:e.identifier];
    for (NSString *k in _cells) {
        UIControl *c = (UIControl *)_cells[k];
        BOOL added = [current containsObject:k];
        c.enabled = !added;
        [UIView animateWithDuration:0.2 animations:^{
            c.alpha = added ? 0.38 : 1;
            [c viewWithTag:4].alpha = added ? 0 : 1;
        }];
        c.accessibilityValue = added ? LQSL(@"tile_already_added") : nil;
    }
}

#pragma mark - Layout

- (CGFloat)cellWidth { return (self.bounds.size.width - 2 * kSide - 2 * kGridPad - (kColumns - 1) * kGap) / kColumns; }

typedef struct { NSInteger row, col, span; } LQSEditCell;

- (NSArray<NSValue *> *)cellsFor:(NSArray<LQSTileEntry *> *)entries rows:(NSInteger *)rowsOut {
    NSMutableArray *out = [NSMutableArray array];
    NSInteger row = 0, col = 0;
    for (LQSTileEntry *e in entries) {
        NSInteger span = LQSTileSpan(e.size);
        if (col + span > kColumns) { row++; col = 0; }
        LQSEditCell c = {row, col, span};
        [out addObject:[NSValue valueWithBytes:&c objCType:@encode(LQSEditCell)]];
        col += span;
    }
    if (rowsOut) *rowsOut = entries.count ? row + 1 : 1;
    return out;
}

- (CGRect)frameForCell:(LQSEditCell)c {
    CGFloat cw = [self cellWidth];
    return CGRectMake(kGridPad + c.col * (cw + kGap), kGridPad + c.row * (kTileH + kGap), c.span * cw + (c.span - 1) * kGap, kTileH);
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.bounds.size.width;
    _scroll.frame = self.bounds;
    CGFloat y = self.topInset;
    // TwoRowsTopAppBar: navigation + actions row, then title / subtitle (vertical padding 8dp).
    y += 8;
    _back.frame = CGRectMake(kSide - 8, y, 48, 48);
    CGSize rs = [_remove sizeThatFits:CGSizeMake(200, 40)];
    CGFloat removeW = rs.width + 20; // padding 10dp
    _remove.frame = CGRectMake(w - kSide - removeW, y + 4, removeW, 40);
    _remove.layer.cornerRadius = 20;
    _undo.frame = CGRectMake(CGRectGetMinX(_remove.frame) - 8 - 40, y + 4, 40, 40);
    y += 48 + 4;
    CGSize ts = [_title sizeThatFits:CGSizeMake(w - 2 * kSide, 100)];
    _title.frame = CGRectMake(kSide, y, w - 2 * kSide, ts.height);
    y = CGRectGetMaxY(_title.frame) + 4;
    CGSize ss = [_subtitle sizeThatFits:CGSizeMake(w - 2 * kSide, 100)];
    _subtitle.frame = CGRectMake(kSide, y, w - 2 * kSide, ss.height);
    y = CGRectGetMaxY(_subtitle.frame) + 8 + 16; // app bar padding + Spacer(16dp)

    NSInteger rows = 1;
    NSArray *cells = [self cellsFor:_entries rows:&rows];
    CGFloat gridH = rows * kTileH + (rows - 1) * kGap + 2 * kGridPad;
    _grid.frame = CGRectMake(kSide, y, w - 2 * kSide, gridH);
    _gridBorder.frame = _grid.bounds;
    _gridBorder.path = [UIBezierPath bezierPathWithRoundedRect:CGRectInset(_grid.bounds, 1, 1) cornerRadius:27].CGPath;
    [self layoutTiles:cells];
    y = CGRectGetMaxY(_grid.frame) + kColumnGap;

    // Available tiles: groups (2dp apart, outer corners 28dp), then Reset.
    CGFloat aw = w - 2 * kSide, acw = (aw - 2 * kGroupPad - (kColumns - 1) * kGap) / kColumns;
    for (NSUInteger gi = 0; gi < _groups.count; gi++) {
        UIView *g = _groups[gi];
        CGFloat gy = kGroupPad;
        UIView *icon = [g viewWithTag:1], *h = [g viewWithTag:2];
        icon.frame = CGRectMake(kGroupPad, gy, 24, 24);
        h.frame = CGRectMake(kGroupPad + 24 + 8, gy, aw - 2 * kGroupPad - 32, 24);
        gy += 24 + 16;
        NSInteger i = 0;
        CGFloat rowMax = 0;
        for (UIView *c in g.subviews) {
            if (c.tag == 1 || c.tag == 2) continue;
            NSInteger col = i % kColumns;
            if (col == 0 && i > 0) { gy += rowMax + kGap; rowMax = 0; }
            UILabel *l = (UILabel *)[c viewWithTag:3];
            CGSize ls = [l sizeThatFits:CGSizeMake(acw, 40)];
            CGFloat ch = kTileH + 8 + MIN(32, ceil(ls.height));
            c.frame = CGRectMake(kGroupPad + col * (acw + kGap), gy, acw, ch);
            UIView *bg = [c viewWithTag:1];
            bg.frame = CGRectMake(0, 0, acw, kTileH);
            bg.layer.cornerRadius = MIN(36, acw / 2);
            [c viewWithTag:2].frame = bg.frame;
            l.frame = CGRectMake(0, kTileH + 8, acw, ch - kTileH - 8);
            UIView *badge = [c viewWithTag:4];
            badge.frame = CGRectMake(acw - 24 + 4, -4, 24, 24);
            badge.transform = CGAffineTransformIdentity;
            rowMax = MAX(rowMax, ch);
            i++;
        }
        gy += rowMax + kGroupPad;
        g.frame = CGRectMake(kSide, y, aw, gy);
        CACornerMask mask = 0;
        if (gi == 0) mask |= kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner;
        if (gi == _groups.count - 1) mask |= kCALayerMinXMaxYCorner | kCALayerMaxXMaxYCorner;
        g.layer.cornerRadius = mask ? 28 : 0;
        g.layer.maskedCorners = mask;
        y += gy + 2;
    }
    y += kColumnGap - 2;
    CGSize resetS = [_reset sizeThatFits:CGSizeMake(200, 40)];
    _reset.frame = CGRectMake(w - kSide - resetS.width, y, resetS.width, 40);
    _reset.layer.cornerRadius = 20;
    y += 40 + 16 + 24;
    _scroll.contentSize = CGSizeMake(w, y);
}

- (void)layoutTiles:(NSArray<NSValue *> *)cells {
    for (NSUInteger i = 0; i < _entries.count && i < cells.count; i++) {
        LQSEditCell c; [cells[i] getValue:&c];
        CGRect f = [self frameForCell:c];
        NSString *k = _entries[i].identifier;
        if ([k isEqualToString:_dragSpec]) { _placeholder.frame = f; _placeholder.layer.cornerRadius = MIN(36, f.size.width / 2); _placeholder.hidden = _dragOutside; continue; }
        _tiles[k].frame = f;
    }
    if (!_dragSpec) _placeholder.hidden = YES;
    [self layoutSelection];
}

- (void)layoutSelection {
    LQSTileView *t = _selected && !_dragSpec ? _tiles[_selected] : nil;
    if (!t) { [_selBorder removeFromSuperview]; [_handle removeFromSuperview]; return; }
    if (_selBorder.superview != _grid) [_grid addSubview:_selBorder];
    if (_handle.superview != _grid) [_grid addSubview:_handle];
    [_grid bringSubviewToFront:t];
    [_grid bringSubviewToFront:_selBorder];
    [_grid bringSubviewToFront:_handle];
    _selBorder.frame = t.frame;
    _selShape.frame = _selBorder.bounds;
    _selShape.path = [UIBezierPath bezierPathWithRoundedRect:CGRectInset(_selBorder.bounds, 1, 1) cornerRadius:MIN(35, t.bounds.size.width / 2 - 1)].CGPath;
    // Resize handle: 8x16dp pill at the end edge, offset -2dp (Selection.kt:463-509).
    _handle.frame = CGRectMake(CGRectGetMaxX(t.frame) - 4 - 2, CGRectGetMidY(t.frame) - 8, 8, 16);
}

#pragma mark - Actions

- (void)snapshot {
    [_undoStack addObject:[[NSArray alloc] initWithArray:_entries copyItems:YES]];
    while (_undoStack.count > kUndoMax) [_undoStack removeObjectAtIndex:0];
    [self updateUndo];
}
- (void)updateUndo { [UIView animateWithDuration:0.2 animations:^{ self->_undo.alpha = self->_undoStack.count ? 1 : 0; }]; _undo.userInteractionEnabled = _undoStack.count > 0; }

- (void)commit {
    [[LQSModel shared] setLayout:_entries];
    [self rebuildCurrentTiles];
    [self updateAvailableStates];
    [self updateRemoveButton];
    UIViewPropertyAnimator *a = PlacementSpring();
    [a addAnimations:^{ [self setNeedsLayout]; [self layoutIfNeeded]; }];
    [a startAnimation];
}

- (BOOL)canRemove { return _selected && _entries.count > LQSMinimumTiles; }

- (void)updateRemoveButton {
    BOOL on = [self canRemove];
    _remove.enabled = on;
    [UIView animateWithDuration:0.3 animations:^{
        self->_remove.backgroundColor = on ? [LQSTheme primary] : [[LQSTheme onSurface] colorWithAlphaComponent:0.1];
    }];
    [_remove setTitleColor:on ? [LQSTheme onPrimary] : [[LQSTheme onSurface] colorWithAlphaComponent:0.38] forState:UIControlStateNormal];
    [_remove setTitleColor:[[LQSTheme onSurface] colorWithAlphaComponent:0.38] forState:UIControlStateDisabled];
}

- (NSUInteger)indexOf:(NSString *)spec {
    for (NSUInteger i = 0; i < _entries.count; i++) if ([_entries[i].identifier isEqualToString:spec]) return i;
    return NSNotFound;
}

- (void)select:(NSString *)spec {
    _selected = spec;
    [self updateRemoveButton];
    UIViewPropertyAnimator *a = DefaultSpring();
    [a addAnimations:^{ [self layoutSelection]; }];
    [a startAnimation];
}

- (void)backTapped { LQSHapticTick(); if (self.onExit) self.onExit(); }

- (void)undoTapped {
    if (!_undoStack.count) return;
    LQSHapticTick();
    _entries = [_undoStack.lastObject mutableCopy];
    [_undoStack removeLastObject];
    [self updateUndo];
    [self commit];
}

- (void)removeTapped {
    if (![self canRemove]) return;
    LQSHapticTick();
    NSUInteger i = [self indexOf:_selected];
    if (i == NSNotFound) return;
    [self snapshot];
    // findNeighboringTile: next one, or the previous when removing the last.
    NSString *next = i + 1 < _entries.count ? _entries[i + 1].identifier : (i > 0 ? _entries[i - 1].identifier : nil);
    LQSTileView *t = _tiles[_selected];
    [_entries removeObjectAtIndex:i];
    [_tiles removeObjectForKey:_selected];
    [UIView animateWithDuration:0.2 animations:^{ t.alpha = 0; t.transform = CGAffineTransformMakeScale(0.8, 0.8); } completion:^(BOOL f) { [t removeFromSuperview]; }];
    _selected = next;
    [self commit];
}

- (void)resetTapped {
    LQSHapticTick();
    __weak typeof(self) weakSelf = self;
    [LQSDialog showIn:self.window ?: self title:LQSL(@"qs_edit_mode_reset_dialog_title") message:LQSL(@"qs_edit_mode_reset_dialog_content")
                   ok:LQSL(@"OK") cancel:LQSL(@"Cancel") onOK:^{
        typeof(self) s = weakSelf;
        [s->_undoStack removeAllObjects]; // reset clears the undo stack
        [s updateUndo];
        [[LQSModel shared] resetLayout];
        s->_entries = [[NSMutableArray alloc] initWithArray:[LQSModel shared].layout copyItems:YES];
        s->_selected = s->_entries.firstObject.identifier;
        [s commit];
        [s->_scroll setContentOffset:CGPointZero animated:YES];
    }];
}

- (void)availableTapped:(UIControl *)c {
    NSString *spec = c.accessibilityIdentifier;
    if ([self indexOf:spec] != NSNotFound) return;
    LQSHapticTick();
    [self snapshot];
    LQSTileEntry *e = [LQSTileEntry new];
    e.identifier = spec;
    e.size = LQSTileSizeSmall;
    [_entries addObject:e]; // POSITION_AT_END
    _selected = spec;
    [self commit];
}

- (NSString *)specAt:(CGPoint)p {
    for (LQSTileEntry *e in _entries) {
        LQSTileView *t = _tiles[e.identifier];
        if (t && t != _dragView && CGRectContainsPoint(t.frame, p)) return e.identifier;
    }
    return nil;
}

- (void)gridTapped:(UITapGestureRecognizer *)g {
    NSString *spec = [self specAt:[g locationInView:_grid]];
    if (!spec || [spec isEqualToString:_selected]) return;
    LQSHapticTick();
    [self select:spec];
}

- (void)toggleSize:(NSString *)spec {
    NSUInteger i = [self indexOf:spec];
    if (i == NSNotFound) return;
    LQSHapticTick();
    [self snapshot];
    LQSTileEntry *e = _entries[i];
    e.size = e.size == LQSTileSizeLarge ? LQSTileSizeSmall : LQSTileSizeLarge;
    _tiles[spec].size = e.size;
    [self commit];
}

- (void)handleTapped { if (_selected) [self toggleSize:_selected]; }

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)g {
    if ([g isKindOfClass:UIPanGestureRecognizer.class] && g.view == _handle) {
        CGPoint v = [(UIPanGestureRecognizer *)g velocityInView:self];
        return fabs(v.x) > fabs(v.y);
    }
    return YES;
}

// Resize by dragging the handle: anchors Icon / Large; settle on the nearer one.
- (void)handlePan:(UIPanGestureRecognizer *)g {
    if (!_selected) return;
    NSUInteger i = [self indexOf:_selected];
    if (i == NSNotFound) return;
    LQSTileEntry *e = _entries[i];
    CGFloat dx = [g translationInView:_grid].x, cw = [self cellWidth];
    LQSTileView *t = _tiles[_selected];
    CGFloat minW = cw, maxW = 2 * cw + kGap;
    if (g.state == UIGestureRecognizerStateBegan) _handleStartX = t.bounds.size.width;
    if (g.state == UIGestureRecognizerStateChanged) {
        CGRect f = t.frame;
        f.size.width = MAX(minW, MIN(maxW, _handleStartX + dx));
        t.frame = f;
        [self layoutSelection];
    } else if (g.state == UIGestureRecognizerStateEnded || g.state == UIGestureRecognizerStateCancelled) {
        BOOL large = t.bounds.size.width > (minW + maxW) / 2 + [g velocityInView:_grid].x * 0.05;
        if (large != (e.size == LQSTileSizeLarge)) [self toggleSize:_selected];
        else { UIViewPropertyAnimator *a = DefaultSpring(); [a addAnimations:^{ [self setNeedsLayout]; [self layoutIfNeeded]; }]; [a startAnimation]; }
    }
}

// Drag and drop (detectDragGesturesAfterLongPress): live reorder; leaving the grid
// removes a removable tile, dropping there confirms the removal.
- (void)gridLongPress:(UILongPressGestureRecognizer *)g {
    CGPoint p = [g locationInView:_grid];
    switch (g.state) {
        case UIGestureRecognizerStateBegan: {
            NSString *spec = [self specAt:p];
            if (!spec) return;
            LQSHapticTick();
            _dragSpec = spec;
            _dragView = _tiles[spec];
            _dragStartEntries = [[NSArray alloc] initWithArray:_entries copyItems:YES];
            _dragOffset = CGPointMake(p.x - _dragView.center.x, p.y - _dragView.center.y);
            _dragOutside = NO;
            _selected = spec;
            [self updateRemoveButton];
            [self addSubview:_dragView]; // float above the scroll view
            _dragView.center = [_grid convertPoint:CGPointMake(p.x - _dragOffset.x, p.y - _dragOffset.y) toView:self];
            [UIView animateWithDuration:0.15 animations:^{ self->_dragView.transform = CGAffineTransformMakeScale(1.04, 1.04); }];
            [self setNeedsLayout];
            [self layoutIfNeeded];
            break;
        }
        case UIGestureRecognizerStateChanged: {
            if (!_dragSpec) return;
            _dragView.center = [_grid convertPoint:CGPointMake(p.x - _dragOffset.x, p.y - _dragOffset.y) toView:self];
            BOOL outside = !CGRectContainsPoint(CGRectInset(_grid.bounds, -8, -8), p);
            BOOL removable = _dragStartEntries.count > LQSMinimumTiles;
            if (outside && removable) {
                if (!_dragOutside) {
                    _dragOutside = YES;
                    NSUInteger i = [self indexOf:_dragSpec];
                    if (i != NSNotFound) [_entries removeObjectAtIndex:i];
                    [self animateLayout];
                }
                break;
            }
            if (_dragOutside) {
                _dragOutside = NO;
                LQSTileEntry *e = nil;
                for (LQSTileEntry *x in _dragStartEntries) if ([x.identifier isEqualToString:_dragSpec]) e = [x copy];
                if (e) [_entries addObject:e];
            }
            NSString *target = [self specAt:p];
            if (target && ![target isEqualToString:_dragSpec]) {
                NSUInteger from = [self indexOf:_dragSpec], to = [self indexOf:target];
                LQSTileView *tv = _tiles[target];
                // insertAfter when hovering the right half of a large target (DragAndDropState.kt:178-183).
                (void)tv;
                if (from != NSNotFound && to != NSNotFound && from != to) {
                    LQSTileEntry *e = _entries[from];
                    [_entries removeObjectAtIndex:from];
                    [_entries insertObject:e atIndex:to];
                    [self animateLayout];
                }
            }
            [self autoScroll:g];
            break;
        }
        default: {
            if (!_dragSpec) return;
            NSString *spec = _dragSpec;
            LQSTileView *v = _dragView;
            BOOL removed = _dragOutside;
            _dragSpec = nil;
            _dragView = nil;
            _dragOutside = NO;
            [_undoStack addObject:_dragStartEntries];
            while (_undoStack.count > kUndoMax) [_undoStack removeObjectAtIndex:0];
            [self updateUndo];
            if (removed) {
                [_tiles removeObjectForKey:spec];
                [UIView animateWithDuration:0.2 animations:^{ v.alpha = 0; v.transform = CGAffineTransformMakeScale(0.8, 0.8); } completion:^(BOOL f) { [v removeFromSuperview]; }];
                _selected = _entries.firstObject.identifier;
                LQSHapticTick();
            } else {
                CGRect inGrid = [self convertRect:v.frame toView:_grid];
                [_grid insertSubview:v belowSubview:_placeholder];
                v.transform = CGAffineTransformIdentity;
                v.frame = inGrid;
            }
            [self commit];
            break;
        }
    }
}

- (void)animateLayout {
    UIViewPropertyAnimator *a = PlacementSpring();
    [a addAnimations:^{ [self setNeedsLayout]; [self layoutIfNeeded]; }];
    [a startAnimation];
}

// AUTO_SCROLL_DISTANCE 100px from the visible edges, 2 ms per px.
- (void)autoScroll:(UILongPressGestureRecognizer *)g {
    CGFloat y = [g locationInView:self].y, h = self.bounds.size.height, edge = 50;
    CGFloat maxOff = MAX(0, _scroll.contentSize.height - h);
    CGFloat off = _scroll.contentOffset.y;
    if (y < self.topInset + edge && off > 0) off = MAX(0, off - 6);
    else if (y > h - edge && off < maxOff) off = MIN(maxOff, off + 6);
    else return;
    _scroll.contentOffset = CGPointMake(0, off);
}

@end
